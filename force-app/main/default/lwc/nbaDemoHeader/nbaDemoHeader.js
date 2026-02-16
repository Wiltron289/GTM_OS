import { LightningElement, api, track } from 'lwc';

// Action type → badge color mapping
const ACTION_TYPE_STYLES = {
    'First Touch': 'action-badge action-badge-blue',
    'Re-engage': 'action-badge action-badge-amber',
    'Stage Progression': 'action-badge action-badge-green',
    'SLA Response': 'action-badge action-badge-red',
    'Blitz Outreach': 'action-badge action-badge-purple'
};

export default class NbaDemoHeader extends LightningElement {
    @api headerData;
    @api contacts;
    @api currentAction;
    @api isActionMode = false;
    @track showContactDropdown = false;
    @track showSmsContactDropdown = false;

    get actionTypeBadgeClass() {
        if (!this.currentAction?.actionType) return 'action-badge';
        return ACTION_TYPE_STYLES[this.currentAction.actionType] || 'action-badge';
    }

    get showSnoozeButton() {
        return !this.isActionMode;
    }

    get showCadenceStep() {
        return this.isActionMode && this.currentAction?.cadenceProgress
            && this.currentAction?.todayCallCount != null
            && this.currentAction?.maxCallsToday != null;
    }

    get cadenceStepLabel() {
        const current = (this.currentAction?.todayCallCount || 0) + 1;
        const max = this.currentAction?.maxCallsToday || 0;
        return `${current}/${max}`;
    }

    get formattedMrr() {
        if (!this.headerData?.mrr) return '$0 MRR';
        const val = Number(this.headerData.mrr);
        return `$${val.toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 0 })} MRR`;
    }

    get formattedCloseProb() {
        if (this.headerData?.closeProbability == null) return '0% Close';
        return `${this.headerData.closeProbability}% Close`;
    }

    get contactList() {
        if (!this.contacts || !Array.isArray(this.contacts)) return [];
        return this.contacts.filter(c => c.email);
    }

    get smsContactList() {
        if (!this.contacts || !Array.isArray(this.contacts)) return [];
        return this.contacts.filter(c => c.mogliNumber);
    }

    handleEmailNow() {
        this.showContactDropdown = false;
        this.showSmsContactDropdown = false;
        this.dispatchEvent(new CustomEvent('emailnow'));
    }

    handleSnooze() {
        this.showContactDropdown = false;
        this.showSmsContactDropdown = false;
        this.dispatchEvent(new CustomEvent('snooze'));
    }

    handleEmailDropdown(event) {
        event.stopPropagation();
        this.showSmsContactDropdown = false;
        this.showContactDropdown = !this.showContactDropdown;
    }

    handleContactSelect(event) {
        const contactId = event.currentTarget.dataset.contactId;
        const contact = this.contactList.find(c => c.contactId === contactId);
        if (contact) {
            this.showContactDropdown = false;
            this.dispatchEvent(new CustomEvent('contactemail', { detail: contact }));
        }
    }

    handleSmsNow() {
        this.showContactDropdown = false;
        this.showSmsContactDropdown = false;
        this.dispatchEvent(new CustomEvent('smsnow'));
    }

    handleSmsDropdown(event) {
        event.stopPropagation();
        this.showContactDropdown = false;
        this.showSmsContactDropdown = !this.showSmsContactDropdown;
    }

    handleSmsContactSelect(event) {
        const contactId = event.currentTarget.dataset.contactId;
        const contact = this.smsContactList.find(c => c.contactId === contactId);
        if (contact) {
            this.showSmsContactDropdown = false;
            this.dispatchEvent(new CustomEvent('contactsms', { detail: contact }));
        }
    }

    connectedCallback() {
        this._closeDropdownHandler = () => {
            this.showContactDropdown = false;
            this.showSmsContactDropdown = false;
        };
        document.addEventListener('click', this._closeDropdownHandler);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._closeDropdownHandler);
    }
}
