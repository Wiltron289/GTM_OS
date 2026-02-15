/**
 * Test class for NbaRealTimeEvaluationQueueable.
 * Verifies that the queueable runs the full engine pipeline
 * (signal → evaluate → create → promote) and sets Source_Path to 'Immediate'.
 */
@isTest
private class NbaRealTimeEvaluationQueueableTest {

    @TestSetup
    static void setupData() {
        Account acc = new Account(
            Name = 'RT Eval Test Account',
            Employee_Count__c = 50,
            Entity_ID__c = 'RT-EVAL-001'
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

        // New Opp — should produce First Touch action
        Opportunity opp = new Opportunity(
            Name = 'RT Eval Opp',
            AccountId = acc.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 10000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp.RecordTypeId = payrollRtId;
        insert opp;
    }

    @isTest
    static void testExecute_createsActionWithImmediateSource() {
        Opportunity opp = [
            SELECT Id FROM Opportunity
            WHERE Account.Name = 'RT Eval Test Account' LIMIT 1
        ];

        Test.startTest();
        System.enqueueJob(
            new NbaRealTimeEvaluationQueueable(new Set<Id>{ opp.Id })
        );
        Test.stopTest();

        List<NBA_Queue__c> actions = [
            SELECT Id, Action_Type__c, Source_Path__c, Status__c, Opportunity__c
            FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id
        ];

        System.assert(!actions.isEmpty(), 'Should create at least one action');
        NBA_Queue__c action = actions[0];
        System.assertEquals('Immediate', action.Source_Path__c,
            'Source path should be Immediate for trigger-created actions');
        System.assertNotEquals(null, action.Action_Type__c,
            'Action type should be set');
    }

    @isTest
    static void testExecute_emptyOppIds() {
        Test.startTest();
        System.enqueueJob(
            new NbaRealTimeEvaluationQueueable(new Set<Id>())
        );
        Test.stopTest();

        List<NBA_Queue__c> actions = [
            SELECT Id FROM NBA_Queue__c
            WHERE Source_Path__c = 'Immediate'
        ];
        System.assertEquals(0, actions.size(),
            'Empty oppIds should not create any actions');
    }

    @isTest
    static void testExecute_closedOppSuppressed() {
        Account acc = new Account(
            Name = 'RT Eval Closed Account',
            Employee_Count__c = 30,
            Entity_ID__c = 'RT-EVAL-002'
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

        Opportunity closedOpp = new Opportunity(
            Name = 'Closed RT Eval Opp',
            AccountId = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Amount = 5000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) closedOpp.RecordTypeId = payrollRtId;
        insert closedOpp;

        Test.startTest();
        System.enqueueJob(
            new NbaRealTimeEvaluationQueueable(new Set<Id>{ closedOpp.Id })
        );
        Test.stopTest();

        List<NBA_Queue__c> actions = [
            SELECT Id FROM NBA_Queue__c
            WHERE Opportunity__c = :closedOpp.Id AND Source_Path__c = 'Immediate'
        ];
        System.assertEquals(0, actions.size(),
            'Closed opp should be suppressed — no actions created');
    }
}
