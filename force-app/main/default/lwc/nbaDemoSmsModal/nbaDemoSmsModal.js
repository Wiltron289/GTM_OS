import { LightningElement, api, track, wire } from 'lwc';
import sendSms from '@salesforce/apex/NbaDemoController.sendSms';
import getSmsTemplates from '@salesforce/apex/NbaDemoController.getSmsTemplates';

export default class NbaDemoSmsModal extends LightningElement {
    @api contacts;
    @api recordId;
    @api selectedContact;
    @track selectedContactId;
    @track selectedTemplateId = '';
    @track messageBody = '';
    @track isSending = false;
    @track sendError = '';
    @track templates = [];

    @wire(getSmsTemplates)
    wiredTemplates({ data, error }) {
        if (data) {
            this.templates = data;
        } else if (error) {
            console.error('Error loading SMS templates:', error);
        }
    }

    connectedCallback() {
        if (this.selectedContact) {
            this.selectedContactId = this.selectedContact.contactId || this.selectedContact;
        } else {
            const eligible = this.smsEligibleContacts;
            if (eligible.length > 0) {
                this.selectedContactId = eligible[0].contactId;
            }
        }
    }

    get contactList() {
        return Array.isArray(this.contacts) ? this.contacts : [];
    }

    get smsEligibleContacts() {
        return this.contactList.filter(c => c.mogliNumber && !c.optedOut);
    }

    get contactOptions() {
        return this.contactList.map(c => ({
            label: c.name
                + (c.mogliNumber ? ' - ' + c.mogliNumber : ' (no SMS number)')
                + (c.optedOut ? ' [OPTED OUT]' : ''),
            value: c.contactId,
            disabled: !c.mogliNumber || c.optedOut
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

    get selectedPhoneNumber() {
        const contact = this.contactList.find(c => c.contactId === this.selectedContactId);
        return contact?.mogliNumber || 'No SMS number';
    }

    get isSelectedOptedOut() {
        const contact = this.contactList.find(c => c.contactId === this.selectedContactId);
        return contact?.optedOut === true;
    }

    get hasNoSmsNumber() {
        const contact = this.contactList.find(c => c.contactId === this.selectedContactId);
        return !contact?.mogliNumber;
    }

    get characterCount() {
        return (this.messageBody || '').length;
    }

    get segmentCount() {
        const len = this.characterCount;
        if (len === 0) return 0;
        return Math.ceil(len / 160);
    }

    get characterCountLabel() {
        const segs = this.segmentCount;
        return `${this.characterCount} / 160 chars (${segs} segment${segs !== 1 ? 's' : ''})`;
    }

    get characterCountClass() {
        return this.characterCount > 160 ? 'char-counter over-limit' : 'char-counter';
    }

    get canSend() {
        return this.selectedContactId
            && this.messageBody.trim()
            && !this.isSending
            && !this.isSelectedOptedOut
            && !this.hasNoSmsNumber;
    }

    get sendDisabled() {
        return !this.canSend;
    }

    handleContactChange(event) {
        this.selectedContactId = event.detail.value;
        this.sendError = '';
    }

    handleTemplateChange(event) {
        this.selectedTemplateId = event.detail.value;
        if (this.selectedTemplateId) {
            const tmpl = this.templates.find(t => t.id === this.selectedTemplateId);
            if (tmpl && tmpl.text) {
                this.messageBody = tmpl.text;
            }
        }
    }

    handleBodyChange(event) {
        this.messageBody = event.detail ? event.detail.value : event.target.value;
    }

    async handleSend() {
        if (!this.canSend) return;
        this.isSending = true;
        this.sendError = '';
        try {
            await sendSms({
                contactId: this.selectedContactId,
                message: this.messageBody,
                oppId: this.recordId
            });
            this.dispatchEvent(new CustomEvent('smssent'));
            this.handleClose();
        } catch (error) {
            console.error('Error sending SMS:', error);
            this.sendError = error.body?.message || 'Failed to send SMS. Please try again.';
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
