@isTest
private class AICallNoteServiceTest {

    /** Full structured payload — every section populated. */
    @isTest
    static void testCreateCallNote_FullPayload() {
        String jsonBody = buildFullPayload();

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/ai-call-notes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(jsonBody);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AICallNoteService.CallNoteResponse res = AICallNoteService.createCallNote();
        Test.stopTest();

        System.assert(res.success, 'Expected success but got: ' + res.message);
        System.assertNotEquals(null, res.recordId);

        AI_Call_Note__c note = [
            SELECT Meeting_ID__c, Customer_Email__c,
                   Contact__c, Account__c, Opportunity__c, Event_ID__c, Lead__c,
                   Customer_Profile__c, Topics_Discussed__c, Main_Challenges__c,
                   Overall_Tone__c, Deal_Momentum__c, Transcript_Partial__c,
                   Company_Size__c, Industry__c, Budget_Signals__c, Timeline_Signals__c,
                   Current_Tools__c, Pain_Points__c, Stakeholders__c,
                   Pricing_Discussion__c, Implementation_Onboarding__c,
                   Product_Areas_Discussed__c, Feature_Questions__c, Integration_Topics__c,
                   Risks_Or_Objections__c, Agreed_Next_Steps__c, Action_Items_JSON__c,
                   Raw_Payload__c,
                   Customer_Story__c, Inception_Or_Switcher__c, Decision_Maker_Identified__c,
                   Business_Challenges__c, Best_Product_Fit_Identified__c,
                   Features_Benefits_Discussed__c, Budget_Confirmed__c,
                   Timeline_Confirmed__c, Verbal_Commit__c
            FROM AI_Call_Note__c
            WHERE Id = :res.recordId
        ];

        // auto-match lookups — no matching data in this test
        System.assertEquals(null, note.Contact__c);
        System.assertEquals(null, note.Account__c);
        System.assertEquals(null, note.Opportunity__c);
        System.assertEquals(null, note.Event_ID__c);
        System.assertEquals(null, note.Lead__c);

        // top-level fields
        System.assertEquals('mtg_abc123', note.Meeting_ID__c);
        System.assertEquals('jane.doe@acme.com', note.Customer_Email__c);

        // call_summary scalars
        System.assertEquals('Mid-market SaaS company evaluating CRM migration', note.Customer_Profile__c);
        System.assertEquals('CRM migration, pricing, timeline', note.Topics_Discussed__c);
        System.assertEquals('Data migration complexity, user adoption', note.Main_Challenges__c);
        System.assertEquals('Cautiously optimistic', note.Overall_Tone__c);
        System.assertEquals('Medium — needs internal approval', note.Deal_Momentum__c);
        System.assertEquals(false, note.Transcript_Partial__c);

        // customer_context scalars
        System.assertEquals('200-500', note.Company_Size__c);
        System.assertEquals('Financial Services', note.Industry__c);
        System.assertEquals('Approved Q3 budget for tooling', note.Budget_Signals__c);
        System.assertEquals('Go-live by September', note.Timeline_Signals__c);

        // customer_context arrays — stored as JSON
        System.assert(note.Current_Tools__c.contains('HubSpot'));
        System.assert(note.Pain_Points__c.contains('Manual data entry'));
        System.assert(note.Stakeholders__c.contains('VP of Sales'));

        // key_discussion_points
        System.assertEquals('Standard tier vs. Enterprise', note.Pricing_Discussion__c);
        System.assertEquals('2-week onboarding program', note.Implementation_Onboarding__c);
        System.assert(note.Product_Areas_Discussed__c.contains('Reporting'));
        System.assert(note.Feature_Questions__c.contains('custom dashboards'));
        System.assert(note.Integration_Topics__c.contains('Slack'));

        // top-level arrays
        System.assert(note.Risks_Or_Objections__c.contains('budget freeze'));
        System.assert(note.Agreed_Next_Steps__c.contains('Send proposal'));
        System.assert(note.Action_Items_JSON__c.contains('Prepare ROI deck'));

        // qualification
        System.assert(note.Customer_Story__c.contains('Mama Bear Bookkeeping'));
        System.assertEquals('Switcher', note.Inception_Or_Switcher__c);
        System.assertEquals(true, note.Decision_Maker_Identified__c);
        System.assert(note.Business_Challenges__c.contains('manual payroll'));
        System.assertEquals(true, note.Best_Product_Fit_Identified__c);
        System.assert(note.Features_Benefits_Discussed__c.contains('Automated payroll'));
        System.assertEquals(true, note.Budget_Confirmed__c);
        System.assertEquals(true, note.Timeline_Confirmed__c);
        System.assertEquals(false, note.Verbal_Commit__c);

        // Raw_Payload__c always captured
        System.assertNotEquals(null, note.Raw_Payload__c);
    }

