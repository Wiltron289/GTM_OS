/**
 * Controller for NBA V2 Demo LWC components.
 * Provides centralized data loading for the nbaDemoWorkspace parent component.
 * All child components receive data via @api properties from the parent - no direct Apex calls.
 */
public with sharing class NbaDemoController {

    // ─── Inner Wrapper Classes ───────────────────────────────────────

    public class PageDataWrapper {
        @AuraEnabled public HeaderData header;
        @AuraEnabled public AccountDetailsData account;
        @AuraEnabled public PayrollStatusData payrollStatus;
        @AuraEnabled public QuotaData quota;
        @AuraEnabled public EngagementData engagement;
        @AuraEnabled public PayrollTabData payrollTab;
        @AuraEnabled public List<ProductData> products;
        @AuraEnabled public List<ContactData> contacts;
        @AuraEnabled public AdminData admin;
        @AuraEnabled public SidebarData sidebar;
        @AuraEnabled public InsightsData insights;
        @AuraEnabled public EventData upcomingEvent;
    }

    public class HeaderData {
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountId;
        @AuraEnabled public Decimal mrr;
        @AuraEnabled public Decimal closeProbability;
        @AuraEnabled public String opportunityName;
    }

    public class AccountDetailsData {
        @AuraEnabled public Integer employeeCount;
        @AuraEnabled public Integer locationCount;
        @AuraEnabled public String plan;
        @AuraEnabled public String onTierMonths;
    }

    public class PayrollStatusData {
        @AuraEnabled public String type;
        @AuraEnabled public String nextStep;
        @AuraEnabled public String checkStatus;
    }

    public class QuotaData {
        @AuraEnabled public Decimal target;
        @AuraEnabled public Decimal closedWon;
        @AuraEnabled public Decimal thisOppMrr;
        @AuraEnabled public Decimal percentage;
    }

    public class EngagementData {
        @AuraEnabled public String lastContactType;
        @AuraEnabled public String lastContactLabel;
        @AuraEnabled public String lastContactAge;
        @AuraEnabled public Integer touchFrequency;
        @AuraEnabled public Decimal closePotential;
        @AuraEnabled public Integer daysInStage;
        @AuraEnabled public String stageName;
        @AuraEnabled public String aiInsight;
    }

    public class PayrollTabData {
        @AuraEnabled public Date firstPayday;
        @AuraEnabled public String inceptionOrSwitcher;
        @AuraEnabled public Integer employeeCount;
        @AuraEnabled public Decimal predictedMrr;
        @AuraEnabled public String payrollRiskLevel;
        @AuraEnabled public Datetime lastProgressionTime;
        @AuraEnabled public String currentLinearFlowPage;
        @AuraEnabled public Datetime lastPayrollEngagement;
        @AuraEnabled public String payrollEngagementType;
        @AuraEnabled public Datetime fedAuthFinish;
        @AuraEnabled public Datetime bankConnectFinish;
        @AuraEnabled public Datetime paySchedFinish;
        @AuraEnabled public String adminLink;
        @AuraEnabled public String checkConsoleLink;
        @AuraEnabled public String kybStatus;
        @AuraEnabled public String onboardStatus;
        @AuraEnabled public String implementationStatus;
        @AuraEnabled public String payrollStatus;
        @AuraEnabled public String blockedReason;
        @AuraEnabled public String checkInfoNeeded;
        @AuraEnabled public Date nextStepDate;
        @AuraEnabled public String nextStepLabel;
        @AuraEnabled public Date futureFollowUpDate;
        @AuraEnabled public String futureFollowUpReason;
        @AuraEnabled public Datetime lastCallDateTime;
        @AuraEnabled public String lastCallOutcome;
        @AuraEnabled public Integer nbaCallCount;
        @AuraEnabled public Boolean isReadyToRun;
    }

    public class ProductData {
        @AuraEnabled public String productFamily;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal salesPrice;
        @AuraEnabled public Decimal totalPrice;
    }

    public class ContactData {
        @AuraEnabled public String contactId;
        @AuraEnabled public String name;
        @AuraEnabled public String initials;
        @AuraEnabled public String title;
        @AuraEnabled public Boolean isPrimary;
        @AuraEnabled public String lastActivityType;
        @AuraEnabled public String lastActivityLabel;
        @AuraEnabled public Date lastActivityDate;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String mogliNumber;
        @AuraEnabled public Boolean optedOut;
    }

    public class AdminData {
        @AuraEnabled public String stageName;
        @AuraEnabled public String oppProductFamilies;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String ownerId;
        @AuraEnabled public Decimal daysSinceLastCall;
        @AuraEnabled public Decimal daysSinceLastMeeting;
        @AuraEnabled public Decimal daysSinceLastInteraction;
        @AuraEnabled public Decimal hoursSinceAssignment;
        @AuraEnabled public Decimal daysSinceCreation;
        @AuraEnabled public String kubaruWorkload;
        @AuraEnabled public Datetime lastMeaningfulConnection;
        @AuraEnabled public Datetime lastCallDateTime;
        @AuraEnabled public Datetime lastMeetingDate;
        @AuraEnabled public Datetime nextScheduledMeeting;
        @AuraEnabled public Datetime firstAssignmentDateTime;
        @AuraEnabled public Boolean isWithin1Hour;
        @AuraEnabled public Datetime lastAssignmentDateTime;
        @AuraEnabled public Datetime createdDate;
    }

    public class SidebarData {
        @AuraEnabled public List<NoteData> notes;
        @AuraEnabled public List<ActivityData> activities;
    }

    public class NoteData {
        @AuraEnabled public String id;
        @AuraEnabled public String title;
        @AuraEnabled public String body;
        @AuraEnabled public String authorName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Boolean isAiSummary;
        @AuraEnabled public Boolean isCurrentUser;
    }

    public class ActivityData implements Comparable {
        @AuraEnabled public String id;
        @AuraEnabled public String iconName;
        @AuraEnabled public String iconVariant;
        @AuraEnabled public String label;
        @AuraEnabled public Date activityDate;
        @AuraEnabled public String contactName;
        @AuraEnabled public String type;

        public Integer compareTo(Object other) {
            ActivityData o = (ActivityData) other;
            if (this.activityDate == null && o.activityDate == null) return 0;
            if (this.activityDate == null) return 1;
            if (o.activityDate == null) return -1;
            // Descending: most recent first
            if (this.activityDate > o.activityDate) return -1;
            if (this.activityDate < o.activityDate) return 1;
            return 0;
        }
    }

    private class NoteDataComparator implements System.Comparator<NoteData> {
        public Integer compare(NoteData a, NoteData b) {
            if (a.createdDate == null && b.createdDate == null) return 0;
            if (a.createdDate == null) return 1;
            if (b.createdDate == null) return -1;
            // Descending: most recent first
            if (a.createdDate > b.createdDate) return -1;
            if (a.createdDate < b.createdDate) return 1;
            return 0;
        }
    }

    public class InsightsData {
        @AuraEnabled public List<String> drivers;
        @AuraEnabled public List<TagData> tags;
        @AuraEnabled public Integer insightCount;
    }

    public class TagData {
        @AuraEnabled public String label;
        @AuraEnabled public Boolean active;
    }

    public class EventData {
        @AuraEnabled public String contactName;
        @AuraEnabled public String accountName;
        @AuraEnabled public Integer minutesUntil;
        @AuraEnabled public String opportunityId;
        @AuraEnabled public Datetime startTime;
        @AuraEnabled public Boolean hasUpcoming;
    }

    // ─── Primary Data Loading Method ─────────────────────────────────

    @AuraEnabled(cacheable=true)
    public static PageDataWrapper getPageData(Id oppId) {
        PageDataWrapper wrapper = new PageDataWrapper();

        // Query 1: Opportunity with Account fields
        Opportunity opp = [
            SELECT Id, Name, StageName, NextStep, Amount, CloseDate, OwnerId, Owner.Name,
                   MRR__c, Deal_Stage_Probability__c,
                   Inception_or_Switcher__c, First_Payday__c,
                   Employee_Count_Deal_Value__c, Payroll_Risk_Level__c,
                   Last_Progression_Time__c, Last_Payroll_Engagement__c,
                   Payroll_Engagement_Type__c, Fed_Auth_Finish_Time__c,
                   Bank_Connect_Finish__c, Pay_Sched_Finish__c,
                   Next_Step_Date__c, Future_Follow_Up_Date__c, Future_Follow_Up_Reason__c,
                   Last_Call_Date_Time__c, Last_Call_Outcome__c, NBA_Call_Count__c,
                   Opportunity_Product_Families__c, Attained_Amount__c,
                   Days_Since_Last_Call__c, Days_Since_Last_Meeting__c,
                   Days_Since_Last_Interaction__c, Hours_Since_Assignment__c,
                   Days_Since_Creation__c, Kubaru_Workload__c,
                   Last_Meaningful_Connection__c, Last_Meeting_Date__c,
                   Next_Scheduled_Meeting__c, First_Assignment_Date_Time__c,
                   Is_Within_1_Hour_of_First_Assignment__c, Date_Time_Last_Reassignment__c,
                   Decision_Maker_Identified__c, Budget_Confirmed__c, Timeline_Confirmed__c,
                   LastStageChange__c, CreatedDate, Primary_Contact__c,
                   Customer_Story__c, Business_Challenge__c,
                   Account.Id, Account.Name,
                   Account.Employee_Count__c, Account.Active_Location_Count__c,
                   Account.Highest_Current_Tier__c, Account.Date_of_Previous_Tier_Change__c,
                   Account.Payroll_Status__c, Account.Payroll_Customer_Status__c,
                   Account.Current_Linear_Flow_Page__c, Account.Admin_Link__c,
                   Account.Check_Console_Link__c, Account.KYB_Status__c,
                   Account.Onboard_Status__c, Account.Implementation_Status__c,
                   Account.Blocked_Reason__c, Account.Check_Info_Needed__c,
                   Account.Last_Payroll_Engagement__c
            FROM Opportunity
            WHERE Id = :oppId
            LIMIT 1
        ];

        // Build Header
        wrapper.header = buildHeader(opp);

        // Build Account Details
        wrapper.account = buildAccountDetails(opp);

        // Build Payroll Status
        wrapper.payrollStatus = buildPayrollStatus(opp);

        // Build Payroll Tab
        wrapper.payrollTab = buildPayrollTab(opp);

        // Build Admin Data
        wrapper.admin = buildAdminData(opp);

        // Query 2: Account Scoring
        wrapper.insights = buildInsights(opp);

        // Query 3: Contacts via OpportunityContactRole
        wrapper.contacts = buildContacts(oppId);

        // Query 4: Products
        wrapper.products = buildProducts(oppId);

        // Query 5: Upcoming Events
        wrapper.upcomingEvent = buildUpcomingEvent(opp);

        // Query 6: Activity Timeline + Notes
        wrapper.sidebar = buildSidebar(oppId);

        // Query 7: Quota Progress
        wrapper.quota = buildQuota(opp);

        // Build Engagement
        wrapper.engagement = buildEngagement(opp, wrapper.sidebar, wrapper.insights);

        return wrapper;
    }

    // ─── Builder Methods ─────────────────────────────────────────────

    private static HeaderData buildHeader(Opportunity opp) {
        HeaderData h = new HeaderData();
        h.accountName = opp.Account.Name;
        h.accountId = opp.Account.Id;
        h.mrr = opp.Amount != null ? opp.Amount : (opp.MRR__c != null ? opp.MRR__c : 0);
        h.closeProbability = opp.Deal_Stage_Probability__c;
        h.opportunityName = opp.Name;
        return h;
    }

    private static AccountDetailsData buildAccountDetails(Opportunity opp) {
        AccountDetailsData a = new AccountDetailsData();
        a.employeeCount = opp.Account.Employee_Count__c != null
            ? Integer.valueOf(opp.Account.Employee_Count__c) : 0;
        a.locationCount = opp.Account.Active_Location_Count__c != null
            ? Integer.valueOf(opp.Account.Active_Location_Count__c) : 0;
        a.plan = opp.Account.Highest_Current_Tier__c;

        if (opp.Account.Date_of_Previous_Tier_Change__c != null) {
            Integer months = opp.Account.Date_of_Previous_Tier_Change__c.monthsBetween(Date.today());
            a.onTierMonths = months + 'mo';
        }
        return a;
    }

    private static PayrollStatusData buildPayrollStatus(Opportunity opp) {
        PayrollStatusData p = new PayrollStatusData();
        p.type = opp.Inception_or_Switcher__c;
        p.nextStep = opp.NextStep;
        p.checkStatus = opp.Account.Payroll_Status__c;
        return p;
    }

    private static PayrollTabData buildPayrollTab(Opportunity opp) {
        PayrollTabData p = new PayrollTabData();
        p.firstPayday = opp.First_Payday__c;
        p.inceptionOrSwitcher = opp.Inception_or_Switcher__c;
        p.employeeCount = opp.Employee_Count_Deal_Value__c != null
            ? Integer.valueOf(opp.Employee_Count_Deal_Value__c) : null;
        p.predictedMrr = opp.MRR__c;
        p.payrollRiskLevel = opp.Payroll_Risk_Level__c;
        p.lastProgressionTime = opp.Last_Progression_Time__c;
        p.currentLinearFlowPage = opp.Account.Current_Linear_Flow_Page__c;
        p.lastPayrollEngagement = opp.Last_Payroll_Engagement__c;
        p.payrollEngagementType = opp.Payroll_Engagement_Type__c;
        p.fedAuthFinish = opp.Fed_Auth_Finish_Time__c;
        p.bankConnectFinish = opp.Bank_Connect_Finish__c;
        p.paySchedFinish = opp.Pay_Sched_Finish__c;
        p.adminLink = opp.Account.Admin_Link__c;
        p.checkConsoleLink = opp.Account.Check_Console_Link__c;
        p.kybStatus = opp.Account.KYB_Status__c;
        p.onboardStatus = opp.Account.Onboard_Status__c;
        p.implementationStatus = opp.Account.Implementation_Status__c;
        p.payrollStatus = opp.Account.Payroll_Status__c;
        p.blockedReason = opp.Account.Blocked_Reason__c;
        p.checkInfoNeeded = opp.Account.Check_Info_Needed__c;
        p.nextStepDate = opp.Next_Step_Date__c;
        p.nextStepLabel = opp.NextStep;
        p.futureFollowUpDate = opp.Future_Follow_Up_Date__c;
        p.futureFollowUpReason = opp.Future_Follow_Up_Reason__c;
        p.lastCallDateTime = opp.Last_Call_Date_Time__c;
        p.lastCallOutcome = opp.Last_Call_Outcome__c;
        p.nbaCallCount = opp.NBA_Call_Count__c != null
            ? Integer.valueOf(opp.NBA_Call_Count__c) : 0;
        p.isReadyToRun = opp.Account.Payroll_Status__c != null
            && opp.Account.Payroll_Status__c.containsIgnoreCase('ready');
        return p;
    }

    private static AdminData buildAdminData(Opportunity opp) {
        AdminData a = new AdminData();
        a.stageName = opp.StageName;
        a.oppProductFamilies = opp.Opportunity_Product_Families__c;
        a.ownerName = opp.Owner.Name;
        a.ownerId = opp.OwnerId;
        a.daysSinceLastCall = opp.Days_Since_Last_Call__c;
        a.daysSinceLastMeeting = opp.Days_Since_Last_Meeting__c;
        a.daysSinceLastInteraction = opp.Days_Since_Last_Interaction__c;
        a.hoursSinceAssignment = opp.Hours_Since_Assignment__c;
        a.daysSinceCreation = opp.Days_Since_Creation__c;
        a.kubaruWorkload = opp.Kubaru_Workload__c;
        a.lastMeaningfulConnection = opp.Last_Meaningful_Connection__c;
        a.lastCallDateTime = opp.Last_Call_Date_Time__c;
        a.lastMeetingDate = opp.Last_Meeting_Date__c;
        a.nextScheduledMeeting = opp.Next_Scheduled_Meeting__c;
        a.firstAssignmentDateTime = opp.First_Assignment_Date_Time__c;
        a.isWithin1Hour = opp.Is_Within_1_Hour_of_First_Assignment__c;
        a.lastAssignmentDateTime = opp.Date_Time_Last_Reassignment__c;
        a.createdDate = opp.CreatedDate;
        return a;
    }

    private static InsightsData buildInsights(Opportunity opp) {
        InsightsData ins = new InsightsData();
        ins.drivers = new List<String>();
        ins.tags = new List<TagData>();

        // Query Account_Scoring__c for driver text
        List<Account_Scoring__c> scoringRecords = [
            SELECT Payroll_Top_Drivers__c, Tier_Upgrade_Top_Drivers__c,
                   Prob_Payroll_Conversion__c, Prob_Tier_Upgrade__c
            FROM Account_Scoring__c
            WHERE Account__c = :opp.Account.Id
            LIMIT 1
        ];

        if (!scoringRecords.isEmpty()) {
            Account_Scoring__c scoring = scoringRecords[0];
            if (String.isNotBlank(scoring.Payroll_Top_Drivers__c)) {
                for (String line : scoring.Payroll_Top_Drivers__c.split('\n')) {
                    if (String.isNotBlank(line.trim())) {
                        ins.drivers.add(line.trim());
                    }
                }
            }
            if (String.isNotBlank(scoring.Tier_Upgrade_Top_Drivers__c)) {
                for (String line : scoring.Tier_Upgrade_Top_Drivers__c.split('\n')) {
                    if (String.isNotBlank(line.trim())) {
                        ins.drivers.add(line.trim());
                    }
                }
            }
        }

        // Build tags from Opportunity checkboxes
        ins.tags.add(buildTag('High Intent',
            opp.Deal_Stage_Probability__c != null && opp.Deal_Stage_Probability__c > 70));
        ins.tags.add(buildTag('Decision Maker Engaged',
            opp.Decision_Maker_Identified__c));
        ins.tags.add(buildTag('Budget Confirmed',
            opp.Budget_Confirmed__c));
        ins.tags.add(buildTag('Time Sensitive',
            opp.Timeline_Confirmed__c));

        ins.insightCount = ins.drivers.size();
        return ins;
    }

    private static TagData buildTag(String label, Boolean active) {
        TagData t = new TagData();
        t.label = label;
        t.active = active != null ? active : false;
        return t;
    }

    private static List<ContactData> buildContacts(Id oppId) {
        List<ContactData> contactList = new List<ContactData>();
        Set<Id> seenContactIds = new Set<Id>();

        // First: get contacts from OpportunityContactRole (these get isPrimary flag)
        // Get the Account Id for the Opp so we can also query Account contacts
        Id accountId;
        for (OpportunityContactRole ocr : [
            SELECT ContactId, Contact.Name, Contact.FirstName, Contact.LastName,
                   Contact.Title, Contact.Email, Contact.Phone, Contact.AccountId,
                   Contact.Mogli_SMS__Mogli_Number__c, Contact.Mogli_SMS__Mogli_Opt_Out__c,
                   IsPrimary
            FROM OpportunityContactRole
            WHERE OpportunityId = :oppId
            ORDER BY IsPrimary DESC, Contact.Name ASC
        ]) {
            ContactData c = new ContactData();
            c.contactId = ocr.ContactId;
            c.name = ocr.Contact.Name;
            c.title = ocr.Contact.Title;
            c.isPrimary = ocr.IsPrimary;
            c.email = ocr.Contact.Email;
            c.phone = ocr.Contact.Phone;
            c.mogliNumber = ocr.Contact.Mogli_SMS__Mogli_Number__c;
            c.optedOut = ocr.Contact.Mogli_SMS__Mogli_Opt_Out__c == true;

            // Build initials
            String first = ocr.Contact.FirstName != null ? ocr.Contact.FirstName.substring(0, 1) : '';
            String last = ocr.Contact.LastName != null ? ocr.Contact.LastName.substring(0, 1) : '';
            c.initials = (first + last).toUpperCase();

            contactList.add(c);
            seenContactIds.add(ocr.ContactId);

            if (accountId == null && ocr.Contact.AccountId != null) {
                accountId = ocr.Contact.AccountId;
            }
        }

        // If we didn't get the AccountId from OCR, query it from the Opportunity
        if (accountId == null) {
            List<Opportunity> opps = [SELECT AccountId FROM Opportunity WHERE Id = :oppId LIMIT 1];
            if (!opps.isEmpty()) {
                accountId = opps[0].AccountId;
            }
        }

        // Second: get all contacts on the Account that aren't already in the list
        if (accountId != null) {
            for (Contact con : [
                SELECT Id, Name, FirstName, LastName, Title, Email, Phone,
                       Mogli_SMS__Mogli_Number__c, Mogli_SMS__Mogli_Opt_Out__c
                FROM Contact
                WHERE AccountId = :accountId
                  AND Id NOT IN :seenContactIds
                ORDER BY Name ASC
            ]) {
                ContactData c = new ContactData();
                c.contactId = con.Id;
                c.name = con.Name;
                c.title = con.Title;
                c.isPrimary = false;
                c.email = con.Email;
                c.phone = con.Phone;
                c.mogliNumber = con.Mogli_SMS__Mogli_Number__c;
                c.optedOut = con.Mogli_SMS__Mogli_Opt_Out__c == true;

                String first = con.FirstName != null ? con.FirstName.substring(0, 1) : '';
                String last = con.LastName != null ? con.LastName.substring(0, 1) : '';
                c.initials = (first + last).toUpperCase();

                contactList.add(c);
                seenContactIds.add(con.Id);
            }
        }

        // Get last activity for each contact
        if (!contactList.isEmpty()) {
            Set<Id> contactIds = new Set<Id>();
            for (ContactData cd : contactList) {
                contactIds.add(cd.contactId);
            }

            Map<Id, Task> lastTaskByContact = new Map<Id, Task>();
            for (Task t : [
                SELECT WhoId, Subject, ActivityDate, TaskSubtype
                FROM Task
                WHERE WhoId IN :contactIds AND Status = 'Completed'
                ORDER BY ActivityDate DESC
                LIMIT 100
            ]) {
                if (!lastTaskByContact.containsKey(t.WhoId)) {
                    lastTaskByContact.put(t.WhoId, t);
                }
            }

            for (ContactData cd : contactList) {
                Task lastTask = lastTaskByContact.get(cd.contactId);
                if (lastTask != null) {
                    cd.lastActivityLabel = lastTask.Subject;
                    cd.lastActivityDate = lastTask.ActivityDate;
                    cd.lastActivityType = lastTask.TaskSubtype == 'Call' ? 'Call' : 'Task';
                }
            }
        }

        return contactList;
    }

    private static List<ProductData> buildProducts(Id oppId) {
        List<ProductData> productList = new List<ProductData>();
        for (OpportunityLineItem oli : [
            SELECT Product2.Family, Product2.Name, Quantity, UnitPrice, TotalPrice
            FROM OpportunityLineItem
            WHERE OpportunityId = :oppId
            ORDER BY Product2.Family, Product2.Name
        ]) {
            ProductData p = new ProductData();
            p.productFamily = oli.Product2.Family;
            p.productName = oli.Product2.Name;
            p.quantity = oli.Quantity;
            p.salesPrice = oli.UnitPrice;
            p.totalPrice = oli.TotalPrice;
            productList.add(p);
        }
        return productList;
    }

    private static EventData buildUpcomingEvent(Opportunity opp) {
        EventData ev = new EventData();
        ev.hasUpcoming = false;

        List<Event> upcomingEvents = [
            SELECT Subject, StartDateTime, Who.Name, What.Name
            FROM Event
            WHERE WhatId = :opp.Id
              AND StartDateTime >= :Datetime.now()
              AND StartDateTime <= :Datetime.now().addHours(24)
            ORDER BY StartDateTime ASC
            LIMIT 1
        ];

        if (!upcomingEvents.isEmpty()) {
            Event e = upcomingEvents[0];
            ev.hasUpcoming = true;
            ev.contactName = e.Who != null ? e.Who.Name : 'Unknown';
            ev.accountName = opp.Account.Name;
            ev.startTime = e.StartDateTime;
            ev.opportunityId = opp.Id;

            Long millisDiff = e.StartDateTime.getTime() - Datetime.now().getTime();
            ev.minutesUntil = Integer.valueOf(millisDiff / 60000);
        }

        return ev;
    }

    private static SidebarData buildSidebar(Id oppId) {
        SidebarData sb = new SidebarData();
        sb.notes = new List<NoteData>();
        sb.activities = new List<ActivityData>();

        // Activities: recent Tasks + Events
        for (Task t : [
            SELECT Id, Subject, ActivityDate, Who.Name, TaskSubtype, Description, CreatedById
            FROM Task
            WHERE WhatId = :oppId
            ORDER BY ActivityDate DESC, CreatedDate DESC
            LIMIT 20
        ]) {
            ActivityData a = new ActivityData();
            a.id = t.Id;
            a.label = t.Subject;
            a.activityDate = t.ActivityDate;
            a.contactName = t.Who != null ? t.Who.Name : null;
            a.type = t.TaskSubtype;

            if (t.TaskSubtype == 'Call') {
                a.iconName = 'standard:log_a_call';
                a.iconVariant = '';
            } else if (t.TaskSubtype == 'Email') {
                a.iconName = 'standard:email';
                a.iconVariant = '';
            } else {
                a.iconName = 'standard:task';
                a.iconVariant = '';
            }

            // Check if this looks like a note
            if (t.Subject != null && t.Subject.startsWithIgnoreCase('Note')) {
                NoteData n = new NoteData();
                n.id = t.Id;
                n.title = t.Subject;
                n.body = t.Description;
                n.authorName = t.Who != null ? t.Who.Name : 'Me';
                n.createdDate = t.ActivityDate != null
                    ? Datetime.newInstance(t.ActivityDate, Time.newInstance(0, 0, 0, 0))
                    : null;
                n.isAiSummary = false;
                n.isCurrentUser = (t.CreatedById == UserInfo.getUserId());
                sb.notes.add(n);
            }

            sb.activities.add(a);
        }

        for (Event e : [
            SELECT Id, Subject, ActivityDate, Who.Name
            FROM Event
            WHERE WhatId = :oppId AND ActivityDate <= TODAY
            ORDER BY ActivityDate DESC
            LIMIT 10
        ]) {
            ActivityData a = new ActivityData();
            a.id = e.Id;
            a.label = e.Subject;
            a.activityDate = e.ActivityDate;
            a.contactName = e.Who != null ? e.Who.Name : null;
            a.type = 'Event';
            a.iconName = 'standard:event';
            a.iconVariant = '';
            sb.activities.add(a);
        }

        // Query ContentNotes linked to this Opportunity
        for (ContentDocumentLink cdl : [
            SELECT ContentDocument.Title, ContentDocument.CreatedDate,
                   ContentDocument.CreatedBy.Name, ContentDocument.CreatedById, ContentDocument.LatestPublishedVersion.VersionData
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :oppId
              AND ContentDocument.FileType = 'SNOTE'
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 20
        ]) {
            NoteData n = new NoteData();
            n.id = cdl.ContentDocumentId;
            n.title = cdl.ContentDocument.Title;
            n.authorName = cdl.ContentDocument.CreatedBy.Name;
            n.createdDate = cdl.ContentDocument.CreatedDate;
            n.isAiSummary = false;
            n.isCurrentUser = (cdl.ContentDocument.CreatedById == UserInfo.getUserId());
            // ContentNote body is stored as VersionData blob
            if (cdl.ContentDocument.LatestPublishedVersion != null
                && cdl.ContentDocument.LatestPublishedVersion.VersionData != null) {
                n.body = cdl.ContentDocument.LatestPublishedVersion.VersionData.toString();
            }
            sb.notes.add(n);
        }

        // SMS activities from Mogli
        for (Mogli_SMS__SMS__c sms : [
            SELECT Id, Mogli_SMS__Message__c, Mogli_SMS__Send_Date__c,
                   Mogli_SMS__Direction__c, Mogli_SMS__Contact__r.Name,
                   Mogli_SMS__Phone_Number__c, CreatedDate
            FROM Mogli_SMS__SMS__c
            WHERE Mogli_SMS__Opportunity__c = :oppId
            ORDER BY CreatedDate DESC
            LIMIT 20
        ]) {
            ActivityData a = new ActivityData();
            a.id = sms.Id;
            String msgPreview = sms.Mogli_SMS__Message__c != null
                ? (sms.Mogli_SMS__Message__c.length() > 40
                    ? sms.Mogli_SMS__Message__c.substring(0, 40) + '...'
                    : sms.Mogli_SMS__Message__c)
                : 'SMS';
            String contactName = sms.Mogli_SMS__Contact__r != null ? sms.Mogli_SMS__Contact__r.Name : null;
            a.label = (sms.Mogli_SMS__Direction__c == 'Outbound' ? 'SMS sent' : 'SMS received')
                + (contactName != null ? ' - ' + contactName + ': ' : ': ') + msgPreview;
            a.activityDate = sms.Mogli_SMS__Send_Date__c != null
                ? sms.Mogli_SMS__Send_Date__c.date()
                : sms.CreatedDate.date();
            a.contactName = contactName;
            a.type = 'SMS';
            a.iconName = 'utility:chat';
            a.iconVariant = '';
            sb.activities.add(a);
        }

        // Sort notes by date descending
        sb.notes.sort(new NoteDataComparator());

        // Sort activities by date descending
        sb.activities.sort();

        return sb;
    }

    private static QuotaData buildQuota(Opportunity opp) {
        QuotaData q = new QuotaData();
        q.target = 5000; // Hardcoded for demo
        q.thisOppMrr = opp.Amount != null ? opp.Amount : 0;

        // Aggregate Closed Won Amount this month for the opp owner
        AggregateResult[] results = [
            SELECT SUM(Amount) totalAmount
            FROM Opportunity
            WHERE OwnerId = :opp.OwnerId
              AND StageName = 'Closed Won'
              AND CloseDate = THIS_MONTH
        ];

        q.closedWon = 0;
        if (!results.isEmpty() && results[0].get('totalAmount') != null) {
            q.closedWon = (Decimal) results[0].get('totalAmount');
        }

        q.percentage = q.target > 0 ? ((q.closedWon / q.target) * 100).setScale(0) : 0;
        return q;
    }

    private static EngagementData buildEngagement(Opportunity opp, SidebarData sidebar, InsightsData insights) {
        EngagementData e = new EngagementData();
        e.closePotential = opp.Deal_Stage_Probability__c;
        e.stageName = opp.StageName;

        // Days in stage
        if (opp.LastStageChange__c != null) {
            e.daysInStage = opp.LastStageChange__c.daysBetween(Date.today());
        } else {
            e.daysInStage = opp.Days_Since_Creation__c != null
                ? Integer.valueOf(opp.Days_Since_Creation__c) : 0;
        }

        // Last contact from activities
        if (sidebar.activities != null && !sidebar.activities.isEmpty()) {
            ActivityData lastAct = sidebar.activities[0];
            e.lastContactType = lastAct.type;
            e.lastContactLabel = lastAct.label != null ?
                (lastAct.label.length() > 20 ? lastAct.label.substring(0, 20) : lastAct.label)
                : 'Activity';

            if (lastAct.activityDate != null) {
                Integer daysAgo = lastAct.activityDate.daysBetween(Date.today());
                e.lastContactAge = daysAgo == 0 ? 'Today' :
                    daysAgo == 1 ? '1d ago' : daysAgo + 'd ago';
            }
        }

        // Touch frequency: count activities in last 30 days
        Integer count = 0;
        if (sidebar.activities != null) {
            Date thirtyDaysAgo = Date.today().addDays(-30);
            for (ActivityData act : sidebar.activities) {
                if (act.activityDate != null && act.activityDate >= thirtyDaysAgo) {
                    count++;
                }
            }
        }
        e.touchFrequency = count;

        // AI Insight from drivers
        if (insights.drivers != null && !insights.drivers.isEmpty()) {
            e.aiInsight = String.join(insights.drivers, ' ');
        }

        return e;
    }

    // ─── Action Methods (Non-cacheable) ──────────────────────────────

    @AuraEnabled
    public static Id saveNote(Id oppId, String noteBody) {
        ContentNote cn = new ContentNote();
        cn.Title = 'Rep Note';
        cn.Content = Blob.valueOf(noteBody);
        insert cn;

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = cn.Id;
        cdl.LinkedEntityId = oppId;
        cdl.ShareType = 'V';
        insert cdl;

        return cn.Id;
    }

    @AuraEnabled
    public static void sendEmail(Id contactId, String subject, String body, Id templateId, Id oppId) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(contactId);
        mail.setSaveAsActivity(true);

        if (oppId != null) {
            mail.setWhatId(oppId);
        }

        if (templateId != null) {
            mail.setTemplateId(templateId);
        } else {
            mail.setSubject(subject);
            mail.setHtmlBody(body);
        }

        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getEmailTemplates() {
        List<Map<String, String>> templates = new List<Map<String, String>>();
        for (EmailTemplate et : [
            SELECT Id, Name, Subject, HtmlValue
            FROM EmailTemplate
            WHERE IsActive = true
            ORDER BY Name ASC
            LIMIT 50
        ]) {
            Map<String, String> t = new Map<String, String>();
            t.put('id', et.Id);
            t.put('name', et.Name);
            t.put('subject', et.Subject);
            t.put('body', et.HtmlValue);
            templates.add(t);
        }
        return templates;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getSmsTemplates() {
        List<Map<String, String>> templates = new List<Map<String, String>>();
        for (Mogli_SMS__SMS_Template__c tmpl : [
            SELECT Id, Name, Mogli_SMS__Name__c, Mogli_SMS__Text__c
            FROM Mogli_SMS__SMS_Template__c
            WHERE Mogli_SMS__private__c = false
            ORDER BY Name ASC
            LIMIT 50
        ]) {
            Map<String, String> t = new Map<String, String>();
            t.put('id', tmpl.Id);
            t.put('name', tmpl.Mogli_SMS__Name__c != null ? tmpl.Mogli_SMS__Name__c : tmpl.Name);
            t.put('text', tmpl.Mogli_SMS__Text__c);
            templates.add(t);
        }
        return templates;
    }

    @AuraEnabled
    public static Id sendSms(Id contactId, String message, Id oppId) {
        Contact con = [
            SELECT Id, Mogli_SMS__Mogli_Number__c, Mogli_SMS__Mogli_Opt_Out__c, AccountId
            FROM Contact
            WHERE Id = :contactId
            LIMIT 1
        ];

        if (String.isBlank(con.Mogli_SMS__Mogli_Number__c)) {
            AuraHandledException ex = new AuraHandledException('Contact does not have an SMS number (Mogli Number is blank).');
            ex.setMessage('Contact does not have an SMS number (Mogli Number is blank).');
            throw ex;
        }

        if (con.Mogli_SMS__Mogli_Opt_Out__c == true) {
            AuraHandledException ex = new AuraHandledException('Contact has opted out of SMS communications.');
            ex.setMessage('Contact has opted out of SMS communications.');
            throw ex;
        }

        List<Mogli_SMS__Gateway__c> gateways = [
            SELECT Id
            FROM Mogli_SMS__Gateway__c
            WHERE Mogli_SMS__Inactive__c = false
            ORDER BY Name ASC
            LIMIT 1
        ];

        Mogli_SMS__SMS__c sms = new Mogli_SMS__SMS__c();
        sms.Mogli_SMS__Contact__c = contactId;
        sms.Mogli_SMS__Opportunity__c = oppId;
        sms.Account__c = con.AccountId;
        sms.Mogli_SMS__Message__c = message;
        sms.Mogli_SMS__Direction__c = 'Outbound';
        sms.Mogli_SMS__Status__c = 'Queued';
        sms.Mogli_SMS__Phone_Number__c = con.Mogli_SMS__Mogli_Number__c;

        if (!gateways.isEmpty()) {
            sms.Mogli_SMS__Gateway__c = gateways[0].Id;
        }

        insert sms;
        return sms.Id;
    }
}
