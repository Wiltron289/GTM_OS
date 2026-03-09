# Post-Call Intelligence Panel — Session Plan

**Created**: 2026-03-09
**Branch**: `feature/post-call-intelligence` (branch off `testing/sprint-22-20260303`)
**Goal**: Detect call record insertion (Talkdesk Activity + AI_Call_Note__c), update the GTM OS Workspace with a rich post-call panel showing AI-extracted notes, qualification field changes, and stage progression.

---

## Background & Context

### What Exists Today

1. **Talkdesk call detection** in GTM OS via `Call_Completed_Event__e` Platform Event → `empApi` push → `nbaCallNoteCapture` overlay. Shows: raw call notes, disposition, talk time. Does NOT show qualification fields or stage progression.

2. **SalesforceAICallNotes project** (`C:\Users\Yeyian PC\SalesforceAICallNotes`) — separate repo with:
   - `AI_Call_Note__c` custom object (38 fields) — receives AI-generated call analysis via REST API
   - `AICallNoteQualificationSync` — syncs 9 qualification fields from AI_Call_Note__c → Opportunity
   - `TalkdeskQualificationTrigger` → `TalkdeskNotesParser` → `TalkdeskQualificationSync` — parses markdown notes on Talkdesk Activity, syncs 9 qualification fields to Opportunity
   - CMDT-controlled rollout (`Talkdesk_Qualification_Config__mdt`)

3. **Stage progression Flow** (`301Po00001ICbCG`) — gates Opportunity stages based on field population:

   | Transition | Required Fields |
   |------------|----------------|
   | NEW → CONNECTED | `Customer_Story__c` (populated), `Decision_Maker_Identified__c` (true), `Inception_or_Switcher__c` (populated) |
   | CONNECTED → CONSULT | `Business_Challenge__c` (populated), `Best_Product_Fit_Identified__c` (true) |
   | CONSULT → CLOSING | `Features_and_Benefits_Discussed__c` (populated), `Budget_Confirmed__c` (true), `Timeline_Confirmed__c` (true), `Verbal_Commit__c` (true) |

4. **Field sync guardrails** (both projects):
   - Text fields: write only if Opp field is blank
   - Checkbox fields: ratchet only (false → true, never true → false)

### Key Architecture Decisions

- **Single event channel**: Reuse `Call_Completed_Event__e` with a `Source_Type__c` discriminator (`Talkdesk` / `AI_Call_Note`) rather than creating a second Platform Event
- **Query-after-event**: LWC receives lightweight Platform Event as detection signal, then calls Apex `getPostCallContext()` to get full qualification + stage data. By the time the event arrives (`PublishAfterCommit`), the qualification sync and stage flow will have already executed.
- **New component**: Replace `nbaCallNoteCapture` with `nbaPostCallPanel` (scope is significantly larger)
- **Stage "before" state**: Use the Opp `StageName` already cached in the workspace from `getPageData()` as the "before" value

### 9 Qualification Fields (AI_Call_Note__c/Talkdesk Activity → Opportunity)

| # | Source Field | Opportunity Field | Type | Sync Rule |
|---|-------------|------------------|------|-----------|
| 1 | `Customer_Story__c` | `Customer_Story__c` | LongTextArea | Write if blank |
| 2 | `Inception_Or_Switcher__c` | `Inception_or_Switcher__c` | Text/Picklist | Write if blank |
| 3 | `Decision_Maker_Identified__c` | `Decision_Maker_Identified__c` | Checkbox | false→true only |
| 4 | `Business_Challenges__c` | `Business_Challenge__c` | LongTextArea | Write if blank |
| 5 | `Best_Product_Fit_Identified__c` | `Best_Product_Fit_Identified__c` | Checkbox | false→true only |
| 6 | `Features_Benefits_Discussed__c` | `Features_and_Benefits_Discussed__c` | LongTextArea | Write if blank |
| 7 | `Budget_Confirmed__c` | `Budget_Confirmed__c` | Checkbox | false→true only |
| 8 | `Timeline_Confirmed__c` | `Timeline_Confirmed__c` | Checkbox | false→true only |
| 9 | `Verbal_Commit__c` | `Verbal_Commit__c` | Checkbox | false→true only |

