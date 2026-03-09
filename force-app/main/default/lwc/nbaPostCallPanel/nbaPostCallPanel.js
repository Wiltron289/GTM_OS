import { LightningElement, api } from 'lwc';

const VALUE_TRUNCATE_LENGTH = 120;

const GATE_LABELS = {
    NEW_TO_CONNECTED: 'Required for Connected',
    CONNECTED_TO_CONSULT: 'Required for Consult',
    CONSULT_TO_CLOSING: 'Required for Closing'
};

const GATE_ORDER = ['NEW_TO_CONNECTED', 'CONNECTED_TO_CONSULT', 'CONSULT_TO_CLOSING'];

export default class NbaPostCallPanel extends LightningElement {
    @api postCallContext;
    @api callNote; // Original Platform Event payload (fallback)

    _userEditedNotes = null;

    // ── Source badge ──────────────────────────────
    get sourceIcon() {
        if (this.postCallContext?.sourceType === 'AI_Call_Note') {
            return 'utility:einstein';
        }
        return 'utility:call';
    }

    get sourceLabel() {
        if (this.postCallContext?.sourceType === 'AI_Call_Note') {
            return 'AI Call Note';
        }
        return 'Talkdesk';
    }

    // ── Stage progression ────────────────────────
    get showStageBanner() {
        return this.postCallContext?.stageChanged === true;
    }

    get previousStage() {
        return this.postCallContext?.previousStage || '';
    }

    get currentStage() {
        return this.postCallContext?.currentStage || '';
    }

    // ── Qualification fields grouped by stage gate ──
    get fieldGroups() {
        const fields = this.postCallContext?.qualificationFields;
        if (!fields || fields.length === 0) {
            return [];
        }

        // Group fields by stageGate
        const grouped = {};
        fields.forEach((f) => {
            const gate = f.stageGate || 'OTHER';
            if (!grouped[gate]) {
                grouped[gate] = [];
            }
            grouped[gate].push(this._buildFieldViewModel(f));
        });

        // Return in gate order
        const result = [];
        GATE_ORDER.forEach((gate) => {
            if (grouped[gate]) {
                result.push({
                    gate,
                    gateLabel: GATE_LABELS[gate] || gate,
                    fields: grouped[gate]
                });
            }
        });

        // Add any ungrouped fields
        Object.keys(grouped).forEach((gate) => {
            if (!GATE_ORDER.includes(gate)) {
                result.push({
                    gate,
                    gateLabel: gate,
                    fields: grouped[gate]
                });
            }
        });

        return result;
    }

    _buildFieldViewModel(field) {
        const isBoolean = field.fieldType === 'boolean';
        const hasValue = field.value != null && field.value !== '' && field.value !== false;
        const fullValue = isBoolean ? '' : String(field.value || '');
        const displayValue = fullValue.length > VALUE_TRUNCATE_LENGTH
            ? fullValue.substring(0, VALUE_TRUNCATE_LENGTH) + '...'
            : fullValue;

        const boolVal = field.value === true || field.value === 'true';

        return {
            fieldName: field.fieldName,
            label: field.label,
            isBoolean,
            hasValue,
            fullValue,
            displayValue,
            isNewlyPopulated: field.isNewlyPopulated === true,
            cardClass: field.isNewlyPopulated ? 'field-card field-card-new' : 'field-card',
            booleanIcon: boolVal ? 'utility:check' : 'utility:close',
            booleanClass: boolVal ? 'bool-icon bool-true' : 'bool-icon bool-false',
            booleanTextClass: boolVal ? 'bool-text bool-text-true' : 'bool-text bool-text-false',
            booleanLabel: boolVal ? 'Yes' : 'No'
        };
    }

    // ── Call notes ────────────────────────────────
    get notesValue() {
        if (this._userEditedNotes != null) {
            return this._userEditedNotes;
        }
        return this.postCallContext?.callNotes || '';
    }

    handleNotesChange(event) {
        this._userEditedNotes = event.target.value;
    }

    // ── Button handlers ──────────────────────────
    handleConfirm() {
        const notes = this.notesValue;
        this.dispatchEvent(new CustomEvent('confirm', {
            detail: { notes }
        }));
    }

    handleEditFields() {
        this.dispatchEvent(new CustomEvent('editfields'));
    }

    handleSkip() {
        this.dispatchEvent(new CustomEvent('skip'));
    }

    // ── Backdrop click = skip ────────────────────
    handleBackdropClick() {
        this.handleSkip();
    }

    handleCardClick(event) {
        event.stopPropagation();
    }
}