    /** Partial payload — only call_summary provided. */
    @isTest
    static void testCreateCallNote_PartialPayload() {
        Map<String, Object> body = new Map<String, Object>{
            'call_summary' => new Map<String, Object>{
                'customer_profile' => 'Enterprise prospect',
                'overall_tone' => 'Positive',
                'transcript_partial' => true
            }
        };
        String jsonBody = JSON.serialize(body);

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/ai-call-notes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(jsonBody);
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AICallNoteService.CallNoteResponse res = AICallNoteService.createCallNote();
        Test.stopTest();

        System.assert(res.success, 'Expected success but got: ' + res.message);

        AI_Call_Note__c note = [
            SELECT Customer_Profile__c, Overall_Tone__c, Transcript_Partial__c,
                   Company_Size__c, Action_Items_JSON__c
            FROM AI_Call_Note__c
            WHERE Id = :res.recordId
        ];
        System.assertEquals('Enterprise prospect', note.Customer_Profile__c);
        System.assertEquals('Positive', note.Overall_Tone__c);
        System.assertEquals(true, note.Transcript_Partial__c);
        System.assertEquals(null, note.Company_Size__c);
        System.assertEquals(null, note.Action_Items_JSON__c);
    }

    /** Empty object — should still succeed and create a record. */
    @isTest
    static void testCreateCallNote_EmptyPayload() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/ai-call-notes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AICallNoteService.CallNoteResponse res = AICallNoteService.createCallNote();
        Test.stopTest();

