/**
 * NbaTalkdeskActivityTrigger — Delegates to NbaTalkdeskActivityTriggerHandler
 * to create "Call Completed" interrupt records when a Talkdesk Activity
 * is linked to an Opportunity.
 *
 * Named with "Nba" prefix to avoid collision with the managed package
 * trigger (talkdesk.TalkdeskActivityTrigger).
 */
trigger NbaTalkdeskActivityTrigger on talkdesk__Talkdesk_Activity__c (after insert, after update) {
    NbaTalkdeskActivityTriggerHandler.handle(Trigger.new, Trigger.oldMap, Trigger.operationType);
}
