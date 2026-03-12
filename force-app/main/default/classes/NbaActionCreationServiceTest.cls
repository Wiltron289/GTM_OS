/**
 * Test class for NbaActionCreationService.
 * Verifies rule evaluation, suppression logic, Expected Incremental ARR scoring,
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

        // Account scoring with new LTW and IIW fields
        Account_Scoring__c scoring = new Account_Scoring__c(
            Account__c = accs[0].Id,
            Entity_ID__c = 'CRE-TEST-001',
            Prob_Payroll_Conversion__c = 75,
            Prob_Tier_Upgrade__c = 50,
            Likelihood_To_Win__c = 0.60,
            Incremental_If_Won__c = 5000
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
        sig.hasAccountScoring = false;
        return sig;
    }

    private static NbaSignalService.OpportunitySignal buildSignalWithScoring(
        Opportunity opp, Decimal daysSinceInteraction,
        Decimal ltw, Decimal iiw
    ) {
        NbaSignalService.OpportunitySignal sig = buildSignal(opp, daysSinceInteraction);
        sig.hasAccountScoring = true;
        sig.likelihoodToWin = ltw;
        sig.incrementalIfWon = iiw;
        sig.probPayrollConversion = ltw != null ? ltw * 100 : null;
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

        NbaSignalService.OpportunitySignal sig = buildSignalWithScoring(opp, 99999, 0.60, 5000);
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
        System.assertNotEquals(null, action.Expected_Incremental_ARR__c, 'Expected ARR should be set');
        System.assertNotEquals(null, action.Stage_Priority__c, 'Stage priority should be set');
        System.assertEquals(action.Expected_Incremental_ARR__c, action.Priority_Score__c,
            'Priority score should equal Expected ARR');
        System.assertEquals('Pipeline', action.Workflow_Mode__c, 'Mode should be Pipeline');
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

    // ─── Expected Incremental ARR Scoring Tests ───────────────────────

    @isTest
    static void testScoring_WithAccountScoringData() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        // LTW=0.60, IIW=5000, attempt 1 connect rate=0.13
        NbaSignalService.OpportunitySignal sig = buildSignalWithScoring(opp, 99999, 0.60, 5000);

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        NBA_Queue__c action = result.actionsToCreate[0];
        // Expected ARR = 0.60 × 5000 × 0.13 = 390.00
        System.assert(action.Expected_Incremental_ARR__c > 350 && action.Expected_Incremental_ARR__c < 450,
            'Expected ARR should be ~390 (LTW×IIW×CR), got: ' + action.Expected_Incremental_ARR__c);
    }

    @isTest
    static void testScoring_FallbackWhenNoAccountScoring() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 2'
            AND StageName = 'Closing' LIMIT 1
        ];

        // No account scoring — should fall back to stage probability + Amount
        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 5);
        sig.hasAccountScoring = false;

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        NBA_Queue__c action = result.actionsToCreate[0];
        // Fallback: LTW=0.75 (Closing stage), IIW=12000 (Amount), CR=0.13 (attempt 1)
        // Expected = 0.75 × 12000 × 0.13 = 1170.00
        System.assert(action.Expected_Incremental_ARR__c > 1000,
            'Fallback scoring should use stage probability × Amount × connect rate, got: '
            + action.Expected_Incremental_ARR__c);
    }

    @isTest
    static void testScoring_FallbackWithNullLtwUsesProb() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        // Account scoring exists but LTW is null — should fall back to probPayrollConversion
        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 99999);
        sig.hasAccountScoring = true;
        sig.likelihoodToWin = null;
        sig.probPayrollConversion = 80;
        sig.incrementalIfWon = 3000;

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        NBA_Queue__c action = result.actionsToCreate[0];
        // LTW = 80/100 = 0.80, IIW = 3000, CR = 0.13
        // Expected = 0.80 × 3000 × 0.13 = 312.00
        System.assert(action.Expected_Incremental_ARR__c > 280 && action.Expected_Incremental_ARR__c < 350,
            'Should use probPayrollConversion as LTW fallback, got: '
            + action.Expected_Incremental_ARR__c);
    }

    @isTest
    static void testScoring_ConnectRateDecreases() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        // Attempt 1 vs attempt 5 — connect rate should decrease
        NbaSignalService.OpportunitySignal sig1 = buildSignalWithScoring(opp, 99999, 0.50, 10000);
        sig1.lastCadenceStepNumber = null; // attempt 1 (default)

        NbaSignalService.OpportunitySignal sig5 = buildSignalWithScoring(opp, 99999, 0.50, 10000);
        sig5.lastCadenceStepNumber = 4; // attempt 5 (4+1)

        // Calculate directly using the @TestVisible method
        Test.startTest();
        Decimal arr1 = NbaActionCreationService.calculateExpectedArr(sig1, 1);
        Decimal arr5 = NbaActionCreationService.calculateExpectedArr(sig5, 5);
        Test.stopTest();

        System.assert(arr1 > arr5,
            'Earlier attempts should have higher Expected ARR. Attempt 1: ' + arr1 + ', Attempt 5: ' + arr5);
    }

    @isTest
    static void testScoring_ConnectRateLookup() {
        // Verify connect rate retrieval for known attempts
        Test.startTest();
        Decimal rate1 = NbaActionCreationService.getConnectRate(1);
        Decimal rate2 = NbaActionCreationService.getConnectRate(2);
        Decimal rate10 = NbaActionCreationService.getConnectRate(10);
        Decimal rate99 = NbaActionCreationService.getConnectRate(99); // caps at 10
        Test.stopTest();

        System.assertEquals(0.13, rate1, 'Attempt 1 rate should be 0.13');
        System.assertEquals(0.15, rate2, 'Attempt 2 rate should be 0.15');
        System.assertEquals(0.03, rate10, 'Attempt 10 rate should be 0.03');
        System.assertEquals(0.03, rate99, 'Attempt 99 should cap at attempt 10 rate');
    }

    @isTest
    static void testScoring_StagePriorityPopulated() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName, Amount, IsClosed
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 2'
            AND StageName = 'Closing' LIMIT 1
        ];

        NbaSignalService.OpportunitySignal sig = buildSignal(opp, 5);

        Map<Id, NbaSignalService.OpportunitySignal> signals =
            new Map<Id, NbaSignalService.OpportunitySignal>{ opp.Id => sig };

        Test.startTest();
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);
        Test.stopTest();

        NBA_Queue__c action = result.actionsToCreate[0];
        System.assertEquals(1, action.Stage_Priority__c,
            'Closing stage should have priority 1');
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

    // ─── New Assignment Interrupt Tests (Two-Stream) ────────────────

    @isTest
    static void testCreateNewAssignmentAction_Success() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        // The trigger already created a new-assignment interrupt during @TestSetup.
        // Expire it so we can test the method directly.
        List<NBA_Queue__c> existing = [
            SELECT Id FROM NBA_Queue__c
            WHERE Rule_Name__c = 'NewAssignment_Interrupt'
              AND Opportunity__c = :opp.Id
        ];
        for (NBA_Queue__c q : existing) {
            q.Status__c = 'Expired';
            q.UniqueKey__c = null;
        }
        if (!existing.isEmpty()) update existing;

        Test.startTest();
        NBA_Queue__c action = NbaActionCreationService.createNewAssignmentAction(
            opp.Id, opp.AccountId, opp.OwnerId, opp.StageName
        );
        Test.stopTest();

        System.assertNotEquals(null, action, 'Should create a new-assignment interrupt');
        System.assertEquals('First Touch', action.Action_Type__c, 'Type should be First Touch');
        System.assertEquals(true, action.Is_Time_Bound__c, 'Should be time-bound (5-min SLA)');
        System.assertEquals('Immediate', action.Source_Path__c, 'Source should be Immediate');
        System.assertEquals('Pending', action.Status__c, 'Status should be Pending');
        System.assertNotEquals(null, action.DueAt__c, 'DueAt should be set for SLA expiration');
        System.assert(action.UniqueKey__c.contains('NewAssignment'),
            'UniqueKey should contain NewAssignment');
        System.assertNotEquals(null, action.Stage_Priority__c, 'Stage priority should be set');
    }

    @isTest
    static void testCreateNewAssignmentAction_DuplicatePrevented() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId, StageName
            FROM Opportunity WHERE Account.Name = 'Creation Test Account 1'
            AND StageName = 'New' LIMIT 1
        ];

        // The trigger already created a new-assignment interrupt during @TestSetup.
        // The second call should return null (dedup).
        Test.startTest();
        NBA_Queue__c second = NbaActionCreationService.createNewAssignmentAction(
            opp.Id, opp.AccountId, opp.OwnerId, opp.StageName
        );
        Test.stopTest();

        System.assertEquals(null, second, 'Duplicate should return null');
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
            Datetime.now().addHours(2), Datetime.now().addHours(3), evt.Id,
            'Review context before demo meeting'
        );
        Test.stopTest();

        System.assertNotEquals(null, action, 'Should create a time-bound action');
        System.assertEquals('Meeting', action.Action_Type__c, 'Type should be Meeting');
        System.assertEquals(true, action.Is_Time_Bound__c, 'Should be time-bound');
        System.assertEquals('Immediate', action.Source_Path__c, 'Source should be Immediate');
        System.assertEquals('Pending', action.Status__c, 'Status should be Pending');
        System.assertNotEquals(null, action.DueAt__c, 'DueAt should be set');
        System.assert(action.UniqueKey__c.contains('Meeting'), 'UniqueKey should contain Meeting');
        System.assertNotEquals(null, action.Stage_Priority__c, 'Stage priority should be set');
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
            Datetime.now().addHours(3), Datetime.now().addHours(4), evt.Id, 'First'
        );
        insert first;

        Test.startTest();
        // Second call with same event → should return null (duplicate)
        NBA_Queue__c second = NbaActionCreationService.createTimeBoundAction(
            opp.Id, opp.AccountId, opp.OwnerId,
            Datetime.now().addHours(3), Datetime.now().addHours(4), evt.Id, 'Duplicate'
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
            Datetime.now().addHours(2), Datetime.now().addHours(3), evt.Id, 'Original time'
        );
        insert action;

        Datetime newStartTime = Datetime.now().addHours(5);
        Datetime newEndTime = Datetime.now().addHours(6);
        Test.startTest();
        NBA_Queue__c updated = NbaActionCreationService.updateTimeBoundAction(
            evt.Id, opp.Id, newStartTime, newEndTime
        );
        Test.stopTest();

        System.assertNotEquals(null, updated, 'Should find the action to update');
        System.assertEquals(newEndTime, updated.DueAt__c, 'DueAt should be updated to new end time');
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
            Datetime.now().addHours(2), Datetime.now().addHours(3), evt.Id, 'Will be cancelled'
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
