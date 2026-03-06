@isTest
private class NbaTagServiceTest {

    // ─── Helpers ──────────────────────────────────────────────────────

    private static NbaActionController.ActionWrapper buildWrapper(
        String actionType, Boolean isTimeBound, Datetime dueAt
    ) {
        NbaActionController.ActionWrapper w = new NbaActionController.ActionWrapper();
        w.actionType = actionType;
        w.isTimeBound = isTimeBound;
        w.dueAt = dueAt;
        w.isCadenceAction = false;
        return w;
    }

    private static NbaActionController.ActionWrapper buildCadenceWrapper(
        String actionType, String cadenceName, Integer stepNum, Integer totalSteps, String method
    ) {
        NbaActionController.ActionWrapper w = buildWrapper(actionType, false, null);
        w.isCadenceAction = true;
        w.cadenceName = cadenceName;
        w.cadenceStepNumber = stepNum;
        w.cadenceTotalSteps = totalSteps;
        w.stepMethod = method;
        w.cadenceProgress = 'Step ' + stepNum + ' of ' + totalSteps + ' — Day 0, ' + method;
        return w;
    }

    private static NbaSignalService.OpportunitySignal buildSignal() {
        NbaSignalService.OpportunitySignal sig = new NbaSignalService.OpportunitySignal();
        sig.oppId = '006000000000001AAA';
        sig.stageName = 'New';
        sig.hasAccountScoring = false;
        sig.hadConnectedCall = false;
        sig.hadIncomingReply = false;
        sig.todayCallCount = 0;
        return sig;
    }

    // ─── Test: Time-bound Meeting tag ─────────────────────────────────

    @isTest
    static void testMeetingUpcomingTag() {
        Datetime meetingTime = Datetime.now().addMinutes(10);
        NbaActionController.ActionWrapper w = buildWrapper('Meeting', true, meetingTime);
        NbaSignalService.OpportunitySignal sig = buildSignal();

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        Boolean hasMeetingTag = false;
        for (NbaTagService.Tag t : tags) {
            if (t.id == 'TB-01') {
                hasMeetingTag = true;
                System.assertEquals('Meeting Upcoming', t.chip, 'Chip label should be Meeting Upcoming');
                System.assertEquals('Time-Bound', t.category, 'Category should be Time-Bound');
                System.assertEquals(1, t.priority, 'Priority should be 1');
            }
        }
        System.assert(hasMeetingTag, 'Should generate TB-01 Meeting Upcoming tag');
    }

    // ─── Test: Cadence tag for active cadence ─────────────────────────

    @isTest
    static void testCadenceFirstTouchTag() {
        NbaActionController.ActionWrapper w = buildCadenceWrapper('First Touch', 'First_Touch_A', 1, 12, 'Call');
        NbaSignalService.OpportunitySignal sig = buildSignal();

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        Boolean hasFirstTouchTag = false;
        for (NbaTagService.Tag t : tags) {
            if (t.id == 'CD-02') {
                hasFirstTouchTag = true;
                System.assertEquals('First Touch', t.chip, 'Chip should be First Touch');
                System.assertEquals(2, t.priority, 'Priority should be 2 (Cadence)');
            }
        }
        System.assert(hasFirstTouchTag, 'Should generate CD-02 First Touch tag for step 1');
    }

    // ─── Test: Call Attempt tag for mid-cadence call ──────────────────

    @isTest
    static void testCallAttemptTag() {
        NbaActionController.ActionWrapper w = buildCadenceWrapper('First Touch', 'First_Touch_A', 5, 12, 'Call');
        NbaSignalService.OpportunitySignal sig = buildSignal();

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        Boolean hasCallAttempt = false;
        for (NbaTagService.Tag t : tags) {
            if (t.id == 'CD-01') {
                hasCallAttempt = true;
                System.assert(t.chip.contains('Call Attempt'), 'Chip should contain Call Attempt');
            }
        }
        System.assert(hasCallAttempt, 'Should generate CD-01 Call Attempt tag for step 5');
    }

    // ─── Test: Last Attempt tag ───────────────────────────────────────

