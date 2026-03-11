/**
 * TalkdeskQualificationHandler — Parses Talkdesk call notes into structured
 * qualification fields and syncs them to Opportunities.
 *
 * Called by TalkdeskQualificationTrigger on:
 * - BEFORE INSERT: Parse talkdesk__Notes__c → populate 9 custom fields on the record
 * - AFTER INSERT:  If talkdesk__Opportunity__c is populated → sync to Opp
 * - AFTER UPDATE:  If talkdesk__Opportunity__c changed null → non-null → sync to Opp
 *
 * Controlled by Talkdesk_Qualification_Config__mdt:
 * - Is_Active__c: global on/off switch
 * - User_Mode__c / User_Ids__c: Opp Owner filter (applied on sync only)
 *
 * Parsing always runs when active (fields on Activity are harmless).
 * User filter only gates the Opportunity sync.
 */
public with sharing class TalkdeskQualificationHandler {

    // Test override: set to true in tests to bypass CMDT kill switch
    @TestVisible
    private static Boolean isActiveOverride = null;

    public static void handle(
        List<talkdesk__Talkdesk_Activity__c> newList,
        Map<Id, talkdesk__Talkdesk_Activity__c> oldMap,
        System.TriggerOperation operationType
    ) {
        // Check global kill switch (test override takes precedence)
        if (!isActive()) {
            return;
        }

        if (operationType == System.TriggerOperation.BEFORE_INSERT) {
            parseNotes(newList);
        } else if (operationType == System.TriggerOperation.AFTER_INSERT) {
            List<talkdesk__Talkdesk_Activity__c> withOpp = filterWithOpportunity(newList);
            if (!withOpp.isEmpty()) {
                TalkdeskQualificationSync.syncToOpportunity(withOpp);
            }
        } else if (operationType == System.TriggerOperation.AFTER_UPDATE) {
            List<talkdesk__Talkdesk_Activity__c> newlyLinked = filterNewlyLinked(newList, oldMap);
            if (!newlyLinked.isEmpty()) {
                TalkdeskQualificationSync.syncToOpportunity(newlyLinked);
            }
        }
    }

    /**
     * Parse talkdesk__Notes__c and populate qualification fields on the record.
     * Runs in BEFORE INSERT so we can set fields directly (no extra DML).
     */
    private static void parseNotes(List<talkdesk__Talkdesk_Activity__c> activities) {
        for (talkdesk__Talkdesk_Activity__c ta : activities) {
            if (String.isBlank(ta.talkdesk__Notes__c)) {
                continue;
            }
            Map<String, String> parsed = TalkdeskNotesParser.parse(ta.talkdesk__Notes__c);
            TalkdeskNotesParser.applyToRecord(ta, parsed);
        }
    }

    /**
     * Filter activities that have an Opportunity link (for AFTER INSERT sync).
     */
    private static List<talkdesk__Talkdesk_Activity__c> filterWithOpportunity(
        List<talkdesk__Talkdesk_Activity__c> activities
    ) {
        List<talkdesk__Talkdesk_Activity__c> result = new List<talkdesk__Talkdesk_Activity__c>();
        for (talkdesk__Talkdesk_Activity__c ta : activities) {
            if (ta.talkdesk__Opportunity__c != null && hasQualificationData(ta)) {
                result.add(ta);
            }
        }
        return result;
    }

    /**
     * Filter activities where talkdesk__Opportunity__c changed from null to non-null
     * (for AFTER UPDATE sync when your other automation links the Opp).
     */
    private static List<talkdesk__Talkdesk_Activity__c> filterNewlyLinked(
        List<talkdesk__Talkdesk_Activity__c> newList,
        Map<Id, talkdesk__Talkdesk_Activity__c> oldMap
    ) {
        List<talkdesk__Talkdesk_Activity__c> result = new List<talkdesk__Talkdesk_Activity__c>();
        for (talkdesk__Talkdesk_Activity__c ta : newList) {
            if (ta.talkdesk__Opportunity__c != null && hasQualificationData(ta)) {
                talkdesk__Talkdesk_Activity__c old = oldMap.get(ta.Id);
                if (old.talkdesk__Opportunity__c == null) {
                    result.add(ta);
                }
            }
        }
        return result;
    }

    /**
     * Check if the feature is active via CMDT or test override.
     */
    private static Boolean isActive() {
        if (isActiveOverride != null) {
            return isActiveOverride;
        }
        Talkdesk_Qualification_Config__mdt config = Talkdesk_Qualification_Config__mdt.getInstance('Default');
        return config != null && config.Is_Active__c;
    }

    /**
     * Check if the activity has any parsed qualification data worth syncing.
     */
    private static Boolean hasQualificationData(talkdesk__Talkdesk_Activity__c ta) {
        return String.isNotBlank(ta.Customer_Story__c)
            || String.isNotBlank(ta.Inception_Or_Switcher__c)
            || ta.Decision_Maker_Identified__c
            || String.isNotBlank(ta.Business_Challenges__c)
            || ta.Best_Product_Fit_Identified__c
            || String.isNotBlank(ta.Features_Benefits_Discussed__c)
            || ta.Budget_Confirmed__c
            || ta.Timeline_Confirmed__c
            || ta.Verbal_Commit__c;
    }
}
