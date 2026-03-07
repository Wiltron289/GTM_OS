@isTest
private class NbaFollowUpServiceTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'FollowUp Test Account',
            Entity_ID__c = 'FU-001'
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
            Name = 'FollowUp Test Opp',
            AccountId = acc.Id,
            StageName = 'Consult',
            CloseDate = Date.today().addDays(30),
            Amount = 5000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp.RecordTypeId = payrollRtId;
        insert opp;
    }

    private static Opportunity getTestOpp() {
        return [SELECT Id, AccountId FROM Opportunity
                WHERE Account.Name = 'FollowUp Test Account' AND StageName = 'Consult'
                LIMIT 1];
    }

    /**
     * Create a Completed audit record for the given Opp. Done inside test methods
     * (not @TestSetup) so we control the exact state and avoid Opp trigger side effects.
     */
    private static NBA_Queue__c createAuditRecord(Id oppId, Id accountId) {
        NBA_Queue__c audit = new NBA_Queue__c(
            Opportunity__c = oppId,
            Account__c = accountId,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'Completed',
            Action_Type__c = 'First Touch',
            Source_Path__c = 'Pipeline Cadence',
            Workflow_Mode__c = 'Pipeline',
            Completed_Date__c = Datetime.now()
        );
        insert audit;
        return audit;
    }

    // ─── Test: Task creation with correct fields ──────────────────────

    @isTest
    static void testCreateFollowUpTaskFields() {
        Opportunity opp = getTestOpp();
        Datetime followUpTime = Datetime.now().addDays(2);

        Test.startTest();
        Id taskId = NbaFollowUpService.createFollowUp(
            opp.Id, 'Call', followUpTime, 'Discuss pricing'
        );
        Test.stopTest();

        Task t = [SELECT Id, WhatId, Subject, ActivityDate, Description, Status, Type,
                         IsReminderSet, ReminderDateTime
                  FROM Task WHERE Id = :taskId];

        System.assertEquals(opp.Id, t.WhatId, 'Task should be linked to Opportunity');
        System.assertEquals('Follow-Up Call', t.Subject, 'Subject should include method');
        System.assertEquals(followUpTime.date(), t.ActivityDate, 'ActivityDate should match');
        System.assertEquals('Not Started', t.Status, 'Status should be Not Started');
        System.assertEquals('Follow-Up', t.Type, 'Type should be Follow-Up');
        System.assert(t.Description.contains('Discuss pricing'), 'Description should include notes');
        System.assertEquals(true, t.IsReminderSet, 'Reminder should be set');
        System.assertNotEquals(null, t.ReminderDateTime, 'ReminderDateTime should be set');
        Long reminderDiff = Math.abs(t.ReminderDateTime.getTime() - followUpTime.getTime());
        System.assert(reminderDiff < 2000, 'ReminderDateTime should match follow-up time');
    }

    // ─── Test: Email follow-up subject ────────────────────────────────

    @isTest
    static void testEmailFollowUpSubject() {
        Opportunity opp = getTestOpp();

        Test.startTest();
        Id taskId = NbaFollowUpService.createFollowUp(
            opp.Id, 'Email', Datetime.now().addDays(1), null
        );
        Test.stopTest();

        Task t = [SELECT Subject FROM Task WHERE Id = :taskId];
        System.assertEquals('Follow-Up Email', t.Subject, 'Subject should be Follow-Up Email');
    }

    // ─── Test: Cadence pauses (Snoozed_Until__c set) ──────────────────

    @isTest
    static void testCadencePauseOnFollowUp() {
        Opportunity opp = getTestOpp();
        NBA_Queue__c audit = createAuditRecord(opp.Id, opp.AccountId);
        Datetime followUpTime = Datetime.now().addDays(3);

        Test.startTest();
        NbaFollowUpService.createFollowUp(opp.Id, 'Call', followUpTime, null);
        Test.stopTest();

        NBA_Queue__c updated = [SELECT Snoozed_Until__c FROM NBA_Queue__c WHERE Id = :audit.Id];
        System.assertNotEquals(null, updated.Snoozed_Until__c, 'Snoozed_Until__c should be set');
        Long diffMs = Math.abs(updated.Snoozed_Until__c.getTime() - followUpTime.getTime());
        System.assert(diffMs < 2000, 'Snoozed_Until__c should match follow-up time');
    }

    // ─── Test: Cancel removes snooze ──────────────────────────────────

    @isTest
    static void testCancelRemovesSnooze() {
        Opportunity opp = getTestOpp();
        NBA_Queue__c audit = createAuditRecord(opp.Id, opp.AccountId);
        Datetime followUpTime = Datetime.now().addDays(3);

        // Create the follow-up (this also snoozes)
        Id taskId = NbaFollowUpService.createFollowUp(opp.Id, 'Call', followUpTime, null);

        // Verify snooze was set
        NBA_Queue__c auditBefore = [SELECT Snoozed_Until__c FROM NBA_Queue__c WHERE Id = :audit.Id];
        System.assertNotEquals(null, auditBefore.Snoozed_Until__c, 'Snooze should be set before cancel');

        Test.startTest();
        NbaFollowUpService.cancelFollowUp(taskId);
        Test.stopTest();

        // Verify Task is completed and reminder cleared
        Task t = [SELECT Status, IsReminderSet FROM Task WHERE Id = :taskId];
        System.assertEquals('Completed', t.Status, 'Task should be marked Completed');
        System.assertEquals(false, t.IsReminderSet, 'Reminder should be cleared on cancel');

        // Verify snooze removed
        NBA_Queue__c auditAfter = [SELECT Snoozed_Until__c FROM NBA_Queue__c WHERE Id = :audit.Id];
        System.assertEquals(null, auditAfter.Snoozed_Until__c, 'Snoozed_Until__c should be cleared');
    }

    // ─── Test: Follow-up in past is rejected ──────────────────────────

    @isTest
    static void testFollowUpInPastRejected() {
        Opportunity opp = getTestOpp();
        Datetime pastTime = Datetime.now().addDays(-1);

        Test.startTest();
        try {
            NbaFollowUpService.createFollowUp(opp.Id, 'Call', pastTime, null);
            System.assert(false, 'Should have thrown exception for past date');
        } catch (NbaFollowUpService.FollowUpException e) {
            System.assert(true, 'Expected exception for past date');
        }
        Test.stopTest();
    }

    // ─── Test: Null oppId rejected ────────────────────────────────────

    @isTest
    static void testNullOppIdRejected() {
        Test.startTest();
        try {
            NbaFollowUpService.createFollowUp(null, 'Call', Datetime.now().addDays(1), null);
            System.assert(false, 'Should have thrown exception for null oppId');
        } catch (NbaFollowUpService.FollowUpException e) {
            System.assert(true, 'Expected exception for null oppId');
        }
        Test.stopTest();
    }

    // ─── Test: Cancel with invalid taskId ─────────────────────────────

    @isTest
    static void testCancelInvalidTaskId() {
        Test.startTest();
        try {
            NbaFollowUpService.cancelFollowUp(null);
            System.assert(false, 'Should throw for null taskId');
        } catch (NbaFollowUpService.FollowUpException e) {
            System.assert(true, 'Expected exception for null taskId');
        }
        Test.stopTest();
    }

    // ─── Test: Follow-up with unknown method uses default subject ─────

    @isTest
    static void testUnknownMethodDefaultSubject() {
        Opportunity opp = getTestOpp();

        Test.startTest();
        Id taskId = NbaFollowUpService.createFollowUp(
            opp.Id, 'Unknown', Datetime.now().addDays(1), null
        );
        Test.stopTest();

        Task t = [SELECT Subject FROM Task WHERE Id = :taskId];
        System.assertEquals('Follow-Up', t.Subject, 'Unknown method should use default subject');
    }
}
