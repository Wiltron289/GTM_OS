import { LightningElement } from 'lwc';

export default class NbaDemoSnoozeDropdown extends LightningElement {
    get snoozeOptions() {
        return [
            { label: '1 hour', value: '1h' },
            { label: '3 hours', value: '3h' },
            { label: 'Tomorrow morning', value: 'tomorrow' },
            { label: 'Next week', value: 'nextweek' },
            { label: 'Custom time...', value: 'custom', isCustom: true }
        ];
    }

    handleSelect(event) {
        const value = event.currentTarget.dataset.value;
        // Visual only for now - would dispatch event to parent
        console.log('Snooze selected:', value);
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    stopPropagation(event) {
        event.stopPropagation();
    }
}
