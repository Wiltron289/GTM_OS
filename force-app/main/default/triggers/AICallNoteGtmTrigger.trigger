/**
 * AICallNoteGtmTrigger — Delegates to AICallNoteGtmTriggerHandler to publish
 * Call_Completed_Event__e when an AI_Call_Note__c is linked to an Opportunity.
 *
 * Enables the GTM OS workspace to detect AI-analyzed call notes and present
 * the post-call intelligence panel.
 */
trigger AICallNoteGtmTrigger on AI_Call_Note__c (after insert) {
    AICallNoteGtmTriggerHandler.handle(Trigger.new);
}