### Existing Files to Know About

**GTM OS (this repo):**
- `force-app/main/default/triggers/NbaTalkdeskActivityTrigger.trigger` — existing trigger on Talkdesk Activity
- `force-app/main/default/classes/NbaTalkdeskActivityTriggerHandler.cls` — publishes `Call_Completed_Event__e`, writes audit records
- `force-app/main/default/classes/NbaActionController.cls` — `saveCallNotes()` method
- `force-app/main/default/lwc/nbaDemoWorkspace/` — empApi subscription, `_pendingCallNote` state
- `force-app/main/default/lwc/nbaCallNoteCapture/` — current simple overlay (to be replaced)
- `force-app/main/default/objects/Call_Completed_Event__e/` — Platform Event definition (8 fields)

**SalesforceAICallNotes (separate repo at `C:\Users\Yeyian PC\SalesforceAICallNotes`):**
- `force-app/main/default/classes/AICallNoteService.cls` — REST endpoint, record creation
- `force-app/main/default/classes/AICallNoteQualificationSync.cls` — syncs to Opp on AI_Call_Note__c insert
- `force-app/main/default/classes/TalkdeskQualificationHandler.cls` — orchestrates Talkdesk qualification
- `force-app/main/default/classes/TalkdeskNotesParser.cls` — parses markdown notes
- `force-app/main/default/classes/TalkdeskQualificationSync.cls` — syncs to Opp from Talkdesk Activity
- `force-app/main/default/objects/AI_Call_Note__c/` — 38-field custom object

---

## Session Plan (6 Sessions)

---

### Session 1: Platform Event Enrichment + AI_Call_Note__c Detection

**Goal**: Extend the Platform Event to identify source type, and create a new trigger so AI_Call_Note__c insertions push events to the workspace.

**Scope**:

1. **Add 2 fields to `Call_Completed_Event__e`**:
   - `Source_Type__c` — Text(20): `'Talkdesk'` or `'AI_Call_Note'`
   - `Source_Record_Id__c` — Text(18): the Activity ID or AI_Call_Note__c ID

2. **Update `NbaTalkdeskActivityTriggerHandler`**:
   - Populate `Source_Type__c = 'Talkdesk'` and `Source_Record_Id__c = activity.Id` on published events
   - Minimal change — just 2 new field assignments in the existing event-building loop

3. **Create `AICallNoteGtmTrigger.trigger`** (after insert on `AI_Call_Note__c`):
   - Delegates to `AICallNoteGtmTriggerHandler.cls`

4. **Create `AICallNoteGtmTriggerHandler.cls`**:
   - Filters for records with `Opportunity__c` populated
   - Queries Opportunity for `Name`, `Account.Name`, `OwnerId`
   - Publishes `Call_Completed_Event__e` with:
     - `Source_Type__c = 'AI_Call_Note'`
     - `Source_Record_Id__c = note.Id`
     - `Sales_Rep_Id__c = opp.OwnerId`
     - `Opportunity_Id__c = note.Opportunity__c`
     - `Call_Notes__c = note.Topics_Discussed__c` (or Main_Challenges__c — best summary field)
     - `Account_Name__c`, `Opp_Name__c` from Opp query
     - `Disposition__c = 'AI Analysis'` (distinguishes from Talkdesk dispositions)
   - Invalidates cache for affected AE via `NbaCacheService`

5. **Create `AICallNoteGtmTriggerHandlerTest.cls`**:
   - Test insert with Opp link → event published
   - Test insert without Opp link → no event
   - Test bulk insert (200 records)
   - Test Source_Type__c and Source_Record_Id__c values

