/**
 * NbaActionCreationService — Rule evaluation and candidate action creation
 * for the GTM OS Action Orchestration Engine.
 *
 * Evaluates OpportunitySignals against suppression rules, determines action type,
 * then scores using Expected Incremental ARR formula (PRD Section 8.3):
 *   Expected_Incremental_ARR = Likelihood_To_Win × Incremental_If_Won × Connect_Rate(attempt)
 *
 * Called by NbaActionController during on-demand evaluation.
 */
public with sharing class NbaActionCreationService {

    // ─── Constants ────────────────────────────────────────────────────
    // Fallback stage-based win probability when no Account_Scoring data
    private static final Map<String, Decimal> STAGE_PROBABILITY_FALLBACK = new Map<String, Decimal>{
        'New' => 0.10,
        'Connect' => 0.25,
        'Consult' => 0.50,
        'Evaluating' => 0.50,
        'Closing' => 0.75,
        'Verbal Commit' => 0.90,
        'Ready to Convert' => 0.90
    };
    private static final Decimal DEFAULT_STAGE_PROBABILITY = 0.30;
    private static final Decimal DEFAULT_CONNECT_RATE = 0.05;  // fallback if no CMDT match

    // Inactivity thresholds (days)
    private static final Decimal FIRST_TOUCH_INACTIVITY = 99999;
    private static final Decimal FIRST_TOUCH_HOURS_THRESHOLD = 1;
    private static final Integer LATE_STAGE_INACTIVITY_DAYS = 3;
    private static final Integer LATE_STAGE_MIN = 4;
    private static final Integer REENGAGE_INACTIVITY_DAYS = 5;
    private static final Integer CONNECTED_FOLLOWUP_HOURS = 4;

    // Connect rate CMDT cache
    private static Map<Integer, Decimal> connectRateMap;

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
     * Loads all CMDT rules once (0 SOQL after first call), then evaluates each signal.
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

        // Load suppression rules (CMDT, 0 SOQL after first call in transaction)
        List<NBA_Suppression_Rule__mdt> suppressionRules = [
            SELECT Rule_Name__c, Condition__c, Suppression_Window_Hours__c,
                   Is_Active__c, Description__c
            FROM NBA_Suppression_Rule__mdt
            WHERE Is_Active__c = true
        ];

        // Load connect rates (CMDT, cached static)
        loadConnectRates();

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

            // Phase 7: Universal cadence integration — try cadence for any action type
            NbaCadenceService.CadenceResult cadenceResult = null;
            String variant = 'A';
            NBA_AE_Config__c aeConfig = NBA_AE_Config__c.getInstance(signal.ownerId);
            if (aeConfig != null && String.isNotBlank(aeConfig.Cadence_Variant__c)) {
                variant = aeConfig.Cadence_Variant__c;
            }
            cadenceResult = NbaCadenceService.getNextStep(signal, variant, actionType);

            if (cadenceResult != null) {
                if (cadenceResult.isComplete || cadenceResult.isSuppressed || cadenceResult.currentStep == null) {
                    // Cadence exhausted or suppressed — fall through to non-cadence
                    String originalType = actionType;
                    actionType = determineNonCadenceActionType(signal);
                    if (actionType == null) {
                        result.suppressedReasons.add(signal.oppId + ': ' + originalType + ' cadence suppressed, no fallback');
                        result.suppressedCount++;
                        continue;
                    }
                    cadenceResult = null; // Clear so we use non-cadence path below
                }
            }

            // Step 3: Calculate Expected Incremental ARR (PRD 8.3)
            Integer attemptNumber = getAttemptNumber(signal, cadenceResult);
            Decimal expectedArr = calculateExpectedArr(signal, attemptNumber);
            Integer stagePriority = NbaActionSelectionService.resolveStagePriority(signal.stageName);

            // Step 4: Build the action record
            String instruction;
            String ruleName;
            Integer cadenceStageVal = 1;
            Integer attemptCountVal = 0;
            String lastMethodVal = 'Call';
            String cadenceNameVal = null;
            Integer cadenceStepNumVal = null;
            String stepMethodVal = null;

            if (cadenceResult != null && cadenceResult.currentStep != null) {
                // Use cadence step values
                instruction = cadenceResult.currentStep.instructionText;
                ruleName = cadenceResult.currentStep.developerName;
                cadenceStageVal = cadenceResult.currentStep.stepNumber;
                attemptCountVal = cadenceResult.position != null
                    ? cadenceResult.position.lastCompletedStep : 0;
                lastMethodVal = cadenceResult.currentStep.method;
                cadenceNameVal = cadenceResult.cadenceName;
                cadenceStepNumVal = cadenceResult.currentStep.stepNumber;
                stepMethodVal = cadenceResult.currentStep.method;
            } else {
                instruction = buildInstruction(signal, actionType);
                ruleName = actionType + '_Auto';
            }

            String reasonText = buildReasonText(signal, actionType, expectedArr, stagePriority);

            NBA_Queue__c action = new NBA_Queue__c(
                Opportunity__c = signal.oppId,
                Account__c = signal.accountId,
                Sales_Rep__c = signal.ownerId,
                Status__c = 'Pending',
                Action_Type__c = actionType,
                Priority_Score__c = expectedArr,
                Expected_Incremental_ARR__c = expectedArr,
                Stage_Priority__c = stagePriority,
                Is_Time_Bound__c = false,
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
                Due_Date__c = Date.today(),
                Cadence_Name__c = cadenceNameVal,
                Cadence_Step_Number__c = cadenceStepNumVal,
                Step_Method__c = stepMethodVal
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

        // Query opp for stage priority
        String stageName = '';
        Integer stagePriority = 99;
        List<Opportunity> opps = [
            SELECT Amount, MRR__c, StageName
            FROM Opportunity
            WHERE Id = :oppId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!opps.isEmpty()) {
            stageName = opps[0].StageName;
            stagePriority = NbaActionSelectionService.resolveStagePriority(stageName);
        }

        NBA_Queue__c action = new NBA_Queue__c(
            Opportunity__c = oppId,
            Account__c = accountId,
            Sales_Rep__c = aeId,
            Status__c = 'Pending',
            Action_Type__c = 'Meeting',
            Priority_Score__c = 0,
            Expected_Incremental_ARR__c = 0,
            Stage_Priority__c = stagePriority,
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

    // ─── New Assignment Interrupt (Two-Stream Architecture) ──────────

    /**
     * Create a Layer 1 interrupt record for a newly assigned Opportunity.
     * Unlike time-bound actions, these have Is_Time_Bound=false and no DueAt.
     * The LWC's 15s interrupt poll picks them up via checkInterrupts().
     * Does NOT insert the record — caller handles DML for bulkification.
     *
     * @param oppId Opportunity ID
     * @param accountId Account ID
     * @param aeId Sales Rep (AE) User ID
     * @param stageName Current stage name of the Opportunity
     * @return NBA_Queue__c record ready for insert, or null if duplicate exists
     */
    public static NBA_Queue__c createNewAssignmentAction(
        Id oppId, Id accountId, Id aeId, String stageName
    ) {
        // Dedup check: one new-assignment interrupt per Opp
        String uniqueKey = 'V2|' + oppId + '|First Touch|NewAssignment';
        List<NBA_Queue__c> existing = [
            SELECT Id FROM NBA_Queue__c
            WHERE UniqueKey__c = :uniqueKey
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return null;
        }

        Integer stagePriority = NbaActionSelectionService.resolveStagePriority(stageName);

        NBA_Queue__c action = new NBA_Queue__c(
            Opportunity__c = oppId,
            Account__c = accountId,
            Sales_Rep__c = aeId,
            Status__c = 'Pending',
            Action_Type__c = 'First Touch',
            Priority_Score__c = 0,
            Expected_Incremental_ARR__c = 0,
            Stage_Priority__c = stagePriority,
            Priority_Layer__c = 'Layer 1 - Time Bound',
            Is_Time_Bound__c = false,
            Cadence_Stage__c = 1,
            Attempt_Count_Today__c = 0,
            Source_Path__c = 'Immediate',
            Rule_Name__c = 'NewAssignment_Interrupt',
            Action_Instruction__c = 'New opportunity assigned — make initial contact',
            Workflow_Mode__c = 'Pipeline',
            ReasonText__c = 'New assignment interrupt. First Touch action for newly assigned opportunity.',
            LastEvaluatedAt__c = Datetime.now(),
            UniqueKey__c = uniqueKey,
            Opportunity_Stage__c = stageName,
            Due_Date__c = Date.today()
        );

        return action;
    }

    /**
     * Bulk version: Create Layer 1 new-assignment interrupt records for multiple Opps.
     * Performs dedup and Amount lookups in bulk (2 SOQL total) to stay within limits.
     *
     * @param opps List of Opportunities (must have Id, AccountId, OwnerId, StageName, Amount)
     * @return List of NBA_Queue__c records ready for insert (excludes duplicates)
     */
    public static List<NBA_Queue__c> createNewAssignmentActions(List<Opportunity> opps) {
        if (opps == null || opps.isEmpty()) {
            return new List<NBA_Queue__c>();
        }

        // Build all unique keys and check for existing in one SOQL
        Set<String> allKeys = new Set<String>();
        Map<Id, String> oppKeyMap = new Map<Id, String>();
        for (Opportunity opp : opps) {
            String key = 'V2|' + opp.Id + '|First Touch|NewAssignment';
            allKeys.add(key);
            oppKeyMap.put(opp.Id, key);
        }

        Set<String> existingKeys = new Set<String>();
        for (NBA_Queue__c existingRec : [
            SELECT UniqueKey__c FROM NBA_Queue__c
            WHERE UniqueKey__c IN :allKeys
            WITH SECURITY_ENFORCED
        ]) {
            existingKeys.add(existingRec.UniqueKey__c);
        }

        // Build records for non-duplicates
        List<NBA_Queue__c> toCreate = new List<NBA_Queue__c>();
        for (Opportunity opp : opps) {
            String key = oppKeyMap.get(opp.Id);
            if (existingKeys.contains(key)) {
                continue; // Duplicate — skip
            }

            Integer stagePriority = NbaActionSelectionService.resolveStagePriority(opp.StageName);

            NBA_Queue__c action = new NBA_Queue__c(
                Opportunity__c = opp.Id,
                Account__c = opp.AccountId,
                Sales_Rep__c = opp.OwnerId,
                Status__c = 'Pending',
                Action_Type__c = 'First Touch',
                Priority_Score__c = 0,
                Expected_Incremental_ARR__c = 0,
                Stage_Priority__c = stagePriority,
                Priority_Layer__c = 'Layer 1 - Time Bound',
                Is_Time_Bound__c = false,
                Cadence_Stage__c = 1,
                Attempt_Count_Today__c = 0,
                Source_Path__c = 'Immediate',
                Rule_Name__c = 'NewAssignment_Interrupt',
                Action_Instruction__c = 'New opportunity assigned — make initial contact',
                Workflow_Mode__c = 'Pipeline',
                ReasonText__c = 'New assignment interrupt. First Touch action for newly assigned opportunity.',
                LastEvaluatedAt__c = Datetime.now(),
                UniqueKey__c = key,
                Opportunity_Stage__c = opp.StageName,
                Due_Date__c = Date.today()
            );
            toCreate.add(action);
        }

        return toCreate;
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

    // ─── Scoring: Expected Incremental ARR ────────────────────────────

    /**
     * Calculate Expected Incremental ARR per PRD Section 8.3:
     *   Expected_Incremental_ARR = Likelihood_To_Win × Incremental_If_Won × Connect_Rate(attempt)
     *
     * Fallbacks:
     *   - LTW: stage-based probability if no Account_Scoring data
     *   - IIW: Opp.MRR or Opp.Amount if no Account_Scoring data
     *   - Connect Rate: from NBA_Connect_Rate__mdt, capped at attempt 10
     */
    @TestVisible
    private static Decimal calculateExpectedArr(
        NbaSignalService.OpportunitySignal signal,
        Integer attemptNumber
    ) {
        // Likelihood_To_Win: Account_Scoring > stage fallback
        Decimal ltw;
        if (signal.hasAccountScoring && signal.likelihoodToWin != null) {
            ltw = signal.likelihoodToWin;  // stored as 0-1 decimal
        } else if (signal.hasAccountScoring && signal.probPayrollConversion != null) {
            ltw = signal.probPayrollConversion / 100;  // percent to decimal
        } else {
            ltw = STAGE_PROBABILITY_FALLBACK.containsKey(signal.stageName)
                ? STAGE_PROBABILITY_FALLBACK.get(signal.stageName)
                : DEFAULT_STAGE_PROBABILITY;
        }

        // Incremental_If_Won: Account_Scoring > Opp Amount
        Decimal iiw;
        if (signal.hasAccountScoring && signal.incrementalIfWon != null) {
            iiw = signal.incrementalIfWon;
        } else {
            iiw = signal.amount != null ? signal.amount : 0;
        }

        // Connect Rate: CMDT lookup by attempt number, default for unknown
        Decimal connectRate = getConnectRate(attemptNumber);

        return ltw * iiw * connectRate;
    }

    /**
     * Determine the attempt number for connect rate lookup.
     * Uses cadence step number if available, otherwise defaults to 1.
     */
    private static Integer getAttemptNumber(
        NbaSignalService.OpportunitySignal signal,
        NbaCadenceService.CadenceResult cadenceResult
    ) {
        if (cadenceResult != null && cadenceResult.currentStep != null) {
            return cadenceResult.currentStep.stepNumber;
        }
        // Use last completed step + 1, or default to 1
        if (signal.lastCadenceStepNumber != null) {
            return signal.lastCadenceStepNumber + 1;
        }
        return 1;
    }

    // ─── Connect Rate CMDT ────────────────────────────────────────────

    private static void loadConnectRates() {
        if (connectRateMap != null) {
            return;
        }
        connectRateMap = new Map<Integer, Decimal>();
        for (NBA_Connect_Rate__mdt cr : [
            SELECT Attempt_Number__c, Connect_Rate__c
            FROM NBA_Connect_Rate__mdt
        ]) {
            connectRateMap.put(Integer.valueOf(cr.Attempt_Number__c), cr.Connect_Rate__c);
        }
    }

    @TestVisible
    private static Decimal getConnectRate(Integer attemptNumber) {
        if (connectRateMap == null) {
            loadConnectRates();
        }
        // Cap at attempt 10 (highest CMDT record)
        Integer lookup = Math.min(attemptNumber != null ? attemptNumber : 1, 10);
        return connectRateMap.containsKey(lookup)
            ? connectRateMap.get(lookup)
            : DEFAULT_CONNECT_RATE;
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
        Decimal expectedArr,
        Integer stagePriority
    ) {
        String reason = actionType + ' action. ';
        reason += 'Expected ARR: $' + expectedArr.setScale(2) + '. ';
        reason += 'Stage Priority: ' + stagePriority + '. ';

        if (signal.hasAccountScoring) {
            reason += 'ML scoring available';
            if (signal.likelihoodToWin != null) {
                reason += ' (LTW: ' + (signal.likelihoodToWin * 100).setScale(1) + '%)';
            }
            reason += '. ';
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
}
