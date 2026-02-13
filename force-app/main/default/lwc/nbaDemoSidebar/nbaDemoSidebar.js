import { LightningElement, api, track } from 'lwc';
import saveNote from '@salesforce/apex/NbaDemoController.saveNote';

export default class NbaDemoSidebar extends LightningElement {
    @api sidebarData;
    @api recordId;
    @track activeTab = 'notes';
    @track newNoteText = '';
    @track showAddNote = false;

    get isNotesTab() { return this.activeTab === 'notes'; }
    get isActivityTab() { return this.activeTab === 'activity'; }
    get notesTabClass() { return this.activeTab === 'notes' ? 'sidebar-tab active' : 'sidebar-tab'; }
    get activityTabClass() { return this.activeTab === 'activity' ? 'sidebar-tab active' : 'sidebar-tab'; }
    get notes() { return this.sidebarData?.notes || []; }
    get hasNotes() { return this.notes.length > 0; }

    get activities() {
        return (this.sidebarData?.activities || []).map((act, idx) => ({
            ...act,
            key: act.id || 'act-' + idx,
            formattedDate: act.activityDate || '',
            hasContact: !!act.contactName
        }));
    }
    get hasActivities() { return this.activities.length > 0; }

    get computedNotes() {
        return this.notes.map((note, idx) => ({
            ...note,
            key: note.id || 'note-' + idx,
            formattedDate: note.createdDate ? new Date(note.createdDate).toLocaleDateString() : '',
            authorDisplay: note.isAiSummary ? '✨ AI Summary' : (note.authorName || 'Me'),
            noteClass: note.isAiSummary ? 'note-item ai-note' : 'note-item'
        }));
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    toggleAddNote() {
        this.showAddNote = !this.showAddNote;
    }

    handleNoteChange(event) {
        this.newNoteText = event.target.value;
    }

    async handleSaveNote() {
        if (!this.newNoteText.trim()) return;
        try {
            await saveNote({ oppId: this.recordId, noteBody: this.newNoteText });
            this.newNoteText = '';
            this.showAddNote = false;
        } catch (error) {
            console.error('Error saving note:', error);
        }
    }
}
