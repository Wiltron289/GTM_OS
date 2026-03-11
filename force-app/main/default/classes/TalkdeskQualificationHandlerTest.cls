@isTest
private class TalkdeskQualificationHandlerTest {

    private static Integer talkdeskIdCounter = 0;

    /** Enable the feature for all tests (CMDT is read-only in test context). */
    static {
        TalkdeskQualificationHandler.isActiveOverride = true;
    }

    /** Helper: build sample notes text with all qualification sections. */
    private static String buildFullNotes() {
        return '**Customer Story:** Crystal is enrolling in payroll for 29 employees.\n' +
               '**Inception or Switcher:** Switcher\n' +
               '**Decision Maker Identified:** True\n' +
               '**Business Challenges:** Overdue setup and auth form difficulties.\n' +
               '**Best Product Fit Identified:** True\n' +
               '**Features and Benefits Discussed:** PTO tracking, federal filing authorization.\n' +
               '**Budget Confirmed:** False\n' +
               '**Timeline Confirmed:** False\n' +
               '**Verbal Commit:** False\n' +
               '\n' +
               '- Get Crystal connected with an implementation specialist.\n' +
               '- Follow up on the liveness check issue.';
    }

    /** Helper: create Account + Opportunity. */
    private static Opportunity createOpp(Map<String, Object> overrides) {
        Account acct = new Account(Name = 'Test Corp ' + talkdeskIdCounter);
        insert acct;

        Opportunity opp = new Opportunity(
            Name = 'Test Deal',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = acct.Id,
            Source__c = 'Other'
        );
        if (overrides != null) {
            for (String field : overrides.keySet()) {
                opp.put(field, overrides.get(field));
            }
        }
        insert opp;
        return opp;
    }

    /** Helper: generate unique Talkdesk Id for the required field. */
    private static String nextTalkdeskId() {
        talkdeskIdCounter++;
        return 'TD-TEST-' + String.valueOf(talkdeskIdCounter) + '-' + String.valueOf(Datetime.now().getTime());
    }

    /** Insert with notes → fields should be parsed and populated on the Activity record. */
    @isTest
    static void testInsert_NotesParsedToFields() {
        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Notes__c = buildFullNotes()
        );

        Test.startTest();
        insert ta;
        Test.stopTest();

        talkdesk__Talkdesk_Activity__c result = [
            SELECT Customer_Story__c, Inception_Or_Switcher__c, Decision_Maker_Identified__c,
                   Business_Challenges__c, Best_Product_Fit_Identified__c,
                   Features_Benefits_Discussed__c, Budget_Confirmed__c,
                   Timeline_Confirmed__c, Verbal_Commit__c
            FROM talkdesk__Talkdesk_Activity__c
            WHERE Id = :ta.Id
        ];

