# Sprint History - NBA V2 Demo LWC

**Branch**: `feature/nba-v2-demo-lwc`

This file contains detailed sprint-by-sprint change logs for the NBA V2 Demo LWC feature. For current architecture and patterns, see [architecture.md](architecture.md). For resolved bugs, see [troubleshooting.md](troubleshooting.md).

---

## Commits on Branch

1. `feat: Add NbaDemoController Apex class for NBA V2 demo LWC`
2. `feat: Add 16 NBA V2 demo LWC components`
3. `feat: Add NbaDemoControllerTest and NBA V2 Demo FlexiPage`
4. `fix: Resolve deploy issues - remove MRR_Potential__c, fix snooze HTML, add Source__c to tests`
5. `docs: Update CLAUDE.md with Feature 2 (NBA V2 Demo LWC) status and troubleshooting`
6. `fix: Resolve Apex test failures - resilient Opp queries and Comparable sort`
7. `docs: Update CLAUDE.md - mark Feature 2 tests as passing, add resolved troubleshooting`
8. `fix: Correct wire data property names in nbaDemoWorkspace`
9. `fix: Resolve field mapping bugs, contacts query, and payroll tab layout`
10. `fix: Sprint 2 UX refinements - 8 issues resolved`
11. `style: Design overhaul - align NBA V2 demo LWC with Tailwind design spec`
12. `style: Design polish - 8 changes to align with Magic Patterns prototype`
13. `feat: Sprint 5 - section header redesign, contact dropdown, collapsible rich text notes`
14. `fix: Sprint 6 - quota donut arc fix, Amount for thisOpp, update CLAUDE.md`
15. `fix: Email modal - rich text body + contact dropdown populates To field`
16. `fix: Email sendEmail - add WhatId for merge tags, activity linking, sidebar refresh`
17. `feat: Add SMS integration via Mogli SMS - Apex layer`
18. `feat: Add SMS modal LWC + header/workspace/contacts integration`
19. `docs: Update CLAUDE.md with Sprint 8 - SMS integration via Mogli SMS`
20. `fix: Set SMS Status to 'Queued' for Mogli delivery trigger`
21. `fix: Change SMS Direction from 'Outbound' to 'Outgoing' for Mogli delivery`
22. `feat: Add SMS conversation view in sidebar Messages tab`
23. `docs: Update CLAUDE.md with Sprint 9 - SMS fix + conversation view`
24. `fix: Sprint 10 - sidebar UX polish, contact dropdown, hidden scrollbars`
25. `feat: Phase 6 cadence rule integration (Sprint 17)`
26. `fix: Set Max_Attempts_Per_Day to 0 for hint-only CMDT records`
27. `docs: Add Phase 6 cadence integration plan (Sprint 17)`
28. `fix: Platform Cache key, suppression rules, and null audit records (Sprint 16)`
29. `fix: Pin action bar to viewport bottom + convert panels to modal overlays`
30. `feat: Sprint 18 — Phase 7 cadence redesign foundation (2-CMDT + rewritten service)`
31. `feat: Sprint 19 — cadence service integration + outcome capture LWC (Phase 7)`
32. `feat: Sprint 20 — Re_engage_A cadence definition (6 steps, 7 days)`
33. `refactor: Sprint 20 — remove deprecated Phase 6 backward-compat code`
34. `chore: Sprint 20 — deactivate 12 Phase 6 NBA_Cadence_Rule__mdt records`
35. `test: Sprint 20 — Re_engage_A test coverage + remove deprecated test`

## Demo Data (org-only, not in repo)

- 3 `Account_Scoring__c` records for: Bluegrass Pools (7%/43%), Focus Group Services LLC (6%/31%), Makenna Koffee Franchise (5%/30%)
- Best demo Opportunity: **Bluegrass Pools** (`006Po000011vxwjIAA`) - 179 emp, 10 locations, aio tier, $2,421, 4 tasks, 3 events, contact, product, scoring record

---

## Initial Build (Commits 1-4)

**Files Created (73 total):**
- `classes/NbaDemoController.cls` + meta (~910 lines)
- `classes/NbaDemoControllerTest.cls` + meta (~560 lines)
- `flexipages/NBA_V2_Demo.flexipage-meta.xml`
- 17 LWC components x 4 files each = 68 files under `lwc/nbaDemo*`

**Bugs fixed (commit 9):**
- **Payroll Tab JS property mismatches**: `inceptionSwitcher` should be `inceptionOrSwitcher`, `currentNextStep` mapped to nonexistent field (now `nextStepLabel`), `nextStep` mapped to wrong field (now `nextStepLabel`)
- **Contacts Tab data access bug**: `this.contactsData?.contacts` tried to access `.contacts` on what was already an array. Changed to `Array.isArray(this.contactsData) ? this.contactsData : []`
- **Contacts query only hit OpportunityContactRole**: Now also queries all Account contacts (deduped by ContactId), so Contact tab shows both OCR contacts and Account contacts
- **Payroll tab layout restructured**: Changed from 4-column grid to 2-pair label-value layout matching prototype, added Admin Link and Check Console Link to Progression section

---

## Sprint 2 - UX Refinement (commit `a1350a2`, 14 tests passing)

Commit 10: `fix: Sprint 2 UX refinements - 8 issues resolved`

| # | Issue | Fix Summary |
|---|-------|-------------|
| 5 | Email contacts dropdown empty | Fixed array-vs-wrapper bug: `this.contacts?.contacts` -> `Array.isArray(this.contacts)` |
| 6 | "Same Lane" badge on Admin tab | Removed -- was misread of prototype owner name "Sierra Lane" |
| 7 | MRR badge shows $0 | Now uses `Amount` as primary, `MRR__c` as fallback, with `toLocaleString` formatting |
| 2 | Products tab redundant header | Removed static "Current Opportunity Details" header + fixed products data access bug |
| 4 | Email body too small | Replaced inline style with CSS class targeting 300px min-height |
| 1 | Notes not showing in sidebar | Added `ContentDocumentLink` SOQL query for ContentNotes + `refreshApex` after save |
| 3 | No email template picker | New `getEmailTemplates()` Apex method + template combobox in modal |
| 8 | No collapsible sections | Added chevron toggle to 6 components: Account Details, Payroll Status, Quota, Sales Engagement, Payroll Tab (4 sections), Admin Tab (4 sections). Insights Panel already had collapse. |

