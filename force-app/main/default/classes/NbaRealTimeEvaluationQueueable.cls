/**
 * NbaRealTimeEvaluationQueueable — Async evaluation triggered by CRM triggers.
 *
 * When Opportunity triggers fire (new opp, stage change), this Queueable
 * runs the full engine pipeline (signal detection → rule evaluation →
 * action creation → promotion) in a separate transaction with fresh
 * governor limits.
 *
 * Uses NbaSignalService + NbaActionCreationService + NbaActionStateService
 * exactly like NbaActionCreationSchedulable, but scoped to specific Opp IDs
 * from the trigger context.
 */
public with sharing class NbaRealTimeEvaluationQueueable implements Queueable {

    private Set<Id> oppIds;

    /**
     * @param oppIds Opportunity IDs to evaluate (from trigger context)
     */
    public NbaRealTimeEvaluationQueueable(Set<Id> oppIds) {
        this.oppIds = oppIds;
    }

    public void execute(QueueableContext qc) {
        if (oppIds == null || oppIds.isEmpty()) {
            return;
        }

        // Step 1: Get signals for the affected Opportunities (7 SOQL)
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            NbaSignalService.getSignals(oppIds);

        if (signals.isEmpty()) {
            return;
        }

        // Step 2: Evaluate and create candidate actions (3-4 SOQL for CMDT)
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);

        // Step 3: Override Source_Path to 'Immediate' for trigger-created actions
        for (NBA_Queue__c action : result.actionsToCreate) {
            action.Source_Path__c = 'Immediate';
        }

        // Step 4: Insert actions with partial success (1 DML)
        if (!result.actionsToCreate.isEmpty()) {
            Database.insert(result.actionsToCreate, false);
        }

        // Step 5: Promote for each unique AE who has capacity
        Set<Id> aeIds = new Set<Id>();
        for (NBA_Queue__c action : result.actionsToCreate) {
            if (action.Sales_Rep__c != null) {
                aeIds.add(action.Sales_Rep__c);
            }
        }

        for (Id aeId : aeIds) {
            if (NbaActionStateService.hasCapacity(aeId)) {
                NbaActionStateService.promoteNextAction(aeId);
            }
        }
    }
}
