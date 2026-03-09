/**
 * AICallNoteGtmTriggerHandler — Processes AI_Call_Note__c records for GTM OS.
 *
 * Fires on AFTER INSERT of AI_Call_Note__c.
 *
 * Responsibilities:
 * 1. Filter for records with Opportunity__c populated
 * 2. Query Opportunity for Name, Account.Name, OwnerId
 * 3. Publish Call_Completed_Event__e with Source_Type='AI_Call_Note'
 * 4. Invalidate cache for affected AEs
 *
 * SOQL budget: 1 (Opp query). Bulk-safe.
 */
public with sharing class AICallNoteGtmTriggerHandler {

    @TestVisible
    static List<Call_Completed_Event__e> lastPublishedEvents;

    public static void handle(List<AI_Call_Note__c> newList) {
        if (NbaTriggerContext.hasAiCallNoteHandlerRun()) {
            return;
        }
        NbaTriggerContext.setAiCallNoteHandlerRun();

        // Filter for records with Opportunity link
        List<AI_Call_Note__c> qualifying = new List<AI_Call_Note__c>();
        Set<Id> oppIds = new Set<Id>();
        for (AI_Call_Note__c note : newList) {
            if (note.Opportunity__c != null) {
                qualifying.add(note);
                oppIds.add(note.Opportunity__c);
            }
        }

        if (qualifying.isEmpty()) {
            return;
        }

        // Query Opportunities for OwnerId + Name + Account.Name (1 SOQL)
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
            SELECT Id, OwnerId, Name, Account.Name
            FROM Opportunity
            WHERE Id IN :oppIds
            WITH SECURITY_ENFORCED
        ]);

        // Build Platform Events
        List<Call_Completed_Event__e> events = new List<Call_Completed_Event__e>();
        Set<Id> affectedAeIds = new Set<Id>();

        for (AI_Call_Note__c note : qualifying) {
            Opportunity opp = oppMap.get(note.Opportunity__c);
            if (opp == null) {
                continue;
            }

            Call_Completed_Event__e evt = new Call_Completed_Event__e(
                Opportunity_Id__c = String.valueOf(opp.Id),
                Activity_Id__c = String.valueOf(note.Id),
                Sales_Rep_Id__c = String.valueOf(opp.OwnerId),
                Call_Notes__c = note.Topics_Discussed__c,
                Disposition__c = 'AI Analysis',
                Account_Name__c = opp.Account?.Name,
                Opp_Name__c = opp.Name,
                Source_Type__c = 'AI_Call_Note',
                Source_Record_Id__c = String.valueOf(note.Id)
            );
            events.add(evt);
            affectedAeIds.add(opp.OwnerId);
        }

        // Publish Platform Events
        if (!events.isEmpty()) {
            lastPublishedEvents = events;
            EventBus.publish(events);
        }

        // Invalidate cache for affected AEs
        NbaCacheService.invalidateForUsers(affectedAeIds);
    }
}
