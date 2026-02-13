import { LightningElement, api } from 'lwc';

export default class NbaDemoPayrollStatus extends LightningElement {
    @api payrollData;

    get typeValue() {
        return this.payrollData?.type ?? '—';
    }

    get nextStepValue() {
        return this.payrollData?.nextStep ?? '—';
    }

    get checkStatusValue() {
        return this.payrollData?.checkStatus ?? '—';
    }

    get isReady() {
        return this.payrollData?.checkStatus?.toLowerCase().includes('ready');
    }

    get statusBadgeClass() {
        const status = this.payrollData?.checkStatus?.toLowerCase() ?? '';
        if (status.includes('ready')) {
            return 'badge badge-green';
        }
        if (status.includes('pending')) {
            return 'badge badge-yellow';
        }
        if (status.includes('error') || status.includes('fail')) {
            return 'badge badge-red';
        }
        return 'badge badge-gray';
    }
}