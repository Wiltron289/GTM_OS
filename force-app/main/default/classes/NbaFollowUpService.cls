/**
 * NbaFollowUpService — AE-defined follow-up creation for the GTM OS engine.
 *
 * When an AE sets a follow-up after a call, this service:
 * 1. Creates a Task on the Opportunity with specified date/time, method, and notes
 * 2. Sets a reminder at the follow-up time so the Task surfaces as time-bound
 * 3. Pauses the cadence by writing Snoozed_Until__c on the most recent audit record
 * 4. When the follow-up date/time arrives, the engine serves it as a time-bound commitment
 *
 * Cancel removes the snooze, clears the reminder, and marks the Task as Completed.
 *
 * See PRD Section 16 (AE-Defined Follow-Ups).
 */
public with sharing class NbaFollowUpService {

    // ─── Custom Exception (declared first for forward references) ─────
    public class FollowUpException extends Exception {}

    // Subject prefixes by follow-up method
    private static final Map<String, String> METHOD_SUBJECTS = new Map<String, String>{
        'Call' => 'Follow-Up Call',
        'Email' => 'Follow-Up Email',
        'SMS' => 'Follow-Up SMS',
        'Meeting' => 'Follow-Up Meeting'
    };

    private static final String DEFAULT_SUBJECT = 'Follow-Up';

    // ─── Create Follow-Up ─────────────────────────────────────────────

    /**
     * Create a follow-up Task on the Opportunity and pause the cadence.
     * The Task is created with a reminder at the specified date/time so it
     * surfaces as a time-bound commitment when the follow-up is due.
     *
     * @param oppId       Opportunity to attach the follow-up to
     * @param method      Follow-up method (Call, Email, SMS, Meeting)
     * @param followUpDt  When the follow-up should surface (date/time bound)
     * @param notes       Optional context notes from the AE
     * @return The created Task ID
     */
    public static Id createFollowUp(Id oppId, String method, Datetime followUpDt, String notes) {
        if (oppId == null) {
            throw new FollowUpException('Opportunity ID is required');
        }

        if (followUpDt != null && followUpDt < Datetime.now()) {
            throw new FollowUpException('Follow-up date must be in the future');
        }

        // Build subject from method
        String subject = METHOD_SUBJECTS.containsKey(method)
            ? METHOD_SUBJECTS.get(method)
            : DEFAULT_SUBJECT;

        // Create Task with reminder for time-bound surfacing
        Task followUp = new Task(
            WhatId = oppId,
            Subject = subject,
            ActivityDate = followUpDt != null ? followUpDt.date() : Date.today(),
            Description = formatDescription(method, notes),
            Status = 'Not Started',
            Priority = 'Normal',
            Type = 'Follow-Up',
            IsReminderSet = followUpDt != null,
            ReminderDateTime = followUpDt
        );

        insert followUp;

        // Pause cadence: set Snoozed_Until__c on most recent audit record
        if (followUpDt != null) {
            pauseCadence(oppId, followUpDt);
        }

        return followUp.Id;
    }

    // ─── Cancel Follow-Up ─────────────────────────────────────────────

    /**
     * Cancel a follow-up: mark Task complete, clear reminder, and remove
     * the cadence snooze so normal cadence resumes.
     *
     * @param taskId The follow-up Task to cancel
     */
    public static void cancelFollowUp(Id taskId) {
        if (taskId == null) {
            throw new FollowUpException('Task ID is required');
        }

        List<Task> tasks = [
            SELECT Id, WhatId, Status
            FROM Task
            WHERE Id = :taskId
            LIMIT 1
        ];

        if (tasks.isEmpty()) {
            throw new FollowUpException('Follow-up Task not found');
        }

        Task t = tasks[0];

        // Mark complete + clear reminder
        t.Status = 'Completed';
        t.IsReminderSet = false;
        t.ReminderDateTime = null;
        update t;

        // Remove cadence snooze
        if (t.WhatId != null) {
            removeCadenceSnooze(t.WhatId);
        }
    }

    // ─── Private Helpers ──────────────────────────────────────────────

    private static String formatDescription(String method, String notes) {
        String body = 'GTM OS Follow-Up';
        if (String.isNotBlank(method)) {
            body += ' (' + method + ')';
        }
        if (String.isNotBlank(notes)) {
            body += '\n\n' + notes;
        }
        return body;
    }

    /**
     * Pause the cadence by writing Snoozed_Until__c on the most recent
     * completed/in-progress audit record for this Opportunity.
     */
    private static void pauseCadence(Id oppId, Datetime snoozedUntil) {
        List<NBA_Queue__c> audits = [
            SELECT Id, Snoozed_Until__c
            FROM NBA_Queue__c
            WHERE Opportunity__c = :oppId
              AND Status__c IN ('Completed', 'In Progress')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!audits.isEmpty()) {
            audits[0].Snoozed_Until__c = snoozedUntil;
            update audits;
        }
    }

    /**
     * Remove cadence snooze by clearing Snoozed_Until__c on the most recent
     * snoozed audit record for this Opportunity.
     */
    private static void removeCadenceSnooze(Id oppId) {
        List<NBA_Queue__c> audits = [
            SELECT Id, Snoozed_Until__c
            FROM NBA_Queue__c
            WHERE Opportunity__c = :oppId
              AND Snoozed_Until__c != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];

        if (!audits.isEmpty()) {
            audits[0].Snoozed_Until__c = null;
            update audits;
        }
    }
}
