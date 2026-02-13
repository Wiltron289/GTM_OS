import { LightningElement, api } from 'lwc';

export default class NbaDemoHeader extends LightningElement {
    @api headerData;

    get formattedMrr() {
        if (!this.headerData?.mrr) return '$0 MRR';
        return `$${this.headerData.mrr} MRR`;
    }

    get formattedCloseProb() {
        if (this.headerData?.closeProbability == null) return '0% Close';
        return `${this.headerData.closeProbability}% Close`;
    }

    handleEmailNow() {
        this.dispatchEvent(new CustomEvent('emailnow'));
    }

    handleSnooze() {
        this.dispatchEvent(new CustomEvent('snooze'));
    }

    handleEmailDropdown(event) {
        event.stopPropagation();
        this.dispatchEvent(new CustomEvent('emaildropdown'));
    }
}
