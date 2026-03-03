import { LightningElement, api } from 'lwc';

export default class NbaCallNoteCapture extends LightningElement {
    @api callNote; // ActionWrapper for the Call Completed interrupt

    editedNotes = '';
    _initialized = false;

    renderedCallback() {
        if (!this._initialized && this.callNote) {
            this.editedNotes = this.callNote.callNotes || '';
            this._initialized = true;
        }
    }

    // ── Computed Getters ─────────────────────────────────

    get dispositionText() {
        const d = this.callNote?.callDisposition;
        if (!d) return 'Call';
        const lower = d.toLowerCase();
        if (lower.includes('connected')) return 'Connected';
        if (lower.includes('voicemail') || lower.includes('lvm')) return 'Left Voicemail';
        if (lower.includes('no answer') || lower.includes('nvm') || lower.includes('no_answer')) return 'No Answer';
        if (lower.includes('busy')) return 'Busy';
        return d;
    }

    get talkTimeFormatted() {
        const sec = this.callNote?.talkTimeSec;
        if (!sec || sec <= 0) return '';
        const m = Math.floor(sec / 60);
        const s = Math.round(sec % 60);
        return `${m}m ${s}s`;
    }

    get showTalkTime() {
        return this.callNote?.talkTimeSec > 0;
    }

    get dispositionLine() {
        if (this.showTalkTime) {
            return `${this.dispositionText} \u2022 ${this.talkTimeFormatted}`;
        }
        return this.dispositionText;
    }

    // ── Event Handlers ───────────────────────────────────

    handleNotesChange(event) {
        this.editedNotes = event.target.value;
    }

    handleSave() {
        this.dispatchEvent(
            new CustomEvent('savecallnotes', {
                detail: {
                    callCompletedActionId: this.callNote?.actionId,
                    notes: this.editedNotes,
                    stepOutcome: null
                }
            })
        );
    }

    handleSkip() {
        this.dispatchEvent(
            new CustomEvent('skipcallnotes', {
                detail: {
                    callCompletedActionId: this.callNote?.actionId
                }
            })
        );
    }
}
