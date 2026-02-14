import { LightningElement, api, track } from 'lwc';
export default class NbaDemoAdminTab extends LightningElement {
    @api adminData;
    @track fieldUpdatesExpanded = true;
    @track slaExpanded = true;
    @track historyExpanded = true;
    @track auditExpanded = true;

    get fieldUpdatesChevron() {
        return this.fieldUpdatesExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }
    get slaChevron() {
        return this.slaExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }
    get historyChevron() {
        return this.historyExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }
    get auditChevron() {
        return this.auditExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    toggleFieldUpdates() { this.fieldUpdatesExpanded = !this.fieldUpdatesExpanded; }
    toggleSla() { this.slaExpanded = !this.slaExpanded; }
    toggleHistory() { this.historyExpanded = !this.historyExpanded; }
    toggleAudit() { this.auditExpanded = !this.auditExpanded; }

    get ownerDisplay() {
        return this.adminData?.ownerName || '\u2014';
    }

    get formattedCreatedDate() {
        if (!this.adminData?.createdDate) return '\u2014';
        return new Date(this.adminData.createdDate).toLocaleString();
    }
    get formattedLastCallDateTime() {
        if (!this.adminData?.lastCallDateTime) return '\u2014';
        return new Date(this.adminData.lastCallDateTime).toLocaleString();
    }
    get formattedLastMeetingDate() {
        if (!this.adminData?.lastMeetingDate) return '\u2014';
        return new Date(this.adminData.lastMeetingDate).toLocaleString();
    }
    get formattedNextMeeting() {
        if (!this.adminData?.nextScheduledMeeting) return '\u2014';
        return new Date(this.adminData.nextScheduledMeeting).toLocaleString();
    }
    get formattedFirstAssignment() {
        if (!this.adminData?.firstAssignmentDateTime) return '\u2014';
        return new Date(
            this.adminData.firstAssignmentDateTime
        ).toLocaleString();
    }
    get formattedLastAssignment() {
        if (!this.adminData?.lastAssignmentDateTime) return '\u2014';
        return new Date(
            this.adminData.lastAssignmentDateTime
        ).toLocaleString();
    }
}