        System.assert(result.Customer_Story__c.contains('Crystal'), 'Customer Story should be parsed');
        System.assertEquals('Switcher', result.Inception_Or_Switcher__c, 'Inception or Switcher should be parsed');
        System.assertEquals(true, result.Decision_Maker_Identified__c, 'Decision Maker should be true');
        System.assert(result.Business_Challenges__c.contains('setup'), 'Business Challenges should be parsed');
        System.assertEquals(true, result.Best_Product_Fit_Identified__c, 'Best Product Fit should be true');
        System.assert(result.Features_Benefits_Discussed__c.contains('PTO'), 'Features should be parsed');
        System.assertEquals(false, result.Budget_Confirmed__c, 'Budget should be false');
        System.assertEquals(false, result.Timeline_Confirmed__c, 'Timeline should be false');
        System.assertEquals(false, result.Verbal_Commit__c, 'Verbal Commit should be false');
    }

    /** Insert with notes + Opp link → fields parsed AND synced to Opportunity. */
    @isTest
    static void testInsert_WithOpp_SyncsToOpportunity() {
        Opportunity opp = createOpp(null);

        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Notes__c = buildFullNotes(),
            talkdesk__Opportunity__c = opp.Id
        );

        Test.startTest();
        insert ta;
        Test.stopTest();

        Opportunity updated = [
            SELECT Customer_Story__c, Inception_or_Switcher__c, Decision_Maker_Identified__c,
                   Business_Challenge__c, Best_Product_Fit_Identified__c,
                   Features_and_Benefits_Discussed__c, Budget_Confirmed__c,
                   Timeline_Confirmed__c, Verbal_Commit__c
            FROM Opportunity WHERE Id = :opp.Id
        ];

        System.assert(updated.Customer_Story__c.contains('Crystal'), 'Opp Customer Story should be synced');
        System.assertEquals('Switcher', updated.Inception_or_Switcher__c, 'Opp Inception should be synced');
        System.assertEquals(true, updated.Decision_Maker_Identified__c, 'Opp Decision Maker should be true');
        System.assert(updated.Business_Challenge__c.contains('setup'), 'Opp Business Challenge should be synced');
        System.assertEquals(true, updated.Best_Product_Fit_Identified__c, 'Opp Best Product Fit should be true');
    }

    /** Update that adds Opp link → sync should fire. */
    @isTest
    static void testUpdate_OppLinked_SyncsToOpportunity() {
        Opportunity opp = createOpp(null);

        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Notes__c = buildFullNotes()
        );
        insert ta;

        // Verify Opp is blank before linking
        Opportunity before = [SELECT Customer_Story__c FROM Opportunity WHERE Id = :opp.Id];
        System.assertEquals(null, before.Customer_Story__c, 'Opp should be blank before link');

        Test.startTest();
        ta.talkdesk__Opportunity__c = opp.Id;
        update ta;
        Test.stopTest();

        Opportunity updated = [
            SELECT Customer_Story__c, Decision_Maker_Identified__c
            FROM Opportunity WHERE Id = :opp.Id
        ];

        System.assert(updated.Customer_Story__c.contains('Crystal'), 'Opp should be synced after Opp link added');
        System.assertEquals(true, updated.Decision_Maker_Identified__c, 'Checkbox should sync after Opp link added');
    }

    /** Opp sync guardrails — existing text not overwritten, checkboxes don't flip to false. */
    @isTest
    static void testSync_GuardrailsRespected() {
        Opportunity opp = createOpp(new Map<String, Object>{
            'Customer_Story__c' => 'Original story',
            'Decision_Maker_Identified__c' => true,
            'Budget_Confirmed__c' => true
        });

        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Notes__c = buildFullNotes(),
            talkdesk__Opportunity__c = opp.Id
        );

        Test.startTest();
        insert ta;
        Test.stopTest();

        Opportunity updated = [
            SELECT Customer_Story__c, Decision_Maker_Identified__c, Budget_Confirmed__c
            FROM Opportunity WHERE Id = :opp.Id
        ];

        System.assertEquals('Original story', updated.Customer_Story__c, 'Existing text should not be overwritten');
        System.assertEquals(true, updated.Decision_Maker_Identified__c, 'True checkbox should stay true');
        System.assertEquals(true, updated.Budget_Confirmed__c, 'True checkbox should not flip to false');
    }

    /** No Opp link — parsing works, no sync errors. */
    @isTest
    static void testInsert_NoOpp_NoError() {
        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Notes__c = buildFullNotes()
        );

        Test.startTest();
        insert ta;
        Test.stopTest();

        talkdesk__Talkdesk_Activity__c result = [
            SELECT Customer_Story__c FROM talkdesk__Talkdesk_Activity__c WHERE Id = :ta.Id
        ];
        System.assert(result.Customer_Story__c.contains('Crystal'), 'Fields should still be parsed');
    }

    /** Blank notes — no parsing errors, fields stay default. */
    @isTest
    static void testInsert_BlankNotes_NoError() {
        talkdesk__Talkdesk_Activity__c ta = new talkdesk__Talkdesk_Activity__c(
            talkdesk__Talkdesk_Id__c = nextTalkdeskId(),
            talkdesk__Notes__c = ''
        );

        Test.startTest();
        insert ta;
        Test.stopTest();

        talkdesk__Talkdesk_Activity__c result = [
            SELECT Customer_Story__c, Decision_Maker_Identified__c
            FROM talkdesk__Talkdesk_Activity__c WHERE Id = :ta.Id
        ];
        System.assertEquals(null, result.Customer_Story__c, 'No notes should mean no parsed data');
        System.assertEquals(false, result.Decision_Maker_Identified__c, 'Default should be false');
    }
}