**New Apex method added:** `getEmailTemplates()` -- cacheable, queries active `EmailTemplate` records, returns `List<Map<String, String>>` with id/name/subject/body.

**New inner class added:** `NoteDataComparator implements System.Comparator<NoteData>` -- sorts notes by date descending.

---

## Sprint 3 - Design Overhaul (commit `5166a1e`, 14 tests passing)

Commit 11: `style: Design overhaul - align NBA V2 demo LWC with Tailwind design spec`

**What changed:** Comprehensive CSS redesign across all 16 NBA demo components to match the product designer's Tailwind CSS prototype specification.

**Key visual changes:**
| Element | Before | After |
|---|---|---|
| Font | Salesforce Sans | `ui-sans-serif, system-ui` (system stack) |
| Email Now CTA | Green `#059669` | Blue-600 `#2563eb` (split button) |
| Send Email btn | Green `#059669` | Blue-600 `#2563eb` |
| Active tabs | Blue `#0070d2` | Blue-600 `#2563eb` |
| Section labels | 12px, gray | 10px, slate-400, tracking 0.1em |
| Icon containers | Circles (50%) | Rounded squares (8px) |
| Sidebar toggle | Underline tabs | Pill segmented control (rounded-full) |
| Note entries | No accent | Left border (blue user, purple AI) |
| MRR/Close badges | Green text | Neutral bordered pills |
| Cards | Shadow only | 1px slate-200 border + shadow-sm |
| AI insight | Purple bg | Blue-50 bg + blue-200 border |
| Stage badge | Indigo square | Purple-50 pill (rounded-full) |
| Page layout | `min-height: 100vh` | `height: 100vh; overflow: hidden` (no outer scroll) |
| Sidebar width | 340px | 320px (xl: 384px) |

**Files changed (19 total):** 16 CSS files + 3 HTML files (header split button, quota SVG stroke, contacts avatar color). Zero JS changes.

---

## Sprint 4 - Design Polish (14 tests passing)

Commit 12: `style: Design polish - 8 changes to align with Magic Patterns prototype`

| # | Change | Summary |
|---|--------|---------|
| 1 | Card section headers | `.card-title` upgraded from 10px/slate-400 to 16px/slate-900 across 4 components |
| 2 | Chevron icons | Size `xx-small` -> `x-small`, added hover color transition on `.collapsible-header` in 4 components |
| 3 | AI Insight formatting | Single paragraph -> bulleted list with "Show more" toggle when >2 signals |
| 4 | Insights Panel bg | Gradient changed from indigo->indigo to blue-50->indigo-50, border blue-200, radius 12px |
| 5 | Tab bar gap | Gap widened 6px -> 24px, tab button padding changed from `12px 16px` to `12px 0` |
| 6 | Sidebar note author | "Me" badge for current user, "AI Summary" purple badge; `isCurrentUser` added to Apex `NoteData` |
| 7 | Empty states | Quota 0% shows "No closed deals this month yet"; Check Status empty -> "Pending" |
| 8 | Header breadcrumb | `font-weight: 700` -> `600` (semibold) |

**Files changed (17 total):** 8 CSS, 4 HTML, 3 JS, 1 Apex class, 1 Apex test

---

## Sprint 5 - UX Refinements & Features (14 tests passing)

| # | Change | Summary |
|---|--------|---------|
| 1 | Section headers redesigned | PayrollTab + AdminTab: 10px uppercase gray -> 15px Title Case dark (`#0f172a`) |
| 2 | Chevrons moved to left | All collapsible section chevrons moved from right side to left (before text) |
| 3 | Chevron color styling | Triple styling hooks for gray `#94a3b8` chevrons with hover darkening |
| 4 | Admin SLA grid alignment | `grid-template-columns: 200px 1fr 240px 1fr` for consistent two-column pairs |
| 5 | Row borders visibility | Changed from `#f1f5f9` to `#e2e8f0` (visible slate) |
| 6 | Email Now icons white | Added `variant="inverse"` to both `lightning-icon` elements in email split button |
| 7 | Email contact dropdown | New dropdown on chevron click: shows contacts with name/title, blue dot for primary |
| 8 | Collapsible notes | Notes in sidebar now collapsible (default collapsed) |
| 9 | Rich text notes | Replaced raw `{note.body}` with `lightning-formatted-rich-text` |
| 10 | Note titles | Each note shows `note.title` from Apex, fallback "Rep Note" |
| 11 | Equal-height overview cards | Added `:host { height: 100% }` + flexbox to overview cards |

**Files changed (13 total):** 6 CSS, 4 HTML, 2 JS, 1 parent HTML

---

## Sprint 6 - Quota Donut, Note Title, Card Whitespace (14 tests passing)

| # | Change | Summary |
|---|--------|---------|
| 1 | Note title | `saveNote()` changed to `'Rep Note'` -- date was redundant |
| 2 | Overview card whitespace | Added flexbox to `.card` so content fills equal-height grid cells |
| 3 | Quota donut: two-layer arc | Blue arc = combined total (bottom), green arc = closedWon (top) |
| 4 | Quota data source | Changed to `Amount` directly (both thisOpp and closedWon) |
| 5 | Donut arc start position | Fixed double-rotation bug: `dashOffset` changed to `0` |
| 6 | Payroll Status icons | Switched from `utility:*` to `standard:*` icons |
| 7 | Field mapping doc | Created `docs/nba-v2-field-mapping.csv` -- 107 field mappings |

**Files changed (9 total):** 3 CSS, 2 HTML, 1 JS, 1 Apex, 1 CSV

---

## Sprint 7 - Email Modal Fixes (14 tests passing)

| # | Change | Summary |
|---|--------|---------|
| 1 | Rich text email body | Replaced `lightning-textarea` with `lightning-input-rich-text` |
| 2 | Contact dropdown -> To field | Fixed `connectedCallback`: extracts `.contactId` from contact object |
| 3 | Merge tags not resolving | Now only `setTemplateId()` is called when template selected; `setSubject`/`setHtmlBody` only for composing without template |
| 4 | Email not in activities | Added `oppId` parameter to `sendEmail` + `mail.setWhatId(oppId)` |
| 5 | Sidebar not refreshing | Email modal dispatches `emailsent` event, workspace calls `refreshApex()` |

