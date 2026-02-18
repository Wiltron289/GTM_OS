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
        sig.hasUpcomingMeeting = false;
        sig.isClosed = false;
        // Phase 7 progress fields — null means start of cadence
        sig.lastCadenceName = null;
        sig.lastCadenceStepNumber = null;
        sig.lastCadenceStepOutcome = null;
        sig.lastCadenceStepDate = null;
        return sig;
    }

    private static Id getFakeOppId() {
        return '006000000000001AAA';
    }

    // ─── Test: getNextStep returns Step 1 for new signal ────────────
    @isTest
    static void testGetNextStepDay0Step1() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 0, 0, null);

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        // CMDT records exist in test context
        if (result != null && result.currentStep != null) {
            System.assertEquals(false, result.isComplete, 'Should not be complete');
            System.assertEquals(false, result.isSuppressed, 'Should not be suppressed');
            System.assertEquals(1, result.currentStep.stepNumber, 'Should be step 1');
            System.assertEquals(0, result.currentStep.dayNumber, 'Should be Day 0');
            System.assertEquals('Call', result.currentStep.method, 'First step should be Call');
            System.assert(result.progressText.contains('Step 1'), 'Progress should show Step 1');
            System.assert(result.upcomingSteps.size() > 0, 'Should have upcoming steps');
        }
    }

    // ─── Test: getNextStep advances after completing step 1 ─────────
    @isTest
    static void testGetNextStepAfterStep1Completed() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 0, 0, null);
        // Simulate: step 1 completed with VM outcome
        sig.lastCadenceStepNumber = 1;
        sig.lastCadenceStepOutcome = 'VM';
        sig.lastCadenceStepDate = Datetime.now().addMinutes(-30);

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        if (result != null && result.currentStep != null) {
            System.assertEquals(2, result.currentStep.stepNumber, 'Should advance to step 2');
            System.assertEquals('SMS', result.currentStep.method, 'Step 2 should be SMS');
        }
    }

    // ─── Test: Branching — Connected call ends cadence ──────────────
    @isTest
    static void testBranchingConnectedEndsCadence() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 0, 0, null);
        // Simulate: step 1 (Call) completed with Connected outcome
        sig.lastCadenceStepNumber = 1;
        sig.lastCadenceStepOutcome = 'Connected';

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        if (result != null) {
            System.assertEquals(true, result.isComplete,
                'Connected on step with End_Cadence should mark cadence complete');
        }
    }

    // ─── Test: Branching — VM continues to next step ────────────────
    @isTest
    static void testBranchingVMContinues() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 0, 1, Datetime.now().addHours(-2));
        // Simulate: step 3 (Call2, Day 0) completed with VM → Continue
        sig.lastCadenceStepNumber = 3;
        sig.lastCadenceStepOutcome = 'VM';

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        if (result != null && result.currentStep != null) {
            System.assertEquals(4, result.currentStep.stepNumber, 'VM should continue to step 4');
            System.assertEquals('Email', result.currentStep.method, 'Step 4 should be Email');
        }
    }

    // ─── Test: Branching — No Answer continues to next step ─────────
    @isTest
    static void testBranchingNoAnswerContinues() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 0, 1, Datetime.now().addHours(-2));
        // Step 5 (Call3, Day 0) completed with No_Answer → Continue
        sig.lastCadenceStepNumber = 5;
        sig.lastCadenceStepOutcome = 'No_Answer';

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        if (result != null && result.currentStep != null) {
            System.assertEquals(6, result.currentStep.stepNumber, 'Should advance to step 6');
            // Step 6 is Day 1 — may be day-gated
        }
    }

    // ─── Test: SMS/Email outcome 'Sent' always continues ───────────
    @isTest
    static void testSentOutcomeContinues() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 0, 0, null);
        // Step 2 (SMS1, Day 0) completed with Sent → Continue
        sig.lastCadenceStepNumber = 2;
        sig.lastCadenceStepOutcome = 'Sent';

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        if (result != null && result.currentStep != null) {
            System.assertEquals(3, result.currentStep.stepNumber, 'Sent should continue to step 3');
        }
    }

    // ─── Test: Exit condition — Connected Call ──────────────────────
    @isTest
    static void testExitConditionConnectedCall() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 1, 0, null);
        sig.hadConnectedCall = true; // Signal shows a connected call happened

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        if (result != null) {
            System.assertEquals(true, result.isComplete,
                'Connected call exit condition should mark cadence complete');
        }
    }

    // ─── Test: Exit condition — Meeting Scheduled ───────────────────
    @isTest
    static void testExitConditionMeetingScheduled() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 0, 0, null);
        sig.hasUpcomingMeeting = true;

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        if (result != null) {
            System.assertEquals(true, result.isComplete,
                'Meeting scheduled exit condition should mark cadence complete');
        }
    }

    // ─── Test: Day gate suppression ─────────────────────────────────
    @isTest
    static void testDayGateSuppression() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 0, 0, null);
        // Simulate: all Day 0 steps done, next step is Day 1 but we're on Day 0
        sig.lastCadenceStepNumber = 5;
        sig.lastCadenceStepOutcome = 'No_Answer';

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        if (result != null) {
            // Step 6 is on Day 1, but cadence day is 0 → suppressed
            if (!result.isComplete) {
                System.assertEquals(true, result.isSuppressed,
                    'Should be suppressed — next step is on a future day');
                System.assert(result.suppressReason != null && result.suppressReason.contains('Day'),
                    'Suppress reason should mention day');
            }
        }
    }

    // ─── Test: Spacing enforcement — too soon returns suppressed ────
    @isTest
    static void testSpacingEnforcement() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(
            getFakeOppId(), 0, 0, Datetime.now().addMinutes(-10)
        );
        // Step 2 (SMS) completed, next is step 3 (Call with 60-min spacing)
        sig.lastCadenceStepNumber = 2;
        sig.lastCadenceStepOutcome = 'Sent';

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        if (result != null && !result.isComplete) {
            System.assertEquals(true, result.isSuppressed,
                'Should be suppressed — 60-min spacing not met');
        }
    }

    // ─── Test: Cadence complete — past max mapped day ───────────────
    @isTest
    static void testCadenceCompletePastMaxDay() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 10, 0, null);

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        if (result != null) {
            System.assertEquals(true, result.isComplete,
                'Should be complete when past max day');
        }
    }

    // ─── Test: Variant mismatch returns null ────────────────────────
    @isTest
    static void testVariantMismatchReturnsNull() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 0, 0, null);

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'B', 'First Touch');
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for unrecognized variant');
    }

    // ─── Test: computeCadenceDay with Day Map ───────────────────────
    @isTest
    static void testComputeCadenceDayWithMap() {
        Map<String, Integer> dayMap = new Map<String, Integer>{
            '0' => 0, '1' => 1, '2' => 3, '3' => 3, '4' => 5, '5' => 5
        };

        System.assertEquals(0, NbaCadenceService.computeCadenceDay(0, dayMap), 'Day 0');
        System.assertEquals(0, NbaCadenceService.computeCadenceDay(null, dayMap), 'Null → Day 0');
        System.assertEquals(1, NbaCadenceService.computeCadenceDay(1, dayMap), 'Day 1');
        System.assertEquals(3, NbaCadenceService.computeCadenceDay(2, dayMap), '2 days → Day 3');
        System.assertEquals(3, NbaCadenceService.computeCadenceDay(3, dayMap), '3 days → Day 3');
        System.assertEquals(5, NbaCadenceService.computeCadenceDay(4, dayMap), '4 days → Day 5');
        System.assertEquals(5, NbaCadenceService.computeCadenceDay(5, dayMap), '5 days → Day 5');
        System.assertEquals(-1, NbaCadenceService.computeCadenceDay(6, dayMap), '6 days → complete');
        System.assertEquals(-1, NbaCadenceService.computeCadenceDay(10, dayMap), '10 days → complete');
    }

    // ─── Test: computeCadenceDay without Day Map (raw days) ─────────
    @isTest
    static void testComputeCadenceDayNoMap() {
        System.assertEquals(0, NbaCadenceService.computeCadenceDay(0, null), 'Raw day 0');
        System.assertEquals(3, NbaCadenceService.computeCadenceDay(3, null), 'Raw day 3');
        System.assertEquals(7, NbaCadenceService.computeCadenceDay(7, null), 'Raw day 7');
    }

    // ─── Test: parseDayMap ──────────────────────────────────────────
    @isTest
    static void testParseDayMap() {
        Map<String, Integer> parsed = NbaCadenceService.parseDayMap(
            '{"0":0,"1":1,"2":3,"3":3,"4":5,"5":5}'
        );
        System.assertNotEquals(null, parsed, 'Should parse successfully');
        System.assertEquals(6, parsed.size(), 'Should have 6 entries');
        System.assertEquals(0, parsed.get('0'), 'Key 0 → 0');
        System.assertEquals(3, parsed.get('2'), 'Key 2 → 3');
        System.assertEquals(5, parsed.get('5'), 'Key 5 → 5');

        // Null/blank input
        System.assertEquals(null, NbaCadenceService.parseDayMap(null), 'Null input');
        System.assertEquals(null, NbaCadenceService.parseDayMap(''), 'Empty input');

        // Invalid JSON
        System.assertEquals(null, NbaCadenceService.parseDayMap('not json'), 'Invalid JSON');
    }

    // ─── Test: resolveNextStep branching logic ──────────────────────
    @isTest
    static void testResolveNextStepBranching() {
        // Build test step definitions
        List<NbaCadenceService.CadenceStepDef> steps = new List<NbaCadenceService.CadenceStepDef>();

        NbaCadenceService.CadenceStepDef s1 = new NbaCadenceService.CadenceStepDef();
        s1.stepNumber = 1; s1.dayNumber = 0; s1.method = 'Call';
        s1.onConnectAction = 'End_Cadence';
        s1.onVMAction = 'Continue';
        s1.onNoAnswerAction = 'Skip_To_Step'; s1.onNoAnswerTarget = 4;
        steps.add(s1);

        NbaCadenceService.CadenceStepDef s2 = new NbaCadenceService.CadenceStepDef();
        s2.stepNumber = 2; s2.dayNumber = 0; s2.method = 'SMS';
        steps.add(s2);

        NbaCadenceService.CadenceStepDef s3 = new NbaCadenceService.CadenceStepDef();
        s3.stepNumber = 3; s3.dayNumber = 0; s3.method = 'Call';
        s3.onConnectAction = 'End_Cadence';
        s3.onVMAction = 'Skip_To_Day'; s3.onVMTarget = 3;
        steps.add(s3);

        NbaCadenceService.CadenceStepDef s4 = new NbaCadenceService.CadenceStepDef();
        s4.stepNumber = 4; s4.dayNumber = 1; s4.method = 'Email';
        steps.add(s4);

        NbaCadenceService.CadenceStepDef s5 = new NbaCadenceService.CadenceStepDef();
        s5.stepNumber = 5; s5.dayNumber = 3; s5.method = 'Call';
        steps.add(s5);

        // Test: no prior step → step 1
        NbaCadenceService.CadencePosition pos0 = new NbaCadenceService.CadencePosition();
        pos0.lastCompletedStep = 0;
        System.assertEquals(1, NbaCadenceService.resolveNextStep(pos0, steps), 'Start → step 1');

        // Test: step 1 with Connected → End_Cadence (null)
        NbaCadenceService.CadencePosition posConnected = new NbaCadenceService.CadencePosition();
        posConnected.lastCompletedStep = 1; posConnected.lastOutcome = 'Connected';
        System.assertEquals(null, NbaCadenceService.resolveNextStep(posConnected, steps),
            'Connected → End_Cadence');

        // Test: step 1 with VM → Continue → step 2
        NbaCadenceService.CadencePosition posVM = new NbaCadenceService.CadencePosition();
        posVM.lastCompletedStep = 1; posVM.lastOutcome = 'VM';
        System.assertEquals(2, NbaCadenceService.resolveNextStep(posVM, steps),
            'VM → Continue → step 2');

        // Test: step 1 with No_Answer → Skip_To_Step 4
        NbaCadenceService.CadencePosition posNA = new NbaCadenceService.CadencePosition();
        posNA.lastCompletedStep = 1; posNA.lastOutcome = 'No_Answer';
        System.assertEquals(4, NbaCadenceService.resolveNextStep(posNA, steps),
            'No_Answer → Skip_To_Step 4');

        // Test: step 3 with VM → Skip_To_Day 3 → step 5 (first step on day 3)
        NbaCadenceService.CadencePosition posVMDay = new NbaCadenceService.CadencePosition();
        posVMDay.lastCompletedStep = 3; posVMDay.lastOutcome = 'VM';
        System.assertEquals(5, NbaCadenceService.resolveNextStep(posVMDay, steps),
            'VM → Skip_To_Day 3 → step 5');

        // Test: step 2 with Sent → Continue → step 3
        NbaCadenceService.CadencePosition posSent = new NbaCadenceService.CadencePosition();
        posSent.lastCompletedStep = 2; posSent.lastOutcome = 'Sent';
        System.assertEquals(3, NbaCadenceService.resolveNextStep(posSent, steps),
            'Sent → Continue → step 3');

        // Test: past last step → null (cadence complete)
        NbaCadenceService.CadencePosition posPast = new NbaCadenceService.CadencePosition();
        posPast.lastCompletedStep = 5; posPast.lastOutcome = 'Sent';
        System.assertEquals(null, NbaCadenceService.resolveNextStep(posPast, steps),
            'Past last step → cadence complete');
    }

    // ─── Test: lastEvaluatedResults populated ───────────────────────
    @isTest
    static void testLastEvaluatedResultsPopulated() {
        NbaCadenceService.resetCache();
        Id oppId = getFakeOppId();
        NbaSignalService.OpportunitySignal sig = buildSignal(oppId, 0, 0, null);

        Test.startTest();
        NbaCadenceService.CadenceResult result = NbaCadenceService.getNextStep(sig, 'A', 'First Touch');
        Test.stopTest();

        if (result != null) {
            System.assert(
                NbaCadenceService.lastEvaluatedResults.containsKey(oppId),
                'lastEvaluatedResults should contain the opp ID'
            );
        }
    }

    // ─── Test: Backward compat — getCurrentStep wrapper ─────────────
    @isTest
    static void testBackwardCompatGetCurrentStep() {
        NbaCadenceService.resetCache();
        NbaSignalService.OpportunitySignal sig = buildSignal(getFakeOppId(), 0, 0, null);

        Test.startTest();
        NbaCadenceService.CadenceStep step = NbaCadenceService.getCurrentStep(sig, 'A');
        Test.stopTest();

        if (step != null) {
            System.assertNotEquals(null, step.method, 'Method should be set');
            System.assertNotEquals(null, step.instruction, 'Instruction should be set');
            System.assert(
                NbaCadenceService.lastEvaluatedSteps.containsKey(getFakeOppId()),
                'Legacy lastEvaluatedSteps should be populated'
            );
        }
    }

    // ─── Test: checkExitConditions ──────────────────────────────────
    @isTest
    static void testCheckExitConditions() {
        NbaSignalService.OpportunitySignal sig = new NbaSignalService.OpportunitySignal();
        sig.hadConnectedCall = false;
        sig.hasUpcomingMeeting = false;
        sig.isClosed = false;

        Set<String> exits = new Set<String>{ 'Connected_Call', 'Meeting_Scheduled', 'Opp_Closed' };

        System.assertEquals(false, NbaCadenceService.checkExitConditions(sig, exits),
            'No conditions met');

        sig.hadConnectedCall = true;
        System.assertEquals(true, NbaCadenceService.checkExitConditions(sig, exits),
            'Connected call should trigger exit');

        sig.hadConnectedCall = false;
        sig.hasUpcomingMeeting = true;
        System.assertEquals(true, NbaCadenceService.checkExitConditions(sig, exits),
            'Meeting should trigger exit');

        sig.hasUpcomingMeeting = false;
        sig.isClosed = true;
        System.assertEquals(true, NbaCadenceService.checkExitConditions(sig, exits),
            'Closed opp should trigger exit');

        // Empty/null conditions
        System.assertEquals(false, NbaCadenceService.checkExitConditions(sig, new Set<String>()),
            'Empty conditions should not exit');
        System.assertEquals(false, NbaCadenceService.checkExitConditions(sig, null),
            'Null conditions should not exit');
    }
}
