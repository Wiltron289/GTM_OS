/**
 * NbaTalkdeskActivityTriggerHandler — Processes Talkdesk Activity records for GTM OS.
 *
 * Fires on AFTER INSERT and AFTER UPDATE of talkdesk__Talkdesk_Activity__c.
 *
 * Responsibilities:
 * 1. Disposition detection: Connected / VM / No Answer
 * 2. 24hr cooldown on Connected: writes audit record with CooldownUntil__c
 * 3. Cadence step advancement: writes Step_Outcome__c on audit record
 * 4. Outcome-conditional auto-send: in New stage + not connected, creates Pending automated NBA_Queue__c
 * 5. ContentNote creation: saves Talkdesk call notes as Note on Opportunity
 * 6. Platform Event publishing: Call_Completed_Event__e for LWC call notes overlay
 * 7. Cache invalidation for affected AEs
 *
 * SOQL budget: 4 (Opp query + Activity detail query + existing audit query + cadence CMDT).
 * Bulk-safe.
 */
public with sharing class NbaTalkdeskActivityTriggerHandler {

    @TestVisible
    static List<Call_Completed_Event__e> lastPublishedEvents;

    // Expose for test assertions
    @TestVisible
    static List<NBA_Queue__c> lastCreatedAutoSendActions;

    // Default cooldown after connected call (24 hours = 1440 minutes)
    private static final Integer CONNECTION_COOLDOWN_MINUTES = 1440;

    public static void handle(
        List<talkdesk__Talkdesk_Activity__c> newList,
        Map<Id, talkdesk__Talkdesk_Activity__c> oldMap,
        System.TriggerOperation operationType
    ) {
        if (NbaTriggerContext.hasTalkdeskActivityHandlerRun()) {
            return;
        }
        NbaTriggerContext.setTalkdeskActivityHandlerRun();

        // Filter qualifying activities
        List<talkdesk__Talkdesk_Activity__c> qualifying = filterQualifying(newList, oldMap, operationType);
        if (qualifying.isEmpty()) {
            return;
        }

        // Collect Opp IDs and Activity IDs from qualifying activities
        Set<Id> oppIds = new Set<Id>();
        Set<Id> activityIds = new Set<Id>();
        for (talkdesk__Talkdesk_Activity__c ta : qualifying) {
            oppIds.add(ta.talkdesk__Opportunity__c);
            activityIds.add(ta.Id);
        }

        // Query Opportunities for OwnerId + Name + Account.Name + StageName (1 SOQL)
        Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>([
            SELECT Id, AccountId, OwnerId, Name, StageName, Account.Name
            FROM Opportunity
            WHERE Id IN :oppIds
            WITH SECURITY_ENFORCED
        ]);

        // Query Activity details for disposition + talk time + notes (1 SOQL)
        Map<Id, talkdesk__Talkdesk_Activity__c> activityDetailMap = new Map<Id, talkdesk__Talkdesk_Activity__c>([
            SELECT Id, talkdesk__Notes__c, talkdesk__Total_Talk_Time_sec__c,
                   talkdesk__DispositionCode__r.talkdesk__Label__c
            FROM talkdesk__Talkdesk_Activity__c
            WHERE Id IN :activityIds
            WITH SECURITY_ENFORCED
        ]);

        // Query most recent completed audit records for these opps (for cadence advancement) (1 SOQL)
        Map<Id, NBA_Queue__c> latestAuditByOpp = queryLatestAuditRecords(oppIds);

        // Build Platform Events + process disposition logic
        List<Call_Completed_Event__e> events = new List<Call_Completed_Event__e>();
        List<NBA_Queue__c> auditRecordsToInsert = new List<NBA_Queue__c>();
        List<NBA_Queue__c> autoSendActionsToInsert = new List<NBA_Queue__c>();
        List<ContentNote> notesToInsert = new List<ContentNote>();
        // Track opp→note index for ContentDocumentLink creation after insert
        List<Id> noteOppIds = new List<Id>();
        Set<Id> affectedAeIds = new Set<Id>();

        for (talkdesk__Talkdesk_Activity__c ta : qualifying) {
            Opportunity opp = oppMap.get(ta.talkdesk__Opportunity__c);
            if (opp == null) {
                continue;
            }

            talkdesk__Talkdesk_Activity__c detail = activityDetailMap.get(ta.Id);
            String disposition = detail?.talkdesk__DispositionCode__r.talkdesk__Label__c;
            Decimal talkTime = detail?.talkdesk__Total_Talk_Time_sec__c;
            String notes = detail?.talkdesk__Notes__c;

            // ─── 1. Disposition Detection ────────────────────────────
            String outcome = classifyDisposition(disposition, talkTime);

            // ─── 2. Platform Event (existing behavior) ──────────────
            Call_Completed_Event__e evt = new Call_Completed_Event__e(
                Opportunity_Id__c = String.valueOf(opp.Id),
                Activity_Id__c = String.valueOf(ta.Id),
                Sales_Rep_Id__c = String.valueOf(opp.OwnerId),
                Call_Notes__c = notes,
                Talk_Time_Sec__c = talkTime,
                Disposition__c = disposition,
                Account_Name__c = opp.Account?.Name,
                Opp_Name__c = opp.Name,
                Source_Type__c = 'Talkdesk',
                Source_Record_Id__c = String.valueOf(ta.Id)
            );
            events.add(evt);
            affectedAeIds.add(opp.OwnerId);

            // ─── 3. Cadence Step Advancement (audit record) ─────────
            NBA_Queue__c latestAudit = latestAuditByOpp.get(opp.Id);
            Integer lastStepNumber = 0;
            String lastCadenceName = null;
            if (latestAudit != null) {
                lastStepNumber = latestAudit.Cadence_Step_Number__c != null
                    ? Integer.valueOf(latestAudit.Cadence_Step_Number__c) : 0;
                lastCadenceName = latestAudit.Cadence_Name__c;
            }

            // Write audit record with step outcome + optional cooldown
            Datetime cooldownUntil = null;
            if (outcome == 'Connected') {
                cooldownUntil = Datetime.now().addMinutes(CONNECTION_COOLDOWN_MINUTES);
            }

            NBA_Queue__c audit = new NBA_Queue__c(
                Opportunity__c = opp.Id,
                Account__c = opp.AccountId,
                Sales_Rep__c = opp.OwnerId,
                Status__c = 'Completed',
                Action_Type__c = 'Call',
                Source_Path__c = 'Pipeline Cadence',
                Workflow_Mode__c = 'Pipeline',
                Step_Outcome__c = outcome,
                Completed_Date__c = Datetime.now(),
                Actioned_Date__c = Datetime.now(),
                LastEvaluatedAt__c = Datetime.now(),
                Cadence_Step_Number__c = lastStepNumber,
                Cadence_Name__c = lastCadenceName,
                Step_Method__c = 'Call',
                Opportunity_Stage__c = opp.StageName
            );
            if (cooldownUntil != null) {
                audit.CooldownUntil__c = cooldownUntil;
            }
            auditRecordsToInsert.add(audit);

            // ─── 4. Outcome-Conditional Auto-Send (New stage only) ──
            if (outcome != 'Connected' && opp.StageName == 'New') {
                NBA_Queue__c autoAction = buildAutoSendAction(
                    opp, lastStepNumber, lastCadenceName
                );
                if (autoAction != null) {
                    autoSendActionsToInsert.add(autoAction);
                }
            }

            // ─── 5. ContentNote Creation ─────────────────────────────
            if (String.isNotBlank(notes)) {
                String title = 'Call Summary — '
                    + (opp.Account?.Name != null ? opp.Account.Name : 'Unknown')
                    + ' — ' + Date.today().format();
                ContentNote note = new ContentNote();
                note.Title = title.left(255);
                note.Content = Blob.valueOf(notes);
                notesToInsert.add(note);
                noteOppIds.add(opp.Id);
            }
        }

        // ─── DML ────────────────────────────────────────────────────

        // Publish Platform Events
        if (!events.isEmpty()) {
            lastPublishedEvents = events;
            EventBus.publish(events);
        }

        // Insert audit records (cadence advancement + cooldown)
        if (!auditRecordsToInsert.isEmpty()) {
            insert auditRecordsToInsert;
        }

        // Insert auto-send actions
        if (!autoSendActionsToInsert.isEmpty()) {
            lastCreatedAutoSendActions = autoSendActionsToInsert;
            insert autoSendActionsToInsert;
        }

        // Insert ContentNotes + link to Opportunities
        // ContentNote has platform limitations on bulk insert — use try/catch
        if (!notesToInsert.isEmpty()) {
            try {
                insert notesToInsert;

                List<ContentDocumentLink> links = new List<ContentDocumentLink>();
                for (Integer i = 0; i < notesToInsert.size(); i++) {
                    links.add(new ContentDocumentLink(
                        ContentDocumentId = notesToInsert[i].Id,
                        LinkedEntityId = noteOppIds[i],
                        ShareType = 'V',
                        Visibility = 'AllUsers'
                    ));
                }
                insert links;
            } catch (Exception e) {
                // ContentNote bulk creation can fail in certain contexts
                // Log but don't fail the entire transaction
                System.debug(LoggingLevel.WARN,
                    'ContentNote creation failed: ' + e.getMessage());
            }
        }

        // Invalidate cache for affected AEs
        NbaCacheService.invalidateForUsers(affectedAeIds);
    }

    // ─── Disposition Classification ─────────────────────────────────

    /**
     * Classify Talkdesk disposition into outcome for cadence branching.
     * - "Connected" + talk_time > 0 → Connected (meaningful conversation)
     * - Contains "VM" or "Voicemail" → VM (left voicemail)
     * - Everything else → No_Answer
     */
    @TestVisible
    static String classifyDisposition(String disposition, Decimal talkTimeSec) {
        if (disposition == null) {
            return 'No_Answer';
        }

        String dispUpper = disposition.toUpperCase();

        // Connected: disposition contains "Connected" AND talk time > 0
        if (dispUpper.contains('CONNECTED') && talkTimeSec != null && talkTimeSec > 0) {
            return 'Connected';
        }

        // Left Voicemail: disposition contains "VM" or "Voicemail"
        if (dispUpper.contains('VM') || dispUpper.contains('VOICEMAIL')) {
            return 'VM';
        }

        // Everything else: No Answer
        return 'No_Answer';
    }

    // ─── Auto-Send Action Builder ───────────────────────────────────

    /**
     * Build an automated SMS/Email NBA_Queue__c action for outcome-conditional
     * auto-send in the New stage. The next step after the call should be an
     * Automated SMS or Email.
     *
     * Returns null if no automated next step is appropriate.
     */
    @TestVisible
    static NBA_Queue__c buildAutoSendAction(
        Opportunity opp, Integer lastStepNumber, String cadenceName
    ) {
        // The next step number after the current call
        Integer nextStepNumber = lastStepNumber + 1;

        // We need to look up the cadence step to confirm it's automated
        // Use NbaCadenceService's loaded cadences to find the step
        Map<String, NbaCadenceService.CadenceContext> ctxMap =
            NbaCadenceService.loadAndParseCadences();

        if (ctxMap == null || ctxMap.isEmpty()) {
            return null;
        }

        // Find the cadence context — try stage-based lookup first
        NbaCadenceService.CadenceContext ctx = null;
        if (NbaCadenceService.stageCadenceMap != null) {
            String stageKey = 'New|A';
            ctx = NbaCadenceService.stageCadenceMap.get(stageKey);
        }
        if (ctx == null && cadenceName != null) {
            // Fallback: search all cadences by name
            for (NbaCadenceService.CadenceContext c : ctxMap.values()) {
                if (c.cadenceName == cadenceName) {
                    ctx = c;
                    break;
                }
            }
        }
        if (ctx == null || ctx.steps == null || ctx.steps.isEmpty()) {
            return null;
        }

        // Find the next step
        NbaCadenceService.CadenceStepDef nextStep = null;
        for (NbaCadenceService.CadenceStepDef step : ctx.steps) {
            if (step.stepNumber == nextStepNumber) {
                nextStep = step;
                break;
            }
        }

        // Only create auto-send if next step is Automated (SMS or Email)
        if (nextStep == null || nextStep.executionType != 'Automated') {
            return null;
        }

        NBA_Queue__c action = new NBA_Queue__c(
            Opportunity__c = opp.Id,
            Account__c = opp.AccountId,
            Sales_Rep__c = opp.OwnerId,
            Status__c = 'Pending',
            Action_Type__c = nextStep.method == 'SMS' ? 'First Touch' : 'First Touch',
            Step_Method__c = nextStep.method,
            Execution_Type__c = 'Automated',
            Automated_Send_Status__c = 'Pending',
            Template_Name__c = nextStep.templateName,
            Scheduled_Send_Time__c = Datetime.now(),
            Source_Path__c = 'Immediate',
            Workflow_Mode__c = 'Pipeline',
            Cadence_Name__c = ctx.cadenceName,
            Cadence_Step_Number__c = nextStep.stepNumber,
            Opportunity_Stage__c = opp.StageName,
            Action_Instruction__c = nextStep.instructionText,
            LastEvaluatedAt__c = Datetime.now(),
            UniqueKey__c = 'V2|' + opp.Id + '|AutoSend|Step' + nextStep.stepNumber
        );

        return action;
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    /**
     * Filter qualifying Talkdesk Activities:
     * - AFTER_INSERT: talkdesk__Opportunity__c is populated
     * - AFTER_UPDATE: talkdesk__Opportunity__c changed from null to non-null
     */
    private static List<talkdesk__Talkdesk_Activity__c> filterQualifying(
        List<talkdesk__Talkdesk_Activity__c> activities,
        Map<Id, talkdesk__Talkdesk_Activity__c> oldMap,
        System.TriggerOperation operationType
    ) {
        List<talkdesk__Talkdesk_Activity__c> result = new List<talkdesk__Talkdesk_Activity__c>();
        for (talkdesk__Talkdesk_Activity__c ta : activities) {
            if (ta.talkdesk__Opportunity__c == null) {
                continue;
            }

            if (operationType == System.TriggerOperation.AFTER_INSERT) {
                result.add(ta);
            } else if (operationType == System.TriggerOperation.AFTER_UPDATE) {
                talkdesk__Talkdesk_Activity__c old = oldMap.get(ta.Id);
                if (old.talkdesk__Opportunity__c == null) {
                    result.add(ta);
                }
            }
        }
        return result;
    }

    /**
     * Query most recent completed audit NBA_Queue__c records per Opportunity.
     * Used for cadence position tracking (last step number, cadence name).
     */
    private static Map<Id, NBA_Queue__c> queryLatestAuditRecords(Set<Id> oppIds) {
        Map<Id, NBA_Queue__c> result = new Map<Id, NBA_Queue__c>();
        if (oppIds == null || oppIds.isEmpty()) {
            return result;
        }

        List<NBA_Queue__c> audits = [
            SELECT Id, Opportunity__c, Cadence_Name__c, Cadence_Step_Number__c,
                   Step_Outcome__c, Step_Method__c, CooldownUntil__c
            FROM NBA_Queue__c
            WHERE Opportunity__c IN :oppIds
              AND Status__c = 'Completed'
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];

        for (NBA_Queue__c audit : audits) {
            if (!result.containsKey(audit.Opportunity__c)) {
                result.put(audit.Opportunity__c, audit);
            }
        }

        return result;
    }
}