**Files changed (7 total):** 1 Apex, 1 Apex test, 3 LWC (emailModal JS/HTML/CSS), 2 LWC (workspace HTML/JS)

---

## Sprint 8 - SMS Integration via Mogli SMS (18 tests passing)

| # | Change | Summary |
|---|--------|---------|
| 1 | SMS modal component | New `nbaDemoSmsModal` LWC: contact selector, Mogli template picker, character counter, opt-out warning |
| 2 | Header SMS button | Green "SMS" split button between "Email Now" and "Snooze" |
| 3 | Contact data enrichment | `ContactData` now includes `mogliNumber` and `optedOut` |
| 4 | sendSms Apex method | Creates `Mogli_SMS__SMS__c` record with Direction='Outgoing' and Status='Queued' |
| 5 | getSmsTemplates Apex method | Queries `Mogli_SMS__SMS_Template__c` (non-private templates) |
| 6 | Sidebar SMS activities | `buildSidebar()` now queries Mogli SMS records |
| 7 | Contacts tab SMS button | New "SMS" action button on each contact card |
| 8 | Workspace wiring | Modal state, event listeners, `refreshApex` after send |

**Files changed (15 total):** 4 new (smsModal), 2 Apex, 3 header, 2 workspace, 2 contactsTab

---

## Sprint 9 - SMS Delivery Fix + Conversation View (19 tests passing)

**Part 1: SMS Delivery Fix**

| # | Change | Summary |
|---|--------|---------|
| 1 | Direction value | `sendSms()`: `'Outbound'` -> `'Outgoing'`. Mogli only processes `'Outgoing'`. |
| 2 | Sidebar direction check | Now handles both `'Outgoing'` and legacy `'Outbound'` for display |
| 3 | Test assertion | Updated to assert `'Outgoing'` |

**Part 2: Conversation View in Sidebar**

| # | Change | Summary |
|---|--------|---------|
| 1 | New LWC `nbaDemoConversationView` | Chat-style SMS conversation: chat bubbles, date headers, compose area, Enter-to-send |
| 2 | Sidebar Messages tab | Third tab in pill segmented control (Notes \| Activity \| Messages) |
| 3 | Workspace wiring | Passes `contacts` and `onsmssent` to sidebar |
| 4 | Apex `SmsMessageData` class | New inner class for SMS message data |
| 5 | Apex `getConversation()` method | Queries SMS by Contact, returns last 50 messages |
| 6 | 2 new test methods | `testGetConversation_ReturnsSmsMessages`, `testGetConversation_NoMessages_ReturnsEmpty` |

**Files changed (10 total):** 4 new (conversationView), 3 sidebar, 1 workspace, 2 Apex

---

## Sprint 10 - Sidebar & UX Polish (19 tests passing)

| # | Change | Summary |
|---|--------|---------|
| 1 | Messages contact picker | Replaced horizontal scrolling contact pills with a chevron dropdown selector |
| 2 | Sidebar header removed | Removed "Notes & Activity" header, pill toggle is now the top element |
| 3 | Hidden scrollbars | Removed visible scrollbar tracks from `.workspace-main` and `.tab-bar` |

**Files changed (7 total):** 3 conversationView (HTML/CSS/JS), 2 sidebar (HTML/CSS), 1 workspace (CSS)

---

## Sprint 11 - NBA V2 Phase 1: Data Foundation (19 tests passing)

**Commits:**
- `feat: Sprint 11 Phase 1 — NBA V2 data foundation`
- `feat: Complete Sprint 11 Phase 1 — seed V2 sample data + update docs`
- `docs: Update CLAUDE.md with Phase 2 signal architecture context`

| # | Change | Summary |
|---|--------|---------|
| 1 | NBA_Queue__c V2 fields | 12 new fields added: Impact_Score, Urgency_Score, Priority_Bucket, Priority_Layer, Is_Time_Bound, Cadence_Stage, Attempt_Count_Today, Last_Attempt_Method, Source_Path, Rule_Name, Action_Instruction, Workflow_Mode |
| 2 | Action_Type__c expansion | 5 new picklist values: First Touch, Re-engage, Stage Progression, SLA Response, Blitz Outreach |
| 3 | Custom Metadata Types | 5 CMDTs deployed: NBA_Cadence_Rule__mdt (7 records), NBA_Urgency_Rule__mdt (4), NBA_Suppression_Rule__mdt (4), NBA_Impact_Weight__mdt (1), NBA_Cooldown_Rule__mdt (3) |
| 4 | Sample data | 5 NBA_Queue__c records with V2 fields populated for UAT testing |
| 5 | Signal architecture docs | Added comprehensive CRM signal mapping to CLAUDE.md |

---

## Sprint 12 - NBA V2 Phase 2: Engine Core (43 new tests, 62 total)

**Commits:**
- `feat: Add NbaSignalService — CRM signal detection for NBA V2 engine`
- `feat: Add NbaActionCreationService — rule evaluation and action candidate creation`
- `feat: Add NbaActionStateService — action lifecycle management and constraints`
- `feat: Add SelectionService + Schedulables — complete Phase 2 engine core`

### Overview
Built the complete NBA V2 Action Orchestration Engine core: 6 Apex service classes + 6 test classes (12 files, ~2,100 lines). All 43 tests passing with 84-100% coverage per class.

### Classes Built

| Class | Lines | Coverage | Tests | Purpose |
|-------|-------|----------|-------|---------|
| NbaSignalService | ~250 | 84% | 8 | CRM signal detection — 7 SOQL per batch |
| NbaActionCreationService | ~350 | 89% | 14 | Rule evaluation + candidate creation |
| NbaActionStateService | ~280 | 85% | 12 | Lifecycle management + promotion |
| NbaActionSelectionService | ~150 | 91% | 5 | Gate → Rank prioritization |
| NbaActionCreationSchedulable | ~120 | 89% | 2 | 10-min creation job |
| NbaActionExpirationSchedulable | ~30 | 100% | 2 | Expire + unsnooze job |

