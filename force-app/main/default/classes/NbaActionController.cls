/**
 * NbaActionController — Two-stream entry point for the NBA V2 App Page LWC.
 *
 * Stream 1 (Scored Queue) — getActiveAction():
 *   1. Check Platform Cache — 0 SOQL
 *   2. Cache miss → full on-demand evaluation — ~12 SOQL
 *      a. Query AE's open Opps
 *      b. NbaSignalService.getSignals()
 *      c. NbaActionCreationService.evaluateAndCreate()
 *      d. NbaActionSelectionService.rankActions()
 *   3. Cache result → return ActionWrapper
 *
 * Stream 2 (Real-Time Interrupts) — checkInterrupts():
 *   Lightweight 15s poll returns Layer 1 interrupt actions:
 *   - Meetings due within 5 minutes (time-bound)
 *   - New-assignment records (L1, non-time-bound, created within 24h)
 *   AE can accept (Jump to it) or dismiss. Accepted interrupts set to
 *   'In Progress' so they stop appearing in the poll.
 *
 * Call Completed interrupts are now delivered via Call_Completed_Event__e
 * Platform Events (push via empApi) instead of NBA_Queue__c polling.
 *
 * complete/snooze/dismiss: delegate to NbaActionStateService (audit writer),
 * then re-evaluate and return the next action.
 */
