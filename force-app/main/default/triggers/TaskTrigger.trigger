/**
 * TaskTrigger — Delegates to NbaTaskTriggerHandler for NBA V2
 * context updates when activities are logged against Opportunities.
 */
trigger TaskTrigger on Task (after insert, after update) {
    NbaTaskTriggerHandler.handle(Trigger.new, Trigger.oldMap, Trigger.operationType);
}
