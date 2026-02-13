import { LightningElement, api } from 'lwc';
export default class NbaDemoAdminTab extends LightningElement {
    @api adminData;

    get ownerDisplay() {
        return this.adminData?.ownerName || '\u2014';
    }
    get isSameLane() {
        return true; // demo placeholder
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