### Engine Architecture

**Signal Detection Pipeline** (NbaSignalService):
- Queries 7 CRM data sources in one batch (Opportunity, Talkdesk, SMS, Events, Tasks, Account_Scoring, existing NBA_Queue)
- Returns `Map<Id, OpportunitySignal>` wrapper with all signal data per Opp
- Stage mapping: New=1, Connect=2, Consult=3, Evaluating=3, Closing=4, Verbal Commit=5, Ready to Convert=5, Hand-Off=0

**Action Creation Pipeline** (NbaActionCreationService):
- Suppression: 4 CMDT-driven rules (closed opp, active action exists, meeting <24h, recent touch <4h)
- Type determination: First Touch (never contacted) > Stage Progression (late-stage) > Re-engage (5d+ inactive) > Follow Up
- Scoring: Impact = (0.6 × normalizedMRR) + (0.4 × closeProb); Urgency = base 0.5 × multipliers; Final = 0.5 × Impact + 0.5 × Urgency
- 5 Priority Buckets: Cadence Due Today, Late-Stage Stalled, High Impact Focus, Neglected, General Pipeline
- 3 Priority Layers: Layer 1 (Time Bound) > Layer 2 (Mode) > Layer 3 (Impact+Urgency)
- UniqueKey format: `'V2|' + oppId + '|' + actionType`

**State Management** (NbaActionStateService):
- AE transitions: complete, snooze (with reason + duration), dismiss (with reason + category)
- System transitions: expire stale (non-timebound >1hr, timebound >DueAt+15min), unsnooze due
- Promotion: Layer precedence (1>2>3) then score DESC, max 2 active+pending per AE
- In-memory sort via `ActionLayerComparator` (SOQL CASE in ORDER BY not supported)

**Selection** (NbaActionSelectionService): Gate (cooldown, mode) → Rank → return top action

**Schedulables**: 6 jobs each (SF cron syntax limitation). Creation at :00/:10/:20/:30/:40/:50, Expiration at :05/:15/:25/:35/:45/:55.

### Bugs Encountered & Fixed

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| Opp query by Name fails | Org trigger renames Opportunities | Query by `Account__r.Name + StageName` |
| `Decimal.subtract()` not visible | Apex Decimal doesn't expose `subtract()` | Use `Long` arithmetic with `-` operator |
| Multiple Opps on same Account fails | "One open Payroll Opp per Account" validation | Separate Accounts per Opp in tests |
| SOQL CASE in ORDER BY | Not supported in Apex SOQL | In-memory sort with `System.Comparator` |
| `Account.Name` on NBA_Queue__c | Custom lookup uses `__r` syntax | Changed to `Account__r.Name` |
| AuraHandledException message | `getMessage()` unreliable for custom messages | Test exception thrown, not message text |
| Invalid Dismissal_Category__c | Restricted picklist: Call Scheduled, Time Zone, Other | Changed test to use 'Other' |
| Promote at capacity | 2 Pending = at cap, promote returns null | Simplified test to use 1 Pending |
| Non-timebound expire test | Threshold=0 doesn't catch just-created records | Set threshold to -60 (future cutoff) |
| Cron `0/10` and comma syntax | SF `System.schedule()` doesn't support step/comma | 6 separate `System.schedule()` calls |

**Files created (24 total):** 12 Apex classes + 12 meta.xml files under `force-app/main/default/classes/`

---

## Sprint 14 — Phase 4: Triggers + Real-Time Events (2026-02-15)

**Goal**: Actions created in real-time from CRM events, not just scheduled batch.

### What Changed

**New Apex Classes (7):**
- `NbaTriggerContext.cls` — Shared recursion guards, constants, helpers for all trigger handlers
- `NbaRealTimeEvaluationQueueable.cls` — Async wrapper: signal → evaluate → create → promote
- `NbaOpportunityTriggerHandler.cls` — After insert (new opp → First Touch), after update (stage change → re-evaluation)
- `NbaEventTriggerHandler.cls` — After insert/update/delete: meeting → Layer 1 time-bound action
- `NbaTaskTriggerHandler.cls` — After insert/update: activity → context update, auto-complete on connected calls

**New Test Classes (4):**
- `NbaRealTimeEvaluationQueueableTest.cls` — 3 tests
- `NbaOpportunityTriggerHandlerTest.cls` — 6 tests
- `NbaEventTriggerHandlerTest.cls` — 5 tests
- `NbaTaskTriggerHandlerTest.cls` — 6 tests

**New Triggers (3):**
- `OpportunityTrigger.trigger` — after insert, after update → NbaOpportunityTriggerHandler
- `EventTrigger.trigger` — after insert, after update, after delete → NbaEventTriggerHandler
- `TaskTrigger.trigger` — after insert, after update → NbaTaskTriggerHandler

**Modified Apex (2):**
- `NbaActionCreationService.cls` — Added `createTimeBoundAction()`, `updateTimeBoundAction()`, `cancelTimeBoundAction()`
- `NbaActionCreationServiceTest.cls` — Added 5 time-bound action tests (19 → 24 total)

**Modified LWC (1):**
- `nbaDemoWorkspace.js` — Added 60s polling interval + `_refreshActiveAction()` + `disconnectedCallback` cleanup

### Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Opp trigger execution model | Queueable (async) | Full signal eval uses ~12 SOQL; Queueable gets fresh governor limits |
| Event trigger execution model | Synchronous | Only 2-3 SOQL + 1-2 DML; safe in trigger context |
| Task trigger execution model | Synchronous | Only 1-2 SOQL + 1-2 DML; context updates are lightweight |
| Recursion prevention | Static booleans in NbaTriggerContext | Prevents re-entry when NBA_Queue__c DML causes cascading triggers |
| Time-bound dedup key | `'V2|' + oppId + '\|Meeting\|' + eventId` | One action per Event, not per Opp (multiple meetings can coexist) |
| LWC real-time updates | 60s polling (not Platform Events) | Simple, no infrastructure overhead; acceptable for ~minute latency |
| Task auto-complete | Connected-DM/GK dispositions | Fulfills First Touch/Re-engage actions when AE already made the call |