**Entry criteria**: Branch `testing/sprint-22-20260303` checked out, up to date
**Exit criteria**: All new/modified Apex compiles, new tests pass, existing `NbaTalkdeskActivityTriggerHandlerTest` still passes
**Files created/modified**: ~6 files (2 Platform Event fields, 1 trigger, 1 handler, 1 test, 1 existing handler update)

---

### Session 2: Post-Call Context Apex Method — COMPLETE

**Goal**: Build the Apex method the LWC will call after receiving a Platform Event to get full qualification + stage context.

**Scope**:

1. **Add `getPostCallContext()` to `NbaActionController.cls`**:
   ```
   @AuraEnabled
   public static PostCallContext getPostCallContext(
       Id opportunityId,
       String sourceType,
       Id sourceRecordId,
       String previousStage
   )
   ```

2. **Inner class `PostCallContext`** (returned to LWC):
   ```
   @AuraEnabled public String opportunityId
   @AuraEnabled public String previousStage
   @AuraEnabled public String currentStage
   @AuraEnabled public Boolean stageChanged
   @AuraEnabled public List<QualificationField> qualificationFields
   @AuraEnabled public String callNotes          // editable notes
   @AuraEnabled public String sourceType         // 'Talkdesk' or 'AI_Call_Note'
   ```
   **Design decision**: The 5 AI-specific fields (customerProfile, topicsDiscussed, mainChallenges, dealMomentum, overallTone) from the original plan were removed — those are the same qualification fields already captured in the `qualificationFields` list from the Opp query. Neither Talkdesk Activity nor AI_Call_Note__c has separate "AI analysis" fields; both objects share the same 9 qualification fields.

3. **Inner class `QualificationField`**:
   ```
   @AuraEnabled public String fieldName          // API name
   @AuraEnabled public String label              // Display label
   @AuraEnabled public String fieldType          // 'text', 'boolean', 'picklist'
   @AuraEnabled public Object value              // Current value on Opp
   @AuraEnabled public Boolean isNewlyPopulated  // Was blank/false before, now has value
   @AuraEnabled public String stageGate          // Which transition this field gates
   ```

4. **Logic**:
   - Query Opportunity for all 9 qualification fields + StageName (1 SOQL)
   - Query source record for callNotes (1 SOQL): AI_Call_Note → `Customer_Story__c`, Talkdesk → `talkdesk__Notes__c`
   - Compare `previousStage` param with current `StageName` → set `stageChanged`
   - For each qualification field: determine if `isNewlyPopulated` by checking if value is non-blank/true
   - Map each field to its `stageGate` (`'NEW_TO_CONNECTED'`, `'CONNECTED_TO_CONSULT'`, `'CONSULT_TO_CLOSING'`)
   - Try/catch on source record query for graceful degradation
   - Return structured `PostCallContext`

5. **Tests in `NbaActionControllerTest.cls`** (5 new methods, 24 total — all passing):
   - Test with AI_Call_Note source → returns correct context + callNotes from Customer_Story__c
   - Test with Talkdesk source → returns correct context + callNotes from talkdesk__Notes__c
   - Test stage change detection (previousStage differs from current)
   - Test no stage change (previousStage matches current)
   - Test with no qualification fields populated (all isNewlyPopulated = false)

**Entry criteria**: Session 1 complete (Platform Event fields + AI_Call_Note trigger deployed)
**Exit criteria**: `getPostCallContext()` returns correct data for both source types, all tests pass
**Files modified**: 2 files (NbaActionController.cls, NbaActionControllerTest.cls)
**Commits**: `17f84bd` (initial), `4b49090` (simplify — remove AI-specific fields)

---

### Session 3: Post-Call Panel LWC — Layout & Display — COMPLETE

**Goal**: Build the new `nbaPostCallPanel` LWC that displays post-call intelligence. Display-only this session — no editing or save.

**Scope**:

