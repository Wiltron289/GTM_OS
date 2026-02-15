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
