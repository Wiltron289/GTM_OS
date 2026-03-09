import { LightningElement, api } from 'lwc';

const VALUE_TRUNCATE_LENGTH = 120;

const GATE_LABELS = {
    NEW_TO_CONNECTED: 'Required for Connected',
    CONNECTED_TO_CONSULT: 'Required for Consult',
    CONSULT_TO_CLOSING: 'Required for Closing'
};

const GATE_FIELDS = {
    NEW_TO_CONNECTED: ['Customer_Story__c', 'Decision_Maker_Identified__c', 'Inception_or_Switcher__c'],
    CONNECTED_TO_CONSULT: ['Business_Challenge__c', 'Best_Product_Fit_Identified__c'],
    CONSULT_TO_CLOSING: [
        'Features_and_Benefits_Discussed__c',
        'Budget_Confirmed__c',
        'Timeline_Confirmed__c',
        'Verbal_Commit__c'
    ]
};

const STAGE_INDEX = { New: 0, Connected: 1, Consult: 2, Closing: 3 };

const INCEPTION_SWITCHER_OPTIONS = [
    { label: '-- None --', value: '' },
    { label: 'Inception', value: 'Inception' },
    { label: 'Switcher', value: 'Switcher' }
];

export default class NbaPostCallPanel extends LightningElement {
    _postCallContext;
    @api callNote;

    @api
    get postCallContext() {
        return this._postCallContext;
    }
    set postCallContext(value) {
        this._postCallContext = value;
        this._isEditMode = false;
        this._fieldEdits = {};
        this._userEditedNotes = null;
    }

    _userEditedNotes = null;
    _isEditMode = false;
    _fieldEdits = {};

    // ── Hero subtitle ─────────────────────────────
    get heroSubtitle() {
        if (this.showStageTransition) {
            return 'AI has analyzed the conversation and detected that stage criteria have been met.';
        }
        if (this.hasDetectedFields) {
            return 'AI has analyzed the conversation and detected qualification updates.';
        }
        return 'Call has been recorded. Review the notes below.';
    }

    // ── Stage computation ─────────────────────────
    get displayCurrentStage() {
        if (this.postCallContext?.stageChanged) {
            return this.postCallContext.previousStage || '';
        }
        return this.postCallContext?.currentStage || '';
    }

    get displayNewStage() {
        if (this.postCallContext?.stageChanged) {
            return this.postCallContext.currentStage || '';
        }
        return this._computeRecommendedStage();
    }

    get showStageTransition() {
        const newStage = this.displayNewStage;
        const currentStage = this.displayCurrentStage;
        if (!newStage || !currentStage) return false;
        const newIdx = STAGE_INDEX[newStage];
        const curIdx = STAGE_INDEX[currentStage];
        return newIdx != null && curIdx != null && newIdx > curIdx;
    }

    _computeRecommendedStage() {
        const fields = this.postCallContext?.qualificationFields;
        if (!fields) return null;

        const fieldMap = {};
        fields.forEach((f) => {
            fieldMap[f.fieldName] = f.value;
        });

        const isPopulated = (val) => val != null && val !== '' && val !== false;
        const gateMet = (gate) => GATE_FIELDS[gate].every((f) => isPopulated(fieldMap[f]));

        // Gates are cumulative — each requires the previous to be met
        let stage = null;
        if (gateMet('NEW_TO_CONNECTED')) stage = 'Connected';
        if (stage === 'Connected' && gateMet('CONNECTED_TO_CONSULT')) stage = 'Consult';
        if (stage === 'Consult' && gateMet('CONSULT_TO_CLOSING')) stage = 'Closing';

        return stage;
    }

    // ── Detected fields (populated qualification fields) ──
    get _allDetectedFields() {
        const fields = this.postCallContext?.qualificationFields;
        if (!fields) return [];
        let index = 0;
        return fields
            .map((f) => this._buildFieldViewModel(f))
            .filter((f) => f.hasValue)
            .map((f) => ({
                ...f,
                staggerStyle: `animation-delay: ${index++ * 50}ms`
            }));
    }

