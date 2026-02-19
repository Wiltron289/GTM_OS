/**
 * Test class for NbaActionExpirationSchedulable (Phase 5 — Layer 1 expiry only).
 * Verifies scheduled execution runs expireStaleActions without errors.
 */
@isTest
private class NbaActionExpirationSchedulableTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'Expire Test Account',
            Entity_ID__c = 'EXP-001'
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
            Name = 'Expire Test Opp',
            AccountId = acc.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 3000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp.RecordTypeId = payrollRtId;
        insert opp;

        // Layer 1 time-bound action with DueAt well in the past (should be expired)
        NBA_Queue__c staleTimeBound = new NBA_Queue__c(
            Opportunity__c = opp.Id,
            Account__c = acc.Id,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'Pending',
            Action_Type__c = 'Meeting',
            Priority_Score__c = 0.90,
            Priority_Layer__c = 'Layer 1 - Time Bound',
            Priority_Bucket__c = 'Cadence Due Today',
            Is_Time_Bound__c = true,
            DueAt__c = Datetime.now().addHours(-1),
            Workflow_Mode__c = 'Pipeline'
        );
        insert staleTimeBound;
    }

    @isTest
    static void testSchedulableExecution_ExpiresStaleTimeBound() {
        Test.startTest();
        NbaActionExpirationSchedulable sched = new NbaActionExpirationSchedulable();
        sched.execute(null);
        Test.stopTest();

        // Verify stale time-bound action was expired
        List<NBA_Queue__c> actions = [
            SELECT Status__c FROM NBA_Queue__c
            WHERE Account__r.Name = 'Expire Test Account'
              AND Action_Type__c = 'Meeting'
              AND Is_Time_Bound__c = true
        ];
        System.assertEquals(1, actions.size(), 'Should find the time-bound action');
        System.assertEquals('Expired', actions[0].Status__c,
            'Stale Layer 1 time-bound action should be expired');
    }

    @isTest
    static void testScheduleMethod() {
        Test.startTest();
        NbaActionExpirationSchedulable.schedule();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'GTM Action Expiration - :%'
        ];
        System.assertEquals(6, jobs.size(), 'Should register 6 scheduled jobs (every 10 min)');
    }
}
