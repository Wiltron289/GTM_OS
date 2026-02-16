/**
 * NbaRealTimeEvaluationQueueable — ARCHIVED (Phase 5).
 *
 * Phase 5 replaced trigger-driven async evaluation with cache invalidation.
 * Triggers now call NbaCacheService.invalidateForUsers() instead of enqueuing
 * this Queueable. The next LWC getActiveAction() call evaluates on-demand.
 *
 * Kept as a no-op to avoid deploy errors if any queued jobs are still pending.
 */
public with sharing class NbaRealTimeEvaluationQueueable implements Queueable {

    private Set<Id> oppIds;

    public NbaRealTimeEvaluationQueueable(Set<Id> oppIds) {
        this.oppIds = oppIds;
    }

    public void execute(QueueableContext qc) {
        // Phase 5: No-op — cache invalidation replaced async evaluation.
    }
}