        System.assert(res.success, 'Expected success for empty object but got: ' + res.message);
        System.assertNotEquals(null, res.recordId);
    }

    /** Invalid JSON — should return 400. */
    @isTest
    static void testCreateCallNote_InvalidPayload() {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/ai-call-notes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('not valid json!!!');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AICallNoteService.CallNoteResponse res = AICallNoteService.createCallNote();
        Test.stopTest();

        System.assert(!res.success, 'Should have failed on bad JSON');
        System.assertEquals(400, RestContext.response.statusCode);
    }

    // =====================================================================
    // Auto-match tests
    // =====================================================================

    /** Tier 1: Event matched by Location = meeting_id. WhatId = Opportunity. */
    @isTest
    static void testCreateCallNote_AutoMatchTier1_MeetingId() {
        // Setup: Account → Contact → Opportunity → Event (Location = meeting ID)
        Account acct = new Account(Name = 'Tier1 Corp');
        insert acct;
        Contact con = new Contact(FirstName = 'Tier1', LastName = 'User',
                                  Email = 'tier1@example.com', AccountId = acct.Id);
        insert con;
        Opportunity opp = new Opportunity(Name = 'Tier1 Deal', StageName = 'Prospecting',
                                          CloseDate = Date.today().addDays(30),
                                          AccountId = acct.Id, Source__c = 'Other');
        insert opp;
        Event evt = new Event(Subject = 'Call', WhoId = con.Id, WhatId = opp.Id,
                              Location = 'mtg_tier1_001',
                              ActivityDateTime = Datetime.now(),
                              DurationInMinutes = 30);
        insert evt;

        // Build payload with matching meeting_id
        Map<String, Object> body = new Map<String, Object>{
            'meeting_id' => 'mtg_tier1_001',
            'customer_email' => 'tier1@example.com'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/ai-call-notes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AICallNoteService.CallNoteResponse res = AICallNoteService.createCallNote();
        Test.stopTest();

        System.assert(res.success, 'Expected success but got: ' + res.message);

        AI_Call_Note__c note = [
            SELECT Contact__c, Account__c, Opportunity__c, Event_ID__c, Lead__c
            FROM AI_Call_Note__c WHERE Id = :res.recordId
        ];
        System.assertEquals(con.Id, note.Contact__c, 'Contact should be set from Event WhoId');
        System.assertEquals(acct.Id, note.Account__c, 'Account should be derived from Opportunity');
        System.assertEquals(opp.Id, note.Opportunity__c, 'Opportunity should be set from Event WhatId');
        System.assertEquals(evt.Id, note.Event_ID__c, 'Event_ID should be stored');
        System.assertEquals(null, note.Lead__c, 'Lead should be null (WhoId is Contact)');
    }

    /** Tier 2: No Event matches meeting_id. Contact found by email → most recent Event with WhatId = Account. */
    @isTest
    static void testCreateCallNote_AutoMatchTier2_CustomerEmail() {
        Account acct = new Account(Name = 'Tier2 Corp');
        insert acct;
        Contact con = new Contact(FirstName = 'Tier2', LastName = 'User',
                                  Email = 'tier2@example.com', AccountId = acct.Id);
        insert con;
        // Event linked to Contact but Location does NOT match the meeting_id
        Event evt = new Event(Subject = 'Follow-up', WhoId = con.Id, WhatId = acct.Id,
                              Location = 'some_other_location',
                              ActivityDateTime = Datetime.now(),
                              DurationInMinutes = 30);
        insert evt;

        Map<String, Object> body = new Map<String, Object>{
            'meeting_id' => 'mtg_no_match',
            'customer_email' => 'tier2@example.com'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/ai-call-notes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AICallNoteService.CallNoteResponse res = AICallNoteService.createCallNote();
        Test.stopTest();

        System.assert(res.success, 'Expected success but got: ' + res.message);

        AI_Call_Note__c note = [
            SELECT Contact__c, Account__c, Opportunity__c, Event_ID__c, Lead__c
            FROM AI_Call_Note__c WHERE Id = :res.recordId
        ];
        System.assertEquals(con.Id, note.Contact__c, 'Contact should be set from email lookup');
        System.assertEquals(acct.Id, note.Account__c, 'Account should be set from Event WhatId');
        System.assertEquals(null, note.Opportunity__c, 'Opportunity should be null (WhatId is Account)');
        System.assertEquals(evt.Id, note.Event_ID__c, 'Event_ID should be stored');
        System.assertEquals(null, note.Lead__c, 'Lead should be null (matched Contact)');
    }

    /** Contact found by email, no Event exists → Account derived from Contact.AccountId. */
    @isTest
    static void testCreateCallNote_AutoMatch_AccountFromContact() {
        Account acct = new Account(Name = 'ContactOnly Corp');
        insert acct;
        Contact con = new Contact(FirstName = 'NoEvent', LastName = 'User',
                                  Email = 'noevent@example.com', AccountId = acct.Id);
        insert con;

        Map<String, Object> body = new Map<String, Object>{
            'customer_email' => 'noevent@example.com'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/ai-call-notes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AICallNoteService.CallNoteResponse res = AICallNoteService.createCallNote();
        Test.stopTest();

        System.assert(res.success, 'Expected success but got: ' + res.message);

        AI_Call_Note__c note = [
            SELECT Contact__c, Account__c, Opportunity__c, Event_ID__c, Lead__c
            FROM AI_Call_Note__c WHERE Id = :res.recordId
        ];
        System.assertEquals(con.Id, note.Contact__c, 'Contact should be set from email lookup');
        System.assertEquals(acct.Id, note.Account__c, 'Account should be derived from Contact');
        System.assertEquals(null, note.Opportunity__c, 'Opportunity should be null');
        System.assertEquals(null, note.Event_ID__c, 'Event_ID should be null (no Event)');
        System.assertEquals(null, note.Lead__c, 'Lead should be null (matched Contact)');
    }

    /** No matching records at all — all lookups null, record still created. */
    @isTest
    static void testCreateCallNote_AutoMatch_NoMatchFound() {
        Map<String, Object> body = new Map<String, Object>{
            'meeting_id' => 'mtg_nonexistent',
            'customer_email' => 'nobody@nowhere.com'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/ai-call-notes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AICallNoteService.CallNoteResponse res = AICallNoteService.createCallNote();
        Test.stopTest();

        System.assert(res.success, 'Expected success but got: ' + res.message);

        AI_Call_Note__c note = [
            SELECT Contact__c, Account__c, Opportunity__c, Event_ID__c, Lead__c
            FROM AI_Call_Note__c WHERE Id = :res.recordId
        ];
        System.assertEquals(null, note.Contact__c, 'Contact should be null');
        System.assertEquals(null, note.Account__c, 'Account should be null');
        System.assertEquals(null, note.Opportunity__c, 'Opportunity should be null');
        System.assertEquals(null, note.Event_ID__c, 'Event_ID should be null');
        System.assertEquals(null, note.Lead__c, 'Lead should be null');
    }

    /** Tier 1: Event matched by Location = meeting_id. WhoId = Lead (00Q prefix). */
    @isTest
    static void testCreateCallNote_AutoMatchTier1_Lead() {
        Lead ld = new Lead(FirstName = 'LeadTier1', LastName = 'Prospect',
                           Email = 'leadtier1@example.com', Company = 'Lead Corp');
        insert ld;
        Event evt = new Event(Subject = 'Intro Call', WhoId = ld.Id,
                              Location = 'mtg_lead_001',
                              ActivityDateTime = Datetime.now(),
                              DurationInMinutes = 30);
        insert evt;

        Map<String, Object> body = new Map<String, Object>{
            'meeting_id' => 'mtg_lead_001',
            'customer_email' => 'leadtier1@example.com'
        };

        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/ai-call-notes';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(JSON.serialize(body));
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        AICallNoteService.CallNoteResponse res = AICallNoteService.createCallNote();
        Test.stopTest();

        System.assert(res.success, 'Expected success but got: ' + res.message);

        AI_Call_Note__c note = [
            SELECT Contact__c, Account__c, Opportunity__c, Event_ID__c, Lead__c
            FROM AI_Call_Note__c WHERE Id = :res.recordId
        ];
        System.assertEquals(ld.Id, note.Lead__c, 'Lead should be set from Event WhoId');
        System.assertEquals(null, note.Contact__c, 'Contact should be null (WhoId is Lead)');
        System.assertEquals(evt.Id, note.Event_ID__c, 'Event_ID should be stored');
    }

    // --- Test data builder ---

    private static String buildFullPayload() {
        Map<String, Object> body = new Map<String, Object>();

        body.put('meeting_id', 'mtg_abc123');
        body.put('customer_email', 'jane.doe@acme.com');

        body.put('call_summary', new Map<String, Object>{
            'customer_profile' => 'Mid-market SaaS company evaluating CRM migration',
            'topics_discussed' => 'CRM migration, pricing, timeline',
            'main_challenges' => 'Data migration complexity, user adoption',
            'overall_tone' => 'Cautiously optimistic',
            'deal_momentum' => 'Medium — needs internal approval',
            'transcript_partial' => false
        });

        body.put('customer_context', new Map<String, Object>{
            'company_size' => '200-500',
            'industry' => 'Financial Services',
            'current_tools' => new List<String>{ 'HubSpot', 'Jira', 'Slack' },
            'pain_points' => new List<String>{ 'Manual data entry', 'No unified view' },
            'budget_signals' => 'Approved Q3 budget for tooling',
            'timeline_signals' => 'Go-live by September',
            'stakeholders' => new List<String>{ 'VP of Sales', 'CTO', 'RevOps Manager' }
        });

        body.put('key_discussion_points', new Map<String, Object>{
            'product_areas_discussed' => new List<String>{ 'Reporting', 'Automations' },
            'feature_questions' => new List<String>{ 'Does it support custom dashboards?', 'API rate limits?' },
            'pricing_discussion' => 'Standard tier vs. Enterprise',
            'integration_topics' => new List<String>{ 'Slack', 'Jira' },
            'implementation_onboarding' => '2-week onboarding program'
        });

        body.put('risks_or_objections', new List<String>{
            'Potential budget freeze in Q4',
            'Competing evaluation with Competitor X'
        });

        body.put('agreed_next_steps', new List<Object>{
            new Map<String, Object>{ 'action' => 'Send proposal', 'owner' => 'AE', 'timing' => 'By Friday' },
            new Map<String, Object>{ 'action' => 'Schedule technical deep-dive', 'owner' => 'SE', 'timing' => 'Next week' }
        });

        body.put('action_items', new List<Object>{
            new Map<String, Object>{ 'task' => 'Prepare ROI deck', 'owner' => 'AE', 'timing' => 'Before next call' },
            new Map<String, Object>{ 'task' => 'Share API docs', 'owner' => 'SE', 'timing' => 'Tomorrow' }
        });

        body.put('qualification', new Map<String, Object>{
            'customer_story' => 'Mama Bear Bookkeeping is a small bookkeeping firm serving local businesses.',
            'inception_or_switcher' => 'Switcher',
            'decision_maker_identified' => 'True',
            'business_challenges' => 'Spending too much time on manual payroll runs across multiple clients.',
            'best_product_fit_identified' => 'True',
            'features_and_benefits_discussed' => 'Automated payroll runs, multi-client dashboard, tax filing integration',
            'budget_confirmed' => 'True',
            'timeline_confirmed' => 'True',
            'verbal_commit' => 'False'
        });

        return JSON.serialize(body);
    }
}
