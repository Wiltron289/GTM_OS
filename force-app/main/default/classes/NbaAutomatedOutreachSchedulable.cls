/**
 * NbaAutomatedOutreachSchedulable — Scheduled job for processing pending automated sends.
 *
 * PRD Section 12.6: Runs every 5 minutes, queries NBA_Queue__c records with
 * Automated_Send_Status__c = 'Pending' and Scheduled_Send_Time__c <= now(),
 * then delegates to NbaAutomatedOutreachService for execution.
 *
 * Schedule: System.schedule('GTM Auto Outreach 0', '0 0 * * * ?', new NbaAutomatedOutreachSchedulable());
 * (Create 12 jobs at 0,5,10,15,20,25,30,35,40,45,50,55 minute marks)
 */
public with sharing class NbaAutomatedOutreachSchedulable implements Schedulable {

    @TestVisible
    private static final Integer BATCH_SIZE = 50;

    public void execute(SchedulableContext sc) {
        List<NBA_Queue__c> pendingActions = [
            SELECT Id, Opportunity__c, Account__c, Sales_Rep__c,
                   Status__c, Action_Type__c, Step_Method__c,
                   Template_Name__c, Execution_Type__c,
                   Automated_Send_Status__c, Scheduled_Send_Time__c,
                   Action_Instruction__c, Cadence_Name__c,
                   Cadence_Step_Number__c, Step_Outcome__c
            FROM NBA_Queue__c
            WHERE Automated_Send_Status__c = 'Pending'
              AND Scheduled_Send_Time__c <= :Datetime.now()
              AND Execution_Type__c = 'Automated'
            WITH SECURITY_ENFORCED
            ORDER BY Scheduled_Send_Time__c ASC
            LIMIT :BATCH_SIZE
        ];

        if (!pendingActions.isEmpty()) {
            NbaAutomatedOutreachService.processAutomatedSends(pendingActions);
        }
    }
}
