/**
 * NbaActionCreationService — Rule evaluation and candidate action creation
 * for the NBA V2 Action Orchestration Engine.
 *
 * Evaluates OpportunitySignals against suppression, urgency, and impact rules
 * from Custom Metadata Types, then creates candidate NBA_Queue__c records
 * with Status = 'Pending'.
 *
 * Called by NbaActionCreationSchedulable on a 10-minute cadence.
 */
public with sharing class NbaActionCreationService {

    // ─── Constants ────────────────────────────────────────────────────
    private static final Decimal DEFAULT_MRR_CEILING = 50000;
    private static final Decimal DEFAULT_CLOSE_PROB = 0.30;
    private static final Decimal MAX_URGENCY_CAP = 2.0;
    private static final Decimal BASE_URGENCY = 0.5;

    // Inactivity thresholds (days)
    private static final Decimal FIRST_TOUCH_INACTIVITY = 99999;
    private static final Decimal FIRST_TOUCH_HOURS_THRESHOLD = 1;
    private static final Integer LATE_STAGE_INACTIVITY_DAYS = 3;
    private static final Integer LATE_STAGE_MIN = 4;
    private static final Integer REENGAGE_INACTIVITY_DAYS = 5;
    private static final Integer CONNECTED_FOLLOWUP_HOURS = 4;

    // Bucket thresholds
    private static final Decimal HIGH_IMPACT_THRESHOLD = 0.7;
    private static final Integer NEGLECTED_DAYS = 7;

    // ─── Result Wrapper ───────────────────────────────────────────────
    public class CreationResult {
        public List<NBA_Queue__c> actionsToCreate;
        public List<String> suppressedReasons;
        public Integer oppCount;
        public Integer createdCount;
        public Integer suppressedCount;

        public CreationResult() {
            this.actionsToCreate = new List<NBA_Queue__c>();
            this.suppressedReasons = new List<String>();
            this.oppCount = 0;
            this.createdCount = 0;
            this.suppressedCount = 0;
        }
    }

    // ─── Primary Entry Point ──────────────────────────────────────────

    /**
     * Evaluate signals and create candidate NBA_Queue__c actions.
     * Loads all CMDT rules once (0 SOQL), then evaluates each signal.
     * DML is NOT performed here — the caller inserts actionsToCreate.
     * @param signals Map of Opp ID to OpportunitySignal from NbaSignalService
     * @return CreationResult containing actions to insert and diagnostics
     */
    public static CreationResult evaluateAndCreate(
        Map<Id, NbaSignalService.OpportunitySignal> signals
    ) {
        CreationResult result = new CreationResult();
        if (signals == null || signals.isEmpty()) {
            return result;
        }

        // Load all CMDT rules (cached, 0 SOQL)
        List<NBA_Suppression_Rule__mdt> suppressionRules = [
            SELECT Rule_Name__c, Condition__c, Suppression_Window_Hours__c,
                   Is_Active__c, Description__c
            FROM NBA_Suppression_Rule__mdt
            WHERE Is_Active__c = true
        ];
        List<NBA_Urgency_Rule__mdt> urgencyRules = [
            SELECT Rule_Name__c, Signal_Type__c, Stage_Minimum__c,
                   Threshold_Days__c, Urgency_Multiplier__c, Is_Active__c
            FROM NBA_Urgency_Rule__mdt
            WHERE Is_Active__c = true
        ];
        NBA_Impact_Weight__mdt weights = getActiveImpactWeights();

        // Calculate max MRR across all signals for normalization
        Decimal maxMrr = calculateMaxMrr(signals.values());

        result.oppCount = signals.size();

        for (NbaSignalService.OpportunitySignal signal : signals.values()) {
            // Step 1: Suppression check
            String suppressReason = checkSuppression(signal, suppressionRules);
            if (suppressReason != null) {
                result.suppressedReasons.add(signal.oppId + ': ' + suppressReason);
                result.suppressedCount++;
                continue;
            }

            // Step 2: Determine action type
            String actionType = determineActionType(signal);

            // Phase 6: Cadence integration for First Touch
            NbaCadenceService.CadenceStep cadenceStep = null;
            if (actionType == 'First Touch') {
                // Resolve AE variant from Hierarchy Custom Setting (0 SOQL)
                String variant = 'A';
                NBA_AE_Config__c aeConfig = NBA_AE_Config__c.getInstance(signal.ownerId);
                if (aeConfig != null && String.isNotBlank(aeConfig.Cadence_Variant__c)) {
                    variant = aeConfig.Cadence_Variant__c;
                }
                cadenceStep = NbaCadenceService.getCurrentStep(signal, variant);
                // If cadence suppresses (spacing/cap/complete), fall through to non-cadence type
                if (cadenceStep == null) {
                    actionType = determineNonCadenceActionType(signal);
                    if (actionType == null) {
                        result.suppressedReasons.add(signal.oppId + ': Cadence suppressed, no fallback');
                        result.suppressedCount++;
                        continue;
                    }
                }
            }

            // Step 3: Calculate scores
            Decimal impactScore = calculateImpactScore(signal, maxMrr, weights);
            Decimal urgencyScore = calculateUrgencyScore(signal, actionType, urgencyRules);
            Decimal finalScore = (weights.Impact_vs_Urgency_Impact_Weight__c * impactScore)
                + (weights.Impact_vs_Urgency_Urgency_Weight__c * urgencyScore);

            // Step 4: Assign bucket and layer
            String bucket = assignBucket(signal, actionType, impactScore);
            String layer = assignLayer(signal, actionType);

            // Step 5: Build the action record
            String instruction;
            String ruleName;
            Integer cadenceStageVal = 1;
            Integer attemptCountVal = 0;
            String lastMethodVal = 'Call';

            if (cadenceStep != null) {
                // Use cadence step values
                instruction = cadenceStep.instruction;
                ruleName = cadenceStep.ruleName;
                cadenceStageVal = cadenceStep.cadenceStage;
                attemptCountVal = cadenceStep.todayCalls != null ? cadenceStep.todayCalls : 0;
                lastMethodVal = cadenceStep.method;
            } else {
                instruction = buildInstruction(signal, actionType);
                ruleName = actionType + '_Auto';
            }

            String reasonText = buildReasonText(signal, actionType, impactScore, urgencyScore);

            NBA_Queue__c action = new NBA_Queue__c(
                Opportunity__c = signal.oppId,
                Account__c = signal.accountId,
                Sales_Rep__c = signal.ownerId,
                Status__c = 'Pending',
                Action_Type__c = actionType,
                Impact_Score__c = impactScore,
                Urgency_Score__c = urgencyScore,
                Priority_Score__c = finalScore,
                Priority_Bucket__c = bucket,
                Priority_Layer__c = layer,
                Is_Time_Bound__c = (layer == 'Layer 1 - Time Bound'),
                Cadence_Stage__c = cadenceStageVal,
                Attempt_Count_Today__c = attemptCountVal,
                Last_Attempt_Method__c = lastMethodVal,
                Source_Path__c = 'Pipeline Cadence',
                Rule_Name__c = ruleName,
                Action_Instruction__c = instruction,
                Workflow_Mode__c = 'Pipeline',
                ReasonText__c = reasonText,
                LastEvaluatedAt__c = Datetime.now(),
                UniqueKey__c = buildUniqueKey(signal.oppId, actionType),
                Opportunity_Stage__c = signal.stageName,
                Due_Date__c = Date.today()
            );

            result.actionsToCreate.add(action);
            result.createdCount++;
        }

        return result;
    }

    // ─── Time-Bound Action Creation (Phase 4 — Trigger-Based) ────────

    /**
     * Create a Layer 1 time-bound action for an upcoming meeting.
     * Used by EventTriggerHandler when a meeting is scheduled on an Opportunity.
     * Does NOT insert the record — caller handles DML for bulkification.
     *
     * @param oppId Opportunity ID the meeting is linked to
     * @param accountId Account ID for the action
     * @param aeId Sales Rep (AE) User ID
     * @param dueAt The meeting start time (sets DueAt__c)
     * @param eventId Event record ID (used in UniqueKey for dedup)
     * @param instruction Human-readable action instruction
     * @return NBA_Queue__c record ready for insert, or null if duplicate exists
     */
    public static NBA_Queue__c createTimeBoundAction(
        Id oppId, Id accountId, Id aeId, Datetime dueAt, Id eventId, String instruction
    ) {
        // Dedup check: one action per Event
        String uniqueKey = 'V2|' + oppId + '|Meeting|' + eventId;
        List<NBA_Queue__c> existing = [
            SELECT Id FROM NBA_Queue__c
            WHERE UniqueKey__c = :uniqueKey
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return null;
        }

        // Simplified scoring: query Opp Amount for impact, use high urgency for time-bound
        Decimal impactScore = 0.5; // default mid-range
        Decimal urgencyScore = 1.5; // high — time-bound actions are urgent
        Decimal oppAmount = 0;
        String stageName = '';

        List<Opportunity> opps = [
            SELECT Amount, MRR__c, StageName
            FROM Opportunity
            WHERE Id = :oppId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!opps.isEmpty()) {
            Opportunity opp = opps[0];
            oppAmount = opp.MRR__c != null ? opp.MRR__c : (opp.Amount != null ? opp.Amount : 0);
            stageName = opp.StageName;
            // Simple impact: normalize against ceiling
            impactScore = Math.min(oppAmount / DEFAULT_MRR_CEILING, 1.0);
        }

        Decimal finalScore = (0.5 * impactScore) + (0.5 * urgencyScore);

        NBA_Queue__c action = new NBA_Queue__c(
            Opportunity__c = oppId,
            Account__c = accountId,
            Sales_Rep__c = aeId,
            Status__c = 'Pending',
            Action_Type__c = 'Meeting',
            Impact_Score__c = impactScore,
            Urgency_Score__c = urgencyScore,
            Priority_Score__c = finalScore,
            Priority_Bucket__c = 'Cadence Due Today',
            Priority_Layer__c = 'Layer 1 - Time Bound',
            Is_Time_Bound__c = true,
            DueAt__c = dueAt,
            Cadence_Stage__c = 1,
            Attempt_Count_Today__c = 0,
            Source_Path__c = 'Immediate',
            Rule_Name__c = 'Meeting_TimeBound',
            Action_Instruction__c = instruction != null ? instruction.left(255) : 'Prepare for upcoming meeting',
            Workflow_Mode__c = 'Pipeline',
            ReasonText__c = 'Time-bound meeting action. Prepare context before the call.',
            LastEvaluatedAt__c = Datetime.now(),
            UniqueKey__c = uniqueKey,
            Opportunity_Stage__c = stageName,
            Due_Date__c = dueAt.date()
        );

        return action;
    }

    /**
     * Update an existing time-bound action's due time (meeting rescheduled).
     * @param eventId The Event record ID to look up the action
     * @param oppId The Opportunity the event is linked to
     * @param newDueAt The new meeting start time
     * @return Updated NBA_Queue__c, or null if no matching action found
     */
    public static NBA_Queue__c updateTimeBoundAction(Id eventId, Id oppId, Datetime newDueAt) {
        String uniqueKey = 'V2|' + oppId + '|Meeting|' + eventId;
        List<NBA_Queue__c> actions = [
            SELECT Id, DueAt__c, Due_Date__c, Status__c
            FROM NBA_Queue__c
            WHERE UniqueKey__c = :uniqueKey
              AND Status__c IN ('New', 'Pending', 'In Progress', 'Accepted')
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (actions.isEmpty()) {
            return null;
        }

        NBA_Queue__c action = actions[0];
        action.DueAt__c = newDueAt;
        action.Due_Date__c = newDueAt.date();
        action.LastEvaluatedAt__c = Datetime.now();
        return action;
    }

    /**
     * Cancel a time-bound action (meeting deleted/cancelled).
     * Sets Status to 'Expired' so it no longer surfaces.
     * @param eventId The Event record ID
     * @param oppId The Opportunity the event was linked to
     * @return Expired NBA_Queue__c, or null if no matching action found
     */
    public static NBA_Queue__c cancelTimeBoundAction(Id eventId, Id oppId) {
        String uniqueKey = 'V2|' + oppId + '|Meeting|' + eventId;
        List<NBA_Queue__c> actions = [
            SELECT Id, Status__c, UniqueKey__c
            FROM NBA_Queue__c
            WHERE UniqueKey__c = :uniqueKey
              AND Status__c IN ('New', 'Pending', 'In Progress', 'Accepted')
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (actions.isEmpty()) {
            return null;
        }

        NBA_Queue__c action = actions[0];
        action.Status__c = 'Expired';
        action.UniqueKey__c = null; // Clear so it can be recreated if meeting is re-added
        action.LastEvaluatedAt__c = Datetime.now();
        return action;
    }

    // ─── Suppression Logic ────────────────────────────────────────────

    /**
     * Check suppression rules against a signal. Returns the suppression reason
     * string if suppressed, null if the Opp is eligible for action creation.
     */
    @TestVisible
    private static String checkSuppression(
        NbaSignalService.OpportunitySignal signal,
        List<NBA_Suppression_Rule__mdt> rules
    ) {
        // Hard-coded checks that map to CMDT conditions
        for (NBA_Suppression_Rule__mdt rule : rules) {
            if (rule.Condition__c == 'Closed Opportunity' && signal.isClosed) {
                return rule.Rule_Name__c;
            }
            if (rule.Condition__c == 'Active Action Exists' && signal.hasActiveAction) {
                return rule.Rule_Name__c;
            }
            if (rule.Condition__c == 'Upcoming Meeting' && signal.hasUpcomingMeeting) {
                return rule.Rule_Name__c;
            }
            if (rule.Condition__c == 'Recent Valid Touch' && signal.lastValidTouchDate != null) {
                Long msSinceTouch = Math.abs(
                    Datetime.now().getTime() - signal.lastValidTouchDate.getTime()
                );
                Decimal hoursSinceTouch = Decimal.valueOf(msSinceTouch).divide(3600000, 2);
                if (rule.Suppression_Window_Hours__c != null
                    && hoursSinceTouch < rule.Suppression_Window_Hours__c) {
                    return rule.Rule_Name__c;
                }
            }
            // Phase 5: Suppress if there's a snoozed audit record still active
            if (rule.Condition__c == 'Snoozed Action Exists'
                && signal.hasSnoozedAction
                && signal.snoozedUntilDate != null
                && signal.snoozedUntilDate > Datetime.now()) {
                return rule.Rule_Name__c;
            }
            // Phase 5: Suppress if recently completed (cooldown window)
            if (rule.Condition__c == 'Recent Completion' && signal.lastCompletedDate != null) {
                Long msSinceComplete = Math.abs(
                    Datetime.now().getTime() - signal.lastCompletedDate.getTime()
                );
                Decimal hoursSinceComplete = Decimal.valueOf(msSinceComplete).divide(3600000, 2);
                if (rule.Suppression_Window_Hours__c != null
                    && hoursSinceComplete < rule.Suppression_Window_Hours__c) {
                    return rule.Rule_Name__c;
                }
            }
        }
        return null;
    }

    // ─── Action Type Determination ────────────────────────────────────

    @TestVisible
    private static String determineActionType(NbaSignalService.OpportunitySignal signal) {
        // Priority 1: First Touch — brand new Opp, never contacted
        if (signal.daysSinceLastInteraction != null
            && signal.daysSinceLastInteraction >= FIRST_TOUCH_INACTIVITY) {
            return 'First Touch';
        }
        if (signal.hoursSinceAssignment != null
            && signal.hoursSinceAssignment <= FIRST_TOUCH_HOURS_THRESHOLD
            && signal.lastValidTouchDate == null) {
            return 'First Touch';
        }

        // Priority 2: Connected follow-up within 4 hours
        if (signal.hadConnectedCall && signal.lastCallDate != null) {
            Long msSinceCall = Datetime.now().getTime() - signal.lastCallDate.getTime();
            Decimal hoursSinceCall = Decimal.valueOf(msSinceCall).divide(3600000, 2);
            if (hoursSinceCall <= CONNECTED_FOLLOWUP_HOURS) {
                return 'Stage Progression';
            }
        }

        // Priority 3: Late-stage inactivity (Stage 4+ with 3+ days)
        if (signal.stageNumber >= LATE_STAGE_MIN
            && signal.daysSinceLastInteraction != null
            && signal.daysSinceLastInteraction >= LATE_STAGE_INACTIVITY_DAYS) {
            return 'Stage Progression';
        }

        // Priority 4: Re-engage — any stage with 5+ days inactivity
        if (signal.daysSinceLastInteraction != null
            && signal.daysSinceLastInteraction >= REENGAGE_INACTIVITY_DAYS) {
            return 'Re-engage';
        }

        // Default: General follow-up
        return 'Follow Up';
    }

    /**
     * Determine a non-cadence action type when cadence suppresses First Touch.
     * Skips First Touch checks, only returns Stage Progression / Re-engage / Follow Up.
     * Returns null if no alternative action type applies (signal too fresh).
     */
    @TestVisible
    private static String determineNonCadenceActionType(NbaSignalService.OpportunitySignal signal) {
        // Connected follow-up within 4 hours
        if (signal.hadConnectedCall && signal.lastCallDate != null) {
            Long msSinceCall = Datetime.now().getTime() - signal.lastCallDate.getTime();
            Decimal hoursSinceCall = Decimal.valueOf(msSinceCall).divide(3600000, 2);
            if (hoursSinceCall <= CONNECTED_FOLLOWUP_HOURS) {
                return 'Stage Progression';
            }
        }

        // Late-stage inactivity
        if (signal.stageNumber >= LATE_STAGE_MIN
            && signal.daysSinceLastInteraction != null
            && signal.daysSinceLastInteraction >= LATE_STAGE_INACTIVITY_DAYS) {
            return 'Stage Progression';
        }

        // Re-engage
        if (signal.daysSinceLastInteraction != null
            && signal.daysSinceLastInteraction >= REENGAGE_INACTIVITY_DAYS) {
            return 'Re-engage';
        }

        // No fallback available — suppress entirely
        return null;
    }

    // ─── Scoring ──────────────────────────────────────────────────────

    @TestVisible
    private static Decimal calculateImpactScore(
        NbaSignalService.OpportunitySignal signal,
        Decimal maxMrr,
        NBA_Impact_Weight__mdt weights
    ) {
        // Normalize MRR to 0-1
        Decimal mrrValue = signal.mrr != null ? signal.mrr
            : (signal.amount != null ? signal.amount : 0);
        Decimal normalizedMrr = maxMrr > 0 ? Math.min(mrrValue / maxMrr, 1.0) : 0;

        // Close probability: Account_Scoring if available, else Deal_Stage_Probability
        Decimal closeProb;
        if (signal.hasAccountScoring && signal.probPayrollConversion != null) {
            closeProb = signal.probPayrollConversion / 100;
        } else if (signal.dealStageProbability != null) {
            closeProb = signal.dealStageProbability / 100;
        } else {
            closeProb = DEFAULT_CLOSE_PROB;
        }
        closeProb = Math.min(closeProb, 1.0);

        return (weights.MRR_Weight__c * normalizedMrr)
            + (weights.Close_Probability_Weight__c * closeProb);
    }

    @TestVisible
    private static Decimal calculateUrgencyScore(
        NbaSignalService.OpportunitySignal signal,
        String actionType,
        List<NBA_Urgency_Rule__mdt> urgencyRules
    ) {
        Decimal urgency = BASE_URGENCY;

        for (NBA_Urgency_Rule__mdt rule : urgencyRules) {
            // SLA urgency for First Touch
            if (rule.Signal_Type__c == 'SLA' && actionType == 'First Touch') {
                urgency *= rule.Urgency_Multiplier__c;
                continue;
            }

            // Inactivity-based urgency
            if (rule.Signal_Type__c == 'Inactivity'
                && signal.daysSinceLastInteraction != null
                && signal.daysSinceLastInteraction >= rule.Threshold_Days__c) {
                Integer stageMin = parseStageMinimum(rule.Stage_Minimum__c);
                if (signal.stageNumber >= stageMin) {
                    urgency *= rule.Urgency_Multiplier__c;
                }
                continue;
            }

            // Stage pressure
            if (rule.Signal_Type__c == 'Stage Pressure') {
                Integer stageMin = parseStageMinimum(rule.Stage_Minimum__c);
                if (signal.stageNumber >= stageMin) {
                    urgency *= rule.Urgency_Multiplier__c;
                }
            }
        }

        return Math.min(urgency, MAX_URGENCY_CAP);
    }

    // ─── Bucket & Layer Assignment ────────────────────────────────────

    @TestVisible
    private static String assignBucket(
        NbaSignalService.OpportunitySignal signal,
        String actionType,
        Decimal impactScore
    ) {
        if (actionType == 'First Touch'
            && signal.hoursSinceAssignment != null
            && signal.hoursSinceAssignment <= FIRST_TOUCH_HOURS_THRESHOLD) {
            return 'Cadence Due Today';
        }
        if (signal.stageNumber >= LATE_STAGE_MIN
            && signal.daysSinceLastInteraction != null
            && signal.daysSinceLastInteraction >= LATE_STAGE_INACTIVITY_DAYS) {
            return 'Late-Stage Stalled';
        }
        if (impactScore >= HIGH_IMPACT_THRESHOLD) {
            return 'High Impact Focus';
        }
        if (signal.daysSinceLastInteraction != null
            && signal.daysSinceLastInteraction >= NEGLECTED_DAYS) {
            return 'Neglected';
        }
        return 'General Pipeline';
    }

    @TestVisible
    private static String assignLayer(
        NbaSignalService.OpportunitySignal signal,
        String actionType
    ) {
        if (actionType == 'First Touch'
            && signal.hoursSinceAssignment != null
            && signal.hoursSinceAssignment <= FIRST_TOUCH_HOURS_THRESHOLD) {
            return 'Layer 1 - Time Bound';
        }
        // Blitz mode check (Phase 5 — currently defaults to Pipeline)
        return 'Layer 3 - Impact+Urgency';
    }

    // ─── Instruction & Reason Builders ────────────────────────────────

    private static String buildInstruction(
        NbaSignalService.OpportunitySignal signal,
        String actionType
    ) {
        String instruction;
        // Method escalation: if last attempt was a no-connect, suggest alternate method
        String methodHint = getMethodEscalationHint(signal);

        if (actionType == 'First Touch') {
            instruction = 'Make initial contact — new opportunity assigned';
        } else if (actionType == 'Stage Progression') {
            if (signal.hadConnectedCall) {
                instruction = 'Follow up on connected call — keep momentum';
            } else {
                instruction = 'Re-engage late-stage opportunity — ' + signal.stageName + ' stalled';
            }
        } else if (actionType == 'Re-engage') {
            Integer days = signal.daysSinceLastInteraction != null
                ? signal.daysSinceLastInteraction.intValue() : 0;
            instruction = 'Re-engage cold deal — ' + days + ' days since last interaction';
        } else {
            instruction = 'Follow up on pipeline opportunity';
        }

        // Append method escalation hint if applicable
        if (String.isNotBlank(methodHint)) {
            instruction += ' [' + methodHint + ']';
        }

        // Truncate to field length (255)
        if (instruction.length() > 255) {
            instruction = instruction.substring(0, 252) + '...';
        }
        return instruction;
    }

    private static String buildReasonText(
        NbaSignalService.OpportunitySignal signal,
        String actionType,
        Decimal impactScore,
        Decimal urgencyScore
    ) {
        String reason = actionType + ' action. ';
        reason += 'Impact: ' + impactScore.setScale(2) + ', ';
        reason += 'Urgency: ' + urgencyScore.setScale(2) + '. ';

        if (signal.hasAccountScoring) {
            reason += 'ML scoring available (Prob: '
                + (signal.probPayrollConversion != null ? signal.probPayrollConversion + '%' : 'N/A')
                + '). ';
        }

        if (signal.daysSinceLastInteraction != null
            && signal.daysSinceLastInteraction < FIRST_TOUCH_INACTIVITY) {
            reason += signal.daysSinceLastInteraction.intValue() + 'd since last interaction.';
        }

        return reason;
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    private static String buildUniqueKey(Id oppId, String actionType) {
        return 'V2|' + oppId + '|' + actionType;
    }

    /**
     * Parse stage minimum from CMDT value like "Stage 4+" → 4.
     * Returns 0 if null or unparseable (matches any stage).
     */
    private static Integer parseStageMinimum(String stageMin) {
        if (String.isBlank(stageMin)) {
            return 0;
        }
        // Extract digits from strings like "Stage 4+", "Stage 3+"
        String digits = stageMin.replaceAll('[^0-9]', '');
        if (String.isNotBlank(digits)) {
            return Integer.valueOf(digits);
        }
        return 0;
    }

    private static Decimal calculateMaxMrr(List<NbaSignalService.OpportunitySignal> signals) {
        Decimal maxMrr = DEFAULT_MRR_CEILING;
        for (NbaSignalService.OpportunitySignal sig : signals) {
            Decimal val = sig.mrr != null ? sig.mrr : (sig.amount != null ? sig.amount : 0);
            if (val > maxMrr) {
                maxMrr = val;
            }
        }
        return maxMrr;
    }

    /**
     * Method escalation: if the last call was a no-connect (Attempted-LVM or
     * Attempted-NVM), suggest an alternate method (SMS or Email).
     * Returns a hint string like "Try SMS" or null if no escalation needed.
     */
    private static String getMethodEscalationHint(NbaSignalService.OpportunitySignal signal) {
        if (!signal.hadNoConnect || String.isBlank(signal.lastCallDisposition)) {
            return null;
        }
        String disp = signal.lastCallDisposition;
        if (disp.startsWithIgnoreCase('Attempted-LVM') || disp.startsWithIgnoreCase('Attempted - LVM')) {
            return 'Try SMS — left voicemail on last attempt';
        }
        if (disp.startsWithIgnoreCase('Attempted-NVM') || disp.startsWithIgnoreCase('Attempted - NVM')) {
            return 'Try SMS or Email — no voicemail on last attempt';
        }
        if (disp.startsWithIgnoreCase('Attempted')) {
            return 'Try SMS — call was not connected';
        }
        return null;
    }

    private static NBA_Impact_Weight__mdt getActiveImpactWeights() {
        List<NBA_Impact_Weight__mdt> configs = [
            SELECT Config_Name__c, MRR_Weight__c, Close_Probability_Weight__c,
                   Impact_vs_Urgency_Impact_Weight__c, Impact_vs_Urgency_Urgency_Weight__c
            FROM NBA_Impact_Weight__mdt
            WHERE Is_Active__c = true
            LIMIT 1
        ];
        if (!configs.isEmpty()) {
            return configs[0];
        }
        // Fallback defaults if no CMDT record exists
        NBA_Impact_Weight__mdt fallback = new NBA_Impact_Weight__mdt();
        fallback.MRR_Weight__c = 0.60;
        fallback.Close_Probability_Weight__c = 0.40;
        fallback.Impact_vs_Urgency_Impact_Weight__c = 0.50;
        fallback.Impact_vs_Urgency_Urgency_Weight__c = 0.50;
        return fallback;
    }
}
