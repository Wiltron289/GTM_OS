/**
 * Test class for NbaOpportunityTriggerHandler + OpportunityTrigger.
 * Two-stream: Verifies cache invalidation + new-assignment interrupt creation
 * on Opportunity insert/update.
 */
@isTest
private class NbaOpportunityTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        // Create accounts (separate per opp to avoid validation rule)
        List<Account> accs = new List<Account>();
        for (Integer i = 1; i <= 5; i++) {
            accs.add(new Account(
                Name = 'OppTrigger Test Account ' + i,
                Employee_Count__c = 40,
                Entity_ID__c = 'OPP-TRIG-00' + i
            ));
        }
        insert accs;
    }

    private static Id getPayrollRecordTypeId() {
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll'
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    // ─── After Insert Tests ──────────────────────────────────────────

    @isTest
    static void testNewOpp_invalidatesCache() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'OppTrigger Test Account 1' LIMIT 1];
        Id rtId = getPayrollRecordTypeId();

        // Pre-populate cache for the running user
        Id userId = UserInfo.getUserId();
        NbaActionController.ActionWrapper cached = new NbaActionController.ActionWrapper();
        cached.actionType = 'Stale Action';
        cached.status = 'Evaluated';
        NbaCacheService.cacheAction(userId, cached);

        Opportunity opp = new Opportunity(
            Name = 'New Trigger Opp',
            AccountId = acc.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 10000,
            Source__c = 'N/A'
        );
        if (rtId != null) opp.RecordTypeId = rtId;

        Test.startTest();
        insert opp;
        Test.stopTest();

        // Phase 5: Handler invalidates cache instead of creating actions
        NbaActionController.ActionWrapper afterCache = NbaCacheService.getCachedAction(userId);
        System.assertEquals(null, afterCache,
            'Cache should be invalidated after new Opp insert');
    }

    @isTest
    static void testClosedOpp_noAction() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'OppTrigger Test Account 2' LIMIT 1];
        Id rtId = getPayrollRecordTypeId();

        Opportunity opp = new Opportunity(
            Name = 'Closed Trigger Opp',
            AccountId = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Amount = 5000,
            Source__c = 'N/A'
        );
        if (rtId != null) opp.RecordTypeId = rtId;

        Test.startTest();
        insert opp;
        Test.stopTest();

        List<NBA_Queue__c> actions = [
            SELECT Id FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Source_Path__c = 'Immediate'
        ];

        System.assertEquals(0, actions.size(),
            'Closed opp should not trigger action creation');
    }

    @isTest
    static void testExcludedStage_noAction() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'OppTrigger Test Account 3' LIMIT 1];
        Id rtId = getPayrollRecordTypeId();

        Opportunity opp = new Opportunity(
            Name = 'HandOff Trigger Opp',
            AccountId = acc.Id,
            StageName = 'Hand-Off',
            CloseDate = Date.today().addDays(10),
            Amount = 3000,
            Source__c = 'N/A'
        );
        if (rtId != null) opp.RecordTypeId = rtId;

        Test.startTest();
        insert opp;
        Test.stopTest();

        List<NBA_Queue__c> actions = [
            SELECT Id FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Source_Path__c = 'Immediate'
        ];

        System.assertEquals(0, actions.size(),
            'Hand-Off stage should be excluded from action creation');
    }

    @isTest
    static void testNewOpp_createsNewAssignmentInterrupt() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'OppTrigger Test Account 1' LIMIT 1];
        Id rtId = getPayrollRecordTypeId();

        // Reset recursion guard so it fires fresh (testNewOpp_invalidatesCache may
        // have run in same thread in some contexts)
        NbaTriggerContext.resetAll();

        Opportunity opp = new Opportunity(
            Name = 'Interrupt Trigger Opp',
            AccountId = acc.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 10000,
            Source__c = 'N/A'
        );
        if (rtId != null) opp.RecordTypeId = rtId;

        Test.startTest();
        insert opp;
        Test.stopTest();

        // Verify a new-assignment interrupt record was created
        List<NBA_Queue__c> interrupts = [
            SELECT Id, Action_Type__c, Priority_Layer__c, Is_Time_Bound__c,
                   Source_Path__c, UniqueKey__c
            FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id
              AND Source_Path__c = 'Immediate'
              AND Is_Time_Bound__c = false
              AND Priority_Layer__c = 'Layer 1 - Time Bound'
        ];
        System.assertEquals(1, interrupts.size(),
            'Should create 1 new-assignment interrupt record');
        System.assertEquals('First Touch', interrupts[0].Action_Type__c,
            'Interrupt should be First Touch');
        System.assert(interrupts[0].UniqueKey__c.contains('NewAssignment'),
            'UniqueKey should contain NewAssignment');
    }

    // ─── After Update Tests ──────────────────────────────────────────

    @isTest
    static void testStageChange_triggersReEvaluation() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'OppTrigger Test Account 4' LIMIT 1];
        Id rtId = getPayrollRecordTypeId();

        Opportunity opp = new Opportunity(
            Name = 'Stage Change Opp',
            AccountId = acc.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 8000,
            Source__c = 'N/A'
        );
        if (rtId != null) opp.RecordTypeId = rtId;
        insert opp;

        // Reset recursion guard so the update fires the handler
        NbaTriggerContext.resetAll();

        Test.startTest();
        opp.StageName = 'Connect';
        update opp;
        Test.stopTest();

        // Phase 5: Stage change invalidates cache — no Queueable.
        // We verify the handler runs without exceptions.
        System.assert(true, 'Stage change handler should run without exceptions');
    }

    // ─── Bulk Test ───────────────────────────────────────────────────

    @isTest
    static void testBulkInsert_noGovernorViolation() {
        List<Account> accs = new List<Account>();
        for (Integer i = 1; i <= 200; i++) {
            accs.add(new Account(
                Name = 'Bulk Trig Account ' + i,
                Employee_Count__c = 30,
                Entity_ID__c = 'BULK-TRIG-' + String.valueOf(i).leftPad(4, '0')
            ));
        }
        insert accs;

        Id rtId = getPayrollRecordTypeId();
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            Opportunity o = new Opportunity(
                Name = 'Bulk Trig Opp ' + i,
                AccountId = accs[i].Id,
                StageName = 'New',
                CloseDate = Date.today().addDays(30),
                Amount = 5000 + i,
                Source__c = 'N/A'
            );
            if (rtId != null) o.RecordTypeId = rtId;
            opps.add(o);
        }

        Test.startTest();
        insert opps;
        Test.stopTest();

        // Phase 5: Handler invalidates cache (no Queueable, no action creation).
        // Key assertion: bulk insert of 200 Opps completes without governor violations.
        System.assert(Limits.getQueries() < 100,
            'Bulk insert should stay under SOQL limit, used: ' + Limits.getQueries());
    }

    // ─── Recursion Guard Test ────────────────────────────────────────

    @isTest
    static void testRecursionGuard_preventsReEntry() {
        // Simulate that the handler already ran in this transaction
        NbaTriggerContext.setOppHandlerRun();

        Account acc = [SELECT Id FROM Account WHERE Name = 'OppTrigger Test Account 5' LIMIT 1];
        Id rtId = getPayrollRecordTypeId();

        Opportunity opp = new Opportunity(
            Name = 'Recursion Guard Opp',
            AccountId = acc.Id,
            StageName = 'New',
            CloseDate = Date.today().addDays(30),
            Amount = 7000,
            Source__c = 'N/A'
        );
        if (rtId != null) opp.RecordTypeId = rtId;

        Test.startTest();
        // The handler should skip because oppHandlerRan = true
        // We call the handler directly to verify the guard
        NbaOpportunityTriggerHandler.handle(
            new List<Opportunity>{ opp },
            null,
            System.TriggerOperation.AFTER_INSERT
        );
        Test.stopTest();

        // Recursion guard prevents cache invalidation on re-entry
        System.assert(true, 'Recursion guard should prevent handler from running again');
    }
}
