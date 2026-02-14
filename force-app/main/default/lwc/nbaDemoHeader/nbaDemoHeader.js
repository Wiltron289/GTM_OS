import { LightningElement, api, track } from 'lwc';

export default class NbaDemoHeader extends LightningElement {
    @api headerData;
    @api contacts;
    @track showContactDropdown = false;

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

    handleEmailNow() {
        this.showContactDropdown = false;
        this.dispatchEvent(new CustomEvent('emailnow'));
    }

    handleSnooze() {
        this.showContactDropdown = false;
        this.dispatchEvent(new CustomEvent('snooze'));
    }

    handleEmailDropdown(event) {
        event.stopPropagation();
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

    connectedCallback() {
        this._closeDropdownHandler = () => {
            this.showContactDropdown = false;
        };
        document.addEventListener('click', this._closeDropdownHandler);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._closeDropdownHandler);
    }
}
