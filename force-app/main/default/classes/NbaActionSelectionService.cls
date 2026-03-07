/**
 * NbaActionSelectionService — Economic ranking for GTM OS engine.
 *
 * Selection hierarchy (PRD Section 8.2):
 *   1. Time-Bound Override — serve immediately, ordered by deadline proximity
 *   2. Timezone Gate — filter out contacts where local time < 9:00 AM
 *   3. Stage Priority — Closing(1) > Consult(2) > Connect(3) > New(4)
 *   4. Expected Incremental ARR — highest economic value within same stage
 *   5. Tiebreaker — oldest Opportunity CreatedDate
 *
 * Called by NbaActionController.evaluateOnDemand() during on-demand evaluation.
 */
public with sharing class NbaActionSelectionService {

    // ─── Result Wrapper ───────────────────────────────────────────────
    public class RankedAction {
        public NBA_Queue__c action;
        public Integer stagePriority;
        public Decimal expectedArr;
        public Boolean isTimeBound;
        public Boolean passedGate;

        public RankedAction(NBA_Queue__c a) {
            this.action = a;
            this.isTimeBound = a.Is_Time_Bound__c == true;
            this.stagePriority = a.Stage_Priority__c != null
                ? Integer.valueOf(a.Stage_Priority__c) : 99;
            this.expectedArr = a.Expected_Incremental_ARR__c != null
                ? a.Expected_Incremental_ARR__c : (a.Priority_Score__c != null ? a.Priority_Score__c : 0);
            this.passedGate = true;
        }
    }

    // ─── Stage Priority Lookup (from CMDT, cached) ──────────────────
    private static Map<String, Integer> stagePriorityMap;

    private static Map<String, Integer> getStagePriorityMap() {
        if (stagePriorityMap == null) {
            stagePriorityMap = new Map<String, Integer>();
            for (NBA_Stage_Priority__mdt sp : [
                SELECT Stage_Name__c, Priority__c
                FROM NBA_Stage_Priority__mdt
            ]) {
                stagePriorityMap.put(sp.Stage_Name__c, Integer.valueOf(sp.Priority__c));
            }
        }
        return stagePriorityMap;
    }

    /**
     * Resolve stage priority for an opportunity stage name.
     * Returns priority integer (1=Closing, 2=Consult, 3=Connect, 4=New).
     * Returns 99 for unknown stages.
     */
    public static Integer resolveStagePriority(String stageName) {
        if (String.isBlank(stageName)) return 99;
        Map<String, Integer> priorities = getStagePriorityMap();
        return priorities.containsKey(stageName) ? priorities.get(stageName) : 99;
    }

    // ─── Primary Entry Point ──────────────────────────────────────────

    /**
     * Select the top-ranked Pending action for an AE.
     * @param aeUserId The AE's User ID
     * @return The best action to serve, or null if none pass gating
     */
    public static NBA_Queue__c selectTop(Id aeUserId) {
        if (aeUserId == null) {
            return null;
        }

        List<NBA_Queue__c> candidates = [
            SELECT Id, Opportunity__c, Status__c, Action_Type__c,
                   Priority_Score__c, Is_Time_Bound__c, DueAt__c,
                   Stage_Priority__c, Expected_Incremental_ARR__c,
                   Execution_Type__c, Action_Tags__c,
                   Workflow_Mode__c, Sales_Rep__c,
                   Action_Instruction__c, ReasonText__c,
                   Opportunity__r.CreatedDate
            FROM NBA_Queue__c
            WHERE Sales_Rep__c = :aeUserId
              AND Status__c = 'Pending'
            WITH SECURITY_ENFORCED
            ORDER BY Stage_Priority__c ASC NULLS LAST,
                     Expected_Incremental_ARR__c DESC NULLS LAST
            LIMIT 20
        ];

        if (candidates.isEmpty()) {
            return null;
        }

        List<RankedAction> ranked = rankActions(candidates);
        return ranked.isEmpty() ? null : ranked[0].action;
    }

    // ─── Full Pipeline ────────────────────────────────────────────────

    /**
     * Apply Time-Bound Override → Timezone Gate → Stage Priority → ARR ranking.
     * Returns sorted list with only passing actions.
     */
    public static List<RankedAction> rankActions(List<NBA_Queue__c> candidates) {
        // Build timezone map from Account.Timezone_Router__c (1 SOQL)
        Map<Id, String> accountTzMap = getAccountTimezoneMap(candidates);

        List<RankedAction> ranked = new List<RankedAction>();

        for (NBA_Queue__c candidate : candidates) {
            RankedAction ra = new RankedAction(candidate);

            // Mode gate (Pipeline only)
            if (candidate.Workflow_Mode__c != null
                && candidate.Workflow_Mode__c != 'Pipeline') {
                ra.passedGate = false;
            }

            // Timezone gate — skip for time-bound actions (meetings always show)
            if (ra.passedGate && !ra.isTimeBound) {
                String tz = accountTzMap.get(candidate.Account__c);
                if (!isLocalTimeAfterGateHour(tz)) {
                    ra.passedGate = false;
                }
            }

            if (ra.passedGate) {
                ranked.add(ra);
            }
        }

        // Sort by new hierarchy
        ranked.sort(new RankedActionComparator());

        return ranked;
    }

    // ─── Timezone Gate ──────────────────────────────────────────────

    @TestVisible
    private static final Integer TZ_GATE_HOUR = 8; // 8:00 AM local time

    private static final Map<String, String> ROUTER_TO_IANA = new Map<String, String>{
        'CST/EST Router' => 'America/Chicago',
        'PST Router'     => 'America/Los_Angeles',
        'MST Router'     => 'America/Denver',
        'Not USA'        => 'America/Chicago'
    };

    private static final String DEFAULT_TZ = 'America/Chicago';

    /**
     * Query Account.Timezone_Router__c for all accounts referenced by candidates.
     */
    private static Map<Id, String> getAccountTimezoneMap(List<NBA_Queue__c> candidates) {
        Set<Id> accountIds = new Set<Id>();
        for (NBA_Queue__c c : candidates) {
            if (c.Account__c != null) {
                accountIds.add(c.Account__c);
            }
        }
        Map<Id, String> tzMap = new Map<Id, String>();
        if (accountIds.isEmpty()) {
            return tzMap;
        }
        for (Account a : [
            SELECT Id, Timezone_Router__c
            FROM Account
            WHERE Id IN :accountIds
            WITH SECURITY_ENFORCED
        ]) {
            tzMap.put(a.Id, resolveIanaTimezone(a.Timezone_Router__c));
        }
        return tzMap;
    }

    /**
     * Map Timezone_Router__c picklist value to IANA timezone ID.
     */
    @TestVisible
    private static String resolveIanaTimezone(String routerValue) {
        if (String.isBlank(routerValue) || !ROUTER_TO_IANA.containsKey(routerValue)) {
            return DEFAULT_TZ;
        }
        return ROUTER_TO_IANA.get(routerValue);
    }

    // Test override: set to control "now" in timezone gate checks
    @TestVisible
    private static Datetime mockNow = null;

    /**
     * Check if the current time in the given IANA timezone is at or after the gate hour.
     */
    @TestVisible
    private static Boolean isLocalTimeAfterGateHour(String ianaTimezone) {
        if (String.isBlank(ianaTimezone)) {
            ianaTimezone = DEFAULT_TZ;
        }
        Datetime now = mockNow != null ? mockNow : Datetime.now();
        // Datetime.format('HH') returns 24-hour hour string in the given timezone
        String hourStr = now.format('HH', ianaTimezone);
        Integer localHour = Integer.valueOf(hourStr);
        return localHour >= TZ_GATE_HOUR;
    }

    // ─── Comparator ───────────────────────────────────────────────────

    private class RankedActionComparator implements System.Comparator<RankedAction> {
        public Integer compare(RankedAction a, RankedAction b) {
            // 1. Time-bound actions always first, ordered by DueAt proximity
            if (a.isTimeBound != b.isTimeBound) {
                return a.isTimeBound ? -1 : 1;
            }
            if (a.isTimeBound && b.isTimeBound) {
                Datetime dueA = a.action.DueAt__c;
                Datetime dueB = b.action.DueAt__c;
                if (dueA != null && dueB != null) {
                    return dueA < dueB ? -1 : (dueA > dueB ? 1 : 0);
                }
                if (dueA != null) return -1;
                if (dueB != null) return 1;
                return 0;
            }

            // 2. Stage priority ascending (1=Closing first)
            if (a.stagePriority != b.stagePriority) {
                return a.stagePriority - b.stagePriority;
            }

            // 3. Expected ARR descending (highest value first)
            if (b.expectedArr > a.expectedArr) return 1;
            if (b.expectedArr < a.expectedArr) return -1;

            // 4. Tiebreaker: oldest Opportunity CreatedDate first
            Datetime createdA = a.action.Opportunity__r?.CreatedDate;
            Datetime createdB = b.action.Opportunity__r?.CreatedDate;
            if (createdA != null && createdB != null) {
                return createdA < createdB ? -1 : (createdA > createdB ? 1 : 0);
            }

            return 0;
        }
    }
}
