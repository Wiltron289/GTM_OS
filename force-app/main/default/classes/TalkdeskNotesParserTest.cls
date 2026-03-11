@isTest
private class TalkdeskNotesParserTest {

    /** Full notes with all 9 qualification sections. */
    @isTest
    static void testParse_FullNotes() {
        String notes =
            '**Customer Story:** The customer, Crystal, is looking to enroll in payroll.\n' +
            '**Inception or Switcher:** Switcher\n' +
            '**Decision Maker Identified:** True\n' +
            '**Business Challenges:** Crystal is facing issues with setup.\n' +
            '**Best Product Fit Identified:** True\n' +
            '**Features and Benefits Discussed:** PTO tracking, federal filing auth.\n' +
            '**Budget Confirmed:** False\n' +
            '**Timeline Confirmed:** False\n' +
            '**Verbal Commit:** False\n' +
            '\n' +
            '- Get Crystal connected with an implementation specialist.\n' +
            '- Follow up on the liveness check issue.';

        Test.startTest();
        Map<String, String> parsed = TalkdeskNotesParser.parse(notes);
        Test.stopTest();

        System.assertEquals('The customer, Crystal, is looking to enroll in payroll.',
            parsed.get('Customer_Story__c'), 'Customer Story should be parsed');
        System.assertEquals('Switcher',
            parsed.get('Inception_Or_Switcher__c'), 'Inception or Switcher should be parsed');
        System.assertEquals('True',
            parsed.get('Decision_Maker_Identified__c'), 'Decision Maker should be True');
        System.assertEquals('Crystal is facing issues with setup.',
            parsed.get('Business_Challenges__c'), 'Business Challenges should be parsed');
        System.assertEquals('True',
            parsed.get('Best_Product_Fit_Identified__c'), 'Best Product Fit should be True');
        System.assertEquals('PTO tracking, federal filing auth.',
            parsed.get('Features_Benefits_Discussed__c'), 'Features should be parsed');
        System.assertEquals('False',
            parsed.get('Budget_Confirmed__c'), 'Budget Confirmed should be False');
        System.assertEquals('False',
            parsed.get('Timeline_Confirmed__c'), 'Timeline Confirmed should be False');
        System.assertEquals('False',
            parsed.get('Verbal_Commit__c'), 'Verbal Commit should be False');
    }

    /** Partial notes — only some sections present. */
    @isTest
    static void testParse_PartialNotes() {
        String notes =
            '**Customer Story:** Partial customer info.\n' +
            '**Decision Maker Identified:** True\n' +
            '**Budget Confirmed:** True';

        Test.startTest();
        Map<String, String> parsed = TalkdeskNotesParser.parse(notes);
        Test.stopTest();

        System.assertEquals(3, parsed.size(), 'Should have 3 parsed fields');
        System.assertEquals('Partial customer info.', parsed.get('Customer_Story__c'));
        System.assertEquals('True', parsed.get('Decision_Maker_Identified__c'));
        System.assertEquals('True', parsed.get('Budget_Confirmed__c'));
        System.assert(!parsed.containsKey('Inception_Or_Switcher__c'), 'Missing sections should not appear');
    }

    /** Empty and null notes return empty map. */
    @isTest
    static void testParse_EmptyAndNull() {
        Test.startTest();
        Map<String, String> parsedNull = TalkdeskNotesParser.parse(null);
        Map<String, String> parsedBlank = TalkdeskNotesParser.parse('');
        Map<String, String> parsedWhitespace = TalkdeskNotesParser.parse('   ');
        Test.stopTest();

        System.assertEquals(0, parsedNull.size(), 'Null should return empty map');
        System.assertEquals(0, parsedBlank.size(), 'Blank should return empty map');
        System.assertEquals(0, parsedWhitespace.size(), 'Whitespace should return empty map');
    }

    /** Multi-line values — text wraps across lines before next header. */
    @isTest
    static void testParse_MultiLineValue() {
        String notes =
            '**Customer Story:** The customer is a large enterprise\n' +
            'with multiple locations across the country\n' +
            'looking for a unified payroll solution.\n' +
            '**Inception or Switcher:** Inception';

        Test.startTest();
        Map<String, String> parsed = TalkdeskNotesParser.parse(notes);
        Test.stopTest();

        String story = parsed.get('Customer_Story__c');
        System.assert(story.contains('large enterprise'), 'Should contain first line');
        System.assert(story.contains('multiple locations'), 'Should contain continuation');
        System.assert(story.contains('unified payroll'), 'Should contain third line');
        System.assertEquals('Inception', parsed.get('Inception_Or_Switcher__c'));
    }

    /** Notes with only action items (no ** headers) — should return empty. */
    @isTest
    static void testParse_NoHeaders() {
        String notes =
            '- Follow up with the customer about their account.\n' +
            '- Send pricing documentation.\n' +
            '- Schedule a demo for next week.';

        Test.startTest();
        Map<String, String> parsed = TalkdeskNotesParser.parse(notes);
        Test.stopTest();

        System.assertEquals(0, parsed.size(), 'No headers means no parsed data');
    }

    /** applyToRecord correctly sets text and boolean fields. */
    @isTest
    static void testApplyToRecord() {
        talkdesk__Talkdesk_Activity__c record = new talkdesk__Talkdesk_Activity__c();
        Map<String, String> parsed = new Map<String, String>{
            'Customer_Story__c' => 'Test story',
            'Inception_Or_Switcher__c' => 'Switcher',
            'Decision_Maker_Identified__c' => 'True',
            'Budget_Confirmed__c' => 'False',
            'Verbal_Commit__c' => 'true'
        };

        Test.startTest();
        TalkdeskNotesParser.applyToRecord(record, parsed);
        Test.stopTest();

        System.assertEquals('Test story', record.Customer_Story__c, 'Text field should be set');
        System.assertEquals('Switcher', record.Inception_Or_Switcher__c, 'Text field should be set');
        System.assertEquals(true, record.Decision_Maker_Identified__c, 'True string should become true');
        System.assertEquals(false, record.Budget_Confirmed__c, 'False string should become false');
        System.assertEquals(true, record.Verbal_Commit__c, 'Lowercase true should become true');
    }

    /** matchHeader returns correct header name for known headers, null for unknown. */
    @isTest
    static void testMatchHeader() {
        Test.startTest();
        System.assertEquals('Customer Story',
            TalkdeskNotesParser.matchHeader('**Customer Story:** Some value'));
        System.assertEquals('Decision Maker Identified',
            TalkdeskNotesParser.matchHeader('**Decision Maker Identified:** True'));
        System.assertEquals(null,
            TalkdeskNotesParser.matchHeader('**Unknown Header:** Some value'));
        System.assertEquals(null,
            TalkdeskNotesParser.matchHeader('Regular text line'));
        System.assertEquals(null,
            TalkdeskNotesParser.matchHeader(''));
        Test.stopTest();
    }
}
