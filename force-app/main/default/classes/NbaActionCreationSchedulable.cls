/**
 * NbaActionCreationSchedulable — 10-minute scheduled job for NBA V2 engine.
 *
 * Finds AEs with capacity (< 2 active+pending actions), evaluates their
 * open Opportunities for signal-driven action creation, and promotes
 * the top-ranked Pending action to In Progress.
 *
 * Governor limit budget: ~12 SOQL per AE → max 5-8 AEs per run.
 * CRON: '0 0/10 * * * ?' (every 10 minutes)
 */
public with sharing class NbaActionCreationSchedulable implements Schedulable {

    private static final Integer MAX_AES_PER_RUN = 5;
    private static final Set<String> EXCLUDED_STAGES = new Set<String>{
        'Hand-Off', 'Closed Won', 'Closed Lost'
    };

    public void execute(SchedulableContext sc) {
        // Step 1: Find AEs who are at capacity (>= 2 active+pending)
        Set<Id> saturatedAeIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT Sales_Rep__c aeId, COUNT(Id) cnt
            FROM NBA_Queue__c
            WHERE Status__c IN ('New', 'Pending', 'In Progress', 'Accepted')
              AND Sales_Rep__c != null
            WITH SECURITY_ENFORCED
            GROUP BY Sales_Rep__c
            HAVING COUNT(Id) >= 2
        ]) {
            saturatedAeIds.add((Id) ar.get('aeId'));
        }

        // Step 2: Find AEs with open pipeline Opportunities
        Set<Id> eligibleAeIds = new Set<Id>();
        for (AggregateResult ar : [
            SELECT OwnerId aeId
            FROM Opportunity
            WHERE IsClosed = false
              AND StageName NOT IN :EXCLUDED_STAGES
            WITH SECURITY_ENFORCED
            GROUP BY OwnerId
            LIMIT 200
        ]) {
            Id aeId = (Id) ar.get('aeId');
            if (!saturatedAeIds.contains(aeId)) {
                eligibleAeIds.add(aeId);
            }
        }

        if (eligibleAeIds.isEmpty()) {
            return;
        }

        // Step 3: Process eligible AEs (capped to stay within governor limits)
        Integer processed = 0;
        for (Id aeId : eligibleAeIds) {
            if (processed >= MAX_AES_PER_RUN) {
                break;
            }

            processAe(aeId);
            processed++;
        }
    }

    /**
     * Process a single AE: query their Opps, get signals, create actions, promote.
     */
    private void processAe(Id aeId) {
        // Query AE's open Opps
        List<Opportunity> opps = [
            SELECT Id
            FROM Opportunity
            WHERE OwnerId = :aeId
              AND IsClosed = false
              AND StageName NOT IN :EXCLUDED_STAGES
            WITH SECURITY_ENFORCED
            LIMIT 200
        ];

        if (opps.isEmpty()) {
            return;
        }

        Set<Id> oppIds = new Set<Id>();
        for (Opportunity o : opps) {
            oppIds.add(o.Id);
        }

        // Get signals (7 SOQL)
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            NbaSignalService.getSignals(oppIds);

        // Evaluate and create candidates (0 SOQL — CMDT cached)
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);

        // Insert created actions (1 DML)
        if (!result.actionsToCreate.isEmpty()) {
            Database.insert(result.actionsToCreate, false);
        }

        // Promote if AE has capacity (2-3 SOQL + 1 DML)
        if (NbaActionStateService.hasCapacity(aeId)) {
            NbaActionStateService.promoteNextAction(aeId);
        }
    }

    // ─── Schedule Helper ──────────────────────────────────────────────

    /**
     * Schedule this job to run every 10 minutes (6 jobs at minute offsets).
     */
    public static void schedule() {
        List<Integer> minutes = new List<Integer>{ 0, 10, 20, 30, 40, 50 };
        for (Integer m : minutes) {
            String jobName = 'NBA Action Creation - :' + String.valueOf(m).leftPad(2, '0');
            String cron = '0 ' + m + ' * * * ?';
            System.schedule(jobName, cron, new NbaActionCreationSchedulable());
        }
    }
}
