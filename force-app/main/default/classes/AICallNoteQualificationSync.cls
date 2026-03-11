public with sharing class AICallNoteQualificationSync {

    public static void syncToOpportunity(List<AI_Call_Note__c> notes) {
        // Collect Opportunity IDs from notes that have a related Opp
        Set<Id> oppIds = new Set<Id>();
        for (AI_Call_Note__c note : notes) {
            if (note.Opportunity__c != null) {
                oppIds.add(note.Opportunity__c);
            }
        }
        if (oppIds.isEmpty()) {
            return;
        }

        // Query current Opportunity field values
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
            SELECT Id,
                   Customer_Story__c,
                   Inception_or_Switcher__c,
                   Decision_Maker_Identified__c,
                   Business_Challenge__c,
                   Best_Product_Fit_Identified__c,
                   Features_and_Benefits_Discussed__c,
                   Budget_Confirmed__c,
                   Timeline_Confirmed__c,
                   Verbal_Commit__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ]);

        // Track which Opps actually change
        Set<Id> dirtyOppIds = new Set<Id>();

        for (AI_Call_Note__c note : notes) {
            if (note.Opportunity__c == null || !oppMap.containsKey(note.Opportunity__c)) {
                continue;
            }
            Opportunity opp = oppMap.get(note.Opportunity__c);

            // Text fields — write only if Opp field is blank
            if (String.isBlank(opp.Customer_Story__c) && String.isNotBlank(note.Customer_Story__c)) {
                opp.Customer_Story__c = note.Customer_Story__c;
                dirtyOppIds.add(opp.Id);
            }
            if (String.isBlank(opp.Inception_or_Switcher__c) && String.isNotBlank(note.Inception_Or_Switcher__c)) {
                opp.Inception_or_Switcher__c = note.Inception_Or_Switcher__c;
                dirtyOppIds.add(opp.Id);
            }
            if (String.isBlank(opp.Business_Challenge__c) && String.isNotBlank(note.Business_Challenges__c)) {
                opp.Business_Challenge__c = note.Business_Challenges__c;
                dirtyOppIds.add(opp.Id);
            }
            if (String.isBlank(opp.Features_and_Benefits_Discussed__c) && String.isNotBlank(note.Features_Benefits_Discussed__c)) {
                opp.Features_and_Benefits_Discussed__c = note.Features_Benefits_Discussed__c;
                dirtyOppIds.add(opp.Id);
            }

            // Checkbox fields — only flip false → true, never true → false
            if (!opp.Decision_Maker_Identified__c && note.Decision_Maker_Identified__c) {
                opp.Decision_Maker_Identified__c = true;
                dirtyOppIds.add(opp.Id);
            }
            if (!opp.Best_Product_Fit_Identified__c && note.Best_Product_Fit_Identified__c) {
                opp.Best_Product_Fit_Identified__c = true;
                dirtyOppIds.add(opp.Id);
            }
            if (!opp.Budget_Confirmed__c && note.Budget_Confirmed__c) {
                opp.Budget_Confirmed__c = true;
                dirtyOppIds.add(opp.Id);
            }
            if (!opp.Timeline_Confirmed__c && note.Timeline_Confirmed__c) {
                opp.Timeline_Confirmed__c = true;
                dirtyOppIds.add(opp.Id);
            }
            if (!opp.Verbal_Commit__c && note.Verbal_Commit__c) {
                opp.Verbal_Commit__c = true;
                dirtyOppIds.add(opp.Id);
            }
        }

        // Only update Opportunities that actually changed
        if (!dirtyOppIds.isEmpty()) {
            List<Opportunity> toUpdate = new List<Opportunity>();
            for (Id oppId : dirtyOppIds) {
                toUpdate.add(oppMap.get(oppId));
            }
            update toUpdate;
        }
    }
}
