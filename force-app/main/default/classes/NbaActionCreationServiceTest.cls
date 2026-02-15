/**
 * Test class for NbaActionCreationService.
 * Verifies rule evaluation, suppression logic, scoring, bucket/layer assignment,
 * and candidate action creation.
 */
@isTest
private class NbaActionCreationServiceTest {

    @TestSetup
    static void setupData() {
        // Separate accounts per Opp to avoid "only one open Payroll Opp" validation rule
        List<Account> accs = new List<Account>();
        for (Integer i = 1; i <= 4; i++) {
            accs.add(new Account(
                Name = 'Creation Test Account ' + i,
                Employee_Count__c = 40,
                Entity_ID__c = 'CRE-TEST-00' + i
            ));
        }
        insert accs;

        Account_Scoring__c scoring = new Account_Scoring__c(
            Account__c = accs[0].Id,
            Entity_ID__c = 'CRE-TEST-001',
            Prob_Payroll_Conversion__c = 75,
            Prob_Tier_Upgrade__c = 50
        );
        insert scoring;

        Id payrollRtId;
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll'
            LIMIT 1
        ];
        if (!rts.isEmpty()) {
            payrollRtId = rts[0].Id;
        }

        // Opp 1: "New" stage — no activities → First Touch
        Opportunity opp1 = new Opportunity(
            Name = 'First Touch Opp',
            AccountId = accs[0].Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 8000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp1.RecordTypeId = payrollRtId;

        // Opp 2: "Closing" stage — will simulate inactivity via signal
        Opportunity opp2 = new Opportunity(
            Name = 'Late Stage Opp',
            AccountId = accs[1].Id,
            StageName = 'Closing',
            CloseDate = Date.today().addDays(15),
            Amount = 12000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp2.RecordTypeId = payrollRtId;

        // Opp 3: "Connect" stage — will simulate 7 days inactivity → Re-engage
        Opportunity opp3 = new Opportunity(
            Name = 'Cold Opp',
            AccountId = accs[2].Id,
            StageName = 'Connect',
            CloseDate = Date.today().addDays(45),
            Amount = 3000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp3.RecordTypeId = payrollRtId;

        // Opp 4: Closed Won — should be suppressed
        Opportunity opp4 = new Opportunity(
            Name = 'Won Opp',
            AccountId = accs[3].Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Amount = 5000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp4.RecordTypeId = payrollRtId;

        insert new List<Opportunity>{ opp1, opp2, opp3, opp4 };
    }

    // ─── Helper: Build signal with defaults ───────────────────────────

    private static NbaSignalService.OpportunitySignal buildSignal(
        Opportunity opp, Decimal daysSinceInteraction
    ) {
        NbaSignalService.OpportunitySignal sig = new NbaSignalService.OpportunitySignal();
        sig.oppId = opp.Id;
        sig.accountId = opp.AccountId;
        sig.ownerId = opp.OwnerId;
        sig.stageName = opp.StageName;
        sig.stageNumber = NbaSignalService.getStageNumber(opp.StageName);
        sig.mrr = opp.Amount;
        sig.amount = opp.Amount;
        sig.dealStageProbability = 50;
        sig.daysSinceLastInteraction = daysSinceInteraction;
        sig.isClosed = opp.IsClosed;
        sig.hasAccountScoring = true;
        sig.probPayrollConversion = 75;
        sig.probTierUpgrade = 50;
        return sig;
    }

    // ─── Action Type Tests ────────────────────────────────────────────

    @isTest
    static void testEvaluateAndCreate_FirstTouch() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 99999);
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        System.assertEquals(1, result.createdCount, 'Should create 1 action');
        System.assertEquals(0, result.suppressedCount, 'Nothing should be suppressed');
        NBA_Queue__c action = result.actionsToCreate[0];
        System.assertEquals('First Touch', action.Action_Type__c, 'Action type should be First Touch');
        System.assertEquals('Pending', action.Status__c, 'Status should be Pending');
        System.assertNotEquals(null, action.Impact_Score__c, 'Impact score should be set');
        System.assertNotEquals(null, action.Urgency_Score__c, 'Urgency score should be set');
        System.assertNotEquals(null, action.Priority_Score__c, 'Priority score should be set');
        System.assertNotEquals(null, action.Priority_Bucket__c, 'Bucket should be set');
        System.assertNotEquals(null, action.Priority_Layer__c, 'Layer should be set');
        System.assertEquals('Pipeline', action.Workflow_Mode__c, 'Mode should be Pipeline');
        System.assertEquals('Pipeline Cadence', action.Source_Path__c, 'Source path should be Pipeline Cadence');
    }

    @isTest
    static void testEvaluateAndCreate_StageProgression() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 2'
            AND StageName = 'Closing' LIMIT 1
        ];

