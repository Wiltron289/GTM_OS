import { LightningElement, api } from 'lwc';

export default class NbaDemoAlertBanner extends LightningElement {
    @api upcomingEvent;

    dismissed = false;

    get showBanner() {
        return this.upcomingEvent?.hasUpcoming && !this.dismissed;
    }

    get bannerMessage() {
        if (!this.upcomingEvent) return '';
        return `Meeting with ${this.upcomingEvent.contactName} at ${this.upcomingEvent.accountName} in ${this.upcomingEvent.minutesUntil} minutes`;
    }

    handleJumpToOpp() {
        this.dispatchEvent(
            new CustomEvent('navigatetoopportunity', {
                detail: {
                    opportunityId: this.upcomingEvent?.opportunityId
                }
            })
        );
    }

    handleDismiss() {
        this.dismissed = true;
    }
}
