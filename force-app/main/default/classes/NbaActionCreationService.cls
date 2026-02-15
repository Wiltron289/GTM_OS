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

            // Step 3: Calculate scores
            Decimal impactScore = calculateImpactScore(signal, maxMrr, weights);
            Decimal urgencyScore = calculateUrgencyScore(signal, actionType, urgencyRules);
            Decimal finalScore = (weights.Impact_vs_Urgency_Impact_Weight__c * impactScore)
                + (weights.Impact_vs_Urgency_Urgency_Weight__c * urgencyScore);

            // Step 4: Assign bucket and layer
            String bucket = assignBucket(signal, actionType, impactScore);
            String layer = assignLayer(signal, actionType);

            // Step 5: Build the action record
            String instruction = buildInstruction(signal, actionType);
            String reasonText = buildReasonText(signal, actionType, impactScore, urgencyScore);
            String ruleName = actionType + '_Auto';

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
                Cadence_Stage__c = 1,
                Attempt_Count_Today__c = 0,
                Last_Attempt_Method__c = 'Call',
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
