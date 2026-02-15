/**
 * Test class for NbaActionExpirationSchedulable.
 * Verifies scheduled execution runs expire + unsnooze without errors.
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

        // Snoozed action with Snoozed_Until in the past
        NBA_Queue__c snoozedAction = new NBA_Queue__c(
            Opportunity__c = opp.Id,
            Account__c = acc.Id,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'Snoozed',
            Snoozed_Until__c = Datetime.now().addMinutes(-10),
            Action_Type__c = 'Follow Up',
            Priority_Score__c = 0.50,
            Priority_Layer__c = 'Layer 3 - Impact+Urgency',
            Priority_Bucket__c = 'General Pipeline',
            Workflow_Mode__c = 'Pipeline'
        );
        insert snoozedAction;
    }

    @isTest
    static void testSchedulableExecution() {
        Test.startTest();
        NbaActionExpirationSchedulable sched = new NbaActionExpirationSchedulable();
        sched.execute(null);
        Test.stopTest();

        // Verify snoozed action was moved to Pending
        List<NBA_Queue__c> unsnoozed = [
            SELECT Status__c FROM NBA_Queue__c
            WHERE Account__r.Name = 'Expire Test Account'
              AND Action_Type__c = 'Follow Up'
        ];
        System.assertEquals(1, unsnoozed.size(), 'Should find the unsnoozed action');
        System.assertEquals('Pending', unsnoozed[0].Status__c,
            'Snoozed action with past due date should be unsnoozed to Pending');
    }

    @isTest
    static void testScheduleMethod() {
        Test.startTest();
        NbaActionExpirationSchedulable.schedule();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'NBA Action Expiration - :%'
        ];
        System.assertEquals(6, jobs.size(), 'Should register 6 scheduled jobs (every 10 min)');
    }
}
