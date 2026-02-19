import { LightningElement, api, wire } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import SUBJECT from '@salesforce/schema/Event.Subject';
import DESCRIPTION from '@salesforce/schema/Event.Description';
import LOCATION from '@salesforce/schema/Event.Location';
import START_DT from '@salesforce/schema/Event.StartDateTime';
import END_DT from '@salesforce/schema/Event.EndDateTime';

const FIELDS = [SUBJECT, DESCRIPTION, LOCATION, START_DT, END_DT];

export default class NbaEventDetails extends LightningElement {
    @api eventId;

    descriptionExpanded = false;

    @wire(getRecord, { recordId: '$eventId', fields: FIELDS })
    wiredEvent;

    get isLoaded() {
        return this.wiredEvent?.data && !this.wiredEvent?.error;
    }

    get hasError() {
        return !!this.wiredEvent?.error;
    }

    get subject() {
        return getFieldValue(this.wiredEvent.data, SUBJECT) || 'Meeting';
    }

    get location() {
        return getFieldValue(this.wiredEvent.data, LOCATION);
    }

    get description() {
        return getFieldValue(this.wiredEvent.data, DESCRIPTION);
    }

    get hasLocation() {
        return !!this.location;
    }

    get hasDescription() {
        return !!this.description;
    }

    get timeRange() {
        const start = getFieldValue(this.wiredEvent.data, START_DT);
        const end = getFieldValue(this.wiredEvent.data, END_DT);
        if (!start) return '';
        const opts = { hour: 'numeric', minute: '2-digit', hour12: true };
        const startStr = new Date(start).toLocaleTimeString('en-US', opts);
        if (!end) return startStr;
        const endStr = new Date(end).toLocaleTimeString('en-US', opts);
        return `${startStr} – ${endStr}`;
    }

    get dateLabel() {
        const start = getFieldValue(this.wiredEvent.data, START_DT);
        if (!start) return '';
        return new Date(start).toLocaleDateString('en-US', {
            weekday: 'short',
            month: 'short',
            day: 'numeric'
        });
    }

    get displayDescription() {
        const desc = this.description;
        if (!desc) return '';
        if (this.descriptionExpanded || desc.length <= 120) return desc;
        return desc.substring(0, 120) + '...';
    }

    get showExpandLink() {
        return this.hasDescription && this.description.length > 120 && !this.descriptionExpanded;
    }

    get showCollapseLink() {
        return this.hasDescription && this.description.length > 120 && this.descriptionExpanded;
    }

    handleExpandDescription() {
        this.descriptionExpanded = true;
    }

    handleCollapseDescription() {
        this.descriptionExpanded = false;
    }
}
