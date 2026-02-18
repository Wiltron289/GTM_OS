/**
 * NbaOpportunityTriggerHandler — Handles Opportunity trigger events for NBA V2.
 *
 * Two-stream architecture:
 * After Insert: New open Opportunity → create Layer 1 new-assignment interrupt
 *   record (picked up by checkInterrupts 15s poll) + invalidate cache for AE.
 * After Update: Stage change on open Opportunity → invalidate cache for AE.
 */
public with sharing class NbaOpportunityTriggerHandler {

    /**
     * Entry point called by OpportunityTrigger.
     * Filters affected Opps, collects owner IDs, invalidates their cache.
     * On AFTER_INSERT: also creates Layer 1 new-assignment interrupt records.
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

        Set<Id> aeIdsToInvalidate = new Set<Id>();

        if (operationType == System.TriggerOperation.AFTER_INSERT) {
            List<Opportunity> newOpps = filterNewOpps(newList);
            aeIdsToInvalidate = collectOwnerIds(newOpps);

            // Two-stream: create Layer 1 new-assignment interrupt records
            createNewAssignmentInterrupts(newOpps);
        } else if (operationType == System.TriggerOperation.AFTER_UPDATE) {
            aeIdsToInvalidate = collectOwnerIds(filterStageChanges(newList, oldMap));
        }

        if (!aeIdsToInvalidate.isEmpty()) {
            NbaCacheService.invalidateForUsers(aeIdsToInvalidate);
        }
    }

    /**
     * After Insert: Return new open Opps in non-excluded stages.
     */
    @TestVisible
    private static List<Opportunity> filterNewOpps(List<Opportunity> newOpps) {
        List<Opportunity> filtered = new List<Opportunity>();
        for (Opportunity opp : newOpps) {
            if (!opp.IsClosed
                && !NbaTriggerContext.EXCLUDED_STAGES.contains(opp.StageName)) {
                filtered.add(opp);
            }
        }
        return filtered;
    }

    /**
     * After Update: Return Opps where StageName changed and still open.
     */
    @TestVisible
    private static List<Opportunity> filterStageChanges(
        List<Opportunity> newOpps,
        Map<Id, Opportunity> oldMap
    ) {
        List<Opportunity> filtered = new List<Opportunity>();
        for (Opportunity opp : newOpps) {
            Opportunity old = oldMap.get(opp.Id);
            if (opp.StageName != old.StageName
                && !opp.IsClosed
                && !NbaTriggerContext.EXCLUDED_STAGES.contains(opp.StageName)) {
                filtered.add(opp);
            }
        }
        return filtered;
    }

    /**
     * Collect unique OwnerId values from a list of Opportunities.
     */
    private static Set<Id> collectOwnerIds(List<Opportunity> opps) {
        Set<Id> ownerIds = new Set<Id>();
        for (Opportunity opp : opps) {
            if (opp.OwnerId != null) {
                ownerIds.add(opp.OwnerId);
            }
        }
        return ownerIds;
    }

    /**
     * Create Layer 1 new-assignment interrupt records for newly inserted Opps.
     * Uses the bulk method (1 SOQL for dedup) to stay within governor limits.
     */
    private static void createNewAssignmentInterrupts(List<Opportunity> newOpps) {
        if (newOpps.isEmpty()) {
            return;
        }

        List<NBA_Queue__c> toInsert =
            NbaActionCreationService.createNewAssignmentActions(newOpps);

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }
}
