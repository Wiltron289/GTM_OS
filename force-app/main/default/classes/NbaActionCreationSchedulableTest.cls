/**
 * Test class for NbaActionCreationSchedulable (Phase 5 — archived, no-op).
 * Verifies the no-op execute runs without error and schedule/unschedule helpers work.
 */
@isTest
private class NbaActionCreationSchedulableTest {

    @isTest
    static void testSchedulableExecution_NoOp() {
        Test.startTest();
        NbaActionCreationSchedulable sched = new NbaActionCreationSchedulable();
        sched.execute(null);
        Test.stopTest();

        // No-op — just verify it executes without error
        System.assert(true, 'Archived schedulable should execute as no-op');
    }

    @isTest
    static void testScheduleMethod() {
        Test.startTest();
        NbaActionCreationSchedulable.schedule();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'NBA Action Creation - :%'
        ];
        System.assertEquals(6, jobs.size(), 'Should register 6 scheduled jobs (every 10 min)');
    }

    @isTest
    static void testUnscheduleMethod() {
        // Schedule first, then unschedule
        NbaActionCreationSchedulable.schedule();

        Test.startTest();
        NbaActionCreationSchedulable.unschedule();
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'NBA Action Creation - :%'
        ];
        System.assertEquals(0, jobs.size(), 'All creation jobs should be aborted');
    }
}
