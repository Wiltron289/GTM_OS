import { LightningElement, api, track, wire } from 'lwc';
import sendEmail from '@salesforce/apex/NbaDemoController.sendEmail';
import getEmailTemplates from '@salesforce/apex/NbaDemoController.getEmailTemplates';

export default class NbaDemoEmailModal extends LightningElement {
    @api contacts;
    @api recordId;
    @api selectedContact;
    @track selectedContactId;
    @track selectedTemplateId = '';
    @track emailSubject = '';
    @track emailBody = '';
    @track isSending = false;
    @track templates = [];

    @wire(getEmailTemplates)
    wiredTemplates({ data, error }) {
        if (data) {
            this.templates = data;
        } else if (error) {
            console.error('Error loading email templates:', error);
        }
    }

    connectedCallback() {
        if (this.selectedContact) {
            this.selectedContactId = this.selectedContact;
        } else {
            const list = Array.isArray(this.contacts) ? this.contacts : [];
            if (list.length > 0) {
                this.selectedContactId = list[0].contactId;
            }
        }
    }

    get contactList() {
        return Array.isArray(this.contacts) ? this.contacts : [];
    }

    get contactOptions() {
        return this.contactList.map(c => ({
            label: c.name + (c.title ? ' - ' + c.title : ''),
            value: c.contactId
        }));
    }

    get templateOptions() {
        const options = [{ label: '-- None --', value: '' }];
        if (this.templates) {
            this.templates.forEach(t => {
                options.push({ label: t.name, value: t.id });
            });
        }
        return options;
    }

    get selectedContactName() {
        const contact = this.contactList.find(c => c.contactId === this.selectedContactId);
        return contact ? contact.name : '';
    }

    get canSend() {
        return this.selectedContactId && this.emailSubject && this.emailBody && !this.isSending;
    }

    handleContactChange(event) {
        this.selectedContactId = event.detail.value;
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        if (this.selectedTemplateId) {
            const tmpl = this.templates.find(t => t.id === this.selectedTemplateId);
            if (tmpl) {
                if (tmpl.subject) this.emailSubject = tmpl.subject;
                if (tmpl.body) this.emailBody = tmpl.body;
            }
        }
    }

    handleSubjectChange(event) {
        this.emailSubject = event.target.value;
    }

    handleBodyChange(event) {
        this.emailBody = event.target.value;
    }

    async handleSend() {
        if (!this.canSend) return;
        this.isSending = true;
        try {
            await sendEmail({
                contactId: this.selectedContactId,
                subject: this.emailSubject,
                body: this.emailBody,
                templateId: this.selectedTemplateId || null
            });
            this.handleClose();
        } catch (error) {
            console.error('Error sending email:', error);
        } finally {
            this.isSending = false;
        }
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    stopPropagation(event) {
        event.stopPropagation();
    }
}
