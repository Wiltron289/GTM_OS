import { LightningElement, api, track } from 'lwc';

// Method → icon mapping
const METHOD_ICONS = {
    'Call': 'utility:call',
    'SMS': 'utility:chat',
    'Email': 'utility:email'
};

export default class NbaDemoInsightsPanel extends LightningElement {
    @api insightsData;
    @api currentAction;
    @api isActionMode = false;

    @track isExpanded = false;

    get panelTitle() {
        return this.isActionMode ? 'Why This Action' : 'Why This Account';
    }

    get hasInsights() {
        if (this.isActionMode) {
            return this.currentAction?.actionInstruction || this.currentAction?.reasonText;
        }
        return this.insightsData?.drivers?.length > 0;
    }

    get showDrivers() {
        return !this.isActionMode && this.insightsData?.drivers?.length > 0;
    }

    get showActionContext() {
        return this.isActionMode && this.currentAction;
    }

    get showCadenceContext() {
        return this.isActionMode && this.currentAction?.isCadenceAction;
    }

    get cadenceProgressText() {
        return this.currentAction?.cadenceProgress;
    }

    get cadenceProgressFraction() {
        return this.currentAction?.progressFraction;
    }

    get progressPercent() {
        if (!this.currentAction?.cadenceStepNumber || !this.currentAction?.cadenceTotalSteps) return 0;
        return Math.round((this.currentAction.cadenceStepNumber / this.currentAction.cadenceTotalSteps) * 100);
    }

    get progressBarStyle() {
        return `width: ${this.progressPercent}%`;
    }

    get stepMethodIcon() {
        return METHOD_ICONS[this.currentAction?.stepMethod] || 'utility:call';
    }

    get stepInstruction() {
        return this.currentAction?.stepInstruction || this.currentAction?.actionInstruction;
    }

    get hasUpcomingSteps() {
        return this.currentAction?.upcomingSteps?.length > 0;
    }

    get upcomingStepsList() {
        if (!this.currentAction?.upcomingSteps) return [];
        return this.currentAction.upcomingSteps.map((step, idx) => ({
            key: `upcoming-${idx}`,
            text: step
        }));
    }

    get insightCountLabel() {
        if (this.isActionMode) return 'action context';
        return `${this.insightsData?.insightCount || 0} insights`;
    }

    get activeTags() {
        if (!this.insightsData?.tags) return [];
        return this.insightsData.tags.filter(tag => tag.active === true);
    }

    get computedTags() {
        if (!this.insightsData?.tags) return [];
        return this.insightsData.tags.map(tag => ({
            ...tag,
            cssClass: tag.active ? 'tag tag-active' : 'tag tag-inactive'
        }));
    }

    get expandIcon() {
        return this.isExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    toggleExpand() {
        this.isExpanded = !this.isExpanded;
    }
}