public with sharing class NbaActionController {

    private static final Set<String> EXCLUDED_STAGES = new Set<String>{
        'Hand-Off', 'Closed Won', 'Closed Lost'
    };

    // ─── Get Active Action (On-Demand Evaluation) ───────────────────

    /**
     * Returns the current user's top-priority scored-queue action.
     * Stream 1 (Scored Queue): Platform Cache → full on-demand evaluation.
     * Layer 1 interrupts are handled separately by checkInterrupts().
     * @return ActionWrapper or null if no actions available
     */
    @AuraEnabled
    public static ActionWrapper getActiveAction() {
        Id userId = UserInfo.getUserId();

        // Step 1: Check Platform Cache
        ActionWrapper cached = NbaCacheService.getCachedAction(userId);
        if (cached != null) {
            return cached;
        }

        // Step 2: Cache miss — full on-demand evaluation
        ActionWrapper evaluated = evaluateOnDemand(userId);
        if (evaluated != null) {
            NbaCacheService.cacheAction(userId, evaluated);
        }

        return evaluated;
    }

    // ─── Check Interrupts (Lightweight, for 15s Polling) ────────────

    /**
     * Stream 2 (Real-Time Interrupts): Lightweight check for Layer 1 interrupt actions.
     * Returns meetings due within 5 minutes AND new-assignment interrupt records
     * (Source_Path='Immediate', Is_Time_Bound=false) created within 24h.
     * Excludes Call Completed actions (now handled via Platform Events).
     * Used by the LWC's 15-second poll.
     * @return List of interrupt ActionWrappers (empty list if none)
     */
    @AuraEnabled
    public static List<ActionWrapper> checkInterrupts() {
        return checkInterruptsInternal(UserInfo.getUserId());
    }

    // ─── Accept Interrupt (AE clicks "Jump to it") ────────────────

    /**
     * Accept an interrupt action — sets Status to 'In Progress' so it stops
     * appearing in the 15s poll. Called when the AE clicks "Jump to it".
     * @param actionId The NBA_Queue__c ID of the interrupt action
     * @return ActionWrapper for the accepted interrupt
     */
    @AuraEnabled
    public static ActionWrapper acceptInterrupt(Id actionId) {
        if (actionId == null) {
            return null;
        }

        List<NBA_Queue__c> actions = [
            SELECT Id, Opportunity__c, Account__c, Action_Type__c,
                   Action_Instruction__c, ReasonText__c, Rule_Name__c,
                   Priority_Score__c, Is_Time_Bound__c,
                   DueAt__c, Status__c, UniqueKey__c, Sales_Rep__c,
                   Account__r.Name, Opportunity__r.Name, Opportunity__r.StageName
            FROM NBA_Queue__c
            WHERE Id = :actionId
              AND Status__c IN ('New', 'Pending', 'Accepted')
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        if (actions.isEmpty()) {
            return null;
        }

        NBA_Queue__c action = actions[0];
        action.Status__c = 'In Progress';
        action.LastEvaluatedAt__c = Datetime.now();
        update action;

        return toWrapperFromRecord(action);
    }

    /**
     * Enrich a Layer 1 action with tags + payroll probability via signal query.
     * Called asynchronously by the LWC after the action is already displayed,
     * so the AE sees the action immediately and enrichment loads in the background.
     * @param opportunityId The Opp to generate tags for
     * @param actionType The action type (for tag context)
     * @param isTimeBound Whether this is a time-bound action
     * @param ruleName The rule that created this action
     * @return EnrichmentResult with tags JSON + payroll probability, or null if fails
     */
    @AuraEnabled
    public static EnrichmentResult enrichActionTags(Id opportunityId, String actionType, Boolean isTimeBound, String ruleName) {
        if (opportunityId == null) return null;
        try {
            Map<Id, NbaSignalService.OpportunitySignal> signals =
                NbaSignalService.getSignals(new Set<Id>{ opportunityId });
            NbaSignalService.OpportunitySignal signal = signals.get(opportunityId);
            if (signal == null) return null;

            // Build a minimal wrapper for tag generation
            ActionWrapper wrapper = new ActionWrapper();
            wrapper.opportunityId = opportunityId;
            wrapper.actionType = actionType;
            wrapper.isTimeBound = isTimeBound == true;
            wrapper.oppStage = signal.stageName;

            List<NbaTagService.Tag> tags = NbaTagService.generateTags(wrapper, signal);

            EnrichmentResult result = new EnrichmentResult();
            result.actionTags = NbaTagService.toJson(tags);
            result.payrollProbability = signal.probPayrollConversion;
            return result;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'enrichActionTags failed for opp ' + opportunityId + ': ' + e.getMessage());
            return null;
        }
    }

    public class EnrichmentResult {
        @AuraEnabled public String actionTags;
        @AuraEnabled public Decimal payrollProbability;
    }

    // ─── Action Lifecycle ───────────────────────────────────────────

    /**
     * Complete an action. Writes audit record, invalidates cache, re-evaluates.
     * @param actionId NBA_Queue__c ID (null for on-demand actions, real ID for Layer 1)
     * @param opportunityId The Opportunity the action was for
     * @param actionType The action type string
     * @return ActionResultWrapper with next action
     */
    @AuraEnabled
    public static ActionResultWrapper completeAction(
        Id actionId, Id opportunityId, String actionType, String stepOutcome
    ) {
        Id userId = UserInfo.getUserId();

        // Guard: if LWC sent null opportunityId, re-evaluate to get correct context
        if (opportunityId == null || String.isBlank(actionType)) {
            ActionWrapper current = evaluateOnDemand(userId);
            if (current != null) {
                opportunityId = opportunityId != null ? opportunityId : current.opportunityId;
                actionType = String.isNotBlank(actionType) ? actionType : current.actionType;
            }
        }

        // Look up account from Opportunity
        Id accountId = getAccountId(opportunityId);

        // Delegate to state service (writes audit + invalidates cache)
        NbaActionStateService.completeAction(
            actionId, opportunityId, accountId, actionType, null, stepOutcome
        );

        // Re-evaluate and return next action
        return buildResultFromEvaluation(userId);
    }

    /**
     * Snooze an action with a reason and duration.
     */
    @AuraEnabled
    public static ActionResultWrapper snoozeAction(
        Id actionId, Id opportunityId, String actionType,
        String reason, Integer durationMinutes
    ) {
        Id userId = UserInfo.getUserId();

        // Guard: if LWC sent null opportunityId, re-evaluate to get correct context
        if (opportunityId == null || String.isBlank(actionType)) {
            ActionWrapper current = evaluateOnDemand(userId);
            if (current != null) {
                opportunityId = opportunityId != null ? opportunityId : current.opportunityId;
                actionType = String.isNotBlank(actionType) ? actionType : current.actionType;
            }
        }

        Id accountId = getAccountId(opportunityId);

        NbaActionStateService.snoozeAction(
            actionId, opportunityId, accountId, actionType, null,
            reason, durationMinutes
        );

        return buildResultFromEvaluation(userId);
    }

    /**
     * Dismiss an action with a reason and category.
     */
    @AuraEnabled
    public static ActionResultWrapper dismissAction(
        Id actionId, Id opportunityId, String actionType,
        String reason, String category
    ) {
        Id userId = UserInfo.getUserId();

        // Guard: if LWC sent null opportunityId, re-evaluate to get correct context
        if (opportunityId == null || String.isBlank(actionType)) {
            ActionWrapper current = evaluateOnDemand(userId);
            if (current != null) {
                opportunityId = opportunityId != null ? opportunityId : current.opportunityId;
                actionType = String.isNotBlank(actionType) ? actionType : current.actionType;
            }
        }

        Id accountId = getAccountId(opportunityId);

        NbaActionStateService.dismissAction(
            actionId, opportunityId, accountId, actionType, null,
            reason, category
        );

        return buildResultFromEvaluation(userId);
    }

    // ─── Post-Call Context ──────────────────────────────────────────

    /**
     * Returns full post-call context for the LWC after a Platform Event fires.
     * Queries Opportunity for 9 qualification fields + StageName (1 SOQL),
     * then queries the source record for call notes (1 SOQL).
     * @param opportunityId The Opportunity whose call just completed
     * @param sourceType 'Talkdesk' or 'AI_Call_Note'
     * @param sourceRecordId The Talkdesk Activity or AI_Call_Note__c ID
     * @param previousStage The StageName the workspace had cached before the call
     * @return PostCallContext with qualification fields, stage change, call notes
     */
    @AuraEnabled
    public static PostCallContext getPostCallContext(
        Id opportunityId, String sourceType, Id sourceRecordId, String previousStage
    ) {
        if (opportunityId == null) {
            return null;
        }

        // 1. Query Opportunity for qualification fields + current stage (1 SOQL)
        List<Opportunity> opps = [
            SELECT StageName, Customer_Story__c, Decision_Maker_Identified__c,
                   Inception_or_Switcher__c, Business_Challenge__c,
                   Best_Product_Fit_Identified__c, Features_and_Benefits_Discussed__c,
                   Budget_Confirmed__c, Timeline_Confirmed__c, Verbal_Commit__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (opps.isEmpty()) {
            return null;
        }
        Opportunity opp = opps[0];

        PostCallContext ctx = new PostCallContext();
        ctx.opportunityId = opportunityId;
        ctx.previousStage = previousStage;
        ctx.currentStage = opp.StageName;
        ctx.stageChanged = (previousStage != null && previousStage != opp.StageName);
        ctx.sourceType = sourceType;

        // 2. Build qualification fields list
        ctx.qualificationFields = buildQualificationFields(opp);

        // 3. Query source record for call notes (1 SOQL)
        if (sourceRecordId != null && String.isNotBlank(sourceType)) {
            populateSourceFields(ctx, sourceType, sourceRecordId);
        }

        return ctx;
    }

    /**
     * Build the list of 9 qualification fields with stage gate mappings.
     */
    private static List<QualificationField> buildQualificationFields(Opportunity opp) {
        List<QualificationField> fields = new List<QualificationField>();

        // NEW → CONNECTED gate fields
        fields.add(buildTextField(
            'Customer_Story__c', 'Customer Story', (String) opp.Customer_Story__c,
            'NEW_TO_CONNECTED'));
        fields.add(buildBooleanField(
            'Decision_Maker_Identified__c', 'Decision Maker Identified',
            opp.Decision_Maker_Identified__c, 'NEW_TO_CONNECTED'));
        fields.add(buildTextField(
            'Inception_or_Switcher__c', 'Inception or Switcher',
            (String) opp.Inception_or_Switcher__c, 'NEW_TO_CONNECTED'));

        // CONNECTED → CONSULT gate fields
        fields.add(buildTextField(
            'Business_Challenge__c', 'Business Challenge',
            (String) opp.Business_Challenge__c, 'CONNECTED_TO_CONSULT'));
        fields.add(buildBooleanField(
            'Best_Product_Fit_Identified__c', 'Best Product Fit Identified',
            opp.Best_Product_Fit_Identified__c, 'CONNECTED_TO_CONSULT'));

        // CONSULT → CLOSING gate fields
        fields.add(buildTextField(
            'Features_and_Benefits_Discussed__c', 'Features and Benefits Discussed',
            (String) opp.Features_and_Benefits_Discussed__c, 'CONSULT_TO_CLOSING'));
        fields.add(buildBooleanField(
            'Budget_Confirmed__c', 'Budget Confirmed',
            opp.Budget_Confirmed__c, 'CONSULT_TO_CLOSING'));
        fields.add(buildBooleanField(
            'Timeline_Confirmed__c', 'Timeline Confirmed',
            opp.Timeline_Confirmed__c, 'CONSULT_TO_CLOSING'));
        fields.add(buildBooleanField(
            'Verbal_Commit__c', 'Verbal Commit',
            opp.Verbal_Commit__c, 'CONSULT_TO_CLOSING'));

        return fields;
    }

    private static QualificationField buildTextField(
        String fieldName, String label, String value, String stageGate
    ) {
        QualificationField qf = new QualificationField();
        qf.fieldName = fieldName;
        qf.label = label;
        qf.fieldType = 'text';
        qf.value = value;
        qf.isNewlyPopulated = String.isNotBlank(value);
        qf.stageGate = stageGate;
        return qf;
    }

    private static QualificationField buildBooleanField(
        String fieldName, String label, Boolean value, String stageGate
    ) {
        QualificationField qf = new QualificationField();
        qf.fieldName = fieldName;
        qf.label = label;
        qf.fieldType = 'boolean';
        qf.value = value;
        qf.isNewlyPopulated = (value == true);
        qf.stageGate = stageGate;
        return qf;
    }

    /**
     * Query the source record (Talkdesk Activity or AI_Call_Note__c) and populate
     * callNotes on the PostCallContext.
     * AI_Call_Note → Customer_Story__c, Talkdesk → talkdesk__Notes__c.
     */
    private static void populateSourceFields(
        PostCallContext ctx, String sourceType, Id sourceRecordId
    ) {
        try {
            if (sourceType == 'AI_Call_Note') {
                List<AI_Call_Note__c> notes = [
                    SELECT Customer_Story__c
                    FROM AI_Call_Note__c
                    WHERE Id = :sourceRecordId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                if (!notes.isEmpty()) {
                    ctx.callNotes = notes[0].Customer_Story__c;
                }
            } else if (sourceType == 'Talkdesk') {
                List<talkdesk__Talkdesk_Activity__c> activities = [
                    SELECT talkdesk__Notes__c
                    FROM talkdesk__Talkdesk_Activity__c
                    WHERE Id = :sourceRecordId
                    WITH SECURITY_ENFORCED
                    LIMIT 1
                ];
                if (!activities.isEmpty()) {
                    ctx.callNotes = activities[0].talkdesk__Notes__c;
                }
            }
        } catch (Exception e) {
            // Graceful degradation if source object is inaccessible
            System.debug(LoggingLevel.WARN,
                'Post-call source query failed for ' + sourceType + ': ' + e.getMessage());
        }
    }

    // ─── Call Notes: Save ────────────────────────────────────────────

    /**
     * Save call notes as a ContentNote linked to the Opportunity.
     * Called from the LWC after a Call_Completed_Event__e is received.
     * No NBA_Queue__c interaction — Platform Events are transient.
     * @param opportunityId The Opportunity to save notes to
     * @param notes Edited call notes (may be blank)
     * @return Boolean true if notes were saved, false if blank/skipped
     */
    @AuraEnabled
    public static Boolean saveCallNotes(Id opportunityId, String notes) {
        if (String.isBlank(notes) || opportunityId == null) {
            return false;
        }

        ContentNote cn = new ContentNote();
        cn.Title = 'Call Notes';
        cn.Content = Blob.valueOf(notes);
        insert cn;

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = cn.Id;
        cdl.LinkedEntityId = opportunityId;
        cdl.ShareType = 'V';
        insert cdl;

        return true;
    }

    // ─── Post-Call: Save Edits ────────────────────────────────────────

    /**
     * Save edited qualification fields and call notes from the Post-Call Panel.
     * Guardrails mirror the qualification sync rules:
     *   - Text/Picklist fields: write only if current Opp value is blank
     *   - Checkbox fields: ratchet only (false→true, never true→false)
     * Notes saved as ContentNote linked to the Opportunity (reuses saveCallNotes pattern).
     * @param opportunityId The Opportunity to update
     * @param notes Edited call notes (may be blank — skips ContentNote if so)
     * @param fieldEdits Map of field API name → new value from the AE's edits
     * @return true on success
     */
    @AuraEnabled
    public static Boolean savePostCallEdits(
        Id opportunityId, String notes, Map<String, Object> fieldEdits
    ) {
        if (opportunityId == null) {
            return false;
        }

        // 1. Query current Opp values for guardrail checks (1 SOQL)
        List<Opportunity> opps = [
            SELECT Customer_Story__c, Decision_Maker_Identified__c,
                   Inception_or_Switcher__c, Business_Challenge__c,
                   Best_Product_Fit_Identified__c, Features_and_Benefits_Discussed__c,
                   Budget_Confirmed__c, Timeline_Confirmed__c, Verbal_Commit__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (opps.isEmpty()) {
            return false;
        }
        Opportunity opp = opps[0];

        // 2. Apply field edits with guardrails
        Boolean hasFieldChanges = false;
        if (fieldEdits != null && !fieldEdits.isEmpty()) {
            for (String fieldName : fieldEdits.keySet()) {
                Object newVal = fieldEdits.get(fieldName);
                Object currentVal = opp.get(fieldName);

                if (BOOLEAN_QUAL_FIELDS.contains(fieldName)) {
                    // Checkbox ratchet: only false→true
                    Boolean currentBool = (currentVal == true);
                    Boolean newBool = (newVal == true || newVal == 'true');
                    if (!currentBool && newBool) {
                        opp.put(fieldName, true);
                        hasFieldChanges = true;
                    }
                } else {
                    // Text/Picklist: write only if current value is blank
                    String currentStr = (currentVal == null) ? '' : String.valueOf(currentVal);
                    String newStr = (newVal == null) ? '' : String.valueOf(newVal);
                    if (String.isBlank(currentStr) && String.isNotBlank(newStr)) {
                        opp.put(fieldName, newStr);
                        hasFieldChanges = true;
                    }
                }
            }
            if (hasFieldChanges) {
                update opp; // 1 DML
            }
        }

        // 3. Save notes as ContentNote (reuse saveCallNotes pattern)
        if (String.isNotBlank(notes)) {
            ContentNote cn = new ContentNote();
            cn.Title = 'Post-Call Notes';
            cn.Content = Blob.valueOf(notes);
            insert cn;

            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = cn.Id;
            cdl.LinkedEntityId = opportunityId;
            cdl.ShareType = 'V';
            insert cdl; // 1-2 DML
        }

        return true;
    }

    // Boolean qualification fields (for checkbox ratchet guardrail)
    private static final Set<String> BOOLEAN_QUAL_FIELDS = new Set<String>{
        'Decision_Maker_Identified__c', 'Best_Product_Fit_Identified__c',
        'Budget_Confirmed__c', 'Timeline_Confirmed__c', 'Verbal_Commit__c'
    };

    // ─── Follow-Up ────────────────────────────────────────────────────

    /**
     * Create a follow-up Task on the Opportunity and pause the cadence.
     * Called from nbaFollowUpModal LWC after a completed call.
     *
     * @param opportunityId  The Opportunity to create the follow-up on
     * @param method         Follow-up method (Call, Email, SMS, Meeting)
     * @param followUpDt     When the follow-up should surface
     * @param notes          Optional AE notes
     * @return The created Task ID
     */
    @AuraEnabled
    public static Id createFollowUp(Id opportunityId, String method, Datetime followUpDt, String notes) {
        return NbaFollowUpService.createFollowUp(opportunityId, method, followUpDt, notes);
    }

    // ─── On-Demand Evaluation Pipeline ──────────────────────────────

    /**
     * Full on-demand evaluation: query AE's Opps → signals → create → rank → return top.
     * ~11 SOQL queries (1 Opps + 7 signals + 3 CMDT via creation).
     */
    private static ActionWrapper evaluateOnDemand(Id userId) {
        // Query AE's open Opportunities
        List<Opportunity> opps = [
            SELECT Id
            FROM Opportunity
            WHERE OwnerId = :userId
              AND IsClosed = false
              AND StageName NOT IN :EXCLUDED_STAGES
            WITH SECURITY_ENFORCED
            ORDER BY Amount DESC NULLS LAST, CreatedDate DESC
            LIMIT 200
        ];

        if (opps.isEmpty()) {
            return null;
        }

        Set<Id> oppIds = new Set<Id>();
        for (Opportunity o : opps) {
            oppIds.add(o.Id);
        }

        // Get signals (7 SOQL)
        Map<Id, NbaSignalService.OpportunitySignal> signals =
            NbaSignalService.getSignals(oppIds);

        if (signals.isEmpty()) {
            return null;
        }

        // Evaluate and create in-memory candidates (3-4 SOQL for CMDT)
        NbaActionCreationService.CreationResult result =
            NbaActionCreationService.evaluateAndCreate(signals);

        if (result.actionsToCreate.isEmpty()) {
            return null;
        }

        // Rank candidates (1 SOQL for cooldown rules)
        List<NbaActionSelectionService.RankedAction> ranked =
            NbaActionSelectionService.rankActions(result.actionsToCreate);

        if (ranked.isEmpty()) {
            return null;
        }

        // Return the top-ranked candidate as an ActionWrapper
        NBA_Queue__c topCandidate = ranked[0].action;
        ActionWrapper wrapper = toWrapperFromCandidate(topCandidate);

        // Generate tags and populate payroll probability from signal data
        NbaSignalService.OpportunitySignal signal = signals.get(topCandidate.Opportunity__c);
        if (signal != null) {
            List<NbaTagService.Tag> tags = NbaTagService.generateTags(wrapper, signal);
            wrapper.actionTags = NbaTagService.toJson(tags);
            wrapper.payrollProbability = signal.probPayrollConversion;
        }

        return wrapper;
    }

    // ─── Private Helpers ────────────────────────────────────────────

    /**
     * Check for Layer 1 interrupt actions in the DB.
     * Returns:
     *   - Meetings with DueAt within 5 minutes (not 24h)
     *   - New-assignment interrupts (Source_Path='Immediate', Is_Time_Bound=false) created within 24h
     * Excludes 'In Progress' records (already accepted by acceptInterrupt).
     * Excludes 'Call Completed' actions (now delivered via Platform Events).
     */
    private static List<ActionWrapper> checkInterruptsInternal(Id userId) {
        List<ActionWrapper> interrupts = new List<ActionWrapper>();

        // Query 1: Time-bound meetings starting within 5 minutes
        // Event_Start_DateTime__c = meeting start (for surfacing), DueAt__c = meeting end (for expiration)
        Datetime fiveMinFromNow = Datetime.now().addMinutes(5);
        List<NBA_Queue__c> meetings = [
            SELECT Id, Opportunity__c, Account__c, Action_Type__c,
                   Action_Instruction__c, ReasonText__c, Rule_Name__c,
                   Priority_Score__c, Is_Time_Bound__c,
                   DueAt__c, Event_Start_DateTime__c, Status__c, UniqueKey__c,
                   Account__r.Name, Opportunity__r.Name, Opportunity__r.StageName
            FROM NBA_Queue__c
            WHERE Sales_Rep__c = :userId
              AND Rule_Name__c = 'Meeting_TimeBound'
              AND Status__c IN ('New', 'Pending', 'Accepted')
              AND Event_Start_DateTime__c != null
              AND Event_Start_DateTime__c <= :fiveMinFromNow
              AND DueAt__c >= :Datetime.now()
            WITH SECURITY_ENFORCED
            ORDER BY Event_Start_DateTime__c ASC
            LIMIT 5
        ];
        for (NBA_Queue__c m : meetings) {
            interrupts.add(toWrapperFromRecord(m));
        }

        // Query 2: New-assignment interrupts (time-bound, 5-min SLA window)
        // These are now Is_Time_Bound__c = true with DueAt__c = creation timestamp
        List<NBA_Queue__c> assignments = [
            SELECT Id, Opportunity__c, Account__c, Action_Type__c,
                   Action_Instruction__c, ReasonText__c, Rule_Name__c,
                   Priority_Score__c, Is_Time_Bound__c,
                   DueAt__c, Status__c, UniqueKey__c,
                   Account__r.Name, Opportunity__r.Name, Opportunity__r.StageName
            FROM NBA_Queue__c
            WHERE Sales_Rep__c = :userId
              AND Rule_Name__c = 'NewAssignment_Interrupt'
              AND Status__c IN ('New', 'Pending', 'Accepted')
            WITH SECURITY_ENFORCED
            ORDER BY DueAt__c DESC
            LIMIT 5
        ];
        for (NBA_Queue__c a : assignments) {
            interrupts.add(toWrapperFromRecord(a));
        }

        return interrupts;
    }

    /**
     * Build ActionResultWrapper by re-evaluating after an AE interaction.
     */
    private static ActionResultWrapper buildResultFromEvaluation(Id userId) {
        ActionResultWrapper result = new ActionResultWrapper();
        ActionWrapper next = getActiveAction();
        result.nextAction = next;
        result.hasNext = (next != null);
        return result;
    }

    /**
     * Convert a DB-queried NBA_Queue__c record to ActionWrapper.
     * Used for Layer 1 time-bound actions that live in the database.
     */
    private static ActionWrapper toWrapperFromRecord(NBA_Queue__c action) {
        ActionWrapper w = new ActionWrapper();
        w.actionId = action.Id;
        w.opportunityId = action.Opportunity__c;
        w.accountId = action.Account__c;
        w.actionType = action.Action_Type__c;
        w.actionInstruction = action.Action_Instruction__c;
        w.reasonText = action.ReasonText__c;
        w.priorityScore = action.Priority_Score__c;
        w.isTimeBound = action.Is_Time_Bound__c;
        w.dueAt = action.DueAt__c;
        w.status = action.Status__c;
        w.accountName = action.Account__r?.Name;
        w.opportunityName = action.Opportunity__r?.Name;
        w.oppStage = action.Opportunity__r?.StageName;

        // Parse eventId from UniqueKey for Meeting actions (format: V2|oppId|Meeting|eventId)
        if (action.Action_Type__c == 'Meeting' && action.UniqueKey__c != null) {
            List<String> parts = action.UniqueKey__c.split('\\|');
            if (parts.size() >= 4) {
                w.eventId = parts[3];
            }
        }

        // Layer 1 actions are interrupts (meetings, new assignments), not cadence
        w.isCadenceAction = false;

        // Set clear contextual reason for Layer 1 interrupt types
        if (String.isBlank(w.reasonText)) {
            if (action.Action_Type__c == 'Meeting') {
                w.reasonText = 'Upcoming meeting — review context and prepare.';
            } else if (action.Rule_Name__c == 'NewAssignment_Interrupt') {
                w.reasonText = 'Newly assigned opportunity — make initial contact.';
            }
        }

        return w;
    }

    /**
     * Convert an in-memory NBA_Queue__c candidate to ActionWrapper.
     * Used for on-demand evaluated actions (not persisted to DB).
     * actionId is null since there's no DB record.
     */
    private static ActionWrapper toWrapperFromCandidate(NBA_Queue__c candidate) {
        ActionWrapper w = new ActionWrapper();
        w.actionId = null; // On-demand — no DB record
        w.opportunityId = candidate.Opportunity__c;
        w.accountId = candidate.Account__c;
        w.actionType = candidate.Action_Type__c;
        w.actionInstruction = candidate.Action_Instruction__c;
        w.reasonText = candidate.ReasonText__c;
        w.priorityScore = candidate.Priority_Score__c;
        w.isTimeBound = candidate.Is_Time_Bound__c;
        w.dueAt = candidate.DueAt__c;
        w.status = 'Evaluated';

        // Relationship fields not available on in-memory record —
        // the LWC will get these from getPageData(oppId)
        w.accountName = null;
        w.opportunityName = null;
        w.oppStage = candidate.Opportunity_Stage__c;

        // Phase 7: Map cadence fields from CadenceResult (replaces Phase 6 CadenceStep)
        NbaCadenceService.CadenceResult cadResult =
            NbaCadenceService.lastEvaluatedResults.get(candidate.Opportunity__c);
        if (cadResult != null && cadResult.currentStep != null) {
            w.isCadenceAction = true;
            w.cadenceName = cadResult.cadenceName;
            w.cadenceStepNumber = cadResult.currentStep.stepNumber;
            w.cadenceTotalSteps = cadResult.context != null ? cadResult.context.totalSteps : null;
            w.stepMethod = cadResult.currentStep.method;
            w.stepInstruction = cadResult.currentStep.instructionText;
            w.cadenceProgress = cadResult.progressText;
            w.progressFraction = cadResult.progressFraction;
            w.upcomingSteps = cadResult.upcomingSteps;
        } else {
            w.isCadenceAction = false;
        }

        return w;
    }

    /**
     * Get the AccountId for an Opportunity (1 SOQL).
     */
    private static Id getAccountId(Id opportunityId) {
        if (opportunityId == null) {
            return null;
        }
        List<Opportunity> opps = [
            SELECT AccountId FROM Opportunity
            WHERE Id = :opportunityId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        return opps.isEmpty() ? null : opps[0].AccountId;
    }

    // ─── Wrapper Classes ────────────────────────────────────────────

    public class ActionWrapper {
        @AuraEnabled public Id actionId;         // null for on-demand, real ID for Layer 1
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String actionType;
        @AuraEnabled public String actionInstruction;
        @AuraEnabled public String reasonText;
        @AuraEnabled public Decimal priorityScore;
        @AuraEnabled public Boolean isTimeBound;
        @AuraEnabled public Datetime dueAt;
        @AuraEnabled public String status;
        @AuraEnabled public String accountName;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String oppStage;
        // Phase 7: Cadence fields (replaces Phase 6)
        @AuraEnabled public String cadenceName;
        @AuraEnabled public Integer cadenceStepNumber;
        @AuraEnabled public Integer cadenceTotalSteps;
        @AuraEnabled public String stepMethod;        // Call, SMS, Email
        @AuraEnabled public String stepInstruction;   // Human-readable step instruction
        @AuraEnabled public String cadenceProgress;   // "Step 3 of 12 — Day 0, SMS"
        @AuraEnabled public String progressFraction;  // "3/12"
        @AuraEnabled public List<String> upcomingSteps; // Next 2-3 step previews
        @AuraEnabled public Boolean isCadenceAction;
        @AuraEnabled public String eventId;          // Event ID parsed from UniqueKey for Meeting actions
        @AuraEnabled public String actionTags;        // JSON from NbaTagService.toJson() — DS driver tags for engine actions, time-bound rationale for interrupts
        @AuraEnabled public Decimal payrollProbability; // Prob_Payroll_Conversion (0-1) for separate UI display
    }

    public class ActionResultWrapper {
        @AuraEnabled public ActionWrapper nextAction;
        @AuraEnabled public Boolean hasNext;
    }

    public class PostCallContext {
        @AuraEnabled public String opportunityId;
        @AuraEnabled public String previousStage;
        @AuraEnabled public String currentStage;
        @AuraEnabled public Boolean stageChanged;
        @AuraEnabled public List<QualificationField> qualificationFields;
        @AuraEnabled public String callNotes;
        @AuraEnabled public String sourceType;
    }

    public class QualificationField {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String label;
        @AuraEnabled public String fieldType;
        @AuraEnabled public Object value;
        @AuraEnabled public Boolean isNewlyPopulated;
        @AuraEnabled public String stageGate;
    }
}
