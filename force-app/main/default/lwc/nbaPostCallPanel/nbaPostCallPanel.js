import { LightningElement, api } from 'lwc';

const VALUE_TRUNCATE_LENGTH = 120;

const GATE_LABELS = {
    NEW_TO_CONNECTED: 'Required for Connected',
    CONNECTED_TO_CONSULT: 'Required for Consult',
    CONSULT_TO_CLOSING: 'Required for Closing'
};

const GATE_ORDER = ['NEW_TO_CONNECTED', 'CONNECTED_TO_CONSULT', 'CONSULT_TO_CLOSING'];

const INCEPTION_SWITCHER_OPTIONS = [
    { label: '-- None --', value: '' },
    { label: 'Inception', value: 'Inception' },
    { label: 'Switcher', value: 'Switcher' }
];

export default class NbaPostCallPanel extends LightningElement {
    @api postCallContext;
    @api callNote; // Original Platform Event payload (fallback)

    _userEditedNotes = null;
    _isEditMode = false;
    _fieldEdits = {}; // { fieldName: newValue }
    _originalFieldValues = {}; // snapshot on entering edit mode

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

    // ── Edit mode state ──────────────────────────
    get isEditMode() {
        return this._isEditMode;
    }

    get isDisplayMode() {
        return !this._isEditMode;
    }

    get editButtonLabel() {
        return this._isEditMode ? 'Cancel Edit' : 'Edit Fields';
    }

    get inceptionSwitcherOptions() {
        return INCEPTION_SWITCHER_OPTIONS;
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
        const isPicklist = field.fieldName === 'Inception_or_Switcher__c';
        const isText = !isBoolean && !isPicklist;

        // Use edited value if available, otherwise original
        const editedVal = this._fieldEdits[field.fieldName];
        const rawValue = editedVal !== undefined ? editedVal : field.value;

        const hasValue = rawValue != null && rawValue !== '' && rawValue !== false;
        const fullValue = isBoolean ? '' : String(rawValue || '');
        const displayValue = fullValue.length > VALUE_TRUNCATE_LENGTH
            ? fullValue.substring(0, VALUE_TRUNCATE_LENGTH) + '...'
            : fullValue;

        const boolVal = rawValue === true || rawValue === 'true';

        return {
            fieldName: field.fieldName,
            label: field.label,
            fieldType: field.fieldType,
            isBoolean,
            isPicklist,
            isText,
            hasValue,
            fullValue,
            displayValue,
            isNewlyPopulated: field.isNewlyPopulated === true,
            cardClass: field.isNewlyPopulated ? 'field-card field-card-new' : 'field-card',
            booleanIcon: boolVal ? 'utility:check' : 'utility:close',
            booleanClass: boolVal ? 'bool-icon bool-true' : 'bool-icon bool-false',
            booleanTextClass: boolVal ? 'bool-text bool-text-true' : 'bool-text bool-text-false',
            booleanLabel: boolVal ? 'Yes' : 'No',
            // Edit mode values
            editTextValue: fullValue,
            editBoolChecked: boolVal,
            editPicklistValue: fullValue || ''
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

    // ── Edit mode: field change handlers ─────────
    handleTextFieldChange(event) {
        const fieldName = event.target.dataset.field;
        this._fieldEdits = { ...this._fieldEdits, [fieldName]: event.target.value };
    }

    handleBooleanToggle(event) {
        const fieldName = event.target.dataset.field;
        this._fieldEdits = { ...this._fieldEdits, [fieldName]: event.target.checked };
    }

    handlePicklistChange(event) {
        const fieldName = event.target.dataset.field;
        this._fieldEdits = { ...this._fieldEdits, [fieldName]: event.detail.value };
    }

    // ── Button handlers ──────────────────────────
    handleConfirm() {
        const notes = this.notesValue;
        const fieldEdits = { ...this._fieldEdits };
        this.dispatchEvent(new CustomEvent('confirm', {
            detail: { notes, fieldEdits }
        }));
    }

    handleEditFields() {
        if (this._isEditMode) {
            // Cancel edit — revert to original values
            this._fieldEdits = {};
            this._isEditMode = false;
        } else {
            // Enter edit mode — snapshot current values for cancel
            this._isEditMode = true;
        }
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
