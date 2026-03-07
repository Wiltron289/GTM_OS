/**
 * NbaAutomatedOutreachService — Automated SMS (Mogli) and Email sends for GTM OS.
 *
 * Handles system-executed cadence steps where Execution_Type__c = 'Automated'.
 * PRD Section 12: Automated Outreach Engine.
 *
 * Responsibilities:
 * - SMS send via Mogli_SMS__SMS__c record creation
 * - Email send via Messaging.SingleEmailMessage
 * - Compliance checks (opt-out, deliverability)
 * - Template lookup (Mogli SMS Template / Salesforce EmailTemplate)
 * - Activity logging on Opportunity
 * - NBA_Queue__c status updates (Sent/Failed/Skipped)
 */
public with sharing class NbaAutomatedOutreachService {

    // ─── Inner Classes ─────────────────────────────────────────────────

    public class OutreachResult {
        public String status;      // 'Sent', 'Failed', 'Skipped'
        public String reason;      // Reason for skip/failure
        public Id smsRecordId;     // Mogli SMS record ID (if SMS)
    }

    // ─── Primary Entry Point ───────────────────────────────────────────

    /**
     * Process a list of NBA_Queue__c records that are pending automated send.
     * Updates each record's Automated_Send_Status__c to Sent/Failed/Skipped.
     *
     * @param pendingActions NBA_Queue__c records with Automated_Send_Status__c = 'Pending'
     */
    public static void processAutomatedSends(List<NBA_Queue__c> pendingActions) {
        if (pendingActions == null || pendingActions.isEmpty()) {
            return;
        }

        // Collect Opportunity IDs to batch-query contact data
        Set<Id> oppIds = new Set<Id>();
        for (NBA_Queue__c action : pendingActions) {
            if (action.Opportunity__c != null) {
                oppIds.add(action.Opportunity__c);
            }
        }

        // Query primary contacts for each Opportunity via OpportunityContactRole
        Map<Id, Contact> oppToContact = queryPrimaryContacts(oppIds);

        List<NBA_Queue__c> toUpdate = new List<NBA_Queue__c>();

        for (NBA_Queue__c action : pendingActions) {
            Contact primaryContact = oppToContact.get(action.Opportunity__c);
            OutreachResult result;

            if (primaryContact == null) {
                result = new OutreachResult();
                result.status = 'Skipped';
                result.reason = 'No primary contact found on Opportunity';
            } else {
                String method = action.Step_Method__c;
                if (method == 'SMS') {
                    result = sendSms(primaryContact, action);
                } else if (method == 'Email') {
                    result = sendEmail(primaryContact, action);
                } else {
                    result = new OutreachResult();
                    result.status = 'Skipped';
                    result.reason = 'Unsupported method for automation: ' + method;
                }
            }

            action.Automated_Send_Status__c = result.status;
            if (result.status != 'Sent') {
                // Store skip/fail reason in the instruction field for audit visibility
                String existingInstruction = action.Action_Instruction__c != null
                    ? action.Action_Instruction__c : '';
                action.Action_Instruction__c =
                    (existingInstruction + ' [Auto: ' + result.reason + ']').left(255);
            }
            if (result.status == 'Sent') {
                action.Status__c = 'Completed';
                action.Completed_Date__c = Datetime.now();
            } else if (result.status == 'Skipped') {
                action.Status__c = 'Completed';
                action.Completed_Date__c = Datetime.now();
                action.Step_Outcome__c = 'Skipped';
            }
            toUpdate.add(action);
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // ─── SMS Send (Mogli) ──────────────────────────────────────────────

    /**
     * Send an SMS via Mogli record creation.
     * Checks: opt-out, valid phone number, template resolution.
     */
    @TestVisible
    static OutreachResult sendSms(Contact con, NBA_Queue__c action) {
        OutreachResult result = new OutreachResult();

        // Compliance: SMS opt-out
        if (con.Mogli_SMS__Mogli_Opt_Out__c == true) {
            result.status = 'Skipped';
            result.reason = 'SMS opt-out';
            return result;
        }

        // Compliance: valid phone number
        if (String.isBlank(con.Mogli_SMS__Mogli_Number__c)) {
            result.status = 'Skipped';
            result.reason = 'No SMS number';
            return result;
        }

        // Resolve template text
        String messageBody = resolveSmsTemplate(action.Template_Name__c);
        if (String.isBlank(messageBody)) {
            result.status = 'Skipped';
            result.reason = 'SMS template not found: ' + action.Template_Name__c;
            return result;
        }

        try {
            // Query gateway
            List<Mogli_SMS__Gateway__c> gateways = [
                SELECT Id
                FROM Mogli_SMS__Gateway__c
                WHERE Mogli_SMS__Inactive__c = false
                ORDER BY Name ASC
                LIMIT 1
            ];

            Mogli_SMS__SMS__c sms = new Mogli_SMS__SMS__c();
            sms.Mogli_SMS__Contact__c = con.Id;
            sms.Mogli_SMS__Opportunity__c = action.Opportunity__c;
            sms.Account__c = con.AccountId;
            sms.Mogli_SMS__Message__c = messageBody;
            sms.Mogli_SMS__Direction__c = 'Outgoing';
            sms.Mogli_SMS__Status__c = 'Queued';
            sms.Mogli_SMS__Phone_Number__c = con.Mogli_SMS__Mogli_Number__c;

            if (!gateways.isEmpty()) {
                sms.Mogli_SMS__Gateway__c = gateways[0].Id;
            }

            insert sms;

            result.status = 'Sent';
            result.smsRecordId = sms.Id;
        } catch (Exception e) {
            result.status = 'Failed';
            result.reason = 'SMS send error: ' + e.getMessage().left(200);
        }

        return result;
    }

    // ─── Email Send (Salesforce) ───────────────────────────────────────

    /**
     * Send an email via Messaging.SingleEmailMessage.
     * Checks: email opt-out, valid email, template resolution.
     */
    @TestVisible
    static OutreachResult sendEmail(Contact con, NBA_Queue__c action) {
        OutreachResult result = new OutreachResult();

        // Compliance: email opt-out
        if (con.HasOptedOutOfEmail == true) {
            result.status = 'Skipped';
            result.reason = 'Email opt-out';
            return result;
        }

        // Compliance: valid email
        if (String.isBlank(con.Email)) {
            result.status = 'Skipped';
            result.reason = 'No email address';
            return result;
        }

        // Resolve email template
        Id templateId = resolveEmailTemplate(action.Template_Name__c);

        try {
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setTargetObjectId(con.Id);
            mail.setWhatId(action.Opportunity__c);
            mail.setSaveAsActivity(true);

            if (templateId != null) {
                mail.setTemplateId(templateId);
            } else {
                // Fallback: simple email with template name as subject
                mail.setSubject('Follow-up: ' + (action.Template_Name__c != null
                    ? action.Template_Name__c.replace('_', ' ') : 'Automated Outreach'));
                mail.setPlainTextBody('This is an automated follow-up from your sales team.');
            }

            Messaging.SendEmailResult[] results = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ mail }, false
            );

            if (results[0].isSuccess()) {
                result.status = 'Sent';
            } else {
                result.status = 'Failed';
                result.reason = 'Email send failed: ' +
                    results[0].getErrors()[0].getMessage().left(200);
            }
        } catch (Exception e) {
            result.status = 'Failed';
            result.reason = 'Email send error: ' + e.getMessage().left(200);
        }

        return result;
    }

    // ─── Template Resolution ───────────────────────────────────────────

    /**
     * Resolve SMS template text from Mogli_SMS__SMS_Template__c by name.
     */
    @TestVisible
    static String resolveSmsTemplate(String templateName) {
        if (String.isBlank(templateName)) {
            return null;
        }
        List<Mogli_SMS__SMS_Template__c> templates = [
            SELECT Id, Mogli_SMS__Text__c
            FROM Mogli_SMS__SMS_Template__c
            WHERE Mogli_SMS__Name__c = :templateName
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Mogli_SMS__Text__c;
    }

    /**
     * Resolve Salesforce EmailTemplate ID by DeveloperName.
     */
    @TestVisible
    static Id resolveEmailTemplate(String templateName) {
        if (String.isBlank(templateName)) {
            return null;
        }
        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :templateName
              AND IsActive = true
            LIMIT 1
        ];
        return templates.isEmpty() ? null : templates[0].Id;
    }

    // ─── Contact Query ─────────────────────────────────────────────────

    /**
     * Query primary contacts for a set of Opportunities.
     * Uses OpportunityContactRole (IsPrimary) with fallback to any OCR.
     * Returns Map<OppId, Contact> with compliance-relevant fields.
     */
    @TestVisible
    static Map<Id, Contact> queryPrimaryContacts(Set<Id> oppIds) {
        Map<Id, Contact> oppToContact = new Map<Id, Contact>();
        if (oppIds == null || oppIds.isEmpty()) {
            return oppToContact;
        }

        // Query OCRs with contact fields needed for compliance + sending
        List<OpportunityContactRole> ocrs = [
            SELECT OpportunityId, ContactId, IsPrimary,
                   Contact.Id, Contact.Email, Contact.AccountId,
                   Contact.HasOptedOutOfEmail,
                   Contact.Mogli_SMS__Mogli_Number__c,
                   Contact.Mogli_SMS__Mogli_Opt_Out__c
            FROM OpportunityContactRole
            WHERE OpportunityId IN :oppIds
              AND ContactId != null
            ORDER BY IsPrimary DESC, CreatedDate ASC
        ];

        for (OpportunityContactRole ocr : ocrs) {
            // Take first contact per Opp (primary first due to ORDER BY)
            if (!oppToContact.containsKey(ocr.OpportunityId)) {
                oppToContact.put(ocr.OpportunityId, ocr.Contact);
            }
        }

        return oppToContact;
    }
}
