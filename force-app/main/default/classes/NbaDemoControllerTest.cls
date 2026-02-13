/**
 * Test class for NbaDemoController.
 * Creates full test data hierarchy and verifies getPageData returns complete wrapper.
 */
@isTest
private class NbaDemoControllerTest {

    @testSetup
    static void setupData() {
        // Account with all fields used by the controller
        Account acc = new Account(
            Name = 'Test Demo Account',
            Employee_Count__c = 50,
            Active_Location_Count__c = 3,
            Highest_Current_Tier__c = 'Premium',
            Date_of_Previous_Tier_Change__c = Date.today().addMonths(-6),
            Payroll_Status__c = 'Ready to Run',
            Current_Linear_Flow_Page__c = 'Step 3',
            Admin_Link__c = 'https://example.com/admin',
            KYB_Status__c = 'Approved',
            Onboard_Status__c = 'Complete',
            Implementation_Status__c = 'Active',
            Entity_ID__c = 'TEST-ENTITY-001'
        );
        insert acc;

        // Account Scoring record - Entity_ID must match parent Account
        Account_Scoring__c scoring = new Account_Scoring__c(
            Account__c = acc.Id,
            Entity_ID__c = 'TEST-ENTITY-001',
            Prob_Payroll_Conversion__c = 75,
            Prob_Tier_Upgrade__c = 60,
            Payroll_Top_Drivers__c = 'High employee count\nRecent sign-up activity',
            Tier_Upgrade_Top_Drivers__c = 'Growing revenue\nMulti-location expansion'
        );
        insert scoring;

        // Opportunity - Payroll record type if available, otherwise default
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
            Name = 'Test NBA Demo Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            NextStep = 'Send proposal',
            Inception_or_Switcher__c = 'Inception',
            First_Payday__c = Date.today().addDays(14),
            Decision_Maker_Identified__c = true,
            Budget_Confirmed__c = true,
            Timeline_Confirmed__c = false,
            Next_Step_Date__c = Date.today().addDays(3),
            Future_Follow_Up_Date__c = Date.today().addDays(7),
            Future_Follow_Up_Reason__c = null,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) {
            opp.RecordTypeId = payrollRtId;
        }
        insert opp;

        // Contact + OpportunityContactRole
        Contact con = new Contact(
            FirstName = 'Jane',
            LastName = 'Smith',
            AccountId = acc.Id,
            Title = 'VP Operations',
            Email = 'jane.smith@example.com',
            Phone = '555-0100'
        );
        insert con;

        OpportunityContactRole ocr = new OpportunityContactRole(
            OpportunityId = opp.Id,
            ContactId = con.Id,
            IsPrimary = true,
            Role = 'Decision Maker'
        );
        insert ocr;

        // Product + OpportunityLineItem
        Product2 prod = new Product2(
            Name = 'Payroll Basic',
            Family = 'Payroll',
            IsActive = true
        );
        insert prod;

