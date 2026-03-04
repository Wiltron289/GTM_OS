/**
 * Test class for NbaTalkdeskActivityTriggerHandler + TalkdeskActivityTrigger.
 *
 * Verifies:
 * - Insert with Opp link publishes Call_Completed_Event__e with correct fields
 * - Insert without Opp link publishes nothing
 * - Update that adds Opp link publishes event
 * - Bulk insert (200 activities) publishes 200 events without governor limit breach
 * - Cache invalidation for affected AEs
 */
@isTest
private class NbaTalkdeskActivityTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'TDActivity Test Account',
            Entity_ID__c = 'TDA-001',
            Employee_Count__c = 50
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
            Name = 'TDActivity Test Opp',
            AccountId = acc.Id,
            StageName = 'Consult',
            CloseDate = Date.today().addDays(30),
            Amount = 7000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp.RecordTypeId = payrollRtId;
        insert opp;
    }

    // ─── Helpers ────────────────────────────────────────────────────

    private static Opportunity getTestOpp() {
        return [SELECT Id, AccountId, OwnerId, Name, Account.Name FROM Opportunity
                WHERE Account.Name = 'TDActivity Test Account' LIMIT 1];
    }

    private static Integer tdIdCounter = 0;
    private static String nextTalkdeskId() {
        tdIdCounter++;
        return 'TEST-TD-' + String.valueOf(Datetime.now().getTime()) + '-' + tdIdCounter;
    }

    // ─── Insert with Opp Link → Publishes Event ─────────────────────

    @isTest
    static void testInsertWithOppLink_PublishesEvent() {
        Opportunity opp = getTestOpp();

        NbaTriggerContext.resetAll();

        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Opportunity__c = opp.Id,
            talkdesk__Type__c = 'Outbound',
            talkdesk__Notes__c = 'Discussed premium tier pricing. Follow up next week.'
        );

        Test.startTest();
        insert ta;
        Test.stopTest();

        List<Call_Completed_Event__e> events = NbaTalkdeskActivityTriggerHandler.lastPublishedEvents;

        System.assertNotEquals(null, events, 'Should have published events');
        System.assertEquals(1, events.size(), 'Should publish 1 event');

        Call_Completed_Event__e evt = events[0];
        System.assertEquals(String.valueOf(opp.Id), evt.Opportunity_Id__c, 'Opp ID should match');
        System.assertEquals(String.valueOf(ta.Id), evt.Activity_Id__c, 'Activity ID should match');
        System.assertEquals(String.valueOf(opp.OwnerId), evt.Sales_Rep_Id__c, 'Sales Rep should match Opp owner');
        System.assertEquals(opp.Account.Name, evt.Account_Name__c, 'Account name should match');
        System.assertEquals(opp.Name, evt.Opp_Name__c, 'Opp name should match');
    }

    // ─── Insert without Opp Link → No Event ────────────────────────

    @isTest
    static void testInsertWithoutOppLink_NoEvent() {
        NbaTriggerContext.resetAll();
        NbaTalkdeskActivityTriggerHandler.lastPublishedEvents = null;

        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Type__c = 'Outbound',
            talkdesk__Notes__c = 'General call, no opp.'
        );

        Test.startTest();
        insert ta;
        Test.stopTest();

        List<Call_Completed_Event__e> events = NbaTalkdeskActivityTriggerHandler.lastPublishedEvents;
        System.assertEquals(null, events, 'Should NOT publish events when no Opp linked');
    }

    // ─── Update: Add Opp Link → Publishes Event ────────────────────

    @isTest
    static void testUpdateNewOppLink_PublishesEvent() {
        Opportunity opp = getTestOpp();

        NbaTriggerContext.resetAll();

        // Insert without Opp
        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Type__c = 'Outbound',
            talkdesk__Notes__c = 'Call notes added later.'
        );
        insert ta;

        // Reset recursion guard and clear published events for the update trigger
        NbaTriggerContext.resetAll();
        NbaTalkdeskActivityTriggerHandler.lastPublishedEvents = null;

        // Update to add Opp link
        ta.talkdesk__Opportunity__c = opp.Id;

        Test.startTest();
        update ta;
        Test.stopTest();

        List<Call_Completed_Event__e> events = NbaTalkdeskActivityTriggerHandler.lastPublishedEvents;

        System.assertNotEquals(null, events, 'Should have published events on Opp link update');
        System.assertEquals(1, events.size(), 'Should publish 1 event');
        System.assertEquals(String.valueOf(opp.Id), events[0].Opportunity_Id__c, 'Opp ID should match');
    }

    // ─── Bulk Test ──────────────────────────────────────────────────

    @isTest
    static void testBulk_PublishesEvents() {
        Opportunity opp = getTestOpp();

        // Create a second account + opp (one Payroll opp per account validation)
        Account acc2 = new Account(Name = 'TDA Bulk Account', Entity_ID__c = 'TDA-BULK');
        insert acc2;

        Id payrollRtId;
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll'
            LIMIT 1
        ];
        if (!rts.isEmpty()) payrollRtId = rts[0].Id;

        Opportunity opp2 = new Opportunity(
            Name = 'TDA Bulk Opp', AccountId = acc2.Id,
            StageName = 'Consult', CloseDate = Date.today().addDays(30),
            Amount = 3000, Source__c = 'N/A'
        );
        if (payrollRtId != null) opp2.RecordTypeId = payrollRtId;
        insert opp2;

        NbaTriggerContext.resetAll();

        // Alternate between two opps to create bulk activities
        List<talkdesk__Talkdesk_Activity__c> activities = new List<talkdesk__Talkdesk_Activity__c>();
        for (Integer i = 0; i < 200; i++) {
            activities.add(new talkdesk__Talkdesk_Activity__c(
                talkdesk__Talkdesk_Id__c = 'BULK-' + String.valueOf(Datetime.now().getTime()) + '-' + i,
                talkdesk__Opportunity__c = Math.mod(i, 2) == 0 ? opp.Id : opp2.Id,
                talkdesk__Type__c = 'Outbound',
                talkdesk__Notes__c = 'Bulk call note ' + i
            ));
        }

        Test.startTest();
        insert activities;
        Test.stopTest();

        List<Call_Completed_Event__e> events = NbaTalkdeskActivityTriggerHandler.lastPublishedEvents;

        System.assertNotEquals(null, events, 'Should have published events');
        System.assertEquals(200, events.size(), 'Should publish 200 events for 200 activities');
    }

    // ─── Cache Invalidation ─────────────────────────────────────────

    @isTest
    static void testCacheInvalidation() {
        Opportunity opp = getTestOpp();
        Id userId = opp.OwnerId;

        // Pre-populate cache
        NbaActionController.ActionWrapper cached = new NbaActionController.ActionWrapper();
        cached.actionType = 'Stale Action';
        cached.status = 'Evaluated';
        NbaCacheService.cacheAction(userId, cached);

        // Verify cache is populated
        NbaActionController.ActionWrapper before = NbaCacheService.getCachedAction(userId);
        System.assertNotEquals(null, before, 'Cache should be populated before trigger');

        NbaTriggerContext.resetAll();

        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Opportunity__c = opp.Id,
            talkdesk__Type__c = 'Outbound',
            talkdesk__Notes__c = 'Cache invalidation test.'
        );

        Test.startTest();
        insert ta;
        Test.stopTest();

        // Cache should be invalidated
        NbaActionController.ActionWrapper after = NbaCacheService.getCachedAction(userId);
        System.assertEquals(null, after,
            'Cache should be invalidated after Talkdesk Activity insert');
    }
}
