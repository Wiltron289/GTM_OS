/**
 * Test class for NbaSignalService.
 * Verifies CRM signal detection across Talkdesk, SMS, Events, Tasks,
 * Account Scoring, and existing NBA_Queue__c actions.
 */
@isTest
private class NbaSignalServiceTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'Signal Test Account',
            Employee_Count__c = 25,
            Active_Location_Count__c = 2,
            Entity_ID__c = 'SIG-TEST-001'
        );
        insert acc;

        Account_Scoring__c scoring = new Account_Scoring__c(
            Account__c = acc.Id,
            Entity_ID__c = 'SIG-TEST-001',
            Prob_Payroll_Conversion__c = 80,
            Prob_Tier_Upgrade__c = 55
        );
        insert scoring;

        // Opportunity with Payroll record type if available
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
            Name = 'Signal Test Opp',
            AccountId = acc.Id,
            StageName = 'Consult',
            CloseDate = Date.today().addDays(30),
            Amount = 5000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) {
            opp.RecordTypeId = payrollRtId;
        }
        insert opp;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Signal',
            AccountId = acc.Id,
            Email = 'test.signal@example.com',
            Phone = '555-0300',
            Mogli_SMS__Mogli_Number__c = '+15550300'
        );
        insert con;

        // Task linked to Opp
        Task t = new Task(
            Subject = 'Call - Signal Test',
            WhatId = opp.Id,
            WhoId = con.Id,
            Status = 'Completed',
            ActivityDate = Date.today().addDays(-1),
            TaskSubtype = 'Call'
        );
        insert t;

        // Event (upcoming meeting in 2 hours)
        Event ev = new Event(
            Subject = 'Signal Test Meeting',
            WhatId = opp.Id,
            WhoId = con.Id,
            StartDateTime = Datetime.now().addHours(2),
            EndDateTime = Datetime.now().addHours(3)
        );
        insert ev;

        // NBA_Queue__c for existing action dedup
        NBA_Queue__c existingAction = new NBA_Queue__c(
            Opportunity__c = opp.Id,
            Account__c = acc.Id,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'In Progress',
            Action_Type__c = 'Follow Up',
            Priority_Score__c = 0.75
        );
        insert existingAction;
    }

    // ─── getSignals Tests ─────────────────────────────────────────────

    @isTest
    static void testGetSignals_FullData() {
        Opportunity opp = [
            SELECT Id FROM Opportunity
            WHERE Account.Name = 'Signal Test Account' AND StageName = 'Consult'
            LIMIT 1
        ];

        Test.startTest();
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            NbaSignalService.getSignals(new Set<Id>{ opp.Id });
        Test.stopTest();

        System.assertEquals(1, signals.size(), 'Should return exactly 1 signal');

        NbaSignalService.OpportunitySignal sig = signals.get(opp.Id);
        System.assertNotEquals(null, sig, 'Signal should not be null');
        System.assertEquals('Consult', sig.stageName, 'Stage should be Consult');
        System.assertEquals(3, sig.stageNumber, 'Consult maps to stage 3');
        System.assertEquals(5000, sig.amount, 'Amount should be 5000');

        // Task signal
        System.assertNotEquals(null, sig.lastTaskDate, 'Should have a task date');
        System.assertEquals('Call', sig.lastTaskSubtype, 'Task subtype should be Call');

        // Meeting signal
        System.assertEquals(true, sig.hasUpcomingMeeting, 'Should detect upcoming meeting');
        System.assertNotEquals(null, sig.upcomingMeetingStart, 'Meeting start should be set');

        // Account scoring
        System.assertEquals(true, sig.hasAccountScoring, 'Should have account scoring');
        System.assertEquals(80, sig.probPayrollConversion, 'Prob Payroll Conversion should be 80');
        System.assertEquals(55, sig.probTierUpgrade, 'Prob Tier Upgrade should be 55');

        // Existing action dedup
        System.assertEquals(true, sig.hasActiveAction, 'Should detect existing active action');
        System.assertEquals(1, sig.existingActiveActions.size(), 'Should have 1 active action');

        // Computed fields
        System.assertNotEquals(null, sig.lastValidTouchDate, 'Last valid touch should be computed');
        System.assertNotEquals(null, sig.ownerId, 'Owner should be set');
        System.assertNotEquals(null, sig.accountId, 'Account should be set');
    }

    @isTest
    static void testGetSignals_NoAccountScoring() {
        // Create Opp on Account without scoring
        Account acc2 = new Account(Name = 'No Scoring Account', Entity_ID__c = 'NO-SCORE-001');
        insert acc2;

        Opportunity opp2 = new Opportunity(
            Name = 'No Scoring Opp',
            AccountId = acc2.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 2000,
            Source__c = 'N/A'
        );
        insert opp2;

        Test.startTest();
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            NbaSignalService.getSignals(new Set<Id>{ opp2.Id });
        Test.stopTest();

        NbaSignalService.OpportunitySignal sig = signals.get(opp2.Id);
        System.assertNotEquals(null, sig, 'Signal should exist');
        System.assertEquals(false, sig.hasAccountScoring, 'Should not have account scoring');
        System.assertEquals(null, sig.probPayrollConversion, 'Prob should be null');
    }

    @isTest
    static void testGetSignals_NoUpcomingMeeting() {
        Account acc3 = new Account(Name = 'No Meeting Account', Entity_ID__c = 'NO-MTG-001');
        insert acc3;

        Opportunity opp3 = new Opportunity(
            Name = 'No Meeting Opp',
            AccountId = acc3.Id,
            StageName = 'Connect',
            CloseDate = Date.today().addDays(30),
            Amount = 3000,
            Source__c = 'N/A'
        );
        insert opp3;

        Test.startTest();
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            NbaSignalService.getSignals(new Set<Id>{ opp3.Id });
        Test.stopTest();

        NbaSignalService.OpportunitySignal sig = signals.get(opp3.Id);
        System.assertEquals(false, sig.hasUpcomingMeeting, 'No upcoming meeting expected');
        System.assertEquals(false, sig.hasActiveAction, 'No active action expected');
    }

    @isTest
    static void testGetSignals_ExistingActiveAction() {
        Opportunity opp = [
            SELECT Id FROM Opportunity
            WHERE Account.Name = 'Signal Test Account' AND StageName = 'Consult'
            LIMIT 1
        ];

        Test.startTest();
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            NbaSignalService.getSignals(new Set<Id>{ opp.Id });
        Test.stopTest();

        NbaSignalService.OpportunitySignal sig = signals.get(opp.Id);
        System.assertEquals(true, sig.hasActiveAction, 'Should have active action');
        System.assertEquals('Follow Up', sig.existingActiveActions[0].Action_Type__c,
            'Active action type should be Follow Up');
    }

    @isTest
    static void testGetSignals_EmptySet() {
        Test.startTest();
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            NbaSignalService.getSignals(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, signals.size(), 'Empty input should return empty map');
    }

    @isTest
    static void testGetSignals_NullInput() {
        Test.startTest();
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            NbaSignalService.getSignals(null);
        Test.stopTest();

        System.assertEquals(0, signals.size(), 'Null input should return empty map');
    }

    @isTest
    static void testGetSignals_BulkTwoHundredOpps() {
        Account bulkAcc = new Account(Name = 'Bulk Test Account', Entity_ID__c = 'BULK-001');
        insert bulkAcc;

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            opps.add(new Opportunity(
                Name = 'Bulk Opp ' + i,
                AccountId = bulkAcc.Id,
                StageName = 'New',
                CloseDate = Date.today().addDays(30),
                Amount = 1000 + i,
                Source__c = 'N/A'
            ));
        }
        insert opps;

        Set<Id> oppIds = new Set<Id>();
        for (Opportunity o : opps) {
            oppIds.add(o.Id);
        }

        Test.startTest();
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            NbaSignalService.getSignals(oppIds);
        Test.stopTest();

        System.assertEquals(200, signals.size(), 'Should return signals for all 200 opps');
        System.assert(Limits.getQueries() < 100,
            'Should stay under 100 SOQL queries, used: ' + Limits.getQueries());
    }

    // ─── Stage Mapping Tests ──────────────────────────────────────────

    @isTest
    static void testGetStageNumber_AllStages() {
        System.assertEquals(1, NbaSignalService.getStageNumber('New'), 'New = 1');
        System.assertEquals(2, NbaSignalService.getStageNumber('Connect'), 'Connect = 2');
        System.assertEquals(3, NbaSignalService.getStageNumber('Consult'), 'Consult = 3');
        System.assertEquals(3, NbaSignalService.getStageNumber('Evaluating'), 'Evaluating = 3');
        System.assertEquals(4, NbaSignalService.getStageNumber('Closing'), 'Closing = 4');
        System.assertEquals(5, NbaSignalService.getStageNumber('Verbal Commit'), 'Verbal Commit = 5');
        System.assertEquals(5, NbaSignalService.getStageNumber('Ready to Convert'), 'Ready to Convert = 5');
        System.assertEquals(0, NbaSignalService.getStageNumber('Hand-Off'), 'Hand-Off = 0');
        System.assertEquals(1, NbaSignalService.getStageNumber('Unknown Stage'), 'Unknown defaults to 1');
        System.assertEquals(1, NbaSignalService.getStageNumber(null), 'Null defaults to 1');
    }
}
