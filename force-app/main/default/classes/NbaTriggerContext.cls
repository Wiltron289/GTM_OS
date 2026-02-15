/**
 * NbaTriggerContext — Shared utility for NBA V2 trigger handlers.
 *
 * Provides recursion prevention (static booleans reset per transaction),
 * shared constants, and helper methods used across all three trigger
 * handlers (Opportunity, Event, Task).
 */
public with sharing class NbaTriggerContext {

    // ─── Recursion Prevention ────────────────────────────────────────
    // Static booleans reset per transaction. Prevent re-entry when
    // trigger DML (e.g., NBA_Queue__c insert) causes cascading triggers.

    private static Boolean oppHandlerRan = false;
    private static Boolean eventHandlerRan = false;
    private static Boolean taskHandlerRan = false;

    public static Boolean hasOppHandlerRun() { return oppHandlerRan; }
    public static void setOppHandlerRun() { oppHandlerRan = true; }

    public static Boolean hasEventHandlerRun() { return eventHandlerRan; }
    public static void setEventHandlerRun() { eventHandlerRan = true; }

    public static Boolean hasTaskHandlerRun() { return taskHandlerRan; }
    public static void setTaskHandlerRun() { taskHandlerRan = true; }

    // Allow test classes to reset recursion guards between scenarios
    @TestVisible
    private static void resetAll() {
        oppHandlerRan = false;
        eventHandlerRan = false;
        taskHandlerRan = false;
    }

    // ─── Shared Constants ────────────────────────────────────────────

    public static final Set<String> EXCLUDED_STAGES = new Set<String>{
        'Hand-Off', 'Closed Won', 'Closed Lost'
    };

    // Status values for active/pending actions
    public static final Set<String> ACTIVE_STATUSES = new Set<String>{
        'New', 'Pending', 'In Progress', 'Accepted'
    };

    // Time-bound action window: only create meeting actions if within 24 hours
    public static final Integer MEETING_WINDOW_HOURS = 24;

    // ─── Helpers ─────────────────────────────────────────────────────

    /**
     * Filters a list of SObjects whose WhatId (or a specified lookup field)
     * references an Opportunity, and groups them by Opportunity ID.
     * Useful for Event and Task triggers where WhatId can point to any object.
     *
     * @param records List of Event or Task records
     * @param whatIdField API name of the polymorphic lookup field (usually 'WhatId')
     * @return Map of Opportunity ID → list of related SObjects
     */
    public static Map<Id, List<SObject>> groupByOppId(List<SObject> records, String whatIdField) {
        Map<Id, List<SObject>> grouped = new Map<Id, List<SObject>>();
        if (records == null) {
            return grouped;
        }
        for (SObject rec : records) {
            Id whatId = (Id) rec.get(whatIdField);
            if (whatId != null && whatId.getSObjectType() == Opportunity.SObjectType) {
                if (!grouped.containsKey(whatId)) {
                    grouped.put(whatId, new List<SObject>());
                }
                grouped.get(whatId).add(rec);
            }
        }
        return grouped;
    }

    /**
     * Extract unique Opportunity IDs from a list of SObjects using a specified field.
     */
    public static Set<Id> extractOppIds(List<SObject> records, String whatIdField) {
        Set<Id> oppIds = new Set<Id>();
        if (records == null) {
            return oppIds;
        }
        for (SObject rec : records) {
            Id whatId = (Id) rec.get(whatIdField);
            if (whatId != null && whatId.getSObjectType() == Opportunity.SObjectType) {
                oppIds.add(whatId);
            }
        }
        return oppIds;
    }
}
