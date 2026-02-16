/**
 * NbaActionCreationSchedulable — ARCHIVED (Phase 5).
 *
 * Phase 5 pivoted to on-demand evaluation. Actions are no longer pre-created
 * by a scheduled job. The on-demand engine (NbaActionController.getActiveAction)
 * evaluates CRM signals in real-time when the AE requests an action.
 *
 * This class is kept as a no-op for backwards compatibility with any existing
 * scheduled jobs in the org. Use unschedule() to remove them.
 */
public with sharing class NbaActionCreationSchedulable implements Schedulable {

    public void execute(SchedulableContext sc) {
        // Phase 5: No-op — on-demand evaluation replaced scheduled creation.
    }

    // ─── Schedule Helpers ─────────────────────────────────────────────

    /**
     * Schedule this job (DEPRECATED — kept for reference).
     */
    public static void schedule() {
        List<Integer> minutes = new List<Integer>{ 0, 10, 20, 30, 40, 50 };
        for (Integer m : minutes) {
            String jobName = 'NBA Action Creation - :' + String.valueOf(m).leftPad(2, '0');
            String cron = '0 ' + m + ' * * * ?';
            System.schedule(jobName, cron, new NbaActionCreationSchedulable());
        }
    }

    /**
     * Unschedule all NBA Action Creation jobs from the org.
     */
    public static void unschedule() {
        for (CronTrigger ct : [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'NBA Action Creation - :%'
        ]) {
            System.abortJob(ct.Id);
        }
    }
}
