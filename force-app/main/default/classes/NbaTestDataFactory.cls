/**
 * Shared test data factory for NBA engine tests.
 * Reduces duplication across 18+ test classes by providing reusable
 * builders for Account, Opportunity, Contact, NBA_Queue__c,
 * Account_Scoring__c, Event, and Task records.
 */
@isTest
public class NbaTestDataFactory {

    private static Id payrollRecordTypeId;
    private static Integer entityCounter = 0;

    // ─── Record Type ──────────────────────────────────────────────────

    public static Id getPayrollRecordTypeId() {
        if (payrollRecordTypeId == null) {
            List<RecordType> rts = [
                SELECT Id FROM RecordType
                WHERE SObjectType = 'Opportunity' AND DeveloperName = 'Payroll'
                LIMIT 1
            ];
            if (!rts.isEmpty()) {
                payrollRecordTypeId = rts[0].Id;
            }
        }
        return payrollRecordTypeId;
    }

    private static String nextEntityId(String prefix) {
        entityCounter++;
        return prefix + '-' + String.valueOf(entityCounter).leftPad(4, '0');
    }

    // ─── Account ──────────────────────────────────────────────────────

    public static Account createAccount(String name) {
        return createAccount(name, 40);
    }

    public static Account createAccount(String name, Integer employeeCount) {
        Account acc = new Account(
            Name = name,
            Entity_ID__c = nextEntityId('NTF'),
            Employee_Count__c = employeeCount
        );
        insert acc;
        return acc;
    }

    public static List<Account> createAccounts(String baseName, Integer count) {
        List<Account> accs = new List<Account>();
        for (Integer i = 1; i <= count; i++) {
            accs.add(new Account(
                Name = baseName + ' ' + i,
                Entity_ID__c = nextEntityId('NTF'),
                Employee_Count__c = 40
            ));
        }
        insert accs;
        return accs;
    }

    // ─── Opportunity ──────────────────────────────────────────────────

    public static Opportunity createOpportunity(Id accountId, String stageName,
            Decimal amount) {
        return createOpportunity(accountId, stageName, amount,
            Date.today().addDays(30));
    }

    public static Opportunity createOpportunity(Id accountId, String stageName,
            Decimal amount, Date closeDate) {
        Opportunity opp = new Opportunity(
            Name = stageName + ' Test Opp',
            AccountId = accountId,
            StageName = stageName,
            CloseDate = closeDate,
            Amount = amount,
            Source__c = 'N/A'
        );
        Id rtId = getPayrollRecordTypeId();
        if (rtId != null) {
            opp.RecordTypeId = rtId;
        }
        insert opp;
        return opp;
    }

    public static List<Opportunity> createOpportunities(List<Account> accounts,
            List<String> stages, List<Decimal> amounts) {
        Id rtId = getPayrollRecordTypeId();
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < accounts.size(); i++) {
            Opportunity opp = new Opportunity(
                Name = stages[i] + ' Test Opp ' + (i + 1),
                AccountId = accounts[i].Id,
                StageName = stages[i],
                CloseDate = Date.today().addDays(30),
                Amount = amounts[i],
                Source__c = 'N/A'
            );
            if (rtId != null) opp.RecordTypeId = rtId;
            opps.add(opp);
        }
        insert opps;
        return opps;
    }

    // ─── Contact ──────────────────────────────────────────────────────

    public static Contact createContact(Id accountId, String firstName,
            String lastName) {
        Contact con = new Contact(
            FirstName = firstName,
            LastName = lastName,
            AccountId = accountId,
            Email = firstName.toLowerCase() + '.' + lastName.toLowerCase()
                + '@example.com',
            Phone = '555-' + String.valueOf(Math.mod(
                Math.abs(entityCounter), 10000)).leftPad(4, '0')
        );
        insert con;
        return con;
    }

    public static Contact createContactWithSMS(Id accountId, String firstName,
            String lastName, String mogliNumber) {
        Contact con = new Contact(
            FirstName = firstName,
            LastName = lastName,
            AccountId = accountId,
            Email = firstName.toLowerCase() + '.' + lastName.toLowerCase()
                + '@example.com',
            Phone = '555-' + String.valueOf(Math.mod(
                Math.abs(entityCounter), 10000)).leftPad(4, '0'),
            Mogli_SMS__Mogli_Number__c = mogliNumber
        );
        insert con;
        return con;
    }

    // ─── Account Scoring ──────────────────────────────────────────────

    public static Account_Scoring__c createAccountScoring(Id accountId,
            String entityId, Decimal ltw, Decimal iiw) {
        Account_Scoring__c scoring = new Account_Scoring__c(
            Account__c = accountId,
            Entity_ID__c = entityId,
            Prob_Payroll_Conversion__c = 75,
            Prob_Tier_Upgrade__c = 50,
            Likelihood_To_Win__c = ltw,
            Incremental_If_Won__c = iiw
        );
        insert scoring;
        return scoring;
    }

    // ─── NBA_Queue__c ─────────────────────────────────────────────────

    public static NBA_Queue__c createQueueRecord(Id oppId, Id accountId,
            String status, String actionType) {
        return createQueueRecord(oppId, accountId, status, actionType,
            'Pipeline Cadence');
    }

    public static NBA_Queue__c createQueueRecord(Id oppId, Id accountId,
            String status, String actionType, String sourcePath) {
        NBA_Queue__c q = new NBA_Queue__c(
            Opportunity__c = oppId,
            Account__c = accountId,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = status,
            Action_Type__c = actionType,
            Source_Path__c = sourcePath,
            Workflow_Mode__c = 'Pipeline'
        );
        insert q;
        return q;
    }

    public static NBA_Queue__c createCadenceQueueRecord(Id oppId,
            Id accountId, String cadenceName, Integer stepNumber,
            String actionType, Integer cadenceStage) {
        NBA_Queue__c q = new NBA_Queue__c(
            Opportunity__c = oppId,
            Account__c = accountId,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'Pending',
            Action_Type__c = actionType,
            Source_Path__c = 'Pipeline Cadence',
            Workflow_Mode__c = 'Pipeline',
            Cadence_Name__c = cadenceName,
            Cadence_Step_Number__c = stepNumber,
            Cadence_Stage__c = cadenceStage
        );
        insert q;
        return q;
    }

    public static NBA_Queue__c buildTimeBoundAction(Id oppId, Id accountId,
            Decimal arr, Datetime dueAt) {
        return new NBA_Queue__c(
            Opportunity__c = oppId,
            Account__c = accountId,
            Sales_Rep__c = UserInfo.getUserId(),
            Status__c = 'Pending',
            Action_Type__c = 'Meeting',
            Workflow_Mode__c = 'Pipeline',
            Is_Time_Bound__c = true,
            DueAt__c = dueAt,
            Expected_Incremental_ARR__c = arr
        );
    }

    // ─── Event ────────────────────────────────────────────────────────

    public static Event createEvent(Id whatId, Datetime startTime,
            Integer durationMinutes) {
        Event evt = new Event(
            WhatId = whatId,
            Subject = 'Test Meeting',
            StartDateTime = startTime,
            DurationInMinutes = durationMinutes
        );
        insert evt;
        return evt;
    }

    // ─── Task ─────────────────────────────────────────────────────────

    public static Task createTask(Id whatId, String subject, Date activityDate) {
        Task t = new Task(
            WhatId = whatId,
            Subject = subject,
            ActivityDate = activityDate,
            Status = 'Not Started'
        );
        insert t;
        return t;
    }
}
