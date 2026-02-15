import { LightningElement, api } from 'lwc';

export default class NbaDemoAlertBanner extends LightningElement {
    @api upcomingEvent;
    @api currentAction;
    @api isActionMode = false;

    dismissed = false;
    urgencyDismissed = false;

    get showBanner() {
        return this.upcomingEvent?.hasUpcoming && !this.dismissed;
    }

    get showUrgencyBanner() {
        return this.isActionMode
            && this.currentAction?.isTimeBound
            && this.currentAction?.dueAt
            && !this.urgencyDismissed;
    }

    get urgencyMessage() {
        if (!this.currentAction?.dueAt) return '';
        const dueDate = new Date(this.currentAction.dueAt);
        const now = new Date();
        const diffMs = dueDate.getTime() - now.getTime();
        const diffMin = Math.round(diffMs / 60000);
        const timeStr = dueDate.toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        });
        if (diffMin <= 0) {
            return `Action was due at ${timeStr} (overdue)`;
        }
        return `Action due by ${timeStr} (in ${diffMin} minutes)`;
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

    handleUrgencyDismiss() {
        this.urgencyDismissed = true;
    }
}
