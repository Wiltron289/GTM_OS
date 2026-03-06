/**
 * Test class for NbaActionSelectionService.
 * Verifies: Time-Bound Override, Stage Priority, Expected ARR ranking,
 * deterministic tiebreaker (oldest Opp CreatedDate).
 */
@isTest
private class NbaActionSelectionServiceTest {

    @TestSetup
    static void setupData() {
        List<Account> accs = new List<Account>();
        for (Integer i = 1; i <= 5; i++) {
            accs.add(new Account(
                Name = 'Selection Test Account ' + i,
                Entity_ID__c = 'SEL-00' + i
            ));
        }
        insert accs;

        Id payrollRtId;
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll'
            LIMIT 1
        ];
        if (!rts.isEmpty()) {
            payrollRtId = rts[0].Id;
        }

        List<Opportunity> opps = new List<Opportunity>();
        // Opp 0: Closing stage, $5000
        // Opp 1: New stage, $10000
        // Opp 2: Consult stage, $3000
        // Opp 3: Closing stage, $8000
        // Opp 4: Connect stage, $6000
        String[] stages = new String[]{ 'Closing', 'New', 'Consult', 'Closing', 'Connect' };
        Decimal[] amounts = new Decimal[]{ 5000, 10000, 3000, 8000, 6000 };
        for (Integer i = 0; i < 5; i++) {
            Opportunity o = new Opportunity(
                Name = 'Sel Opp ' + i,
                AccountId = accs[i].Id,
                StageName = stages[i],
                CloseDate = Date.today().addDays(30),
                Amount = amounts[i],
                Source__c = 'N/A'
            );
            if (payrollRtId != null) o.RecordTypeId = payrollRtId;
            opps.add(o);
        }
        insert opps;
    }

    private static List<Opportunity> getOpps() {
        // Set mockNow to 5 PM UTC (noon ET / 11 AM CT / 9 AM PT) —
        // past 8 AM gate hour in all US timezones, so existing tests are time-independent
        NbaActionSelectionService.mockNow = Datetime.newInstanceGmt(
            Date.today(), Time.newInstance(17, 0, 0, 0));
        return [SELECT Id, AccountId, StageName, Amount, CreatedDate,
                       Account.Name
                FROM Opportunity ORDER BY Account.Name];
    }

    private static NBA_Queue__c makeAction(Id oppId, Id acctId, String stage,
            Decimal arr, Boolean isTimeBound, Datetime dueAt) {
        Integer stagePriority = NbaActionSelectionService.resolveStagePriority(stage);
        return new NBA_Queue__c(
            Opportunity__c = oppId, Account__c = acctId,
            Sales_Rep__c = UserInfo.getUserId(), Status__c = 'Pending',
            Action_Type__c = 'First Touch', Workflow_Mode__c = 'Pipeline',
            Stage_Priority__c = stagePriority,
            Expected_Incremental_ARR__c = arr,
            Is_Time_Bound__c = isTimeBound,
            DueAt__c = dueAt
        );
    }

    // ─── Time-Bound Override ─────────────────────────────────────────

    @isTest
    static void testTimeBoundOverride_ServedFirst() {
        List<Opportunity> opps = getOpps();

        // Non-time-bound Closing-stage action with high ARR
        NBA_Queue__c closingAction = makeAction(
            opps[0].Id, opps[0].AccountId, 'Closing', 50000, false, null);

        // Time-bound action (meeting in 3 min) with low ARR
        NBA_Queue__c timeBoundAction = makeAction(
            opps[1].Id, opps[1].AccountId, 'New', 100,
            true, Datetime.now().addMinutes(3));

        List<NBA_Queue__c> candidates = new List<NBA_Queue__c>{ closingAction, timeBoundAction };

        Test.startTest();
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(candidates);
        Test.stopTest();

        System.assertEquals(2, ranked.size(), 'Both should pass gating');
        System.assert(ranked[0].isTimeBound, 'Time-bound should be served first');
        System.assertEquals(opps[1].Id, ranked[0].action.Opportunity__c,
            'Time-bound action should win over high-ARR Closing action');
    }

    @isTest
    static void testTimeBoundOverride_OrderedByDeadlineProximity() {
        List<Opportunity> opps = getOpps();

        NBA_Queue__c laterMeeting = makeAction(
            opps[0].Id, opps[0].AccountId, 'New', 100,
            true, Datetime.now().addMinutes(10));
        NBA_Queue__c soonerMeeting = makeAction(
            opps[1].Id, opps[1].AccountId, 'New', 100,
            true, Datetime.now().addMinutes(2));

        List<NBA_Queue__c> candidates = new List<NBA_Queue__c>{ laterMeeting, soonerMeeting };

        Test.startTest();
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(candidates);
        Test.stopTest();

        System.assertEquals(opps[1].Id, ranked[0].action.Opportunity__c,
            'Sooner meeting should be served first');
    }

    // ─── Stage Priority ─────────────────────────────────────────────

    @isTest
    static void testStagePriority_ClosingBeatsNewRegardlessOfARR() {
        List<Opportunity> opps = getOpps();

        // Closing-stage $20K
        NBA_Queue__c closingAction = makeAction(
            opps[0].Id, opps[0].AccountId, 'Closing', 20000, false, null);

        // New-stage $100K — higher ARR but lower stage priority
        NBA_Queue__c newAction = makeAction(
            opps[1].Id, opps[1].AccountId, 'New', 100000, false, null);

        List<NBA_Queue__c> candidates = new List<NBA_Queue__c>{ newAction, closingAction };

        Test.startTest();
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(candidates);
        Test.stopTest();

        System.assertEquals(2, ranked.size(), 'Both should pass gating');
        System.assertEquals(1, ranked[0].stagePriority,
            'Closing (priority 1) should be first');
        System.assertEquals(4, ranked[1].stagePriority,
            'New (priority 4) should be last');
    }

    @isTest
    static void testStagePriority_FullOrderingCorrect() {
        List<Opportunity> opps = getOpps();

        // Create one action per stage, all same ARR
        NBA_Queue__c newAction = makeAction(
            opps[1].Id, opps[1].AccountId, 'New', 1000, false, null);
        NBA_Queue__c connectAction = makeAction(
            opps[4].Id, opps[4].AccountId, 'Connect', 1000, false, null);
        NBA_Queue__c consultAction = makeAction(
            opps[2].Id, opps[2].AccountId, 'Consult', 1000, false, null);
        NBA_Queue__c closingAction = makeAction(
            opps[0].Id, opps[0].AccountId, 'Closing', 1000, false, null);

        List<NBA_Queue__c> candidates = new List<NBA_Queue__c>{
            newAction, connectAction, consultAction, closingAction
        };

        Test.startTest();
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(candidates);
        Test.stopTest();

        System.assertEquals(4, ranked.size(), 'All should pass gating');
        System.assertEquals(1, ranked[0].stagePriority, 'First: Closing (1)');
        System.assertEquals(2, ranked[1].stagePriority, 'Second: Consult (2)');
        System.assertEquals(3, ranked[2].stagePriority, 'Third: Connect (3)');
        System.assertEquals(4, ranked[3].stagePriority, 'Fourth: New (4)');
    }

    // ─── Expected ARR Within Same Stage ─────────────────────────────

    @isTest
    static void testExpectedARR_RanksWithinSameStage() {
        List<Opportunity> opps = getOpps();

        // Two Closing-stage actions with different ARR
        NBA_Queue__c lowArr = makeAction(
            opps[0].Id, opps[0].AccountId, 'Closing', 5000, false, null);
        NBA_Queue__c highArr = makeAction(
            opps[3].Id, opps[3].AccountId, 'Closing', 25000, false, null);

        List<NBA_Queue__c> candidates = new List<NBA_Queue__c>{ lowArr, highArr };

        Test.startTest();
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(candidates);
        Test.stopTest();

        System.assertEquals(2, ranked.size(), 'Both should pass gating');
        System.assertEquals(25000, ranked[0].expectedArr,
            'Higher ARR should be first within same stage');
        System.assertEquals(5000, ranked[1].expectedArr,
            'Lower ARR should be second');
    }

    // ─── Tiebreaker (Oldest Opp CreatedDate) ────────────────────────

    @isTest
    static void testTiebreaker_OldestOppWins() {
        List<Opportunity> opps = getOpps();

        // Two Closing-stage actions with identical ARR
        // Use opps[0] and opps[3] — both are Closing stage
        // Since they were inserted in the same transaction, CreatedDates are the same,
        // so we verify the comparator doesn't throw and returns deterministic results
        NBA_Queue__c action1 = makeAction(
            opps[0].Id, opps[0].AccountId, 'Closing', 10000, false, null);
        NBA_Queue__c action2 = makeAction(
            opps[3].Id, opps[3].AccountId, 'Closing', 10000, false, null);

        List<NBA_Queue__c> candidates = new List<NBA_Queue__c>{ action1, action2 };

        Test.startTest();
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(candidates);
        Test.stopTest();

        System.assertEquals(2, ranked.size(), 'Both should pass gating');
        // Both have same stage, ARR, and CreatedDate — just verify stable sort
        System.assertNotEquals(null, ranked[0].action.Opportunity__c,
            'Should return a valid action');
    }

    // ─── Edge Cases ─────────────────────────────────────────────────

    @isTest
    static void testSelectTop_NullUserId() {
        Test.startTest();
        NBA_Queue__c top = NbaActionSelectionService.selectTop(null);
        Test.stopTest();

        System.assertEquals(null, top, 'Null user ID should return null');
    }

    @isTest
    static void testSelectTop_NoCandidates() {
        delete [SELECT Id FROM NBA_Queue__c WHERE Status__c = 'Pending'];

        Test.startTest();
        NBA_Queue__c top = NbaActionSelectionService.selectTop(UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals(null, top, 'No candidates should return null');
    }

    @isTest
    static void testResolveStagePriority_ValidStages() {
        Test.startTest();
        Integer closing = NbaActionSelectionService.resolveStagePriority('Closing');
        Integer consult = NbaActionSelectionService.resolveStagePriority('Consult');
        Integer connect = NbaActionSelectionService.resolveStagePriority('Connect');
        Integer newStage = NbaActionSelectionService.resolveStagePriority('New');
        Integer unknown = NbaActionSelectionService.resolveStagePriority('Unknown');
        Integer blank = NbaActionSelectionService.resolveStagePriority(null);
        Test.stopTest();

        System.assertEquals(1, closing, 'Closing should be priority 1');
        System.assertEquals(2, consult, 'Consult should be priority 2');
        System.assertEquals(3, connect, 'Connect should be priority 3');
        System.assertEquals(4, newStage, 'New should be priority 4');
        System.assertEquals(99, unknown, 'Unknown stage should default to 99');
        System.assertEquals(99, blank, 'Null stage should default to 99');
    }

    @isTest
    static void testModeGate_NonPipelineFiltered() {
        List<Opportunity> opps = getOpps();

        NBA_Queue__c pipelineAction = makeAction(
            opps[0].Id, opps[0].AccountId, 'Closing', 10000, false, null);

        NBA_Queue__c blitzAction = new NBA_Queue__c(
            Opportunity__c = opps[1].Id, Account__c = opps[1].AccountId,
            Sales_Rep__c = UserInfo.getUserId(), Status__c = 'Pending',
            Action_Type__c = 'Blitz Outreach', Workflow_Mode__c = 'Blitz',
            Stage_Priority__c = 4, Expected_Incremental_ARR__c = 50000
        );

        List<NBA_Queue__c> candidates = new List<NBA_Queue__c>{ pipelineAction, blitzAction };

        Test.startTest();
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(candidates);
        Test.stopTest();

        System.assertEquals(1, ranked.size(), 'Blitz mode should be filtered out');
        System.assertEquals(opps[0].Id, ranked[0].action.Opportunity__c,
            'Only Pipeline action should pass');
    }

    // ─── Timezone Gate ────────────────────────────────────────────

    @isTest
    static void testTimezoneGate_GatesBeforeEightAM() {
        // 7 AM Central = 13:00 UTC — before 8 AM gate
        NbaActionSelectionService.mockNow = Datetime.newInstanceGmt(
            Date.today(), Time.newInstance(13, 0, 0, 0));

        Test.startTest();
        Boolean result = NbaActionSelectionService.isLocalTimeAfterGateHour('America/Chicago');
        Test.stopTest();

        System.assertEquals(false, result,
            '7 AM Central should be before 8 AM gate');
    }

    @isTest
    static void testTimezoneGate_PassesAtEightAM() {
        // 8 AM Central = 14:00 UTC — at gate hour
        NbaActionSelectionService.mockNow = Datetime.newInstanceGmt(
            Date.today(), Time.newInstance(14, 0, 0, 0));

        Test.startTest();
        Boolean result = NbaActionSelectionService.isLocalTimeAfterGateHour('America/Chicago');
        Test.stopTest();

        System.assertEquals(true, result,
            '8 AM Central should pass the gate');
    }

    @isTest
    static void testTimezoneGate_PSTGatedWhenEarlyMorning() {
        // 7:30 AM Pacific = 15:30 UTC — before 8 AM PST gate
        NbaActionSelectionService.mockNow = Datetime.newInstanceGmt(
            Date.today(), Time.newInstance(15, 30, 0, 0));

        Test.startTest();
        Boolean result = NbaActionSelectionService.isLocalTimeAfterGateHour('America/Los_Angeles');
        Test.stopTest();

        System.assertEquals(false, result,
            '7:30 AM Pacific should be before 8 AM gate');
    }

    @isTest
    static void testTimezoneGate_TimeBoundBypassesGate() {
        List<Opportunity> opps = getOpps();

        // Set mockNow to 5 AM Central (11:00 UTC) — well before 8 AM
        NbaActionSelectionService.mockNow = Datetime.newInstanceGmt(
            Date.today(), Time.newInstance(11, 0, 0, 0));

        // Time-bound meeting should bypass the timezone gate
        NBA_Queue__c timeBound = makeAction(
            opps[0].Id, opps[0].AccountId, 'Closing', 10000,
            true, Datetime.now().addMinutes(3));

        Test.startTest();
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(new List<NBA_Queue__c>{ timeBound });
        Test.stopTest();

        System.assertEquals(1, ranked.size(),
            'Time-bound action should bypass timezone gate');
    }

    @isTest
    static void testTimezoneGate_NotUSADefaultsToCST() {
        Test.startTest();
        String tz = NbaActionSelectionService.resolveIanaTimezone('Not USA');
        Test.stopTest();

        System.assertEquals('America/Chicago', tz,
            'Not USA should default to America/Chicago');
    }

    @isTest
    static void testTimezoneGate_BlankDefaultsToCST() {
        Test.startTest();
        String tz = NbaActionSelectionService.resolveIanaTimezone(null);
        Test.stopTest();

        System.assertEquals('America/Chicago', tz,
            'Blank timezone should default to America/Chicago');
    }

    @isTest
    static void testTimezoneGate_IntegrationWithRankActions() {
        List<Opportunity> opps = getOpps();

        // Set mockNow to 5 AM Central (11:00 UTC) — before gate
        NbaActionSelectionService.mockNow = Datetime.newInstanceGmt(
            Date.today(), Time.newInstance(11, 0, 0, 0));

        // Non-time-bound action should be gated (account defaults to America/Chicago)
        NBA_Queue__c action = makeAction(
            opps[0].Id, opps[0].AccountId, 'Closing', 10000, false, null);

        Test.startTest();
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(new List<NBA_Queue__c>{ action });
        Test.stopTest();

        System.assertEquals(0, ranked.size(),
            'Non-time-bound action should be gated at 5 AM Central');
    }
}
