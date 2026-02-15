import { LightningElement, api, track } from 'lwc';
import saveNote from '@salesforce/apex/NbaDemoController.saveNote';

export default class NbaDemoSidebar extends LightningElement {
    @api sidebarData;
    @api recordId;
    @api contacts;
    @track activeTab = 'notes';
    @track newNoteText = '';
    @track showAddNote = false;
    @track expandedNoteIds = new Set();

    get isNotesTab() { return this.activeTab === 'notes'; }
    get isActivityTab() { return this.activeTab === 'activity'; }
    get isMessagesTab() { return this.activeTab === 'messages'; }
    get notesTabClass() { return this.activeTab === 'notes' ? 'sidebar-tab active' : 'sidebar-tab'; }
    get activityTabClass() { return this.activeTab === 'activity' ? 'sidebar-tab active' : 'sidebar-tab'; }
    get messagesTabClass() { return this.activeTab === 'messages' ? 'sidebar-tab active' : 'sidebar-tab'; }
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
        return this.notes.map((note, idx) => {
            const key = note.id || 'note-' + idx;
            const isExpanded = this.expandedNoteIds.has(key);
            return {
                ...note,
                key,
                formattedDate: note.createdDate ? new Date(note.createdDate).toLocaleDateString() : '',
                authorDisplay: note.isAiSummary
                    ? '✨ AI Summary'
                    : (note.isCurrentUser ? 'Me' : (note.authorName || 'Me')),
                displayTitle: note.title || 'Rep Note',
                noteClass: note.isAiSummary
                    ? 'note-item ai-note' + (isExpanded ? ' note-expanded' : '')
                    : 'note-item' + (isExpanded ? ' note-expanded' : ''),
                authorBadgeClass: note.isAiSummary
                    ? 'note-author author-badge ai-author-badge'
                    : 'note-author author-badge',
                isExpanded,
                chevronIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright'
            };
        });
    }

    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    handleNoteToggle(event) {
        const noteId = event.currentTarget.dataset.noteId;
        const updated = new Set(this.expandedNoteIds);
        if (updated.has(noteId)) {
            updated.delete(noteId);
        } else {
            updated.add(noteId);
        }
        this.expandedNoteIds = updated;
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
            this.dispatchEvent(new CustomEvent('notesaved'));
        } catch (error) {
            console.error('Error saving note:', error);
        }
    }

    handleSmsSent() {
        this.dispatchEvent(new CustomEvent('smssent'));
    }
}
