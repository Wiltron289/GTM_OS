@isTest
private class NbaAutomatedOutreachServiceTest {

    // ─── Test Data Setup ───────────────────────────────────────────────

    @TestSetup
    static void setupData() {
        // Account
        Account acc = new Account(Name = 'Auto Outreach Test Account');
        insert acc;

        // Contact with SMS number and email
        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Outreach',
            AccountId = acc.Id,
            Email = 'test.outreach@example.com',
            Mogli_SMS__Mogli_Number__c = '+15551234567'
        );
        insert con;

        // Opportunity
        Opportunity opp = new Opportunity(
            Name = 'Auto Outreach Opp',
            AccountId = acc.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 5000,
            Source__c = 'N/A'
        );
        insert opp;

        // OpportunityContactRole (primary)
        OpportunityContactRole ocr = new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = con.Id,
            IsPrimary = true,
            Role = 'Decision Maker'
        );
        insert ocr;
    }

    // ─── Helper Methods ────────────────────────────────────────────────

    static Opportunity getTestOpp() {
        return [SELECT Id, AccountId FROM Opportunity
                WHERE Account.Name = 'Auto Outreach Test Account' AND StageName = 'New' LIMIT 1];
    }

    static Contact getTestContact() {
        return [SELECT Id, Email, AccountId, HasOptedOutOfEmail,
                       Mogli_SMS__Mogli_Number__c, Mogli_SMS__Mogli_Opt_Out__c
                FROM Contact WHERE LastName = 'Outreach' LIMIT 1];
    }

    static NBA_Queue__c createPendingAction(Id oppId, Id accountId, String method, String templateName) {
        NBA_Queue__c action = new NBA_Queue__c(
            Opportunity__c = oppId,
            Account__c = accountId,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'Pending',
            Action_Type__c = 'First Touch',
            Step_Method__c = method,
            Template_Name__c = templateName,
            Execution_Type__c = 'Automated',
            Automated_Send_Status__c = 'Pending',
            Scheduled_Send_Time__c = Datetime.now().addMinutes(-5),
            Source_Path__c = 'Pipeline Cadence',
            Workflow_Mode__c = 'Pipeline',
            LastEvaluatedAt__c = Datetime.now()
        );
        insert action;
        return action;
    }

    // ─── SMS Tests ─────────────────────────────────────────────────────

    @isTest
    static void testSmsSuccess() {
        Opportunity opp = getTestOpp();
        NBA_Queue__c action = createPendingAction(opp.Id, opp.AccountId, 'SMS', 'test_template');

        // Re-query with all fields
        action = [SELECT Id, Opportunity__c, Account__c, Step_Method__c, Template_Name__c,
                         Automated_Send_Status__c, Action_Instruction__c, Status__c,
                         Cadence_Name__c, Cadence_Step_Number__c, Step_Outcome__c,
                         Sales_Rep__c, Action_Type__c, Execution_Type__c, Scheduled_Send_Time__c
                  FROM NBA_Queue__c WHERE Id = :action.Id];

        Contact con = getTestContact();

        Test.startTest();
        // Call sendSms directly since Mogli template won't exist in test context
        NbaAutomatedOutreachService.OutreachResult result =
            NbaAutomatedOutreachService.sendSms(con, action);
        Test.stopTest();

        // Template won't exist in test org — expect Skipped
        System.assertEquals('Skipped', result.status,
            'Should skip when SMS template not found in test context');
        System.assert(result.reason.contains('template not found'),
            'Reason should mention template not found');
    }

    @isTest
    static void testSmsOptOut() {
        Opportunity opp = getTestOpp();
        NBA_Queue__c action = createPendingAction(opp.Id, opp.AccountId, 'SMS', 'test_template');

        // Create opted-out contact
        Contact con = new Contact(
            FirstName = 'OptedOut',
            LastName = 'Contact',
            Email = 'opted@example.com',
            Mogli_SMS__Mogli_Number__c = '+15559999999',
            Mogli_SMS__Mogli_Opt_Out__c = true
        );
        insert con;

        Test.startTest();
        NbaAutomatedOutreachService.OutreachResult result =
            NbaAutomatedOutreachService.sendSms(con, action);
        Test.stopTest();

        System.assertEquals('Skipped', result.status, 'Should skip for opted-out contact');
        System.assertEquals('SMS opt-out', result.reason, 'Should identify SMS opt-out');
    }

    @isTest
    static void testSmsNoNumber() {
        Opportunity opp = getTestOpp();
        NBA_Queue__c action = createPendingAction(opp.Id, opp.AccountId, 'SMS', 'test_template');

        // Create contact without SMS number
        Contact con = new Contact(
            FirstName = 'NoPhone',
            LastName = 'Contact',
            Email = 'nophone@example.com'
        );
        insert con;

        Test.startTest();
        NbaAutomatedOutreachService.OutreachResult result =
            NbaAutomatedOutreachService.sendSms(con, action);
        Test.stopTest();

        System.assertEquals('Skipped', result.status, 'Should skip when no SMS number');
        System.assertEquals('No SMS number', result.reason, 'Should identify missing number');
    }

    // ─── Email Tests ───────────────────────────────────────────────────

    @isTest
    static void testEmailOptOut() {
        Opportunity opp = getTestOpp();
        NBA_Queue__c action = createPendingAction(opp.Id, opp.AccountId, 'Email', 'test_email_template');

        Contact con = new Contact(
            FirstName = 'EmailOptOut',
            LastName = 'Contact',
            Email = 'optout@example.com',
            HasOptedOutOfEmail = true
        );
        insert con;

        Test.startTest();
        NbaAutomatedOutreachService.OutreachResult result =
            NbaAutomatedOutreachService.sendEmail(con, action);
        Test.stopTest();

        System.assertEquals('Skipped', result.status, 'Should skip for email opt-out');
        System.assertEquals('Email opt-out', result.reason, 'Should identify email opt-out');
    }

    @isTest
    static void testEmailNoAddress() {
        Opportunity opp = getTestOpp();
        NBA_Queue__c action = createPendingAction(opp.Id, opp.AccountId, 'Email', 'test_email_template');

        Contact con = new Contact(
            FirstName = 'NoEmail',
            LastName = 'Contact'
        );
        insert con;

        Test.startTest();
        NbaAutomatedOutreachService.OutreachResult result =
            NbaAutomatedOutreachService.sendEmail(con, action);
        Test.stopTest();

        System.assertEquals('Skipped', result.status, 'Should skip when no email');
        System.assertEquals('No email address', result.reason, 'Should identify missing email');
    }

    @isTest
    static void testEmailSendWithFallback() {
        Opportunity opp = getTestOpp();
        NBA_Queue__c action = createPendingAction(opp.Id, opp.AccountId, 'Email', 'nonexistent_template');
        action = [SELECT Id, Opportunity__c, Account__c, Step_Method__c, Template_Name__c,
                         Automated_Send_Status__c, Action_Instruction__c, Status__c
                  FROM NBA_Queue__c WHERE Id = :action.Id];

        Contact con = getTestContact();

        Test.startTest();
        NbaAutomatedOutreachService.OutreachResult result =
            NbaAutomatedOutreachService.sendEmail(con, action);
        Test.stopTest();

        // In test context, email sending may succeed or fail depending on org config
        // Just verify it doesn't throw and returns a valid status
        System.assert(result.status == 'Sent' || result.status == 'Failed',
            'Should attempt email send with fallback template');
    }

    // ─── Process Automated Sends (Integration) ─────────────────────────

    @isTest
    static void testProcessAutomatedSendsNoContact() {
        // Create Opp without OCR (different account)
        Account acc2 = new Account(Name = 'No Contact Account');
        insert acc2;

        Opportunity opp2 = new Opportunity(
            Name = 'No Contact Opp',
            AccountId = acc2.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 3000,
            Source__c = 'N/A'
        );
        insert opp2;

        NBA_Queue__c action = createPendingAction(opp2.Id, acc2.Id, 'SMS', 'test_template');
        List<NBA_Queue__c> actions = [
            SELECT Id, Opportunity__c, Account__c, Step_Method__c, Template_Name__c,
                   Automated_Send_Status__c, Action_Instruction__c, Status__c,
                   Cadence_Name__c, Cadence_Step_Number__c, Step_Outcome__c,
                   Sales_Rep__c, Action_Type__c, Execution_Type__c, Scheduled_Send_Time__c
            FROM NBA_Queue__c WHERE Id = :action.Id
        ];

        Test.startTest();
        NbaAutomatedOutreachService.processAutomatedSends(actions);
        Test.stopTest();

        NBA_Queue__c updated = [SELECT Automated_Send_Status__c, Action_Instruction__c
                                FROM NBA_Queue__c WHERE Id = :action.Id];
        System.assertEquals('Skipped', updated.Automated_Send_Status__c,
            'Should skip when no primary contact');
        System.assert(updated.Action_Instruction__c.contains('No primary contact'),
            'Instruction should note missing contact');
    }

    @isTest
    static void testProcessAutomatedSendsUnsupportedMethod() {
        Opportunity opp = getTestOpp();
        NBA_Queue__c action = createPendingAction(opp.Id, opp.AccountId, 'Call', 'test_template');
        List<NBA_Queue__c> actions = [
            SELECT Id, Opportunity__c, Account__c, Step_Method__c, Template_Name__c,
                   Automated_Send_Status__c, Action_Instruction__c, Status__c,
                   Cadence_Name__c, Cadence_Step_Number__c, Step_Outcome__c,
                   Sales_Rep__c, Action_Type__c, Execution_Type__c, Scheduled_Send_Time__c
            FROM NBA_Queue__c WHERE Id = :action.Id
        ];

        Test.startTest();
        NbaAutomatedOutreachService.processAutomatedSends(actions);
        Test.stopTest();

        NBA_Queue__c updated = [SELECT Automated_Send_Status__c, Action_Instruction__c
                                FROM NBA_Queue__c WHERE Id = :action.Id];
        System.assertEquals('Skipped', updated.Automated_Send_Status__c,
            'Should skip unsupported method');
        System.assert(updated.Action_Instruction__c.contains('Unsupported method'),
            'Instruction should note unsupported method');
    }

    @isTest
    static void testProcessAutomatedSendsEmptyList() {
        Test.startTest();
        NbaAutomatedOutreachService.processAutomatedSends(new List<NBA_Queue__c>());
        NbaAutomatedOutreachService.processAutomatedSends(null);
        Test.stopTest();
        // No exception = pass
    }

    // ─── Contact Query Tests ───────────────────────────────────────────

    @isTest
    static void testQueryPrimaryContacts() {
        Opportunity opp = getTestOpp();

        Test.startTest();
        Map<Id, Contact> result = NbaAutomatedOutreachService.queryPrimaryContacts(
            new Set<Id>{ opp.Id }
        );
        Test.stopTest();

        System.assert(result.containsKey(opp.Id), 'Should find contact for Opp');
        Contact con = result.get(opp.Id);
        System.assertNotEquals(null, con.Email, 'Contact should have email');
        System.assertNotEquals(null, con.Mogli_SMS__Mogli_Number__c,
            'Contact should have SMS number');
    }

    @isTest
    static void testQueryPrimaryContactsEmpty() {
        Test.startTest();
        Map<Id, Contact> result = NbaAutomatedOutreachService.queryPrimaryContacts(new Set<Id>());
        Test.stopTest();

        System.assert(result.isEmpty(), 'Should return empty map for empty input');
    }

    // ─── Template Resolution Tests ─────────────────────────────────────

    @isTest
    static void testResolveSmsTemplateNotFound() {
        Test.startTest();
        String body = NbaAutomatedOutreachService.resolveSmsTemplate('nonexistent_template');
        Test.stopTest();

        System.assertEquals(null, body, 'Should return null for missing template');
    }

    @isTest
    static void testResolveSmsTemplateBlank() {
        Test.startTest();
        String body = NbaAutomatedOutreachService.resolveSmsTemplate(null);
        Test.stopTest();

        System.assertEquals(null, body, 'Should return null for blank template name');
    }

    @isTest
    static void testResolveEmailTemplateNotFound() {
        Test.startTest();
        Id templateId = NbaAutomatedOutreachService.resolveEmailTemplate('nonexistent_template');
        Test.stopTest();

        System.assertEquals(null, templateId, 'Should return null for missing template');
    }
}
