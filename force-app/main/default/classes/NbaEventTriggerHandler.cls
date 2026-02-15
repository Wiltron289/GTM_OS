/**
 * NbaEventTriggerHandler — Handles Event trigger events for NBA V2.
 *
 * After Insert: Meeting scheduled on Opportunity within 24 hours →
 *               creates Layer 1 time-bound action via NbaActionCreationService.
 * After Update: Meeting rescheduled → updates DueAt on existing action.
 * After Delete: Meeting cancelled → expires the time-bound action.
 *
 * Runs synchronously (lightweight — 2-3 SOQL, 1-2 DML per batch).
 */
public with sharing class NbaEventTriggerHandler {

    /**
     * Entry point called by EventTrigger.
     */
    public static void handle(
        List<Event> newList,
        List<Event> oldList,
        Map<Id, Event> oldMap,
        System.TriggerOperation operationType
    ) {
        if (NbaTriggerContext.hasEventHandlerRun()) {
            return;
        }
        NbaTriggerContext.setEventHandlerRun();

        if (operationType == System.TriggerOperation.AFTER_INSERT) {
            handleInsert(newList);
        } else if (operationType == System.TriggerOperation.AFTER_UPDATE) {
            handleUpdate(newList, oldMap);
        } else if (operationType == System.TriggerOperation.AFTER_DELETE) {
            handleDelete(oldList);
        }
    }

    // ─── After Insert ────────────────────────────────────────────────

    private static void handleInsert(List<Event> events) {
        // Filter: Events linked to Opportunities, starting within 24 hours
        Map<Id, Event> oppEvents = filterOppEventsWithinWindow(events);
        if (oppEvents.isEmpty()) {
            return;
        }

        // Query Opportunity data for the linked opps
        Set<Id> oppIds = new Set<Id>();
        for (Event evt : oppEvents.values()) {
            oppIds.add(evt.WhatId);
        }

        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, AccountId, OwnerId, Name, StageName
            FROM Opportunity
            WHERE Id IN :oppIds AND IsClosed = false
            WITH SECURITY_ENFORCED
        ]);

        // Create time-bound actions
        List<NBA_Queue__c> actionsToInsert = new List<NBA_Queue__c>();
        for (Event evt : oppEvents.values()) {
            Opportunity opp = opps.get(evt.WhatId);
            if (opp == null) {
                continue; // Opp is closed or doesn't exist
            }

            String instruction = buildMeetingInstruction(evt, opp);
            NBA_Queue__c action = NbaActionCreationService.createTimeBoundAction(
                opp.Id, opp.AccountId, opp.OwnerId,
                evt.StartDateTime, evt.Id, instruction
            );

            if (action != null) {
                actionsToInsert.add(action);
            }
        }

        if (!actionsToInsert.isEmpty()) {
            Database.insert(actionsToInsert, false);

            // Promote for each AE with new time-bound action
            Set<Id> aeIds = new Set<Id>();
            for (NBA_Queue__c a : actionsToInsert) {
                if (a.Id != null && a.Sales_Rep__c != null) {
                    aeIds.add(a.Sales_Rep__c);
                }
            }
            for (Id aeId : aeIds) {
                if (NbaActionStateService.hasCapacity(aeId)) {
                    NbaActionStateService.promoteNextAction(aeId);
                }
            }
        }
    }

    // ─── After Update ────────────────────────────────────────────────

    private static void handleUpdate(List<Event> events, Map<Id, Event> oldMap) {
        List<NBA_Queue__c> actionsToUpdate = new List<NBA_Queue__c>();

        for (Event evt : events) {
            Event old = oldMap.get(evt.Id);
            Id whatId = evt.WhatId;

            // Only process Events linked to Opportunities with changed start time
            if (whatId == null
                || whatId.getSObjectType() != Opportunity.SObjectType
                || evt.StartDateTime == old.StartDateTime) {
                continue;
            }

            NBA_Queue__c updated = NbaActionCreationService.updateTimeBoundAction(
                evt.Id, whatId, evt.StartDateTime
            );
            if (updated != null) {
                actionsToUpdate.add(updated);
            }
        }

        if (!actionsToUpdate.isEmpty()) {
            update actionsToUpdate;
        }
    }

    // ─── After Delete ────────────────────────────────────────────────

    private static void handleDelete(List<Event> deletedEvents) {
        List<NBA_Queue__c> actionsToUpdate = new List<NBA_Queue__c>();

        for (Event evt : deletedEvents) {
            Id whatId = evt.WhatId;
            if (whatId == null || whatId.getSObjectType() != Opportunity.SObjectType) {
                continue;
            }

            NBA_Queue__c cancelled = NbaActionCreationService.cancelTimeBoundAction(
                evt.Id, whatId
            );
            if (cancelled != null) {
                actionsToUpdate.add(cancelled);
            }
        }

        if (!actionsToUpdate.isEmpty()) {
            update actionsToUpdate;
        }
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    /**
     * Filter events: linked to an Opportunity, StartDateTime within the
     * meeting window (default 24 hours from now).
     */
    private static Map<Id, Event> filterOppEventsWithinWindow(List<Event> events) {
        Map<Id, Event> result = new Map<Id, Event>();
        Datetime windowEnd = Datetime.now().addHours(NbaTriggerContext.MEETING_WINDOW_HOURS);

        for (Event evt : events) {
            if (evt.WhatId != null
                && evt.WhatId.getSObjectType() == Opportunity.SObjectType
                && evt.StartDateTime != null
                && evt.StartDateTime <= windowEnd
                && evt.StartDateTime >= Datetime.now()) {
                result.put(evt.Id, evt);
            }
        }
        return result;
    }

    private static String buildMeetingInstruction(Event evt, Opportunity opp) {
        String instruction = 'Prepare for meeting';
        if (String.isNotBlank(evt.Subject)) {
            instruction += ': ' + evt.Subject;
        }
        if (String.isNotBlank(opp.Name)) {
            instruction += ' (' + opp.Name + ')';
        }
        return instruction.left(255);
    }
}
