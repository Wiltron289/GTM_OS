/**
 * NbaActionSelectionService — Gate/Bucket/Rank prioritization for NBA V2 engine.
 *
 * Lightweight selection layer. Most scoring and bucketing happens at creation
 * time in NbaActionCreationService. This service applies final gating (cooldown,
 * mode filter) and selects the top-ranked Pending action for an AE.
 *
 * Called by NbaActionCreationSchedulable and NbaActionStateService.promoteNextAction.
 */
public with sharing class NbaActionSelectionService {

    // ─── Result Wrapper ───────────────────────────────────────────────
    public class RankedAction {
        public NBA_Queue__c action;
        public Integer layerRank;
        public String bucket;
        public Decimal finalScore;
        public Boolean passedGate;

        public RankedAction(NBA_Queue__c a) {
            this.action = a;
            this.layerRank = getLayerRank(a.Priority_Layer__c);
            this.bucket = a.Priority_Bucket__c;
            this.finalScore = a.Priority_Score__c != null ? a.Priority_Score__c : 0;
            this.passedGate = true;
        }
    }

    // ─── Layer Ranking ────────────────────────────────────────────────
    private static final Map<String, Integer> LAYER_ORDER = new Map<String, Integer>{
        'Layer 1 - Time Bound' => 1,
        'Layer 2 - Mode' => 2,
        'Layer 3 - Impact+Urgency' => 3
    };

    private static Integer getLayerRank(String layer) {
        return LAYER_ORDER.containsKey(layer) ? LAYER_ORDER.get(layer) : 4;
    }

    // ─── Primary Entry Point ──────────────────────────────────────────

    /**
     * Select the top-ranked Pending action for an AE after applying gate filters.
     * @param aeUserId The AE's User ID
     * @return The best action to serve, or null if none pass gating
     */
    public static NBA_Queue__c selectTop(Id aeUserId) {
        if (aeUserId == null) {
            return null;
        }

        // Query Pending actions for this AE
        List<NBA_Queue__c> candidates = [
            SELECT Id, Opportunity__c, Status__c, Action_Type__c,
                   Priority_Score__c, Priority_Layer__c, Priority_Bucket__c,
                   Is_Time_Bound__c, Impact_Score__c, Urgency_Score__c,
                   CooldownUntil__c, Workflow_Mode__c, Sales_Rep__c, DueAt__c,
                   Action_Instruction__c, ReasonText__c
            FROM NBA_Queue__c
            WHERE Sales_Rep__c = :aeUserId
              AND Status__c = 'Pending'
            WITH SECURITY_ENFORCED
            ORDER BY Priority_Score__c DESC
            LIMIT 20
        ];

        if (candidates.isEmpty()) {
            return null;
        }

        // Apply gate + rank
        List<RankedAction> ranked = rankActions(candidates);

        return ranked.isEmpty() ? null : ranked[0].action;
    }

    // ─── Full Pipeline ────────────────────────────────────────────────

    /**
     * Apply Gate → Rank on a list of candidates.
     * Returns sorted list (Layer ASC, Score DESC) with only passing actions.
     */
    public static List<RankedAction> rankActions(List<NBA_Queue__c> candidates) {
        // Load cooldown rules (cached, 0 SOQL)
        Map<String, NBA_Cooldown_Rule__mdt> cooldownMap = new Map<String, NBA_Cooldown_Rule__mdt>();
        for (NBA_Cooldown_Rule__mdt rule : [
            SELECT Method__c, Min_Spacing_Minutes__c, Daily_Cap__c
            FROM NBA_Cooldown_Rule__mdt
            WHERE Is_Active__c = true
        ]) {
            cooldownMap.put(rule.Method__c, rule);
        }

        // Step 1: Gate filter
        List<RankedAction> ranked = new List<RankedAction>();
        for (NBA_Queue__c candidate : candidates) {
            RankedAction ra = new RankedAction(candidate);

            // Cooldown gate
            if (candidate.CooldownUntil__c != null
                && candidate.CooldownUntil__c > Datetime.now()) {
                ra.passedGate = false;
            }

            // Mode gate (Phase 2: Pipeline only)
            if (candidate.Workflow_Mode__c != null
                && candidate.Workflow_Mode__c != 'Pipeline') {
                ra.passedGate = false;
            }

            if (ra.passedGate) {
                ranked.add(ra);
            }
        }

        // Step 2: Sort by layer rank ASC, then score DESC
        ranked.sort(new RankedActionComparator());

        return ranked;
    }

    // ─── Comparator ───────────────────────────────────────────────────

    private class RankedActionComparator implements System.Comparator<RankedAction> {
        public Integer compare(RankedAction a, RankedAction b) {
            // Layer rank ascending (Layer 1 first)
            if (a.layerRank != b.layerRank) {
                return a.layerRank - b.layerRank;
            }
            // Score descending (higher score first)
            if (b.finalScore > a.finalScore) return 1;
            if (b.finalScore < a.finalScore) return -1;
            return 0;
        }
    }
}
