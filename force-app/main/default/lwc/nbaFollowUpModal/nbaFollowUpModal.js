import { LightningElement, api, track } from 'lwc';
import createFollowUp from '@salesforce/apex/NbaActionController.createFollowUp';

const METHOD_OPTIONS = [
    { label: 'Call', value: 'Call', icon: 'utility:call' },
    { label: 'Email', value: 'Email', icon: 'utility:email' },
    { label: 'SMS', value: 'SMS', icon: 'utility:chat' },
    { label: 'Meeting', value: 'Meeting', icon: 'utility:event' }
];

export default class NbaFollowUpModal extends LightningElement {
    @api opportunityId;

    @track selectedMethod = 'Call';
    @track followUpDate = '';
    @track followUpTime = '';
    @track notes = '';
    @track isSaving = false;
    @track errorMessage = '';

    get methodOptions() {
        return METHOD_OPTIONS.map(opt => ({
            ...opt,
            cssClass: this.selectedMethod === opt.value
                ? 'method-chip selected' : 'method-chip'
        }));
    }

    get isSaveDisabled() {
        return this.isSaving || !this.followUpDate || !this.followUpTime;
    }

    get saveButtonClass() {
        return this.isSaveDisabled
            ? 'modal-btn save-btn disabled' : 'modal-btn save-btn';
    }

    handleMethodSelect(event) {
        this.selectedMethod = event.currentTarget.dataset.value;
    }

    handleDateChange(event) {
        this.followUpDate = event.target.value;
        this.errorMessage = '';
    }

    handleTimeChange(event) {
        this.followUpTime = event.target.value;
        this.errorMessage = '';
    }

    handleNotesChange(event) {
        this.notes = event.target.value;
    }

    async handleSave() {
        if (this.isSaveDisabled) return;

        // Build datetime from date + time inputs
        const followUpDt = new Date(`${this.followUpDate}T${this.followUpTime}`);
        if (isNaN(followUpDt.getTime())) {
            this.errorMessage = 'Invalid date/time selected.';
            return;
        }
        if (followUpDt <= new Date()) {
            this.errorMessage = 'Follow-up must be in the future.';
            return;
        }

        this.isSaving = true;
        this.errorMessage = '';

        try {
            await createFollowUp({
                opportunityId: this.opportunityId,
                method: this.selectedMethod,
                followUpDt: followUpDt.toISOString(),
                notes: this.notes || null
            });

            this.dispatchEvent(new CustomEvent('setfollowup', {
                detail: {
                    method: this.selectedMethod,
                    followUpDt: followUpDt.toISOString()
                }
            }));
        } catch (err) {
            this.errorMessage = err.body?.message || 'Failed to create follow-up.';
        } finally {
            this.isSaving = false;
        }
    }

    handleNoFollowUp() {
        this.dispatchEvent(new CustomEvent('nofollowup'));
    }

    handleOverlayClick(event) {
        // Only close if clicking the overlay itself, not the modal content
        if (event.target === event.currentTarget) {
            this.handleNoFollowUp();
        }
    }
}