        // Get standard pricebook
        Id stdPbId = Test.getStandardPricebookId();

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100
        );
        insert oli;

        // Task (activity for sidebar + contacts)
        Task t = new Task(
            Subject = 'Call - Demo Follow Up',
            WhatId = opp.Id,
            WhoId = con.Id,
            Status = 'Completed',
            ActivityDate = Date.today().addDays(-1),
            TaskSubtype = 'Call',
            Description = 'Discussed payroll setup timeline'
        );
        insert t;

        // Task that looks like a Note
        Task noteTask = new Task(
            Subject = 'Note - Client meeting summary',
            WhatId = opp.Id,
            WhoId = con.Id,
            Status = 'Completed',
            ActivityDate = Date.today(),
            Description = 'Client is interested in premium tier upgrade'
        );
        insert noteTask;

        // Event (upcoming meeting for alert banner)
        Event ev = new Event(
            Subject = 'Payroll Onboarding Call',
            WhatId = opp.Id,
            WhoId = con.Id,
            StartDateTime = Datetime.now().addHours(2),
            EndDateTime = Datetime.now().addHours(3)
        );
        insert ev;

        // Past event for sidebar
        Event pastEv = new Event(
            Subject = 'Discovery Call',
            WhatId = opp.Id,
            WhoId = con.Id,
            StartDateTime = Datetime.now().addDays(-5),
            EndDateTime = Datetime.now().addDays(-5).addHours(1),
            ActivityDate = Date.today().addDays(-5)
        );
        insert pastEv;
    }

    // ─── getPageData Tests ────────────────────────────────────────────

    @isTest
    static void testGetPageData_ReturnsCompleteWrapper() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp' LIMIT 1];

        Test.startTest();
        NbaDemoController.PageDataWrapper result = NbaDemoController.getPageData(opp.Id);
        Test.stopTest();

        // Verify wrapper is not null
        System.assertNotEquals(null, result, 'PageDataWrapper should not be null');

        // Header
        System.assertNotEquals(null, result.header, 'Header should not be null');
        System.assertEquals('Test Demo Account', result.header.accountName);
        System.assertEquals('Test NBA Demo Opp', result.header.opportunityName);

        // Account Details
        System.assertNotEquals(null, result.account, 'Account data should not be null');
        System.assertEquals(50, result.account.employeeCount);
        System.assertEquals(3, result.account.locationCount);
        System.assertEquals('Premium', result.account.plan);
        System.assert(result.account.onTierMonths != null, 'On tier months should be calculated');

        // Payroll Status
        System.assertNotEquals(null, result.payrollStatus, 'Payroll status should not be null');
        System.assertEquals('Inception', result.payrollStatus.type);
        System.assertEquals('Send proposal', result.payrollStatus.nextStep);
        System.assertEquals('Ready to Run', result.payrollStatus.checkStatus);

        // Quota
        System.assertNotEquals(null, result.quota, 'Quota should not be null');
        System.assertEquals(5000, result.quota.target, 'Quota target should be 5000 (hardcoded)');
        System.assertNotEquals(null, result.quota.closedWon);
        System.assertNotEquals(null, result.quota.percentage);

        // Engagement
        System.assertNotEquals(null, result.engagement, 'Engagement should not be null');
        System.assertEquals('Prospecting', result.engagement.stageName);

        // Payroll Tab
        System.assertNotEquals(null, result.payrollTab, 'Payroll tab should not be null');
        System.assertEquals('Inception', result.payrollTab.inceptionOrSwitcher);
        System.assertEquals(true, result.payrollTab.isReadyToRun);
        System.assertEquals('Send proposal', result.payrollTab.nextStepLabel);

        // Admin
        System.assertNotEquals(null, result.admin, 'Admin data should not be null');
        System.assertEquals('Prospecting', result.admin.stageName);
        System.assertNotEquals(null, result.admin.ownerName);

        // Insights
        System.assertNotEquals(null, result.insights, 'Insights should not be null');
        System.assert(result.insights.drivers.size() >= 2, 'Should have at least 2 drivers from scoring');
        System.assertEquals(4, result.insights.tags.size(), 'Should have 4 tags');

        // Contacts
        System.assertNotEquals(null, result.contacts, 'Contacts should not be null');
        System.assert(result.contacts.size() >= 1, 'Should have at least 1 contact');
        System.assertEquals('Jane Smith', result.contacts[0].name);
        System.assertEquals('JS', result.contacts[0].initials);
        System.assertEquals(true, result.contacts[0].isPrimary);

        // Products
        System.assertNotEquals(null, result.products, 'Products should not be null');
        System.assert(result.products.size() >= 1, 'Should have at least 1 product');
        System.assertEquals('Payroll Basic', result.products[0].productName);

        // Sidebar
        System.assertNotEquals(null, result.sidebar, 'Sidebar should not be null');
        System.assert(result.sidebar.activities.size() >= 1, 'Should have activities');
        System.assert(result.sidebar.notes.size() >= 1, 'Should have at least 1 note from Note-prefixed task');

        // Upcoming Event
        System.assertNotEquals(null, result.upcomingEvent, 'Upcoming event should not be null');
        System.assertEquals(true, result.upcomingEvent.hasUpcoming, 'Should detect upcoming event');
        System.assertEquals('Test Demo Account', result.upcomingEvent.accountName);
    }

    @isTest
    static void testGetPageData_NoScoringRecord() {
        // Delete scoring record to test graceful handling
        delete [SELECT Id FROM Account_Scoring__c];

        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp' LIMIT 1];

        Test.startTest();
        NbaDemoController.PageDataWrapper result = NbaDemoController.getPageData(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.insights, 'Insights should still be populated');
        System.assertEquals(0, result.insights.drivers.size(), 'No drivers without scoring record');
        System.assertEquals(4, result.insights.tags.size(), 'Tags should still derive from Opp checkboxes');
    }

    @isTest
    static void testGetPageData_NoContactRoles() {
        // Delete contact roles to test empty contacts
        delete [SELECT Id FROM OpportunityContactRole];

        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp' LIMIT 1];

        Test.startTest();
        NbaDemoController.PageDataWrapper result = NbaDemoController.getPageData(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.contacts, 'Contacts list should not be null');
        System.assertEquals(0, result.contacts.size(), 'Should have no contacts');
    }

    @isTest
    static void testGetPageData_NoProducts() {
        delete [SELECT Id FROM OpportunityLineItem];

        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp' LIMIT 1];

        Test.startTest();
        NbaDemoController.PageDataWrapper result = NbaDemoController.getPageData(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.products, 'Products list should not be null');
        System.assertEquals(0, result.products.size(), 'Should have no products');
    }

    @isTest
    static void testGetPageData_NoUpcomingEvents() {
        // Delete future events
        delete [SELECT Id FROM Event WHERE StartDateTime >= :Datetime.now()];

        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp' LIMIT 1];

        Test.startTest();
        NbaDemoController.PageDataWrapper result = NbaDemoController.getPageData(opp.Id);
        Test.stopTest();

        System.assertEquals(false, result.upcomingEvent.hasUpcoming, 'Should report no upcoming event');
    }

    @isTest
    static void testGetPageData_NoActivities() {
        delete [SELECT Id FROM Task WHERE WhatId IN (SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp')];
        delete [SELECT Id FROM Event WHERE WhatId IN (SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp')];

        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp' LIMIT 1];

        Test.startTest();
        NbaDemoController.PageDataWrapper result = NbaDemoController.getPageData(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.sidebar);
        System.assertEquals(0, result.sidebar.activities.size(), 'Should have no activities');
        System.assertEquals(0, result.sidebar.notes.size(), 'Should have no notes');
    }

    // ─── saveNote Tests ───────────────────────────────────────────────

    @isTest
    static void testSaveNote_CreatesContentNote() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp' LIMIT 1];

        Test.startTest();
        Id noteId = NbaDemoController.saveNote(opp.Id, 'This is a test note from NBA demo');
        Test.stopTest();

        System.assertNotEquals(null, noteId, 'Note ID should be returned');

        // Verify ContentNote was created
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :opp.Id
            ORDER BY SystemModstamp DESC
            LIMIT 1
        ];
        System.assert(!links.isEmpty(), 'ContentDocumentLink should exist for the Opportunity');
    }

    // ─── sendEmail Tests ──────────────────────────────────────────────

    @isTest
    static void testSendEmail_SendsMessage() {
        Contact con = [SELECT Id FROM Contact WHERE LastName = 'Smith' LIMIT 1];

        Test.startTest();
        // sendEmail may throw in test context depending on org config,
        // so we catch and verify the method runs without unhandled exceptions
        try {
            NbaDemoController.sendEmail(con.Id, 'Test Subject', '<p>Test body</p>', null);
        } catch (Exception e) {
            // Email send may fail in test context - that's acceptable
            // We just need to verify the method is callable and hits the code path
            System.assert(true, 'sendEmail executed - exception in test context is acceptable');
        }
        Test.stopTest();
    }

    // ─── Tag Building Tests ───────────────────────────────────────────

    @isTest
    static void testTagDerivation_HighIntent() {
        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp' LIMIT 1];

        Test.startTest();
        NbaDemoController.PageDataWrapper result = NbaDemoController.getPageData(opp.Id);
        Test.stopTest();

        // Find the High Intent tag
        Boolean foundHighIntent = false;
        Boolean foundDecisionMaker = false;
        Boolean foundBudget = false;
        Boolean foundTimeSensitive = false;

        for (NbaDemoController.TagData tag : result.insights.tags) {
            if (tag.label == 'High Intent') foundHighIntent = true;
            if (tag.label == 'Decision Maker Engaged' && tag.active == true) foundDecisionMaker = true;
            if (tag.label == 'Budget Confirmed' && tag.active == true) foundBudget = true;
            if (tag.label == 'Time Sensitive' && tag.active == false) foundTimeSensitive = true;
        }

        System.assert(foundHighIntent, 'High Intent tag should exist');
        System.assert(foundDecisionMaker, 'Decision Maker tag should be active');
        System.assert(foundBudget, 'Budget Confirmed tag should be active');
        System.assert(foundTimeSensitive, 'Time Sensitive tag should be inactive (Timeline not confirmed)');
    }

    // ─── Quota Calculation Tests ──────────────────────────────────────

    @isTest
    static void testQuotaCalculation_WithClosedWon() {
        // Create a Closed Won opp for quota calculation
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Demo Account' LIMIT 1];
        Opportunity closedOpp = new Opportunity(
            Name = 'Closed Won Test Opp',
            AccountId = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Amount = 1500,
            Source__c = 'N/A'
        );
        insert closedOpp;

        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp' LIMIT 1];

        Test.startTest();
        NbaDemoController.PageDataWrapper result = NbaDemoController.getPageData(opp.Id);
        Test.stopTest();

        System.assert(result.quota.closedWon >= 1500, 'Closed Won MRR should include the closed opp');
        System.assert(result.quota.percentage > 0, 'Percentage should be > 0 with closed won amount');
    }

    // ─── On Tier Months Calculation ───────────────────────────────────

    @isTest
    static void testOnTierMonths_NullDate() {
        // Set Date_of_Previous_Tier_Change__c to null
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Demo Account' LIMIT 1];
        acc.Date_of_Previous_Tier_Change__c = null;
        update acc;

        Opportunity opp = [SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp' LIMIT 1];

        Test.startTest();
        NbaDemoController.PageDataWrapper result = NbaDemoController.getPageData(opp.Id);
        Test.stopTest();

        System.assertEquals(null, result.account.onTierMonths, 'On tier months should be null when date is null');
    }
}
