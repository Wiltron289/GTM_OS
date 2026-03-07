/**
 * NbaTagService — Tag generation for the GTM OS Action Orchestration Engine.
 *
 * Generates 2-4 prioritization tags per served action explaining WHY this
 * opportunity was prioritized. Tags are read-only context — they don't
 * affect scoring or selection.
 *
 * Tag priority (higher = survives 4-tag cap):
 *   1 = Time-Bound, 2 = Cadence, 3 = Signal (Data Science), 4 = Engagement, 5 = Stage/Economic
 *
 * Called by NbaActionController after ActionWrapper is built.
 * Output is serialized to NBA_Queue__c.Action_Tags__c as JSON.
 *
 * See PRD Section 15 and TAG-TAXONOMY.md for full definitions.
 */
public with sharing class NbaTagService {

    // ─── Constants ────────────────────────────────────────────────────
    private static final Integer MAX_TAGS = 4;

    // Priority tiers (lower number = higher priority = survives cap)
    private static final Integer PRIORITY_TIME_BOUND = 1;
    private static final Integer PRIORITY_CADENCE = 2;
    private static final Integer PRIORITY_SIGNAL = 3;
    private static final Integer PRIORITY_ENGAGEMENT = 4;
    private static final Integer PRIORITY_STAGE = 5;

    // Thresholds
    private static final Decimal HIGH_WIN_THRESHOLD = 0.70;
    private static final Decimal PAYROLL_READY_THRESHOLD = 0.60;
    private static final Decimal HIGH_VALUE_THRESHOLD = 500; // $500 MRR
    private static final Integer LATE_STAGE_DAYS = 14;
    private static final Integer CONNECTED_RECENTLY_DAYS = 7;
    private static final Integer NO_CONTACT_DAYS = 5;
    private static final Integer NO_CONTACT_MIN_ATTEMPTS = 3;
    private static final Integer INBOUND_REPLY_HOURS = 48;

    // ─── Tag Inner Class ──────────────────────────────────────────────

    public class Tag implements Comparable {
        public String id;
        public String category;
        public String chip;
        public String expanded;
        public Integer priority;

        public Tag(String id, String category, String chip, String expanded, Integer priority) {
            this.id = id;
            this.category = category;
            this.chip = chip;
            this.expanded = expanded;
            this.priority = priority;
        }

        public Integer compareTo(Object other) {
            Tag otherTag = (Tag) other;
            return this.priority - otherTag.priority;
        }
    }

    // ─── Primary Entry Point ──────────────────────────────────────────

    /**
     * Generate up to 4 prioritized tags for the given action.
     *
     * @param wrapper The built ActionWrapper with action context
     * @param signal  The OpportunitySignal with CRM data
     * @return List of Tag objects sorted by priority, capped at 4
     */
    public static List<Tag> generateTags(
        NbaActionController.ActionWrapper wrapper,
        NbaSignalService.OpportunitySignal signal
    ) {
        List<Tag> candidates = new List<Tag>();

        if (wrapper == null || signal == null) {
            return candidates;
        }

        // 1. Time-Bound tags (priority 1)
        addTimeBoundTags(candidates, wrapper, signal);

        // 2. Cadence tags (priority 2)
        addCadenceTags(candidates, wrapper);

        // 3. Data Science signal tags (priority 3)
        addSignalTags(candidates, signal);

        // 4. Engagement tags (priority 4)
        addEngagementTags(candidates, signal);

        // 5. Stage/Economic tags (priority 5)
        addStageTags(candidates, wrapper, signal);

        // Sort by priority (ascending = highest priority first)
        candidates.sort();

        // Cap at MAX_TAGS
        List<Tag> result = new List<Tag>();
        for (Integer i = 0; i < Math.min(candidates.size(), MAX_TAGS); i++) {
            result.add(candidates[i]);
        }

        return result;
    }

    /**
     * Serialize a list of tags to JSON for storage in Action_Tags__c.
     */
    public static String toJson(List<Tag> tags) {
        if (tags == null || tags.isEmpty()) {
            return null;
        }
        List<Map<String, Object>> tagList = new List<Map<String, Object>>();
        for (Tag t : tags) {
            Map<String, Object> tagMap = new Map<String, Object>();
            tagMap.put('id', t.id);
            tagMap.put('category', t.category);
            tagMap.put('chip', t.chip);
            tagMap.put('expanded', t.expanded);
            tagMap.put('priority', t.priority);
            tagList.add(tagMap);
        }
        return JSON.serialize(tagList);
    }

    // ─── Tag Generators ───────────────────────────────────────────────

    private static void addTimeBoundTags(
        List<Tag> candidates,
        NbaActionController.ActionWrapper wrapper,
        NbaSignalService.OpportunitySignal signal
    ) {
        // TB-01: Meeting Upcoming
        if (wrapper.isTimeBound == true && wrapper.actionType == 'Meeting' && wrapper.dueAt != null) {
            Long minutesUntil = getMinutesBetween(Datetime.now(), wrapper.dueAt);
            candidates.add(new Tag(
                'TB-01', 'Time-Bound', 'Meeting Upcoming',
                'You have a meeting in ' + minutesUntil + ' minutes',
                PRIORITY_TIME_BOUND
            ));
        }

        // TB-02: SLA Active
        if (signal.hoursSinceAssignment != null && signal.hoursSinceAssignment < 1) {
            Long minutesSince = (Long)(signal.hoursSinceAssignment * 60);
            candidates.add(new Tag(
                'TB-02', 'Time-Bound', 'SLA Active',
                'New opportunity assigned ' + minutesSince + ' minutes ago — respond within SLA window',
                PRIORITY_TIME_BOUND
            ));
        }

        // TB-03: Follow-Up Due (detected via action type)
        if (wrapper.actionType == 'Follow Up' && wrapper.isTimeBound == true) {
            candidates.add(new Tag(
                'TB-03', 'Time-Bound', 'Follow-Up Due',
                'Your scheduled follow-up is now due',
                PRIORITY_TIME_BOUND
            ));
        }
    }

    private static void addCadenceTags(
        List<Tag> candidates,
        NbaActionController.ActionWrapper wrapper
    ) {
        if (wrapper.isCadenceAction != true) {
            return;
        }

        Integer stepNum = wrapper.cadenceStepNumber;
        Integer totalSteps = wrapper.cadenceTotalSteps;
        String method = wrapper.stepMethod;

        // CD-02: First Touch (Step 1, no prior activity)
        if (stepNum != null && stepNum == 1) {
            candidates.add(new Tag(
                'CD-02', 'Cadence', 'First Touch',
                'First outreach attempt for this opportunity — no prior contact',
                PRIORITY_CADENCE
            ));
        }
        // CD-01: Call Attempt {N} (for Call steps beyond step 1)
        else if (method == 'Call' && stepNum != null) {
            candidates.add(new Tag(
                'CD-01', 'Cadence', 'Call Attempt ' + stepNum,
                'Attempt ' + stepNum + ' of ' + (totalSteps != null ? String.valueOf(totalSteps) : '?') + ' in cadence',
                PRIORITY_CADENCE
            ));
        }

        // CD-04: Last Attempt
        if (stepNum != null && totalSteps != null && stepNum == totalSteps) {
            candidates.add(new Tag(
                'CD-04', 'Cadence', 'Last Attempt',
                'Final attempt in cadence — breakup step',
                PRIORITY_CADENCE
            ));
        }

        // CD-03: Cadence Day context (from progress text)
        if (wrapper.cadenceProgress != null && stepNum != null && stepNum > 1 && stepNum < totalSteps) {
            candidates.add(new Tag(
                'CD-03', 'Cadence', 'Step ' + stepNum + '/' + totalSteps,
                wrapper.cadenceProgress,
                PRIORITY_CADENCE
            ));
        }

        // CD-05: Re-engaged (if cadence name contains Re_engage)
        if (wrapper.cadenceName != null && wrapper.cadenceName.containsIgnoreCase('Re_engage')) {
            candidates.add(new Tag(
                'CD-05', 'Cadence', 'Re-engaged',
                'Cadence resumed — re-engagement outreach',
                PRIORITY_CADENCE
            ));
        }
    }

    private static void addSignalTags(
        List<Tag> candidates,
        NbaSignalService.OpportunitySignal signal
    ) {
        if (!signal.hasAccountScoring) {
            return;
        }

        // DS-01: High Win Likelihood
        if (signal.likelihoodToWin != null && signal.likelihoodToWin > HIGH_WIN_THRESHOLD) {
            Integer pct = (Integer)(signal.likelihoodToWin * 100);
            candidates.add(new Tag(
                'DS-01', 'Signal', 'High Win Likelihood',
                'Data model scores this account at ' + pct + '% probability of conversion',
                PRIORITY_SIGNAL
            ));
        }

        // DS-06: Payroll Ready
        if (signal.probPayrollConversion != null && signal.probPayrollConversion > PAYROLL_READY_THRESHOLD) {
            candidates.add(new Tag(
                'DS-06', 'Signal', 'Payroll Ready',
                'Account signals readiness for payroll product adoption',
                PRIORITY_SIGNAL
            ));
        }

        // DS-03: Tier Upgrade (using probTierUpgrade as proxy)
        if (signal.probTierUpgrade != null && signal.probTierUpgrade > 0.5) {
            candidates.add(new Tag(
                'DS-03', 'Signal', 'Tier Upgrade',
                'Account trending toward tier upgrade based on usage patterns',
                PRIORITY_SIGNAL
            ));
        }
    }

    private static void addEngagementTags(
        List<Tag> candidates,
        NbaSignalService.OpportunitySignal signal
    ) {
        // EN-01: Inbound Reply
        if (signal.hadIncomingReply && signal.lastSmsDate != null) {
            Long hoursSince = getHoursBetween(signal.lastSmsDate, Datetime.now());
            if (hoursSince <= INBOUND_REPLY_HOURS) {
                candidates.add(new Tag(
                    'EN-01', 'Engagement', 'Inbound Reply',
                    'Contact replied to SMS ' + hoursSince + ' hours ago — no follow-up yet',
                    PRIORITY_ENGAGEMENT
                ));
            }
        }

        // EN-02: Connected Recently
        if (signal.hadConnectedCall && signal.lastCallDate != null) {
            Long daysSince = getDaysBetween(signal.lastCallDate, Datetime.now());
            if (daysSince <= CONNECTED_RECENTLY_DAYS && daysSince >= 1) {
                candidates.add(new Tag(
                    'EN-02', 'Engagement', 'Connected Recently',
                    'Connected ' + daysSince + ' days ago — follow-up window open',
                    PRIORITY_ENGAGEMENT
                ));
            }
        }

        // EN-03: No Contact
        if (!signal.hadConnectedCall && signal.todayCallCount != null && signal.todayCallCount >= NO_CONTACT_MIN_ATTEMPTS) {
            Decimal daysSince = signal.daysSinceLastInteraction != null ? signal.daysSinceLastInteraction : 0;
            if (daysSince >= NO_CONTACT_DAYS) {
                candidates.add(new Tag(
                    'EN-03', 'Engagement', 'No Contact',
                    'No successful connection in ' + daysSince.intValue() + ' days across ' + signal.todayCallCount + ' attempts',
                    PRIORITY_ENGAGEMENT
                ));
            }
        }
    }

    private static void addStageTags(
        List<Tag> candidates,
        NbaActionController.ActionWrapper wrapper,
        NbaSignalService.OpportunitySignal signal
    ) {
        // ST-01: Late Stage (opportunity stuck)
        if (signal.daysSinceLastInteraction != null
            && signal.daysSinceLastInteraction >= LATE_STAGE_DAYS
            && signal.daysSinceLastInteraction < 99999
            && signal.stageName != null) {
            candidates.add(new Tag(
                'ST-01', 'Stage', 'Late Stage',
                'Opportunity in ' + signal.stageName + ' for ' + signal.daysSinceLastInteraction.intValue() + ' days — at risk of stalling',
                PRIORITY_STAGE
            ));
        }

        // ST-03: High Value
        if (signal.incrementalIfWon != null && signal.incrementalIfWon > HIGH_VALUE_THRESHOLD) {
            candidates.add(new Tag(
                'ST-03', 'Economic', 'High Value',
                'This opportunity represents $' + signal.incrementalIfWon.intValue() + ' incremental MRR',
                PRIORITY_STAGE
            ));
        } else if (signal.mrr != null && signal.mrr > HIGH_VALUE_THRESHOLD) {
            candidates.add(new Tag(
                'ST-03', 'Economic', 'High Value',
                'This opportunity represents $' + signal.mrr.intValue() + ' MRR',
                PRIORITY_STAGE
            ));
        }
    }

    // ─── Utilities ────────────────────────────────────────────────────

    private static Long getMinutesBetween(Datetime dt1, Datetime dt2) {
        Long ms = Math.abs(dt2.getTime() - dt1.getTime());
        return ms / 60000;
    }

    private static Long getHoursBetween(Datetime dt1, Datetime dt2) {
        Long ms = Math.abs(dt2.getTime() - dt1.getTime());
        return ms / 3600000;
    }

    private static Long getDaysBetween(Datetime dt1, Datetime dt2) {
        Long ms = Math.abs(dt2.getTime() - dt1.getTime());
        return ms / 86400000;
    }
}
