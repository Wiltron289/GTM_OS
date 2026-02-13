import { LightningElement, api, wire } from 'lwc';
import getPageData from '@salesforce/apex/NbaDemoController.getPageData';

export default class NbaDemoWorkspace extends LightningElement {
    @api recordId;

    // Tab state
    activeTab = 'overview';

    // Modal / dropdown state
    showEmailModal = false;
    selectedEmailContact = null;
    showSnoozeDropdown = false;

    // Loading & error state
    isLoading = true;
    error;

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

    // ────────────────────────────────────────────
    // Wire: load all page data in a single call
    // ────────────────────────────────────────────
    @wire(getPageData, { oppId: '$recordId' })
    wiredPageData({ data, error }) {
        if (data) {
            this.headerData = data.headerData;
            this.accountData = data.accountData;
            this.payrollStatusData = data.payrollStatusData;
            this.quotaData = data.quotaData;
            this.engagementData = data.engagementData;
            this.payrollTabData = data.payrollTabData;
            this.productsData = data.productsData;
            this.contactsData = data.contactsData;
            this.adminData = data.adminData;
            this.sidebarData = data.sidebarData;
            this.insightsData = data.insightsData;
            this.upcomingEvent = data.upcomingEvent;
            this.error = undefined;
            this.isLoading = false;
        } else if (error) {
            this.error = error;
            this.isLoading = false;
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
}
