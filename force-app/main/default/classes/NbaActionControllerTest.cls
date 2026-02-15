/**
 * Test class for NbaActionController.
 * Verifies getActiveAction, completeAction, snoozeAction, dismissAction
 * through the thin controller layer.
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

        // Active action (In Progress)
        NBA_Queue__c activeAction = new NBA_Queue__c(
            Opportunity__c = opp.Id,
            Account__c = acc.Id,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'In Progress',
            Action_Type__c = 'Follow Up',
            Action_Instruction__c = 'Call to discuss payroll migration',
            ReasonText__c = 'High MRR account with stalled deal',
            Priority_Score__c = 0.80,
            Priority_Layer__c = 'Layer 3 - Impact+Urgency',
            Priority_Bucket__c = 'General Pipeline',
            Impact_Score__c = 0.60,
            Urgency_Score__c = 0.50,
            Workflow_Mode__c = 'Pipeline'
        );
        insert activeAction;
    }

    // ─── Helpers ────────────────────────────────────────────────────

    private static NBA_Queue__c getActiveAction() {
        return [
            SELECT Id, Status__c, Sales_Rep__c, Opportunity__c
            FROM NBA_Queue__c
            WHERE Account__r.Name = 'Controller Test Account'
              AND Status__c = 'In Progress'
            LIMIT 1
        ];
    }

    private static NBA_Queue__c createPendingAction() {
        Account acc2 = new Account(Name = 'Ctrl Pending Account', Entity_ID__c = 'CTRL-P-001');
        insert acc2;

        Opportunity opp2 = new Opportunity(
            Name = 'Ctrl Pending Opp',
            AccountId = acc2.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 3000,
            Source__c = 'N/A'
        );
        Id payrollRtId;
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll'
            LIMIT 1
        ];
        if (!rts.isEmpty()) opp2.RecordTypeId = rts[0].Id;
        insert opp2;

        NBA_Queue__c pending = new NBA_Queue__c(
            Opportunity__c = opp2.Id,
            Account__c = acc2.Id,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'Pending',
            Action_Type__c = 'Re-engage',
            Action_Instruction__c = 'Re-engage stalled opportunity',
            Priority_Score__c = 0.65,
            Priority_Layer__c = 'Layer 3 - Impact+Urgency',
            Priority_Bucket__c = 'General Pipeline',
            Workflow_Mode__c = 'Pipeline'
        );
        insert pending;
        return pending;
    }

    // ─── getActiveAction Tests ──────────────────────────────────────

    @isTest
    static void testGetActiveAction_returnsInProgressAction() {
        Test.startTest();
        NbaActionController.ActionWrapper result = NbaActionController.getActiveAction();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return an active action');
        System.assertEquals('In Progress', result.status, 'Status should be In Progress');
        System.assertEquals('Follow Up', result.actionType, 'Action type should match');
        System.assertNotEquals(null, result.opportunityId, 'Opportunity ID should be populated');
        System.assertNotEquals(null, result.accountName, 'Account name should be populated via relationship');
        System.assertEquals('Call to discuss payroll migration', result.actionInstruction, 'Instruction should match');
    }

    @isTest
    static void testGetActiveAction_promotesWhenNoneActive() {
        // Complete the existing active action
        NBA_Queue__c active = getActiveAction();
        active.Status__c = 'Completed';
        active.Completed_Date__c = Datetime.now();
        update active;

        // Create a pending action to be promoted
        NBA_Queue__c pending = createPendingAction();

        Test.startTest();
        NbaActionController.ActionWrapper result = NbaActionController.getActiveAction();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should promote and return the pending action');
        System.assertEquals('In Progress', result.status, 'Promoted action should be In Progress');
        System.assertEquals(pending.Id, result.actionId, 'Should return the promoted action');
    }

    @isTest
    static void testGetActiveAction_returnsNullWhenEmpty() {
        // Complete the active action, leave no pending
        NBA_Queue__c active = getActiveAction();
        active.Status__c = 'Completed';
        active.Completed_Date__c = Datetime.now();
        update active;

        Test.startTest();
        NbaActionController.ActionWrapper result = NbaActionController.getActiveAction();
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null when no actions exist');
    }

    // ─── completeAction Tests ───────────────────────────────────────

    @isTest
    static void testCompleteAction_returnsNextAction() {
        NBA_Queue__c active = getActiveAction();
        // Create a pending action so there's something to promote after complete
        NBA_Queue__c pending = createPendingAction();

        Test.startTest();
        NbaActionController.ActionResultWrapper result = NbaActionController.completeAction(active.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.hasNext, 'Should have a next action');
        System.assertNotEquals(null, result.nextAction, 'Next action should be populated');
        System.assertEquals(pending.Id, result.nextAction.actionId, 'Next action should be the promoted pending');

        // Verify the original action is completed
        NBA_Queue__c completed = [SELECT Status__c FROM NBA_Queue__c WHERE Id = :active.Id];
        System.assertEquals('Completed', completed.Status__c, 'Original action should be Completed');
    }

    @isTest
    static void testCompleteAction_returnsNullWhenNoNext() {
        NBA_Queue__c active = getActiveAction();

        Test.startTest();
        NbaActionController.ActionResultWrapper result = NbaActionController.completeAction(active.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(false, result.hasNext, 'Should have no next action');
        System.assertEquals(null, result.nextAction, 'Next action should be null');
    }

    @isTest
    static void testCompleteAction_invalidIdThrowsException() {
        // Complete the action first so it can't be completed again
        NBA_Queue__c active = getActiveAction();
        active.Status__c = 'Completed';
        update active;

        Test.startTest();
        Boolean threwException = false;
        try {
            NbaActionController.completeAction(active.Id);
        } catch (AuraHandledException e) {
            threwException = true;
        }
        Test.stopTest();

        System.assert(threwException, 'Should throw AuraHandledException for already-completed action');
    }

    // ─── snoozeAction Tests ─────────────────────────────────────────

    @isTest
    static void testSnoozeAction_returnsNextAction() {
        NBA_Queue__c active = getActiveAction();
        NBA_Queue__c pending = createPendingAction();

        Test.startTest();
        NbaActionController.ActionResultWrapper result = NbaActionController.snoozeAction(
            active.Id, 'In a meeting', 60
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.hasNext, 'Should have a next action');
        System.assertNotEquals(null, result.nextAction, 'Next action should be populated');

        // Verify original is snoozed
        NBA_Queue__c snoozed = [SELECT Status__c, Snoozed_Until__c FROM NBA_Queue__c WHERE Id = :active.Id];
        System.assertEquals('Snoozed', snoozed.Status__c, 'Original should be Snoozed');
        System.assertNotEquals(null, snoozed.Snoozed_Until__c, 'Snoozed_Until should be set');
    }

    @isTest
    static void testSnoozeAction_invalidIdThrowsException() {
        NBA_Queue__c active = getActiveAction();
        active.Status__c = 'Completed';
        update active;

        Test.startTest();
        Boolean threwException = false;
        try {
            NbaActionController.snoozeAction(active.Id, 'test', 30);
        } catch (AuraHandledException e) {
            threwException = true;
        }
        Test.stopTest();

        System.assert(threwException, 'Should throw AuraHandledException for non-snoozable action');
    }

    // ─── dismissAction Tests ────────────────────────────────────────

    @isTest
    static void testDismissAction_returnsNextAction() {
        NBA_Queue__c active = getActiveAction();
        NBA_Queue__c pending = createPendingAction();

        Test.startTest();
        NbaActionController.ActionResultWrapper result = NbaActionController.dismissAction(
            active.Id, 'Not relevant right now', 'Other'
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals(true, result.hasNext, 'Should have a next action');

        // Verify original is dismissed
        NBA_Queue__c dismissed = [
            SELECT Status__c, Dismissed_Reason__c, Dismissal_Category__c
            FROM NBA_Queue__c WHERE Id = :active.Id
        ];
        System.assertEquals('Dismissed', dismissed.Status__c, 'Original should be Dismissed');
        System.assertEquals('Not relevant right now', dismissed.Dismissed_Reason__c, 'Reason should be saved');
        System.assertEquals('Other', dismissed.Dismissal_Category__c, 'Category should be saved');
    }

    @isTest
    static void testDismissAction_invalidIdThrowsException() {
        NBA_Queue__c active = getActiveAction();
        active.Status__c = 'Completed';
        update active;

        Test.startTest();
        Boolean threwException = false;
        try {
            NbaActionController.dismissAction(active.Id, 'test', 'Other');
        } catch (AuraHandledException e) {
            threwException = true;
        }
        Test.stopTest();

        System.assert(threwException, 'Should throw AuraHandledException for non-dismissable action');
    }
}
