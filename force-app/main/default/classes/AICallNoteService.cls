@RestResource(urlMapping='/ai-call-notes')
global with sharing class AICallNoteService {

    global class CallNoteResponse {
        global Boolean success;
        global String recordId;
        global String message;
    }

    @HttpPost
    global static CallNoteResponse createCallNote() {
        RestRequest req = RestContext.request;
        CallNoteResponse res = new CallNoteResponse();

        try {
            String requestBody = req.requestBody.toString();
            Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(requestBody);

            AI_Call_Note__c note = new AI_Call_Note__c();
            note.Raw_Payload__c = requestBody;

            // --- top-level fields ---
            note.Meeting_ID__c     = getString(payload, 'meeting_id');
            note.Customer_Email__c = getString(payload, 'customer_email');

            // --- call_summary ---
            Map<String, Object> callSummary = getMap(payload, 'call_summary');
            if (callSummary != null) {
                note.Customer_Profile__c    = getString(callSummary, 'customer_profile');
                note.Topics_Discussed__c    = getString(callSummary, 'topics_discussed');
                note.Main_Challenges__c     = getString(callSummary, 'main_challenges');
                note.Overall_Tone__c        = getString(callSummary, 'overall_tone');
                note.Deal_Momentum__c       = getString(callSummary, 'deal_momentum');
                note.Transcript_Partial__c  = getBool(callSummary, 'transcript_partial');
            }

            // --- customer_context ---
            Map<String, Object> customerCtx = getMap(payload, 'customer_context');
            if (customerCtx != null) {
                note.Company_Size__c     = getString(customerCtx, 'company_size');
                note.Industry__c         = getString(customerCtx, 'industry');
                note.Budget_Signals__c   = getString(customerCtx, 'budget_signals');
                note.Timeline_Signals__c = getString(customerCtx, 'timeline_signals');
                note.Current_Tools__c    = serializeArray(customerCtx, 'current_tools');
                note.Pain_Points__c      = serializeArray(customerCtx, 'pain_points');
                note.Stakeholders__c     = serializeArray(customerCtx, 'stakeholders');
            }

            // --- key_discussion_points ---
            Map<String, Object> keyPoints = getMap(payload, 'key_discussion_points');
            if (keyPoints != null) {
                note.Pricing_Discussion__c        = getString(keyPoints, 'pricing_discussion');
                note.Implementation_Onboarding__c = getString(keyPoints, 'implementation_onboarding');
                note.Product_Areas_Discussed__c   = serializeArray(keyPoints, 'product_areas_discussed');
                note.Feature_Questions__c         = serializeArray(keyPoints, 'feature_questions');
                note.Integration_Topics__c        = serializeArray(keyPoints, 'integration_topics');
            }

            // --- top-level arrays ---
            note.Risks_Or_Objections__c = serializeArray(payload, 'risks_or_objections');
            note.Agreed_Next_Steps__c   = serializeArray(payload, 'agreed_next_steps');
            note.Action_Items_JSON__c   = serializeArray(payload, 'action_items');

            // --- qualification ---
            Map<String, Object> qualification = getMap(payload, 'qualification');
            if (qualification != null) {
                note.Customer_Story__c              = getString(qualification, 'customer_story');
                note.Inception_Or_Switcher__c       = getString(qualification, 'inception_or_switcher');
                note.Decision_Maker_Identified__c   = getBoolString(qualification, 'decision_maker_identified');
                note.Business_Challenges__c         = getString(qualification, 'business_challenges');
                note.Best_Product_Fit_Identified__c = getBoolString(qualification, 'best_product_fit_identified');
                note.Features_Benefits_Discussed__c = getString(qualification, 'features_and_benefits_discussed');
                note.Budget_Confirmed__c            = getBoolString(qualification, 'budget_confirmed');
                note.Timeline_Confirmed__c          = getBoolString(qualification, 'timeline_confirmed');
                note.Verbal_Commit__c               = getBoolString(qualification, 'verbal_commit');
            }

            // --- auto-match related records ---
            resolveRelatedRecords(note, note.Meeting_ID__c, note.Customer_Email__c);

            insert note;

            res.success  = true;
            res.recordId = note.Id;
            res.message  = 'AI Call Note created successfully.';

        } catch (Exception e) {
            res.success = false;
            res.message = e.getMessage();
            RestContext.response.statusCode = 400;
        }

        return res;
    }

    // --- Helper methods ---

    private static Map<String, Object> getMap(Map<String, Object> source, String key) {
        Object val = source.get(key);
        if (val instanceof Map<String, Object>) {
            return (Map<String, Object>) val;
        }
        return null;
    }

    private static String getString(Map<String, Object> source, String key) {
        Object val = source.get(key);
        return val != null ? String.valueOf(val) : null;
    }

    private static Boolean getBool(Map<String, Object> source, String key) {
        Object val = source.get(key);
        if (val instanceof Boolean) {
            return (Boolean) val;
        }
        return false;
    }

    private static Boolean getBoolString(Map<String, Object> source, String key) {
        Object val = source.get(key);
        if (val instanceof Boolean) {
            return (Boolean) val;
        }
        if (val != null) {
            return String.valueOf(val).equalsIgnoreCase('true');
        }
        return false;
    }

    private static String serializeArray(Map<String, Object> source, String key) {
        Object val = source.get(key);
        if (val != null) {
            return JSON.serialize(val);
        }
        return null;
    }

    /**
     * Two-tier auto-matching: resolves Contact/Lead, Account, Opportunity, and Event_ID
     * from Salesforce Events before insert.
     *
     * Tier 1: Match Event by Location = meetingId
     * Tier 2: Find Contact by email, then most recent Event for that Contact;
     *         if no Contact found, try Lead by email
     *
     * All failures caught silently — record is always created.
     */
    private static void resolveRelatedRecords(AI_Call_Note__c note, String meetingId, String customerEmail) {
        try {
            Event matchedEvent = null;
            Id contactId = null;

            // --- Tier 1: match by meeting ID in Event.Location ---
            if (String.isNotBlank(meetingId)) {
                List<Event> events = [
                    SELECT Id, WhoId, WhatId
                    FROM Event
                    WHERE Location = :meetingId
                    LIMIT 1
                ];
                if (!events.isEmpty()) {
                    matchedEvent = events[0];
                }
            }

            // --- Tier 2: fall back to Contact email → most recent Event ---
            if (matchedEvent == null && String.isNotBlank(customerEmail)) {
                List<Contact> contacts = [
                    SELECT Id, AccountId
                    FROM Contact
                    WHERE Email = :customerEmail
                    LIMIT 1
                ];
                if (!contacts.isEmpty()) {
                    contactId = contacts[0].Id;
                    note.Contact__c = contactId;

                    List<Event> events = [
                        SELECT Id, WhoId, WhatId
                        FROM Event
                        WHERE WhoId = :contactId
                        ORDER BY ActivityDateTime DESC
                        LIMIT 1
                    ];
                    if (!events.isEmpty()) {
                        matchedEvent = events[0];
                    } else {
                        // No Event found — derive Account from Contact
                        note.Account__c = contacts[0].AccountId;
                    }
                }

                // No Contact found — try Lead by email
                if (contactId == null) {
                    List<Lead> leads = [
                        SELECT Id FROM Lead WHERE Email = :customerEmail LIMIT 1
                    ];
                    if (!leads.isEmpty()) {
                        note.Lead__c = leads[0].Id;
                        // Query most recent Event for this Lead
                        List<Event> events = [
                            SELECT Id, WhoId, WhatId FROM Event
                            WHERE WhoId = :leads[0].Id
                            ORDER BY ActivityDateTime DESC LIMIT 1
                        ];
                        if (!events.isEmpty()) {
                            matchedEvent = events[0];
                        }
                    }
                }
            }

            // --- Populate fields from matched Event ---
            if (matchedEvent != null) {
                note.Event_ID__c = matchedEvent.Id;
                populateFromEvent(note, matchedEvent);
            }

            // --- Final fallback: Account from Contact if still null ---
            if (note.Contact__c != null && note.Account__c == null) {
                List<Contact> contacts = [
                    SELECT AccountId
                    FROM Contact
                    WHERE Id = :note.Contact__c
                    LIMIT 1
                ];
                if (!contacts.isEmpty()) {
                    note.Account__c = contacts[0].AccountId;
                }
            }
        } catch (Exception e) {
            // Silently catch — record creation should never fail due to matching
        }
    }

    /**
     * Populates Contact, Account, and Opportunity from an Event's WhoId/WhatId.
     */
    private static void populateFromEvent(AI_Call_Note__c note, Event evt) {
        // WhoId → Contact (003) or Lead (00Q)
        if (evt.WhoId != null) {
            String whoPrefix = String.valueOf(evt.WhoId).substring(0, 3);
            if (whoPrefix == '003') {
                note.Contact__c = evt.WhoId;
            } else if (whoPrefix == '00Q') {
                note.Lead__c = evt.WhoId;
            }
        }

        // WhatId → Opportunity (006) or Account (001)
        if (evt.WhatId != null) {
            String whatPrefix = String.valueOf(evt.WhatId).substring(0, 3);
            if (whatPrefix == '006') {
                note.Opportunity__c = evt.WhatId;
                // Derive Account from Opportunity
                List<Opportunity> opps = [
                    SELECT AccountId
                    FROM Opportunity
                    WHERE Id = :evt.WhatId
                    LIMIT 1
                ];
                if (!opps.isEmpty()) {
                    note.Account__c = opps[0].AccountId;
                }
            } else if (whatPrefix == '001') {
                note.Account__c = evt.WhatId;
            }
        }
    }
}
