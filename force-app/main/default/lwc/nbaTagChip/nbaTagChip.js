import { LightningElement, api, track } from 'lwc';

const CATEGORY_COLORS = {
    'Time-Bound': 'chip chip-time-bound',
    'Cadence': 'chip chip-cadence',
    'Signal': 'chip chip-signal',
    'Engagement': 'chip chip-engagement',
    'Stage': 'chip chip-stage',
    'Economic': 'chip chip-stage'
};

export default class NbaTagChip extends LightningElement {
    @api tag; // { id, category, chip, expanded, priority }

    @track isExpanded = false;

    get chipClass() {
        const base = CATEGORY_COLORS[this.tag?.category] || 'chip chip-default';
        return this.isExpanded ? base + ' expanded' : base;
    }

    get chipLabel() {
        return this.tag?.chip || '';
    }

    get expandedText() {
        return this.tag?.expanded || '';
    }

    handleClick() {
        this.isExpanded = !this.isExpanded;
    }
}
