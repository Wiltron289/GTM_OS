/**
 * NbaTaskTriggerHandler — Handles Task trigger events for NBA V2.
 *
 * When a Task is completed on an Opportunity that has active/pending
 * NBA_Queue__c actions, this handler updates context on those actions:
 *
 * 1. Updates LastEvaluatedAt__c (signals are stale, next scheduled run re-scores)
 * 2. Increments Attempt_Count_Today__c and sets Last_Attempt_Method__c for calls
 * 3. Auto-completes "First Touch" or "Re-engage" actions if the logged activity
 *    represents a connected call (the AE already did the work)
 *
 * Does NOT create new actions — the scheduled job handles creation.
 * Runs synchronously (lightweight — 1-2 SOQL, 1-2 DML).
 */
public with sharing class NbaTaskTriggerHandler {

    // Call disposition values that represent a connected call
    private static final Set<String> CONNECTED_DISPOSITIONS = new Set<String>{
        'Connected-DM', 'Connected-GK', 'Connected - DM', 'Connected - GK'
    };

    // Action types that can be auto-completed by a connected call
    private static final Set<String> COMPLETABLE_TYPES = new Set<String>{
        'First Touch', 'Re-engage', 'Follow Up'
    };

    /**
     * Entry point called by TaskTrigger.
     */
    public static void handle(
        List<Task> newList,
        Map<Id, Task> oldMap,
        System.TriggerOperation operationType
    ) {
        if (NbaTriggerContext.hasTaskHandlerRun()) {
            return;
        }
        NbaTriggerContext.setTaskHandlerRun();

        // Filter: completed tasks on Opportunities
        List<Task> completedOppTasks = filterCompletedOppTasks(newList, oldMap, operationType);
        if (completedOppTasks.isEmpty()) {
            return;
        }

        // Collect Opp IDs
        Set<Id> oppIds = NbaTriggerContext.extractOppIds(completedOppTasks, 'WhatId');
        if (oppIds.isEmpty()) {
            return;
        }

        // Query existing active/pending actions for these Opps
        List<NBA_Queue__c> existingActions = [
            SELECT Id, Opportunity__c, Action_Type__c, Status__c,
                   Sales_Rep__c, Attempt_Count_Today__c, Last_Attempt_Method__c,
                   LastEvaluatedAt__c
            FROM NBA_Queue__c
            WHERE Opportunity__c IN :oppIds
              AND Status__c IN :NbaTriggerContext.ACTIVE_STATUSES
            WITH SECURITY_ENFORCED
        ];

        if (existingActions.isEmpty()) {
            return;
        }

        // Build map: Opp ID → list of active actions
        Map<Id, List<NBA_Queue__c>> actionsByOpp = new Map<Id, List<NBA_Queue__c>>();
        for (NBA_Queue__c action : existingActions) {
            if (!actionsByOpp.containsKey(action.Opportunity__c)) {
                actionsByOpp.put(action.Opportunity__c, new List<NBA_Queue__c>());
            }
            actionsByOpp.get(action.Opportunity__c).add(action);
        }

        // Process each completed task
        List<NBA_Queue__c> actionsToUpdate = new List<NBA_Queue__c>();
        Set<Id> actionsToComplete = new Set<Id>();

        for (Task t : completedOppTasks) {
            Id oppId = t.WhatId;
            List<NBA_Queue__c> oppActions = actionsByOpp.get(oppId);
            if (oppActions == null) {
                continue;
            }

            Boolean isConnectedCall = isConnectedCallTask(t);

            for (NBA_Queue__c action : oppActions) {
                // Skip if we already marked this action for completion
                if (actionsToComplete.contains(action.Id)) {
                    continue;
                }

                // Auto-complete if connected call + completable action type
                if (isConnectedCall && COMPLETABLE_TYPES.contains(action.Action_Type__c)) {
                    actionsToComplete.add(action.Id);
                    continue;
                }

                // Context update: mark as stale, increment attempt count for calls
                action.LastEvaluatedAt__c = Datetime.now();
                if (isCallTask(t)) {
                    action.Attempt_Count_Today__c = (action.Attempt_Count_Today__c != null
                        ? action.Attempt_Count_Today__c : 0) + 1;
                    action.Last_Attempt_Method__c = 'Call';
                }
                actionsToUpdate.add(action);
            }
        }

        // Perform context updates (bulk DML)
        if (!actionsToUpdate.isEmpty()) {
            update actionsToUpdate;
        }

        // Auto-complete actions where the AE did the work
        // Use NbaActionStateService for proper lifecycle management
        for (Id actionId : actionsToComplete) {
            try {
                NbaActionStateService.completeAction(actionId);
            } catch (Exception e) {
                // Swallow — the action may have been completed/expired already
                System.debug(LoggingLevel.WARN,
                    'NbaTaskTriggerHandler: Could not auto-complete action ' + actionId + ': ' + e.getMessage());
            }
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    /**
     * Filter for completed Tasks linked to Opportunities.
     * For after insert: task must already be completed.
     * For after update: task status must have changed to completed.
     */
    private static List<Task> filterCompletedOppTasks(
        List<Task> tasks,
        Map<Id, Task> oldMap,
        System.TriggerOperation operationType
    ) {
        List<Task> result = new List<Task>();
        for (Task t : tasks) {
            // Must be linked to an Opportunity
            if (t.WhatId == null || t.WhatId.getSObjectType() != Opportunity.SObjectType) {
                continue;
            }

            if (operationType == System.TriggerOperation.AFTER_INSERT) {
                // New task that is already completed
                if (t.Status == 'Completed') {
                    result.add(t);
                }
            } else if (operationType == System.TriggerOperation.AFTER_UPDATE) {
                // Task status changed to Completed
                Task old = oldMap.get(t.Id);
                if (t.Status == 'Completed' && old.Status != 'Completed') {
                    result.add(t);
                }
            }
        }
        return result;
    }

    /**
     * Check if the task represents a connected call based on its Subject or CallDisposition.
     */
    private static Boolean isConnectedCallTask(Task t) {
        if (String.isNotBlank(t.CallDisposition)) {
            return CONNECTED_DISPOSITIONS.contains(t.CallDisposition);
        }
        // Fallback: check subject for "Connected" keyword
        if (String.isNotBlank(t.Subject)) {
            return t.Subject.containsIgnoreCase('Connected');
        }
        return false;
    }

    /**
     * Check if the task is a call-related task.
     */
    private static Boolean isCallTask(Task t) {
        if (t.TaskSubtype == 'Call') {
            return true;
        }
        if (String.isNotBlank(t.Subject)
            && (t.Subject.containsIgnoreCase('Call')
                || t.Subject.containsIgnoreCase('Dial'))) {
            return true;
        }
        return false;
    }
}
