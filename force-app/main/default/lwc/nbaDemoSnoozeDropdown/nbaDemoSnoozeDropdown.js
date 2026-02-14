import { LightningElement } from 'lwc';

export default class NbaDemoSnoozeDropdown extends LightningElement {
    get snoozeOptions() {
        return [
            { label: '1 hour', value: '1h', className: 'option-label' },
            { label: '3 hours', value: '3h', className: 'option-label' },
            { label: 'Tomorrow morning', value: 'tomorrow', className: 'option-label' },
            { label: 'Next week', value: 'nextweek', className: 'option-label' },
            { label: 'Custom time...', value: 'custom', className: 'option-label custom' }
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
