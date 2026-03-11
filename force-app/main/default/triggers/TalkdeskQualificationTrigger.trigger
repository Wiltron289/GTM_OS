/**
 * TalkdeskQualificationTrigger — Parses qualification data from Talkdesk call
 * notes and syncs to Opportunities.
 *
 * Separate from NbaTalkdeskActivityTrigger (GTM OS) which handles disposition,
 * cooldown, platform events, and cadence workflows.
 */
trigger TalkdeskQualificationTrigger on talkdesk__Talkdesk_Activity__c (before insert, after insert, after update) {
    TalkdeskQualificationHandler.handle(Trigger.new, Trigger.oldMap, Trigger.operationType);
}
