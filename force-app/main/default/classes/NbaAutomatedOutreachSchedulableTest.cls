@isTest
private class NbaAutomatedOutreachSchedulableTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'Schedulable Test Account');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Sched',
            LastName = 'Test',
            AccountId = acc.Id,
            Email = 'sched.test@example.com',
            Mogli_SMS__Mogli_Number__c = '+15551112222'
        );
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'Schedulable Test Opp',
            AccountId = acc.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 4000,
            Source__c = 'N/A'
        );
        insert opp;

        OpportunityContactRole ocr = new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = con.Id,
            IsPrimary = true,
            Role = 'Decision Maker'
        );
        insert ocr;
    }

    @isTest
    static void testSchedulableExecutesAndProcessesPending() {
        Opportunity opp = [SELECT Id, AccountId FROM Opportunity
                           WHERE Account.Name = 'Schedulable Test Account' AND StageName = 'New' LIMIT 1];

        // Create a pending automated action with past scheduled time
        NBA_Queue__c action = new NBA_Queue__c(
            Opportunity__c = opp.Id,
            Account__c = opp.AccountId,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'Pending',
            Action_Type__c = 'First Touch',
            Step_Method__c = 'SMS',
            Template_Name__c = 'test_sms_template',
            Execution_Type__c = 'Automated',
            Automated_Send_Status__c = 'Pending',
            Scheduled_Send_Time__c = Datetime.now().addMinutes(-10),
            Source_Path__c = 'Pipeline Cadence',
            Workflow_Mode__c = 'Pipeline',
            LastEvaluatedAt__c = Datetime.now()
        );
        insert action;

        Test.startTest();
        NbaAutomatedOutreachSchedulable schedulable = new NbaAutomatedOutreachSchedulable();
        schedulable.execute(null);
        Test.stopTest();

        // Verify action was processed (template won't exist, so should be Skipped)
        NBA_Queue__c updated = [SELECT Automated_Send_Status__c, Status__c
                                FROM NBA_Queue__c WHERE Id = :action.Id];
        System.assertNotEquals('Pending', updated.Automated_Send_Status__c,
            'Schedulable should process pending action');
    }

    @isTest
    static void testSchedulableSkipsFutureActions() {
        Opportunity opp = [SELECT Id, AccountId FROM Opportunity
                           WHERE Account.Name = 'Schedulable Test Account' AND StageName = 'New' LIMIT 1];

        // Create a pending action with FUTURE scheduled time
        NBA_Queue__c action = new NBA_Queue__c(
            Opportunity__c = opp.Id,
            Account__c = opp.AccountId,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'Pending',
            Action_Type__c = 'First Touch',
            Step_Method__c = 'Email',
            Template_Name__c = 'test_email_template',
            Execution_Type__c = 'Automated',
            Automated_Send_Status__c = 'Pending',
            Scheduled_Send_Time__c = Datetime.now().addHours(2),
            Source_Path__c = 'Pipeline Cadence',
            Workflow_Mode__c = 'Pipeline',
            LastEvaluatedAt__c = Datetime.now()
        );
        insert action;

        Test.startTest();
        NbaAutomatedOutreachSchedulable schedulable = new NbaAutomatedOutreachSchedulable();
        schedulable.execute(null);
        Test.stopTest();

        // Future action should NOT be processed
        NBA_Queue__c updated = [SELECT Automated_Send_Status__c
                                FROM NBA_Queue__c WHERE Id = :action.Id];
        System.assertEquals('Pending', updated.Automated_Send_Status__c,
            'Should not process future-scheduled actions');
    }

    @isTest
    static void testSchedulableWithNoRecords() {
        Test.startTest();
        NbaAutomatedOutreachSchedulable schedulable = new NbaAutomatedOutreachSchedulable();
        schedulable.execute(null);
        Test.stopTest();
        // No exception = pass — handles empty query gracefully
    }
}
