/**
 * NbaActionStateService — Audit record writer + cache invalidation for NBA V2.
 *
 * Phase 5 pivot: In the on-demand model, most actions exist only in memory
 * (evaluated on request, cached in Platform Cache). NBA_Queue__c records are
 * written only as audit records when the AE interacts (complete/snooze/dismiss),
 * or by triggers for Layer 1 time-bound actions.
 *
 * Responsibilities:
 * - Write audit NBA_Queue__c records on AE interaction
 * - Update persisted Layer 1 records when completed/snoozed/dismissed
 * - Expire stale Layer 1 time-bound records
 * - Invalidate Platform Cache after state changes
 *
 * Called by NbaActionController and NbaActionExpirationSchedulable.
 */
public with sharing class NbaActionStateService {

    // Expiration threshold for Layer 1 time-bound actions (configurable for testing)
    @TestVisible
    private static Integer TIMEBOUND_EXPIRE_MINUTES = 15;

    // Default cooldown after completing an action (minutes)
    private static final Integer DEFAULT_COOLDOWN_MINUTES = 60;

    // ─── AE-Invoked: Complete ──────────────────────────────────────

    /**
     * Complete an action. If persisted (Layer 1), updates the DB record.
     * Always writes an audit record and invalidates cache.
     *
     * @param actionId NBA_Queue__c ID (null for on-demand actions)
     * @param opportunityId Opportunity the action was for
     * @param accountId Account the action was for
     * @param actionType Action type string (e.g., 'First Touch', 'Re-engage')
     * @param actionInstruction The instruction text shown to the AE
     * @param stepOutcome Cadence step outcome (Connected, VM, No_Answer, Sent, etc.)
     */
    public static void completeAction(
        Id actionId, Id opportunityId, Id accountId, String actionType,
        String actionInstruction, String stepOutcome
    ) {
        Id userId = UserInfo.getUserId();

        // If Layer 1 persisted action, update the existing DB record
        if (actionId != null) {
            updatePersistedAction(actionId, 'Completed');
        }

        // Write audit record
        writeAuditRecord(opportunityId, accountId, userId, actionType, actionInstruction,
            'Completed', null, null, null, null, stepOutcome);

        // Invalidate cache so next getActiveAction() re-evaluates
        NbaCacheService.invalidate(userId);
    }

    // ─── AE-Invoked: Snooze ───────────────────────────────────────

    /**
     * Snooze an action. Writes audit record with Snoozed_Until__c so the
     * on-demand evaluator will suppress this opp until the snooze expires.
     *
     * @param actionId NBA_Queue__c ID (null for on-demand actions)
     * @param opportunityId Opportunity the action was for
     * @param accountId Account the action was for
     * @param actionType Action type string
     * @param actionInstruction The instruction text shown to the AE
     * @param reason The snooze reason text
     * @param durationMinutes Duration in minutes before re-entry
     */
    public static void snoozeAction(
        Id actionId, Id opportunityId, Id accountId, String actionType,
        String actionInstruction, String reason, Integer durationMinutes
    ) {
        Id userId = UserInfo.getUserId();

        // If Layer 1 persisted action, update the existing DB record
        if (actionId != null) {
            updatePersistedAction(actionId, 'Snoozed');
        }

        Datetime snoozedUntil = Datetime.now().addMinutes(durationMinutes);

        // Write audit record with snooze fields
        writeAuditRecord(opportunityId, accountId, userId, actionType, actionInstruction,
            'Snoozed', reason, null, snoozedUntil, null, null);

        NbaCacheService.invalidate(userId);
    }

    // ─── AE-Invoked: Dismiss ──────────────────────────────────────

    /**
     * Dismiss an action. Writes audit record with dismiss reason and category.
     *
     * @param actionId NBA_Queue__c ID (null for on-demand actions)
     * @param opportunityId Opportunity the action was for
     * @param accountId Account the action was for
     * @param actionType Action type string
     * @param actionInstruction The instruction text shown to the AE
     * @param reason The dismiss reason text
     * @param category The dismiss category (restricted picklist)
     */
    public static void dismissAction(
        Id actionId, Id opportunityId, Id accountId, String actionType,
        String actionInstruction, String reason, String category
    ) {
        Id userId = UserInfo.getUserId();

        // If Layer 1 persisted action, update the existing DB record
        if (actionId != null) {
            updatePersistedAction(actionId, 'Dismissed');
        }

        // Write audit record with dismiss fields
        writeAuditRecord(opportunityId, accountId, userId, actionType, actionInstruction,
            'Dismissed', reason, category, null, null, null);

        NbaCacheService.invalidate(userId);
    }

    // ─── System-Invoked: Expire Stale Layer 1 Actions ─────────────

    /**
     * Expire stale Layer 1 time-bound actions that have passed their DueAt
     * plus the expiration threshold (default 15 minutes).
     *
     * In Phase 5, only Layer 1 (time-bound) actions are persisted in DB,
     * so this only processes Is_Time_Bound__c = true records.
     *
     * @return Count of expired records
     */
    public static Integer expireStaleActions() {
        Datetime timeboundCutoff = Datetime.now().addMinutes(-TIMEBOUND_EXPIRE_MINUTES);
        List<NBA_Queue__c> toExpire = [
            SELECT Id, Status__c, Sales_Rep__c
            FROM NBA_Queue__c
            WHERE Is_Time_Bound__c = true
              AND Status__c IN ('New', 'Pending', 'In Progress', 'Accepted')
              AND DueAt__c != null
              AND DueAt__c < :timeboundCutoff
            WITH SECURITY_ENFORCED
            LIMIT 200
        ];

        if (toExpire.isEmpty()) {
            return 0;
        }

        // Collect AE IDs for cache invalidation
        Set<Id> affectedAeIds = new Set<Id>();
        for (NBA_Queue__c a : toExpire) {
            a.Status__c = 'Expired';
            a.UniqueKey__c = null;
            if (a.Sales_Rep__c != null) {
                affectedAeIds.add(a.Sales_Rep__c);
            }
        }
        update toExpire;

        // Invalidate cache for affected AEs so they get fresh evaluation
        NbaCacheService.invalidateForUsers(affectedAeIds);

        return toExpire.size();
    }

    // ─── Audit Record Writer ──────────────────────────────────────

    /**
     * Write an NBA_Queue__c audit record capturing the AE's interaction.
     * These records serve as the historical log for analytics, cooldown
     * enforcement, and snooze suppression in the on-demand model.
     */
    @TestVisible
    private static NBA_Queue__c writeAuditRecord(
        Id opportunityId, Id accountId, Id userId, String actionType,
        String actionInstruction, String status, String reason,
        String dismissCategory, Datetime snoozedUntil, Datetime cooldownUntil,
        String stepOutcome
    ) {
        // Determine cooldown: use provided value or default for complete/dismiss
        if (cooldownUntil == null && (status == 'Completed' || status == 'Dismissed')) {
            cooldownUntil = Datetime.now().addMinutes(DEFAULT_COOLDOWN_MINUTES);
        }

        NBA_Queue__c audit = new NBA_Queue__c(
            Opportunity__c = opportunityId,
            Account__c = accountId,
            Sales_Rep__c = userId,
            Status__c = status,
            Action_Type__c = actionType,
            Action_Instruction__c = actionInstruction != null ? actionInstruction.left(255) : null,
            Source_Path__c = 'Pipeline Cadence',
            Workflow_Mode__c = 'Pipeline',
            LastEvaluatedAt__c = Datetime.now(),
            Actioned_Date__c = Datetime.now()
        );

        // Status-specific fields
        if (status == 'Completed') {
            audit.Completed_Date__c = Datetime.now();
        }
        if (String.isNotBlank(reason)) {
            audit.Dismissed_Reason__c = reason;
        }
        if (String.isNotBlank(dismissCategory)) {
            audit.Dismissal_Category__c = dismissCategory;
        }
        if (snoozedUntil != null) {
            audit.Snoozed_Until__c = snoozedUntil;
        }
        if (cooldownUntil != null) {
            audit.CooldownUntil__c = cooldownUntil;
        }

        // Phase 7: Write cadence progress from lastEvaluatedResults
        if (opportunityId != null
            && NbaCadenceService.lastEvaluatedResults.containsKey(opportunityId)) {
            NbaCadenceService.CadenceResult cadResult =
                NbaCadenceService.lastEvaluatedResults.get(opportunityId);
            audit.Cadence_Name__c = cadResult.cadenceName;
            if (cadResult.currentStep != null) {
                audit.Cadence_Step_Number__c = cadResult.currentStep.stepNumber;
                audit.Step_Method__c = cadResult.currentStep.method;
                audit.Cadence_Stage__c = cadResult.currentStep.stepNumber;
            }
        }

        // Write step outcome from AE interaction
        if (String.isNotBlank(stepOutcome)) {
            audit.Step_Outcome__c = stepOutcome;
        }

        insert audit;
        return audit;
    }

    // ─── Private Helpers ──────────────────────────────────────────

    /**
     * Update a persisted (Layer 1) NBA_Queue__c record to a terminal status.
     * Used when completing/snoozing/dismissing a time-bound action that
     * exists in the database.
     */
    private static void updatePersistedAction(Id actionId, String newStatus) {
        List<NBA_Queue__c> actions = [
            SELECT Id, Status__c, UniqueKey__c
            FROM NBA_Queue__c
            WHERE Id = :actionId
              AND Status__c IN ('New', 'Pending', 'In Progress', 'Accepted')
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (actions.isEmpty()) {
            return; // Already transitioned — no error, just skip
        }

        NBA_Queue__c action = actions[0];
        action.Status__c = newStatus;
        action.UniqueKey__c = null;
        action.Actioned_Date__c = Datetime.now();
        if (newStatus == 'Completed') {
            action.Completed_Date__c = Datetime.now();
        }
        update action;
    }
}
