/**
 * @description Test class for NBAQueueSelector utility class
 */
@isTest
public class NBAQueueSelectorTest {
    
    @isTest
    static void testBasicSelectorMethods() {
        // Create minimal test data
        Account testAccount = new Account(Name = 'Test Account', Phone = '1234567890');
        insert testAccount;
        
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = testAccount.Id,
            Phone = '9876543210'
        );
        insert testContact;
        
        Opportunity testOpp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = testAccount.Id,
            StageName = 'Attempted',
            CloseDate = Date.today().addDays(30),
            Source__c = 'Outbound'
        );
        insert testOpp;
        
        Lead testLead = new Lead(
            FirstName = 'Test',
            LastName = 'Lead',
            Company = 'Test Company',
            Phone = '5555555555'
        );
        insert testLead;
        
        NBA_Queue__c testQueue = new NBA_Queue__c(
            Account__c = testAccount.Id,
            Opportunity__c = testOpp.Id,
            Lead__c = testLead.Id,
            Action_Type__c = 'Call',
            Priority_Score__c = 75.0,
            Status__c = 'Pending'
        );
        insert testQueue;
        
        Task testTask = new Task(
            Subject = 'Test Task',
            WhatId = testOpp.Id,
            CallDisposition = 'No Answer'
        );
        insert testTask;
        
        Test.startTest();
        
        // Test NBA_Queue__c selectors
        NBA_Queue__c queueResult = NBAQueueSelector.getQueueItemById(testQueue.Id);
        System.assertEquals(testQueue.Id, queueResult.Id, 'Should return correct queue item');
        
        NBA_Queue__c queueStatusResult = NBAQueueSelector.getQueueItemWithStatus(testQueue.Id);
        System.assertEquals('Pending', queueStatusResult.Status__c, 'Should return status');
        
        NBA_Queue__c queueDismissalResult = NBAQueueSelector.getQueueItemForDismissal(testQueue.Id);
        System.assertEquals(testQueue.Id, queueDismissalResult.Id, 'Should return queue for dismissal');
        
        NBA_Queue__c queueFirstViewedResult = NBAQueueSelector.getQueueItemWithFirstViewed(testQueue.Id);
        System.assertEquals(testQueue.Id, queueFirstViewedResult.Id, 'Should return queue with first viewed');
        
        NBA_Queue__c queueBestPersonResult = NBAQueueSelector.getQueueItemWithBestPerson(testQueue.Id);
        System.assertEquals(testQueue.Id, queueBestPersonResult.Id, 'Should return queue with best person');
        
        
        NBA_Queue__c queueNextStepsResult = NBAQueueSelector.getQueueItemForNextSteps(testQueue.Id);
        System.assertEquals(testQueue.Id, queueNextStepsResult.Id, 'Should return queue for next steps');
        
        NBA_Queue__c queueEmailAcceptResult = NBAQueueSelector.getQueueItemForEmailAcceptance(testQueue.Id);
        System.assertEquals(testQueue.Id, queueEmailAcceptResult.Id, 'Should return queue for email acceptance');
        
        NBA_Queue__c queueEventAcceptResult = NBAQueueSelector.getQueueItemForEventAcceptance(testQueue.Id);
        System.assertEquals(testQueue.Id, queueEventAcceptResult.Id, 'Should return queue for event acceptance');
        
        NBA_Queue__c queueMeetingResult = NBAQueueSelector.getQueueItemForMeetingNotes(testQueue.Id);
        System.assertEquals(testQueue.Id, queueMeetingResult.Id, 'Should return queue for meeting notes');
        
        NBA_Queue__c queueStatusUpdateResult = NBAQueueSelector.getQueueItemForStatusUpdate(testQueue.Id);
        System.assertEquals(testQueue.Id, queueStatusUpdateResult.Id, 'Should return queue for status update');
        
        NBA_Queue__c queueAcceptActionResult = NBAQueueSelector.getQueueItemForAcceptAction(testQueue.Id);
        System.assertEquals(testQueue.Id, queueAcceptActionResult.Id, 'Should return queue for accept action');
        
        NBA_Queue__c queueCancellationResult = NBAQueueSelector.getQueueItemForCancellation(testQueue.Id);
        System.assertEquals(testQueue.Id, queueCancellationResult.Id, 'Should return queue for cancellation');
        
        NBA_Queue__c queueLastViewedResult = NBAQueueSelector.getQueueItemWithLastViewed(testQueue.Id);
        System.assertEquals(testQueue.Id, queueLastViewedResult.Id, 'Should return queue with last viewed');
        
        // Test Opportunity selectors
        List<Opportunity> oppsByAccount = NBAQueueSelector.getOpportunitiesByAccountId(testAccount.Id);
        System.assertEquals(1, oppsByAccount.size(), 'Should return opportunities by account');
        
        Opportunity oppStageResult = NBAQueueSelector.getOpportunityWithStage(testOpp.Id);
        System.assertEquals('Attempted', oppStageResult.StageName, 'Should return opportunity with stage');
        
        Opportunity oppAccountResult = NBAQueueSelector.getOpportunityWithAccountId(testOpp.Id);
        System.assertEquals(testAccount.Id, oppAccountResult.AccountId, 'Should return opportunity with account');
        
        Opportunity oppCallTimesResult = NBAQueueSelector.getOpportunityWithCallTimes(testOpp.Id);
        System.assertEquals(testOpp.Id, oppCallTimesResult.Id, 'Should return opportunity with call times');
        
        Opportunity oppPrimaryContactResult = NBAQueueSelector.getOpportunityWithPrimaryContactPhone(testOpp.Id);
        System.assertEquals(testOpp.Id, oppPrimaryContactResult.Id, 'Should return opportunity with primary contact');
        
        Opportunity oppDescResult = NBAQueueSelector.getOpportunityWithDescriptionAndCallTimes(testOpp.Id);
        System.assertEquals(testOpp.Id, oppDescResult.Id, 'Should return opportunity with description');
        
        Opportunity oppNextStepResult = NBAQueueSelector.getOpportunityWithNextStep(testOpp.Id);
        System.assertEquals(testOpp.Id, oppNextStepResult.Id, 'Should return opportunity with next step');
        
        Opportunity oppDescOnlyResult = NBAQueueSelector.getOpportunityWithDescription(testOpp.Id);
        System.assertEquals(testOpp.Id, oppDescOnlyResult.Id, 'Should return opportunity with description only');
        
        // Test Account selectors
        List<Account> accountsResult = NBAQueueSelector.getAccountsWithOwner(new List<Id>{testAccount.Id});
        System.assertEquals(1, accountsResult.size(), 'Should return accounts with owner');
        
        Account accPhoneResult = NBAQueueSelector.getAccountWithPhone(testAccount.Id);
        System.assertEquals('1234567890', accPhoneResult.Phone, 'Should return account with phone');
        
        Account accPrimaryContactResult = NBAQueueSelector.getAccountWithPrimaryContactPhone(testAccount.Id);
        System.assertEquals(testAccount.Id, accPrimaryContactResult.Id, 'Should return account with primary contact');
        
        // Test Lead selectors
        Lead leadPhoneResult = NBAQueueSelector.getLeadWithPhone(testLead.Id);
        System.assertEquals('5555555555', leadPhoneResult.Phone, 'Should return lead with phone');
        
        Lead leadDescResult = NBAQueueSelector.getLeadWithDescription(testLead.Id);
        System.assertEquals(testLead.Id, leadDescResult.Id, 'Should return lead with description');
        
        Lead leadStatusResult = NBAQueueSelector.getLeadWithStatus(testLead.Id);
        System.assertEquals(testLead.Id, leadStatusResult.Id, 'Should return lead with status');
        
        // Test Contact selectors
        List<Contact> contactsResult = NBAQueueSelector.getContactsByAccountId(testAccount.Id);
        System.assertEquals(1, contactsResult.size(), 'Should return contacts by account');
        
        // Test OpportunityContactRole selectors
        List<OpportunityContactRole> ocrResult = NBAQueueSelector.getOpportunityContactRoles(testOpp.Id);
        System.assertNotEquals(null, ocrResult, 'Should return opportunity contact roles');
        
        // Test Task selectors
        Task taskResult = NBAQueueSelector.getTaskWithCallDisposition(testTask.Id);
        System.assertEquals('No Answer', taskResult.CallDisposition, 'Should return task with call disposition');
        
        // Test new Task and Event selectors
        List<Id> whatIds = new List<Id>{testOpp.Id};
        List<Id> whoIds = new List<Id>{testContact.Id};
        Date today = Date.today();
        Date ninetyDaysAgo = Date.today().addDays(-90);
        Datetime now = Datetime.now();
        Datetime ninetyDaysAgoDt = Datetime.now().addDays(-90);
        
        List<Task> upcomingTasks = NBAQueueSelector.getUpcomingTasks(whatIds, whoIds, today);
        System.assertNotEquals(null, upcomingTasks, 'Should return upcoming tasks list');
        
        List<Task> pastTasks = NBAQueueSelector.getPastTasks(whatIds, whoIds, ninetyDaysAgo);
        System.assertNotEquals(null, pastTasks, 'Should return past tasks list');
        
        List<Event> upcomingEvents = NBAQueueSelector.getUpcomingEvents(whatIds, whoIds, now);
        System.assertNotEquals(null, upcomingEvents, 'Should return upcoming events list');
        
        List<Event> pastEvents = NBAQueueSelector.getPastEvents(whatIds, whoIds, ninetyDaysAgoDt);
        System.assertNotEquals(null, pastEvents, 'Should return past events list');
        
        // Test complex NBA_Queue__c selectors
        NBA_Queue__c queueTaskCreationResult = NBAQueueSelector.getQueueItemForTaskCreation(testQueue.Id);
        System.assertEquals(testQueue.Id, queueTaskCreationResult.Id, 'Should return queue for task creation');
        
        NBA_Queue__c queueUpdateResult = NBAQueueSelector.getQueueItemForUpdate(testQueue.Id);
        System.assertEquals(testQueue.Id, queueUpdateResult.Id, 'Should return queue for update');
        
        Test.stopTest();
    }
    
}