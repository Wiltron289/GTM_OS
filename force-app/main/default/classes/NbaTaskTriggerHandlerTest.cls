/**
 * Test class for NbaTaskTriggerHandler + TaskTrigger.
 * Phase 5: Verifies context updates and cache invalidation when
 * activities are logged on Opportunities with active NBA actions.
 * Auto-completion removed — on-demand model detects activity during evaluation.
 */
@isTest
private class NbaTaskTriggerHandlerTest {

    @TestSetup
    static void setupData() {
        List<Account> accs = new List<Account>();
        for (Integer i = 1; i <= 3; i++) {
            accs.add(new Account(
                Name = 'TaskTrig Test Account ' + i,
                Employee_Count__c = 40,
                Entity_ID__c = 'TSK-TRIG-00' + i
            ));
        }
        insert accs;

        Id payrollRtId;
        List<RecordType> rts = [
            SELECT Id FROM RecordType
            WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll'
            LIMIT 1
        ];
        if (!rts.isEmpty()) {
            payrollRtId = rts[0].Id;
        }

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            Opportunity o = new Opportunity(
                Name = 'TaskTrig Opp ' + (i + 1),
                AccountId = accs[i].Id,
                StageName = 'Connect',
                CloseDate = Date.today().addDays(30),
                Amount = 8000 + (i * 1000),
                Source__c = 'N/A'
            );
            if (payrollRtId != null) o.RecordTypeId = payrollRtId;
            opps.add(o);
        }
        insert opps;

