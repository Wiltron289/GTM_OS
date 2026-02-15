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
