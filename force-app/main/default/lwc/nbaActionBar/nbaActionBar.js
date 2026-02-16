import { LightningElement, api, track } from 'lwc';

export default class NbaActionBar extends LightningElement {
    @api currentAction;
    @api isTransitioning = false;

    @track showSnoozePanel = false;
    @track showDismissPanel = false;

    // Snooze state
    snoozeReason = '';
    snoozeDuration = 60; // default 1 hour

    // Dismiss state
    dismissReason = '';
    dismissCategory = 'Other';

    // ── Snooze duration options ──────────────────────────────────

    get snoozeDurationOptions() {
        return [
            { 
                label: '15 min', 
                value: 15, 
                cssClass: this.snoozeDuration === 15 ? 'duration-chip selected' : 'duration-chip'
            },
            { 
                label: '1 hour', 
                value: 60, 
                cssClass: this.snoozeDuration === 60 ? 'duration-chip selected' : 'duration-chip'
            },
            { 
                label: '4 hours', 
                value: 240, 
                cssClass: this.snoozeDuration === 240 ? 'duration-chip selected' : 'duration-chip'
            }
        ];
    }

    // ── Dismiss category options ─────────────────────────────────

    get dismissCategoryOptions() {
        return [
            { 
                label: 'Call Scheduled', 
                value: 'Call Scheduled', 
                cssClass: this.dismissCategory === 'Call Scheduled' ? 'category-chip selected' : 'category-chip'
            },
            { 
                label: 'Time Zone', 
                value: 'Time Zone', 
                cssClass: this.dismissCategory === 'Time Zone' ? 'category-chip selected' : 'category-chip'
            },
            { 
                label: 'Other', 
                value: 'Other', 
                cssClass: this.dismissCategory === 'Other' ? 'category-chip selected' : 'category-chip'
            }
        ];
    }

    // ── Button state ─────────────────────────────────────────────

    get isDisabled() {
        return this.isTransitioning || !this.currentAction;
    }

    get completeBtnClass() {
        return this.isDisabled ? 'action-btn complete-btn disabled' : 'action-btn complete-btn';
    }

    get snoozeBtnClass() {
        let cls = this.isDisabled ? 'action-btn snooze-btn disabled' : 'action-btn snooze-btn';
        if (this.showSnoozePanel) cls += ' active';
        return cls;
    }

    get dismissBtnClass() {
        let cls = this.isDisabled ? 'action-btn dismiss-btn disabled' : 'action-btn dismiss-btn';
        if (this.showDismissPanel) cls += ' active';
        return cls;
    }

    // ── Complete ─────────────────────────────────────────────────

    handleComplete() {
        if (this.isDisabled) return;
        this.closeAllPanels();
        const detail = this._extractActionDetail();
        this.dispatchEvent(new CustomEvent('complete', { detail }));
    }

    // ── Snooze ───────────────────────────────────────────────────

    handleSnoozeToggle() {
        if (this.isDisabled) return;
        this.showDismissPanel = false;
        this.showSnoozePanel = !this.showSnoozePanel;
        if (this.showSnoozePanel) {
            this.snoozeReason = '';
            this.snoozeDuration = 60;
        }
    }

    handleSnoozeDurationSelect(event) {
        this.snoozeDuration = Number(event.currentTarget.dataset.value);
    }

    handleSnoozeReasonChange(event) {
        this.snoozeReason = event.target.value;
    }

    handleSnoozeSubmit() {
        this.showSnoozePanel = false;
        const detail = this._extractActionDetail();
        detail.reason = this.snoozeReason;
        detail.durationMinutes = this.snoozeDuration;
        this.dispatchEvent(new CustomEvent('snooze', { detail }));
    }

    // ── Dismiss ──────────────────────────────────────────────────

    handleDismissToggle() {
        if (this.isDisabled) return;
        this.showSnoozePanel = false;
        this.showDismissPanel = !this.showDismissPanel;
        if (this.showDismissPanel) {
            this.dismissReason = '';
            this.dismissCategory = 'Other';
        }
    }

    handleDismissCategorySelect(event) {
        this.dismissCategory = event.currentTarget.dataset.value;
    }

    handleDismissReasonChange(event) {
        this.dismissReason = event.target.value;
    }

    handleDismissSubmit() {
        this.showDismissPanel = false;
        const detail = this._extractActionDetail();
        detail.reason = this.dismissReason;
        detail.category = this.dismissCategory;
        this.dispatchEvent(new CustomEvent('dismiss', { detail }));
    }

    // ── Shared ───────────────────────────────────────────────────

    closeAllPanels() {
        this.showSnoozePanel = false;
        this.showDismissPanel = false;
    }

    handlePanelClose() {
        this.closeAllPanels();
    }

    /**
     * Safely extract action detail from currentAction for event dispatch.
     * Reads all properties into a plain object to avoid LWC proxy issues.
     */
    _extractActionDetail() {
        const action = this.currentAction;
        if (!action) {
            console.warn('[nbaActionBar] _extractActionDetail called with null currentAction');
            return { actionId: null, opportunityId: null, actionType: null };
        }
        const detail = {
            actionId: action.actionId || null,
            opportunityId: action.opportunityId || null,
            actionType: action.actionType || null
        };
        if (!detail.opportunityId) {
            console.warn('[nbaActionBar] currentAction has null opportunityId:', JSON.stringify(action));
        }
        return detail;
    }
}
