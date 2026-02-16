/**
 * NbaCadenceService — Cadence logic for the NBA V2 Action Orchestration Engine (Phase 6).
 *
 * Loads NBA_Cadence_Rule__mdt records, determines the AE's current step in the
 * cadence sequence, enforces spacing and daily caps, and returns cadence context
 * for the ActionWrapper and LWC display.
 *
 * CMDT rules are cached in a transaction-scoped static to avoid repeated queries.
 * The lastEvaluatedSteps map is populated during getCurrentStep() and read by
 * NbaActionController.toWrapperFromCandidate() in the same transaction.
 */
public with sharing class NbaCadenceService {

    // ─── Transaction-Scoped Caches ─────────────────────────────────────
    private static List<NBA_Cadence_Rule__mdt> cachedRules;
    private static Boolean rulesLoaded = false;

    // Populated during getCurrentStep(), read by NbaActionController
    public static Map<Id, CadenceStep> lastEvaluatedSteps = new Map<Id, CadenceStep>();

    // ─── CadenceStep Wrapper ───────────────────────────────────────────
    public class CadenceStep {
        public String ruleName;
        public Integer cadenceStage;
        public Integer cadenceDay;
        public String method;
        public Boolean isPrimary;
        public Integer spacingMinutes;
        public Integer maxCallsToday;
        public String nextMethodOnFail;
        public String hintText;
        public String instruction;
        public String progressText;
        public Integer todayCalls;
        public List<String> upcomingHints;
    }

    // ─── Primary Entry Point ───────────────────────────────────────────

    /**
     * Determine the current cadence step for a First Touch signal.
     * Returns null if:
     *   - No matching rules for the scenario/variant
     *   - Daily call cap reached
     *   - Spacing not met (too soon since last call)
     *   - Cadence is complete (past Day 5)
     *
     * @param signal The OpportunitySignal with enriched cadence fields
     * @param variant The cadence variant (e.g., 'A')
     * @return CadenceStep with instruction and context, or null if suppressed
     */
    public static CadenceStep getCurrentStep(
        NbaSignalService.OpportunitySignal signal, String variant
    ) {
        List<NBA_Cadence_Rule__mdt> rules = loadRules();
        if (rules.isEmpty()) {
            return null;
        }

        // Compute cadence day from daysSinceCreation
        Integer cadenceDay = computeCadenceDay(signal.daysSinceCreation);

        // Filter rules for this scenario + variant, sorted by Cadence_Stage__c
        List<NBA_Cadence_Rule__mdt> matchingRules = new List<NBA_Cadence_Rule__mdt>();
        for (NBA_Cadence_Rule__mdt rule : rules) {
            if (rule.Scenario__c == 'First Touch'
                && rule.Variant__c == variant
                && rule.Is_Active__c) {
                matchingRules.add(rule);
            }
        }

        if (matchingRules.isEmpty()) {
            return null;
        }

        // Find the next primary (call) step on today's cadenceDay
        NBA_Cadence_Rule__mdt targetRule = null;
        for (NBA_Cadence_Rule__mdt rule : matchingRules) {
            if (rule.Cadence_Day__c != null
                && rule.Cadence_Day__c.intValue() == cadenceDay
                && rule.Is_Primary__c) {
                // Check if AE has already done enough calls for this step
                Integer todayCalls = signal.todayCallCount != null ? signal.todayCallCount : 0;
                Integer stepOrder = rule.Step_Order__c != null ? rule.Step_Order__c.intValue() : 1;
                // Count how many primary steps come before this one on the same day
                Integer primaryStepsBefore = countPrimaryStepsBefore(matchingRules, cadenceDay, stepOrder);
                if (todayCalls <= primaryStepsBefore) {
                    targetRule = rule;
                    break;
                }
            }
        }

        // If no primary step found on today's cadenceDay, check if there are only hints left
        if (targetRule == null) {
            return null;
        }

        // Check daily cap
        Integer maxPerDay = targetRule.Max_Attempts_Per_Day__c != null
            ? targetRule.Max_Attempts_Per_Day__c.intValue() : 99;
        Integer todayCalls = signal.todayCallCount != null ? signal.todayCallCount : 0;
        if (todayCalls >= maxPerDay) {
            return null;
        }

        // Check spacing
        Integer spacingMinutes = targetRule.Attempt_Spacing_Minutes__c != null
            ? targetRule.Attempt_Spacing_Minutes__c.intValue() : 0;
        if (spacingMinutes > 0 && signal.lastCallDate != null) {
            Long msSinceLastCall = Math.abs(
                Datetime.now().getTime() - signal.lastCallDate.getTime()
            );
            Decimal minutesSinceLastCall = Decimal.valueOf(msSinceLastCall).divide(60000, 2);
            if (minutesSinceLastCall < spacingMinutes) {
                return null;
            }
        }

        // Build CadenceStep
        CadenceStep step = new CadenceStep();
        step.ruleName = targetRule.Rule_Name__c;
        step.cadenceStage = targetRule.Cadence_Stage__c != null
            ? targetRule.Cadence_Stage__c.intValue() : 1;
        step.cadenceDay = cadenceDay;
        step.method = targetRule.Method__c;
        step.isPrimary = targetRule.Is_Primary__c;
        step.spacingMinutes = spacingMinutes;
        step.maxCallsToday = maxPerDay;
        step.nextMethodOnFail = targetRule.Next_Method_On_Fail__c;
        step.hintText = targetRule.Hint_Text__c;
        step.todayCalls = todayCalls;

        // Build progress text: "Call X of Y today (Day N)"
        Integer callNumber = todayCalls + 1;
        step.progressText = 'Call ' + callNumber + ' of ' + maxPerDay + ' today (Day ' + cadenceDay + ')';

        // Build instruction
        step.instruction = step.progressText;
        if (String.isNotBlank(step.hintText)) {
            step.instruction += '. ' + step.hintText;
        }
        if (String.isNotBlank(step.nextMethodOnFail)) {
            step.instruction += '. If no connect: ' + step.nextMethodOnFail;
        }

        // Collect upcoming hint-only steps after this call on today's day
        step.upcomingHints = collectUpcomingHints(matchingRules, cadenceDay,
            targetRule.Step_Order__c != null ? targetRule.Step_Order__c.intValue() : 1);

        // Store in transaction-scoped map for ActionWrapper mapping
        lastEvaluatedSteps.put(signal.oppId, step);

        return step;
    }

    // ─── CMDT Loader ───────────────────────────────────────────────────

    @TestVisible
    private static List<NBA_Cadence_Rule__mdt> loadRules() {
        if (!rulesLoaded) {
            cachedRules = [
                SELECT Rule_Name__c, Scenario__c, Variant__c, Cadence_Day__c,
                       Step_Order__c, Cadence_Stage__c, Attempt_Spacing_Minutes__c,
                       Max_Attempts_Per_Day__c, Method__c, Next_Method_On_Fail__c,
                       Is_Active__c, Is_Primary__c, Hint_Text__c, Description__c
                FROM NBA_Cadence_Rule__mdt
                WHERE Is_Active__c = true
                ORDER BY Cadence_Stage__c ASC
            ];
            rulesLoaded = true;
        }
        return cachedRules;
    }

    // ─── Helpers ───────────────────────────────────────────────────────

    /**
     * Map daysSinceCreation to the cadence day (0, 1, 3, 5).
     * Day 0 = same day, Day 1 = next day, Day 3 = 2-3 days, Day 5 = 4-5 days.
     * Beyond Day 5 = cadence complete (returns -1).
     */
    @TestVisible
    private static Integer computeCadenceDay(Decimal daysSinceCreation) {
        if (daysSinceCreation == null) {
            return 0;
        }
        Integer days = daysSinceCreation.intValue();
        if (days <= 0) {
            return 0;
        }
        if (days == 1) {
            return 1;
        }
        if (days >= 2 && days <= 3) {
            return 3;
        }
        if (days >= 4 && days <= 5) {
            return 5;
        }
        return -1; // Cadence complete
    }

    /**
     * Count the number of primary (call) steps that come before the given stepOrder
     * on the specified cadenceDay. Used to match todayCallCount to the correct step.
     */
    private static Integer countPrimaryStepsBefore(
        List<NBA_Cadence_Rule__mdt> rules, Integer cadenceDay, Integer stepOrder
    ) {
        Integer count = 0;
        for (NBA_Cadence_Rule__mdt rule : rules) {
            if (rule.Cadence_Day__c != null
                && rule.Cadence_Day__c.intValue() == cadenceDay
                && rule.Is_Primary__c
                && rule.Step_Order__c != null
                && rule.Step_Order__c.intValue() < stepOrder) {
                count++;
            }
        }
        return count;
    }

    /**
     * Collect hint-only steps that follow the current call step on the same day.
     */
    private static List<String> collectUpcomingHints(
        List<NBA_Cadence_Rule__mdt> rules, Integer cadenceDay, Integer afterStepOrder
    ) {
        List<String> hints = new List<String>();
        for (NBA_Cadence_Rule__mdt rule : rules) {
            if (rule.Cadence_Day__c != null
                && rule.Cadence_Day__c.intValue() == cadenceDay
                && !rule.Is_Primary__c
                && rule.Step_Order__c != null
                && rule.Step_Order__c.intValue() > afterStepOrder
                && String.isNotBlank(rule.Hint_Text__c)) {
                hints.add(rule.Method__c + ': ' + rule.Hint_Text__c);
            }
        }
        return hints;
    }

    /**
     * Reset cached rules (for testing).
     */
    @TestVisible
    private static void resetCache() {
        cachedRules = null;
        rulesLoaded = false;
        lastEvaluatedSteps = new Map<Id, CadenceStep>();
    }
}
