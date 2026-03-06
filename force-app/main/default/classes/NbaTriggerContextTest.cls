/**
 * NbaTriggerContextTest — Tests for NbaTriggerContext shared utility.
 *
 * Covers recursion guards, groupByOppId, and extractOppIds.
 */
@isTest
private class NbaTriggerContextTest {

    @isTest
    static void testRecursionGuards() {
        // Initially all guards should be false
        System.assertEquals(false, NbaTriggerContext.hasOppHandlerRun(), 'Opp guard should start false');
        System.assertEquals(false, NbaTriggerContext.hasEventHandlerRun(), 'Event guard should start false');
        System.assertEquals(false, NbaTriggerContext.hasTaskHandlerRun(), 'Task guard should start false');
        System.assertEquals(false, NbaTriggerContext.hasTalkdeskActivityHandlerRun(), 'Talkdesk guard should start false');

        // Set each guard
        NbaTriggerContext.setOppHandlerRun();
        NbaTriggerContext.setEventHandlerRun();
        NbaTriggerContext.setTaskHandlerRun();
        NbaTriggerContext.setTalkdeskActivityHandlerRun();

        System.assertEquals(true, NbaTriggerContext.hasOppHandlerRun(), 'Opp guard should be true');
        System.assertEquals(true, NbaTriggerContext.hasEventHandlerRun(), 'Event guard should be true');
        System.assertEquals(true, NbaTriggerContext.hasTaskHandlerRun(), 'Task guard should be true');
        System.assertEquals(true, NbaTriggerContext.hasTalkdeskActivityHandlerRun(), 'Talkdesk guard should be true');

        // Reset all
        NbaTriggerContext.resetAll();
        System.assertEquals(false, NbaTriggerContext.hasOppHandlerRun(), 'Opp guard should reset');
        System.assertEquals(false, NbaTriggerContext.hasEventHandlerRun(), 'Event guard should reset');
        System.assertEquals(false, NbaTriggerContext.hasTaskHandlerRun(), 'Task guard should reset');
        System.assertEquals(false, NbaTriggerContext.hasTalkdeskActivityHandlerRun(), 'Talkdesk guard should reset');
    }

    @isTest
    static void testGroupByOppId_WithOppEvents() {
        // Create a real Opportunity to get a valid Opp ID
        Account acc = new Account(Name = 'Trigger Context Test Acct');
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'Trigger Context Test Opp',
            AccountId = acc.Id,
            StageName = 'Consult',
            CloseDate = Date.today().addDays(30),
            Source__c = 'N/A'
        );
        insert opp;

        // Create events related to the opp
        List<Event> events = new List<Event>{
            new Event(WhatId = opp.Id, Subject = 'Call 1', DurationInMinutes = 30, ActivityDateTime = Datetime.now()),
            new Event(WhatId = opp.Id, Subject = 'Call 2', DurationInMinutes = 30, ActivityDateTime = Datetime.now())
        };
        insert events;

        Test.startTest();
        Map<Id, List<SObject>> grouped = NbaTriggerContext.groupByOppId(events, 'WhatId');
        Test.stopTest();

        System.assertEquals(1, grouped.size(), 'Should have one opp key');
        System.assertEquals(2, grouped.get(opp.Id).size(), 'Should have two events for the opp');
    }

    @isTest
    static void testGroupByOppId_NullInput() {
        Test.startTest();
        Map<Id, List<SObject>> grouped = NbaTriggerContext.groupByOppId(null, 'WhatId');
        Test.stopTest();

        System.assertEquals(0, grouped.size(), 'Should return empty map for null input');
    }

    @isTest
    static void testGroupByOppId_NonOppWhatId() {
        // Create a task related to an Account (not an Opp)
        Account acc = new Account(Name = 'Non-Opp Test Acct');
        insert acc;

        List<Task> tasks = new List<Task>{
            new Task(WhatId = acc.Id, Subject = 'Follow up', Status = 'Open', Priority = 'Normal')
        };
        insert tasks;

        Test.startTest();
        Map<Id, List<SObject>> grouped = NbaTriggerContext.groupByOppId(tasks, 'WhatId');
        Test.stopTest();

        System.assertEquals(0, grouped.size(), 'Should filter out non-Opportunity WhatIds');
    }

    @isTest
    static void testExtractOppIds_WithOppTasks() {
        Account acc = new Account(Name = 'Extract Test Acct');
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'Extract Test Opp',
            AccountId = acc.Id,
            StageName = 'Consult',
            CloseDate = Date.today().addDays(30),
            Source__c = 'N/A'
        );
        insert opp;

        List<Task> tasks = new List<Task>{
            new Task(WhatId = opp.Id, Subject = 'Call', Status = 'Open', Priority = 'Normal')
        };
        insert tasks;

        Test.startTest();
        Set<Id> oppIds = NbaTriggerContext.extractOppIds(tasks, 'WhatId');
        Test.stopTest();

        System.assertEquals(1, oppIds.size(), 'Should extract one opp ID');
        System.assert(oppIds.contains(opp.Id), 'Should contain the opp ID');
    }

    @isTest
    static void testExtractOppIds_NullInput() {
        Test.startTest();
        Set<Id> oppIds = NbaTriggerContext.extractOppIds(null, 'WhatId');
        Test.stopTest();

        System.assertEquals(0, oppIds.size(), 'Should return empty set for null input');
    }

    @isTest
    static void testConstants() {
        // Verify shared constants exist and have expected values
        System.assert(NbaTriggerContext.EXCLUDED_STAGES.contains('Closed Won'), 'Should contain Closed Won');
        System.assert(NbaTriggerContext.ACTIVE_STATUSES.contains('New'), 'Should contain New');
        System.assertEquals(24, NbaTriggerContext.MEETING_WINDOW_HOURS, 'Meeting window should be 24 hours');
    }
}
