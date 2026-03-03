/**
 * NbaTalkdeskActivityTriggerHandler — Creates "Call Completed" interrupt
 * records when a Talkdesk Activity is linked to an Opportunity.
 *
 * Fires on AFTER INSERT and AFTER UPDATE of talkdesk__Talkdesk_Activity__c.
 * - INSERT: creates interrupt if talkdesk__Opportunity__c is populated.
 * - UPDATE: creates interrupt if talkdesk__Opportunity__c changed from null to non-null.
 *
 * Creates NBA_Queue__c records with Action_Type = "Call Completed" and
 * Priority_Layer = "Layer 1 - Time Bound" (non-time-bound) so they appear
 * in the 15s interrupt poll (Stream 2).
 *
 * SOQL budget: 2 (Opp query + dedup). Bulk-safe.
 */
public with sharing class NbaTalkdeskActivityTriggerHandler {

    public static void handle(
        List<talkdesk__Talkdesk_Activity__c> newList,
        Map<Id, talkdesk__Talkdesk_Activity__c> oldMap,
        System.TriggerOperation operationType
    ) {
        if (NbaTriggerContext.hasTalkdeskActivityHandlerRun()) {
            return;
        }
        NbaTriggerContext.setTalkdeskActivityHandlerRun();

        // Filter qualifying activities
        List<talkdesk__Talkdesk_Activity__c> qualifying = filterQualifying(newList, oldMap, operationType);
        if (qualifying.isEmpty()) {
            return;
        }

        // Collect Opp IDs from qualifying activities
        Set<Id> oppIds = new Set<Id>();
        for (talkdesk__Talkdesk_Activity__c ta : qualifying) {
            oppIds.add(ta.talkdesk__Opportunity__c);
        }

        // Query Opportunities for AccountId + OwnerId (1 SOQL)
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
            SELECT Id, AccountId, OwnerId
            FROM Opportunity
            WHERE Id IN :oppIds
            WITH SECURITY_ENFORCED
        ]);

        // Build unique keys for all qualifying activities
        Set<String> allKeys = new Set<String>();
        Map<Id, String> activityKeyMap = new Map<Id, String>();
        for (talkdesk__Talkdesk_Activity__c ta : qualifying) {
            String key = 'V2|' + ta.talkdesk__Opportunity__c + '|CallCompleted|' + ta.Id;
            allKeys.add(key);
            activityKeyMap.put(ta.Id, key);
        }

        // Bulk dedup (1 SOQL)
        Set<String> existingKeys = new Set<String>();
        for (NBA_Queue__c existing : [
            SELECT UniqueKey__c FROM NBA_Queue__c
            WHERE UniqueKey__c IN :allKeys
            WITH SECURITY_ENFORCED
        ]) {
            existingKeys.add(existing.UniqueKey__c);
        }

        // Build NBA_Queue__c records for non-duplicates
        List<NBA_Queue__c> toInsert = new List<NBA_Queue__c>();
        Set<Id> affectedAeIds = new Set<Id>();

        for (talkdesk__Talkdesk_Activity__c ta : qualifying) {
            String key = activityKeyMap.get(ta.Id);
            if (existingKeys.contains(key)) {
                continue;
            }

            Opportunity opp = oppMap.get(ta.talkdesk__Opportunity__c);
            if (opp == null) {
                continue;
            }

            NBA_Queue__c action = new NBA_Queue__c(
                Opportunity__c = opp.Id,
                Account__c = opp.AccountId,
                Sales_Rep__c = opp.OwnerId,
                Action_Type__c = 'Call Completed',
                Priority_Layer__c = 'Layer 1 - Time Bound',
                Is_Time_Bound__c = false,
                Status__c = 'Pending',
                Talkdesk_Activity__c = ta.Id,
                Rep_Notes__c = ta.talkdesk__Notes__c,
                Action_Instruction__c = 'Review and save call notes',
                Rule_Name__c = 'CallCompleted_Interrupt',
                UniqueKey__c = key,
                Workflow_Mode__c = 'Pipeline'
            );
            toInsert.add(action);
            affectedAeIds.add(opp.OwnerId);
        }

        // Insert records
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }

        // Invalidate cache for affected AEs
        NbaCacheService.invalidateForUsers(affectedAeIds);
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    /**
     * Filter qualifying Talkdesk Activities:
     * - AFTER_INSERT: talkdesk__Opportunity__c is populated
     * - AFTER_UPDATE: talkdesk__Opportunity__c changed from null to non-null
     */
    private static List<talkdesk__Talkdesk_Activity__c> filterQualifying(
        List<talkdesk__Talkdesk_Activity__c> activities,
        Map<Id, talkdesk__Talkdesk_Activity__c> oldMap,
        System.TriggerOperation operationType
    ) {
        List<talkdesk__Talkdesk_Activity__c> result = new List<talkdesk__Talkdesk_Activity__c>();
        for (talkdesk__Talkdesk_Activity__c ta : activities) {
            if (ta.talkdesk__Opportunity__c == null) {
                continue;
            }

            if (operationType == System.TriggerOperation.AFTER_INSERT) {
                result.add(ta);
            } else if (operationType == System.TriggerOperation.AFTER_UPDATE) {
                talkdesk__Talkdesk_Activity__c old = oldMap.get(ta.Id);
                if (old.talkdesk__Opportunity__c == null) {
                    result.add(ta);
                }
            }
        }
        return result;
    }
}