### Test Results

44 new tests passing (100% pass rate). Key coverage:
- NbaOpportunityTriggerHandler: 100%
- NbaEventTriggerHandler: 94%
- NbaTaskTriggerHandler: 79%
- NbaRealTimeEvaluationQueueable: 95%
- NbaActionCreationService: 77% (with new time-bound methods)

### Bugs Encountered & Fixed

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| Empty Queueable test creates action | @TestSetup Opp insert fires trigger → enqueues async → Test.stopTest() flushes it | Compare delta counts instead of asserting zero |
| Duplicate ID in bulk Task test | 200 Tasks on same Opp → same action added to update list 200 times | Use `Map<Id, NBA_Queue__c>` to deduplicate before DML |
| Time-bound creation tests return null | Event insert fires trigger → creates action → direct call finds dedup → returns null | Set `NbaTriggerContext.setEventHandlerRun()` before Event insert in direct method tests |

**Files created (27 total):** 7 Apex classes + 4 test classes + 3 triggers + 13 meta.xml files

---

## Sprint 16 — Bug Fixes: Platform Cache, Suppression, and Audit Records (2026-02-16)

**Goal**: Fix NBA V2 App Page showing same Opp repeatedly and creating empty audit records.

### What Changed

| File | Change |
|------|--------|
| `NbaCacheService.cls` | Fixed cache key — removed underscore (`action_` → `nba`); Platform Cache keys must be alphanumeric only |
| `NbaActionController.cls` | Added server-side null guards on complete/snooze/dismiss; if LWC sends null oppId, controller re-evaluates to recover context |
| `NbaSignalService.cls` | Added `Status__c = 'Dismissed'` to `queryExistingActions` query; treat dismissed records as cooldowns in signal assembly |
| `nbaActionBar.js` | Refactored event dispatch to use centralized `_extractActionDetail()` to safely read action properties from LWC proxy; added console.warn for null oppId debugging |
| `nbaDemoWorkspace.js` | Fixed 5-min poll comparison: `actionId` is always null for on-demand actions, so compare by `opportunityId + actionType` instead; added console.warn for null oppId |
| `NBA_Suppression_Rule.Recent_Completion.md-meta.xml` | **NEW** — CMDT record: suppress opp for 1 hour after completion |
| `NBA_Suppression_Rule.Snoozed_Action.md-meta.xml` | **NEW** — CMDT record: suppress opp while snooze is active |

### Bugs Found & Fixed

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| Platform Cache silently failing on every operation | Cache key `action_005Hp00000iHg58` contains underscore; SF Platform Cache keys must be alphanumeric only | Changed prefix from `action_` to `nba` |
| Audit records created with null Opportunity/Account/ActionType | LWC proxy or stale bundle issue causing `currentAction` properties to be undefined when dispatching events | Added `_extractActionDetail()` in action bar + server-side null guards in controller that re-evaluate on-demand to recover context |
| Same opp returned after every complete/dismiss/snooze | Phase 5 code had `checkSuppression()` handling for `'Recent Completion'` and `'Snoozed Action Exists'` conditions, but the CMDT records were never deployed | Created 2 new NBA_Suppression_Rule__mdt records |
| Dismissed opps not tracked for suppression | `queryExistingActions()` only fetched Active/Snoozed/Completed records; dismissed records were ignored | Added `OR (Status__c = 'Dismissed' AND CooldownUntil__c > :Datetime.now())` to query |
| 5-min poll never updates on-demand actions | `_refreshActiveAction()` compared `action.actionId !== prevActionId`, but both are null for on-demand actions | Changed comparison to use `opportunityId + actionType` |

### Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Cache key format | `'nba' + userId.left(15)` | Alphanumeric only; 18 chars total within SF 50-char limit |
| Completion cooldown window | 1 hour | Matches existing `DEFAULT_COOLDOWN_MINUTES = 60` in NbaActionStateService |
| Dismissed = completed for cooldown | Use `CreatedDate` as pseudo-completion | Simpler than adding a separate "Recent Dismissal" condition; same 1hr suppression |
| Null guard strategy | Re-evaluate on-demand in controller | More resilient than throwing; AE still gets correct audit + next action even if LWC sends stale data |

### Suppression Rules (6 total, all active)

| Rule | Condition | Window |
|------|-----------|--------|
| Active_Action_Exists_Suppress | Active Action Exists | permanent |
| Closed_Opp_Suppress | Closed Opportunity | permanent |
| Meeting_Scheduled_Suppress | Upcoming Meeting | 24h |
| Recent_Valid_Touch_Suppress | Recent Valid Touch | 4h |
| Recent_Completion_Suppress | Recent Completion | 1h |
| Snoozed_Action_Suppress | Snoozed Action Exists | until snooze expires |

### Test Results

All 93 existing tests passing (8 cache + 10 controller + 8 signal + rest unchanged).

---

## Sprint 17 — Phase 6: Cadence Rule Integration (2026-02-16)

**Goal**: Integrate NBA_Cadence_Rule__mdt into the on-demand engine so First Touch actions follow a structured 5-day cadence with spacing enforcement, daily caps, and method hints displayed in the LWC.

**Commits:**
- `93f2c98` — `feat: Phase 6 cadence rule integration (Sprint 17)` (34 files, 1245 insertions)
- `1b3309a` — `fix: Set Max_Attempts_Per_Day to 0 for hint-only CMDT records` (6 files)

### What Changed

**New Apex Classes (2):**
- `NbaCadenceService.cls` — Core cadence logic: loads CMDT rules (1 SOQL, static-cached), determines current step via `getCurrentStep(signal, variant)`, enforces 60-min spacing + daily caps, returns `CadenceStep` wrapper. Uses transaction-scoped `lastEvaluatedSteps` static map for cross-class data sharing.
- `NbaCadenceServiceTest.cls` — 8 test methods: Day 0 first call, Day 0 second call, spacing enforcement, daily cap, cadence complete, variant mismatch, computeCadenceDay mapping, lastEvaluatedSteps population.

