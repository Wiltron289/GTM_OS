@isTest
private class AICallNoteQualificationSyncTest {

    /** Helper: create Account + Opportunity with optional pre-set qualification fields. */
    private static Opportunity createOpp(Map<String, Object> overrides) {
        Account acct = new Account(Name = 'Test Corp');
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

    /** Helper: build and insert an AI_Call_Note__c linked to an Opportunity. */
    private static AI_Call_Note__c insertNote(Id oppId, Map<String, Object> overrides) {
        AI_Call_Note__c note = new AI_Call_Note__c(
            Opportunity__c = oppId
        );
        if (overrides != null) {
            for (String field : overrides.keySet()) {
                note.put(field, overrides.get(field));
            }
        }
        insert note;
        return note;
    }

    /** Happy path: Opp fields are blank — all qualification fields get populated. */
    @isTest
    static void testSync_AllFieldsPopulated() {
        Opportunity opp = createOpp(null);

        Test.startTest();
        insertNote(opp.Id, new Map<String, Object>{
            'Customer_Story__c' => 'A great customer story',
            'Inception_Or_Switcher__c' => 'Switcher',
            'Decision_Maker_Identified__c' => true,
            'Business_Challenges__c' => 'Manual processes',
            'Best_Product_Fit_Identified__c' => true,
            'Features_Benefits_Discussed__c' => 'Automated payroll, dashboard',
            'Budget_Confirmed__c' => true,
            'Timeline_Confirmed__c' => true,
            'Verbal_Commit__c' => true
        });
        Test.stopTest();

        Opportunity updated = [
            SELECT Customer_Story__c, Inception_or_Switcher__c, Decision_Maker_Identified__c,
                   Business_Challenge__c, Best_Product_Fit_Identified__c,
                   Features_and_Benefits_Discussed__c, Budget_Confirmed__c,
                   Timeline_Confirmed__c, Verbal_Commit__c
            FROM Opportunity WHERE Id = :opp.Id
        ];

        System.assertEquals('A great customer story', updated.Customer_Story__c);
        System.assertEquals('Switcher', updated.Inception_or_Switcher__c);
        System.assertEquals(true, updated.Decision_Maker_Identified__c);
        System.assertEquals('Manual processes', updated.Business_Challenge__c);
        System.assertEquals(true, updated.Best_Product_Fit_Identified__c);
        System.assertEquals('Automated payroll, dashboard', updated.Features_and_Benefits_Discussed__c);
        System.assertEquals(true, updated.Budget_Confirmed__c);
        System.assertEquals(true, updated.Timeline_Confirmed__c);
        System.assertEquals(true, updated.Verbal_Commit__c);
    }

    /** No-overwrite: Opp already has text values — they should not be replaced. */
    @isTest
    static void testSync_NoOverwriteExistingText() {
        Opportunity opp = createOpp(new Map<String, Object>{
            'Customer_Story__c' => 'Original story',
            'Inception_or_Switcher__c' => 'Inception',
            'Business_Challenge__c' => 'Original challenge',
            'Features_and_Benefits_Discussed__c' => 'Original features'
        });

        Test.startTest();
        insertNote(opp.Id, new Map<String, Object>{
            'Customer_Story__c' => 'New story from call',
            'Inception_Or_Switcher__c' => 'Switcher',
            'Business_Challenges__c' => 'New challenge from call',
            'Features_Benefits_Discussed__c' => 'New features from call'
        });
        Test.stopTest();

        Opportunity updated = [
            SELECT Customer_Story__c, Inception_or_Switcher__c,
                   Business_Challenge__c, Features_and_Benefits_Discussed__c
            FROM Opportunity WHERE Id = :opp.Id
        ];

        System.assertEquals('Original story', updated.Customer_Story__c, 'Should not overwrite existing Customer_Story');
        System.assertEquals('Inception', updated.Inception_or_Switcher__c, 'Should not overwrite existing Inception_or_Switcher');
        System.assertEquals('Original challenge', updated.Business_Challenge__c, 'Should not overwrite existing Business_Challenge');
        System.assertEquals('Original features', updated.Features_and_Benefits_Discussed__c, 'Should not overwrite existing Features');
    }

    /** Checkbox ratchet: true on Opp stays true even if note has false. */
    @isTest
    static void testSync_CheckboxNeverFlipsToFalse() {
        Opportunity opp = createOpp(new Map<String, Object>{
            'Decision_Maker_Identified__c' => true,
            'Best_Product_Fit_Identified__c' => true,
            'Budget_Confirmed__c' => true,
            'Timeline_Confirmed__c' => true,
            'Verbal_Commit__c' => true
        });

        Test.startTest();
        insertNote(opp.Id, new Map<String, Object>{
            'Decision_Maker_Identified__c' => false,
            'Best_Product_Fit_Identified__c' => false,
            'Budget_Confirmed__c' => false,
            'Timeline_Confirmed__c' => false,
            'Verbal_Commit__c' => false
        });
        Test.stopTest();

        Opportunity updated = [
            SELECT Decision_Maker_Identified__c, Best_Product_Fit_Identified__c,
                   Budget_Confirmed__c, Timeline_Confirmed__c, Verbal_Commit__c
            FROM Opportunity WHERE Id = :opp.Id
        ];

        System.assertEquals(true, updated.Decision_Maker_Identified__c, 'Should stay true');
        System.assertEquals(true, updated.Best_Product_Fit_Identified__c, 'Should stay true');
        System.assertEquals(true, updated.Budget_Confirmed__c, 'Should stay true');
        System.assertEquals(true, updated.Timeline_Confirmed__c, 'Should stay true');
        System.assertEquals(true, updated.Verbal_Commit__c, 'Should stay true');
    }

    /** No Opportunity on the note — should not error. */
    @isTest
    static void testSync_NoOpportunity() {
        Test.startTest();
        AI_Call_Note__c note = new AI_Call_Note__c(
            Customer_Story__c = 'Some story',
            Decision_Maker_Identified__c = true
        );
        insert note;
        Test.stopTest();

        // Just verify the note was created — no exceptions
        AI_Call_Note__c created = [SELECT Id FROM AI_Call_Note__c WHERE Id = :note.Id];
        System.assertNotEquals(null, created.Id);
    }
}