    @isTest
    static void testLastAttemptTag() {
        NbaActionController.ActionWrapper w = buildCadenceWrapper('First Touch', 'First_Touch_A', 12, 12, 'Call');
        NbaSignalService.OpportunitySignal sig = buildSignal();

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        Boolean hasLastAttempt = false;
        for (NbaTagService.Tag t : tags) {
            if (t.id == 'CD-04') {
                hasLastAttempt = true;
                System.assertEquals('Last Attempt', t.chip, 'Chip should be Last Attempt');
            }
        }
        System.assert(hasLastAttempt, 'Should generate CD-04 Last Attempt tag for final step');
    }

    // ─── Test: 4-tag cap enforced ─────────────────────────────────────

    @isTest
    static void testFourTagCapEnforced() {
        // Build a wrapper + signal that would generate many tags
        Datetime meetingTime = Datetime.now().addMinutes(10);
        NbaActionController.ActionWrapper w = buildWrapper('Meeting', true, meetingTime);
        w.isCadenceAction = true;
        w.cadenceName = 'First_Touch_A';
        w.cadenceStepNumber = 5;
        w.cadenceTotalSteps = 12;
        w.stepMethod = 'Call';
        w.cadenceProgress = 'Step 5 of 12 — Day 1, Call';

        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = true;
        sig.likelihoodToWin = 0.85;
        sig.probPayrollConversion = 0.75;
        sig.probTierUpgrade = 0.60;
        sig.hadIncomingReply = true;
        sig.lastSmsDate = Datetime.now().addHours(-2);
        sig.daysSinceLastInteraction = 20;
        sig.stageName = 'Connect';
        sig.incrementalIfWon = 1000;

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        System.assert(tags.size() <= 4, 'Should never exceed 4 tags, got ' + tags.size());
    }

    // ─── Test: Priority ordering (higher priority tags survive cap) ───

    @isTest
    static void testPriorityOrdering() {
        Datetime meetingTime = Datetime.now().addMinutes(10);
        NbaActionController.ActionWrapper w = buildWrapper('Meeting', true, meetingTime);
        w.isCadenceAction = true;
        w.cadenceName = 'First_Touch_A';
        w.cadenceStepNumber = 5;
        w.cadenceTotalSteps = 12;
        w.stepMethod = 'Call';
        w.cadenceProgress = 'Step 5 of 12 — Day 1, Call';

        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = true;
        sig.likelihoodToWin = 0.85;
        sig.daysSinceLastInteraction = 20;
        sig.stageName = 'Connect';
        sig.incrementalIfWon = 1000;

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        // First tag should be Time-Bound (priority 1)
        System.assert(tags.size() >= 1, 'Should have at least 1 tag');
        System.assertEquals(1, tags[0].priority, 'First tag should be priority 1 (Time-Bound)');

        // Tags should be in ascending priority order
        for (Integer i = 1; i < tags.size(); i++) {
            System.assert(tags[i].priority >= tags[i-1].priority,
                'Tags should be sorted by priority — tag ' + i + ' priority ' + tags[i].priority +
                ' should be >= tag ' + (i-1) + ' priority ' + tags[i-1].priority);
        }
    }

    // ─── Test: JSON output format ─────────────────────────────────────

    @isTest
    static void testJsonOutputFormat() {
        NbaActionController.ActionWrapper w = buildCadenceWrapper('First Touch', 'First_Touch_A', 1, 12, 'Call');
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = true;
        sig.likelihoodToWin = 0.85;

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        String jsonStr = NbaTagService.toJson(tags);
        Test.stopTest();

        System.assertNotEquals(null, jsonStr, 'JSON should not be null');

        // Deserialize and verify structure
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(jsonStr);
        System.assert(parsed.size() > 0, 'Should have at least one tag in JSON');

        Map<String, Object> firstTag = (Map<String, Object>) parsed[0];
        System.assert(firstTag.containsKey('id'), 'Tag should have id field');
        System.assert(firstTag.containsKey('category'), 'Tag should have category field');
        System.assert(firstTag.containsKey('chip'), 'Tag should have chip field');
        System.assert(firstTag.containsKey('expanded'), 'Tag should have expanded field');
        System.assert(firstTag.containsKey('priority'), 'Tag should have priority field');
    }

    // ─── Test: Empty/null signal handling ─────────────────────────────

