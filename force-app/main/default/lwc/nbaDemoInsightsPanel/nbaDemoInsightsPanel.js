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

    @track isExpanded = true;

    get panelTitle() {
        return this.isActionMode ? 'Why This Action' : 'Why This Account';
    }

    get hasInsights() {
        if (this.isActionMode) {
            return this.currentAction?.actionInstruction
                || this.currentAction?.reasonText
                || this.parsedTags.length > 0;
        }
        return this.insightsData?.drivers?.length > 0;
    }

    get showActionContext() {
        return this.isActionMode && this.currentAction;
    }

    get showDrivers() {
        return !this.isActionMode && this.insightsData?.drivers?.length > 0;
    }

    // ── Time-Bound vs Engine Display ──────────────────

    get isTimeBoundAction() {
        return this.isActionMode && this.currentAction?.isTimeBound === true;
    }

    get isEngineAction() {
        return this.isActionMode && !this.currentAction?.isTimeBound;
    }

    // ── DS Driver Tags (engine actions only) ──────────

    get parsedTags() {
        if (!this.currentAction?.actionTags) return [];
        try {
            const tags = JSON.parse(this.currentAction.actionTags);
            return tags.map((tag, idx) => ({
                key: `tag-${idx}`,
                chip: tag.chip,
                expanded: tag.expanded,
                category: tag.category
            }));
        } catch (e) {
            return [];
        }
    }

    get hasDriverTags() {
        return this.parsedTags.length > 0;
    }

    // ── Payroll Probability (engine actions only) ─────

    get hasPayrollProbability() {
        return this.isEngineAction
            && this.currentAction?.payrollProbability != null
            && this.currentAction.payrollProbability > 0;
    }

    get payrollProbabilityPercent() {
        if (!this.currentAction?.payrollProbability) return 0;
        return Math.round(this.currentAction.payrollProbability * 100);
    }

    get payrollProbabilityLabel() {
        return `${this.payrollProbabilityPercent}% payroll conversion probability`;
    }

    get payrollBarStyle() {
        return `width: ${this.payrollProbabilityPercent}%`;
    }

    get payrollBarColorClass() {
        const pct = this.payrollProbabilityPercent;
        if (pct >= 60) return 'prob-bar-fill prob-high';
        if (pct >= 30) return 'prob-bar-fill prob-medium';
        return 'prob-bar-fill prob-low';
    }

    // ── Cadence Context (engine actions only) ─────────

    get showCadenceContext() {
        return this.isEngineAction && this.currentAction?.isCadenceAction;
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

    // ── Time-Bound Rationale ──────────────────────────

    get stepMethodIcon() {
        return METHOD_ICONS[this.currentAction?.stepMethod] || 'utility:call';
    }

    get stepInstruction() {
        return this.currentAction?.stepInstruction || this.currentAction?.actionInstruction;
    }

    // ── Record Page Mode ──────────────────────────────

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

    // ── General ───────────────────────────────────────

    get insightCountLabel() {
        if (this.isActionMode) {
            const tagCount = this.parsedTags.length;
            return tagCount > 0 ? `${tagCount} signals` : 'action context';
        }
        return `${this.insightsData?.insightCount || 0} insights`;
    }

    get expandIcon() {
        return this.isExpanded ? 'utility:chevronup' : 'utility:chevrondown';
    }

    toggleExpand() {
        this.isExpanded = !this.isExpanded;
    }
}
