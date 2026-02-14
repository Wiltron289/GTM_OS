import { LightningElement, api, track } from 'lwc';

export default class NbaDemoAccountDetails extends LightningElement {
    @api accountData;
    @track sectionExpanded = true;

    get chevronIcon() {
        return this.sectionExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    toggleSection() {
        this.sectionExpanded = !this.sectionExpanded;
    }

    get employeeCount() {
        return this.accountData?.employeeCount ?? '—';
    }

    get locationCount() {
        return this.accountData?.locationCount ?? '—';
    }

    get plan() {
        return this.accountData?.plan ?? '—';
    }

    get onTierMonths() {
        return this.accountData?.onTierMonths ?? '—';
    }
}