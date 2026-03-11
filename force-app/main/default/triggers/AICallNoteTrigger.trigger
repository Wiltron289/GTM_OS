trigger AICallNoteTrigger on AI_Call_Note__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        AICallNoteQualificationSync.syncToOpportunity(Trigger.new);
    }
}
