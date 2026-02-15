/**
 * NbaOpportunityTriggerHandler — Handles Opportunity trigger events for NBA V2.
 *
 * After Insert: New open Opportunity → enqueues async evaluation that produces
 *               a "First Touch" action via the full engine pipeline.
 * After Update: Stage change on open Opportunity → enqueues re-evaluation that
 *               may produce "Stage Progression" or other actions.
 *
 * Heavy signal evaluation runs in NbaRealTimeEvaluationQueueable (async)
 * to avoid governor limit pressure in the trigger transaction.
 */
public with sharing class NbaOpportunityTriggerHandler {

    /**
     * Entry point called by OpportunityTrigger.
     * Filters affected Opps, collects IDs, enqueues a single Queueable.
     */
    public static void handle(
        List<Opportunity> newList,
        Map<Id, Opportunity> oldMap,
        System.TriggerOperation operationType
    ) {
        // Recursion guard — prevent re-entry if NBA_Queue__c DML causes cascade
        if (NbaTriggerContext.hasOppHandlerRun()) {
            return;
        }
        NbaTriggerContext.setOppHandlerRun();

        Set<Id> oppIdsToEvaluate = new Set<Id>();

        if (operationType == System.TriggerOperation.AFTER_INSERT) {
            oppIdsToEvaluate = filterNewOpps(newList);
        } else if (operationType == System.TriggerOperation.AFTER_UPDATE) {
            oppIdsToEvaluate = filterStageChanges(newList, oldMap);
        }

        if (!oppIdsToEvaluate.isEmpty()) {
            System.enqueueJob(new NbaRealTimeEvaluationQueueable(oppIdsToEvaluate));
        }
    }

    /**
     * After Insert: Return IDs of new open Opps in non-excluded stages.
     */
    @TestVisible
    private static Set<Id> filterNewOpps(List<Opportunity> newOpps) {
        Set<Id> ids = new Set<Id>();
        for (Opportunity opp : newOpps) {
            if (!opp.IsClosed
                && !NbaTriggerContext.EXCLUDED_STAGES.contains(opp.StageName)) {
                ids.add(opp.Id);
            }
        }
        return ids;
    }

    /**
     * After Update: Return IDs of Opps where StageName changed and the Opp
     * is still open and not in an excluded stage.
     */
    @TestVisible
    private static Set<Id> filterStageChanges(
        List<Opportunity> newOpps,
        Map<Id, Opportunity> oldMap
    ) {
        Set<Id> ids = new Set<Id>();
        for (Opportunity opp : newOpps) {
            Opportunity old = oldMap.get(opp.Id);
            if (opp.StageName != old.StageName
                && !opp.IsClosed
                && !NbaTriggerContext.EXCLUDED_STAGES.contains(opp.StageName)) {
                ids.add(opp.Id);
            }
        }
        return ids;
    }
}
