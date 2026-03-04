import { LightningElement, api } from 'lwc';

export default class NbaCallNoteCapture extends LightningElement {
    @api callNote; // Platform Event payload object with callNotes, callDisposition, talkTimeSec, etc.

    _userEditedNotes = null; // null = user hasn't edited yet; use callNote.callNotes
    _domInitialized = false;

    get notesValue() {
        if (this._userEditedNotes !== null) {
            return this._userEditedNotes;
        }
        return this.callNote?.callNotes || '';
    }

    renderedCallback() {
        // Belt-and-suspenders: directly set DOM textarea value
        // in case value={} binding doesn't propagate on native <textarea>
        if (!this._domInitialized && this.callNote?.callNotes) {
            const ta = this.template.querySelector('.notes-textarea');
            if (ta && !ta.value) {
                ta.value = this.callNote.callNotes;
            }
            this._domInitialized = true;
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
        this._userEditedNotes = event.target.value;
    }

    handleSave() {
        this.dispatchEvent(
            new CustomEvent('savecallnotes', {
                detail: {
                    notes: this.notesValue,
                    stepOutcome: null
                }
            })
        );
    }

    handleSkip() {
        this.dispatchEvent(
            new CustomEvent('skipcallnotes', {
                detail: {}
            })
        );
    }
}
