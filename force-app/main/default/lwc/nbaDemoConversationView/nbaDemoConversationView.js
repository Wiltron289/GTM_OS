import { LightningElement, api, track } from 'lwc';
import getConversation from '@salesforce/apex/NbaDemoController.getConversation';
import sendSms from '@salesforce/apex/NbaDemoController.sendSms';

export default class NbaDemoConversationView extends LightningElement {
    @api contacts;
    @api recordId;

    @track selectedContactId;
    @track messages = [];
    @track isLoading = false;
    @track messageBody = '';
    @track isSending = false;
    @track sendError = '';

    connectedCallback() {
        const eligible = this.smsEligibleContacts;
        if (eligible.length > 0) {
            this.selectedContactId = eligible[0].contactId;
            this.loadConversation();
        }
    }

    // ─── Computed properties ──────────────────────────────

    get contactList() {
        return Array.isArray(this.contacts) ? this.contacts : [];
    }

    get smsEligibleContacts() {
        return this.contactList.filter(c => c.mogliNumber);
    }

    get hasSmsContacts() {
        return this.smsEligibleContacts.length > 0;
    }

    get contactPills() {
        return this.smsEligibleContacts.map(c => ({
            contactId: c.contactId,
            name: c.name,
            initials: c.initials || (c.name ? c.name.substring(0, 2).toUpperCase() : '??'),
            isSelected: c.contactId === this.selectedContactId,
            pillClass: c.contactId === this.selectedContactId
                ? 'contact-pill contact-pill-selected'
                : 'contact-pill',
            optedOut: c.optedOut === true
        }));
    }

    get selectedContact() {
        return this.contactList.find(c => c.contactId === this.selectedContactId);
    }

    get selectedContactName() {
        return this.selectedContact ? this.selectedContact.name : '';
    }

    get isSelectedOptedOut() {
        return this.selectedContact ? this.selectedContact.optedOut === true : false;
    }

    get hasMessages() {
        return this.messages.length > 0;
    }

    get computedMessages() {
        const result = [];
        let lastDate = '';
        this.messages.forEach((msg, idx) => {
            const msgDate = msg.createdDate
                ? new Date(msg.createdDate).toLocaleDateString('en-US', {
                    month: 'short', day: 'numeric', year: 'numeric'
                  })
                : '';
            if (msgDate && msgDate !== lastDate) {
                result.push({
                    key: 'date-' + idx,
                    isDateHeader: true,
                    dateLabel: msgDate
                });
                lastDate = msgDate;
            }
            result.push({
                ...msg,
                key: msg.id || 'msg-' + idx,
                isDateHeader: false,
                bubbleClass: msg.isOutbound ? 'chat-bubble chat-bubble-outbound' : 'chat-bubble chat-bubble-inbound',
                alignClass: msg.isOutbound ? 'chat-row chat-row-right' : 'chat-row chat-row-left',
                timeLabel: msg.createdDate
                    ? new Date(msg.createdDate).toLocaleTimeString('en-US', {
                        hour: 'numeric', minute: '2-digit'
                      })
                    : '',
                statusLabel: msg.isOutbound ? (msg.status || '') : ''
            });
        });
        return result;
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
        return `${this.characterCount} / 160 (${segs} seg${segs !== 1 ? 's' : ''})`;
    }

    get characterCountClass() {
        return this.characterCount > 160 ? 'char-counter over-limit' : 'char-counter';
    }

    get canSend() {
        return this.selectedContactId
            && this.messageBody && this.messageBody.trim()
            && !this.isSending
            && !this.isSelectedOptedOut;
    }

    get sendDisabled() {
        return !this.canSend;
    }

    // ─── Event handlers ──────────────────────────────────

    handleContactSelect(event) {
        const contactId = event.currentTarget.dataset.contactId;
        if (contactId !== this.selectedContactId) {
            this.selectedContactId = contactId;
            this.messages = [];
            this.loadConversation();
        }
    }

    handleBodyChange(event) {
        this.messageBody = event.detail ? event.detail.value : event.target.value;
    }

    handleKeyDown(event) {
        if (event.key === 'Enter' && !event.shiftKey && this.canSend) {
            event.preventDefault();
            this.handleSend();
        }
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
            this.messageBody = '';
            await this.loadConversation();
            this.dispatchEvent(new CustomEvent('smssent'));
        } catch (error) {
            this.sendError = error.body ? error.body.message : 'Failed to send SMS.';
        } finally {
            this.isSending = false;
        }
    }

    // ─── Data loading ────────────────────────────────────

    async loadConversation() {
        if (!this.selectedContactId) return;
        this.isLoading = true;
        try {
            const data = await getConversation({ contactId: this.selectedContactId });
            this.messages = data || [];
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(() => this.scrollToBottom(), 100);
        } catch (error) {
            this.messages = [];
        } finally {
            this.isLoading = false;
        }
    }

    scrollToBottom() {
        const chatArea = this.template.querySelector('.chat-area');
        if (chatArea) {
            chatArea.scrollTop = chatArea.scrollHeight;
        }
    }

    @api
    refreshConversation() {
        this.loadConversation();
    }
}
