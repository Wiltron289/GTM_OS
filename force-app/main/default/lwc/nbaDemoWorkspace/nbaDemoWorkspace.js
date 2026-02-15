import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import Id from '@salesforce/user/Id';
import getPageData from '@salesforce/apex/NbaDemoController.getPageData';
import getActiveAction from '@salesforce/apex/NbaActionController.getActiveAction';
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
    _pollInterval = null;

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

            // Poll every 60s for new actions (e.g., trigger-created Layer 1 time-bound)
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._pollInterval = setInterval(() => {
                if (!this.isTransitioning && !this.isLoading) {
                    this._refreshActiveAction();
                }
            }, 60000);
        }
    }

    disconnectedCallback() {
        if (this._pollInterval) {
            clearInterval(this._pollInterval);
            this._pollInterval = null;
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
                const prevActionId = this.currentAction?.actionId;
                const prevOppId = this.currentAction?.opportunityId;

                // Only update if the action changed (new action or different opp)
                if (action.actionId !== prevActionId) {
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
    // Action lifecycle handlers (App Page mode)
    // ────────────────────────────────────────────
    async handleCompleteAction(event) {
        const { actionId } = event.detail;
        this.isTransitioning = true;
        try {
            const result = await completeAction({ actionId });
            await this._handleActionResult(result);
        } catch (err) {
            this.error = err;
            this.isTransitioning = false;
        }
    }

    async handleSnoozeAction(event) {
        const { actionId, reason, durationMinutes } = event.detail;
        this.isTransitioning = true;
        try {
            const result = await snoozeAction({ actionId, reason, durationMinutes });
            await this._handleActionResult(result);
        } catch (err) {
            this.error = err;
            this.isTransitioning = false;
        }
    }

    async handleDismissAction(event) {
        const { actionId, reason, category } = event.detail;
        this.isTransitioning = true;
        try {
            const result = await dismissAction({ actionId, reason, category });
            await this._handleActionResult(result);
        } catch (err) {
            this.error = err;
            this.isTransitioning = false;
        }
    }

    async _handleActionResult(result) {
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

    handleEmailSent() {
        if (this._wiredResult) {
            refreshApex(this._wiredResult);
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

    handleSmsSent() {
        if (this._wiredResult) {
            refreshApex(this._wiredResult);
        }
    }

    // ────────────────────────────────────────────
    // Sidebar note-saved handler — refresh data
    // ────────────────────────────────────────────
    handleNoteSaved() {
        if (this._wiredResult) {
            refreshApex(this._wiredResult);
        }
    }
}
