/**
 * NbaActionController — Two-stream entry point for the NBA V2 App Page LWC.
 *
 * Stream 1 (Scored Queue) — getActiveAction():
 *   1. Check Platform Cache — 0 SOQL
 *   2. Cache miss → full on-demand evaluation — ~12 SOQL
 *      a. Query AE's open Opps
 *      b. NbaSignalService.getSignals()
 *      c. NbaActionCreationService.evaluateAndCreate()
 *      d. NbaActionSelectionService.rankActions()
 *   3. Cache result → return ActionWrapper
 *
 * Stream 2 (Real-Time Interrupts) — checkInterrupts():
 *   Lightweight 15s poll returns Layer 1 interrupt actions:
 *   - Meetings due within 5 minutes (time-bound)
 *   - New-assignment records (L1, non-time-bound, created within 24h)
 *   AE can accept (Jump to it) or dismiss. Accepted interrupts set to
 *   'In Progress' so they stop appearing in the poll.
 *
 * complete/snooze/dismiss: delegate to NbaActionStateService (audit writer),
 * then re-evaluate and return the next action.
 */
public with sharing class NbaActionController {

    private static final Set<String> EXCLUDED_STAGES = new Set<String>{
        'Hand-Off', 'Closed Won', 'Closed Lost'
    };

    // ─── Get Active Action (On-Demand Evaluation) ───────────────────

    /**
     * Returns the current user's top-priority scored-queue action.
     * Stream 1 (Scored Queue): Platform Cache → full on-demand evaluation.
     * Layer 1 interrupts are handled separately by checkInterrupts().
     * @return ActionWrapper or null if no actions available
     */
    @AuraEnabled
    public static ActionWrapper getActiveAction() {
        Id userId = UserInfo.getUserId();

        // Step 1: Check Platform Cache
        ActionWrapper cached = NbaCacheService.getCachedAction(userId);
        if (cached != null) {
            return cached;
        }

        // Step 2: Cache miss — full on-demand evaluation
        ActionWrapper evaluated = evaluateOnDemand(userId);
        if (evaluated != null) {
            NbaCacheService.cacheAction(userId, evaluated);
        }

        return evaluated;
    }

    // ─── Check Interrupts (Lightweight, for 15s Polling) ────────────

    /**
     * Stream 2 (Real-Time Interrupts): Lightweight check for Layer 1 interrupt actions.
     * Returns meetings due within 5 minutes AND new-assignment interrupt records
     * (Priority_Layer='L1', Is_Time_Bound=false) created within 24h.
     * Used by the LWC's 15-second poll.
     * @return List of interrupt ActionWrappers (empty list if none)
     */
    @AuraEnabled
    public static List<ActionWrapper> checkInterrupts() {
        return checkInterruptsInternal(UserInfo.getUserId());
    }

    // ─── Accept Interrupt (AE clicks "Jump to it") ────────────────

    /**
     * Accept an interrupt action — sets Status to 'In Progress' so it stops
     * appearing in the 15s poll. Called when the AE clicks "Jump to it".
     * @param actionId The NBA_Queue__c ID of the interrupt action
     * @return ActionWrapper for the accepted interrupt
     */
    @AuraEnabled
    public static ActionWrapper acceptInterrupt(Id actionId) {
        if (actionId == null) {
            return null;
        }

        List<NBA_Queue__c> actions = [
            SELECT Id, Opportunity__c, Account__c, Action_Type__c,
                   Action_Instruction__c, ReasonText__c, Priority_Layer__c,
                   Priority_Bucket__c, Priority_Score__c, Is_Time_Bound__c,
                   DueAt__c, Status__c,
                   Account__r.Name, Opportunity__r.Name, Opportunity__r.StageName
            FROM NBA_Queue__c
            WHERE Id = :actionId
              AND Status__c IN ('New', 'Pending', 'Accepted')
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (actions.isEmpty()) {
            return null;
        }

        NBA_Queue__c action = actions[0];
        action.Status__c = 'In Progress';
        action.LastEvaluatedAt__c = Datetime.now();
        update action;

        return toWrapperFromRecord(action);
    }

    // ─── Action Lifecycle ───────────────────────────────────────────

    /**
     * Complete an action. Writes audit record, invalidates cache, re-evaluates.
     * @param actionId NBA_Queue__c ID (null for on-demand actions, real ID for Layer 1)
     * @param opportunityId The Opportunity the action was for
     * @param actionType The action type string
     * @return ActionResultWrapper with next action
     */
    @AuraEnabled
    public static ActionResultWrapper completeAction(
        Id actionId, Id opportunityId, String actionType, String stepOutcome
    ) {
        Id userId = UserInfo.getUserId();

        // Guard: if LWC sent null opportunityId, re-evaluate to get correct context
        if (opportunityId == null || String.isBlank(actionType)) {
            ActionWrapper current = evaluateOnDemand(userId);
            if (current != null) {
                opportunityId = opportunityId != null ? opportunityId : current.opportunityId;
                actionType = String.isNotBlank(actionType) ? actionType : current.actionType;
            }
        }

        // Look up account from Opportunity
        Id accountId = getAccountId(opportunityId);

        // Delegate to state service (writes audit + invalidates cache)
        NbaActionStateService.completeAction(
            actionId, opportunityId, accountId, actionType, null, stepOutcome
        );

        // Re-evaluate and return next action
        return buildResultFromEvaluation(userId);
    }

    /**
     * Snooze an action with a reason and duration.
     */
    @AuraEnabled
    public static ActionResultWrapper snoozeAction(
        Id actionId, Id opportunityId, String actionType,
        String reason, Integer durationMinutes
    ) {
        Id userId = UserInfo.getUserId();

        // Guard: if LWC sent null opportunityId, re-evaluate to get correct context
        if (opportunityId == null || String.isBlank(actionType)) {
            ActionWrapper current = evaluateOnDemand(userId);
            if (current != null) {
                opportunityId = opportunityId != null ? opportunityId : current.opportunityId;
                actionType = String.isNotBlank(actionType) ? actionType : current.actionType;
            }
        }

        Id accountId = getAccountId(opportunityId);

        NbaActionStateService.snoozeAction(
            actionId, opportunityId, accountId, actionType, null,
            reason, durationMinutes
        );

        return buildResultFromEvaluation(userId);
    }

    /**
     * Dismiss an action with a reason and category.
     */
    @AuraEnabled
    public static ActionResultWrapper dismissAction(
        Id actionId, Id opportunityId, String actionType,
        String reason, String category
    ) {
        Id userId = UserInfo.getUserId();

        // Guard: if LWC sent null opportunityId, re-evaluate to get correct context
        if (opportunityId == null || String.isBlank(actionType)) {
            ActionWrapper current = evaluateOnDemand(userId);
            if (current != null) {
                opportunityId = opportunityId != null ? opportunityId : current.opportunityId;
                actionType = String.isNotBlank(actionType) ? actionType : current.actionType;
            }
        }

        Id accountId = getAccountId(opportunityId);

        NbaActionStateService.dismissAction(
            actionId, opportunityId, accountId, actionType, null,
            reason, category
        );

        return buildResultFromEvaluation(userId);
    }

    // ─── On-Demand Evaluation Pipeline ──────────────────────────────

    /**
     * Full on-demand evaluation: query AE's Opps → signals → create → rank → return top.
     * ~12 SOQL queries (1 Opps + 7 signals + 3-4 CMDT via creation + 1 cooldown via selection).
     */
    private static ActionWrapper evaluateOnDemand(Id userId) {
        // Query AE's open Opportunities
        List<Opportunity> opps = [
            SELECT Id
            FROM Opportunity
            WHERE OwnerId = :userId
              AND IsClosed = false
              AND StageName NOT IN :EXCLUDED_STAGES
            WITH SECURITY_ENFORCED
            LIMIT 200
        ];

        if (opps.isEmpty()) {
            return null;
        }

        Set<Id> oppIds = new Set<Id>();
        for (Opportunity o : opps) {
            oppIds.add(o.Id);
        }

        // Get signals (7 SOQL)
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            NbaSignalService.getSignals(oppIds);

        if (signals.isEmpty()) {
            return null;
        }

        // Evaluate and create in-memory candidates (3-4 SOQL for CMDT)
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);

        if (result.actionsToCreate.isEmpty()) {
            return null;
        }

        // Rank candidates (1 SOQL for cooldown rules)
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(result.actionsToCreate);

        if (ranked.isEmpty()) {
            return null;
        }

        // Return the top-ranked candidate as an ActionWrapper
        return toWrapperFromCandidate(ranked[0].action);
    }

    // ─── Private Helpers ────────────────────────────────────────────

    /**
     * Check for Layer 1 interrupt actions in the DB.
     * Returns:
     *   - Meetings with DueAt within 5 minutes (not 24h)
     *   - New-assignment interrupts (L1, Is_Time_Bound=false) created within 24h
     * Excludes 'In Progress' records (already accepted by acceptInterrupt).
     */
    private static List<ActionWrapper> checkInterruptsInternal(Id userId) {
        List<ActionWrapper> interrupts = new List<ActionWrapper>();

        // Query 1: Time-bound meetings due within 5 minutes
        Datetime fiveMinFromNow = Datetime.now().addMinutes(5);
        List<NBA_Queue__c> meetings = [
            SELECT Id, Opportunity__c, Account__c, Action_Type__c,
                   Action_Instruction__c, ReasonText__c, Priority_Layer__c,
                   Priority_Bucket__c, Priority_Score__c, Is_Time_Bound__c,
                   DueAt__c, Status__c,
                   Account__r.Name, Opportunity__r.Name, Opportunity__r.StageName
            FROM NBA_Queue__c
            WHERE Sales_Rep__c = :userId
              AND Is_Time_Bound__c = true
              AND Status__c IN ('New', 'Pending', 'Accepted')
              AND DueAt__c != null
              AND DueAt__c <= :fiveMinFromNow
              AND DueAt__c >= :Datetime.now().addMinutes(-15)
            WITH SECURITY_ENFORCED
            ORDER BY DueAt__c ASC
            LIMIT 5
        ];
        for (NBA_Queue__c m : meetings) {
            interrupts.add(toWrapperFromRecord(m));
        }

        // Query 2: New-assignment interrupt records (L1, non-time-bound, within 24h)
        Datetime twentyFourHoursAgo = Datetime.now().addHours(-24);
        List<NBA_Queue__c> assignments = [
            SELECT Id, Opportunity__c, Account__c, Action_Type__c,
                   Action_Instruction__c, ReasonText__c, Priority_Layer__c,
                   Priority_Bucket__c, Priority_Score__c, Is_Time_Bound__c,
                   DueAt__c, Status__c,
                   Account__r.Name, Opportunity__r.Name, Opportunity__r.StageName
            FROM NBA_Queue__c
            WHERE Sales_Rep__c = :userId
              AND Priority_Layer__c = 'Layer 1 - Time Bound'
              AND Is_Time_Bound__c = false
              AND Status__c IN ('New', 'Pending', 'Accepted')
              AND CreatedDate >= :twentyFourHoursAgo
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 5
        ];
        for (NBA_Queue__c a : assignments) {
            interrupts.add(toWrapperFromRecord(a));
        }

        return interrupts;
    }

    /**
     * Build ActionResultWrapper by re-evaluating after an AE interaction.
     */
    private static ActionResultWrapper buildResultFromEvaluation(Id userId) {
        ActionResultWrapper result = new ActionResultWrapper();
        ActionWrapper next = getActiveAction();
        result.nextAction = next;
        result.hasNext = (next != null);
        return result;
    }

    /**
     * Convert a DB-queried NBA_Queue__c record to ActionWrapper.
     * Used for Layer 1 time-bound actions that live in the database.
     */
    private static ActionWrapper toWrapperFromRecord(NBA_Queue__c action) {
        ActionWrapper w = new ActionWrapper();
        w.actionId = action.Id;
        w.opportunityId = action.Opportunity__c;
        w.accountId = action.Account__c;
        w.actionType = action.Action_Type__c;
        w.actionInstruction = action.Action_Instruction__c;
        w.reasonText = action.ReasonText__c;
        w.priorityLayer = action.Priority_Layer__c;
        w.priorityBucket = action.Priority_Bucket__c;
        w.priorityScore = action.Priority_Score__c;
        w.isTimeBound = action.Is_Time_Bound__c;
        w.dueAt = action.DueAt__c;
        w.status = action.Status__c;
        w.accountName = action.Account__r?.Name;
        w.opportunityName = action.Opportunity__r?.Name;
        w.oppStage = action.Opportunity__r?.StageName;

        // Layer 1 time-bound actions are meetings, not cadence
        w.isCadenceAction = false;

        return w;
    }

    /**
     * Convert an in-memory NBA_Queue__c candidate to ActionWrapper.
     * Used for on-demand evaluated actions (not persisted to DB).
     * actionId is null since there's no DB record.
     */
    private static ActionWrapper toWrapperFromCandidate(NBA_Queue__c candidate) {
        ActionWrapper w = new ActionWrapper();
        w.actionId = null; // On-demand — no DB record
        w.opportunityId = candidate.Opportunity__c;
        w.accountId = candidate.Account__c;
        w.actionType = candidate.Action_Type__c;
        w.actionInstruction = candidate.Action_Instruction__c;
        w.reasonText = candidate.ReasonText__c;
        w.priorityLayer = candidate.Priority_Layer__c;
        w.priorityBucket = candidate.Priority_Bucket__c;
        w.priorityScore = candidate.Priority_Score__c;
        w.isTimeBound = candidate.Is_Time_Bound__c;
        w.dueAt = candidate.DueAt__c;
        w.status = 'Evaluated';

        // Relationship fields not available on in-memory record —
        // the LWC will get these from getPageData(oppId)
        w.accountName = null;
        w.opportunityName = null;
        w.oppStage = candidate.Opportunity_Stage__c;

        // Phase 7: Map cadence fields from CadenceResult (replaces Phase 6 CadenceStep)
        NbaCadenceService.CadenceResult cadResult =
            NbaCadenceService.lastEvaluatedResults.get(candidate.Opportunity__c);
        if (cadResult != null && cadResult.currentStep != null) {
            w.isCadenceAction = true;
            w.cadenceName = cadResult.cadenceName;
            w.cadenceStepNumber = cadResult.currentStep.stepNumber;
            w.cadenceTotalSteps = cadResult.context != null ? cadResult.context.totalSteps : null;
            w.stepMethod = cadResult.currentStep.method;
            w.stepInstruction = cadResult.currentStep.instructionText;
            w.cadenceProgress = cadResult.progressText;
            w.progressFraction = cadResult.progressFraction;
            w.upcomingSteps = cadResult.upcomingSteps;
        } else {
            w.isCadenceAction = false;
        }

        return w;
    }

    /**
     * Get the AccountId for an Opportunity (1 SOQL).
     */
    private static Id getAccountId(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }
        List<Opportunity> opps = [
            SELECT AccountId FROM Opportunity
            WHERE Id = :opportunityId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return opps.isEmpty() ? null : opps[0].AccountId;
    }

    // ─── Wrapper Classes ────────────────────────────────────────────

    public class ActionWrapper {
        @AuraEnabled public Id actionId;         // null for on-demand, real ID for Layer 1
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String actionType;
        @AuraEnabled public String actionInstruction;
        @AuraEnabled public String reasonText;
        @AuraEnabled public String priorityLayer;
        @AuraEnabled public String priorityBucket;
        @AuraEnabled public Decimal priorityScore;
        @AuraEnabled public Boolean isTimeBound;
        @AuraEnabled public Datetime dueAt;
        @AuraEnabled public String status;
        @AuraEnabled public String accountName;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String oppStage;
        // Phase 7: Cadence fields (replaces Phase 6)
        @AuraEnabled public String cadenceName;
        @AuraEnabled public Integer cadenceStepNumber;
        @AuraEnabled public Integer cadenceTotalSteps;
        @AuraEnabled public String stepMethod;        // Call, SMS, Email
        @AuraEnabled public String stepInstruction;   // Human-readable step instruction
        @AuraEnabled public String cadenceProgress;   // "Step 3 of 12 — Day 0, SMS"
        @AuraEnabled public String progressFraction;  // "3/12"
        @AuraEnabled public List<String> upcomingSteps; // Next 2-3 step previews
        @AuraEnabled public Boolean isCadenceAction;
    }

    public class ActionResultWrapper {
        @AuraEnabled public ActionWrapper nextAction;
        @AuraEnabled public Boolean hasNext;
    }
}
