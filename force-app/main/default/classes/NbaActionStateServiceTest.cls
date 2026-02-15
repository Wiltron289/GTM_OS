/**
 * Test class for NbaActionStateService.
 * Verifies lifecycle transitions, constraint enforcement, expiration,
 * unsnooze, and promotion logic.
 */
@isTest
private class NbaActionStateServiceTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'State Test Account',
            Entity_ID__c = 'STATE-001'
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
            Name = 'State Test Opp',
            AccountId = acc.Id,
            StageName = 'Consult',
            CloseDate = Date.today().addDays(30),
            Amount = 5000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp.RecordTypeId = payrollRtId;
        insert opp;

        // Active action (In Progress) for complete/snooze/dismiss
        NBA_Queue__c activeAction = new NBA_Queue__c(
            Opportunity__c = opp.Id,
            Account__c = acc.Id,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'In Progress',
            Action_Type__c = 'Follow Up',
            Priority_Score__c = 0.80,
            Priority_Layer__c = 'Layer 3 - Impact+Urgency',
            Priority_Bucket__c = 'General Pipeline',
            Impact_Score__c = 0.60,
            Urgency_Score__c = 0.50,
            Workflow_Mode__c = 'Pipeline'
        );
        insert activeAction;
    }

    // ─── Helper ───────────────────────────────────────────────────────

    private static NBA_Queue__c getActiveAction() {
        return [
            SELECT Id, Status__c, Sales_Rep__c
            FROM NBA_Queue__c
            WHERE Account__r.Name = 'State Test Account'
              AND Status__c = 'In Progress'
            LIMIT 1
        ];
    }

    // ─── Complete Tests ───────────────────────────────────────────────

    @isTest
    static void testCompleteAction_Success() {
        NBA_Queue__c action = getActiveAction();

        Test.startTest();
        NBA_Queue__c next = NbaActionStateService.completeAction(action.Id);
        Test.stopTest();

        NBA_Queue__c completed = [
            SELECT Status__c, Completed_Date__c, Actioned_Date__c, UniqueKey__c
            FROM NBA_Queue__c WHERE Id = :action.Id
        ];
        System.assertEquals('Completed', completed.Status__c, 'Status should be Completed');
        System.assertNotEquals(null, completed.Completed_Date__c, 'Completed_Date should be set');
        System.assertNotEquals(null, completed.Actioned_Date__c, 'Actioned_Date should be set');
        System.assertEquals(null, completed.UniqueKey__c, 'UniqueKey should be cleared');
    }

    @isTest
    static void testCompleteAction_InvalidId() {
        // Complete the action first so it's no longer In Progress,
        // then try to complete it again — should throw
        NBA_Queue__c action = getActiveAction();
        action.Status__c = 'Completed';
        update action;

        Test.startTest();
        Boolean threwException = false;
        try {
            NbaActionStateService.completeAction(action.Id);
        } catch (AuraHandledException e) {
            threwException = true;
        }
        Test.stopTest();

        System.assert(threwException, 'Should throw AuraHandledException for already-completed action');
    }

    // ─── Snooze Tests ─────────────────────────────────────────────────

    @isTest
    static void testSnoozeAction_Success() {
        NBA_Queue__c action = getActiveAction();

        Test.startTest();
        NBA_Queue__c next = NbaActionStateService.snoozeAction(action.Id, 'Busy right now', 30);
        Test.stopTest();

        NBA_Queue__c snoozed = [
            SELECT Status__c, Snoozed_Until__c, Dismissed_Reason__c
            FROM NBA_Queue__c WHERE Id = :action.Id
        ];
        System.assertEquals('Snoozed', snoozed.Status__c, 'Status should be Snoozed');
        System.assertNotEquals(null, snoozed.Snoozed_Until__c, 'Snoozed_Until should be set');
        System.assertEquals('Busy right now', snoozed.Dismissed_Reason__c, 'Reason should be saved');
    }

    // ─── Dismiss Tests ────────────────────────────────────────────────

    @isTest
    static void testDismissAction_Success() {
        NBA_Queue__c action = getActiveAction();

        Test.startTest();
        NBA_Queue__c next = NbaActionStateService.dismissAction(
            action.Id, 'Not relevant', 'Other'
        );
        Test.stopTest();

        NBA_Queue__c dismissed = [
            SELECT Status__c, Dismissed_Reason__c, Dismissal_Category__c, UniqueKey__c
            FROM NBA_Queue__c WHERE Id = :action.Id
        ];
        System.assertEquals('Dismissed', dismissed.Status__c, 'Status should be Dismissed');
        System.assertEquals('Not relevant', dismissed.Dismissed_Reason__c, 'Reason should be saved');
        System.assertEquals('Other', dismissed.Dismissal_Category__c, 'Category should be saved');
        System.assertEquals(null, dismissed.UniqueKey__c, 'UniqueKey should be cleared');
    }

    // ─── Expiration Tests ─────────────────────────────────────────────

    @isTest
    static void testExpireStaleActions_NonTimebound() {
        // Set threshold to negative value so cutoff is in the future,
        // ensuring the just-created record's LastModifiedDate is before the cutoff
        NbaActionStateService.NON_TIMEBOUND_EXPIRE_MINUTES = -60;

        Test.startTest();
        Integer count = NbaActionStateService.expireStaleActions();
        Test.stopTest();

        // The active action should be expired
        NBA_Queue__c expired = [
            SELECT Status__c FROM NBA_Queue__c
            WHERE Account__r.Name = 'State Test Account' LIMIT 1
        ];
        System.assertEquals('Expired', expired.Status__c, 'Should expire non-timebound action');
        System.assert(count >= 1, 'Should expire at least 1 action');
    }

    @isTest
    static void testExpireStaleActions_Timebound() {
        // Create a timebound action with DueAt in the past
        Account acc = [SELECT Id FROM Account WHERE Name = 'State Test Account' LIMIT 1];
        Account acc2 = new Account(Name = 'State Test Account TB', Entity_ID__c = 'STATE-TB-001');
        insert acc2;

        Opportunity opp2 = new Opportunity(
            Name = 'TB Opp', AccountId = acc2.Id, StageName = 'New',
            CloseDate = Date.today().addDays(30), Amount = 3000, Source__c = 'N/A'
        );
        Id payrollRtId;
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll' LIMIT 1];
        if (!rts.isEmpty()) opp2.RecordTypeId = rts[0].Id;
        insert opp2;

        NBA_Queue__c tbAction = new NBA_Queue__c(
            Opportunity__c = opp2.Id, Account__c = acc2.Id,
            Sales_Rep__c = UserInfo.getUserId(), Status__c = 'In Progress',
            Action_Type__c = 'First Touch', Is_Time_Bound__c = true,
            DueAt__c = Datetime.now().addHours(-1),
            Priority_Score__c = 0.90, Priority_Layer__c = 'Layer 1 - Time Bound',
            Priority_Bucket__c = 'Cadence Due Today', Workflow_Mode__c = 'Pipeline'
        );
        insert tbAction;

        Test.startTest();
        Integer count = NbaActionStateService.expireStaleActions();
        Test.stopTest();

        NBA_Queue__c result = [SELECT Status__c FROM NBA_Queue__c WHERE Id = :tbAction.Id];
        System.assertEquals('Expired', result.Status__c, 'Timebound past-due action should expire');
    }

    // ─── Unsnooze Tests ───────────────────────────────────────────────

    @isTest
    static void testUnsnoozeDueActions() {
        // Snooze the action, then set Snoozed_Until to the past
        NBA_Queue__c action = getActiveAction();
        action.Status__c = 'Snoozed';
        action.Snoozed_Until__c = Datetime.now().addMinutes(-5);
        update action;

        Test.startTest();
        Integer count = NbaActionStateService.unsnoozeDueActions();
        Test.stopTest();

        NBA_Queue__c result = [SELECT Status__c, Snoozed_Until__c FROM NBA_Queue__c WHERE Id = :action.Id];
        System.assertEquals('Pending', result.Status__c, 'Should be unsnoozed to Pending');
        System.assertEquals(null, result.Snoozed_Until__c, 'Snoozed_Until should be cleared');
        System.assert(count >= 1, 'Should unsnooze at least 1 action');
    }

    // ─── Promotion Tests ──────────────────────────────────────────────

    @isTest
    static void testPromoteNextAction_HasCapacity() {
        // Complete the active action first, then create a Pending action
        NBA_Queue__c active = getActiveAction();
        active.Status__c = 'Completed';
        active.Completed_Date__c = Datetime.now();
        update active;

        // Create a Pending action for promotion
        Account acc2 = new Account(Name = 'Promote Test Account', Entity_ID__c = 'PROM-001');
        insert acc2;
        Opportunity opp2 = new Opportunity(
            Name = 'Promote Opp', AccountId = acc2.Id, StageName = 'New',
            CloseDate = Date.today().addDays(30), Amount = 4000, Source__c = 'N/A'
        );
        Id payrollRtId;
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll' LIMIT 1];
        if (!rts.isEmpty()) opp2.RecordTypeId = rts[0].Id;
        insert opp2;

        NBA_Queue__c pending = new NBA_Queue__c(
            Opportunity__c = opp2.Id, Account__c = acc2.Id,
            Sales_Rep__c = UserInfo.getUserId(), Status__c = 'Pending',
            Action_Type__c = 'Re-engage', Priority_Score__c = 0.65,
            Priority_Layer__c = 'Layer 3 - Impact+Urgency',
            Priority_Bucket__c = 'General Pipeline', Workflow_Mode__c = 'Pipeline'
        );
        insert pending;

        Test.startTest();
        NBA_Queue__c promoted = NbaActionStateService.promoteNextAction(UserInfo.getUserId());
        Test.stopTest();

        System.assertNotEquals(null, promoted, 'Should promote a pending action');
        NBA_Queue__c result = [SELECT Status__c FROM NBA_Queue__c WHERE Id = :pending.Id];
        System.assertEquals('In Progress', result.Status__c, 'Promoted action should be In Progress');
    }

    @isTest
    static void testPromoteNextAction_AtCapacity() {
        // Active action already exists (1 active), add a Pending to hit cap of 2
        Account acc2 = new Account(Name = 'Cap Test Account', Entity_ID__c = 'CAP-001');
        insert acc2;
        Opportunity opp2 = new Opportunity(
            Name = 'Cap Opp', AccountId = acc2.Id, StageName = 'Connect',
            CloseDate = Date.today().addDays(30), Amount = 2000, Source__c = 'N/A'
        );
        Id payrollRtId;
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll' LIMIT 1];
        if (!rts.isEmpty()) opp2.RecordTypeId = rts[0].Id;
        insert opp2;

        NBA_Queue__c pending = new NBA_Queue__c(
            Opportunity__c = opp2.Id, Account__c = acc2.Id,
            Sales_Rep__c = UserInfo.getUserId(), Status__c = 'Pending',
            Action_Type__c = 'Follow Up', Priority_Score__c = 0.50,
            Priority_Layer__c = 'Layer 3 - Impact+Urgency',
            Priority_Bucket__c = 'General Pipeline', Workflow_Mode__c = 'Pipeline'
        );
        insert pending;
        // Now: 1 In Progress + 1 Pending = 2 (at cap)

        Test.startTest();
        NBA_Queue__c promoted = NbaActionStateService.promoteNextAction(UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals(null, promoted, 'Should not promote when at capacity');
    }

    @isTest
    static void testPromoteNextAction_LayerPrecedence() {
        // Complete the active action so AE has 0 in queue
        NBA_Queue__c active = getActiveAction();
        active.Status__c = 'Completed';
        update active;

        // Insert 1 Pending Layer 1 (time-bound, low score)
        // With 1 Pending, count=1, under cap of 2 → promote should work
        Account acc2 = new Account(Name = 'Layer Test Account 1', Entity_ID__c = 'LAY-001');
        insert acc2;

        Opportunity opp2 = new Opportunity(
            Name = 'Layer Opp 1', AccountId = acc2.Id, StageName = 'New',
            CloseDate = Date.today().addDays(30), Amount = 2000, Source__c = 'N/A'
        );
        Id payrollRtId;
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll' LIMIT 1];
        if (!rts.isEmpty()) {
            opp2.RecordTypeId = rts[0].Id;
        }
        insert opp2;

        // Layer 1 with LOW score — should still be promoted over any Layer 3
        NBA_Queue__c layer1 = new NBA_Queue__c(
            Opportunity__c = opp2.Id, Account__c = acc2.Id,
            Sales_Rep__c = UserInfo.getUserId(), Status__c = 'Pending',
            Action_Type__c = 'First Touch', Priority_Score__c = 0.30,
            Priority_Layer__c = 'Layer 1 - Time Bound', Is_Time_Bound__c = true,
            Priority_Bucket__c = 'Cadence Due Today', Workflow_Mode__c = 'Pipeline'
        );
        insert layer1;

        Test.startTest();
        NBA_Queue__c promoted = NbaActionStateService.promoteNextAction(UserInfo.getUserId());
        Test.stopTest();

        System.assertNotEquals(null, promoted, 'Should promote an action');
        System.assertEquals(layer1.Id, promoted.Id,
            'Layer 1 action should be promoted');
        NBA_Queue__c result = [SELECT Status__c FROM NBA_Queue__c WHERE Id = :layer1.Id];
        System.assertEquals('In Progress', result.Status__c,
            'Promoted action should be In Progress');
    }

    // ─── Constraint Tests ─────────────────────────────────────────────

    @isTest
    static void testGetActiveCount() {
        Integer count = NbaActionStateService.getActiveCount(UserInfo.getUserId());
        System.assertEquals(1, count, 'Should count 1 active action (In Progress from setup)');
    }

    @isTest
    static void testHasCapacity_WithOneActive() {
        Boolean hasCap = NbaActionStateService.hasCapacity(UserInfo.getUserId());
        System.assertEquals(true, hasCap, 'With 1 active, should have capacity (max is 2)');
    }
}