1. **Create `nbaPostCallPanel` LWC** (HTML + JS + CSS + meta):

   **Layout sections**:
   - **Header bar**: Source badge (Talkdesk/Zoom icon), "Call Analysis Complete", close button
   - **Stage progression banner** (conditional): Animated `OLD STAGE → NEW STAGE` with arrow, green highlight. Only shown if `stageChanged === true`.
   - **Qualification fields grid**: 2-column grid of field cards. Each card shows:
     - Field label
     - Current value (truncated with expand)
     - Green checkmark badge if `isNewlyPopulated`
     - Stage gate label (e.g., "Required for Connected")
     - Grouped by stage transition
   - **Call notes textarea**: Pre-populated from source record (AI_Call_Note → Customer_Story__c, Talkdesk → talkdesk__Notes__c), editable (but save wired in Session 4)
   - **Button row**: "Confirm & Continue" (primary), "Edit Fields" (secondary), "Skip" (tertiary)

2. **Component API**:
   ```javascript
   @api postCallContext;   // PostCallContext object from Apex
   @api callNote;          // Original Platform Event payload (fallback)
   // Events: 'confirm', 'editfields', 'skip'
   ```

3. **CSS**: Follow existing design token system (`--nba-*` variables). Stage progression uses `--nba-emerald-*` for success states. Qualification cards use `--nba-blue-*` for populated fields.

4. **Wire into `nbaDemoWorkspace`**:
   - Replace `showCallNoteCapture` / `<c-nba-call-note-capture>` with `showPostCallPanel` / `<c-nba-post-call-panel>`
   - Update `_handleCallCompletedEvent()` to call `getPostCallContext()` after receiving event
   - Store result in `_postCallContext` state variable
   - Pass to child component

**Entry criteria**: Session 2 complete (`getPostCallContext()` deployed and tested)
**Exit criteria**: Panel renders correctly with mock data, stage banner animates, qualification fields display, workspace shows panel on Platform Event receipt
**Files created/modified**: ~5 files (4 new LWC files + nbaDemoWorkspace.js/html updates)
**Commits**: `e75c779` (LWC + workspace wiring)

**Implementation notes**:
- `nbaPostCallPanel` uses overlay-backdrop pattern from `nbaCallNoteCapture` (z-index 299/300)
- Fields grouped by stage gate using `GATE_ORDER` array for consistent ordering
- Boolean fields render as check/close icons with Yes/No labels (not raw true/false)
- Text values truncated at 120 chars with `...` suffix
- Workspace falls back to old `nbaCallNoteCapture` if `getPostCallContext()` fails
- `previousStage` captured from `engagementData.stageName` (not headerData)
- `_handleCallCompletedEvent` now async — calls `getPostCallContext()` Apex after building raw callNote

---

### Session 4: Save, Edit & Confirm Flow — COMPLETE

**Goal**: Wire up the save/edit/confirm actions so the AE can review, edit qualification fields, save notes, and continue.

**Scope**:

1. **Add `savePostCallEdits()` to `NbaActionController.cls`**:
   ```
   @AuraEnabled
   public static Boolean savePostCallEdits(
       Id opportunityId,
       String notes,
       Map<String, Object> fieldEdits  // { 'Customer_Story__c': 'new value', ... }
   )
   ```
   - Updates Opportunity fields from `fieldEdits` map (same guardrails: write-if-blank, checkbox ratchet)
   - Saves notes as ContentNote linked to Opp (existing pattern)
   - Returns true on success

2. **Inline field editing in `nbaPostCallPanel`**:
   - "Edit Fields" button toggles edit mode on qualification field cards
   - Text fields → textarea inputs
   - Checkbox fields → toggle switches
   - Picklist fields → combobox dropdown
   - Pre-populated from current values
   - "Cancel Edit" reverts to display mode

3. **Confirm flow**:
   - "Confirm & Continue" → calls `savePostCallEdits()` with any edits + notes → clears panel → loads next action
   - "Skip" → clears panel without saving → loads next action
   - Loading spinner during save

