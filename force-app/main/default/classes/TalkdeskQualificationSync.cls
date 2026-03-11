/**
 * TalkdeskQualificationSync — Syncs qualification fields from Talkdesk Activity
 * records to their related Opportunities.
 *
 * Mirrors AICallNoteQualificationSync guardrails:
 * - Text fields: write only if Opp field is currently blank
 * - Checkbox fields: only flip false → true, never true → false
 * - Dirty-tracking: only updates Opps where something actually changed
 * - Bulk-safe
 */
public with sharing class TalkdeskQualificationSync {

    public static void syncToOpportunity(List<talkdesk__Talkdesk_Activity__c> activities) {
        // Collect Opportunity IDs
        Set<Id> oppIds = new Set<Id>();
        for (talkdesk__Talkdesk_Activity__c ta : activities) {
            if (ta.talkdesk__Opportunity__c != null) {
                oppIds.add(ta.talkdesk__Opportunity__c);
            }
        }
        if (oppIds.isEmpty()) {
            return;
        }

        // Query current Opportunity field values
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
            SELECT Id, OwnerId,
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

        // Check CMDT config for user filtering
        Talkdesk_Qualification_Config__mdt config = Talkdesk_Qualification_Config__mdt.getInstance('Default');
        Set<String> allowedUserIds = null;
        if (config != null && config.User_Mode__c == 'Specific_Users' && String.isNotBlank(config.User_Ids__c)) {
            allowedUserIds = new Set<String>();
            for (String uid : config.User_Ids__c.split(',')) {
                String trimmed = uid.trim();
                if (String.isNotBlank(trimmed)) {
                    allowedUserIds.add(trimmed);
                }
            }
        }

        // Track which Opps actually change
        Set<Id> dirtyOppIds = new Set<Id>();

        for (talkdesk__Talkdesk_Activity__c ta : activities) {
            if (ta.talkdesk__Opportunity__c == null || !oppMap.containsKey(ta.talkdesk__Opportunity__c)) {
                continue;
            }
            Opportunity opp = oppMap.get(ta.talkdesk__Opportunity__c);

            // User filter: skip if Opp Owner not in allowed list
            if (allowedUserIds != null && !allowedUserIds.contains(String.valueOf(opp.OwnerId))) {
                continue;
            }

            // Text fields — write only if Opp field is blank
            if (String.isBlank(opp.Customer_Story__c) && String.isNotBlank(ta.Customer_Story__c)) {
                opp.Customer_Story__c = ta.Customer_Story__c;
                dirtyOppIds.add(opp.Id);
            }
            if (String.isBlank(opp.Inception_or_Switcher__c) && String.isNotBlank(ta.Inception_Or_Switcher__c)) {
                opp.Inception_or_Switcher__c = ta.Inception_Or_Switcher__c;
                dirtyOppIds.add(opp.Id);
            }
            if (String.isBlank(opp.Business_Challenge__c) && String.isNotBlank(ta.Business_Challenges__c)) {
                opp.Business_Challenge__c = ta.Business_Challenges__c;
                dirtyOppIds.add(opp.Id);
            }
            if (String.isBlank(opp.Features_and_Benefits_Discussed__c) && String.isNotBlank(ta.Features_Benefits_Discussed__c)) {
                opp.Features_and_Benefits_Discussed__c = ta.Features_Benefits_Discussed__c;
                dirtyOppIds.add(opp.Id);
            }

            // Checkbox fields — only flip false → true, never true → false
            if (!opp.Decision_Maker_Identified__c && ta.Decision_Maker_Identified__c) {
                opp.Decision_Maker_Identified__c = true;
                dirtyOppIds.add(opp.Id);
            }
            if (!opp.Best_Product_Fit_Identified__c && ta.Best_Product_Fit_Identified__c) {
                opp.Best_Product_Fit_Identified__c = true;
                dirtyOppIds.add(opp.Id);
            }
            if (!opp.Budget_Confirmed__c && ta.Budget_Confirmed__c) {
                opp.Budget_Confirmed__c = true;
                dirtyOppIds.add(opp.Id);
            }
            if (!opp.Timeline_Confirmed__c && ta.Timeline_Confirmed__c) {
                opp.Timeline_Confirmed__c = true;
                dirtyOppIds.add(opp.Id);
            }
            if (!opp.Verbal_Commit__c && ta.Verbal_Commit__c) {
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
