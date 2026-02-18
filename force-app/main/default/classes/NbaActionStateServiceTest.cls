/**
 * Test class for NbaActionStateService (Phase 5 — audit writer + cache invalidation).
 *
 * Verifies:
 * - completeAction writes audit record + updates persisted Layer 1
 * - snoozeAction writes audit with Snoozed_Until__c
 * - dismissAction writes audit with reason + category
 * - expireStaleActions expires only Layer 1 time-bound records
 * - On-demand (null actionId) path creates audit without DB update
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

        // Layer 1 persisted action (simulates trigger-created time-bound)
        NBA_Queue__c timeBound = new NBA_Queue__c(
            Opportunity__c = opp.Id,
            Account__c = acc.Id,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'In Progress',
            Action_Type__c = 'Meeting',
            Priority_Score__c = 0.90,
            Priority_Layer__c = 'Layer 1 - Time Bound',
            Priority_Bucket__c = 'Cadence Due Today',
            Is_Time_Bound__c = true,
            DueAt__c = Datetime.now().addHours(2),
            Workflow_Mode__c = 'Pipeline',
            Action_Instruction__c = 'Prepare for meeting'
        );
        insert timeBound;
    }

    // ─── Helpers ────────────────────────────────────────────────────

    private static NBA_Queue__c getTimeBoundAction() {
        return [
            SELECT Id, Status__c, Sales_Rep__c, Opportunity__c, Account__c
            FROM NBA_Queue__c
            WHERE Account__r.Name = 'State Test Account'
              AND Is_Time_Bound__c = true
              AND Status__c = 'In Progress'
            LIMIT 1
        ];
    }

    private static Opportunity getTestOpp() {
        return [SELECT Id, AccountId FROM Opportunity WHERE Account.Name = 'State Test Account' LIMIT 1];
    }

    private static Integer countAuditRecords(String status) {
        return [
            SELECT COUNT() FROM NBA_Queue__c
            WHERE Account__r.Name = 'State Test Account'
              AND Status__c = :status
              AND Actioned_Date__c != null
        ];
    }

    // ─── Complete Tests ─────────────────────────────────────────────

    @isTest
    static void testCompleteAction_PersistedLayerOne() {
        NBA_Queue__c action = getTimeBoundAction();
        Opportunity opp = getTestOpp();

        Test.startTest();
        NbaActionStateService.completeAction(
            action.Id, opp.Id, opp.AccountId, 'Meeting', 'Prepare for meeting', null
        );
        Test.stopTest();

        // Layer 1 record should be marked Completed
        NBA_Queue__c persisted = [SELECT Status__c, Completed_Date__c FROM NBA_Queue__c WHERE Id = :action.Id];
        System.assertEquals('Completed', persisted.Status__c, 'Persisted action should be Completed');
        System.assertNotEquals(null, persisted.Completed_Date__c, 'Completed_Date should be set');

        // Audit record should also be created
        System.assert(countAuditRecords('Completed') >= 1, 'Should have at least 1 Completed audit record');
    }

    @isTest
    static void testCompleteAction_OnDemandNullId() {
        Opportunity opp = getTestOpp();

        Test.startTest();
        NbaActionStateService.completeAction(
            null, opp.Id, opp.AccountId, 'Re-engage', 'Re-engage cold deal — 7 days inactive', null
        );
        Test.stopTest();

        // Should write audit record without touching any persisted action
        List<NBA_Queue__c> audits = [
            SELECT Status__c, Action_Type__c, CooldownUntil__c, Completed_Date__c
            FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id
              AND Action_Type__c = 'Re-engage'
              AND Status__c = 'Completed'
        ];
        System.assertEquals(1, audits.size(), 'Should create 1 audit record');
        System.assertNotEquals(null, audits[0].CooldownUntil__c, 'Cooldown should be set on complete');
        System.assertNotEquals(null, audits[0].Completed_Date__c, 'Completed_Date should be set');
    }

    @isTest
    static void testCompleteAction_CachInvalidated() {
        Opportunity opp = getTestOpp();
        Id userId = UserInfo.getUserId();

        // Pre-populate cache
        NbaActionController.ActionWrapper cached = new NbaActionController.ActionWrapper();
        cached.opportunityId = opp.Id;
        cached.actionType = 'Follow Up';
        NbaCacheService.cacheAction(userId, cached);
        System.assertNotEquals(null, NbaCacheService.getCachedAction(userId),
            'Cache should be populated before complete');

        Test.startTest();
        NbaActionStateService.completeAction(null, opp.Id, opp.AccountId, 'Follow Up', 'Follow up', null);
        Test.stopTest();

        System.assertEquals(null, NbaCacheService.getCachedAction(userId),
            'Cache should be invalidated after complete');
    }

    // ─── Snooze Tests ───────────────────────────────────────────────

    @isTest
    static void testSnoozeAction_WritesAudit() {
        Opportunity opp = getTestOpp();

        Test.startTest();
        NbaActionStateService.snoozeAction(
            null, opp.Id, opp.AccountId, 'First Touch',
            'Make initial contact', 'Busy right now', 30
        );
        Test.stopTest();

        List<NBA_Queue__c> audits = [
            SELECT Status__c, Snoozed_Until__c, Dismissed_Reason__c
            FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id
              AND Status__c = 'Snoozed'
        ];
        System.assertEquals(1, audits.size(), 'Should create 1 snoozed audit record');
        System.assertNotEquals(null, audits[0].Snoozed_Until__c, 'Snoozed_Until should be set');
        System.assertEquals('Busy right now', audits[0].Dismissed_Reason__c, 'Reason should be saved');
    }

    @isTest
    static void testSnoozeAction_PersistedLayerOne() {
        NBA_Queue__c action = getTimeBoundAction();
        Opportunity opp = getTestOpp();

        Test.startTest();
        NbaActionStateService.snoozeAction(
            action.Id, opp.Id, opp.AccountId, 'Meeting',
            'Prepare for meeting', 'Need more time', 60
        );
        Test.stopTest();

        // Layer 1 record should be marked Snoozed
        NBA_Queue__c persisted = [SELECT Status__c FROM NBA_Queue__c WHERE Id = :action.Id];
        System.assertEquals('Snoozed', persisted.Status__c, 'Persisted action should be Snoozed');
    }

    // ─── Dismiss Tests ──────────────────────────────────────────────

    @isTest
    static void testDismissAction_WritesAudit() {
        Opportunity opp = getTestOpp();

        Test.startTest();
        NbaActionStateService.dismissAction(
            null, opp.Id, opp.AccountId, 'Stage Progression',
            'Re-engage late-stage', 'Not relevant', 'Other'
        );
        Test.stopTest();

        List<NBA_Queue__c> audits = [
            SELECT Status__c, Dismissed_Reason__c, Dismissal_Category__c, CooldownUntil__c
            FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id
              AND Status__c = 'Dismissed'
        ];
        System.assertEquals(1, audits.size(), 'Should create 1 dismissed audit record');
        System.assertEquals('Not relevant', audits[0].Dismissed_Reason__c, 'Reason should be saved');
        System.assertEquals('Other', audits[0].Dismissal_Category__c, 'Category should be saved');
        System.assertNotEquals(null, audits[0].CooldownUntil__c, 'Cooldown should be set on dismiss');
    }

    @isTest
    static void testDismissAction_PersistedLayerOne() {
        NBA_Queue__c action = getTimeBoundAction();
        Opportunity opp = getTestOpp();

        Test.startTest();
        NbaActionStateService.dismissAction(
            action.Id, opp.Id, opp.AccountId, 'Meeting',
            'Prepare for meeting', 'Call Scheduled already', 'Call Scheduled'
        );
        Test.stopTest();

        NBA_Queue__c persisted = [SELECT Status__c FROM NBA_Queue__c WHERE Id = :action.Id];
        System.assertEquals('Dismissed', persisted.Status__c, 'Persisted action should be Dismissed');
    }

    // ─── Expiration Tests ───────────────────────────────────────────

    @isTest
    static void testExpireStaleActions_TimeboundPastDue() {
        // Create a time-bound action with DueAt well in the past
        Account acc2 = new Account(Name = 'Expire Test Account', Entity_ID__c = 'EXP-001');
        insert acc2;
        Opportunity opp2 = new Opportunity(
            Name = 'Expire Opp', AccountId = acc2.Id, StageName = 'New',
            CloseDate = Date.today().addDays(30), Amount = 3000, Source__c = 'N/A'
        );
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll' LIMIT 1];
        if (!rts.isEmpty()) opp2.RecordTypeId = rts[0].Id;
        insert opp2;

        NBA_Queue__c staleAction = new NBA_Queue__c(
            Opportunity__c = opp2.Id, Account__c = acc2.Id,
            Sales_Rep__c = UserInfo.getUserId(), Status__c = 'Pending',
            Action_Type__c = 'Meeting', Is_Time_Bound__c = true,
            DueAt__c = Datetime.now().addHours(-2),
            Priority_Score__c = 0.90, Priority_Layer__c = 'Layer 1 - Time Bound',
            Priority_Bucket__c = 'Cadence Due Today', Workflow_Mode__c = 'Pipeline'
        );
        insert staleAction;

        Test.startTest();
        Integer count = NbaActionStateService.expireStaleActions();
        Test.stopTest();

        NBA_Queue__c result = [SELECT Status__c FROM NBA_Queue__c WHERE Id = :staleAction.Id];
        System.assertEquals('Expired', result.Status__c, 'Past-due time-bound should expire');
        System.assert(count >= 1, 'Should expire at least 1 action');
    }

    @isTest
    static void testExpireStaleActions_FutureTimeboundNotExpired() {
        // The setup data has a time-bound action with DueAt 2 hours from now
        // It should NOT be expired
        Test.startTest();
        Integer count = NbaActionStateService.expireStaleActions();
        Test.stopTest();

        NBA_Queue__c action = getTimeBoundAction();
        System.assertEquals('In Progress', action.Status__c,
            'Future time-bound action should NOT be expired');
    }

    @isTest
    static void testExpireStaleActions_NonTimeBoundL1OlderThan24h() {
        // Create a non-time-bound L1 interrupt record and backdate it via
        // a low INTERRUPT_EXPIRE_HOURS threshold (test override)
        Account acc3 = new Account(Name = 'Interrupt Expire Account', Entity_ID__c = 'IEXP-001');
        insert acc3;
        Opportunity opp3 = new Opportunity(
            Name = 'Interrupt Expire Opp', AccountId = acc3.Id, StageName = 'New',
            CloseDate = Date.today().addDays(30), Amount = 2000, Source__c = 'N/A'
        );
        List<RecordType> rts3 = [SELECT Id FROM RecordType WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll' LIMIT 1];
        if (!rts3.isEmpty()) opp3.RecordTypeId = rts3[0].Id;
        insert opp3;

        NBA_Queue__c interruptAction = new NBA_Queue__c(
            Opportunity__c = opp3.Id, Account__c = acc3.Id,
            Sales_Rep__c = UserInfo.getUserId(), Status__c = 'Pending',
            Action_Type__c = 'First Touch', Is_Time_Bound__c = false,
            Priority_Score__c = 0.80, Priority_Layer__c = 'Layer 1 - Time Bound',
            Priority_Bucket__c = 'Cadence Due Today', Workflow_Mode__c = 'Pipeline',
            UniqueKey__c = 'V2|' + opp3.Id + '|First Touch|NewAssignment'
        );
        insert interruptAction;

        // Override expire threshold to 0 hours so the just-created record qualifies
        NbaActionStateService.INTERRUPT_EXPIRE_HOURS = 0;

        Test.startTest();
        Integer count = NbaActionStateService.expireStaleActions();
        Test.stopTest();

        NBA_Queue__c result = [SELECT Status__c, UniqueKey__c FROM NBA_Queue__c WHERE Id = :interruptAction.Id];
        System.assertEquals('Expired', result.Status__c,
            'Non-time-bound L1 interrupt older than threshold should expire');
        System.assertEquals(null, result.UniqueKey__c, 'UniqueKey should be cleared');
        System.assert(count >= 1, 'Should expire at least 1 action');
    }

    @isTest
    static void testExpireStaleActions_InvalidatesCacheForAffectedAEs() {
        Id userId = UserInfo.getUserId();

        // Pre-populate cache
        NbaActionController.ActionWrapper cached = new NbaActionController.ActionWrapper();
        cached.actionType = 'Meeting';
        NbaCacheService.cacheAction(userId, cached);

        // Create a stale time-bound action
        Account acc2 = new Account(Name = 'Cache Expire Account', Entity_ID__c = 'CEXP-001');
        insert acc2;
        Opportunity opp2 = new Opportunity(
            Name = 'Cache Expire Opp', AccountId = acc2.Id, StageName = 'New',
            CloseDate = Date.today().addDays(30), Amount = 1000, Source__c = 'N/A'
        );
        List<RecordType> rts = [SELECT Id FROM RecordType WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll' LIMIT 1];
        if (!rts.isEmpty()) opp2.RecordTypeId = rts[0].Id;
        insert opp2;

        NBA_Queue__c stale = new NBA_Queue__c(
            Opportunity__c = opp2.Id, Account__c = acc2.Id,
            Sales_Rep__c = userId, Status__c = 'In Progress',
            Action_Type__c = 'Meeting', Is_Time_Bound__c = true,
            DueAt__c = Datetime.now().addHours(-2),
            Priority_Score__c = 0.80, Priority_Layer__c = 'Layer 1 - Time Bound',
            Priority_Bucket__c = 'Cadence Due Today', Workflow_Mode__c = 'Pipeline'
        );
        insert stale;

        Test.startTest();
        NbaActionStateService.expireStaleActions();
        Test.stopTest();

        System.assertEquals(null, NbaCacheService.getCachedAction(userId),
            'Cache should be invalidated for AE with expired action');
    }
}
