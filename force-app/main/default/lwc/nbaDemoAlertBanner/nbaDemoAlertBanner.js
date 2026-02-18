import { LightningElement, api } from 'lwc';

export default class NbaDemoAlertBanner extends LightningElement {
    @api upcomingEvent;
    @api currentAction;
    @api isActionMode = false;
    @api pendingInterrupts = [];

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

    // ── Interrupt Banner (Stream 2 — two-stream) ─────────────
    get showInterruptBanner() {
        return this.isActionMode
            && this.pendingInterrupts
            && this.pendingInterrupts.length > 0;
    }

    get topInterrupt() {
        return this.pendingInterrupts?.[0] || null;
    }

    get interruptMessage() {
        const interrupt = this.topInterrupt;
        if (!interrupt) return '';

        const type = interrupt.actionType || 'Action';
        const acctName = interrupt.accountName || '';
        const oppName = interrupt.opportunityName || '';

        if (interrupt.isTimeBound && interrupt.dueAt) {
            const dueDate = new Date(interrupt.dueAt);
            const now = new Date();
            const diffMin = Math.round((dueDate.getTime() - now.getTime()) / 60000);
            const timeStr = dueDate.toLocaleTimeString('en-US', {
                hour: 'numeric',
                minute: '2-digit',
                hour12: true
            });
            if (diffMin <= 0) {
                return `${type} for ${acctName || oppName} was due at ${timeStr} (overdue)`;
            }
            return `${type} for ${acctName || oppName} at ${timeStr} (in ${diffMin} min)`;
        }

        // New-assignment interrupt
        return `New ${type} — ${acctName || oppName} just assigned to you`;
    }

    get interruptCount() {
        return this.pendingInterrupts?.length || 0;
    }

    get interruptCountBadge() {
        const count = this.interruptCount;
        return count > 1 ? `+${count - 1} more` : '';
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

    handleAcceptInterrupt() {
        const interrupt = this.topInterrupt;
        if (interrupt) {
            this.dispatchEvent(
                new CustomEvent('acceptinterrupt', {
                    detail: { actionId: interrupt.actionId }
                })
            );
        }
    }

    handleDismissInterrupt() {
        const interrupt = this.topInterrupt;
        if (interrupt) {
            this.dispatchEvent(
                new CustomEvent('dismissinterrupt', {
                    detail: { actionId: interrupt.actionId }
                })
            );
        }
    }
}
