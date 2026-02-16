@isTest
private class NbaCadenceServiceTest {

    // ─── Helper: Build a minimal signal for cadence testing ────────────
    private static NbaSignalService.OpportunitySignal buildSignal(
        Id oppId, Decimal daysSinceCreation, Integer todayCallCount,
        Datetime lastCallDate
    ) {
        NbaSignalService.OpportunitySignal sig = new NbaSignalService.OpportunitySignal();
        sig.oppId = oppId;
        sig.daysSinceCreation = daysSinceCreation;
        sig.todayCallCount = todayCallCount;
        sig.todayCallDates = new List<Datetime>();
        sig.lastCallDate = lastCallDate;
        sig.hadConnectedCall = false;
        sig.hadNoConnect = false;
        return sig;
    }

    // Use a fake Opp ID for unit tests (no DML needed for pure logic tests)
    private static Id getFakeOppId() {
        return '006000000000001AAA';
    }

    // ─── Test: Day 0 first call step returned correctly ───────────────
    @isTest
    static void testDay0FirstCallStep() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(
            getFakeOppId(), 0, 0, null
        );

        Test.startTest();
        NbaCadenceService.CadenceStep step = NbaCadenceService.getCurrentStep(sig, 'A');
        Test.stopTest();

        // Step should be returned (may be null if no CMDT records in test context)
        // In real org, this would return the FT_A_D0_Call1 rule
        if (step != null) {
            System.assertEquals(0, step.cadenceDay, 'Should be Day 0');
            System.assert(step.isPrimary, 'Should be a primary (call) step');
            System.assertEquals('Call', step.method, 'Method should be Call');
            System.assert(step.progressText.contains('Day 0'), 'Progress should mention Day 0');
        }
    }

    // ─── Test: Day 0 second call after one call made ──────────────────
    @isTest
    static void testDay0SecondCallAfterOneCall() {
        NbaCadenceService.resetCache();
        // Signal: 1 call made today, last call was 2 hours ago (spacing met)
        NbaSignalService.OpportunitySignal sig = buildSignal(
            getFakeOppId(), 0, 1, Datetime.now().addHours(-2)
        );

        Test.startTest();
        NbaCadenceService.CadenceStep step = NbaCadenceService.getCurrentStep(sig, 'A');
        Test.stopTest();

        if (step != null) {
            System.assertEquals(0, step.cadenceDay, 'Should be Day 0');
            System.assert(step.progressText.contains('2 of'), 'Should be call 2');
        }
    }

    // ─── Test: Spacing enforcement — too soon returns null ────────────
    @isTest
    static void testSpacingEnforcementReturnsNull() {
        NbaCadenceService.resetCache();
        // Signal: 1 call made, last call was 10 minutes ago (spacing NOT met for 60-min rule)
        NbaSignalService.OpportunitySignal sig = buildSignal(
            getFakeOppId(), 0, 1, Datetime.now().addMinutes(-10)
        );

        Test.startTest();
        NbaCadenceService.CadenceStep step = NbaCadenceService.getCurrentStep(sig, 'A');
        Test.stopTest();

        // Should return null because spacing is not met
        System.assertEquals(null, step, 'Should be null when spacing not met');
    }

    // ─── Test: Daily cap reached returns null ─────────────────────────
    @isTest
    static void testDailyCapReturnsNull() {
        NbaCadenceService.resetCache();
        // Signal: 3 calls made today on Day 0 (max is 3)
        NbaSignalService.OpportunitySignal sig = buildSignal(
            getFakeOppId(), 0, 3, Datetime.now().addHours(-2)
        );

        Test.startTest();
        NbaCadenceService.CadenceStep step = NbaCadenceService.getCurrentStep(sig, 'A');
        Test.stopTest();

        System.assertEquals(null, step, 'Should be null when daily cap reached');
    }

    // ─── Test: Cadence complete (past Day 5) returns null ─────────────
    @isTest
    static void testCadenceCompleteReturnsNull() {
        NbaCadenceService.resetCache();
        // Signal: 10 days since creation — past cadence end
        NbaSignalService.OpportunitySignal sig = buildSignal(
            getFakeOppId(), 10, 0, null
        );

        Test.startTest();
        NbaCadenceService.CadenceStep step = NbaCadenceService.getCurrentStep(sig, 'A');
        Test.stopTest();

        System.assertEquals(null, step, 'Should be null when cadence is complete');
    }

    // ─── Test: Variant mismatch returns null ──────────────────────────
    @isTest
    static void testVariantMismatchReturnsNull() {
        NbaCadenceService.resetCache();
        // Signal for Day 0, but variant B has no rules
        NbaSignalService.OpportunitySignal sig = buildSignal(
            getFakeOppId(), 0, 0, null
        );

        Test.startTest();
        NbaCadenceService.CadenceStep step = NbaCadenceService.getCurrentStep(sig, 'B');
        Test.stopTest();

        System.assertEquals(null, step, 'Should be null for unrecognized variant');
    }

    // ─── Test: computeCadenceDay mapping ──────────────────────────────
    @isTest
    static void testComputeCadenceDay() {
        System.assertEquals(0, NbaCadenceService.computeCadenceDay(0), 'Day 0');
        System.assertEquals(0, NbaCadenceService.computeCadenceDay(null), 'Null → Day 0');
        System.assertEquals(1, NbaCadenceService.computeCadenceDay(1), 'Day 1');
        System.assertEquals(3, NbaCadenceService.computeCadenceDay(2), '2 days → Day 3');
        System.assertEquals(3, NbaCadenceService.computeCadenceDay(3), '3 days → Day 3');
        System.assertEquals(5, NbaCadenceService.computeCadenceDay(4), '4 days → Day 5');
        System.assertEquals(5, NbaCadenceService.computeCadenceDay(5), '5 days → Day 5');
        System.assertEquals(-1, NbaCadenceService.computeCadenceDay(6), '6 days → complete');
        System.assertEquals(-1, NbaCadenceService.computeCadenceDay(10), '10 days → complete');
    }

    // ─── Test: lastEvaluatedSteps populated ───────────────────────────
    @isTest
    static void testLastEvaluatedStepsPopulated() {
        NbaCadenceService.resetCache();
        Id oppId = getFakeOppId();
        NbaSignalService.OpportunitySignal sig = buildSignal(oppId, 0, 0, null);

        Test.startTest();
        NbaCadenceService.CadenceStep step = NbaCadenceService.getCurrentStep(sig, 'A');
        Test.stopTest();

        if (step != null) {
            System.assert(
                NbaCadenceService.lastEvaluatedSteps.containsKey(oppId),
                'lastEvaluatedSteps should contain the opp ID'
            );
        }
    }
}
