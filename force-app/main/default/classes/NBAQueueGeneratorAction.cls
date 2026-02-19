/**
 * @description Custom AI Agent action that generates NBA Queue recommendations.
 *              This action is called by the NBA_Orchestrator AI Agent to analyze
 *              opportunities and generate prioritized next best actions.
 *
 * @group NBA AI Integration
 * @date 2026-01-26
 */
public with sharing class NBAQueueGeneratorAction implements IAgentAction {

    /**
     * @description Execute the action - query records and format for AI analysis
     *              Supports Opportunities, Accounts, Contacts, and Leads
     *              Implements IAgentAction interface
     * @param actionConfigurationJson Configuration JSON (not used currently)
     * @param argumentsJson JSON containing parameters like limit, objectType, queryFields
     * @param context Execution context with user IDs and metadata
     * @return ActionOutcome with success/failure and record data
     */
    public ActionOutcome execute(String actionConfigurationJson, String argumentsJson, ActionContext context) {
        try {
            // Parse arguments if provided
            Map<String, Object> arguments = new Map<String, Object>();
            if (String.isNotBlank(argumentsJson)) {
                arguments = (Map<String, Object>)JSON.deserializeUntyped(argumentsJson);
            }

            // Get userId from context (prefer originalUserId, fallback to executionUserId)
            Id userId = context.originalUserId != null ? context.originalUserId : context.executionUserId;
            if (userId == null) {
                userId = UserInfo.getUserId();
            }

            // Get parameters from arguments
            Integer limitCount = arguments.containsKey('limit') ? Integer.valueOf(arguments.get('limit')) : 50;
            String objectType = arguments.containsKey('objectType') ? (String)arguments.get('objectType') : 'Opportunity';
            String queryFields = arguments.containsKey('queryFields') ? (String)arguments.get('queryFields') : null;
            String whereClause = arguments.containsKey('whereClause') ? (String)arguments.get('whereClause') : null;
            Boolean includeOwnershipFilter = arguments.containsKey('includeOwnershipFilter') ?
                                             (Boolean)arguments.get('includeOwnershipFilter') : true; // Default true for backward compatibility

            System.debug('NBAQueueGeneratorAction executing for user: ' + userId + ', limit: ' + limitCount + ', objectType: ' + objectType + ', includeOwnershipFilter: ' + includeOwnershipFilter + ', WHERE: ' + whereClause);

            // Query records based on objectType
            List<SObject> records = queryRecords(userId, limitCount, objectType, queryFields, whereClause, includeOwnershipFilter);
            List<Map<String, Object>> formattedRecords = formatRecordsForAI(records, objectType);

            // Build response for AI
            Map<String, Object> response = new Map<String, Object>{
                'timestamp' => System.now().format(),
                'userId' => userId,
                'executionId' => context.executionId,
                'objectType' => objectType,
                'recordCount' => records.size(),
                'opportunities' => formattedRecords, // Keep 'opportunities' key for backward compatibility
                'instructions' => buildInstructions(objectType)
            };

            System.debug('Generated NBA data for AI analysis with ' + records.size() + ' ' + objectType + ' records');

            // Return success with the data
            return ActionOutcome.success(response);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'NBAQueueGeneratorAction failed: ' + e.getMessage() + '\n' + e.getStackTraceString());

            // Return failure with guidance for the AI
            return ActionOutcome.failureWithGuidance(
                'QUERY_FAILED',
                'Failed to generate NBA recommendations: ' + e.getMessage(),
                'Please verify the user has access to the requested records and all required fields. Check that the user ID is valid and has records assigned.'
            );
        }
    }

    /**
     * @description Query records based on object type
     */
    private List<SObject> queryRecords(Id userId, Integer limitCount, String objectType, String queryFields, String whereClause, Boolean includeOwnershipFilter) {
        if (objectType == 'Account') {
            return queryAccounts(userId, limitCount, queryFields, whereClause, includeOwnershipFilter);
        } else if (objectType == 'Contact') {
            return queryContacts(userId, limitCount, queryFields, whereClause, includeOwnershipFilter);
        } else if (objectType == 'Lead') {
            return queryLeads(userId, limitCount, queryFields, whereClause, includeOwnershipFilter);
        } else {
            return queryOpportunities(userId, limitCount, queryFields, whereClause, includeOwnershipFilter);
        }
    }

    /**
     * @description Query opportunities for the user
     */
    private List<Opportunity> queryOpportunities(Id userId, Integer limitCount, String queryFields, String whereClause, Boolean includeOwnershipFilter) {
        String fields = String.isNotBlank(queryFields) ? queryFields :
            'Id, Name, Amount, StageName, CloseDate, CreatedDate, Account.Id, Account.Name, LastActivityDate, Description, Type, LeadSource, Probability, ExpectedRevenue, NextStep, IsClosed, IsWon, ForecastCategory';

        // Build WHERE clause with optional ownership filter
        String baseWhere = '';
        if (includeOwnershipFilter) {
            baseWhere = 'OwnerId = :userId AND ';
        }
        baseWhere += 'IsClosed = false AND Amount != null';

        // Append custom WHERE clause if provided
        if (String.isNotBlank(whereClause)) {
            baseWhere += ' AND (' + whereClause + ')';
        }

        String query = 'SELECT ' + fields + ' FROM Opportunity WHERE ' + baseWhere + ' ORDER BY CloseDate ASC, Amount DESC LIMIT :limitCount';
        System.debug('Executing query: ' + query);
        return Database.query(query);
    }

    /**
     * @description Query accounts (for Sale Blitz prospecting)
     */
    private List<Account> queryAccounts(Id userId, Integer limitCount, String queryFields, String whereClause, Boolean includeOwnershipFilter) {
        String fields = String.isNotBlank(queryFields) ? queryFields :
            'Id, Name, MRR_Potential__c, Sales_Blitz__c, Industry, NumberOfEmployees, Website, Phone, BillingCity, BillingState, CreatedDate, LastActivityDate, OwnerId, Owner.Name';

        // Build WHERE clause with optional ownership filter
        String baseWhere = '';
        if (includeOwnershipFilter) {
            baseWhere = 'OwnerId = :userId';
        }

        // Append custom WHERE clause if provided, otherwise use default for Sale Blitz
        if (String.isNotBlank(whereClause)) {
            if (String.isNotBlank(baseWhere)) {
                baseWhere += ' AND (' + whereClause + ')';
            } else {
                baseWhere = whereClause;
            }
        } else if (String.isBlank(baseWhere)) {
            // Default filter only if no ownership filter and no WHERE clause
            baseWhere = 'Sales_Blitz__c != null';
        }

        String query = 'SELECT ' + fields + ' FROM Account WHERE ' + baseWhere + ' ORDER BY MRR_Potential__c DESC NULLS LAST, CreatedDate DESC LIMIT :limitCount';
        System.debug('Executing query: ' + query);
        return Database.query(query);
    }

    /**
     * @description Query contacts for the user
     */
    private List<Contact> queryContacts(Id userId, Integer limitCount, String queryFields, String whereClause, Boolean includeOwnershipFilter) {
        String fields = String.isNotBlank(queryFields) ? queryFields :
            'Id, Name, Title, Email, Phone, MobilePhone, Account.Id, Account.Name, LastActivityDate, CreatedDate, LeadSource, OwnerId, Owner.Name';

        // Build WHERE clause with optional ownership filter
        String baseWhere = '';
        if (includeOwnershipFilter) {
            baseWhere = 'OwnerId = :userId';
        }

        // Append custom WHERE clause if provided
        if (String.isNotBlank(whereClause)) {
            if (String.isNotBlank(baseWhere)) {
                baseWhere += ' AND (' + whereClause + ')';
            } else {
                baseWhere = whereClause;
            }
        }

        // If no WHERE clause at all, query all contacts (use with caution)
        String whereString = String.isNotBlank(baseWhere) ? ' WHERE ' + baseWhere : '';
        String query = 'SELECT ' + fields + ' FROM Contact' + whereString + ' ORDER BY CreatedDate DESC LIMIT :limitCount';
        System.debug('Executing query: ' + query);
        return Database.query(query);
    }

    /**
     * @description Query leads for the user
     */
    private List<Lead> queryLeads(Id userId, Integer limitCount, String queryFields, String whereClause, Boolean includeOwnershipFilter) {
        String fields = String.isNotBlank(queryFields) ? queryFields :
            'Id, Name, Company, Title, Email, Phone, MobilePhone, Status, Rating, Industry, NumberOfEmployees, LeadSource, CreatedDate, LastActivityDate, OwnerId, Owner.Name';

        // Build WHERE clause with optional ownership filter
        String baseWhere = '';
        if (includeOwnershipFilter) {
            baseWhere = 'OwnerId = :userId AND ';
        }
        baseWhere += 'IsConverted = false';

        // Append custom WHERE clause if provided
        if (String.isNotBlank(whereClause)) {
            baseWhere += ' AND (' + whereClause + ')';
        }

        String query = 'SELECT ' + fields + ' FROM Lead WHERE ' + baseWhere + ' ORDER BY CreatedDate DESC, Rating DESC NULLS LAST LIMIT :limitCount';
        System.debug('Executing query: ' + query);
        return Database.query(query);
    }

    /**
     * @description Format records in a structure optimized for AI analysis
     */
    private List<Map<String, Object>> formatRecordsForAI(List<SObject> records, String objectType) {
        List<Map<String, Object>> formatted = new List<Map<String, Object>>();

        for (SObject record : records) {
            Map<String, Object> recordData = new Map<String, Object>();

            // Get all populated fields dynamically
            Map<String, Object> populatedFields = record.getPopulatedFieldsAsMap();
            for (String fieldName : populatedFields.keySet()) {
                Object fieldValue = populatedFields.get(fieldName);

                // Handle relationship fields
                if (fieldValue instanceof List<SObject>) {
                    // Handle subquery results (child relationships like Events, Tasks, etc.)
                    List<SObject> relatedRecords = (List<SObject>)fieldValue;
                    List<Map<String, Object>> relatedList = new List<Map<String, Object>>();
                    for (SObject relatedRecord : relatedRecords) {
                        // Create mutable map (getPopulatedFieldsAsMap returns read-only)
                        Map<String, Object> relatedData = new Map<String, Object>(relatedRecord.getPopulatedFieldsAsMap());

                        // Add calculated timing fields for Events
                        if (relatedRecord.getSObjectType() == Event.SObjectType) {
                            DateTime startDT = (DateTime)relatedRecord.get('StartDateTime');
                            if (startDT != null) {
                                Integer daysUntilEvent = Date.today().daysBetween(startDT.date());
                                relatedData.put('daysUntilEvent', daysUntilEvent);
                            }
                        }

                        relatedList.add(relatedData);
                    }
                    recordData.put(fieldName, relatedList);
                } else if (fieldValue instanceof SObject) {
                    // Handle parent relationships (like Account, Owner, etc.)
                    SObject relatedRecord = (SObject)fieldValue;
                    Map<String, Object> relatedFields = relatedRecord.getPopulatedFieldsAsMap();
                    recordData.put(fieldName, relatedFields);
                } else if (fieldValue instanceof Date) {
                    recordData.put(fieldName, ((Date)fieldValue).format());
                } else if (fieldValue instanceof DateTime) {
                    recordData.put(fieldName, ((DateTime)fieldValue).format());
                } else {
                    recordData.put(fieldName, fieldValue);
                }
            }

            // Add calculated fields based on object type
            if (objectType == 'Opportunity') {
                Opportunity opp = (Opportunity)record;
                recordData.put('daysUntilClose', calculateDaysUntilClose(opp.CloseDate));
                recordData.put('daysSinceLastActivity', calculateDaysSince(opp.LastActivityDate));
            } else if (objectType == 'Account') {
                Account acc = (Account)record;
                recordData.put('daysSinceLastActivity', calculateDaysSince(acc.LastActivityDate));
                recordData.put('daysSinceCreated', calculateDaysSince(acc.CreatedDate));
            } else if (objectType == 'Contact' || objectType == 'Lead') {
                SObject rec = record;
                Date lastActivity = (Date)rec.get('LastActivityDate');
                Date created = (Date)rec.get('CreatedDate');
                recordData.put('daysSinceLastActivity', calculateDaysSince(lastActivity));
                recordData.put('daysSinceCreated', calculateDaysSince(created));
            }

            formatted.add(recordData);
        }

        return formatted;
    }

    /**
     * @description Calculate days until close date
     */
    private Integer calculateDaysUntilClose(Date closeDate) {
        if (closeDate == null) return 999;
        return Date.today().daysBetween(closeDate);
    }

    /**
     * @description Calculate days since last activity (Date version)
     */
    private Integer calculateDaysSince(Date activityDate) {
        if (activityDate == null) return 999;
        return activityDate.daysBetween(Date.today());
    }

    /**
     * @description Calculate days since last activity (DateTime version)
     */
    private Integer calculateDaysSince(DateTime activityDateTime) {
        if (activityDateTime == null) return 999;
        return activityDateTime.date().daysBetween(Date.today());
    }

    /**
     * @description Build instructions for the AI agent based on object type
     */
    private String buildInstructions(String objectType) {
        if (objectType == 'Account') {
            return 'Analyze the provided accounts and generate the top 10 prospecting recommendations. ' +
                   'For each recommendation, provide: ' +
                   '1) priority score (1-100), ' +
                   '2) recommended action (specific and actionable with contact details), ' +
                   '3) plain language explanation (2-3 sentences) of WHY this account is a priority NOW. ' +
                   'Consider factors like: MRR_Potential__c, Sales_Blitz__c status, days since created, contact availability. ' +
                   'Return ONLY valid JSON in this exact format: ' +
                   '[{"opportunityId": "...", "priority": 95, "score": 95.5, "recommendedAction": "Call John Smith at 555-1234", ' +
                   '"explanation": "High-value account with $15K MRR potential marked as Hot in Sales Blitz. ' +
                   'Decision maker identified. Immediate outreach capitalizes on high intent."}]';
        } else if (objectType == 'Contact') {
            return 'Analyze the provided contacts and generate the top 10 outreach recommendations. ' +
                   'For each recommendation, provide: ' +
                   '1) priority score (1-100), ' +
                   '2) recommended action (specific outreach strategy), ' +
                   '3) plain language explanation (2-3 sentences) of WHY to contact them NOW. ' +
                   'Consider factors like: title/role, account relationship, days since last activity. ' +
                   'Return ONLY valid JSON.';
        } else if (objectType == 'Lead') {
            return 'Analyze the provided leads and generate the top 10 follow-up recommendations. ' +
                   'For each recommendation, provide: ' +
                   '1) priority score (1-100), ' +
                   '2) recommended action (specific next step), ' +
                   '3) plain language explanation (2-3 sentences) of WHY this lead needs attention NOW. ' +
                   'Consider factors like: lead status, rating, days since created, industry fit. ' +
                   'Return ONLY valid JSON.';
        } else {
            return 'Analyze the provided opportunities and generate the top 10 recommendations. ' +
                   'For each recommendation, provide: ' +
                   '1) priority score (1-100), ' +
                   '2) recommended action (specific and actionable), ' +
                   '3) plain language explanation (2-3 sentences) of WHY this is important NOW. ' +
                   'Consider factors like: deal size, stage, days until close, days since last activity. ' +
                   'Return ONLY valid JSON in this exact format: ' +
                   '[{"opportunityId": "...", "priority": 95, "score": 95.5, "recommendedAction": "Schedule demo call", ' +
                   '"explanation": "This $100k deal closes in 7 days but hasn\'t been touched in 5 days. ' +
                   'Immediate action needed to keep momentum."}]';
        }
    }

    /**
     * @description Custom exception for NBA actions
     */
    public class NBAActionException extends Exception {}
}