import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import Id from '@salesforce/user/Id';
import getPageData from '@salesforce/apex/NbaDemoController.getPageData';
import getActiveAction from '@salesforce/apex/NbaActionController.getActiveAction';
import checkInterrupts from '@salesforce/apex/NbaActionController.checkInterrupts';
import acceptInterrupt from '@salesforce/apex/NbaActionController.acceptInterrupt';
import completeAction from '@salesforce/apex/NbaActionController.completeAction';
import snoozeAction from '@salesforce/apex/NbaActionController.snoozeAction';
import dismissAction from '@salesforce/apex/NbaActionController.dismissAction';

export default class NbaDemoWorkspace extends LightningElement {
    @api recordId;

    // Current user ID (for App Page mode)
    userId = Id;

    // Tab state
    activeTab = 'overview';

    // Modal / dropdown state
    showEmailModal = false;
    selectedEmailContact = null;
    showSmsModal = false;
    selectedSmsContact = null;
    showSnoozeDropdown = false;

    // Loading & error state
    isLoading = true;
    error;

    // ── Action Mode (App Page) state ──────────────────────────
    isActionMode = false;
    currentAction = null;
    showEmptyState = false;
    isTransitioning = false;
    _interruptPollInterval = null;  // 15s — lightweight interrupt check
    _fullRefreshInterval = null;    // 5min — full on-demand re-evaluation

    // ── Two-stream: interrupt state ─────────────────────────
    pendingInterrupts = [];     // List of interrupt ActionWrappers from checkInterrupts
    _pausedAction = null;       // Saved scored-queue action when rep jumps to interrupt

    // Data properties populated from the Apex wrapper
    headerData;
    accountData;
    payrollStatusData;
    quotaData;
    engagementData;
    payrollTabData;
    productsData;
    contactsData;
    adminData;
    sidebarData;
    insightsData;
    upcomingEvent;

    // Store wire result for refreshApex (Record Page mode)
    _wiredResult;

    // ────────────────────────────────────────────
    // Lifecycle: detect App Page vs Record Page
    // ────────────────────────────────────────────
    connectedCallback() {
        if (!this.recordId) {
            // App Page mode — no recordId injected
            this.isActionMode = true;
            this._loadActiveAction();

            // 15s poll: lightweight interrupt check (Stream 2 — meetings + new assignments)
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._interruptPollInterval = setInterval(() => {
                if (!this.isTransitioning && !this.isLoading) {
                    this._checkInterrupts();
                }
            }, 15000);

            // 5min poll: full on-demand re-evaluation (~12 SOQL on cache miss)
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._fullRefreshInterval = setInterval(() => {
                if (!this.isTransitioning && !this.isLoading) {
                    this._refreshActiveAction();
                }
            }, 300000);
        }
    }

    disconnectedCallback() {
        if (this._interruptPollInterval) {
            clearInterval(this._interruptPollInterval);
            this._interruptPollInterval = null;
        }
        if (this._fullRefreshInterval) {
            clearInterval(this._fullRefreshInterval);
            this._fullRefreshInterval = null;
        }
    }

    // ────────────────────────────────────────────
    // Wire: load all page data (Record Page mode)
    // ────────────────────────────────────────────
    @wire(getPageData, { oppId: '$recordId' })
    wiredPageData(result) {
        this._wiredResult = result;
        const { data, error } = result;
        if (data) {
            this._applyPageData(data);
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.error = error;
            this.isLoading = false;
        }
    }

    // ────────────────────────────────────────────
    // Shared data application (wire + imperative)
    // ────────────────────────────────────────────
    _applyPageData(data) {
        this.headerData = data.header;
        this.accountData = data.account;
        this.payrollStatusData = data.payrollStatus;
        this.quotaData = data.quota;
        this.engagementData = data.engagement;
        this.payrollTabData = data.payrollTab;
        this.productsData = data.products;
        this.contactsData = data.contacts;
        this.adminData = data.admin;
        this.sidebarData = data.sidebar;
        this.insightsData = data.insights;
        this.upcomingEvent = data.upcomingEvent;
    }

    // ────────────────────────────────────────────
    // App Page: load active action + opp data
    // ────────────────────────────────────────────
    async _loadActiveAction() {
        this.isLoading = true;
        this.error = undefined;
        try {
            const action = await getActiveAction();
            if (action) {
                this.currentAction = action;
                this.showEmptyState = false;
                const data = await getPageData({ oppId: action.opportunityId });
                this._applyPageData(data);
            } else {
                this.currentAction = null;
                this.showEmptyState = true;
            }
        } catch (err) {
            this.error = err;
        } finally {
            this.isLoading = false;
            this.isTransitioning = false;
        }
    }

