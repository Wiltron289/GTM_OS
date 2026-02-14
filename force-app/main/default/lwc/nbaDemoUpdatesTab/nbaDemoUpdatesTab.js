import { LightningElement, api } from 'lwc';
export default class NbaDemoUpdatesTab extends LightningElement {
    @api recordId;

    get inputVariables() {
        return [
            { name: 'recordId', type: 'String', value: this.recordId }
        ];
    }

    handleFlowStatusChange(event) {
        if (
            event.detail.status === 'FINISHED' ||
            event.detail.status === 'FINISHED_SCREEN'
        ) {
            // Flow completed - could refresh data
        }
    }
}
