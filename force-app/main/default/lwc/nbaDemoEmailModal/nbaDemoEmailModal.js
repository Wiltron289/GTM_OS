import { LightningElement, api, track } from 'lwc';
import sendEmail from '@salesforce/apex/NbaDemoController.sendEmail';

export default class NbaDemoEmailModal extends LightningElement {
    @api contacts;
    @api recordId;
    @api selectedContact;
    @track selectedContactId;
    @track emailSubject = '';
    @track emailBody = '';
    @track isSending = false;

    connectedCallback() {
        if (this.selectedContact) {
            this.selectedContactId = this.selectedContact;
        } else if (this.contacts?.contacts?.length > 0) {
            this.selectedContactId = this.contacts.contacts[0].contactId;
        }
    }

    get contactOptions() {
        if (!this.contacts?.contacts) return [];
        return this.contacts.contacts.map(c => ({
            label: c.name + (c.title ? ' - ' + c.title : ''),
            value: c.contactId
        }));
    }

    get selectedContactName() {
        const contact = this.contacts?.contacts?.find(c => c.contactId === this.selectedContactId);
        return contact ? contact.name : '';
    }

    get canSend() {
        return this.selectedContactId && this.emailSubject && this.emailBody && !this.isSending;
    }

    handleContactChange(event) {
        this.selectedContactId = event.detail.value;
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
                templateId: null
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
