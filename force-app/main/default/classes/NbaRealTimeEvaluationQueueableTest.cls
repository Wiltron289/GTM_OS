/**
 * Test class for NbaRealTimeEvaluationQueueable (Phase 5 — archived, no-op).
 * Verifies the no-op execute runs without error.
 */
@isTest
private class NbaRealTimeEvaluationQueueableTest {

    @isTest
    static void testExecute_NoOp() {
        Test.startTest();
        System.enqueueJob(
            new NbaRealTimeEvaluationQueueable(new Set<Id>())
        );
        Test.stopTest();

        // No-op — just verify it executes without error
        System.assert(true, 'Archived queueable should execute as no-op');
    }

    @isTest
    static void testExecute_WithIds_NoOp() {
        // Even with real IDs, the execute body is a no-op
        Account acc = new Account(
            Name = 'RT Eval No-Op Account',
            Entity_ID__c = 'RT-NOOP-001'
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
            Name = 'RT Eval No-Op Opp',
            AccountId = acc.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 5000,
            Source__c = 'N/A'
        );
        if (payrollRtId != null) opp.RecordTypeId = payrollRtId;
        insert opp;

        // Count actions created by the Opp insert trigger
        Integer beforeCount = [SELECT COUNT() FROM NBA_Queue__c WHERE Opportunity__c = :opp.Id];

        Test.startTest();
        System.enqueueJob(
            new NbaRealTimeEvaluationQueueable(new Set<Id>{ opp.Id })
        );
        Test.stopTest();

        // No-op should not create any additional actions
        Integer afterCount = [SELECT COUNT() FROM NBA_Queue__c WHERE Opportunity__c = :opp.Id];
        System.assertEquals(beforeCount, afterCount,
            'Archived queueable should not create any actions');
    }
}
