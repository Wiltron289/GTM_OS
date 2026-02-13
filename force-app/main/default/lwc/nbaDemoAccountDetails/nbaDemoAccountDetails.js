import { LightningElement, api } from 'lwc';

export default class NbaDemoAccountDetails extends LightningElement {
    @api accountData;

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