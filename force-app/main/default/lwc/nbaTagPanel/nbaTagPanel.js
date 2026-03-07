import { LightningElement, api } from 'lwc';

export default class NbaTagPanel extends LightningElement {
    @api actionTags; // JSON string from Action_Tags__c

    get parsedTags() {
        if (!this.actionTags) return [];
        try {
            const tags = JSON.parse(this.actionTags);
            if (!Array.isArray(tags)) return [];
            return tags.map((tag, idx) => ({
                ...tag,
                key: tag.id || `tag-${idx}`
            }));
        } catch (e) {
            return [];
        }
    }

    get hasTags() {
        return this.parsedTags.length > 0;
    }
}