    // ────────────────────────────────────────────
    // App Page: silent refresh (polling, no loading spinner)
    // ────────────────────────────────────────────
    async _refreshActiveAction() {
        try {
            const action = await getActiveAction();
            if (action) {
                const prevOppId = this.currentAction?.opportunityId;
                const prevActionType = this.currentAction?.actionType;

                // For on-demand actions, actionId is always null, so compare by
                // opportunityId + actionType to detect if a different action was evaluated
                const changed = action.opportunityId !== prevOppId
                    || action.actionType !== prevActionType;

                if (changed) {
                    this.currentAction = action;
                    this.showEmptyState = false;
                    if (action.opportunityId !== prevOppId) {
                        const data = await getPageData({ oppId: action.opportunityId });
                        this._applyPageData(data);
                    }
                }
            } else if (this.currentAction) {
                // Actions cleared — show empty state
                this.currentAction = null;
                this.showEmptyState = true;
            }
        } catch (err) {
            // Silent fail on polling — don't disrupt the UI
        }
    }

    // ────────────────────────────────────────────
    // App Page: lightweight interrupt check (15s poll, Stream 2)
    // ────────────────────────────────────────────
    async _checkInterrupts() {
        try {
            const interrupts = await checkInterrupts();
            // Filter out any interrupt the rep already dismissed this session
            const newInterrupts = (interrupts || []).filter(
                (i) => !this._dismissedInterruptIds.has(i.actionId)
            );
            this.pendingInterrupts = newInterrupts;
        } catch (err) {
            // Silent fail on polling — don't disrupt the UI
        }
    }

    // Track dismissed interrupt IDs for this session so they don't re-appear
    _dismissedInterruptIds = new Set();

    // ────────────────────────────────────────────
    // Computed: effective record ID for children
    // ────────────────────────────────────────────
    get effectiveRecordId() {
        if (this.isActionMode && this.currentAction) {
            return this.currentAction.opportunityId;
        }
        return this.recordId;
    }

    get showWorkspace() {
        return !this.showEmptyState && !this.isLoading;
    }

    get showActionBar() {
        return this.isActionMode && this.currentAction;
    }

    get workspaceBodyClass() {
        return this.showActionBar ? 'workspace-body workspace-body-with-bar' : 'workspace-body';
    }

    // ────────────────────────────────────────────
    // Interrupt handlers (Stream 2 — two-stream)
    // ────────────────────────────────────────────
    async handleAcceptInterrupt(event) {
        const { actionId } = event.detail;
        if (!actionId) return;

        this.isTransitioning = true;
        try {
            // Save current scored-queue action so we can resume after interrupt
            if (this.currentAction) {
                this._pausedAction = { ...this.currentAction };
            }

            // Accept the interrupt (sets it to 'In Progress' so poll stops showing it)
            const accepted = await acceptInterrupt({ actionId });
            if (accepted) {
                this.currentAction = accepted;
                this.showEmptyState = false;
                this.pendingInterrupts = [];

                // Load page data if Opp changed
                const prevOppId = this._pausedAction?.opportunityId;
                if (accepted.opportunityId !== prevOppId) {
                    const data = await getPageData({ oppId: accepted.opportunityId });
                    this._applyPageData(data);
                }
            }
        } catch (err) {
            this.error = err;
        } finally {
            this.isTransitioning = false;
        }
    }

    handleDismissInterrupt(event) {
        const { actionId } = event.detail;
        if (actionId) {
            this._dismissedInterruptIds.add(actionId);
        }
        // Remove dismissed interrupt from pending list
        this.pendingInterrupts = this.pendingInterrupts.filter(
            (i) => i.actionId !== actionId
        );
    }

    // ────────────────────────────────────────────
    // Action lifecycle handlers (App Page mode)
    // ────────────────────────────────────────────
    async handleCompleteAction(event) {
        const { actionId, opportunityId, actionType, stepOutcome } = event.detail;
        if (!opportunityId) {
            console.warn('[nbaDemoWorkspace] completeAction called with null opportunityId. event.detail:', JSON.stringify(event.detail), 'currentAction:', JSON.stringify(this.currentAction));
        }
        this.isTransitioning = true;
        try {
            const result = await completeAction({
                actionId,
                opportunityId,
                actionType,
                stepOutcome: stepOutcome || null
            });
            await this._handleActionResult(result);
        } catch (err) {
            this.error = err;
            this.isTransitioning = false;
        }
    }

    async handleSnoozeAction(event) {
        const { actionId, opportunityId, actionType, reason, durationMinutes } = event.detail;
        this.isTransitioning = true;
        try {
            const result = await snoozeAction({ actionId, opportunityId, actionType, reason, durationMinutes });
            await this._handleActionResult(result);
        } catch (err) {
            this.error = err;
            this.isTransitioning = false;
        }
    }

    async handleDismissAction(event) {
        const { actionId, opportunityId, actionType, reason, category } = event.detail;
        this.isTransitioning = true;
        try {
            const result = await dismissAction({ actionId, opportunityId, actionType, reason, category });
            await this._handleActionResult(result);
        } catch (err) {
            this.error = err;
            this.isTransitioning = false;
        }
    }