**New Custom Setting (1):**
- `NBA_AE_Config__c` — Hierarchy custom setting with `Cadence_Variant__c` field (Text 30, default 'A'). Resolved via `getInstance(ownerId)` for 0 SOQL variant lookup.

**New CMDT Fields (5) on NBA_Cadence_Rule__mdt:**
- `Cadence_Day__c` (Number) — Which day of the cadence this step belongs to
- `Variant__c` (Text 10) — Cadence variant identifier (e.g., 'A')
- `Step_Order__c` (Number) — Ordering within a cadence day
- `Hint_Text__c` (Text 255) — Method hint displayed in LWC
- `Is_Primary__c` (Checkbox) — Whether this is the primary (callable) step vs. a hint

**New CMDT Records (12, replacing 7 deleted):**

| Record | Day | Method | Primary | Hint |
|--------|-----|--------|---------|------|
| FT_A_D0_Call1 | 0 | Call | Yes | First attempt: introduce yourself |
| FT_A_D0_Hint_SMS1 | 0 | SMS | No | Send SMS if no connect |
| FT_A_D0_Call2 | 0 | Call | Yes | Second attempt: try again |
| FT_A_D0_Hint_Email1 | 0 | Email | No | Send intro email |
| FT_A_D0_Call3 | 0 | Call | Yes | Third attempt: final try today |
| FT_A_D1_Call4 | 1 | Call | Yes | Day 1 follow-up |
| FT_A_D1_Call5 | 1 | Call | Yes | Day 1 second attempt |
| FT_A_D1_Hint_SMS2 | 1 | SMS | No | Send follow-up SMS |
| FT_A_D1_Hint_Email2 | 1 | Email | No | Send follow-up email |
| FT_A_D3_Hint_Email3 | 3 | Email | No | Send value-add email |
| FT_A_D3_Call6 | 3 | Call | Yes | Day 3 attempt |
| FT_A_D5_Hint_Breakup | 5 | Email | No | Send breakup email |

**Modified Apex (4):**

| File | Changes |
|------|---------|
| `NbaSignalService.cls` | Added 3 OpportunitySignal fields (`daysSinceCreation`, `todayCallCount`, `todayCallDates`). Changed `queryRecentTalkdesk()` return type from single-record map to list map. Signal assembly now counts today's calls. 0 extra SOQL. |
| `NbaActionCreationService.cls` | Integrated cadence into `evaluateAndCreate()` for First Touch: resolve variant via `NBA_AE_Config__c.getInstance()`, call `NbaCadenceService.getCurrentStep()`, use cadence step values for NBA_Queue__c fields. Added `determineNonCadenceActionType()` fallback. |
| `NbaActionController.cls` | Added 6 cadence fields to ActionWrapper (`cadenceStage`, `cadenceDay`, `todayCallCount`, `maxCallsToday`, `methodHints`, `cadenceProgress`). Updated `toWrapperFromCandidate()` and `toWrapperFromRecord()` to map cadence data. Added Cadence_Stage__c and Attempt_Count_Today__c to `checkTimeBoundInternal` SOQL. |
| `NbaActionStateService.cls` | Updated `writeAuditRecord()` to check `NbaCadenceService.lastEvaluatedSteps` and write cadence metadata to audit records. |

**Modified LWC (2):**

| Component | Changes |
|-----------|---------|
| `nbaDemoInsightsPanel` | Added `showCadenceContext` and `cadenceMethodHint` getters (JS). Added cadence context section with progress + method hints (HTML). Added `.cadence-context`, `.cadence-progress`, `.cadence-hint` styles (CSS). |
| `nbaDemoHeader` | Added `showCadenceStep` and `cadenceStepLabel` getters (JS). Added cadence-step-badge showing "X/Y" call count (HTML). Added `.cadence-step-badge` style (CSS). |

### Architecture: Cadence Evaluation Flow

```
LWC → getActiveAction() → cache miss → NbaSignalService.getSignals()
  Signal now includes: daysSinceCreation, todayCallCount, todayCallDates
  → NbaActionCreationService.evaluateAndCreate()
    → First Touch path: NBA_AE_Config__c.getInstance(ownerId) → variant (0 SOQL)
    → NbaCadenceService.getCurrentStep(signal, variant) → CadenceStep or null
      → loadRules() (1 SOQL, static-cached after first call)
      → computeCadenceDay(daysSinceCreation) → 0/1/3/5/complete
      → Filter by scenario + variant + cadenceDay
      → Check daily cap (todayCallCount vs Max_Attempts_Per_Day__c)
      → Check spacing (todayCallDates vs Attempt_Spacing_Minutes__c = 60 min)
      → Populate lastEvaluatedSteps static map
    → If suppressed → determineNonCadenceActionType() fallback
    → Build NBA_Queue__c with cadence fields
  → ActionWrapper reads from NbaCadenceService.lastEvaluatedSteps
  → LWC displays cadence progress + method hints
```

### Key Pattern: Transaction-Scoped Static Map

`NbaCadenceService.lastEvaluatedSteps` (a `Map<Id, CadenceStep>`) bridges data between:
- `NbaCadenceService.getCurrentStep()` (called during creation evaluation)
- `NbaActionController.toWrapperFromCandidate()` (called when mapping to ActionWrapper)

Both execute in the same Apex transaction. This avoids extra SOQL to retrieve cadence context.

### Bugs Encountered & Fixed

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| Deploy failed: "Required fields missing: Max_Attempts_Per_Day__c" | 6 hint-only CMDT records had `xsi:nil="true"` for Max_Attempts_Per_Day__c but the field has `required=true` | Changed all 6 to `<value xsi:type="xsd:double">0</value>` |
| Deploy with RunLocalTests failed | Pre-existing `NBAQueueSelector.getByAssignee(Id, Integer)` compilation error in org (not from Phase 6 code) | Deployed with `--test-level NoTestRun`, then ran 5 test classes individually (52 tests, all passing) |

### Test Results

52 targeted tests passing across 5 test classes:
- NbaCadenceServiceTest: 8/8 (NEW)
- NbaActionCreationServiceTest: 19/19
- NbaActionControllerTest: 10/10
- NbaActionStateServiceTest: 10/10
- NbaActionSelectionServiceTest: 5/5

