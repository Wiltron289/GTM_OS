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

    get formattedClosedWon() {
        const closedWon = this.quotaData?.closedWon;
        if (closedWon == null) return '$0';
        return `$${Number(closedWon).toLocaleString()}`;
    }

    get formattedTarget() {
        const target = this.quotaData?.target;
        if (target == null) return '—';
        if (target >= 1000) {
            return `$${(target / 1000).toFixed(1)}k`;
        }
        return `$${target}`;
    }

    get formattedThisOpp() {
        const thisOppMrr = this.quotaData?.thisOppMrr;
        if (thisOppMrr == null) return '—';
        return `+$${Number(thisOppMrr).toLocaleString()}`;
    }

    // Blue arc: combined (closedWon + thisOpp), rendered first as bottom layer
    get combinedDashArray() {
        const target = this.quotaData?.target ?? 1;
        const closedWon = this.quotaData?.closedWon ?? 0;
        const thisOpp = this.quotaData?.thisOppMrr ?? 0;
        const combinedPct = Math.min(((closedWon + thisOpp) / target) * 100, 100);
        const filled = (combinedPct / 100) * CIRCUMFERENCE;
        return `${filled} ${CIRCUMFERENCE}`;
    }

    // Green arc: closedWon only, rendered on top
    get closedWonDashArray() {
        const target = this.quotaData?.target ?? 1;
        const closedWon = this.quotaData?.closedWon ?? 0;
        const pct = Math.min((closedWon / target) * 100, 100);
        const filled = (pct / 100) * CIRCUMFERENCE;
        return `${filled} ${CIRCUMFERENCE}`;
    }

    get dashOffset() {
        // CSS rotate(-90deg) already positions arc start at 12 o'clock
        return 0;
    }

    get hasThisOpp() {
        return (this.quotaData?.thisOppMrr ?? 0) > 0;
    }

    get hasClosedWon() {
        return (this.quotaData?.closedWon ?? 0) > 0;
    }

    get isZeroProgress() {
        const closedWon = this.quotaData?.closedWon ?? 0;
        const thisOpp = this.quotaData?.thisOppMrr ?? 0;
        return closedWon === 0 && thisOpp === 0;
    }
}