4. **Workspace event handlers**:
   - `handlePostCallConfirm(event)` → save + clear `_postCallContext` + refresh action
   - `handlePostCallSkip()` → clear `_postCallContext`
   - `handlePostCallEdit()` → toggle edit mode on child

5. **Tests for `savePostCallEdits()`**:
   - Test saves notes as ContentNote
   - Test updates text field when blank
   - Test does NOT overwrite existing text field
   - Test checkbox ratchet (false→true works, true→false blocked)

**Entry criteria**: Session 3 complete (panel displays correctly)
**Exit criteria**: Full edit→save→continue flow works, all tests pass, existing tests still pass
**Files modified**: ~4 files (NbaActionController.cls, NbaActionControllerTest.cls, nbaPostCallPanel.js/html)
**Commits**: `aa4de59` (save, edit & confirm flow)

**Implementation notes**:
- `savePostCallEdits()` applies guardrails: text/picklist write-if-blank, boolean ratchet (false→true only)
- Edit mode handled entirely in `nbaPostCallPanel` child (no parent handler needed)
- Text fields → textarea, Booleans → custom toggle switch, Picklist → lightning-combobox
- `_fieldEdits` map tracks only changed fields; Cancel clears and exits edit mode
- Workspace `handlePostCallConfirm` passes `fieldEdits` to new Apex method, then refreshes page data
- 5 new tests (29 total in NbaActionControllerTest), all passing. Controller at 89% coverage.

---

### Session 5: Polish, Edge Cases & Integration Testing

**Goal**: Handle edge cases, polish animations, ensure both detection paths work end-to-end, and harden the feature.

**Scope**:

1. **Edge cases**:
   - Platform Event arrives but Opp no longer matches current action (AE moved on) → queue/ignore
   - Multiple events arrive before AE acts → queue, show most recent
   - AI_Call_Note__c inserted WITHOUT qualification data (partial analysis) → show what's available, graceful empty states
   - Talkdesk Activity inserted but notes parsing fails → fallback to raw notes display
   - Stage jumps multiple levels (NEW → CLOSING) → show multi-step progression
   - AE is NOT in action mode (Record Page) → still show panel if Opp matches `recordId`

2. **Animation & transitions**:
   - Stage progression: animated slide with brief delay between stages
   - Qualification fields: staggered fade-in for newly populated fields
   - Panel entrance: slide-up from bottom or fade-in overlay

3. **Workspace state cleanup**:
   - After confirm/skip, ensure `_postCallContext` is fully cleared
   - If action changes while panel is open, dismiss panel
   - Handle `disconnectedCallback` cleanup

4. **Record Page mode support**:
   - In Record Page mode (not App Page), the panel should still work
   - Filter Platform Events by `recordId` instead of `currentAction.opportunityId`
   - Adjust `showPostCallPanel` getter for dual-mode

5. **Integration verification**:
   - Manual test path: Talkdesk Activity insert → event → panel → edit → save → verify Opp fields
   - Manual test path: AI_Call_Note__c insert → event → panel → confirm → verify
   - Verify no regression on existing interrupt banners, action bar, cadence flow

**Entry criteria**: Session 4 complete (edit/save flow works)
**Exit criteria**: All edge cases handled, both detection paths verified, no regressions
**Files modified**: ~4-6 files (workspace JS, panel JS/CSS, possibly handler updates)
**Commits**: `07e90d8` (polish, edge cases & event queue)

**Implementation notes**:
- `_pendingEventQueue` array queues Platform Events while panel is open; processed FIFO after confirm/skip
- `_showPostCallForEvent()` extracted from `_handleCallCompletedEvent()` for reuse by queue processor
- `_dismissPostCallPanel()` helper clears all panel state + empties event queue (used by action change paths)
- `_processEventQueue()` recursively skips stale events (Opp mismatch) before showing next valid one
- `postCallContext` @api property converted to getter/setter in nbaPostCallPanel — setter resets edit state
- `showPostCallPanel` / `showCallNoteCapture` getters removed `isActionMode` guard — now work in Record Page mode
- empApi subscription moved to `connectedCallback()` (outside `if (!this.recordId)` block) for dual-mode support
- CSS animations: `fieldFadeIn` (0.3s ease-out) with `animation-delay` set via inline `style` attribute per field
- `fieldFadeInHighlight` for newly populated fields adds brief green glow (box-shadow pulse)
- Stage labels use `stageFadeIn` with staggered delays (0.1s old, 0.3s new) for left-slide entrance
- `editExpand` keyframe animates `max-height` 0→200px for smooth edit mode toggle

