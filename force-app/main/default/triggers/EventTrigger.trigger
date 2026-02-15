/**
 * EventTrigger — Delegates to NbaEventTriggerHandler for real-time
 * Layer 1 time-bound action creation (meeting → prepare action).
 */
trigger EventTrigger on Event (after insert, after update, after delete) {
    NbaEventTriggerHandler.handle(
        Trigger.new, Trigger.old, Trigger.oldMap, Trigger.operationType
    );
}
