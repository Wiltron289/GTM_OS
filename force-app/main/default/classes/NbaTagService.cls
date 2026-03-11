/**
 * NbaTagService — Explainability tag generation for the GTM OS engine.
 *
 * Two display modes:
 *   1. Time-Bound actions → single rationale tag (Meeting Upcoming, SLA Active, Follow-Up Due)
 *   2. Engine-Generated actions → Data Science driver tags parsed from
 *      Account_Scoring__c.Payroll_Top_Drivers__c, mapped to AE-facing language
 *
 * Cadence context and payroll probability are displayed separately by the LWC
 * (not as tags). Tags are strictly for explaining WHY this account was prioritized.
 *
 * Called by NbaActionController after ActionWrapper is built.
 * Output is serialized to NBA_Queue__c.Action_Tags__c as JSON.
 *
 * See docs/EXPLAINABILITY-MODEL.md for the full specification.
 */
public with sharing class NbaTagService {

    // ─── Constants ────────────────────────────────────────────────────
    private static final Integer MAX_TAGS = 4;

    // ─── Driver Mapping (Model Output → AE-Facing Language) ─────────
    // Keys are lowercase-trimmed for case-insensitive matching.
    // New drivers from the DS team just need a map entry added here.
    @TestVisible
    private static final Map<String, DriverMapping> DRIVER_MAP = new Map<String, DriverMapping>{
        'growing team size' => new DriverMapping(
            'Growing Team',
            'This account is actively growing their team — payroll need increases with headcount'),
        'high hiring activity' => new DriverMapping(
            'Hiring Surge',
            'High hiring activity recently — strong signal for payroll adoption'),
        'high engagement across features' => new DriverMapping(
            'Power User',
            'Account is highly engaged across multiple product features'),
        'enterprise-adjacent size' => new DriverMapping(
            'Enterprise-Adjacent',
            'Company size is approaching enterprise scale — higher payroll complexity'),
        'low tier' => new DriverMapping(
            'Room to Grow',
            'Currently on a lower tier — strong upsell opportunity with payroll'),
        'essential tier' => new DriverMapping(
            'Room to Grow',
            'Currently on Essential tier — strong upsell opportunity with payroll'),
        'recent team management usage' => new DriverMapping(
            'Managing Teams',
            'Account recently started using team management features — payroll is a natural next step'),
        'new location' => new DriverMapping(
            'New Location',
            'Account just added a new location — expansion signal for payroll'),
        'active scheduling' => new DriverMapping(
            'Active Scheduling',
            'Heavy scheduling usage signals operational maturity for payroll'),
        'steady usage growth' => new DriverMapping(
            'Usage Growing',
            'Account shows steady growth in platform usage over time'),
        'multi-location company' => new DriverMapping(
            'Multi-Location',
            'Company operates multiple locations — payroll complexity drives need'),
        'spike in timeclock punches' => new DriverMapping(
            'Timeclock Spike',
            'Unusual spike in timeclock activity recently — possible event or growth'),
        'high timeclock usage' => new DriverMapping(
            'Heavy Timeclock',
            'Consistently high timeclock usage — strong payroll readiness signal'),
        'consistent time tracking' => new DriverMapping(
            'Tracking Time',
            'Account consistently tracks employee time — payroll is the next logical step'),
        'frequent scheduling activity' => new DriverMapping(
            'Active Scheduler',
            'Frequent scheduling activity signals operational reliance on the platform')
    };

    // ─── Inner Classes ──────────────────────────────────────────────

    public class Tag {
        public String id;
        public String category;
        public String chip;
        public String expanded;

        public Tag(String id, String category, String chip, String expanded) {
            this.id = id;
            this.category = category;
            this.chip = chip;
            this.expanded = expanded;
        }
    }

    private class DriverMapping {
        public String chip;
        public String expanded;
        public DriverMapping(String chip, String expanded) {
            this.chip = chip;
            this.expanded = expanded;
        }
    }

    // ─── Primary Entry Point ──────────────────────────────────────────

    /**
     * Generate tags for the given action.
     *
     * Time-bound actions: single rationale tag explaining why (meeting, SLA, follow-up).
     * Engine-generated actions: DS driver tags from Payroll_Top_Drivers__c.
     *
     * @param wrapper The built ActionWrapper with action context
     * @param signal  The OpportunitySignal with CRM data
     * @return List of Tag objects (max 4 for engine actions, 1 for time-bound)
     */
    public static List<Tag> generateTags(
        NbaActionController.ActionWrapper wrapper,
        NbaSignalService.OpportunitySignal signal
    ) {
        List<Tag> tags = new List<Tag>();

        if (wrapper == null || signal == null) {
            return tags;
        }

        // Time-bound actions: only show the time-bound rationale
        if (wrapper.isTimeBound == true) {
            addTimeBoundRationale(tags, wrapper);
            return tags;
        }

        // Engine-generated actions: show DS driver tags
        addDriverTags(tags, signal);

        return tags;
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
            tagList.add(tagMap);
        }
        return JSON.serialize(tagList);
    }

    // ─── Time-Bound Rationale ────────────────────────────────────────

    private static void addTimeBoundRationale(
        List<Tag> tags,
        NbaActionController.ActionWrapper wrapper
    ) {
        if (wrapper.actionType == 'Meeting') {
            tags.add(new Tag(
                'TB-01', 'Time-Bound', 'Meeting Upcoming',
                'Upcoming meeting — review context and prepare.'
            ));
        } else if (wrapper.actionType == 'Follow Up') {
            tags.add(new Tag(
                'TB-03', 'Time-Bound', 'Follow-Up Due',
                'Your scheduled follow-up is now due.'
            ));
        } else {
            // New assignment / SLA
            tags.add(new Tag(
                'TB-02', 'Time-Bound', 'Newly Assigned',
                'Newly assigned opportunity — make initial contact within SLA window.'
            ));
        }
    }

    // ─── Data Science Driver Tags ────────────────────────────────────

    /**
     * Parse Payroll_Top_Drivers__c (comma-separated string from DS model)
     * and map each driver to an AE-facing tag using DRIVER_MAP.
     * Unknown drivers fall back to displaying the raw model text.
     */
    private static void addDriverTags(
        List<Tag> tags,
        NbaSignalService.OpportunitySignal signal
    ) {
        if (!signal.hasAccountScoring || String.isBlank(signal.payrollTopDrivers)) {
            return;
        }

        // Parse comma-separated drivers (e.g., "Growing team size, high hiring activity (9d), essential tier")
        List<String> rawDrivers = signal.payrollTopDrivers.split(',');
        Integer driverIndex = 0;

        for (String raw : rawDrivers) {
            if (driverIndex >= MAX_TAGS) break;

            String trimmed = raw.trim();
            if (String.isBlank(trimmed)) continue;

            // Strip parenthetical suffixes for matching (e.g., "(9d)", "(30d)", "(3d)")
            String matchKey = trimmed.replaceAll('\\s*\\([^)]*\\)\\s*$', '').toLowerCase().trim();

            DriverMapping mapping = DRIVER_MAP.get(matchKey);

            if (mapping != null) {
                tags.add(new Tag(
                    'DS-' + String.valueOf(driverIndex + 1),
                    'Signal',
                    mapping.chip,
                    mapping.expanded
                ));
            } else {
                // Unknown driver — show raw text (graceful degradation)
                tags.add(new Tag(
                    'DS-' + String.valueOf(driverIndex + 1),
                    'Signal',
                    trimmed.length() > 25 ? trimmed.left(22) + '...' : trimmed,
                    trimmed
                ));
            }
            driverIndex++;
        }
    }

    // ─── Utilities ────────────────────────────────────────────────────

    @TestVisible
    private static Long getMinutesBetween(Datetime dt1, Datetime dt2) {
        Long ms = Math.abs(dt2.getTime() - dt1.getTime());
        return ms / 60000;
    }
}