---

### Session 6: Cleanup, Deprecation & Documentation

**Goal**: Remove old code, update all documentation, final deploy and test suite run.

**Scope**:

1. **Deprecate `nbaCallNoteCapture`**:
   - Remove component files (HTML, JS, CSS, meta) OR keep as dead code with deprecation comment
   - Remove all references from `nbaDemoWorkspace` (template + JS)
   - Update `nbaCallNoteCapture.js-meta.xml` if keeping (mark not exposed)

2. **Update CLAUDE.md**:
   - Add Feature 16: Post-Call Intelligence Panel
   - Document the architecture (detection → context query → panel → save)
   - Add new gotchas discovered during implementation
   - Update "What Exists" section

3. **Update `docs/architecture.md`**:
   - Add Post-Call Intelligence Panel to component tree
   - Document Platform Event enrichment (Source_Type, Source_Record_Id)
   - Document `getPostCallContext()` and `savePostCallEdits()` data contracts

4. **Update `docs/sprint-history.md`**:
   - Log all changes with file lists and commit hashes

5. **Full test suite run**:
   - Run all GTM OS targeted tests (261 + new tests)
   - Verify ≥75% coverage on all new/modified classes
   - Run `npm test` for LWC Jest if applicable

6. **Deploy to UAT**:
   - `sf project deploy start --source-dir force-app`
   - Run targeted tests in org
   - Verify end-to-end in browser

**Entry criteria**: Session 5 complete (all edge cases handled)
**Exit criteria**: Old code removed, docs updated, all tests passing, deployed to UAT
**Files modified**: ~8-10 files (deletions, doc updates, CLAUDE.md)

---

## Quick Reference: Session Startup

Each session should start by reading:
1. `CLAUDE.md` (working rules, project state)
2. This file (`docs/POST-CALL-INTELLIGENCE-PLAN.md`) — for phase context
3. The specific files listed in that session's scope

### Branch Strategy
```
testing/sprint-22-20260303  (base)
  └── feature/post-call-intelligence  (work branch)
```

### Key Apex Files to Know
| File | Purpose |
|------|---------|
| `NbaActionController.cls` | LWC controller — add `getPostCallContext()`, `savePostCallEdits()` |
| `NbaTalkdeskActivityTriggerHandler.cls` | Existing Talkdesk event publisher — add Source_Type |
| `NbaCacheService.cls` | Platform Cache — invalidate on new events |
| `NbaActionControllerTest.cls` | Controller tests — add new test methods |

### Key LWC Files to Know
| File | Purpose |
|------|---------|
| `nbaDemoWorkspace/nbaDemoWorkspace.js` | empApi subscription, state management |
| `nbaDemoWorkspace/nbaDemoWorkspace.html` | Template — replace call note capture section |
| `nbaCallNoteCapture/*` | OLD component (to be replaced by nbaPostCallPanel) |
| `nbaPostCallPanel/*` | NEW component (created in Session 3) |

### SalesforceAICallNotes Reference (separate repo)
Location: `C:\Users\Yeyian PC\SalesforceAICallNotes`
- `AI_Call_Note__c` field definitions: `force-app/main/default/objects/AI_Call_Note__c/fields/`
- Qualification sync logic: `force-app/main/default/classes/AICallNoteQualificationSync.cls`
- Talkdesk notes parser: `force-app/main/default/classes/TalkdeskNotesParser.cls`
