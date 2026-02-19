/**
 * NbaActionExpirationSchedulable — Housekeeping job for GTM OS engine.
 *
 * Phase 5: Only expires stale Layer 1 time-bound actions (DueAt + 15min).
 * Unsnooze is no longer needed — snooze suppression is handled by
 * on-demand evaluation checking Snoozed_Until on audit records.
 *
 * CRON: '0 5/10 * * * ?' (every 10 minutes, offset by 5 from creation)
 */
public with sharing class NbaActionExpirationSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        // Expire stale Layer 1 time-bound actions (DueAt + 15min past)
        NbaActionStateService.expireStaleActions();
    }

    // ─── Schedule Helper ──────────────────────────────────────────────

    /**
     * Schedule this job to run every 10 minutes (offset by 5 from creation job).
     */
    public static void schedule() {
        List<Integer> minutes = new List<Integer>{ 5, 15, 25, 35, 45, 55 };
        for (Integer m : minutes) {
            String jobName = 'GTM Action Expiration - :' + String.valueOf(m).leftPad(2, '0');
            String cron = '0 ' + m + ' * * * ?';
            System.schedule(jobName, cron, new NbaActionExpirationSchedulable());
        }
    }
}
