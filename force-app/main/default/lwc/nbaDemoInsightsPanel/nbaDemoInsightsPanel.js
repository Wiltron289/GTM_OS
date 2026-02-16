import { LightningElement, api, track } from 'lwc';

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
        return this.isActionMode && this.currentAction?.cadenceProgress;
    }

    get cadenceMethodHint() {
        if (!this.currentAction?.methodHints) return null;
        return 'If no connect: ' + this.currentAction.methodHints;
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
