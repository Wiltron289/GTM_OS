import { LightningElement, api, track } from 'lwc';

const RADIUS = 50;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

export default class NbaDemoQuotaProgress extends LightningElement {
    @api quotaData;
    @track sectionExpanded = true;

    get chevronIcon() {
        return this.sectionExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    toggleSection() {
        this.sectionExpanded = !this.sectionExpanded;
    }

    get percentageDisplay() {
        return this.quotaData?.percentage ?? 0;
    }

    get formattedTarget() {
        const target = this.quotaData?.target;
        if (target == null) return '—';
        if (target >= 1000) {
            return `$${(target / 1000).toFixed(1)}k`;
        }
        return `$${target}`;
    }

    get formattedClosedWon() {
        const closedWon = this.quotaData?.closedWon;
        if (closedWon == null) return '—';
        if (closedWon >= 1000) {
            return `$${(closedWon / 1000).toFixed(1)}k`;
        }
        return `$${closedWon}`;
    }

    get formattedThisOpp() {
        const thisOppMrr = this.quotaData?.thisOppMrr;
        if (thisOppMrr == null) return '—';
        return `+$${thisOppMrr}`;
    }

    get dashArray() {
        const percentage = this.quotaData?.percentage ?? 0;
        const filled = (percentage / 100) * CIRCUMFERENCE;
        return `${filled} ${CIRCUMFERENCE}`;
    }

    get dashOffset() {
        return CIRCUMFERENCE * 0.25;
    }
}