    @isTest
    static void testNullInputsReturnEmptyList() {
        Test.startTest();
        List<NbaTagService.Tag> tags1 = NbaTagService.generateTags(null, null);
        List<NbaTagService.Tag> tags2 = NbaTagService.generateTags(null, buildSignal());
        List<NbaTagService.Tag> tags3 = NbaTagService.generateTags(
            buildWrapper('First Touch', false, null), null
        );
        Test.stopTest();

        System.assertEquals(0, tags1.size(), 'Null both should return empty');
        System.assertEquals(0, tags2.size(), 'Null wrapper should return empty');
        System.assertEquals(0, tags3.size(), 'Null signal should return empty');
    }

    // ─── Test: toJson with null/empty returns null ────────────────────

    @isTest
    static void testToJsonNullEmpty() {
        Test.startTest();
        String json1 = NbaTagService.toJson(null);
        String json2 = NbaTagService.toJson(new List<NbaTagService.Tag>());
        Test.stopTest();

        System.assertEquals(null, json1, 'Null tags should return null JSON');
        System.assertEquals(null, json2, 'Empty tags should return null JSON');
    }

    // ─── Test: Data Science signal tag ────────────────────────────────

    @isTest
    static void testHighWinLikelihoodTag() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = true;
        sig.likelihoodToWin = 0.85;

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        Boolean hasWinTag = false;
        for (NbaTagService.Tag t : tags) {
            if (t.id == 'DS-01') {
                hasWinTag = true;
                System.assertEquals('Signal', t.category, 'Category should be Signal');
                System.assert(t.expanded.contains('85%'), 'Should show 85% in expanded text');
            }
        }
        System.assert(hasWinTag, 'Should generate DS-01 High Win Likelihood tag');
    }

    // ─── Test: Engagement — Inbound Reply ─────────────────────────────

    @isTest
    static void testInboundReplyTag() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hadIncomingReply = true;
        sig.lastSmsDate = Datetime.now().addHours(-6);

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        Boolean hasReplyTag = false;
        for (NbaTagService.Tag t : tags) {
            if (t.id == 'EN-01') {
                hasReplyTag = true;
                System.assertEquals('Engagement', t.category, 'Category should be Engagement');
            }
        }
        System.assert(hasReplyTag, 'Should generate EN-01 Inbound Reply tag');
    }

    // ─── Test: Stage — High Value tag ─────────────────────────────────

    @isTest
    static void testHighValueTag() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.incrementalIfWon = 1500;

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        Boolean hasValueTag = false;
        for (NbaTagService.Tag t : tags) {
            if (t.id == 'ST-03') {
                hasValueTag = true;
                System.assertEquals('Economic', t.category, 'Category should be Economic');
                System.assert(t.expanded.contains('1500'), 'Should show $1500');
            }
        }
        System.assert(hasValueTag, 'Should generate ST-03 High Value tag');
    }

    // ─── Test: Re-engaged cadence tag ─────────────────────────────────

    @isTest
    static void testReEngagedTag() {
        NbaActionController.ActionWrapper w = buildCadenceWrapper('Re-engage', 'Re_engage_A', 2, 6, 'Call');
        NbaSignalService.OpportunitySignal sig = buildSignal();

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        Boolean hasReEngaged = false;
        for (NbaTagService.Tag t : tags) {
            if (t.id == 'CD-05') {
                hasReEngaged = true;
                System.assertEquals('Re-engaged', t.chip, 'Chip should be Re-engaged');
            }
        }
        System.assert(hasReEngaged, 'Should generate CD-05 Re-engaged tag for Re_engage cadence');
    }

    // ─── Test: SLA Active tag ─────────────────────────────────────────

    @isTest
    static void testSlaActiveTag() {
        NbaActionController.ActionWrapper w = buildWrapper('SLA Response', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hoursSinceAssignment = 0.5; // 30 minutes

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        Boolean hasSla = false;
        for (NbaTagService.Tag t : tags) {
            if (t.id == 'TB-02') {
                hasSla = true;
                System.assertEquals('SLA Active', t.chip, 'Chip should be SLA Active');
            }
        }
        System.assert(hasSla, 'Should generate TB-02 SLA Active tag');
    }

    // ─── Test: No tags when minimal data ──────────────────────────────

    @isTest
    static void testMinimalDataReturnsMinimalTags() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        // With minimal data (no cadence, no scoring, no engagement, no time-bound),
        // should return 0 or very few tags
        System.assert(tags.size() <= 2, 'Minimal data should produce few tags, got ' + tags.size());
    }
}
