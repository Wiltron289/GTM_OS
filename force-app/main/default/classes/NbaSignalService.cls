/**
 * NbaSignalService — CRM signal detection for the NBA V2 Action Orchestration Engine.
 * Queries Talkdesk calls, Mogli SMS, Events, Tasks, Account Scoring, and existing
 * NBA_Queue__c actions to build a signal wrapper per Opportunity.
 *
 * Called by NbaActionCreationService during scheduled evaluation runs.
 * Uses 7 SOQL queries per batch of Opportunity IDs (all outside loops).
 */
public with sharing class NbaSignalService {

    // ─── Stage Number Mapping ─────────────────────────────────────────
    private static final Map<String, Integer> STAGE_MAP = new Map<String, Integer>{
        'New' => 1,
        'Connect' => 2,
        'Consult' => 3,
        'Evaluating' => 3,
        'Closing' => 4,
        'Verbal Commit' => 5,
        'Ready to Convert' => 5,
        'Hand-Off' => 0
    };

    // ─── Signal Wrapper ───────────────────────────────────────────────
    public class OpportunitySignal {
        public Id oppId;
        public Id accountId;
        public Id ownerId;
        public String stageName;
        public Integer stageNumber;
        public Decimal mrr;
        public Decimal amount;
        public Decimal dealStageProbability;
        public Decimal daysSinceLastInteraction;
        public Decimal hoursSinceAssignment;
        public Boolean isClosed;

        // Talkdesk signals
        public Datetime lastCallDate;
        public String lastCallDisposition;
        public Decimal lastCallTalkTimeSec;
        public Boolean hadConnectedCall;
        public Boolean hadNoConnect;

        // SMS signals
        public Datetime lastSmsDate;
        public String lastSmsDirection;
        public Boolean hadIncomingReply;

        // Meeting signals
        public Boolean hasUpcomingMeeting;
        public Datetime upcomingMeetingStart;

        // Task signals
        public Datetime lastTaskDate;
        public String lastTaskSubtype;

        // Account scoring
        public Decimal probPayrollConversion;
        public Decimal probTierUpgrade;
        public Boolean hasAccountScoring;

        // Existing actions (dedup)
        public List<NBA_Queue__c> existingActiveActions;
        public Boolean hasActiveAction;

        // Audit record signals (on-demand suppression)
        public Boolean hasSnoozedAction;
        public Datetime snoozedUntilDate;
        public Datetime lastCompletedDate;

        // Computed: most recent valid touch
        public Datetime lastValidTouchDate;

        public OpportunitySignal() {
            this.hadConnectedCall = false;
            this.hadNoConnect = false;
            this.hadIncomingReply = false;
            this.hasUpcomingMeeting = false;
            this.hasAccountScoring = false;
            this.hasActiveAction = false;
            this.existingActiveActions = new List<NBA_Queue__c>();
            this.hasSnoozedAction = false;
        }
    }

    // ─── Primary Entry Point ──────────────────────────────────────────

    /**
     * Build signal wrappers for a batch of Opportunity IDs.
     * Uses 7 SOQL queries (all batched, outside loops).
     * @param oppIds Set of Opportunity IDs to evaluate
     * @return Map of Opp ID to OpportunitySignal
     */
    public static Map<Id, OpportunitySignal> getSignals(Set<Id> oppIds) {
        Map<Id, OpportunitySignal> signals = new Map<Id, OpportunitySignal>();
        if (oppIds == null || oppIds.isEmpty()) {
            return signals;
        }

        // Query 1: Opportunity data
        Map<Id, Opportunity> oppMap = queryOpportunities(oppIds);

        // Collect Account IDs for scoring query
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : oppMap.values()) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }

        // Queries 2-7 (all batched, outside loops)
        Map<Id, talkdesk__Talkdesk_Activity__c> talkdeskMap = queryRecentTalkdesk(oppIds);
        Map<Id, Mogli_SMS__SMS__c> smsMap = queryRecentSms(oppIds);
        Map<Id, Event> eventMap = queryUpcomingEvents(oppIds);
        Map<Id, Task> taskMap = queryRecentTasks(oppIds);
        Map<Id, Account_Scoring__c> scoringMap = queryAccountScoring(accountIds);
        Map<Id, List<NBA_Queue__c>> existingActionsMap = queryExistingActions(oppIds);

        // Assemble signals per Opportunity
        for (Id oppId : oppIds) {
            Opportunity opp = oppMap.get(oppId);
            if (opp == null) {
                continue;
            }

            OpportunitySignal sig = new OpportunitySignal();
            sig.oppId = opp.Id;
            sig.accountId = opp.AccountId;
            sig.ownerId = opp.OwnerId;
            sig.stageName = opp.StageName;
            sig.stageNumber = getStageNumber(opp.StageName);
            sig.mrr = opp.MRR__c;
            sig.amount = opp.Amount;
            sig.dealStageProbability = opp.Deal_Stage_Probability__c;
            sig.daysSinceLastInteraction = opp.Days_Since_Last_Interaction__c;
            sig.hoursSinceAssignment = opp.Hours_Since_Assignment__c;
            sig.isClosed = opp.IsClosed;

            // Talkdesk signals
            talkdesk__Talkdesk_Activity__c call = talkdeskMap.get(oppId);
            if (call != null) {
                sig.lastCallDate = call.CreatedDate;
                sig.lastCallTalkTimeSec = call.talkdesk__Total_Talk_Time_sec__c;
                String disposition = call.talkdesk__DispositionCode__r != null
                    ? call.talkdesk__DispositionCode__r.talkdesk__Label__c
                    : null;
                sig.lastCallDisposition = disposition;
                sig.hadConnectedCall = disposition != null
                    && disposition.startsWithIgnoreCase('Connected')
                    && call.talkdesk__Total_Talk_Time_sec__c != null
                    && call.talkdesk__Total_Talk_Time_sec__c > 0;
                sig.hadNoConnect = disposition != null
                    && (disposition.startsWithIgnoreCase('Attempted')
                        || (call.talkdesk__Total_Talk_Time_sec__c == null
                            || call.talkdesk__Total_Talk_Time_sec__c == 0));
            }

            // SMS signals
            Mogli_SMS__SMS__c sms = smsMap.get(oppId);
            if (sms != null) {
                sig.lastSmsDate = sms.CreatedDate;
                sig.lastSmsDirection = sms.Mogli_SMS__Direction__c;
                sig.hadIncomingReply = sms.Mogli_SMS__Direction__c == 'Incoming';
            }

            // Meeting signals
            Event evt = eventMap.get(oppId);
            if (evt != null) {
                sig.hasUpcomingMeeting = true;
                sig.upcomingMeetingStart = evt.StartDateTime;
            }

            // Task signals
            Task tsk = taskMap.get(oppId);
            if (tsk != null) {
                sig.lastTaskDate = tsk.ActivityDate != null
                    ? Datetime.newInstance(tsk.ActivityDate, Time.newInstance(0, 0, 0, 0))
                    : tsk.CreatedDate;
                sig.lastTaskSubtype = tsk.TaskSubtype;
            }

            // Account scoring
            if (opp.AccountId != null) {
                Account_Scoring__c scoring = scoringMap.get(opp.AccountId);
                if (scoring != null) {
                    sig.hasAccountScoring = true;
                    sig.probPayrollConversion = scoring.Prob_Payroll_Conversion__c;
                    sig.probTierUpgrade = scoring.Prob_Tier_Upgrade__c;
                }
            }

            // Existing actions + audit records
            List<NBA_Queue__c> existing = existingActionsMap.get(oppId);
            if (existing != null && !existing.isEmpty()) {
                for (NBA_Queue__c ea : existing) {
                    if (ea.Status__c == 'Snoozed' && ea.Snoozed_Until__c != null
                        && ea.Snoozed_Until__c > Datetime.now()) {
                        sig.hasSnoozedAction = true;
                        sig.snoozedUntilDate = ea.Snoozed_Until__c;
                    } else if (ea.Status__c == 'Completed' && ea.Completed_Date__c != null) {
                        if (sig.lastCompletedDate == null || ea.Completed_Date__c > sig.lastCompletedDate) {
                            sig.lastCompletedDate = ea.Completed_Date__c;
                        }
                    } else if (ea.Status__c == 'Dismissed' && ea.CooldownUntil__c != null
                               && ea.CooldownUntil__c > Datetime.now()) {
                        // Treat dismissed records as completions for cooldown suppression
                        Datetime dismissedAt = ea.CreatedDate;
                        if (sig.lastCompletedDate == null || dismissedAt > sig.lastCompletedDate) {
                            sig.lastCompletedDate = dismissedAt;
                        }
                    } else if (ea.Status__c != 'Completed' && ea.Status__c != 'Dismissed') {
                        // Active status — mark as having active action
                        sig.hasActiveAction = true;
                    }
                }
                sig.existingActiveActions = existing;
            }

            // Compute last valid touch date (MAX of call, sms, task)
            sig.lastValidTouchDate = computeLastValidTouch(
                sig.lastCallDate, sig.lastSmsDate, sig.lastTaskDate
            );

            signals.put(oppId, sig);
        }

        return signals;
    }

    // ─── Stage Utility ────────────────────────────────────────────────

    public static Integer getStageNumber(String stageName) {
        if (stageName == null) {
            return 1;
        }
        return STAGE_MAP.containsKey(stageName) ? STAGE_MAP.get(stageName) : 1;
    }

    // ─── Private Query Methods ────────────────────────────────────────

    private static Map<Id, Opportunity> queryOpportunities(Set<Id> oppIds) {
        return new Map<Id, Opportunity>([
            SELECT Id, Name, StageName, Amount, MRR__c, OwnerId, AccountId,
                   CloseDate, IsClosed, Deal_Stage_Probability__c,
                   Days_Since_Last_Interaction__c, Hours_Since_Assignment__c,
                   Days_Since_Creation__c
            FROM Opportunity
            WHERE Id IN :oppIds
            WITH SECURITY_ENFORCED
        ]);
    }

    private static Map<Id, talkdesk__Talkdesk_Activity__c> queryRecentTalkdesk(Set<Id> oppIds) {
        Map<Id, talkdesk__Talkdesk_Activity__c> resultMap = new Map<Id, talkdesk__Talkdesk_Activity__c>();
        List<talkdesk__Talkdesk_Activity__c> activities = [
            SELECT Id, talkdesk__Opportunity__c, talkdesk__Type__c,
                   talkdesk__DispositionCode__r.talkdesk__Label__c,
                   talkdesk__Total_Talk_Time_sec__c, CreatedDate
            FROM talkdesk__Talkdesk_Activity__c
            WHERE talkdesk__Opportunity__c IN :oppIds
              AND talkdesk__Type__c IN ('Outbound', 'Inbound')
              AND CreatedDate >= LAST_N_DAYS:7
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1000
        ];
        // Keep only the most recent per Opp
        for (talkdesk__Talkdesk_Activity__c a : activities) {
            if (!resultMap.containsKey(a.talkdesk__Opportunity__c)) {
                resultMap.put(a.talkdesk__Opportunity__c, a);
            }
        }
        return resultMap;
    }

    private static Map<Id, Mogli_SMS__SMS__c> queryRecentSms(Set<Id> oppIds) {
        Map<Id, Mogli_SMS__SMS__c> resultMap = new Map<Id, Mogli_SMS__SMS__c>();
        List<Mogli_SMS__SMS__c> messages = [
            SELECT Id, Mogli_SMS__Opportunity__c, Mogli_SMS__Direction__c,
                   Mogli_SMS__Status__c, CreatedDate
            FROM Mogli_SMS__SMS__c
            WHERE Mogli_SMS__Opportunity__c IN :oppIds
              AND Mogli_SMS__Status__c != 'Error'
              AND CreatedDate >= LAST_N_DAYS:7
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate DESC
            LIMIT 1000
        ];
        for (Mogli_SMS__SMS__c m : messages) {
            if (!resultMap.containsKey(m.Mogli_SMS__Opportunity__c)) {
                resultMap.put(m.Mogli_SMS__Opportunity__c, m);
            }
        }
        return resultMap;
    }

    private static Map<Id, Event> queryUpcomingEvents(Set<Id> oppIds) {
        Map<Id, Event> resultMap = new Map<Id, Event>();
        List<Event> events = [
            SELECT Id, WhatId, StartDateTime
            FROM Event
            WHERE WhatId IN :oppIds
              AND StartDateTime >= :Datetime.now()
              AND StartDateTime <= :Datetime.now().addHours(24)
            WITH SECURITY_ENFORCED
            ORDER BY StartDateTime ASC
            LIMIT 1000
        ];
        for (Event e : events) {
            if (!resultMap.containsKey(e.WhatId)) {
                resultMap.put(e.WhatId, e);
            }
        }
        return resultMap;
    }

    private static Map<Id, Task> queryRecentTasks(Set<Id> oppIds) {
        Map<Id, Task> resultMap = new Map<Id, Task>();
        List<Task> tasks = [
            SELECT Id, WhatId, ActivityDate, TaskSubtype, CreatedDate
            FROM Task
            WHERE WhatId IN :oppIds
              AND Status = 'Completed'
            WITH SECURITY_ENFORCED
            ORDER BY ActivityDate DESC, CreatedDate DESC
            LIMIT 1000
        ];
        for (Task t : tasks) {
            if (!resultMap.containsKey(t.WhatId)) {
                resultMap.put(t.WhatId, t);
            }
        }
        return resultMap;
    }

    private static Map<Id, Account_Scoring__c> queryAccountScoring(Set<Id> accountIds) {
        Map<Id, Account_Scoring__c> resultMap = new Map<Id, Account_Scoring__c>();
        if (accountIds.isEmpty()) {
            return resultMap;
        }
        List<Account_Scoring__c> scores = [
            SELECT Id, Account__c, Prob_Payroll_Conversion__c, Prob_Tier_Upgrade__c
            FROM Account_Scoring__c
            WHERE Account__c IN :accountIds
            WITH SECURITY_ENFORCED
            LIMIT 1000
        ];
        for (Account_Scoring__c s : scores) {
            resultMap.put(s.Account__c, s);
        }
        return resultMap;
    }

    private static Map<Id, List<NBA_Queue__c>> queryExistingActions(Set<Id> oppIds) {
        Map<Id, List<NBA_Queue__c>> resultMap = new Map<Id, List<NBA_Queue__c>>();
        // Query active actions AND recent audit records (snoozed/completed/dismissed)
        // so the on-demand evaluation can enforce cooldown + snooze suppression.
        List<NBA_Queue__c> actions = [
            SELECT Id, Opportunity__c, Status__c, Action_Type__c, Priority_Score__c,
                   CreatedDate, Completed_Date__c, Snoozed_Until__c, CooldownUntil__c
            FROM NBA_Queue__c
            WHERE Opportunity__c IN :oppIds
              AND (
                  Status__c IN ('New', 'Pending', 'In Progress', 'Accepted')
                  OR (Status__c = 'Snoozed' AND Snoozed_Until__c > :Datetime.now())
                  OR (Status__c = 'Completed' AND Completed_Date__c >= :Datetime.now().addHours(-1))
                  OR (Status__c = 'Dismissed' AND CooldownUntil__c > :Datetime.now())
              )
            WITH SECURITY_ENFORCED
            LIMIT 1000
        ];
        for (NBA_Queue__c a : actions) {
            if (!resultMap.containsKey(a.Opportunity__c)) {
                resultMap.put(a.Opportunity__c, new List<NBA_Queue__c>());
            }
            resultMap.get(a.Opportunity__c).add(a);
        }
        return resultMap;
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    private static Datetime computeLastValidTouch(Datetime callDate, Datetime smsDate, Datetime taskDate) {
        Datetime latest = null;
        if (callDate != null) {
            latest = callDate;
        }
        if (smsDate != null && (latest == null || smsDate > latest)) {
            latest = smsDate;
        }
        if (taskDate != null && (latest == null || taskDate > latest)) {
            latest = taskDate;
        }
        return latest;
    }
}
