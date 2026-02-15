/**
 * OpportunityTrigger — Delegates to NbaOpportunityTriggerHandler for
 * real-time NBA V2 action creation (new opp → First Touch, stage change → re-evaluation).
 */
trigger OpportunityTrigger on Opportunity (after insert, after update) {
    NbaOpportunityTriggerHandler.handle(Trigger.new, Trigger.oldMap, Trigger.operationType);
}
