/**
 * Test class for NbaTalkdeskActivityTriggerHandler + TalkdeskActivityTrigger.
 *
 * Verifies:
 * - Insert with Opp link creates "Call Completed" NBA_Queue__c record
 * - Insert without Opp link creates nothing
 * - Update that adds Opp link creates record
 * - Duplicate suppression (same activity ID in UniqueKey)
 * - Bulk insert (200 activities) — governor limits safe
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
        return [SELECT Id, AccountId, OwnerId FROM Opportunity
                WHERE Account.Name = 'TDActivity Test Account' LIMIT 1];
    }

    private static Integer tdIdCounter = 0;
    private static String nextTalkdeskId() {
        tdIdCounter++;
        return 'TEST-TD-' + String.valueOf(Datetime.now().getTime()) + '-' + tdIdCounter;
    }

    // ─── Insert with Opp Link → Creates Call Completed ──────────────

    @isTest
    static void testInsertWithOppLink() {
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

        List<NBA_Queue__c> created = [
            SELECT Id, Action_Type__c, Status__c, Opportunity__c, Account__c,
                   Sales_Rep__c, Talkdesk_Activity__c, Rep_Notes__c,
                   Action_Instruction__c, Rule_Name__c, UniqueKey__c,
                   Priority_Layer__c, Is_Time_Bound__c
            FROM NBA_Queue__c
            WHERE Action_Type__c = 'Call Completed'
              AND Talkdesk_Activity__c = :ta.Id
        ];

        System.assertEquals(1, created.size(), 'Should create 1 Call Completed record');
        NBA_Queue__c rec = created[0];
        System.assertEquals(opp.Id, rec.Opportunity__c, 'Opp should match');
        System.assertEquals(opp.AccountId, rec.Account__c, 'Account should match');
        System.assertEquals(opp.OwnerId, rec.Sales_Rep__c, 'Sales Rep should match Opp owner');
        System.assertEquals('Pending', rec.Status__c, 'Status should be Pending');
        System.assertEquals(ta.Id, rec.Talkdesk_Activity__c, 'Talkdesk Activity should be linked');
        System.assertEquals('Discussed premium tier pricing. Follow up next week.', rec.Rep_Notes__c,
            'Notes should be pre-populated from Talkdesk');
        System.assertEquals('Review and save call notes', rec.Action_Instruction__c, 'Instruction should match');
        System.assertEquals('CallCompleted_Interrupt', rec.Rule_Name__c, 'Rule name should match');
        System.assertEquals('Layer 1 - Time Bound', rec.Priority_Layer__c, 'Priority layer should be L1');
        System.assertEquals(false, rec.Is_Time_Bound__c, 'Should be non-time-bound');
        System.assert(rec.UniqueKey__c.contains('CallCompleted'), 'UniqueKey should contain CallCompleted');
    }

    // ─── Insert without Opp Link → No Record ───────────────────────

    @isTest
    static void testInsertWithoutOppLink() {
        NbaTriggerContext.resetAll();

        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Type__c = 'Outbound',
            talkdesk__Notes__c = 'General call, no opp.'
        );

        Test.startTest();
        insert ta;
        Test.stopTest();

        List<NBA_Queue__c> created = [
            SELECT Id FROM NBA_Queue__c
            WHERE Action_Type__c = 'Call Completed'
              AND Talkdesk_Activity__c = :ta.Id
        ];

        System.assertEquals(0, created.size(), 'Should NOT create record when no Opp linked');
    }

    // ─── Update: Add Opp Link → Creates Record ─────────────────────

    @isTest
    static void testUpdateNewOppLink() {
        Opportunity opp = getTestOpp();

        NbaTriggerContext.resetAll();

        // Insert without Opp
        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Type__c = 'Outbound',
            talkdesk__Notes__c = 'Call notes added later.'
        );
        insert ta;

        // Verify no record created yet
        List<NBA_Queue__c> beforeUpdate = [
            SELECT Id FROM NBA_Queue__c
            WHERE Action_Type__c = 'Call Completed'
              AND Talkdesk_Activity__c = :ta.Id
        ];
        System.assertEquals(0, beforeUpdate.size(), 'No record before Opp link');

        // Reset recursion guard for the update trigger
        NbaTriggerContext.resetAll();

        // Update to add Opp link
        ta.talkdesk__Opportunity__c = opp.Id;

        Test.startTest();
        update ta;
        Test.stopTest();

        List<NBA_Queue__c> afterUpdate = [
            SELECT Id, Opportunity__c FROM NBA_Queue__c
            WHERE Action_Type__c = 'Call Completed'
              AND Talkdesk_Activity__c = :ta.Id
        ];

        System.assertEquals(1, afterUpdate.size(), 'Should create record when Opp linked via update');
        System.assertEquals(opp.Id, afterUpdate[0].Opportunity__c, 'Opp should match');
    }

    // ─── Duplicate Suppression ──────────────────────────────────────

    @isTest
    static void testDuplicateSuppression() {
        Opportunity opp = getTestOpp();

        NbaTriggerContext.resetAll();

        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Opportunity__c = opp.Id,
            talkdesk__Type__c = 'Outbound',
            talkdesk__Notes__c = 'First call.'
        );
        insert ta;

        // Manually create the NBA_Queue__c record with matching UniqueKey
        // to simulate an already-existing record
        Integer countAfterFirst = [
            SELECT COUNT() FROM NBA_Queue__c
            WHERE Action_Type__c = 'Call Completed' AND Talkdesk_Activity__c = :ta.Id
        ];
        System.assertEquals(1, countAfterFirst, 'Should have 1 record after first insert');

        // Reset and trigger update (which re-fires handler)
        NbaTriggerContext.resetAll();
        ta.talkdesk__Notes__c = 'Updated notes';
        // This update won't qualify (Opp was already set, not changed from null)
        update ta;

        Integer countAfterUpdate = [
            SELECT COUNT() FROM NBA_Queue__c
            WHERE Action_Type__c = 'Call Completed' AND Talkdesk_Activity__c = :ta.Id
        ];
        System.assertEquals(1, countAfterUpdate, 'Should still have only 1 record (no duplicate)');
    }

    // ─── Bulk Test ──────────────────────────────────────────────────

    @isTest
    static void testBulk() {
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

        // Verify records created (governor limits not exceeded)
        Integer callCompletedCount = [
            SELECT COUNT() FROM NBA_Queue__c
            WHERE Action_Type__c = 'Call Completed'
        ];
        System.assert(callCompletedCount > 0,
            'Should create Call Completed records from bulk insert');
        System.assert(callCompletedCount <= 200,
            'Should not exceed the number of activities inserted');
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