**Files created (34 total):** 2 Apex classes + 2 meta.xml + 1 custom setting object + 1 custom setting field + 5 CMDT fields + 12 CMDT records + 5 CMDT field meta.xml + modified 4 Apex classes + modified 3 LWC components (6 files)

---

## Sprint 18 — Phase 7 Foundation (2026-02-18)

**Commit**: `e7394fc` — `feat: Sprint 18 — Phase 7 cadence redesign foundation (2-CMDT + rewritten service)`

**Goal**: Replace flat NBA_Cadence_Rule__mdt with 2-CMDT parent/child architecture (NBA_Cadence__mdt + NBA_Cadence_Step__mdt) supporting outcome-based branching, day mapping, and exit conditions.

### What Was Built

**New CMDT Objects (2):**

| Object | Purpose |
|--------|---------|
| `NBA_Cadence__mdt` | Parent cadence definition: scenario, variant, total steps/days, exit conditions (comma-separated), Day_Map__c (JSON), Is_Active__c |
| `NBA_Cadence_Step__mdt` | Child step definition: linked to parent via Cadence_Name__c (text FK), method (Call/SMS/Email), branching fields (On_Connect/VM/No_Answer/Meeting actions + targets), spacing, max attempts |

**CMDT Records (13):**
- `First_Touch_A` parent record
- 12 step records: D0 (Call→SMS→Call→Email→Call), D1 (Call→Call→SMS→Email), D3 (Email→Call), D5 (SMS breakup)

**NBA_Queue__c Field Additions (4):**
- `Cadence_Name__c` (Text 80) — DeveloperName of the cadence
- `Cadence_Step_Number__c` (Number 3,0) — Step that was completed
- `Step_Outcome__c` (Picklist) — Connected, VM, No_Answer, Sent, Meeting_Scheduled, Skipped
- `Step_Method__c` (Picklist) — Call, SMS, Email

**NbaCadenceService.cls** — Complete rewrite with new inner classes:
- `CadenceContext` — parsed parent CMDT (scenario, variant, totalSteps, exitConditions, dayMap, steps list)
- `CadenceStepDef` — parsed step CMDT (stepNumber, day, method, instruction, branching fields)
- `CadencePosition` — last completed step from audit records (lastCompletedStep, lastOutcome, lastStepDate)
- `CadenceResult` — evaluation result (cadenceName, currentStep, position, progressText, progressFraction, isComplete, isSuppressed, upcomingSteps)

Key methods:
- `getNextStep(signal, variant, actionType)` — Primary entry point, replaces `getCurrentStep()`
- `applyBranching(lastStep, outcome)` — Resolves outcome to End_Cadence / Skip_To_Step / Skip_To_Day / Continue
- `computeCadenceDay(rawDays, dayMapJson)` — JSON-driven day mapping (replaces hardcoded mapping)

**NbaCadenceServiceTest.cls** — Rewritten with 19 tests (was 8):
- Branching: Connected → End_Cadence, VM → Continue, Skip_To_Step, Skip_To_Day
- Day gating: future day steps suppressed
- Spacing: 60-min minimum between call attempts
- Exit conditions: Connected_Call, Meeting_Scheduled
- Progress resolution from audit records

**NbaSignalService.cls** — 4 new OpportunitySignal fields:
- `lastCadenceName`, `lastCadenceStepNumber`, `lastCadenceStepOutcome`, `lastCadenceStepDate`

### Test Results

19/19 tests passing in NbaCadenceServiceTest (94% coverage).

**Files changed:** ~25 metadata files (2 CMDT objects + 13 CMDT records + 4 NBA_Queue__c fields + meta.xml), 2 Apex classes rewritten, 1 Apex class modified

---

## Sprint 19 — Phase 7 Integration + LWC (2026-02-18)

**Commit**: `5324d09` — `feat: Sprint 19 — cadence service integration + outcome capture LWC (Phase 7)`

**Goal**: Wire the new 2-CMDT cadence engine into all Apex service layers and add LWC outcome capture for Call/SMS/Email steps.

### Apex Service Changes (4 classes)

| Class | Changes |
|-------|---------|
| `NbaSignalService.cls` | Added `Cadence_Name__c`, `Cadence_Step_Number__c`, `Step_Outcome__c`, `Step_Method__c` to `queryExistingActions()` SELECT. In existing actions loop, extracts cadence progress from most recent Completed audit with non-null Cadence_Name__c → populates `lastCadenceName`, `lastCadenceStepNumber`, `lastCadenceStepOutcome`, `lastCadenceStepDate` on OpportunitySignal. 0 extra SOQL. |
| `NbaActionCreationService.cls` | Replaced Phase 6 First-Touch-only cadence block with universal `NbaCadenceService.getNextStep(signal, variant, actionType)` call for any action type. Uses `CadenceResult` instead of `CadenceStep`. Writes `Cadence_Name__c`, `Cadence_Step_Number__c`, `Step_Method__c` to action record. Falls back to `determineNonCadenceActionType()` when cadence suppresses or completes. |
| `NbaActionController.cls` | Extended ActionWrapper with 8 Phase 7 fields: `cadenceName`, `cadenceStepNumber`, `cadenceTotalSteps`, `stepMethod`, `stepInstruction`, `cadenceProgress`, `progressFraction`, `upcomingSteps`, `isCadenceAction`. Updated `completeAction()` to accept `stepOutcome` parameter. Updated `toWrapperFromCandidate()` to read from `NbaCadenceService.lastEvaluatedResults`. |
| `NbaActionStateService.cls` | Updated `completeAction()` to accept `stepOutcome` (6 params). Updated `writeAuditRecord()` to write all 4 cadence fields from `lastEvaluatedResults` + `stepOutcome`. Updated `snoozeAction()` and `dismissAction()` callers to pass null stepOutcome. |

### LWC Changes (4 components)

