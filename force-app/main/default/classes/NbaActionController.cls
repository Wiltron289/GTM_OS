/**
 * NbaActionController — Thin Apex controller for the NBA V2 App Page LWC.
 *
 * Bridges the nbaDemoWorkspace component to the engine services.
 * getActiveAction: finds or promotes the current user's top action.
 * complete/snooze/dismiss: delegate to NbaActionStateService, return next action.
 */
public with sharing class NbaActionController {

    // ─── Get Active Action ──────────────────────────────────────────

    /**
     * Returns the current user's active (In Progress) action.
     * If none exists, promotes the top-ranked Pending action.
     * @return ActionWrapper or null if no actions available
     */
    @AuraEnabled
    public static ActionWrapper getActiveAction() {
        Id userId = UserInfo.getUserId();

        // Check for an existing In Progress action
        List<NBA_Queue__c> active = [
            SELECT Id, Opportunity__c, Account__c, Action_Type__c,
                   Action_Instruction__c, ReasonText__c, Priority_Layer__c,
                   Priority_Bucket__c, Priority_Score__c, Is_Time_Bound__c,
                   DueAt__c, Status__c,
                   Account__r.Name, Opportunity__r.Name, Opportunity__r.StageName
            FROM NBA_Queue__c
            WHERE Sales_Rep__c = :userId
              AND Status__c = 'In Progress'
            WITH SECURITY_ENFORCED
            ORDER BY Priority_Score__c DESC
            LIMIT 1
        ];

        if (!active.isEmpty()) {
            return toWrapper(active[0]);
        }

        // No active action — try to promote the next Pending
        NBA_Queue__c promoted = NbaActionStateService.promoteNextAction(userId);
        if (promoted == null) {
            return null;
        }

        // Re-query promoted action with relationship fields
        List<NBA_Queue__c> requeried = [
            SELECT Id, Opportunity__c, Account__c, Action_Type__c,
                   Action_Instruction__c, ReasonText__c, Priority_Layer__c,
                   Priority_Bucket__c, Priority_Score__c, Is_Time_Bound__c,
                   DueAt__c, Status__c,
                   Account__r.Name, Opportunity__r.Name, Opportunity__r.StageName
            FROM NBA_Queue__c
            WHERE Id = :promoted.Id
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        return requeried.isEmpty() ? null : toWrapper(requeried[0]);
    }

    // ─── Action Lifecycle ───────────────────────────────────────────

    /**
     * Complete an action. Returns the next action for the AE.
     */
    @AuraEnabled
    public static ActionResultWrapper completeAction(Id actionId) {
        NBA_Queue__c next = NbaActionStateService.completeAction(actionId);
        return buildResult(next);
    }

    /**
     * Snooze an action with a reason and duration. Returns the next action.
     */
    @AuraEnabled
    public static ActionResultWrapper snoozeAction(Id actionId, String reason, Integer durationMinutes) {
        NBA_Queue__c next = NbaActionStateService.snoozeAction(actionId, reason, durationMinutes);
        return buildResult(next);
    }

    /**
     * Dismiss an action with a reason and category. Returns the next action.
     */
    @AuraEnabled
    public static ActionResultWrapper dismissAction(Id actionId, String reason, String category) {
        NBA_Queue__c next = NbaActionStateService.dismissAction(actionId, reason, category);
        return buildResult(next);
    }

    // ─── Private Helpers ────────────────────────────────────────────

    private static ActionResultWrapper buildResult(NBA_Queue__c nextRaw) {
        ActionResultWrapper result = new ActionResultWrapper();
        if (nextRaw == null) {
            result.nextAction = null;
            result.hasNext = false;
            return result;
        }

        // Re-query with relationship fields
        List<NBA_Queue__c> requeried = [
            SELECT Id, Opportunity__c, Account__c, Action_Type__c,
                   Action_Instruction__c, ReasonText__c, Priority_Layer__c,
                   Priority_Bucket__c, Priority_Score__c, Is_Time_Bound__c,
                   DueAt__c, Status__c,
                   Account__r.Name, Opportunity__r.Name, Opportunity__r.StageName
            FROM NBA_Queue__c
            WHERE Id = :nextRaw.Id
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (requeried.isEmpty()) {
            result.nextAction = null;
            result.hasNext = false;
        } else {
            result.nextAction = toWrapper(requeried[0]);
            result.hasNext = true;
        }
        return result;
    }

    private static ActionWrapper toWrapper(NBA_Queue__c action) {
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
        return w;
    }

    // ─── Wrapper Classes ────────────────────────────────────────────

    public class ActionWrapper {
        @AuraEnabled public Id actionId;
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
    }

    public class ActionResultWrapper {
        @AuraEnabled public ActionWrapper nextAction;
        @AuraEnabled public Boolean hasNext;
    }
}
