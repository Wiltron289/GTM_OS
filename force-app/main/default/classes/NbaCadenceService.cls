/**
 * NbaCadenceService — Cadence engine for the NBA V2 Action Orchestration Engine (Phase 7 redesign).
 *
 * Loads NBA_Cadence__mdt (parent) and NBA_Cadence_Step__mdt (child) records to define
 * multi-day, multi-step, multi-method cadences with outcome-based branching.
 *
 * All steps (Call, SMS, Email) are full actionable items. Progress is tracked via
 * NBA_Queue__c audit records (Cadence_Name__c, Cadence_Step_Number__c, Step_Outcome__c).
 *
 * CMDT records are static-cached per transaction. The lastEvaluatedResults map is
 * populated during getNextStep() and read by NbaActionController.toWrapperFromCandidate()
 * and NbaActionStateService.writeAuditRecord() in the same transaction.
 */
public with sharing class NbaCadenceService {

    // ─── Transaction-Scoped Caches ─────────────────────────────────────
    private static List<NBA_Cadence__mdt> cachedCadences;
    private static List<NBA_Cadence_Step__mdt> cachedSteps;
    private static Boolean cadencesLoaded = false;
    private static Boolean stepsLoaded = false;

    // Parsed cadence contexts keyed by 'Scenario|Variant'
    private static Map<String, CadenceContext> cadenceContextMap;

    // Populated during getNextStep(), read by NbaActionController + NbaActionStateService
    public static Map<Id, CadenceResult> lastEvaluatedResults = new Map<Id, CadenceResult>();

    // ─── Inner Classes ────────────────────────────────────────────────

    public class CadenceContext {
        public String cadenceName;
        public String scenario;
        public String variant;
        public Integer totalSteps;
        public Integer totalDays;
        public String anchorField;
        public Set<String> exitConditions;
        public Map<String, Integer> dayMap;
        public List<CadenceStepDef> steps;
    }

    public class CadenceStepDef {
        public String developerName;
        public Integer stepNumber;
        public Integer dayNumber;
        public Integer orderInDay;
        public String method;
        public String instructionText;
        public Integer maxAttempts;
        public Integer spacingMinutes;
        public String onConnectAction;
        public Integer onConnectTarget;
        public String onVMAction;
        public Integer onVMTarget;
        public String onNoAnswerAction;
        public Integer onNoAnswerTarget;
        public String onMeetingAction;
        public Integer onMeetingTarget;
    }

    public class CadencePosition {
        public Integer lastCompletedStep;   // 0 = never started
        public String lastOutcome;          // Connected, VM, No_Answer, Sent, etc.
        public Datetime lastStepDate;
    }

    public class CadenceResult {
        public String cadenceName;
        public CadenceStepDef currentStep;
        public CadenceContext context;
        public CadencePosition position;
        public String progressText;         // "Step 3 of 12 — Day 0, SMS"
        public String progressFraction;     // "3/12"
        public Boolean isComplete;
        public Boolean isSuppressed;
        public String suppressReason;
        public List<String> upcomingSteps;  // Next 2-3 step previews
    }

    // ─── Primary Entry Point ──────────────────────────────────────────

    /**
     * Determine the next cadence step for a given signal and action type.
     *
     * @param signal The OpportunitySignal with enriched fields
     * @param variant The cadence variant (e.g., 'A')
     * @param actionType The action type scenario (e.g., 'First Touch', 'Re-engage')
     * @return CadenceResult with next step, progress, and context — or null if no cadence matches
     */
    public static CadenceResult getNextStep(
        NbaSignalService.OpportunitySignal signal, String variant, String actionType
    ) {
        Map<String, CadenceContext> ctxMap = loadAndParseCadences();
        if (ctxMap.isEmpty()) {
            return null;
        }

        // Find matching cadence
        String key = actionType + '|' + variant;
        CadenceContext ctx = ctxMap.get(key);
        if (ctx == null || ctx.steps.isEmpty()) {
            return null;
        }

        CadenceResult result = new CadenceResult();
        result.cadenceName = ctx.cadenceName;
        result.context = ctx;
        result.isComplete = false;
        result.isSuppressed = false;
        result.upcomingSteps = new List<String>();

        // Check exit conditions
        if (checkExitConditions(signal, ctx.exitConditions)) {
            result.isComplete = true;
            lastEvaluatedResults.put(signal.oppId, result);
            return result;
        }

        // Compute cadence day from anchor field
        Decimal anchorValue = getAnchorValue(signal, ctx.anchorField);
        Integer cadenceDay = computeCadenceDay(anchorValue, ctx.dayMap);
        if (cadenceDay == -1) {
            result.isComplete = true;
            lastEvaluatedResults.put(signal.oppId, result);
            return result;
        }

        // Get position from signal (populated by NbaSignalService from audit records)
        CadencePosition pos = new CadencePosition();
        pos.lastCompletedStep = signal.lastCadenceStepNumber != null ? signal.lastCadenceStepNumber : 0;
        pos.lastOutcome = signal.lastCadenceStepOutcome;
        pos.lastStepDate = signal.lastCadenceStepDate;
        result.position = pos;

        // Determine next step number via branching
        Integer nextStepNumber = resolveNextStep(pos, ctx.steps);
        if (nextStepNumber == null) {
            result.isComplete = true;
            lastEvaluatedResults.put(signal.oppId, result);
            return result;
        }

        // Find the target step
        CadenceStepDef targetStep = findStepByNumber(ctx.steps, nextStepNumber);
        if (targetStep == null) {
            result.isComplete = true;
            lastEvaluatedResults.put(signal.oppId, result);
            return result;
        }

        // Day gate: is this step available today?
        if (targetStep.dayNumber > cadenceDay) {
            result.isSuppressed = true;
            result.suppressReason = 'Step is on Day ' + targetStep.dayNumber
                + ', current cadence day is ' + cadenceDay;
            lastEvaluatedResults.put(signal.oppId, result);
            return result;
        }

        // Spacing check (for Call steps with spacing > 0)
        if (targetStep.spacingMinutes != null && targetStep.spacingMinutes > 0
            && signal.lastCallDate != null) {
            Long msSinceLastCall = Math.abs(
                Datetime.now().getTime() - signal.lastCallDate.getTime()
            );
            Decimal minutesSinceLastCall = Decimal.valueOf(msSinceLastCall).divide(60000, 2);
            if (minutesSinceLastCall < targetStep.spacingMinutes) {
                result.isSuppressed = true;
                result.suppressReason = 'Spacing: ' + minutesSinceLastCall.intValue()
                    + 'min since last call, need ' + targetStep.spacingMinutes + 'min';
                lastEvaluatedResults.put(signal.oppId, result);
                return result;
            }
        }

        // Success — set the current step
        result.currentStep = targetStep;
        result.progressFraction = targetStep.stepNumber + '/' + ctx.totalSteps;
        result.progressText = 'Step ' + targetStep.stepNumber + ' of ' + ctx.totalSteps
            + ' \u2014 Day ' + targetStep.dayNumber + ', ' + targetStep.method;
        result.upcomingSteps = collectUpcomingSteps(ctx.steps, targetStep.stepNumber, 3);

        lastEvaluatedResults.put(signal.oppId, result);
        return result;
    }

    // ─── Branching Logic ──────────────────────────────────────────────

    @TestVisible
    private static Integer resolveNextStep(CadencePosition pos, List<CadenceStepDef> steps) {
        if (pos.lastCompletedStep == 0) {
            return 1;
        }

        CadenceStepDef lastStep = findStepByNumber(steps, pos.lastCompletedStep);
        if (lastStep == null) {
            return 1;
        }

        String branchAction = getBranchAction(lastStep, pos.lastOutcome);
        Integer branchTarget = getBranchTarget(lastStep, pos.lastOutcome);

        if (branchAction == 'End_Cadence') {
            return null;
        }
        if (branchAction == 'Skip_To_Step' && branchTarget != null) {
            return branchTarget;
        }
        if (branchAction == 'Skip_To_Day' && branchTarget != null) {
            for (CadenceStepDef step : steps) {
                if (step.dayNumber == branchTarget) {
                    return step.stepNumber;
                }
            }
            return null;
        }

        // Default: Continue to next step
        Integer nextNum = pos.lastCompletedStep + 1;
        // Check if next step exists
        if (findStepByNumber(steps, nextNum) == null) {
            return null; // Past last step — cadence complete
        }
        return nextNum;
    }

    private static String getBranchAction(CadenceStepDef step, String outcome) {
        if (outcome == null) {
            return 'Continue';
        }
        if (outcome == 'Connected') {
            return String.isNotBlank(step.onConnectAction) ? step.onConnectAction : 'End_Cadence';
        }
        if (outcome == 'VM') {
            return String.isNotBlank(step.onVMAction) ? step.onVMAction : 'Continue';
        }
        if (outcome == 'No_Answer') {
            return String.isNotBlank(step.onNoAnswerAction) ? step.onNoAnswerAction : 'Continue';
        }
        if (outcome == 'Meeting_Scheduled') {
            return String.isNotBlank(step.onMeetingAction) ? step.onMeetingAction : 'End_Cadence';
        }
        return 'Continue';
    }

    private static Integer getBranchTarget(CadenceStepDef step, String outcome) {
        if (outcome == 'Connected') {
            return step.onConnectTarget;
        }
        if (outcome == 'VM') {
            return step.onVMTarget;
        }
        if (outcome == 'No_Answer') {
            return step.onNoAnswerTarget;
        }
        if (outcome == 'Meeting_Scheduled') {
            return step.onMeetingTarget;
        }
        return null;
    }

    // ─── Exit Condition Checks ────────────────────────────────────────

    @TestVisible
    private static Boolean checkExitConditions(
        NbaSignalService.OpportunitySignal signal, Set<String> exitConditions
    ) {
        if (exitConditions == null || exitConditions.isEmpty()) {
            return false;
        }
        if (exitConditions.contains('Connected_Call') && signal.hadConnectedCall) {
            return true;
        }
        if (exitConditions.contains('Meeting_Scheduled') && signal.hasUpcomingMeeting) {
            return true;
        }
        if (exitConditions.contains('Opp_Closed') && signal.isClosed) {
            return true;
        }
        return false;
    }

    // ─── Day Computation ──────────────────────────────────────────────

    private static Decimal getAnchorValue(
        NbaSignalService.OpportunitySignal signal, String anchorField
    ) {
        if (anchorField == 'daysSinceLastInteraction') {
            return signal.daysSinceLastInteraction;
        }
        return signal.daysSinceCreation;
    }

    @TestVisible
    private static Integer computeCadenceDay(Decimal rawDaysDecimal, Map<String, Integer> dayMap) {
        if (rawDaysDecimal == null) {
            return 0;
        }
        Integer rawDays = rawDaysDecimal.intValue();
        if (rawDays < 0) {
            rawDays = 0;
        }

        if (dayMap == null || dayMap.isEmpty()) {
            return rawDays;
        }

        // Exact match
        String rawKey = String.valueOf(rawDays);
        if (dayMap.containsKey(rawKey)) {
            return dayMap.get(rawKey);
        }

        // Find max mapped raw day and closest floor value
        Integer maxMappedRaw = -1;
        Integer bestFloorKey = -1;
        Integer floorValue = 0;
        for (String k : dayMap.keySet()) {
            Integer keyInt = Integer.valueOf(k);
            if (keyInt > maxMappedRaw) {
                maxMappedRaw = keyInt;
            }
            if (keyInt <= rawDays && keyInt > bestFloorKey) {
                bestFloorKey = keyInt;
                floorValue = dayMap.get(k);
            }
        }

        if (rawDays > maxMappedRaw) {
            return -1; // Past max — cadence complete
        }

        return floorValue;
    }

    // ─── CMDT Loaders ─────────────────────────────────────────────────

    @TestVisible
    private static Map<String, CadenceContext> loadAndParseCadences() {
        if (cadenceContextMap != null) {
            return cadenceContextMap;
        }

        List<NBA_Cadence__mdt> cadences = loadCadences();
        List<NBA_Cadence_Step__mdt> steps = loadSteps();

        cadenceContextMap = new Map<String, CadenceContext>();
        Map<String, CadenceContext> byName = new Map<String, CadenceContext>();

        for (NBA_Cadence__mdt c : cadences) {
            CadenceContext ctx = new CadenceContext();
            ctx.cadenceName = c.DeveloperName;
            ctx.scenario = c.Scenario__c;
            ctx.variant = c.Variant__c;
            ctx.totalSteps = c.Total_Steps__c != null ? c.Total_Steps__c.intValue() : 0;
            ctx.totalDays = c.Total_Days__c != null ? c.Total_Days__c.intValue() : 0;
            ctx.anchorField = String.isNotBlank(c.Anchor_Field__c)
                ? c.Anchor_Field__c : 'daysSinceCreation';
            ctx.exitConditions = parseExitConditions(c.Exit_Conditions__c);
            ctx.dayMap = parseDayMap(c.Day_Map__c);
            ctx.steps = new List<CadenceStepDef>();

            String key = ctx.scenario + '|' + ctx.variant;
            cadenceContextMap.put(key, ctx);
            byName.put(ctx.cadenceName, ctx);
        }

        for (NBA_Cadence_Step__mdt s : steps) {
            CadenceContext ctx = byName.get(s.Cadence_Name__c);
            if (ctx == null) {
                continue;
            }

            CadenceStepDef stepDef = new CadenceStepDef();
            stepDef.developerName = s.DeveloperName;
            stepDef.stepNumber = s.Step_Number__c != null ? s.Step_Number__c.intValue() : 0;
            stepDef.dayNumber = s.Day_Number__c != null ? s.Day_Number__c.intValue() : 0;
            stepDef.orderInDay = s.Step_Order_In_Day__c != null ? s.Step_Order_In_Day__c.intValue() : 0;
            stepDef.method = s.Method__c;
            stepDef.instructionText = s.Instruction_Text__c;
            stepDef.maxAttempts = s.Max_Attempts__c != null ? s.Max_Attempts__c.intValue() : 1;
            stepDef.spacingMinutes = s.Spacing_Minutes__c != null ? s.Spacing_Minutes__c.intValue() : 0;
            stepDef.onConnectAction = s.On_Connect_Action__c;
            stepDef.onConnectTarget = s.On_Connect_Target__c != null
                ? s.On_Connect_Target__c.intValue() : null;
            stepDef.onVMAction = s.On_VM_Action__c;
            stepDef.onVMTarget = s.On_VM_Target__c != null
                ? s.On_VM_Target__c.intValue() : null;
            stepDef.onNoAnswerAction = s.On_No_Answer_Action__c;
            stepDef.onNoAnswerTarget = s.On_No_Answer_Target__c != null
                ? s.On_No_Answer_Target__c.intValue() : null;
            stepDef.onMeetingAction = s.On_Meeting_Action__c;
            stepDef.onMeetingTarget = s.On_Meeting_Target__c != null
                ? s.On_Meeting_Target__c.intValue() : null;

            ctx.steps.add(stepDef);
        }

        return cadenceContextMap;
    }

    @TestVisible
    private static List<NBA_Cadence__mdt> loadCadences() {
        if (!cadencesLoaded) {
            cachedCadences = [
                SELECT DeveloperName, Scenario__c, Variant__c, Anchor_Field__c,
                       Total_Steps__c, Total_Days__c, Exit_Conditions__c, Day_Map__c,
                       Is_Active__c
                FROM NBA_Cadence__mdt
                WHERE Is_Active__c = true
            ];
            cadencesLoaded = true;
        }
        return cachedCadences;
    }

    @TestVisible
    private static List<NBA_Cadence_Step__mdt> loadSteps() {
        if (!stepsLoaded) {
            cachedSteps = [
                SELECT DeveloperName, Cadence_Name__c, Step_Number__c, Day_Number__c,
                       Step_Order_In_Day__c, Method__c, Instruction_Text__c, Max_Attempts__c,
                       Spacing_Minutes__c, On_Connect_Action__c, On_Connect_Target__c,
                       On_VM_Action__c, On_VM_Target__c, On_No_Answer_Action__c,
                       On_No_Answer_Target__c, On_Meeting_Action__c, On_Meeting_Target__c,
                       Is_Active__c
                FROM NBA_Cadence_Step__mdt
                WHERE Is_Active__c = true
                ORDER BY Step_Number__c ASC
            ];
            stepsLoaded = true;
        }
        return cachedSteps;
    }

    // ─── Parsing Helpers ──────────────────────────────────────────────

    private static Set<String> parseExitConditions(String exitConditionsStr) {
        Set<String> conditions = new Set<String>();
        if (String.isNotBlank(exitConditionsStr)) {
            for (String cond : exitConditionsStr.split(',')) {
                conditions.add(cond.trim());
            }
        }
        return conditions;
    }

    @TestVisible
    private static Map<String, Integer> parseDayMap(String dayMapJson) {
        if (String.isBlank(dayMapJson)) {
            return null;
        }
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(dayMapJson);
            Map<String, Integer> parsed = new Map<String, Integer>();
            for (String k : raw.keySet()) {
                Object val = raw.get(k);
                if (val instanceof Integer) {
                    parsed.put(k, (Integer) val);
                } else if (val instanceof Decimal) {
                    parsed.put(k, ((Decimal) val).intValue());
                }
            }
            return parsed;
        } catch (Exception e) {
            return null;
        }
    }

    // ─── Step Helpers ─────────────────────────────────────────────────

    private static CadenceStepDef findStepByNumber(List<CadenceStepDef> steps, Integer stepNumber) {
        for (CadenceStepDef step : steps) {
            if (step.stepNumber == stepNumber) {
                return step;
            }
        }
        return null;
    }

    private static List<String> collectUpcomingSteps(
        List<CadenceStepDef> steps, Integer afterStepNumber, Integer maxCount
    ) {
        List<String> upcoming = new List<String>();
        for (CadenceStepDef step : steps) {
            if (step.stepNumber > afterStepNumber && upcoming.size() < maxCount) {
                upcoming.add('Day ' + step.dayNumber + ': ' + step.method
                    + ' \u2014 ' + step.instructionText);
            }
        }
        return upcoming;
    }

    // ─── Cache Reset (Testing) ────────────────────────────────────────

    @TestVisible
    private static void resetCache() {
        cachedCadences = null;
        cachedSteps = null;
        cadencesLoaded = false;
        stepsLoaded = false;
        cadenceContextMap = null;
        lastEvaluatedResults = new Map<Id, CadenceResult>();
    }
}
