/**
 * NbaActionStateService — Action lifecycle management for the NBA V2 engine.
 *
 * Manages state transitions: complete, snooze, dismiss, expire, unsnooze.
 * Enforces constraints: max 2 active+pending per AE, 1 active per Opp.
 * Handles promotion of next-highest-ranked Pending action when slots open.
 *
 * Called by NbaActionController (LWC) and NbaActionExpirationSchedulable.
 */
public with sharing class NbaActionStateService {

    // ─── Constants ────────────────────────────────────────────────────
    private static final Integer MAX_ACTIVE_PENDING_PER_AE = 2;
    private static final Set<String> ACTIVE_STATUSES = new Set<String>{
        'Pending', 'In Progress', 'Accepted'
    };

    // Expiration thresholds (configurable for testing)
    @TestVisible
    private static Integer NON_TIMEBOUND_EXPIRE_MINUTES = 60;
    @TestVisible
    private static Integer TIMEBOUND_EXPIRE_MINUTES = 15;

    // ─── AE-Invoked Transitions ───────────────────────────────────────

    /**
     * Complete an action. Sets Status='Completed', triggers promotion.
     * @param actionId The NBA_Queue__c record ID
     * @return The next promoted action for the AE (or null if none)
     */
    public static NBA_Queue__c completeAction(Id actionId) {
        NBA_Queue__c action = queryAction(actionId);
        if (action == null) {
            throw new AuraHandledException('Action not found or already completed.');
        }

        action.Status__c = 'Completed';
        action.Completed_Date__c = Datetime.now();
        action.Actioned_Date__c = Datetime.now();
        // Clear unique key so engine can recreate if conditions apply later
        action.UniqueKey__c = null;
        update action;

        return promoteNextAction(action.Sales_Rep__c);
    }

    /**
     * Snooze an action. Sets Status='Snoozed' with a snooze-until time.
     * Snoozed actions do NOT count toward the AE's active cap.
     * @param actionId The NBA_Queue__c record ID
     * @param reason The snooze reason text
     * @param snoozeDurationMinutes Duration in minutes before re-entry
     * @return The next promoted action for the AE (or null)
     */
    public static NBA_Queue__c snoozeAction(Id actionId, String reason, Integer snoozeDurationMinutes) {
        NBA_Queue__c action = queryAction(actionId);
        if (action == null) {
            throw new AuraHandledException('Action not found or not in a snoozable state.');
        }

        action.Status__c = 'Snoozed';
        action.Snoozed_Until__c = Datetime.now().addMinutes(snoozeDurationMinutes);
        action.Dismissed_Reason__c = reason;
        update action;

        return promoteNextAction(action.Sales_Rep__c);
    }

    /**
     * Dismiss an action. Sets Status='Dismissed' with reason and category.
     * @param actionId The NBA_Queue__c record ID
     * @param reason The dismiss reason text
     * @param category The dismiss category (picklist value)
     * @return The next promoted action for the AE (or null)
     */
    public static NBA_Queue__c dismissAction(Id actionId, String reason, String category) {
        List<NBA_Queue__c> actions = [
            SELECT Id, Status__c, Sales_Rep__c, UniqueKey__c
            FROM NBA_Queue__c
            WHERE Id = :actionId
              AND Status__c IN ('In Progress', 'Accepted', 'Pending')
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (actions.isEmpty()) {
            throw new AuraHandledException('Action not found or not dismissable.');
        }

        NBA_Queue__c action = actions[0];
        action.Status__c = 'Dismissed';
        action.Dismissed_Reason__c = reason;
        action.Dismissal_Category__c = category;
        action.UniqueKey__c = null;
        update action;

        return promoteNextAction(action.Sales_Rep__c);
    }

    // ─── System-Invoked Transitions ───────────────────────────────────

    /**
     * Expire stale In Progress actions.
     * Non-timebound: expired after NON_TIMEBOUND_EXPIRE_MINUTES (default 60 min).
     * Timebound: expired TIMEBOUND_EXPIRE_MINUTES after DueAt__c (default 15 min).
     * @return Count of expired records
     */
    public static Integer expireStaleActions() {
        List<NBA_Queue__c> toExpire = new List<NBA_Queue__c>();

        // Non-timebound: In Progress for > threshold
        Datetime nonTimeboundCutoff = Datetime.now().addMinutes(-NON_TIMEBOUND_EXPIRE_MINUTES);
        List<NBA_Queue__c> nonTimebound = [
            SELECT Id, Status__c
            FROM NBA_Queue__c
            WHERE Status__c = 'In Progress'
              AND Is_Time_Bound__c = false
              AND LastModifiedDate < :nonTimeboundCutoff
            WITH SECURITY_ENFORCED
            LIMIT 200
        ];
        toExpire.addAll(nonTimebound);

        // Timebound: past DueAt + threshold
        Datetime timeboundCutoff = Datetime.now().addMinutes(-TIMEBOUND_EXPIRE_MINUTES);
        List<NBA_Queue__c> timebound = [
            SELECT Id, Status__c
            FROM NBA_Queue__c
            WHERE Status__c = 'In Progress'
              AND Is_Time_Bound__c = true
              AND DueAt__c != null
              AND DueAt__c < :timeboundCutoff
            WITH SECURITY_ENFORCED
            LIMIT 200
        ];
        toExpire.addAll(timebound);

        if (!toExpire.isEmpty()) {
            for (NBA_Queue__c a : toExpire) {
                a.Status__c = 'Expired';
                a.UniqueKey__c = null;
            }
            update toExpire;
        }

        return toExpire.size();
    }

    /**
     * Unsnooze actions whose Snoozed_Until__c has passed.
     * Moves them back to 'Pending' for re-evaluation.
     * @return Count of unsnoozed records
     */
    public static Integer unsnoozeDueActions() {
        List<NBA_Queue__c> toUnsnooze = [
            SELECT Id, Status__c, Sales_Rep__c, Snoozed_Until__c
            FROM NBA_Queue__c
            WHERE Status__c = 'Snoozed'
              AND Snoozed_Until__c <= :Datetime.now()
            WITH SECURITY_ENFORCED
            LIMIT 200
        ];

        if (!toUnsnooze.isEmpty()) {
            for (NBA_Queue__c a : toUnsnooze) {
                a.Status__c = 'Pending';
                a.Snoozed_Until__c = null;
            }
            update toUnsnooze;
        }

        return toUnsnooze.size();
    }

    // ─── Promotion ────────────────────────────────────────────────────

    /**
     * Promote the top-ranked Pending action to 'In Progress' for an AE,
     * if they have capacity (< MAX_ACTIVE_PENDING_PER_AE active+pending).
     * @param aeUserId The AE's User ID
     * @return The promoted action, or null if no capacity or no candidates
     */
    public static NBA_Queue__c promoteNextAction(Id aeUserId) {
        if (aeUserId == null) {
            return null;
        }

        // Check capacity
        Integer activeCount = getActiveCount(aeUserId);
        if (activeCount >= MAX_ACTIVE_PENDING_PER_AE) {
            return null;
        }

        // Find top-ranked Pending action (Layer 1 > 2 > 3, then by score)
        // SOQL CASE not supported in Apex ORDER BY, so query all and sort in-memory
        List<NBA_Queue__c> candidates = [
            SELECT Id, Status__c, Priority_Layer__c, Priority_Score__c,
                   Is_Time_Bound__c, Opportunity__c, Sales_Rep__c,
                   Action_Type__c, Action_Instruction__c
            FROM NBA_Queue__c
            WHERE Sales_Rep__c = :aeUserId
              AND Status__c = 'Pending'
            WITH SECURITY_ENFORCED
            ORDER BY Priority_Score__c DESC
            LIMIT 20
        ];
        // Sort by layer precedence (Layer 1 first), then by score descending
        candidates.sort(new ActionLayerComparator());

        if (candidates.isEmpty()) {
            return null;
        }

        NBA_Queue__c action = candidates[0];
        action.Status__c = 'In Progress';
        action.Actioned_Date__c = Datetime.now();
        update action;

        return action;
    }

    // ─── Constraint Helpers ───────────────────────────────────────────

    /**
     * Count active+pending actions for an AE.
     * Snoozed does NOT count toward cap.
     */
    public static Integer getActiveCount(Id aeUserId) {
        return [
            SELECT COUNT()
            FROM NBA_Queue__c
            WHERE Sales_Rep__c = :aeUserId
              AND Status__c IN :ACTIVE_STATUSES
            WITH SECURITY_ENFORCED
        ];
    }

    /**
     * Check if AE has capacity for more actions.
     */
    public static Boolean hasCapacity(Id aeUserId) {
        return getActiveCount(aeUserId) < MAX_ACTIVE_PENDING_PER_AE;
    }

    // ─── Private Helpers ──────────────────────────────────────────────

    private static NBA_Queue__c queryAction(Id actionId) {
        List<NBA_Queue__c> actions = [
            SELECT Id, Status__c, Sales_Rep__c, UniqueKey__c
            FROM NBA_Queue__c
            WHERE Id = :actionId
              AND Status__c IN ('In Progress', 'Accepted')
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return actions.isEmpty() ? null : actions[0];
    }

    // ─── Layer Comparator ─────────────────────────────────────────────

    private static final Map<String, Integer> LAYER_ORDER = new Map<String, Integer>{
        'Layer 1 - Time Bound' => 1,
        'Layer 2 - Mode' => 2,
        'Layer 3 - Impact+Urgency' => 3
    };

    /**
     * Sorts NBA_Queue__c by Priority Layer (ascending), then Priority Score (descending).
     */
    private class ActionLayerComparator implements System.Comparator<NBA_Queue__c> {
        public Integer compare(NBA_Queue__c a, NBA_Queue__c b) {
            Integer layerA = LAYER_ORDER.containsKey(a.Priority_Layer__c)
                ? LAYER_ORDER.get(a.Priority_Layer__c) : 4;
            Integer layerB = LAYER_ORDER.containsKey(b.Priority_Layer__c)
                ? LAYER_ORDER.get(b.Priority_Layer__c) : 4;
            if (layerA != layerB) {
                return layerA - layerB;
            }
            // Same layer: higher score first (descending)
            Decimal scoreA = a.Priority_Score__c != null ? a.Priority_Score__c : 0;
            Decimal scoreB = b.Priority_Score__c != null ? b.Priority_Score__c : 0;
            if (scoreB > scoreA) return 1;
            if (scoreB < scoreA) return -1;
            return 0;
        }
    }
}