    get detectedTextFields() {
        return this._allDetectedFields.filter((f) => !f.isBoolean);
    }

    get detectedBooleanFields() {
        return this._allDetectedFields.filter((f) => f.isBoolean);
    }

    get hasDetectedFields() {
        return this._allDetectedFields.length > 0;
    }

    get hasBooleanDetectedFields() {
        return this.detectedBooleanFields.length > 0;
    }

    get showRecommendedUpdate() {
        return this.hasDetectedFields || this.showStageTransition;
    }

    get showEmptyState() {
        return !this.showRecommendedUpdate;
    }

    // ── Edit mode ─────────────────────────────────
    get isEditMode() {
        return this._isEditMode;
    }

    get isDisplayMode() {
        return !this._isEditMode;
    }

    get editButtonLabel() {
        return this._isEditMode ? 'Cancel' : 'Edit Details';
    }

    get editButtonIcon() {
        return this._isEditMode ? 'utility:close' : 'utility:edit';
    }

    get confirmButtonLabel() {
        return this.showStageTransition ? 'Accept & Update Stage' : 'Confirm & Continue';
    }

    get inceptionSwitcherOptions() {
        return INCEPTION_SWITCHER_OPTIONS;
    }

    // ── Call notes ─────────────────────────────────
    get notesValue() {
        if (this._userEditedNotes != null) {
            return this._userEditedNotes;
        }
        return this.postCallContext?.callNotes || '';
    }

    get notesDisplayValue() {
        return this.notesValue || 'No call notes available';
    }

    get notesTextClass() {
        return this.notesValue ? 'notes-text' : 'notes-text notes-text-empty';
    }

    // ── Field view model builder ──────────────────
    _buildFieldViewModel(field) {
        const isBoolean = field.fieldType === 'boolean';
        const isPicklist = field.fieldName === 'Inception_or_Switcher__c';
        const isText = !isBoolean && !isPicklist;

        const editedVal = this._fieldEdits[field.fieldName];
        const rawValue = editedVal !== undefined ? editedVal : field.value;

        const hasValue = rawValue != null && rawValue !== '' && rawValue !== false;
        const fullValue = isBoolean ? '' : String(rawValue || '');
        const displayValue =
            fullValue.length > VALUE_TRUNCATE_LENGTH
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
            booleanLabel: boolVal ? 'Yes' : 'No',
            gateLabel: GATE_LABELS[field.stageGate] || '',
            editTextValue: fullValue,
            editBoolChecked: boolVal,
            editPicklistValue: fullValue || ''
        };
    }

    // ── Event handlers ────────────────────────────
    handleNotesChange(event) {
        this._userEditedNotes = event.target.value;
    }

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

    handleConfirm() {
        const notes = this.notesValue;
        const fieldEdits = { ...this._fieldEdits };
        this.dispatchEvent(
            new CustomEvent('confirm', {
                detail: { notes, fieldEdits }
            })
        );
    }

    handleEditFields() {
        if (this._isEditMode) {
            this._fieldEdits = {};
            this._isEditMode = false;
        } else {
            // Pre-populate fieldEdits with current values so textareas render populated
            const fields = this.postCallContext?.qualificationFields;
            if (fields) {
                const edits = {};
                fields.forEach((f) => {
                    if (f.value != null && f.value !== '' && f.value !== false) {
                        edits[f.fieldName] = f.value;
                    }
                });
                this._fieldEdits = edits;
            }
            this._isEditMode = true;
        }
    }

    handleSkip() {
        this.dispatchEvent(new CustomEvent('skip'));
    }

    handleBackdropClick() {
        this.handleSkip();
    }

    handleCardClick(event) {
        event.stopPropagation();
    }
}
