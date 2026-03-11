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

    // ─── Time-Bound: Only rationale tag ─────────────────────────────

    @isTest
    static void testTimeBound_MeetingShowsOnlyRationale() {
        Datetime meetingTime = Datetime.now().addMinutes(10);
        NbaActionController.ActionWrapper w = buildWrapper('Meeting', true, meetingTime);
        NbaSignalService.OpportunitySignal sig = buildSignal();

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        System.assertEquals(1, tags.size(), 'Time-bound meeting should produce exactly 1 tag');
        System.assertEquals('TB-01', tags[0].id, 'Should be TB-01');
        System.assertEquals('Meeting Upcoming', tags[0].chip, 'Chip should be Meeting Upcoming');
        System.assertEquals('Time-Bound', tags[0].category, 'Category should be Time-Bound');
    }

    @isTest
    static void testTimeBound_NewAssignmentShowsOnlyRationale() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', true, Datetime.now());
        NbaSignalService.OpportunitySignal sig = buildSignal();

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        System.assertEquals(1, tags.size(), 'Time-bound assignment should produce exactly 1 tag');
        System.assertEquals('TB-02', tags[0].id, 'Should be TB-02');
        System.assertEquals('Newly Assigned', tags[0].chip, 'Chip should be Newly Assigned');
    }

    @isTest
    static void testTimeBound_FollowUpShowsOnlyRationale() {
        NbaActionController.ActionWrapper w = buildWrapper('Follow Up', true, Datetime.now());
        NbaSignalService.OpportunitySignal sig = buildSignal();

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        System.assertEquals(1, tags.size(), 'Time-bound follow-up should produce exactly 1 tag');
        System.assertEquals('TB-03', tags[0].id, 'Should be TB-03');
        System.assertEquals('Follow-Up Due', tags[0].chip, 'Chip should be Follow-Up Due');
    }

    @isTest
    static void testTimeBound_IgnoresDsDriversEvenIfPresent() {
        NbaActionController.ActionWrapper w = buildWrapper('Meeting', true, Datetime.now().addMinutes(5));
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = true;
        sig.payrollTopDrivers = 'Growing team size, high hiring activity (9d)';
        sig.likelihoodToWin = 0.85;

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        System.assertEquals(1, tags.size(), 'Time-bound should show only rationale even with DS data');
        System.assertEquals('Time-Bound', tags[0].category, 'Should be Time-Bound category only');
    }

    // ─── Engine: DS Driver Tags ─────────────────────────────────────

    @isTest
    static void testEngine_ParsesDriverTags() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = true;
        sig.payrollTopDrivers = 'Growing team size, high hiring activity (9d), essential tier';

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        System.assertEquals(3, tags.size(), 'Should parse 3 driver tags');
        System.assertEquals('Signal', tags[0].category, 'All tags should be Signal category');
        System.assertEquals('Growing Team', tags[0].chip, 'First driver should map to Growing Team');
        System.assertEquals('Hiring Surge', tags[1].chip, 'Second driver should map to Hiring Surge');
        System.assertEquals('Room to Grow', tags[2].chip, 'Third driver should map to Room to Grow');
    }

    @isTest
    static void testEngine_UnknownDriverFallsBackToRawText() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = true;
        sig.payrollTopDrivers = 'some unknown driver from DS';

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        System.assertEquals(1, tags.size(), 'Should still generate 1 tag for unknown driver');
        System.assertEquals('Signal', tags[0].category, 'Category should be Signal');
        System.assertEquals('some unknown driver from DS', tags[0].expanded,
            'Expanded text should be the raw driver string');
    }

    @isTest
    static void testEngine_NoDrivers_NoTags() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = true;
        sig.payrollTopDrivers = null;

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        System.assertEquals(0, tags.size(), 'No drivers should produce no tags');
    }

    @isTest
    static void testEngine_NoAccountScoring_NoTags() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = false;

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        System.assertEquals(0, tags.size(), 'No account scoring should produce no tags');
    }

    @isTest
    static void testEngine_MaxFourTags() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = true;
        sig.payrollTopDrivers = 'Growing team size, high hiring activity (9d), essential tier, steady usage growth, new location';

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        System.assert(tags.size() <= 4, 'Should cap at 4 tags, got ' + tags.size());
    }

    @isTest
    static void testEngine_StripsParentheticalForMatching() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = true;
        sig.payrollTopDrivers = 'Spike in timeclock punches (3d), High timeclock usage (30d)';

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        Test.stopTest();

        System.assertEquals(2, tags.size(), 'Should parse 2 drivers');
        System.assertEquals('Timeclock Spike', tags[0].chip, 'Should match despite (3d) suffix');
        System.assertEquals('Heavy Timeclock', tags[1].chip, 'Should match despite (30d) suffix');
    }

    // ─── JSON Serialization ─────────────────────────────────────────

    @isTest
    static void testJsonOutputFormat() {
        NbaActionController.ActionWrapper w = buildWrapper('First Touch', false, null);
        NbaSignalService.OpportunitySignal sig = buildSignal();
        sig.hasAccountScoring = true;
        sig.payrollTopDrivers = 'Growing team size';

        Test.startTest();
        List<NbaTagService.Tag> tags = NbaTagService.generateTags(w, sig);
        String jsonStr = NbaTagService.toJson(tags);
        Test.stopTest();

        System.assertNotEquals(null, jsonStr, 'JSON should not be null');

        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(jsonStr);
        System.assertEquals(1, parsed.size(), 'Should have 1 tag in JSON');

        Map<String, Object> firstTag = (Map<String, Object>) parsed[0];
        System.assert(firstTag.containsKey('id'), 'Tag should have id field');
        System.assert(firstTag.containsKey('category'), 'Tag should have category field');
        System.assert(firstTag.containsKey('chip'), 'Tag should have chip field');
        System.assert(firstTag.containsKey('expanded'), 'Tag should have expanded field');
    }

    @isTest
    static void testToJsonNullEmpty() {
        Test.startTest();
        String json1 = NbaTagService.toJson(null);
        String json2 = NbaTagService.toJson(new List<NbaTagService.Tag>());
        Test.stopTest();

        System.assertEquals(null, json1, 'Null tags should return null JSON');
        System.assertEquals(null, json2, 'Empty tags should return null JSON');
    }

    // ─── Null/Empty Inputs ──────────────────────────────────────────

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
}
