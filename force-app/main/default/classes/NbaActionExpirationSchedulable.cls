/**
 * NbaActionExpirationSchedulable — Housekeeping job for NBA V2 engine.
 *
 * Expires stale In Progress actions and unsnoozes due Snoozed actions.
 * Runs on a 10-minute cadence, offset from the creation schedulable.
 *
 * CRON: '0 5/10 * * * ?' (every 10 minutes, offset by 5 from creation)
 */
public with sharing class NbaActionExpirationSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        // Expire stale actions (non-timebound > 1hr, timebound > DueAt + 15min)
        NbaActionStateService.expireStaleActions();

        // Unsnooze due actions (Snoozed_Until <= now → Pending)
        NbaActionStateService.unsnoozeDueActions();
    }

    // ─── Schedule Helper ──────────────────────────────────────────────

    /**
     * Schedule this job to run every 10 minutes (offset by 5 from creation job).
     */
    public static void schedule() {
        List<Integer> minutes = new List<Integer>{ 5, 15, 25, 35, 45, 55 };
        for (Integer m : minutes) {
            String jobName = 'NBA Action Expiration - :' + String.valueOf(m).leftPad(2, '0');
            String cron = '0 ' + m + ' * * * ?';
            System.schedule(jobName, cron, new NbaActionExpirationSchedulable());
        }
    }
}
