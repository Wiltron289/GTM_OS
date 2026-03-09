/**
 * Test class for AICallNoteGtmTriggerHandler.
 *
 * Verifies:
 * - Insert with Opp link publishes Call_Completed_Event__e with Source_Type='AI_Call_Note'
 * - Insert without Opp link publishes nothing
 * - Bulk insert (200 records) publishes 200 events without governor limit breach
 * - Source_Type__c and Source_Record_Id__c values are correct
 * - All payload fields (Sales_Rep_Id, Opportunity_Id, Account_Name, Opp_Name, Disposition) populated correctly
 * - Cache invalidation for affected AEs
 */
@isTest
private class AICallNoteGtmTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'AI Call Note Test Account',
            Entity_ID__c = 'AICN-001',
            Employee_Count__c = 75
        );
        insert acc;

        Id payrollRtId;
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll'
            LIMIT 1
        ];
        if (!rts.isEmpty()) {
            payrollRtId = rts[0].Id;
        }

        Opportunity opp = new Opportunity(
            Name = 'AI Call Note Test Opp',
            AccountId = acc.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 8000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp.RecordTypeId = payrollRtId;
        insert opp;
    }

    // ─── Helpers ────────────────────────────────────────────────────

    private static Opportunity getTestOpp() {
        return [SELECT Id, AccountId, OwnerId, Name, StageName, Account.Name
                FROM Opportunity
                WHERE Account.Name = 'AI Call Note Test Account' LIMIT 1];
    }

    // ─── Insert with Opp Link → Publishes Event with Correct Fields ──

    @isTest
    static void testInsertWithOppLink_PublishesEventWithCorrectFields() {
        Opportunity opp = getTestOpp();

        NbaTriggerContext.resetAll();

        AI_Call_Note__c note = new AI_Call_Note__c(
            Opportunity__c = opp.Id,
            Topics_Discussed__c = 'Discussed pricing tiers and onboarding timeline.'
        );

        Test.startTest();
        insert note;
        Test.stopTest();

        List<Call_Completed_Event__e> events = AICallNoteGtmTriggerHandler.lastPublishedEvents;

        System.assertNotEquals(null, events, 'Should have published events');
        System.assertEquals(1, events.size(), 'Should publish 1 event');

        Call_Completed_Event__e evt = events[0];
        System.assertEquals('AI_Call_Note', evt.Source_Type__c,
            'Source_Type should be AI_Call_Note');
        System.assertEquals(String.valueOf(note.Id), evt.Source_Record_Id__c,
            'Source_Record_Id should match the AI Call Note ID');
        System.assertEquals(String.valueOf(opp.Id), evt.Opportunity_Id__c,
            'Opportunity_Id should match');
        System.assertEquals(String.valueOf(note.Id), evt.Activity_Id__c,
            'Activity_Id should carry the note ID');
        System.assertEquals(String.valueOf(opp.OwnerId), evt.Sales_Rep_Id__c,
            'Sales_Rep_Id should match Opp owner');
        System.assertEquals('AI Analysis', evt.Disposition__c,
            'Disposition should be AI Analysis');
        System.assertEquals(opp.Account.Name, evt.Account_Name__c,
            'Account name should match');
        System.assertEquals(opp.Name, evt.Opp_Name__c,
            'Opp name should match');
        System.assertEquals('Discussed pricing tiers and onboarding timeline.',
            evt.Call_Notes__c,
            'Call_Notes should carry Topics_Discussed from AI note');
    }

    // ─── Insert without Opp Link → No Event ─────────────────────────

    @isTest
    static void testInsertWithoutOppLink_NoEvent() {
        NbaTriggerContext.resetAll();
        AICallNoteGtmTriggerHandler.lastPublishedEvents = null;

        AI_Call_Note__c note = new AI_Call_Note__c(
            Topics_Discussed__c = 'General discussion, no opp linked.'
        );

        Test.startTest();
        insert note;
        Test.stopTest();

        List<Call_Completed_Event__e> events = AICallNoteGtmTriggerHandler.lastPublishedEvents;
        System.assertEquals(null, events,
            'Should NOT publish events when no Opp linked');
    }

    // ─── Bulk Insert (200 records) ───────────────────────────────────

    @isTest
    static void testBulkInsert_PublishesAllEvents() {
        Opportunity opp = getTestOpp();

        NbaTriggerContext.resetAll();

        List<AI_Call_Note__c> notes = new List<AI_Call_Note__c>();
        for (Integer i = 0; i < 200; i++) {
            notes.add(new AI_Call_Note__c(
                Opportunity__c = opp.Id,
                Topics_Discussed__c = 'Bulk test note ' + i
            ));
        }

        Test.startTest();
        insert notes;
        Test.stopTest();

        List<Call_Completed_Event__e> events = AICallNoteGtmTriggerHandler.lastPublishedEvents;

        System.assertNotEquals(null, events, 'Should have published events');
        System.assertEquals(200, events.size(),
            'Should publish 200 events for 200 AI Call Notes');

        // Verify all events have correct Source_Type
        for (Call_Completed_Event__e evt : events) {
            System.assertEquals('AI_Call_Note', evt.Source_Type__c,
                'All events should have Source_Type = AI_Call_Note');
        }
    }

    // ─── Source_Record_Id matches individual note IDs ─────────────────

    @isTest
    static void testSourceRecordId_MatchesNoteIds() {
        Opportunity opp = getTestOpp();

        NbaTriggerContext.resetAll();

        AI_Call_Note__c note1 = new AI_Call_Note__c(
            Opportunity__c = opp.Id,
            Topics_Discussed__c = 'Note 1'
        );
        AI_Call_Note__c note2 = new AI_Call_Note__c(
            Opportunity__c = opp.Id,
            Topics_Discussed__c = 'Note 2'
        );

        Test.startTest();
        insert new List<AI_Call_Note__c>{ note1, note2 };
        Test.stopTest();

        List<Call_Completed_Event__e> events = AICallNoteGtmTriggerHandler.lastPublishedEvents;

        System.assertEquals(2, events.size(), 'Should publish 2 events');

        Set<String> eventSourceIds = new Set<String>();
        for (Call_Completed_Event__e evt : events) {
            eventSourceIds.add(evt.Source_Record_Id__c);
        }

        System.assert(eventSourceIds.contains(String.valueOf(note1.Id)),
            'Events should include Source_Record_Id for note1');
        System.assert(eventSourceIds.contains(String.valueOf(note2.Id)),
            'Events should include Source_Record_Id for note2');
    }

    // ─── Cache Invalidation ──────────────────────────────────────────

    @isTest
    static void testCacheInvalidation() {
        Opportunity opp = getTestOpp();
        Id userId = opp.OwnerId;

        // Pre-populate cache
        NbaActionController.ActionWrapper cached = new NbaActionController.ActionWrapper();
        cached.actionType = 'Stale Action';
        cached.status = 'Evaluated';
        NbaCacheService.cacheAction(userId, cached);

        NbaActionController.ActionWrapper before = NbaCacheService.getCachedAction(userId);
        System.assertNotEquals(null, before, 'Cache should be populated before trigger');

        NbaTriggerContext.resetAll();

        AI_Call_Note__c note = new AI_Call_Note__c(
            Opportunity__c = opp.Id,
            Topics_Discussed__c = 'Cache invalidation test.'
        );

        Test.startTest();
        insert note;
        Test.stopTest();

        NbaActionController.ActionWrapper after = NbaCacheService.getCachedAction(userId);
        System.assertEquals(null, after,
            'Cache should be invalidated after AI Call Note insert');
    }
}
