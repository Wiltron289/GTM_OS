import { LightningElement, api, track } from 'lwc';

export default class NbaDemoInsightsPanel extends LightningElement {
    @api insightsData;

    @track isExpanded = false;

    get hasInsights() {
        return this.insightsData?.drivers?.length > 0;
    }

    get insightCountLabel() {
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
