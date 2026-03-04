/**
 * NbaTalkdeskActivityTriggerHandler — Publishes Call_Completed_Event__e
 * Platform Events when a Talkdesk Activity is linked to an Opportunity.
 *
 * Fires on AFTER INSERT and AFTER UPDATE of talkdesk__Talkdesk_Activity__c.
 * - INSERT: publishes event if talkdesk__Opportunity__c is populated.
 * - UPDATE: publishes event if talkdesk__Opportunity__c changed from null to non-null.
 *
 * Platform Events are transient (no dedup needed) and delivered via
 * lightning/empApi push — replacing the 15s NBA_Queue__c interrupt poll.
 *
 * SOQL budget: 2 (Opp query + Activity detail query). Bulk-safe.
 */
public with sharing class NbaTalkdeskActivityTriggerHandler {

    @TestVisible
    static List<Call_Completed_Event__e> lastPublishedEvents;

    public static void handle(
        List<talkdesk__Talkdesk_Activity__c> newList,
        Map<Id, talkdesk__Talkdesk_Activity__c> oldMap,
        System.TriggerOperation operationType
    ) {
        if (NbaTriggerContext.hasTalkdeskActivityHandlerRun()) {
            return;
        }
        NbaTriggerContext.setTalkdeskActivityHandlerRun();

        // Filter qualifying activities
        List<talkdesk__Talkdesk_Activity__c> qualifying = filterQualifying(newList, oldMap, operationType);
        if (qualifying.isEmpty()) {
            return;
        }

        // Collect Opp IDs and Activity IDs from qualifying activities
        Set<Id> oppIds = new Set<Id>();
        Set<Id> activityIds = new Set<Id>();
        for (talkdesk__Talkdesk_Activity__c ta : qualifying) {
            oppIds.add(ta.talkdesk__Opportunity__c);
            activityIds.add(ta.Id);
        }

        // Query Opportunities for OwnerId + Name + Account.Name (1 SOQL)
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
            SELECT Id, AccountId, OwnerId, Name, Account.Name
            FROM Opportunity
            WHERE Id IN :oppIds
            WITH SECURITY_ENFORCED
        ]);

        // Query Activity details for disposition + talk time (1 SOQL)
        // Formula/relationship fields not available in trigger context
        Map<Id, talkdesk__Talkdesk_Activity__c> activityDetailMap = new Map<Id, talkdesk__Talkdesk_Activity__c>([
            SELECT Id, talkdesk__Notes__c, talkdesk__Total_Talk_Time_sec__c,
                   talkdesk__DispositionCode__r.talkdesk__Label__c
            FROM talkdesk__Talkdesk_Activity__c
            WHERE Id IN :activityIds
            WITH SECURITY_ENFORCED
        ]);

        // Build Platform Events
        List<Call_Completed_Event__e> events = new List<Call_Completed_Event__e>();
        Set<Id> affectedAeIds = new Set<Id>();

        for (talkdesk__Talkdesk_Activity__c ta : qualifying) {
            Opportunity opp = oppMap.get(ta.talkdesk__Opportunity__c);
            if (opp == null) {
                continue;
            }

            talkdesk__Talkdesk_Activity__c detail = activityDetailMap.get(ta.Id);

            Call_Completed_Event__e evt = new Call_Completed_Event__e(
                Opportunity_Id__c = String.valueOf(opp.Id),
                Activity_Id__c = String.valueOf(ta.Id),
                Sales_Rep_Id__c = String.valueOf(opp.OwnerId),
                Call_Notes__c = detail?.talkdesk__Notes__c,
                Talk_Time_Sec__c = detail?.talkdesk__Total_Talk_Time_sec__c,
                Disposition__c = detail?.talkdesk__DispositionCode__r.talkdesk__Label__c,
                Account_Name__c = opp.Account?.Name,
                Opp_Name__c = opp.Name
            );
            events.add(evt);
            affectedAeIds.add(opp.OwnerId);
        }

        // Publish events
        if (!events.isEmpty()) {
            lastPublishedEvents = events;
            EventBus.publish(events);
        }

        // Invalidate cache for affected AEs
        NbaCacheService.invalidateForUsers(affectedAeIds);
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    /**
     * Filter qualifying Talkdesk Activities:
     * - AFTER_INSERT: talkdesk__Opportunity__c is populated
     * - AFTER_UPDATE: talkdesk__Opportunity__c changed from null to non-null
     */
    private static List<talkdesk__Talkdesk_Activity__c> filterQualifying(
        List<talkdesk__Talkdesk_Activity__c> activities,
        Map<Id, talkdesk__Talkdesk_Activity__c> oldMap,
        System.TriggerOperation operationType
    ) {
        List<talkdesk__Talkdesk_Activity__c> result = new List<talkdesk__Talkdesk_Activity__c>();
        for (talkdesk__Talkdesk_Activity__c ta : activities) {
            if (ta.talkdesk__Opportunity__c == null) {
                continue;
            }

            if (operationType == System.TriggerOperation.AFTER_INSERT) {
                result.add(ta);
            } else if (operationType == System.TriggerOperation.AFTER_UPDATE) {
                talkdesk__Talkdesk_Activity__c old = oldMap.get(ta.Id);
                if (old.talkdesk__Opportunity__c == null) {
                    result.add(ta);
                }
            }
        }
        return result;
    }
}
