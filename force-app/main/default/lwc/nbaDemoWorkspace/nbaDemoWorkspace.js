import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import Id from '@salesforce/user/Id';
import getPageData from '@salesforce/apex/NbaDemoController.getPageData';
import getActiveAction from '@salesforce/apex/NbaActionController.getActiveAction';
import checkInterrupts from '@salesforce/apex/NbaActionController.checkInterrupts';
import acceptInterrupt from '@salesforce/apex/NbaActionController.acceptInterrupt';
import completeAction from '@salesforce/apex/NbaActionController.completeAction';
import snoozeAction from '@salesforce/apex/NbaActionController.snoozeAction';
import dismissAction from '@salesforce/apex/NbaActionController.dismissAction';
import saveCallNotes from '@salesforce/apex/NbaActionController.saveCallNotes';
import savePostCallEdits from '@salesforce/apex/NbaActionController.savePostCallEdits';
import getPostCallContext from '@salesforce/apex/NbaActionController.getPostCallContext';

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
    _pendingCallNote = null;    // Platform Event payload for Call Completed overlay
    _postCallContext = null;    // PostCallContext from Apex (replaces simple call note capture)
    _previousStage = null;      // Cached stage before Platform Event arrived
    _pendingEventQueue = [];    // Queued Platform Events received while panel is open

    // ── Follow-up modal state ────────────────────────────────
    _showFollowUpModal = false;
    _pendingCompleteResult = null;  // Stashed result from completeAction, used after follow-up decision

    // ── Platform Event subscription ─────────────────────────
    _callCompletedSubscription = null;

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
        // Subscribe to Call Completed Platform Events in both modes
        this._subscribeToCallCompletedEvents();

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
        // Unsubscribe from Platform Event channel
        if (this._callCompletedSubscription) {
            unsubscribe(this._callCompletedSubscription, () => {
                this._callCompletedSubscription = null;
            });
        }
        // Clear post-call state to prevent memory leaks
        this._postCallContext = null;
        this._pendingCallNote = null;
        this._pendingEventQueue = [];
        this._previousStage = null;
    }

    // ────────────────────────────────────────────
    // Platform Event: Call Completed subscription
    // ────────────────────────────────────────────
    _subscribeToCallCompletedEvents() {
        const channel = '/event/Call_Completed_Event__e';

        // Register error listener
        onError((error) => {
            console.error('[nbaDemoWorkspace] empApi error:', JSON.stringify(error));
        });

        subscribe(channel, -1, (message) => {
            this._handleCallCompletedEvent(message);
        }).then((subscription) => {
            this._callCompletedSubscription = subscription;
        });
    }

    async _handleCallCompletedEvent(message) {
        const payload = message.data?.payload;
        if (!payload) {
            return;
        }

        // Filter: only events for the current user
        if (payload.Sales_Rep_Id__c !== this.userId) {
            return;
        }

        // Filter: only events matching the currently displayed Opportunity
        // In Action mode: match against currentAction.opportunityId
        // In Record Page mode: match against recordId
        const targetOppId = this.isActionMode
            ? this.currentAction?.opportunityId
            : this.recordId;
        if (!targetOppId || payload.Opportunity_Id__c !== targetOppId) {
            return;
        }

        const eventPayload = {
            opportunityId: payload.Opportunity_Id__c,
            activityId: payload.Activity_Id__c,
            callNotes: payload.Call_Notes__c,
            callDisposition: payload.Disposition__c,
            talkTimeSec: payload.Talk_Time_Sec__c,
            accountName: payload.Account_Name__c,
            oppName: payload.Opp_Name__c,
            sourceType: payload.Source_Type__c || 'Talkdesk',
            sourceRecordId: payload.Source_Record_Id__c || payload.Activity_Id__c
        };

        // If panel is already open, queue the event instead of ignoring it
        if (this._postCallContext || this._pendingCallNote) {
            this._pendingEventQueue = [...this._pendingEventQueue, eventPayload];
            return;
        }

        await this._showPostCallForEvent(eventPayload);
    }

    async _showPostCallForEvent(eventPayload) {
        // Save the raw call note as fallback
        this._pendingCallNote = eventPayload;

        // Capture current stage BEFORE the sync/flow ran (cached from getPageData)
        this._previousStage = this.engagementData?.stageName || '';

        // Call Apex for full post-call context
        try {
            const ctx = await getPostCallContext({
                opportunityId: eventPayload.opportunityId,
                sourceType: eventPayload.sourceType,
                sourceRecordId: eventPayload.sourceRecordId,
                previousStage: this._previousStage
            });
            if (ctx) {
                this._postCallContext = ctx;
            }
            // If getPostCallContext returns null, _pendingCallNote remains as fallback
        } catch (err) {
            console.error('[nbaDemoWorkspace] getPostCallContext error:', err);
            // Fall back to _pendingCallNote (old call note capture)
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
                    // Dismiss post-call panel if action changed while open
                    this._dismissPostCallPanel();
                    this.currentAction = action;
                    this.showEmptyState = false;
                    if (action.opportunityId !== prevOppId) {
                        const data = await getPageData({ oppId: action.opportunityId });
                        this._applyPageData(data);
                    }
                }
            } else if (this.currentAction) {
                // Actions cleared — show empty state
                this._dismissPostCallPanel();
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
            const filtered = (interrupts || []).filter(
                (i) => !this._dismissedInterruptIds.has(i.actionId)
            );

            // Regular interrupts only (Call Completed now handled via Platform Events)
            this.pendingInterrupts = filtered;
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

    get showPostCallPanel() {
        return this._postCallContext != null;
    }

    get showCallNoteCapture() {
        // Only show old call note capture as fallback when post-call context failed
        return this._pendingCallNote != null && this._postCallContext == null;
    }

    get showTagPanel() {
        return this.isActionMode && this.currentAction?.actionTags;
    }

    get showFollowUpModal() {
        return this.isActionMode && this._showFollowUpModal;
    }

    get showEventDetails() {
        return this.isActionMode
            && this.currentAction?.actionType === 'Meeting'
            && this.currentAction?.eventId;
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
    // Post-Call Panel handlers
    // ────────────────────────────────────────────
    async handlePostCallConfirm(event) {
        const { notes, fieldEdits } = event.detail;
        const oppId = this._postCallContext?.opportunityId || this.currentAction?.opportunityId || this.recordId;
        this.isTransitioning = true;
        try {
            await savePostCallEdits({
                opportunityId: oppId,
                notes: notes || '',
                fieldEdits: fieldEdits || {}
            });

            // Refresh page data to reflect updated qualification fields
            if (oppId) {
                const data = await getPageData({ oppId });
                this._applyPageData(data);
            }
        } catch (err) {
            this.error = err;
        } finally {
            this._postCallContext = null;
            this._pendingCallNote = null;
            this._previousStage = null;
            this.isTransitioning = false;
            // Process next queued event if any
            this._processEventQueue();
        }
    }

    handlePostCallSkip() {
        this._postCallContext = null;
        this._pendingCallNote = null;
        this._previousStage = null;
        // Process next queued event if any
        this._processEventQueue();
    }

    _dismissPostCallPanel() {
        if (this._postCallContext || this._pendingCallNote) {
            this._postCallContext = null;
            this._pendingCallNote = null;
            this._previousStage = null;
            this._pendingEventQueue = [];
        }
    }

    async _processEventQueue() {
        if (this._pendingEventQueue.length === 0) {
            return;
        }
        // Take the next event from the queue
        const nextEvent = this._pendingEventQueue[0];
        this._pendingEventQueue = this._pendingEventQueue.slice(1);

        // Verify it still matches the current Opp
        const targetOppId = this.isActionMode
            ? this.currentAction?.opportunityId
            : this.recordId;
        if (nextEvent.opportunityId === targetOppId) {
            await this._showPostCallForEvent(nextEvent);
        } else {
            // Skip stale events, try next
            await this._processEventQueue();
        }
    }

    // ────────────────────────────────────────────
    // Call Notes capture handlers (fallback)
    // ────────────────────────────────────────────
    async handleSaveCallNotes(event) {
        const { notes } = event.detail;
        this.isTransitioning = true;
        this._pendingCallNote = null;
        try {
            await saveCallNotes({
                opportunityId: this.currentAction?.opportunityId || this.recordId,
                notes
            });
        } catch (err) {
            this.error = err;
        } finally {
            this.isTransitioning = false;
            this._processEventQueue();
        }
    }

    handleSkipCallNotes() {
        this._pendingCallNote = null;
        this._processEventQueue();
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

            // Show follow-up modal after completing a Call step (Connected or VM)
            const isCallOutcome = stepOutcome === 'Connected' || stepOutcome === 'VM';
            if (isCallOutcome) {
                this._pendingCompleteResult = result;
                this._showFollowUpModal = true;
                this.isTransitioning = false;
                return;
            }

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
        // Dismiss post-call panel when action changes
        this._dismissPostCallPanel();

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
    // Follow-Up Modal handlers
    // ────────────────────────────────────────────
    async handleFollowUpSet() {
        // Follow-up was created by the modal's Apex call.
        // Now proceed with the stashed complete result.
        this._showFollowUpModal = false;
        const result = this._pendingCompleteResult;
        this._pendingCompleteResult = null;
        if (result) {
            this.isTransitioning = true;
            await this._handleActionResult(result);
        }
    }

    async handleFollowUpSkip() {
        // AE chose no follow-up — proceed with the stashed result.
        this._showFollowUpModal = false;
        const result = this._pendingCompleteResult;
        this._pendingCompleteResult = null;
        if (result) {
            this.isTransitioning = true;
            await this._handleActionResult(result);
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
