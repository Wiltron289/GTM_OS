/**
 * @description NBASchema - Single source of truth for all NBA system object and field API names.
 *              ALL Apex code must use these constants instead of hardcoded strings.
 *              This class is generated from the schema alignment document (docs/schema-alignment.md).
 *
 * @group NBA Infrastructure
 * @date 2026-01-23
 */
public with sharing class NBASchema {

    // ========== NBA_QUEUE OBJECT ==========

    public static final String NBA_QUEUE_OBJECT = 'NBA_Queue__c';

    // Standard fields
    public static final String NBA_QUEUE_ID = 'Id';
    public static final String NBA_QUEUE_NAME = 'Name';
    public static final String NBA_QUEUE_OWNER_ID = 'OwnerId';
    public static final String NBA_QUEUE_CREATED_DATE = 'CreatedDate';
    public static final String NBA_QUEUE_CREATED_BY_ID = 'CreatedById';
    public static final String NBA_QUEUE_LAST_MODIFIED_DATE = 'LastModifiedDate';
    public static final String NBA_QUEUE_LAST_MODIFIED_BY_ID = 'LastModifiedById';

    // NBA Core fields
    public static final String NBA_QUEUE_ASSIGNEE = 'Assignee__c';              // Lookup(User) - NEW FIELD TO ADD
    public static final String NBA_QUEUE_STATUS = 'Status__c';                  // Picklist - EXISTS, need to extend values
    public static final String NBA_QUEUE_PRIORITY_BAND = 'PriorityBand__c';     // Picklist(P1-P4) - NEW FIELD TO ADD
    public static final String NBA_QUEUE_WORKSTREAM = 'Workstream__c';          // Picklist(Events/Cadence/Motion/Prospecting) - NEW FIELD TO ADD
    public static final String NBA_QUEUE_TARGET_OBJECT = 'TargetObject__c';     // Text(255) - NEW FIELD TO ADD
    public static final String NBA_QUEUE_TARGET_RECORD_ID = 'TargetRecordId__c'; // Text(18) - NEW FIELD TO ADD
    public static final String NBA_QUEUE_UNIQUE_KEY = 'UniqueKey__c';           // Text(255), Unique, External ID - NEW FIELD TO ADD
    public static final String NBA_QUEUE_DUE_AT = 'DueAt__c';                   // Datetime - NEW FIELD TO ADD
    public static final String NBA_QUEUE_WITHIN_BAND_SCORE = 'WithinBandScore__c'; // Number(10,2) - NEW FIELD TO ADD
    public static final String NBA_QUEUE_REASON_TEXT = 'ReasonText__c';         // Long Text - NEW FIELD TO ADD
    public static final String NBA_QUEUE_REASON_JSON = 'ReasonJson__c';         // Long Text - NEW FIELD TO ADD
    public static final String NBA_QUEUE_ELIGIBILITY_FINGERPRINT = 'EligibilityFingerprint__c'; // Text(255) - NEW FIELD TO ADD
    public static final String NBA_QUEUE_SNOOZE_UNTIL = 'Snoozed_Until__c';     // Datetime - EXISTS (mapped to existing field)
    public static final String NBA_QUEUE_SNOOZE_REASON = 'Snooze_Reason__c';    // Long Text - NEW FIELD TO ADD
    public static final String NBA_QUEUE_CONFIGURATION = 'Configuration__c';    // Text(255) - AI Configuration name (e.g., Default, Sale Blitz)
    public static final String NBA_QUEUE_COOLDOWN_UNTIL = 'CooldownUntil__c';   // Datetime - NEW FIELD TO ADD
    public static final String NBA_QUEUE_LAST_EVALUATED_AT = 'LastEvaluatedAt__c'; // Datetime - NEW FIELD TO ADD
    public static final String NBA_QUEUE_FOCUS_UNTIL = 'FocusUntil__c';         // Datetime (optional) - NEW FIELD TO ADD

    // Legacy/Business fields (for context, not to be used by NBA core logic)
    public static final String NBA_QUEUE_SALES_REP = 'Sales_Rep__c';            // Legacy - DO NOT USE in NBA logic
    public static final String NBA_QUEUE_OPP_OWNER = 'Opp_Owner__c';            // Legacy - DO NOT USE in NBA logic
    public static final String NBA_QUEUE_DUE_DATE_LEGACY = 'Due_Date__c';       // Legacy Date (no time) - DO NOT USE
    public static final String NBA_QUEUE_MODEL_REASON_LEGACY = 'Model_Reason__c'; // Legacy - keeping for compatibility
    public static final String NBA_QUEUE_ACTION_CONTEXT_LEGACY = 'Action_Context__c'; // Legacy - keeping for compatibility

    // Existing fields that may be useful for reports/context
    public static final String NBA_QUEUE_OPPORTUNITY = 'Opportunity__c';        // Lookup(Opportunity) - EXISTS
    public static final String NBA_QUEUE_ACCOUNT = 'Account__c';                // Lookup(Account) - EXISTS
    public static final String NBA_QUEUE_ACTION_TYPE = 'Action_Type__c';        // Picklist - EXISTS
    public static final String NBA_QUEUE_SUBJECT = 'Subject__c';                // Text - EXISTS
    public static final String NBA_QUEUE_DESCRIPTION = 'Description__c';        // Long Text - EXISTS
    public static final String NBA_QUEUE_COMPLETED_DATE = 'Completed_Date__c';  // Datetime - EXISTS
    public static final String NBA_QUEUE_FIRST_VIEWED_DATE = 'First_Viewed_Date__c'; // Datetime - EXISTS
    public static final String NBA_QUEUE_LAST_VIEWED_DATE = 'Last_Viewed_Date__c';  // Datetime - EXISTS

    // ========== NBA_QUEUE STATUS VALUES ==========

    public static final String NBA_STATUS_NEW = 'New';                 // NEW VALUE TO ADD
    public static final String NBA_STATUS_IN_PROGRESS = 'In Progress'; // EXISTS
    public static final String NBA_STATUS_SNOOZED = 'Snoozed';         // EXISTS
    public static final String NBA_STATUS_DISMISSED = 'Dismissed';     // EXISTS
    public static final String NBA_STATUS_COMPLETED = 'Completed';     // NEW VALUE TO ADD
    public static final String NBA_STATUS_EXPIRED = 'Expired';         // NEW VALUE TO ADD

    // Legacy status values (may want to map or deprecate)
    public static final String NBA_STATUS_PENDING = 'Pending';         // EXISTS - consider mapping to NEW
    public static final String NBA_STATUS_ACCEPTED = 'Accepted';       // EXISTS - consider mapping to IN_PROGRESS
    public static final String NBA_STATUS_ARCHIVE = 'Archive';         // EXISTS - keeping for compatibility

    // ========== NBA_QUEUE PRIORITY BANDS ==========

    public static final String PRIORITY_BAND_P1 = 'P1';  // Events - action needed within 15 minutes
    public static final String PRIORITY_BAND_P2 = 'P2';  // Cadence - next step in active sequence
    public static final String PRIORITY_BAND_P3 = 'P3';  // Motion - proactive outreach on opportunities
    public static final String PRIORITY_BAND_P4 = 'P4';  // Prospecting - backfill for idle time

    // ========== NBA_QUEUE WORKSTREAMS ==========

    public static final String WORKSTREAM_EVENTS = 'Events';
    public static final String WORKSTREAM_CADENCE = 'Cadence';
    public static final String WORKSTREAM_MOTION = 'Motion';
    public static final String WORKSTREAM_PROSPECTING = 'Prospecting';

    // ========== OPPORTUNITY OBJECT ==========

    public static final String OPPORTUNITY_OBJECT = 'Opportunity';
    public static final String OPP_ID = 'Id';
    public static final String OPP_NAME = 'Name';
    public static final String OPP_OWNER_ID = 'OwnerId';
    public static final String OPP_STAGE_NAME = 'StageName';
    public static final String OPP_CREATED_DATE = 'CreatedDate';
    public static final String OPP_LAST_CALL_DATE_TIME = 'Last_Call_Date_Time__c';  // EXISTS
    public static final String OPP_LAST_CALL_OUTCOME = 'Last_Call_Outcome__c';      // EXISTS
    public static final String OPP_ACCOUNT_ID = 'AccountId';

    // ========== ACCOUNT OBJECT ==========

    public static final String ACCOUNT_OBJECT = 'Account';
    public static final String ACCOUNT_ID = 'Id';
    public static final String ACCOUNT_NAME = 'Name';
    public static final String ACCOUNT_OWNER_ID = 'OwnerId';
    public static final String ACCOUNT_CREATED_DATE = 'CreatedDate';

    // Priority Scoring field - NEW field to add for NBA prospecting prioritization
    public static final String ACCOUNT_PRIORITY_SCORE = 'Priority_Score__c';  // NEW FIELD TO ADD - Primary prospecting priority indicator

    // Legacy MRR fields (for reference/context, not to be used by NBA core logic)
    public static final String ACCOUNT_MRR = 'Account_MRR__c';                // EXISTS - Business MRR field
    public static final String ACCOUNT_FORECAST_MRR = 'Forecast_MRR__c';      // EXISTS - Business forecast MRR
    public static final String ACCOUNT_CURRENT_PAYROLL_MRR = 'Current_Payroll_MRR__c'; // EXISTS - Payroll-specific MRR

    // Account "unowned" indicators
    public static final String ACCOUNT_OWNER_IS_SALES = 'Account_Owner_is_Sales__c'; // EXISTS - Boolean indicator

    // ========== EVENT OBJECT ==========

    public static final String EVENT_OBJECT = 'Event';
    public static final String EVENT_ID = 'Id';
    public static final String EVENT_OWNER_ID = 'OwnerId';
    public static final String EVENT_SUBJECT = 'Subject';
    public static final String EVENT_START_DATETIME = 'StartDateTime';
    public static final String EVENT_END_DATETIME = 'EndDateTime';
    public static final String EVENT_WHO_ID = 'WhoId';
    public static final String EVENT_WHAT_ID = 'WhatId';

    // ========== PROSPECTING_RESERVATION OBJECT ==========

    public static final String PROSPECTING_RESERVATION_OBJECT = 'Prospecting_Reservation__c'; // NEW OBJECT TO CREATE
    public static final String PROSP_RES_ID = 'Id';
    public static final String PROSP_RES_NAME = 'Name';
    public static final String PROSP_RES_ACCOUNT = 'Account__c';              // Lookup(Account), Unique - NEW FIELD TO ADD
    public static final String PROSP_RES_RESERVED_FOR = 'ReservedFor__c';     // Lookup(User) - NEW FIELD TO ADD
    public static final String PROSP_RES_RESERVED_UNTIL = 'ReservedUntil__c'; // Datetime - NEW FIELD TO ADD
    public static final String PROSP_RES_MRR_POTENTIAL = 'MRRPotentialSnapshot__c'; // Number(10,2) - NEW FIELD TO ADD
    public static final String PROSP_RES_CREATED_REASON = 'CreatedReason__c'; // Long Text - NEW FIELD TO ADD
    public static final String PROSP_RES_LAST_TOUCHED_AT = 'LastTouchedAt__c'; // Datetime - NEW FIELD TO ADD

    // ========== USER OBJECT ==========

    public static final String USER_OBJECT = 'User';
    public static final String USER_ID = 'Id';
    public static final String USER_NAME = 'Name';
    public static final String USER_IS_ACTIVE = 'IsActive';

    // ========== VALIDATION & UTILITY ==========

    /**
     * @description Asserts that a required field mapping is not UNMAPPED. Throws a clear exception if unmapped.
     * @param fieldApiName The field API name constant
     * @param conceptName Human-readable name of the concept being mapped
     * @throws NBASchemaException if the field is UNMAPPED
     */
    public static void assertMapped(String fieldApiName, String conceptName) {
        if (String.isBlank(fieldApiName) || fieldApiName == 'UNMAPPED__c' || fieldApiName.contains('UNMAPPED')) {
            throw new NBASchemaException('CRITICAL: Field mapping for "' + conceptName + '" is UNMAPPED. Cannot proceed. Check schema-alignment.md and update NBASchema.cls.');
        }
    }

    /**
     * @description Validates all required NBA Queue field mappings are present. Call this in tests or startup.
     * @throws NBASchemaException if any required mapping is missing
     */
    public static void validateNBAQueueSchema() {
        assertMapped(NBA_QUEUE_ASSIGNEE, 'NBA Queue Assignee');
        assertMapped(NBA_QUEUE_STATUS, 'NBA Queue Status');
        assertMapped(NBA_QUEUE_PRIORITY_BAND, 'NBA Queue Priority Band');
        assertMapped(NBA_QUEUE_WORKSTREAM, 'NBA Queue Workstream');
        assertMapped(NBA_QUEUE_TARGET_OBJECT, 'NBA Queue Target Object');
        assertMapped(NBA_QUEUE_TARGET_RECORD_ID, 'NBA Queue Target Record ID');
        assertMapped(NBA_QUEUE_UNIQUE_KEY, 'NBA Queue Unique Key');
        assertMapped(NBA_QUEUE_DUE_AT, 'NBA Queue Due At');
        assertMapped(NBA_QUEUE_WITHIN_BAND_SCORE, 'NBA Queue Within Band Score');
        assertMapped(NBA_QUEUE_REASON_TEXT, 'NBA Queue Reason Text');
        assertMapped(NBA_QUEUE_REASON_JSON, 'NBA Queue Reason JSON');
        assertMapped(NBA_QUEUE_ELIGIBILITY_FINGERPRINT, 'NBA Queue Eligibility Fingerprint');
        assertMapped(NBA_QUEUE_SNOOZE_UNTIL, 'NBA Queue Snooze Until');
        assertMapped(NBA_QUEUE_COOLDOWN_UNTIL, 'NBA Queue Cooldown Until');
        assertMapped(NBA_QUEUE_LAST_EVALUATED_AT, 'NBA Queue Last Evaluated At');
        // FocusUntil is optional, so we don't assert it
    }

    /**
     * @description Builds a qualified field reference for SOQL (e.g., NBA_Queue__c.Assignee__c)
     * @param objectApiName The object API name
     * @param fieldApiName The field API name
     * @return Qualified field reference string
     */
    public static String qualifiedField(String objectApiName, String fieldApiName) {
        return objectApiName + '.' + fieldApiName;
    }

    /**
     * @description Generates a UniqueKey for NBA upsert operations
     * @param workstream The workstream (Events, Cadence, Motion, Prospecting)
     * @param targetRecordId The target record ID (18-char)
     * @param assigneeId The assignee user ID (18-char)
     * @return Unique key string in format: workstream|targetRecordId|assigneeId
     */
    public static String generateUniqueKey(String workstream, String targetRecordId, String assigneeId) {
        if (String.isBlank(workstream) || String.isBlank(targetRecordId) || String.isBlank(assigneeId)) {
            throw new NBASchemaException('Cannot generate UniqueKey: workstream, targetRecordId, and assigneeId are all required.');
        }
        return workstream + '|' + targetRecordId + '|' + assigneeId;
    }

    /**
     * @description Custom exception for NBA schema-related errors
     */
    public class NBASchemaException extends Exception {}
}