        // Create active NBA_Queue__c actions for the Opps
        List<NBA_Queue__c> actions = new List<NBA_Queue__c>();
        for (Integer i = 0; i < 3; i++) {
            String actionType = i == 0 ? 'First Touch' : (i == 1 ? 'Re-engage' : 'Stage Progression');
            actions.add(new NBA_Queue__c(
                Opportunity__c = opps[i].Id,
                Account__c = accs[i].Id,
                Sales_Rep__c = UserInfo.getUserId(),
                Status__c = 'In Progress',
                Action_Type__c = actionType,
                Impact_Score__c = 0.5,
                Urgency_Score__c = 0.5,
                Priority_Score__c = 0.5,
                Priority_Bucket__c = 'General Pipeline',
                Priority_Layer__c = 'Layer 3 - Impact+Urgency',
                Is_Time_Bound__c = false,
                Cadence_Stage__c = 1,
                Attempt_Count_Today__c = 0,
                Last_Attempt_Method__c = 'Call',
                Source_Path__c = 'Pipeline Cadence',
                Rule_Name__c = actionType + '_Auto',
                Action_Instruction__c = 'Test action for ' + actionType,
                Workflow_Mode__c = 'Pipeline',
                UniqueKey__c = 'V2|' + opps[i].Id + '|' + actionType,
                LastEvaluatedAt__c = Datetime.now().addHours(-1)
            ));
        }
        insert actions;
    }

    // ─── Context Update on Call Task ─────────────────────────────────

    @isTest
    static void testCallTask_updatesContext() {
        Opportunity opp = [
            SELECT Id FROM Opportunity WHERE Account.Name = 'TaskTrig Test Account 3' LIMIT 1
        ];
        NBA_Queue__c actionBefore = [
            SELECT Id, Attempt_Count_Today__c, LastEvaluatedAt__c
            FROM NBA_Queue__c WHERE Opportunity__c = :opp.Id LIMIT 1
        ];
        Datetime oldEvalTime = actionBefore.LastEvaluatedAt__c;

        NbaTriggerContext.resetAll();

        Task t = new Task(
            WhatId = opp.Id,
            Subject = 'Call - No Answer',
            Status = 'Completed',
            TaskSubtype = 'Call'
        );

        Test.startTest();
        insert t;
        Test.stopTest();

        NBA_Queue__c actionAfter = [
            SELECT Id, Attempt_Count_Today__c, Last_Attempt_Method__c, LastEvaluatedAt__c
            FROM NBA_Queue__c WHERE Id = :actionBefore.Id
        ];

        System.assertEquals(1, actionAfter.Attempt_Count_Today__c,
            'Attempt count should increment to 1');
        System.assertEquals('Call', actionAfter.Last_Attempt_Method__c,
            'Last attempt method should be Call');
        System.assert(actionAfter.LastEvaluatedAt__c > oldEvalTime,
            'LastEvaluatedAt should be updated');
    }

    // ─── Connected Call → Context Update + Cache Invalidation ─────────

    @isTest
    static void testConnectedCall_updatesContextAndInvalidatesCache() {
        Opportunity opp = [
            SELECT Id FROM Opportunity WHERE Account.Name = 'TaskTrig Test Account 1' LIMIT 1
        ];

        NBA_Queue__c actionBefore = [
            SELECT Id, Status__c, Attempt_Count_Today__c FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Action_Type__c = 'First Touch' LIMIT 1
        ];
        System.assertEquals('In Progress', actionBefore.Status__c,
            'Action should be In Progress before test');

        // Pre-populate cache to verify invalidation
        Id userId = UserInfo.getUserId();
        NbaActionController.ActionWrapper cached = new NbaActionController.ActionWrapper();
        cached.actionType = 'Stale Action';
        cached.status = 'Evaluated';
        NbaCacheService.cacheAction(userId, cached);

        NbaTriggerContext.resetAll();

        Task t = new Task(
            WhatId = opp.Id,
            Subject = 'Call - Connected with DM',
            Status = 'Completed',
            CallDisposition = 'Connected-DM',
            TaskSubtype = 'Call'
        );

        Test.startTest();
        insert t;
        Test.stopTest();

        // Phase 5: Action stays In Progress (no auto-complete), but context is updated
        NBA_Queue__c actionAfter = [
            SELECT Id, Status__c, Attempt_Count_Today__c, Last_Attempt_Method__c
            FROM NBA_Queue__c WHERE Id = :actionBefore.Id
        ];
        System.assertEquals('In Progress', actionAfter.Status__c,
            'Phase 5: Action should remain In Progress (no auto-complete)');
        System.assertEquals(1, actionAfter.Attempt_Count_Today__c,
            'Attempt count should increment for call task');
        System.assertEquals('Call', actionAfter.Last_Attempt_Method__c,
            'Last attempt method should be Call');

        // Cache should be invalidated
        NbaActionController.ActionWrapper afterCache = NbaCacheService.getCachedAction(userId);
        System.assertEquals(null, afterCache,
            'Cache should be invalidated after task completion');
    }

    @isTest
    static void testConnectedCall_invalidatesCacheForReengage() {
        Opportunity opp = [
            SELECT Id FROM Opportunity WHERE Account.Name = 'TaskTrig Test Account 2' LIMIT 1
        ];

        NBA_Queue__c actionBefore = [
            SELECT Id, Status__c FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Action_Type__c = 'Re-engage' LIMIT 1
        ];

        NbaTriggerContext.resetAll();

        Task t = new Task(
            WhatId = opp.Id,
            Subject = 'Connected with Gatekeeper',
            Status = 'Completed',
            CallDisposition = 'Connected-GK'
        );

        Test.startTest();
        insert t;
        Test.stopTest();

        // Phase 5: Action stays In Progress — on-demand evaluation will detect the activity
        NBA_Queue__c actionAfter = [
            SELECT Id, Status__c FROM NBA_Queue__c
            WHERE Id = :actionBefore.Id
        ];
        System.assertEquals('In Progress', actionAfter.Status__c,
            'Phase 5: Re-engage action should remain In Progress (no auto-complete)');
    }

    // ─── Task on Non-Opportunity → No Action ─────────────────────────

    @isTest
    static void testTaskOnAccount_noAction() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'TaskTrig Test Account 1' LIMIT 1];

        // Capture action state before
        NBA_Queue__c actionBefore = [
            SELECT Id, LastEvaluatedAt__c FROM NBA_Queue__c
            WHERE Account__c = :acc.Id LIMIT 1
        ];

        NbaTriggerContext.resetAll();

        Task t = new Task(
            WhatId = acc.Id,
            Subject = 'Account Task',
            Status = 'Completed'
        );

        Test.startTest();
        insert t;
        Test.stopTest();

        NBA_Queue__c actionAfter = [
            SELECT Id, LastEvaluatedAt__c FROM NBA_Queue__c
            WHERE Id = :actionBefore.Id
        ];

        System.assertEquals(actionBefore.LastEvaluatedAt__c, actionAfter.LastEvaluatedAt__c,
            'Task on Account should not update NBA action context');
    }

    // ─── Non-Completed Task → No Action ──────────────────────────────

    @isTest
    static void testNonCompletedTask_noAction() {
        Opportunity opp = [
            SELECT Id FROM Opportunity WHERE Account.Name = 'TaskTrig Test Account 1' LIMIT 1
        ];

        NBA_Queue__c actionBefore = [
            SELECT Id, LastEvaluatedAt__c, Status__c FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id LIMIT 1
        ];

        NbaTriggerContext.resetAll();

        Task t = new Task(
            WhatId = opp.Id,
            Subject = 'Open Task',
            Status = 'Not Started'
        );

        Test.startTest();
        insert t;
        Test.stopTest();

        NBA_Queue__c actionAfter = [
            SELECT Id, LastEvaluatedAt__c, Status__c FROM NBA_Queue__c
            WHERE Id = :actionBefore.Id
        ];

        System.assertEquals(actionBefore.LastEvaluatedAt__c, actionAfter.LastEvaluatedAt__c,
            'Non-completed task should not update action context');
    }

    // ─── Bulk Test ───────────────────────────────────────────────────

    @isTest
    static void testBulkTasks_noGovernorViolation() {
        Opportunity opp = [
            SELECT Id FROM Opportunity WHERE Account.Name = 'TaskTrig Test Account 3' LIMIT 1
        ];

        NbaTriggerContext.resetAll();

        List<Task> tasks = new List<Task>();
        for (Integer i = 0; i < 200; i++) {
            tasks.add(new Task(
                WhatId = opp.Id,
                Subject = 'Bulk Call Task ' + i,
                Status = 'Completed',
                TaskSubtype = 'Call'
            ));
        }

        Test.startTest();
        insert tasks;
        Test.stopTest();

        // Verify no exceptions and action was updated
        NBA_Queue__c action = [
            SELECT Id, Attempt_Count_Today__c FROM NBA_Queue__c
            WHERE Opportunity__c = :opp.Id AND Action_Type__c = 'Stage Progression' LIMIT 1
        ];

        // Note: Due to recursion guard, only the first batch fires.
        // The count may not be 200 — the important thing is no governor violation.
        System.assert(action.Attempt_Count_Today__c > 0,
            'Attempt count should be incremented after bulk task insert');
    }
}