    async _handleActionResult(result) {
        // If we just completed an interrupt and have a paused action, resume it
        if (this._pausedAction) {
            const paused = this._pausedAction;
            this._pausedAction = null;

            // The scored queue re-evaluation (result.nextAction) will naturally
            // return the paused action since it was never completed. Use the
            // re-evaluated result if available, otherwise fall back to paused.
            const nextAction = result?.hasNext && result.nextAction
                ? result.nextAction : paused;

            const prevOppId = this.currentAction?.opportunityId;
            this.currentAction = nextAction;
            this.showEmptyState = false;
            if (nextAction.opportunityId !== prevOppId) {
                try {
                    const data = await getPageData({ oppId: nextAction.opportunityId });
                    this._applyPageData(data);
                } catch (err) {
                    this.error = err;
                }
            }
            this.isTransitioning = false;
            return;
        }

        if (result && result.hasNext && result.nextAction) {
            const prevOppId = this.currentAction?.opportunityId;
            this.currentAction = result.nextAction;
            this.showEmptyState = false;
            if (result.nextAction.opportunityId !== prevOppId) {
                try {
                    const data = await getPageData({ oppId: result.nextAction.opportunityId });
                    this._applyPageData(data);
                } catch (err) {
                    this.error = err;
                }
            }
            this.isTransitioning = false;
        } else {
            this.currentAction = null;
            this.showEmptyState = true;
            this.isTransitioning = false;
        }
    }

    // ────────────────────────────────────────────
    // Tab navigation
    // ────────────────────────────────────────────
    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleTabChange(event) {
        this.activeTab = event.detail;
    }

    // Computed tab visibility getters
    get isOverview() {
        return this.activeTab === 'overview';
    }

    get isUpdates() {
        return this.activeTab === 'updates';
    }

    get isPayroll() {
        return this.activeTab === 'payroll';
    }

    get isProducts() {
        return this.activeTab === 'products';
    }

    get isContacts() {
        return this.activeTab === 'contacts';
    }

    get isAdmin() {
        return this.activeTab === 'admin';
    }

    // ────────────────────────────────────────────
    // Tab CSS class getters (active / inactive)
    // ────────────────────────────────────────────
    get overviewTabClass() {
        return this.activeTab === 'overview' ? 'tab-button tab-active' : 'tab-button';
    }

    get updatesTabClass() {
        return this.activeTab === 'updates' ? 'tab-button tab-active' : 'tab-button';
    }

    get payrollTabClass() {
        return this.activeTab === 'payroll' ? 'tab-button tab-active' : 'tab-button';
    }

    get productsTabClass() {
        return this.activeTab === 'products' ? 'tab-button tab-active' : 'tab-button';
    }

    get contactsTabClass() {
        return this.activeTab === 'contacts' ? 'tab-button tab-active' : 'tab-button';
    }

    get adminTabClass() {
        return this.activeTab === 'admin' ? 'tab-button tab-active' : 'tab-button';
    }

    // ────────────────────────────────────────────
    // Header action handlers
    // ────────────────────────────────────────────
    handleEmailNow() {
        this.selectedEmailContact = null;
        this.showEmailModal = true;
    }

    handleSnooze() {
        this.showSnoozeDropdown = !this.showSnoozeDropdown;
    }

    handleSnoozeClose() {
        this.showSnoozeDropdown = false;
    }

    // ────────────────────────────────────────────
    // Email modal handlers
    // ────────────────────────────────────────────
    handleEmailModalClose() {
        this.showEmailModal = false;
        this.selectedEmailContact = null;
    }

    handleContactEmail(event) {
        this.selectedEmailContact = event.detail;
        this.showEmailModal = true;
    }

    async handleEmailSent() {
        if (this._wiredResult) {
            refreshApex(this._wiredResult);
        } else if (this.isActionMode && this.effectiveRecordId) {
            try {
                const data = await getPageData({ oppId: this.effectiveRecordId });
                this._applyPageData(data);
            } catch (err) {
                console.error('Error refreshing after email sent:', err);
            }
        }
    }

    // ────────────────────────────────────────────
    // SMS modal handlers
    // ────────────────────────────────────────────
    handleSmsNow() {
        this.selectedSmsContact = null;
        this.showSmsModal = true;
    }

    handleSmsModalClose() {
        this.showSmsModal = false;
        this.selectedSmsContact = null;
    }

    handleContactSms(event) {
        this.selectedSmsContact = event.detail;
        this.showSmsModal = true;
    }

    async handleSmsSent() {
        if (this._wiredResult) {
            refreshApex(this._wiredResult);
        } else if (this.isActionMode && this.effectiveRecordId) {
            try {
                const data = await getPageData({ oppId: this.effectiveRecordId });
                this._applyPageData(data);
            } catch (err) {
                console.error('Error refreshing after SMS sent:', err);
            }
        }
    }

    // ────────────────────────────────────────────
    // Sidebar note-saved handler — refresh data
    // ────────────────────────────────────────────
    async handleNoteSaved() {
        if (this._wiredResult) {
            refreshApex(this._wiredResult);
        } else if (this.isActionMode && this.effectiveRecordId) {
            try {
                const data = await getPageData({ oppId: this.effectiveRecordId });
                this._applyPageData(data);
            } catch (err) {
                console.error('Error refreshing after note save:', err);
            }
        }
    }
}
