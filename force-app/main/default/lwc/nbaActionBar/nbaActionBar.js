import { LightningElement, api, track } from 'lwc';

export default class NbaActionBar extends LightningElement {
    @api currentAction;
    @api isTransitioning = false;

    @track showSnoozePanel = false;
    @track showDismissPanel = false;
    @track showOutcomePanel = false;

    // Snooze state
    snoozeReason = '';
    snoozeDuration = 60; // default 1 hour

    // Dismiss state
    dismissReason = '';
    dismissCategory = 'Other';

    // ── Cadence-aware button labels ────────────────────────────────

    get isCadenceCall() {
        return this.currentAction?.isCadenceAction && this.currentAction?.stepMethod === 'Call';
    }

    get isCadenceSms() {
        return this.currentAction?.isCadenceAction && this.currentAction?.stepMethod === 'SMS';
    }

    get isCadenceEmail() {
        return this.currentAction?.isCadenceAction && this.currentAction?.stepMethod === 'Email';
    }

    get completeButtonLabel() {
        if (this.isCadenceSms) return 'Mark SMS Sent';
        if (this.isCadenceEmail) return 'Mark Email Sent';
        return 'Complete';
    }

    get completeButtonIcon() {
        if (this.isCadenceSms) return 'utility:chat';
        if (this.isCadenceEmail) return 'utility:email';
        return 'utility:check';
    }

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
        let cls = this.isDisabled ? 'action-btn complete-btn disabled' : 'action-btn complete-btn';
        if (this.isCadenceSms) cls = cls.replace('complete-btn', 'complete-btn sms-btn');
        if (this.isCadenceEmail) cls = cls.replace('complete-btn', 'complete-btn email-btn');
        return cls;
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

        // For Call cadence steps, show outcome panel instead of completing immediately
        if (this.isCadenceCall) {
            this.showOutcomePanel = true;
            return;
        }

        // SMS/Email cadence steps auto-complete with "Sent" outcome
        const detail = this._extractActionDetail();
        if (this.isCadenceSms || this.isCadenceEmail) {
            detail.stepOutcome = 'Sent';
        }
        this.dispatchEvent(new CustomEvent('complete', { detail }));
    }

    // ── Call Outcome Panel ────────────────────────────────────────

    handleOutcomeSelect(event) {
        const outcome = event.currentTarget.dataset.outcome;
        this.showOutcomePanel = false;
        const detail = this._extractActionDetail();
        detail.stepOutcome = outcome;
        this.dispatchEvent(new CustomEvent('complete', { detail }));
    }

    handleOutcomePanelClose() {
        this.showOutcomePanel = false;
    }

    // ── Snooze ───────────────────────────────────────────────────

    handleSnoozeToggle() {
        if (this.isDisabled) return;
        this.showDismissPanel = false;
        this.showOutcomePanel = false;
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
        this.showOutcomePanel = false;
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
        this.showOutcomePanel = false;
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
