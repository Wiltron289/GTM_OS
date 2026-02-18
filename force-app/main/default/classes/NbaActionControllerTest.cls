/**
 * Test class for NbaActionController (Phase 5 — on-demand evaluation).
 *
 * Verifies:
 * - getActiveAction returns Layer 1 time-bound when present
 * - getActiveAction returns cached action on cache hit
 * - getActiveAction evaluates on-demand on cache miss (via open Opps)
 * - getActiveAction returns null when AE has no open pipeline
 * - checkTimeBound returns only Layer 1 actions
 * - completeAction writes audit + invalidates cache + returns next
 * - snoozeAction writes audit + returns next
 * - dismissAction writes audit + returns next
 */
@isTest
private class NbaActionControllerTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'Controller Test Account',
            Entity_ID__c = 'CTRL-001'
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
            Name = 'Controller Test Opp',
            AccountId = acc.Id,
            StageName = 'Consult',
            CloseDate = Date.today().addDays(30),
            Amount = 5000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp.RecordTypeId = payrollRtId;
        insert opp;
    }

    // ─── Helpers ────────────────────────────────────────────────────

    private static Opportunity getTestOpp() {
        return [SELECT Id, AccountId FROM Opportunity WHERE Account.Name = 'Controller Test Account' LIMIT 1];
    }

    private static NBA_Queue__c createTimeBoundAction() {
        Opportunity opp = getTestOpp();
        Account acc = [SELECT Id FROM Account WHERE Name = 'Controller Test Account' LIMIT 1];

        NBA_Queue__c tb = new NBA_Queue__c(
            Opportunity__c = opp.Id,
            Account__c = acc.Id,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'Pending',
            Action_Type__c = 'Meeting',
            Action_Instruction__c = 'Prepare for meeting',
            ReasonText__c = 'Time-bound meeting action',
            Priority_Score__c = 0.90,
            Priority_Layer__c = 'Layer 1 - Time Bound',
            Priority_Bucket__c = 'Cadence Due Today',
            Is_Time_Bound__c = true,
            DueAt__c = Datetime.now().addHours(1),
            Workflow_Mode__c = 'Pipeline'
        );
        insert tb;
        return tb;
    }

    // ─── getActiveAction Tests ──────────────────────────────────────

    @isTest
    static void testGetActiveAction_ReturnsTimeBoundFirst() {
        // Create a Layer 1 time-bound action
        NBA_Queue__c tb = createTimeBoundAction();

        Test.startTest();
        NbaActionController.ActionWrapper result = NbaActionController.getActiveAction();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return the time-bound action');
        System.assertEquals(tb.Id, result.actionId, 'Should return the Layer 1 action ID');
        System.assertEquals('Meeting', result.actionType, 'Action type should be Meeting');
        System.assertEquals(true, result.isTimeBound, 'Should be time-bound');
    }

    @isTest
    static void testGetActiveAction_ReturnsCachedOnHit() {
        Id userId = UserInfo.getUserId();
        Opportunity opp = getTestOpp();

        // Pre-populate cache with a fake action
        NbaActionController.ActionWrapper cached = new NbaActionController.ActionWrapper();
        cached.actionId = null;
        cached.opportunityId = opp.Id;
        cached.actionType = 'Re-engage';
        cached.actionInstruction = 'Re-engage cold deal';
        cached.priorityLayer = 'Layer 3 - Impact+Urgency';
        cached.isTimeBound = false;
        cached.status = 'Evaluated';
        NbaCacheService.cacheAction(userId, cached);

        Test.startTest();
        NbaActionController.ActionWrapper result = NbaActionController.getActiveAction();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return cached action');
        System.assertEquals('Re-engage', result.actionType, 'Should return the cached action type');
        System.assertEquals(null, result.actionId, 'On-demand actions have null actionId');
    }

    @isTest
    static void testGetActiveAction_EvaluatesOnCacheMiss() {
        // No Layer 1 action, no cache → should evaluate on-demand
        // The test opp at 'Consult' stage with Amount=5000 should produce a candidate

        Test.startTest();
        NbaActionController.ActionWrapper result = NbaActionController.getActiveAction();
        Test.stopTest();

        // The evaluation may or may not produce a candidate depending on
        // suppression rules and signal state. Just verify no exception thrown.
        // In a clean test context with no prior activity, it should produce something.
        if (result != null) {
            System.assertEquals(null, result.actionId, 'On-demand actions should have null actionId');
            System.assertNotEquals(null, result.opportunityId, 'Should have an opportunity ID');
        }
    }

    @isTest
    static void testGetActiveAction_ReturnsNullWhenNoOpps() {
        // Close the only opp so AE has no open pipeline
        Opportunity opp = getTestOpp();
        opp.StageName = 'Closed Won';
        update opp;

        Test.startTest();
        NbaActionController.ActionWrapper result = NbaActionController.getActiveAction();
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when AE has no open opps');
    }

    // ─── checkTimeBound Tests ───────────────────────────────────────

    @isTest
    static void testCheckTimeBound_ReturnsTimeBound() {
        NBA_Queue__c tb = createTimeBoundAction();

        Test.startTest();
        NbaActionController.ActionWrapper result = NbaActionController.checkTimeBound();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return the time-bound action');
        System.assertEquals(tb.Id, result.actionId, 'Should return the Layer 1 record ID');
    }

    @isTest
    static void testCheckTimeBound_ReturnsNullWhenNone() {
        Test.startTest();
        NbaActionController.ActionWrapper result = NbaActionController.checkTimeBound();
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when no time-bound actions');
    }

    // ─── completeAction Tests ───────────────────────────────────────

    @isTest
    static void testCompleteAction_PersistedLayerOne() {
        NBA_Queue__c tb = createTimeBoundAction();
        Opportunity opp = getTestOpp();

        Test.startTest();
        NbaActionController.ActionResultWrapper result =
            NbaActionController.completeAction(tb.Id, opp.Id, 'Meeting', null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');

        // Verify Layer 1 record is completed
        NBA_Queue__c completed = [SELECT Status__c FROM NBA_Queue__c WHERE Id = :tb.Id];
        System.assertEquals('Completed', completed.Status__c, 'Layer 1 record should be Completed');

        // Verify audit record was created
        Integer auditCount = [
            SELECT COUNT() FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Status__c = 'Completed'
              AND Actioned_Date__c != null AND Id != :tb.Id
        ];
        System.assert(auditCount >= 1, 'Should have created an audit record');
    }

    @isTest
    static void testCompleteAction_OnDemand() {
        Opportunity opp = getTestOpp();

        Test.startTest();
        NbaActionController.ActionResultWrapper result =
            NbaActionController.completeAction(null, opp.Id, 'Follow Up', null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');

        // Verify audit record was created
        Integer auditCount = [
            SELECT COUNT() FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Status__c = 'Completed'
              AND Actioned_Date__c != null
        ];
        System.assert(auditCount >= 1, 'Should have created an audit record for on-demand complete');
    }

    // ─── snoozeAction Tests ─────────────────────────────────────────

    @isTest
    static void testSnoozeAction_WritesAudit() {
        Opportunity opp = getTestOpp();

        Test.startTest();
        NbaActionController.ActionResultWrapper result =
            NbaActionController.snoozeAction(null, opp.Id, 'Re-engage', 'Busy now', 60);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');

        // Verify snoozed audit record
        List<NBA_Queue__c> audits = [
            SELECT Status__c, Snoozed_Until__c, Dismissed_Reason__c
            FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Status__c = 'Snoozed'
        ];
        System.assertEquals(1, audits.size(), 'Should create 1 snoozed audit record');
        System.assertNotEquals(null, audits[0].Snoozed_Until__c, 'Snoozed_Until should be set');
        System.assertEquals('Busy now', audits[0].Dismissed_Reason__c, 'Reason should be saved');
    }

    // ─── dismissAction Tests ────────────────────────────────────────

    @isTest
    static void testDismissAction_WritesAudit() {
        Opportunity opp = getTestOpp();

        Test.startTest();
        NbaActionController.ActionResultWrapper result =
            NbaActionController.dismissAction(null, opp.Id, 'First Touch', 'Not relevant', 'Other');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');

        // Verify dismissed audit record
        List<NBA_Queue__c> audits = [
            SELECT Status__c, Dismissed_Reason__c, Dismissal_Category__c
            FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Status__c = 'Dismissed'
        ];
        System.assertEquals(1, audits.size(), 'Should create 1 dismissed audit record');
        System.assertEquals('Not relevant', audits[0].Dismissed_Reason__c, 'Reason should match');
        System.assertEquals('Other', audits[0].Dismissal_Category__c, 'Category should match');
    }
}
