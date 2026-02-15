/**
 * Test class for NbaEventTriggerHandler + EventTrigger.
 * Verifies time-bound action creation, rescheduling, and cancellation.
 */
@isTest
private class NbaEventTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        List<Account> accs = new List<Account>();
        for (Integer i = 1; i <= 3; i++) {
            accs.add(new Account(
                Name = 'EventTrig Test Account ' + i,
                Employee_Count__c = 40,
                Entity_ID__c = 'EVT-TRIG-00' + i
            ));
        }
        insert accs;

        Id payrollRtId;
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll'
            LIMIT 1
        ];
        if (!rts.isEmpty()) {
            payrollRtId = rts[0].Id;
        }

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            Opportunity o = new Opportunity(
                Name = 'EventTrig Opp ' + (i + 1),
                AccountId = accs[i].Id,
                StageName = 'Connect',
                CloseDate = Date.today().addDays(30),
                Amount = 8000 + (i * 1000),
                Source__c = 'N/A'
            );
            if (payrollRtId != null) o.RecordTypeId = payrollRtId;
            opps.add(o);
        }
        insert opps;
    }

    // ─── Meeting Scheduled → Time-Bound Action Created ──────────────

    @isTest
    static void testMeetingScheduled_createsTimeBoundAction() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId
            FROM Opportunity WHERE Account.Name = 'EventTrig Test Account 1' LIMIT 1
        ];

        // Reset recursion guards (Opp insert may have set them)
        NbaTriggerContext.resetAll();

        Event evt = new Event(
            WhatId = opp.Id,
            Subject = 'Demo Meeting',
            StartDateTime = Datetime.now().addHours(3),
            EndDateTime = Datetime.now().addHours(4)
        );

        Test.startTest();
        insert evt;
        Test.stopTest();

        List<NBA_Queue__c> actions = [
            SELECT Id, Action_Type__c, Priority_Layer__c, Is_Time_Bound__c,
                   DueAt__c, Source_Path__c, Status__c, Action_Instruction__c
            FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Action_Type__c = 'Meeting'
        ];

        System.assert(!actions.isEmpty(),
            'Meeting within 24h should create a time-bound action');
        NBA_Queue__c action = actions[0];
        System.assertEquals('Layer 1 - Time Bound', action.Priority_Layer__c,
            'Should be Layer 1');
        System.assertEquals(true, action.Is_Time_Bound__c,
            'Should be time-bound');
        System.assertEquals('Immediate', action.Source_Path__c,
            'Source should be Immediate');
        System.assert(action.Action_Instruction__c.contains('Demo Meeting'),
            'Instruction should contain event subject');
    }

    // ─── Meeting Too Far Away → No Action ────────────────────────────

    @isTest
    static void testMeetingBeyondWindow_noAction() {
        Opportunity opp = [
            SELECT Id FROM Opportunity
            WHERE Account.Name = 'EventTrig Test Account 2' LIMIT 1
        ];

        NbaTriggerContext.resetAll();

        Event evt = new Event(
            WhatId = opp.Id,
            Subject = 'Far Future Meeting',
            StartDateTime = Datetime.now().addHours(48),
            EndDateTime = Datetime.now().addHours(49)
        );

        Test.startTest();
        insert evt;
        Test.stopTest();

        List<NBA_Queue__c> actions = [
            SELECT Id FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Action_Type__c = 'Meeting'
        ];

        System.assertEquals(0, actions.size(),
            'Meeting >24h away should not create a time-bound action');
    }

    // ─── Meeting Rescheduled → DueAt Updated ────────────────────────

    @isTest
    static void testMeetingRescheduled_updatesDueAt() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId
            FROM Opportunity WHERE Account.Name = 'EventTrig Test Account 1' LIMIT 1
        ];

        NbaTriggerContext.resetAll();

        Event evt = new Event(
            WhatId = opp.Id,
            Subject = 'Reschedule Meeting',
            StartDateTime = Datetime.now().addHours(2),
            EndDateTime = Datetime.now().addHours(3)
        );
        insert evt;

        // Verify action was created
        List<NBA_Queue__c> beforeActions = [
            SELECT Id, DueAt__c FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Action_Type__c = 'Meeting'
        ];
        System.assert(!beforeActions.isEmpty(), 'Action should exist before reschedule');

        NbaTriggerContext.resetAll();

        Datetime newStart = Datetime.now().addHours(5);
        Test.startTest();
        evt.StartDateTime = newStart;
        evt.EndDateTime = newStart.addHours(1);
        update evt;
        Test.stopTest();

        List<NBA_Queue__c> afterActions = [
            SELECT Id, DueAt__c FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Action_Type__c = 'Meeting'
              AND Status__c IN ('New', 'Pending', 'In Progress', 'Accepted')
        ];

        System.assert(!afterActions.isEmpty(), 'Action should still exist after reschedule');
        // The DueAt should have been updated
        System.assertNotEquals(beforeActions[0].DueAt__c, afterActions[0].DueAt__c,
            'DueAt should be updated after reschedule');
    }

    // ─── Meeting Cancelled → Action Expired ──────────────────────────

    @isTest
    static void testMeetingCancelled_expiresAction() {
        Opportunity opp = [
            SELECT Id, AccountId, OwnerId
            FROM Opportunity WHERE Account.Name = 'EventTrig Test Account 3' LIMIT 1
        ];

        NbaTriggerContext.resetAll();

        Event evt = new Event(
            WhatId = opp.Id,
            Subject = 'Cancel Meeting',
            StartDateTime = Datetime.now().addHours(2),
            EndDateTime = Datetime.now().addHours(3)
        );
        insert evt;

        // Verify action exists
        List<NBA_Queue__c> beforeActions = [
            SELECT Id FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Action_Type__c = 'Meeting'
              AND Status__c IN ('New', 'Pending', 'In Progress', 'Accepted')
        ];
        System.assert(!beforeActions.isEmpty(), 'Action should exist before cancellation');

        NbaTriggerContext.resetAll();

        Test.startTest();
        delete evt;
        Test.stopTest();

        List<NBA_Queue__c> expiredActions = [
            SELECT Id, Status__c FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Action_Type__c = 'Meeting'
              AND Status__c = 'Expired'
        ];

        System.assert(!expiredActions.isEmpty(),
            'Action should be expired after meeting cancellation');
    }

    // ─── Event Not On Opportunity → No Action ────────────────────────

    @isTest
    static void testEventNotOnOpp_noAction() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'EventTrig Test Account 1' LIMIT 1];

        NbaTriggerContext.resetAll();

        Event evt = new Event(
            WhatId = acc.Id, // linked to Account, not Opportunity
            Subject = 'Non-Opp Meeting',
            StartDateTime = Datetime.now().addHours(2),
            EndDateTime = Datetime.now().addHours(3)
        );

        Test.startTest();
        insert evt;
        Test.stopTest();

        List<NBA_Queue__c> actions = [
            SELECT Id FROM NBA_Queue__c
            WHERE Action_Type__c = 'Meeting' AND Source_Path__c = 'Immediate'
        ];

        System.assertEquals(0, actions.size(),
            'Events on non-Opportunity objects should not create actions');
    }
}