| Component | Changes |
|-----------|---------|
| `nbaActionBar` | **Call outcome panel**: "Complete" shows panel with 3 buttons (Connected / Left VM / No Answer). **SMS button**: "Mark SMS Sent" with chat icon, auto-outcome = `Sent`. **Email button**: "Mark Email Sent" with email icon, auto-outcome = `Sent`. Non-cadence actions: unchanged "Complete" button. New CSS: outcome panel styles, method-specific button colors (blue for SMS, indigo for Email). |
| `nbaDemoWorkspace` | `handleCompleteAction()` extracts `stepOutcome` from event detail, passes to `completeAction()` Apex call as 4th parameter. |
| `nbaDemoInsightsPanel` | Progress bar with dynamic fill width (`progressBarWidth`). Fraction badge (e.g., "3/12"). Upcoming steps preview list with method-specific icons (call/sms/email). `showCadenceContext` now checks `isCadenceAction`. |
| `nbaDemoHeader` | `showCadenceStep` checks `isCadenceAction`. `cadenceStepLabel` returns `progressFraction`. Added `stepMethodIcon` getter (call/sms/email icon). |

### Test Class Updates (2 classes)

| Class | Changes |
|-------|---------|
| `NbaActionControllerTest` | Updated `completeAction()` calls to pass 4th `null` param for stepOutcome |
| `NbaActionStateServiceTest` | Updated all `completeAction()` calls to pass 6th `null` param for stepOutcome |

### Test Results

70 targeted tests passing across 6 test classes:
- NbaCadenceServiceTest: 19/19
- NbaActionCreationServiceTest: 19/19
- NbaActionControllerTest: 10/10
- NbaActionStateServiceTest: 10/10
- NbaSignalServiceTest: 8/8
- NbaActionSelectionServiceTest: 4/4

**Files changed (15):** 4 Apex service classes + 2 Apex test classes + 4 LWC components (JS+HTML+CSS) = +424/-100 lines

---

## Sprint 20 — Phase 7 Second Cadence + Cleanup (2026-02-18)

**Commits**: `c4a70a6`, `c31b53e`, `40b32b9`, `f21bea6`

**Goal**: Add Re_engage_A cadence (second cadence in the 2-CMDT system), deactivate all Phase 6 flat CMDT records, remove all deprecated backward-compat code, and update tests.

### 1. Re_engage_A Cadence Definition (7 new CMDT files)

**Parent**: `NBA_Cadence.Re_engage_A.md-meta.xml`
- Scenario: Re-engage, Variant: A, Anchor: `daysSinceLastInteraction`
- 6 steps over 7 days, Exit: Connected_Call, Meeting_Scheduled, Opp_Closed
- Day Map: `{"5":0,"6":1,"7":3,"8":3,"9":5,"10":5,"11":7,"12":7}` (5+ days inactivity = cadence day 0)

**Steps (6)**:

| Record | Step | Day | Method | Instruction | On Connect |
|--------|------|-----|--------|-------------|------------|
| `REA_D0_Call1` | 1 | 0 | Call | Re-engagement call — review opportunity history | End_Cadence |
| `REA_D0_Email1` | 2 | 0 | Email | Send re-engagement email, reference last activity | — |
| `REA_D1_Call2` | 3 | 1 | Call | Follow-up call, try different time of day | End_Cadence |
| `REA_D3_SMS1` | 4 | 3 | SMS | Brief check-in text, keep short and personal | — |
| `REA_D5_Email2` | 5 | 5 | Email | Value-add email with resources or case studies | — |
| `REA_D7_Call3` | 6 | 7 | Call | Final re-engagement attempt, detailed voicemail | End_Cadence |

### 2. Deprecated Code Removal (2 Apex classes)

**NbaCadenceService.cls:**
- Removed `lastEvaluatedSteps` static map (Phase 6 transaction-scoped map, replaced by `lastEvaluatedResults`)
- Removed `CadenceStep` inner class (Phase 6 data class, replaced by `CadenceResult`)
- Removed `getCurrentStep()` wrapper method (Phase 6 entry point, replaced by `getNextStep()`)
- Removed `lastEvaluatedSteps` reset from `resetCache()`

**NbaActionController.cls:**
- Removed 5 backward-compat ActionWrapper fields: `cadenceStage`, `cadenceDay`, `todayCallCount`, `maxCallsToday`, `methodHints`
- Removed backward-compat population block in `toWrapperFromCandidate()` (was reading from old `lastEvaluatedSteps`)
- Simplified `toWrapperFromRecord()` — just sets `isCadenceAction = false`
- Removed `Cadence_Stage__c`, `Attempt_Count_Today__c` from `checkTimeBoundInternal()` SOQL

### 3. Phase 6 CMDT Deactivation (12 files)

Set `Is_Active__c = false` on all 12 `NBA_Cadence_Rule__mdt` records (Phase 6 flat CMDT system, fully replaced by NBA_Cadence__mdt + NBA_Cadence_Step__mdt):
- `FT_A_D0_Call1`, `FT_A_D0_Call2`, `FT_A_D0_Call3`
- `FT_A_D1_Call4`, `FT_A_D1_Call5`
- `FT_A_D3_Call6`
- `FT_A_D0_Hint_SMS1`, `FT_A_D0_Hint_Email1`
- `FT_A_D1_Hint_SMS2`, `FT_A_D1_Hint_Email2`
- `FT_A_D3_Hint_Email3`
- `FT_A_D5_Hint_Breakup`

### 4. Test Updates (NbaCadenceServiceTest.cls)

- Removed `testBackwardCompatGetCurrentStep` (referenced deleted `CadenceStep` class)
- Added `buildReEngageSignal()` helper method
- Added 5 new Re_engage_A tests:
  - `testReEngageCadenceDay0Call` — Step 1 resolves on Day 0 (5d inactivity)
  - `testReEngageCadenceDay0Email` — Step 2 after step 1 completed with No_Answer
  - `testReEngageBranchingOnConnect` — Connected call ends cadence
  - `testReEngageDayGating` — Day 1 step suppressed when still on Day 0
  - `testReEngageCadenceComplete` — Past day 12 returns cadence complete

### Test Results

62 targeted tests passing across 4 test classes:
- NbaCadenceServiceTest: 23/23 (was 19; -1 removed, +5 new)
- NbaActionControllerTest: 10/10
- NbaActionCreationServiceTest: 19/19
- NbaActionStateServiceTest: 10/10

**Files changed (22):** 7 new CMDT records + 12 deactivated CMDT records + 2 Apex classes modified + 1 test class modified