        // Late-stage (Closing=4) with 5 days inactivity
        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 5);

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        System.assertEquals(1, result.createdCount, 'Should create 1 action');
        NBA_Queue__c action = result.actionsToCreate[0];
        System.assertEquals('Stage Progression', action.Action_Type__c,
            'Action type should be Stage Progression for late-stage inactivity');
        System.assertEquals('Late-Stage Stalled', action.Priority_Bucket__c,
            'Bucket should be Late-Stage Stalled');
    }

    @isTest
    static void testEvaluateAndCreate_Reengage() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 3'
            AND StageName = 'Connect' LIMIT 1
        ];

        // Connect stage (2) with 7 days inactivity → Re-engage
        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 7);

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        System.assertEquals(1, result.createdCount, 'Should create 1 action');
        NBA_Queue__c action = result.actionsToCreate[0];
        System.assertEquals('Re-engage', action.Action_Type__c,
            'Action type should be Re-engage for cold deal');
    }

    // ─── Suppression Tests ────────────────────────────────────────────

    @isTest
    static void testSuppression_ClosedOpp() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 4'
            AND IsClosed = true LIMIT 1
        ];

        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 10);

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        System.assertEquals(0, result.createdCount, 'Closed opp should be suppressed');
        System.assertEquals(1, result.suppressedCount, 'Should count as suppressed');
    }

    @isTest
    static void testSuppression_ActiveActionExists() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 99999);
        sig.hasActiveAction = true;
        sig.existingActiveActions = new List<NBA_Queue__c>{
            new NBA_Queue__c(Status__c = 'In Progress')
        };

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        System.assertEquals(0, result.createdCount, 'Active action should suppress creation');
        System.assertEquals(1, result.suppressedCount, 'Should count as suppressed');
    }

    @isTest
    static void testSuppression_UpcomingMeeting() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 99999);
        sig.hasUpcomingMeeting = true;
        sig.upcomingMeetingStart = Datetime.now().addHours(2);

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        System.assertEquals(0, result.createdCount, 'Upcoming meeting should suppress creation');
    }

    @isTest
    static void testSuppression_RecentTouch() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 3'
            AND StageName = 'Connect' LIMIT 1
        ];

        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 7);
        // Recent touch 1 hour ago (within 4h suppression window)
        sig.lastValidTouchDate = Datetime.now().addHours(-1);

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        System.assertEquals(0, result.createdCount, 'Recent touch should suppress creation');
    }

    // ─── Scoring Tests ────────────────────────────────────────────────

    @isTest
    static void testScoring_ImpactCalculation() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 99999);
        sig.mrr = 25000;
        sig.probPayrollConversion = 80;

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        NBA_Queue__c action = result.actionsToCreate[0];
        // Impact = (0.6 * 25000/50000) + (0.4 * 80/100) = (0.6 * 0.5) + (0.4 * 0.8) = 0.3 + 0.32 = 0.62
        System.assert(action.Impact_Score__c > 0.5 && action.Impact_Score__c < 0.8,
            'Impact score should be between 0.5 and 0.8, got: ' + action.Impact_Score__c);
        System.assert(action.Urgency_Score__c > 0,
            'Urgency score should be positive, got: ' + action.Urgency_Score__c);
        System.assert(action.Priority_Score__c > 0,
            'Priority score should be positive, got: ' + action.Priority_Score__c);
    }

    // ─── Bucket Assignment Tests ──────────────────────────────────────

    @isTest
    static void testBucketAssignment_GeneralPipeline() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 3'
            AND StageName = 'Connect' LIMIT 1
        ];

        // Connect stage, 2 days inactivity, low impact → General Pipeline
        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 2);
        sig.mrr = 1000;
        sig.probPayrollConversion = 20;

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        // With 2 days inactivity and Connect stage, this is a Follow Up
        NBA_Queue__c action = result.actionsToCreate[0];
        System.assertEquals('Follow Up', action.Action_Type__c, 'Should be Follow Up');
        System.assertEquals('General Pipeline', action.Priority_Bucket__c,
            'Low-impact early-stage should be General Pipeline');
    }

    @isTest
    static void testBucketAssignment_Neglected() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 3'
            AND StageName = 'Connect' LIMIT 1
        ];

        // Connect stage, 8 days inactivity, low MRR → Neglected
        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 8);
        sig.mrr = 500;
        sig.probPayrollConversion = 15;

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        NBA_Queue__c action = result.actionsToCreate[0];
        System.assertEquals('Re-engage', action.Action_Type__c, 'Should be Re-engage at 8 days');
        System.assertEquals('Neglected', action.Priority_Bucket__c,
            '8 days inactivity with low impact should be Neglected');
    }

    // ─── Null/Empty Input ─────────────────────────────────────────────

    @isTest
    static void testEvaluateAndCreate_EmptyInput() {
        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(
                new Map<Id, NbaSignalService.OpportunitySignal>()
            );
        Test.stopTest();

        System.assertEquals(0, result.createdCount, 'Empty input should produce 0 actions');
    }

    @isTest
    static void testEvaluateAndCreate_NullInput() {
        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(null);
        Test.stopTest();

        System.assertEquals(0, result.createdCount, 'Null input should produce 0 actions');
    }

    // ─── Bulk Test ────────────────────────────────────────────────────

    @isTest
    static void testBulk_MultipleOpps() {
        // Use the 3 open opps from setup with varying signals
        List<Opportunity> opps = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity
            WHERE Account.Name LIKE 'Creation Test Account%' AND IsClosed = false
        ];

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>();
        for (Opportunity opp : opps) {
            Decimal inactivity = opp.StageName == 'New' ? 99999
                : (opp.StageName == 'Closing' ? 5 : 7);
            signals.put(opp.Id, buildSignal(opp, inactivity));
        }

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        System.assertEquals(3, result.createdCount,
            'Should create actions for all 3 open opps, created: ' + result.createdCount);
        System.assertEquals(0, result.suppressedCount, 'None should be suppressed');
    }

    // ─── UniqueKey Test ───────────────────────────────────────────────

    @isTest
    static void testUniqueKey_Format() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 99999);

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        NBA_Queue__c action = result.actionsToCreate[0];
        String expectedKey = 'V2|' + opp.Id + '|First Touch';
        System.assertEquals(expectedKey, action.UniqueKey__c,
            'UniqueKey should follow V2|oppId|actionType format');
    }

    // ─── Time-Bound Action Tests (Phase 4) ──────────────────────────

    @isTest
    static void testCreateTimeBoundAction_Success() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        // Block EventTrigger so it doesn't create the action before our direct test
        NbaTriggerContext.setEventHandlerRun();

        // Create an Event to use its ID for the unique key
        Event evt = new Event(
            WhatId = opp.Id,
            Subject = 'Test Meeting',
            StartDateTime = Datetime.now().addHours(2),
            EndDateTime = Datetime.now().addHours(3)
        );
        insert evt;

        Test.startTest();
        NBA_Queue__c action = NbaActionCreationService.createTimeBoundAction(
            opp.Id, opp.AccountId, opp.OwnerId,
            Datetime.now().addHours(2), evt.Id,
            'Review context before demo meeting'
        );
        Test.stopTest();

        System.assertNotEquals(null, action, 'Should create a time-bound action');
        System.assertEquals('Meeting', action.Action_Type__c, 'Type should be Meeting');
        System.assertEquals('Layer 1 - Time Bound', action.Priority_Layer__c, 'Layer should be Layer 1');
        System.assertEquals(true, action.Is_Time_Bound__c, 'Should be time-bound');
        System.assertEquals('Immediate', action.Source_Path__c, 'Source should be Immediate');
        System.assertEquals('Pending', action.Status__c, 'Status should be Pending');
        System.assertNotEquals(null, action.DueAt__c, 'DueAt should be set');
        System.assert(action.UniqueKey__c.contains('Meeting'), 'UniqueKey should contain Meeting');
    }

    @isTest
    static void testCreateTimeBoundAction_DuplicatePrevented() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        NbaTriggerContext.setEventHandlerRun();

        Event evt = new Event(
            WhatId = opp.Id,
            Subject = 'Dup Test Meeting',
            StartDateTime = Datetime.now().addHours(3),
            EndDateTime = Datetime.now().addHours(4)
        );
        insert evt;

        // Create first action and insert it
        NBA_Queue__c first = NbaActionCreationService.createTimeBoundAction(
            opp.Id, opp.AccountId, opp.OwnerId,
            Datetime.now().addHours(3), evt.Id, 'First'
        );
        insert first;

        Test.startTest();
        // Second call with same event → should return null (duplicate)
        NBA_Queue__c second = NbaActionCreationService.createTimeBoundAction(
            opp.Id, opp.AccountId, opp.OwnerId,
            Datetime.now().addHours(3), evt.Id, 'Duplicate'
        );
        Test.stopTest();

        System.assertEquals(null, second, 'Duplicate should return null');
    }

    @isTest
    static void testUpdateTimeBoundAction_ReschedulesMeeting() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        NbaTriggerContext.setEventHandlerRun();

        Event evt = new Event(
            WhatId = opp.Id,
            Subject = 'Reschedule Test',
            StartDateTime = Datetime.now().addHours(2),
            EndDateTime = Datetime.now().addHours(3)
        );
        insert evt;

        NBA_Queue__c action = NbaActionCreationService.createTimeBoundAction(
            opp.Id, opp.AccountId, opp.OwnerId,
            Datetime.now().addHours(2), evt.Id, 'Original time'
        );
        insert action;

        Datetime newTime = Datetime.now().addHours(5);
        Test.startTest();
        NBA_Queue__c updated = NbaActionCreationService.updateTimeBoundAction(
            evt.Id, opp.Id, newTime
        );
        Test.stopTest();

        System.assertNotEquals(null, updated, 'Should find the action to update');
        System.assertEquals(newTime, updated.DueAt__c, 'DueAt should be updated');
    }

    @isTest
    static void testCancelTimeBoundAction_ExpiresMeetingAction() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        NbaTriggerContext.setEventHandlerRun();

        Event evt = new Event(
            WhatId = opp.Id,
            Subject = 'Cancel Test',
            StartDateTime = Datetime.now().addHours(2),
            EndDateTime = Datetime.now().addHours(3)
        );
        insert evt;

        NBA_Queue__c action = NbaActionCreationService.createTimeBoundAction(
            opp.Id, opp.AccountId, opp.OwnerId,
            Datetime.now().addHours(2), evt.Id, 'Will be cancelled'
        );
        insert action;

        Test.startTest();
        NBA_Queue__c cancelled = NbaActionCreationService.cancelTimeBoundAction(evt.Id, opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, cancelled, 'Should find the action to cancel');
        System.assertEquals('Expired', cancelled.Status__c, 'Status should be Expired');
        System.assertEquals(null, cancelled.UniqueKey__c, 'UniqueKey should be cleared');
    }

    @isTest
    static void testCancelTimeBoundAction_NoMatchReturnsNull() {
        Opportunity opp = [
            SELECT Id FROM Opportunity
            WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        // Use a fake event ID — no matching action exists
        Id fakeEventId = opp.Id; // reuse an ID just to have a valid one for the query
        Test.startTest();
        NBA_Queue__c result = NbaActionCreationService.cancelTimeBoundAction(fakeEventId, opp.Id);
        Test.stopTest();

        System.assertEquals(null, result, 'No matching action should return null');
    }
}
