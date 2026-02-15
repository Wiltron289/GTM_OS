/**
 * Test class for NbaActionSelectionService.
 * Verifies gate filtering, layer precedence, and score-based ranking.
 */
@isTest
private class NbaActionSelectionServiceTest {

    @TestSetup
    static void setupData() {
        List<Account> accs = new List<Account>();
        for (Integer i = 1; i <= 3; i++) {
            accs.add(new Account(
                Name = 'Selection Test Account ' + i,
                Entity_ID__c = 'SEL-00' + i
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
                Name = 'Sel Opp ' + i,
                AccountId = accs[i].Id,
                StageName = 'New',
                CloseDate = Date.today().addDays(30),
                Amount = 3000 + (i * 1000),
                Source__c = 'N/A'
            );
            if (payrollRtId != null) o.RecordTypeId = payrollRtId;
            opps.add(o);
        }
        insert opps;

        // Action 1: Layer 3, high score (0.95)
        NBA_Queue__c a1 = new NBA_Queue__c(
            Opportunity__c = opps[0].Id, Account__c = accs[0].Id,
            Sales_Rep__c = UserInfo.getUserId(), Status__c = 'Pending',
            Action_Type__c = 'Re-engage', Priority_Score__c = 0.95,
            Priority_Layer__c = 'Layer 3 - Impact+Urgency',
            Priority_Bucket__c = 'High Impact Focus', Workflow_Mode__c = 'Pipeline'
        );

        // Action 2: Layer 1, low score (0.30) — should be selected first
        NBA_Queue__c a2 = new NBA_Queue__c(
            Opportunity__c = opps[1].Id, Account__c = accs[1].Id,
            Sales_Rep__c = UserInfo.getUserId(), Status__c = 'Pending',
            Action_Type__c = 'First Touch', Priority_Score__c = 0.30,
            Priority_Layer__c = 'Layer 1 - Time Bound', Is_Time_Bound__c = true,
            Priority_Bucket__c = 'Cadence Due Today', Workflow_Mode__c = 'Pipeline'
        );

        // Action 3: Layer 3, medium score (0.60), IN COOLDOWN
        NBA_Queue__c a3 = new NBA_Queue__c(
            Opportunity__c = opps[2].Id, Account__c = accs[2].Id,
            Sales_Rep__c = UserInfo.getUserId(), Status__c = 'Pending',
            Action_Type__c = 'Follow Up', Priority_Score__c = 0.60,
            Priority_Layer__c = 'Layer 3 - Impact+Urgency',
            Priority_Bucket__c = 'General Pipeline', Workflow_Mode__c = 'Pipeline',
            CooldownUntil__c = Datetime.now().addHours(2)
        );

        insert new List<NBA_Queue__c>{ a1, a2, a3 };
    }

    @isTest
    static void testSelectTop_ReturnsLayer1First() {
        Test.startTest();
        NBA_Queue__c top = NbaActionSelectionService.selectTop(UserInfo.getUserId());
        Test.stopTest();

        System.assertNotEquals(null, top, 'Should return a top action');
        System.assertEquals('Layer 1 - Time Bound', top.Priority_Layer__c,
            'Layer 1 should be selected over Layer 3 regardless of score');
        System.assertEquals('First Touch', top.Action_Type__c,
            'Selected action should be First Touch');
    }

    @isTest
    static void testSelectTop_CooldownFiltered() {
        // Verify that the cooldown action is NOT returned
        Test.startTest();
        NBA_Queue__c top = NbaActionSelectionService.selectTop(UserInfo.getUserId());
        Test.stopTest();

        System.assertNotEquals(null, top, 'Should return an action');
        // The cooldown action has score 0.60 — it should be filtered out
        System.assertNotEquals(0.60, top.Priority_Score__c,
            'Cooldown action should not be selected');
    }

    @isTest
    static void testSelectTop_NoCandidates() {
        // Delete all Pending actions
        delete [SELECT Id FROM NBA_Queue__c WHERE Status__c = 'Pending'];

        Test.startTest();
        NBA_Queue__c top = NbaActionSelectionService.selectTop(UserInfo.getUserId());
        Test.stopTest();

        System.assertEquals(null, top, 'No candidates should return null');
    }

    @isTest
    static void testSelectTop_NullUserId() {
        Test.startTest();
        NBA_Queue__c top = NbaActionSelectionService.selectTop(null);
        Test.stopTest();

        System.assertEquals(null, top, 'Null user ID should return null');
    }

    @isTest
    static void testRankActions_SortOrder() {
        List<NBA_Queue__c> candidates = [
            SELECT Id, Opportunity__c, Status__c, Action_Type__c,
                   Priority_Score__c, Priority_Layer__c, Priority_Bucket__c,
                   Is_Time_Bound__c, Impact_Score__c, Urgency_Score__c,
                   CooldownUntil__c, Workflow_Mode__c, Sales_Rep__c, DueAt__c
            FROM NBA_Queue__c
            WHERE Status__c = 'Pending'
              AND Sales_Rep__c = :UserInfo.getUserId()
        ];

        Test.startTest();
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(candidates);
        Test.stopTest();

        // Should have 2 actions (cooldown one is filtered)
        System.assertEquals(2, ranked.size(), 'Should have 2 actions after gating (1 in cooldown)');
        // First should be Layer 1
        System.assertEquals(1, ranked[0].layerRank, 'First ranked should be Layer 1');
        // Second should be Layer 3 with score 0.95
        System.assertEquals(3, ranked[1].layerRank, 'Second ranked should be Layer 3');
    }
}
