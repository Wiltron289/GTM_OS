import { LightningElement, api, track } from 'lwc';

export default class NbaDemoSalesEngagement extends LightningElement {
    @api engagementData;
    @track sectionExpanded = true;

    get chevronIcon() {
        return this.sectionExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    toggleSection() {
        this.sectionExpanded = !this.sectionExpanded;
    }

    get stageName() {
        return this.engagementData?.stageName ?? '—';
    }

    get lastContactLabel() {
        return this.engagementData?.lastContactLabel ?? '—';
    }

    get lastContactAge() {
        return this.engagementData?.lastContactAge ?? '—';
    }

    get touchFrequency() {
        return this.engagementData?.touchFrequency ?? '—';
    }

    get closePotentialPercent() {
        return this.engagementData?.closePotential ?? 0;
    }

    get daysInStage() {
        return this.engagementData?.daysInStage ?? '—';
    }

    get aiInsight() {
        return this.engagementData?.aiInsight ?? '';
    }

    get hasAiInsight() {
        return !!this.engagementData?.aiInsight;
    }

    get touchFrequencyLabel() {
        const freq = this.engagementData?.touchFrequency;
        if (freq == null) return '—';
        return `${freq} in 30 days`;
    }

    get formattedClosePotential() {
        const value = this.engagementData?.closePotential;
        if (value == null) return '—';
        if (value >= 70) return 'High';
        if (value >= 40) return 'Medium';
        return 'Low';
    }

    get closePotentialClass() {
        const value = this.engagementData?.closePotential;
        if (value == null) return 'close-low';
        if (value >= 70) return 'close-high';
        if (value >= 40) return 'close-medium';
        return 'close-low';
    }
}