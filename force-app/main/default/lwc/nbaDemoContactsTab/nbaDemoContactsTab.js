import { LightningElement, api } from 'lwc';
export default class NbaDemoContactsTab extends LightningElement {
    @api contactsData;

    get contacts() {
        return Array.isArray(this.contactsData) ? this.contactsData : [];
    }
    get hasContacts() {
        return this.contacts.length > 0;
    }

    get computedContacts() {
        return this.contacts.map((contact, index) => ({
            ...contact,
            cardClass: contact.isPrimary
                ? 'contact-card contact-primary'
                : 'contact-card',
            hasLastActivity: !!contact.lastActivityLabel,
            activityIconName:
                contact.lastActivityType === 'Call'
                    ? 'standard:log_a_call'
                    : 'standard:event',
            key: contact.contactId || index
        }));
    }

    handleEmail(event) {
        const contactId = event.currentTarget.dataset.contactId;
        this.dispatchEvent(
            new CustomEvent('contactemail', {
                detail: { contactId },
                bubbles: true,
                composed: true
            })
        );
    }

    handleCall(event) {
        const phone = event.currentTarget.dataset.phone;
        if (phone) {
            window.open('tel:' + phone);
        }
    }
}
