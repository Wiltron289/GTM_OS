/**
 * @description Read-only selector class for NBA Queue related SOQL queries
 * Contains all SOQL queries extracted from NBAQueueManager for better organization and testability
 */
public with sharing class NBAQueueSelector {
    
    // =========================
    // NBA_Queue__c Queries
    // =========================
    
    /**
     * @description Get NBA Queue item by ID with basic fields
     */
    public static NBA_Queue__c getQueueItemById(Id queueItemId) {
        return [SELECT Id, Opportunity__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
    }
    
    /**
     * @description Get NBA Queue item by ID with status fields
     */
    public static NBA_Queue__c getQueueItemWithStatus(Id queueItemId) {
        return [SELECT Id, Status__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
    }
    
    /**
     * @description Get NBA Queue item by ID with dismissal fields
     */
    public static NBA_Queue__c getQueueItemForDismissal(Id queueItemId) {
        return [SELECT Id, Description__c, Sales_Rep__c FROM NBA_Queue__c WHERE Id = :queueItemId];
    }
    
    /**
     * @description Get NBA Queue item by ID with cancellation fields
     */
    public static NBA_Queue__c getQueueItemForCancellation(Id queueItemId) {
        return [SELECT Id, Status__c, Sales_Rep__c, Completed_Date__c, Actioned_Date__c FROM NBA_Queue__c WHERE Id = :queueItemId];
    }
    
    /**
     * @description Get NBA Queue item by ID with first viewed date
     */
    public static NBA_Queue__c getQueueItemWithFirstViewed(Id queueItemId) {
        return [SELECT Id, First_Viewed_Date__c FROM NBA_Queue__c WHERE Id = :queueItemId];
    }
    
    /**
     * @description Get NBA Queue item by ID with last viewed date
     */
    public static NBA_Queue__c getQueueItemWithLastViewed(Id queueItemId) {
        return [SELECT Id, Last_Viewed_Date__c FROM NBA_Queue__c WHERE Id = :queueItemId];
    }
    
    /**
     * @description Get NBA Queue item by ID with best person to call
     */
    public static NBA_Queue__c getQueueItemWithBestPerson(Id queueItemId) {
        return [SELECT Id, Best_Person_to_Call__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
    }
    
    
    /**
     * @description Get NBA Queue item by ID with next steps fields
     */
    public static NBA_Queue__c getQueueItemForNextSteps(Id queueItemId) {
        return [SELECT Id, Opportunity__c, Lead__c FROM NBA_Queue__c WHERE Id = :queueItemId];
    }
    
    /**
     * @description Get NBA Queue item by ID with email acceptance fields
     */
    public static NBA_Queue__c getQueueItemForEmailAcceptance(Id queueItemId) {
        return [SELECT Id, Opportunity__c, Email_Message_Id__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
    }
    
    /**
     * @description Get NBA Queue item by ID with event acceptance fields
     */
    public static NBA_Queue__c getQueueItemForEventAcceptance(Id queueItemId) {
        return [SELECT Id, Opportunity__c, Start_Time__c, Event_Id__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
    }
    
    /**
     * @description Get NBA Queue item by ID with meeting notes fields
     */
    public static NBA_Queue__c getQueueItemForMeetingNotes(Id queueItemId) {
        return [SELECT Id, Rep_Notes__c, Opportunity__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
    }
    
    /**
     * @description Get NBA Queue item by ID with status update fields
     */
    public static NBA_Queue__c getQueueItemForStatusUpdate(Id queueItemId) {
        return [SELECT Id, Status__c FROM NBA_Queue__c WHERE Id = :queueItemId LIMIT 1];
    }
    
    /**
     * @description Get NBA Queue item by ID with all fields needed for acceptAction
     */
    public static NBA_Queue__c getQueueItemForAcceptAction(Id queueItemId) {
        return [SELECT Id, Account__c, Account__r.Payroll_Status__c, Account__r.Last_Web_Usage_Timestamp__c,
                       Subject__c, Description__c, Due_Date__c, Action_Type__c,
                       Priority_Score__c, Sales_Rep__c, Opportunity__c, Lead__c, Best_Time_to_Call__c, Best_Number_to_Call__c, Person_Called__c, Number_Dialed__c
                FROM NBA_Queue__c 
                WHERE Id = :queueItemId];
    }
    
    // =========================
    // Opportunity Queries
    // =========================
    
    /**
     * @description Get Opportunity by Account ID with owner
     */
    public static List<Opportunity> getOpportunitiesByAccountId(Id accountId) {
        return [SELECT Id, OwnerId FROM Opportunity WHERE AccountId = :accountId LIMIT 1];
    }
    
    /**
     * @description Get Opportunity by ID with stage
     */
    public static Opportunity getOpportunityWithStage(Id opportunityId) {
        return [SELECT Id, StageName FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
    }
    
    /**
     * @description Get Opportunity by ID with account ID
     */
    public static Opportunity getOpportunityWithAccountId(Id opportunityId) {
        return [SELECT AccountId FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
    }
    
    /**
     * @description Get Opportunity by ID with call time fields
     */
    public static Opportunity getOpportunityWithCallTimes(Id opportunityId) {
        return [SELECT Id, First_Call_Date_Time__c FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
    }
    
    /**
     * @description Get Opportunity by ID with primary contact phone
     */
    public static Opportunity getOpportunityWithPrimaryContactPhone(Id opportunityId) {
        return [SELECT Primary_Contact__r.Phone, Primary_Contact__r.MobilePhone FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
    }
    
    /**
     * @description Get Opportunity by ID with description and call times
     */
    public static Opportunity getOpportunityWithDescriptionAndCallTimes(Id opportunityId) {
        return [SELECT Id, Description, First_Call_Date_Time__c, Last_Call_Date_Time__c FROM Opportunity WHERE Id = :opportunityId];
    }
    
    /**
     * @description Get Opportunity by ID with next step fields
     */
    public static Opportunity getOpportunityWithNextStep(Id opportunityId) {
        return [SELECT Id, NextStep, StageName FROM Opportunity WHERE Id = :opportunityId];
    }
    
    /**
     * @description Get Opportunity by ID with description only
     */
    public static Opportunity getOpportunityWithDescription(Id opportunityId) {
        return [SELECT Id, Description FROM Opportunity WHERE Id = :opportunityId LIMIT 1];
    }
    
    // =========================
    // Account Queries
    // =========================
    
    /**
     * @description Get Accounts by IDs with owner
     */
    public static List<Account> getAccountsWithOwner(List<Id> accountIds) {
        return [SELECT Id, OwnerId FROM Account WHERE Id IN :accountIds];
    }
    
    /**
     * @description Get Account by ID with phone
     */
    public static Account getAccountWithPhone(Id accountId) {
        return [SELECT Id, Phone FROM Account WHERE Id = :accountId LIMIT 1];
    }
    
    /**
     * @description Get Account by ID with primary contact phone
     */
    public static Account getAccountWithPrimaryContactPhone(Id accountId) {
        return [SELECT Primary_Contact__r.Phone, Primary_Contact__r.MobilePhone, Phone FROM Account WHERE Id = :accountId LIMIT 1];
    }
    
    // =========================
    // Lead Queries
    // =========================
    
    /**
     * @description Get Lead by ID with phone fields
     */
    public static Lead getLeadWithPhone(Id leadId) {
        return [SELECT Phone, MobilePhone FROM Lead WHERE Id = :leadId LIMIT 1];
    }
    
    /**
     * @description Get Lead by ID with description
     */
    public static Lead getLeadWithDescription(Id leadId) {
        return [SELECT Id, Description FROM Lead WHERE Id = :leadId LIMIT 1];
    }
    
    /**
     * @description Get Lead by ID with status
     */
    public static Lead getLeadWithStatus(Id leadId) {
        return [SELECT Id, Status FROM Lead WHERE Id = :leadId LIMIT 1];
    }
    
    // =========================
    // Contact Queries
    // =========================
    
    /**
     * @description Get Contacts by Account ID
     */
    public static List<Contact> getContactsByAccountId(Id accountId) {
        return [SELECT Id FROM Contact WHERE AccountId = :accountId LIMIT 500];
    }
    
    // =========================
    // OpportunityContactRole Queries
    // =========================
    
    /**
     * @description Get Opportunity Contact Roles by Opportunity ID
     */
    public static List<OpportunityContactRole> getOpportunityContactRoles(Id opportunityId) {
        return [SELECT ContactId FROM OpportunityContactRole WHERE OpportunityId = :opportunityId AND ContactId != null LIMIT 200];
    }
    
    // =========================
    // Task Queries
    // =========================
    
    /**
     * @description Get Task by ID with call disposition fields
     */
    public static Task getTaskWithCallDisposition(Id taskId) {
        return [SELECT Id, Description, CallDisposition FROM Task WHERE Id = :taskId];
    }
    
    /**
     * @description Get upcoming Tasks (not completed, due today or future) for multiple records
     */
    public static List<Task> getUpcomingTasks(List<Id> whatIds, List<Id> whoIds, Date today) {
        return [SELECT Id, Subject, ActivityDate, Status
                FROM Task
                WHERE ((WhatId IN :whatIds) OR (WhoId IN :whoIds))
                AND Status != 'Completed'
                AND ActivityDate >= :today
                ORDER BY ActivityDate ASC
                LIMIT 300];
    }
    
    /**
     * @description Get past Tasks within last 90 days for multiple records
     */
    public static List<Task> getPastTasks(List<Id> whatIds, List<Id> whoIds, Date ninetyDaysAgo) {
        return [SELECT Id, Subject, ActivityDate, Status
                FROM Task
                WHERE ((WhatId IN :whatIds) OR (WhoId IN :whoIds))
                AND ActivityDate >= :ninetyDaysAgo
                AND ActivityDate < TODAY
                ORDER BY ActivityDate DESC
                LIMIT 300];
    }
    
    // =========================
    // Event Queries
    // =========================
    
    /**
     * @description Get upcoming Events for multiple records
     */
    public static List<Event> getUpcomingEvents(List<Id> whatIds, List<Id> whoIds, Datetime now) {
        return [SELECT Id, Subject, StartDateTime, EndDateTime
                FROM Event
                WHERE ((WhatId IN :whatIds) OR (WhoId IN :whoIds))
                AND StartDateTime >= :now
                ORDER BY StartDateTime ASC
                LIMIT 300];
    }
    
    /**
     * @description Get past Events within last 90 days for multiple records
     */
    public static List<Event> getPastEvents(List<Id> whatIds, List<Id> whoIds, Datetime ninetyDaysAgo) {
        Datetime now = Datetime.now();
        return [SELECT Id, Subject, StartDateTime, EndDateTime
                FROM Event
                WHERE ((WhatId IN :whatIds) OR (WhoId IN :whoIds))
                AND StartDateTime >= :ninetyDaysAgo
                AND StartDateTime < :now
                ORDER BY StartDateTime DESC
                LIMIT 300];
    }
    
    // =========================
    // NBA_Queue__c List Queries
    // =========================

    /**
     * @description Get active NBA Queue items assigned to a user, ordered by priority
     * @param assigneeId The user ID to filter by
     * @param limitCount Maximum number of records to return
     * @return List of NBA_Queue__c records
     */
    public static List<NBA_Queue__c> getByAssignee(Id assigneeId, Integer limitCount) {
        return [SELECT Id, Assignee__c, PriorityBand__c, Workstream__c,
                       TargetObject__c, TargetRecordId__c, DueAt__c,
                       WithinBandScore__c, ReasonText__c, ReasonJson__c,
                       Status__c, UniqueKey__c, FocusUntil__c
                FROM NBA_Queue__c
                WHERE Assignee__c = :assigneeId
                AND Status__c IN ('New', 'In Progress')
                ORDER BY PriorityBand__c ASC, WithinBandScore__c DESC
                LIMIT :limitCount];
    }

    /**
     * @description Get NBA Queue items by target record
     * @param targetObjectType The object API name (e.g., 'Opportunity')
     * @param recordId The target record ID
     * @return List of NBA_Queue__c records
     */
    public static List<NBA_Queue__c> getByTargetRecord(String targetObjectType, Id recordId) {
        String recordIdStr = String.valueOf(recordId);
        return [SELECT Id, Assignee__c, PriorityBand__c, Workstream__c,
                       TargetObject__c, TargetRecordId__c, DueAt__c,
                       WithinBandScore__c, ReasonText__c, ReasonJson__c,
                       Status__c, UniqueKey__c, FocusUntil__c
                FROM NBA_Queue__c
                WHERE TargetObject__c = :targetObjectType
                AND TargetRecordId__c = :recordIdStr
                AND Status__c IN ('New', 'In Progress')
                ORDER BY PriorityBand__c ASC, WithinBandScore__c DESC];
    }

    /**
     * @description Get NBA Queue items by unique keys
     * @param uniqueKeys Set of unique key values
     * @return List of NBA_Queue__c records
     */
    public static List<NBA_Queue__c> getByUniqueKeys(Set<String> uniqueKeys) {
        return [SELECT Id, Assignee__c, PriorityBand__c, Workstream__c,
                       TargetObject__c, TargetRecordId__c, DueAt__c,
                       WithinBandScore__c, ReasonText__c, ReasonJson__c,
                       Status__c, UniqueKey__c, FocusUntil__c
                FROM NBA_Queue__c
                WHERE UniqueKey__c IN :uniqueKeys];
    }

    /**
     * @description Get count of active NBA Queue items grouped by workstream for a user
     * @param assigneeId The user ID
     * @return Map of workstream name to count
     */
    public static Map<String, Integer> getActiveCountByWorkstream(Id assigneeId) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (AggregateResult ar : [SELECT Workstream__c ws, COUNT(Id) cnt
                                   FROM NBA_Queue__c
                                   WHERE Assignee__c = :assigneeId
                                   AND Status__c IN ('New', 'In Progress')
                                   GROUP BY Workstream__c]) {
            String ws = (String) ar.get('ws');
            Integer cnt = (Integer) ar.get('cnt');
            if (ws != null) {
                counts.put(ws, cnt);
            }
        }
        return counts;
    }

    // =========================
    // Complex NBA_Queue__c Queries
    // =========================
    
    /**
     * @description Get NBA Queue item with all fields needed for task creation
     */
    public static NBA_Queue__c getQueueItemForTaskCreation(Id queueItemId) {
        return [SELECT Id, Account__c, Account__r.Payroll_Status__c, Account__r.Last_Web_Usage_Timestamp__c,
                       Subject__c, Description__c, Due_Date__c, Action_Type__c,
                       Priority_Score__c, Sales_Rep__c, Opportunity__c, Lead__c, Best_Time_to_Call__c, Best_Number_to_Call__c, Person_Called__c, Number_Dialed__c
                FROM NBA_Queue__c 
                WHERE Id = :queueItemId];
    }
    
    /**
     * @description Get NBA Queue item with all fields needed for queue item update
     */
    public static NBA_Queue__c getQueueItemForUpdate(Id queueItemId) {
        return [SELECT Id, Rep_Notes__c, Call_Disposition__c, Status__c, Completed_Date__c, Opportunity__c, Lead__c,
                       Priority_Score__c, Account__c, Account__r.Payroll_Status__c, Account__r.Last_Web_Usage_Timestamp__c, Account__r.Last_Progression_Time__c, 
                       Subject__c, Description__c, Due_Date__c, Action_Type__c, Sales_Rep__c, Best_Time_to_Call__c, Best_Number_to_Call__c, Person_Called__c, Number_Dialed__c,
                       Next_Step_Date__c, Next_Steps__c
                FROM NBA_Queue__c 
                WHERE Id = :queueItemId];
    }
    
    
}