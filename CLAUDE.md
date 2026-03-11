# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Detailed Documentation

Sprint-by-sprint change logs, architecture details, and resolved bugs live in separate files to keep this file lean:

- **`docs/architecture.md`** -- Component tree, data flow, design tokens, Mogli SMS architecture, reusable patterns
- **`docs/sprint-history.md`** -- Detailed sprint logs (Sprints 2-22), commit history, files changed per sprint
- **`docs/troubleshooting.md`** -- All resolved bugs with root causes, fixes, and prevention notes
- **`docs/nba-v2-field-mapping.csv`** -- 107 field mappings across all 13 visual sections
- **`docs/nba-v2-phase-plan.md`** -- Full implementation plan for NBA V2 Action Orchestration Engine (Phases 1-5). Covers NBA_Queue__c data model, Custom Metadata rule framework, 3-engine architecture (Creation, State, Selection), Demo LWC refactor, App Page setup, and phased sprint plan.
- **`docs/nba-v2-phase6-cadence-plan.md`** -- Phase 6 cadence integration plan (IMPLEMENTED in Sprint 17, superseded by Phase 7). Covers First Touch cadence (5-Day Variant A), CMDT redesign (12 step-sequence records), NbaCadenceService, signal enrichment, spacing enforcement, ActionWrapper extension, LWC display updates, and NBA_AE_Config__c variant assignment.
- **`.claude/plans/jiggly-inventing-candle.md`** -- Phase 7 NBA Cadence Redesign plan (COMPLETE — Sprints 18-20). Covers 2-CMDT parent/child architecture (NBA_Cadence__mdt + NBA_Cadence_Step__mdt), outcome-based branching, universal cadence support, LWC outcome capture panel.

Read these when needed (debugging, building new features, understanding history). Don't load them every session.

## Working Rules

**IMPORTANT**: All Claude agents must follow these rules:

### 1. Git Version Control
- Make frequent, atomic commits with detailed, descriptive commit messages
- Each commit should clearly explain **what** changed and **why**

### 2. Keep Documentation Updated
When developing features or debugging, update the appropriate doc file:
- **`CLAUDE.md`**: Working rules, current project state, essential commands
- **`docs/architecture.md`**: New patterns, component changes, integration points
- **`docs/sprint-history.md`**: Sprint change logs with files changed
- **`docs/troubleshooting.md`**: Bugs encountered with root cause, fix, and prevention

### 3. Deployment Target
- **Primary org**: vscodeOrg (lwilson@joinhomebase.com.uat, Homebase UAT sandbox)
- Deploy with `sf project deploy start` to the default org
- Verify org context with `sf org display` before deploying

### 4. Local Dev for LWC Development
- **Always start Local Dev** at the beginning of any session involving LWC CSS, HTML, or JS changes
- **Command**: `sf lightning dev app --target-org lwilson@joinhomebase.com.uat --device-type desktop --name "GTM OS"`
- CSS/HTML/JS changes appear in ~1-2 seconds on save -- no deploy needed
- **Still needs deploy**: Apex changes, new `@api` properties, `@wire` signature changes, `.js-meta.xml` changes
- **Port**: 8081. If `EADDRINUSE`: `netstat -ano | findstr ":8081"` then `taskkill //PID <pid> //F`

### 5. Context Management
- Before restarting conversations, update docs with current state, decisions, and next steps
- New agents should read CLAUDE.md first, then relevant docs as needed

### 6. Salesforce Metadata via MCP
- MCP Server configured in `.mcp.json` (toolsets: metadata, data, orgs, users)
- **Before writing SFDC code**: Query object metadata to verify field API names, picklist values, validation rules, relationships
- Especially important before creating test classes or referencing managed package fields

## Current Project State

**Last Updated**: 2026-03-10

| Item | Value |
|------|-------|
| **Active Branch** | `testing/sprint-22-20260303` (local changes pending: owner-reassignment interrupt, repo merge) |
| **Deployment Target** | vscodeOrg (Homebase UAT sandbox) + nbav2 (dev sandbox) |
| **Apex Tests** | 271 targeted tests passing (100%) across 22 test classes. All GTM OS classes ≥75% coverage. |
| **Current Phase** | **Post-Call Intelligence Panel — COMPLETE (6 sessions)** |
| **Phase Plan** | `docs/POST-CALL-INTELLIGENCE-PLAN.md` (6 sessions). |
| **Previous Phase** | PRD v2.2 Refactor — ALL 14 SESSIONS COMPLETE. `docs/REFACTOR-SESSION-PLAN.md`. |
| **PRD** | `/Users/lwilson/Downloads/PRD-GTM-OS-MVP.md` — PRD v2.0, 92% coverage verified 2026-03-10 |
| **GitHub** | https://github.com/Wiltron289/GTM_OS |
| **Related Repo** | SalesforceAICallNotes — **MERGED INTO THIS REPO** (2026-03-10). AI call notes REST endpoint + Talkdesk qualification parsing. |

## Engine Architecture (PRD-Aligned)

GTM OS uses a 3-engine architecture per PRD v2.0. **Do not confuse with the older Impact×Urgency model** — the engine was rewritten in the PRD v2 refactor (14 sessions).

### Three-Engine Model

```
Engine 1: ELIGIBILITY — "What work is logically required?"
  Cadence rules, suppression, timezone gates, timing
  → Logical Candidate Pool (in-memory, not persisted)

Engine 2: SELECTION — "Which work is most valuable right now?"
  Time-bound override → Timezone gate → Stage priority → Expected Incremental ARR
  → Single top-ranked candidate

Engine 3: RECORD CREATION & SERVING — "What must be shown to the AE?"
  Persist to NBA_Queue__c, cache in Platform Cache, serve via LWC
```

### Selection Hierarchy (PRD Section 8.2)

```
Step 1: Time-Bound Override — meetings, SLAs, follow-ups (ordered by deadline proximity)
Step 2: Timezone Gate — filter contacts where local time < 8 AM (via Account.Timezone_Router__c)
Step 3: Stage Priority — HARD boundary: Closing(1) > Consult(2) > Connect(3) > New(4)
Step 4: Expected Incremental ARR — highest economic value within same stage bucket
Step 5: Tiebreaker — oldest Opportunity CreatedDate
```

**No urgency blending. No Impact×Urgency. Stage priority is a hard boundary** — a Closing $20K deal always beats a New $100K deal.

### Expected Incremental ARR Formula (PRD Section 8.3)

```
Expected_ARR = Likelihood_To_Win × Incremental_If_Won × Meaningful_Connect_Rate(attempt_i)
```

- **Likelihood_To_Win**: `Account_Scoring__c.Prob_Payroll_Conversion__c` (fallback: stage-based: New=10%, Connect=25%, Consult=50%, Closing=75%)
- **Incremental_If_Won**: `Account_Scoring__c.Incremental_If_Won__c` (fallback: `Opp.MRR__c` or `Opp.Amount`)
- **Connect_Rate**: `NBA_Connect_Rate__mdt` per attempt number (decreasing: 0.13, 0.10, 0.08, 0.06, 0.05, 0.04)

### Two-Stream Serving

| Stream | Purpose | Frequency | Cost |
|--------|---------|-----------|------|
| Scored Queue | Full evaluation: Eligibility → Selection → Serve top action | 5 min (Platform Cache TTL) | ~12 SOQL (cache miss) |
| Real-Time Interrupts | Time-bound commitments + new assignments | 15 seconds | 2 SOQL |

### Stage-Scoped Cadences (5 deployed)

| Stage | Cadence | Trigger | Touches |
|-------|---------|---------|:-------:|
| New | First_Touch_A | Opp created (SLA 5 min) | 12 (6C, 3S, 3E) |
| Connect | Post_Demo_Connect_A | Missed follow-up meeting | 7 (3C, 1S, 2E, 1 recap) |
| Consult | Post_Demo_Consult_A | Missed follow-up meeting | 8 (3C, 2S, 2E, 1 recap) |
| Closing | Closing_Follow_Through_A | Follow-up Task date passes | 7 (2C, 2S, 2E, 1 recap) |
| Any | Re_engage_A | 5+ days inactivity | 6 (3C, 1S, 2E) |

Stage change resets cadence to Step 1 of the new stage. MCR attempt counter also resets.

### PRD Gap Analysis (2026-03-10)

| Gap | PRD Section | Severity | Status |
|-----|------------|----------|--------|
| Hand-Off stage suppression | 7.4, 7.8 | P1 | Missing — add check in NbaActionCreationService |
| SLA expiration window | 13.3 | P1 | PRD=5min, code=15min — verify and align |
| Incremental_If_Won__c field | 8.4 | P2 | Verify DS pipeline populates this field |
| Starvation report/dashboard | 18.1 | P2 | Fields exist, report type + dashboard not created |
| Action metrics collection | 18.2 | P3 | Not implemented |

### What Exists

- **Feature 1**: Account Scoring Data Layer -- `Account_Scoring__c` custom object + permission sets (deployed)
- **Feature 2**: NBA V2 Demo LWC -- 20 LWC components (18 original + nbaEmptyState + nbaActionBar), 2 Apex controllers (NbaDemoController + NbaActionController), 2 FlexiPages (Record Page + App Page). Deployed through Sprint 13.
- **Feature 3**: NBA_Queue__c -- 108-field custom object deployed to UAT (96 original + 12 V2 fields: Impact_Score, Urgency_Score, Priority_Bucket, Priority_Layer, Is_Time_Bound, Cadence_Stage, Attempt_Count_Today, Last_Attempt_Method, Source_Path, Rule_Name, Action_Instruction, Workflow_Mode). Action_Type__c updated with 5 new values (First Touch, Re-engage, Stage Progression, SLA Response, Blitz Outreach).
- **Feature 4**: 5 Custom Metadata Types for NBA V2 rule engine -- NBA_Cadence_Rule__mdt (12 records — **deactivated in Sprint 20**, superseded by 2-CMDT architecture), NBA_Urgency_Rule__mdt (4 records), NBA_Suppression_Rule__mdt (6 records — added Recent_Completion + Snoozed_Action in Sprint 16), NBA_Impact_Weight__mdt (1 record), NBA_Cooldown_Rule__mdt (3 records). All deployed to UAT.
- **Feature 5**: 5 sample NBA_Queue__c records with V2 fields populated (First Touch/Time-Bound, Re-engage, Stage Progression, Snoozed, Blitz Outreach)
- **Feature 6**: NBA V2 Engine Core (Phase 2) -- 6 Apex service classes + 6 test classes, all deployed to UAT. See details below.
- **Feature 7**: NBA V2 Triggers (Phase 4) -- 3 triggers (Opportunity, Event, Task) + 3 handler classes + 1 utility class + 4 test classes. All deployed to UAT.
- **Feature 8**: NBA V2 On-Demand Engine (Phase 5) -- NbaCacheService (Platform Cache), rewritten NbaActionController (on-demand evaluation), simplified NbaActionStateService (audit writer), LWC dual polling (15s/5min), cache invalidation in all triggers. Schedulables archived, Queueable no-op'd. NBA_Queue_AE permission set. All deployed to UAT (93/93 tests passing).
- **Feature 9**: NBA V2 Cadence Integration (Phase 6) -- NbaCadenceService (cadence step resolution, spacing enforcement, daily caps), NBA_AE_Config__c hierarchy custom setting (variant assignment), 5 new CMDT fields + 12 redesigned cadence records (First Touch Variant A, 5-day cadence), signal enrichment (todayCallCount, daysSinceCreation), ActionWrapper cadence fields, LWC cadence display (progress + method hints). All deployed to UAT. **Superseded by Phase 7.**
- **Feature 10**: NBA V2 Cadence Redesign — Sprint 18 Foundation (Phase 7) -- 2-CMDT parent/child architecture (NBA_Cadence__mdt parent + NBA_Cadence_Step__mdt child with outcome branching). NbaCadenceService complete rewrite (CadenceContext, CadenceStepDef, CadencePosition, CadenceResult classes; getNextStep(), applyBranching(), computeCadenceDay()). 4 new NBA_Queue__c fields (Cadence_Name__c, Cadence_Step_Number__c, Step_Outcome__c, Step_Method__c). 4 cadence progress fields on OpportunitySignal. 19 tests in rewritten NbaCadenceServiceTest. All deployed to UAT.
- **Feature 11**: NBA V2 Cadence Redesign — Sprint 19 Integration + LWC (Phase 7) -- Universal cadence wired into all service layers: NbaSignalService (cadence progress extraction from audit records), NbaActionCreationService (universal cadence for any action type), NbaActionController (8 new ActionWrapper fields, stepOutcome parameter), NbaActionStateService (4-field cadence audit writing). LWC: nbaActionBar outcome capture panel (Connected/Left VM/No Answer for Call steps, auto-Sent for SMS/Email), nbaDemoInsightsPanel progress bar + upcoming steps, nbaDemoHeader method icon badge. 70 targeted tests passing. All deployed to UAT.
- **Feature 12**: Two-Stream Architecture — Sprint 21 (COMPLETE) -- Split action delivery into two independent streams: Stream 1 (Scored Queue) = getActiveAction() on-demand evaluation only (removed L1 DB check); Stream 2 (Real-Time Interrupts) = checkInterrupts() 15s poll for meetings within 5 min + new-assignment L1 records. LWC: indigo interrupt banner with "Jump to it"/"Later", _pausedAction state for resume after interrupt. NbaActionCreationService.createNewAssignmentActions() bulk method for trigger-based interrupt creation. NbaActionStateService expireStaleActions() extended for non-time-bound L1 expiry. nbaEventDetails LWC for Meeting action context (LDS getRecord, 0 SOQL). Amber banner suppressed for Meeting actions. All deployed to UAT.
- **Feature 13**: GTM OS Rebrand — Sprint 22 -- Renamed all user-facing "NBA v2" labels to "GTM OS" across 23 files (FlexiPages, LWC, custom objects, CMDTs, permission sets, schedulable job names). API names unchanged (NBA_Queue__c etc. are immutable). All deployed to UAT.
- **Feature 14**: Engine Hardening — Sprint 22 -- 4 fixes from code audit: (1) ORDER BY Amount DESC NULLS LAST on 200-opp query prevents non-deterministic truncation, (2) removed dead cooldown code from NbaActionSelectionService (saves 1 SOQL), (3) fixed MRR normalization to use fixed $50K ceiling instead of batch-relative max, (4) try/catch on Talkdesk/Mogli SOQL for graceful degradation. +3 new tests.
- **Feature 15**: Post-Call Notes Capture — Sprint 22 (COMPLETE) -- Talkdesk Activity trigger detects completed calls, publishes Call_Completed_Event__e Platform Event. LWC subscribes via empApi, presents nbaCallNoteCapture overlay with pre-populated notes, disposition, talk time. AE saves edited notes as ContentNote linked to Opp. NbaTalkdeskActivityTrigger + handler (2 SOQL). 6 handler tests + 2 controller tests. All deployed to UAT. **Deprecated in Post-Call Intelligence feature** — replaced by nbaPostCallPanel.
- **Feature 16**: Post-Call Intelligence Panel (6 sessions) -- Detects Talkdesk Activity + AI_Call_Note__c insertion via enriched `Call_Completed_Event__e` Platform Event (Source_Type__c discriminator). LWC subscribes via empApi, calls `getPostCallContext()` for full qualification + stage context, renders `nbaPostCallPanel` overlay with stage progression banner, 9 qualification field cards (grouped by stage gate), inline editing, and editable call notes. `savePostCallEdits()` persists field edits (write-if-blank text, ratchet-only booleans) + ContentNote. Event queue handles multiple events while panel is open. Works in both App Page and Record Page modes. Replaces deprecated `nbaCallNoteCapture` LWC. AICallNoteGtmTrigger + handler publishes events for AI_Call_Note__c records. All deployed to UAT.

### Sprint 21 — Two-Stream Architecture (COMPLETE)

Split action delivery into two independent streams. All items deployed to UAT and tested, including Event Details component and duplicate banner suppression.

#### Architecture: Two-Stream Action Delivery

```
Stream 1 (Scored Queue) — getActiveAction():
  Platform Cache → cache miss → full on-demand evaluation (~12 SOQL)
  Returns ActionWrapper for the top-priority scored action.
  NO Layer 1 DB check — interrupts handled separately.

Stream 2 (Real-Time Interrupts) — checkInterrupts():
  15s LWC poll → 2 lightweight SOQL:
    1. Meetings: DueAt within 5 min, Status IN (New/Pending/Accepted)
    2. New-assignments: L1 non-time-bound, created within 24h
  Returns List<ActionWrapper>. AE clicks "Jump to it" → acceptInterrupt()
  sets Status='In Progress', saves _pausedAction, loads interrupt context.
  On complete → resumes paused scored-queue action.
```

#### What Was Built

| Component | Change |
|-----------|--------|
| `NbaActionController.cls` | Removed L1 check from getActiveAction. Added checkInterrupts() returning List<ActionWrapper>. Added acceptInterrupt(Id). |
| `NbaActionCreationService.cls` | Added createNewAssignmentAction() single + createNewAssignmentActions() bulk (1 SOQL dedup). |
| `NbaOpportunityTriggerHandler.cls` | AFTER_INSERT creates new-assignment interrupt via bulk method. AFTER_UPDATE detects OwnerId changes by non-self users (router/manager reassignment) → creates interrupt for new owner, invalidates cache for both old and new owners. Self-assignment excluded. |
| `NbaActionStateService.cls` | expireStaleActions() extended: non-time-bound L1 older than 24h expired. INTERRUPT_EXPIRE_HOURS constant. |
| `nbaDemoWorkspace` LWC | Replaced checkTimeBound with checkInterrupts + acceptInterrupt. Added _pausedAction, pendingInterrupts, _dismissedInterruptIds. |
| `nbaDemoAlertBanner` LWC | Added indigo interrupt banner with "Jump to it" / "Later" buttons. Slide-down animation. |

#### Sprint 21 Completed Items (formerly pending)

- **Suppress duplicate amber banner**: DONE (commit `1f45388`). `showBanner` getter in nbaDemoAlertBanner returns false when `isActionMode && currentAction?.actionType === 'Meeting'`.
- **Event Details component**: DONE (commit `1f45388`). New `nbaEventDetails` LWC showing Event Subject, Description, Location, Start/End Time via LDS `getRecord` (0 SOQL). `eventId` added to ActionWrapper, parsed from UniqueKey. Wired into nbaDemoWorkspace with `showEventDetails` getter.

### Sprint 22 — Engine Hardening + Talkdesk Call Notes + Rebrand (COMPLETE)

Sprint 22 delivered 4 features across 6 commits (2026-02-19 to 2026-03-03).

#### 22a. GTM OS Rebrand (commit `d930710`)

Renamed all user-facing "NBA v2" labels to "GTM OS" across 23 files. API names unchanged (NBA_Queue__c, NBA_Cadence__mdt, etc. are immutable once deployed).

| Scope | Change |
|-------|--------|
| FlexiPages | "NBA V2 Demo/Workspace" → "GTM OS Demo/Workspace" |
| LWC | breadcrumb "NBAv2" → "GTM OS", field label "NBA Call Count" → "GTM Call Count" |
| Custom Object | "NBA Queue" → "GTM Queue", auto-number "NBA-" → "GTM-" |
| 7 CMDTs | "NBA Cadence/Suppression/Urgency/..." → "GTM ..." |
| Custom Setting | "NBA AE Config" → "GTM AE Config" |
| 3 Permission Sets | "NBA Queue AE/Account Scoring..." → "GTM ..." |
| ListView | "NBA Ownership Transfer" → "GTM Ownership Transfer" |
| Apex | Schedulable job names + test LIKE patterns |

#### 22b. Engine Hardening (commit `fc0d83c`)

4 fixes from code audit, 3 new tests added:

| Priority | Fix | Impact |
|----------|-----|--------|
| P0 | `ORDER BY Amount DESC NULLS LAST` on 200-opp query in `evaluateOnDemand()` | Prevents non-deterministic truncation that could exclude high-value opps |
| P1 | Removed dead cooldown code from `NbaActionSelectionService` | Saves 1 SOQL per evaluation. Note: `CooldownUntil__c` write in `NbaActionStateService` preserved — feeds `NbaSignalService` dismissed-record detection |
| P1 | Fixed MRR normalization to use fixed $50K ceiling | Previously a $200K outlier would suppress all other opps' impact scores to near zero |
| P3 | try/catch around Talkdesk + Mogli SOQL in `NbaSignalService` | Graceful degradation if managed packages are removed |

#### 22c. Post-Call Notes Capture (commits `d235ed5`, `4fb7b43`, `f7f4ced`, `c7f2cd8`)

Auto-detect Talkdesk calls and present editable notes overlay. Evolved through 4 commits: initial NBA_Queue__c interrupt approach → trigger naming fix → test data fix → Platform Event refactor.

**Final architecture (Platform Event)**:
```
Talkdesk Activity inserted → NbaTalkdeskActivityTrigger fires
  → NbaTalkdeskActivityTriggerHandler filters (has Opp link, correct type)
  → EventBus.publish(Call_Completed_Event__e) with 8 payload fields
  → LWC nbaDemoWorkspace subscribes via empApi
  → Shows nbaCallNoteCapture overlay with pre-populated notes
  → AE edits + saves → NbaActionController.saveCallNotes()
  → Creates ContentNote + ContentDocumentLink to Opportunity
```

**Why Platform Event over NBA_Queue__c interrupt**: Eliminates polluting GTM Queue reporting with non-scored actions. Delivers overlay via push (empApi) instead of 15s polling.

| Component | Purpose |
|-----------|---------|
| `Call_Completed_Event__e` | Platform Event (PublishAfterCommit) with 8 fields: Sales_Rep_Id, Opportunity_Id, Activity_Id, Call_Notes, Disposition, Account_Name, Opp_Name, Talk_Time_Sec |
| `NbaTalkdeskActivityTrigger` | After insert on `talkdesk__Talkdesk_Activity__c` |
| `NbaTalkdeskActivityTriggerHandler` | Filter → dedup → publish Platform Event (2 SOQL) |
| `NbaActionController.saveCallNotes()` | Creates ContentNote linked to Opportunity |
| `nbaCallNoteCapture` LWC | Overlay with notes textarea, disposition badge, talk time, save/cancel |
| `nbaDemoWorkspace` | empApi subscription, `_pendingCallNote` state, overlay show/hide |

**Test coverage**: 6 handler tests (NbaTalkdeskActivityTriggerHandlerTest) + 2 controller tests. All passing.

#### Gotchas Discovered in Sprint 22

- **Talkdesk trigger naming collision**: Production has managed `talkdesk.TalkdeskActivityTrigger`. Our trigger must use `NbaTalkdeskActivityTrigger` prefix to avoid ambiguity.
- **`talkdesk__Talkdesk_Id__c` required**: External ID field is required by managed package. Test data must include unique values via helper method.
- **Call Completed picklist value**: Added then deactivated on `Action_Type__c` — preserves existing records but prevents new selections. History remains queryable.
- **empApi subscription**: `subscribe('/event/Call_Completed_Event__e', -1, handler)` in `connectedCallback`, `unsubscribe` in `disconnectedCallback`. Filter by `Sales_Rep_Id__c` matching current user.

### Phase 2 Engine Core — COMPLETE (Sprint 12, REWRITTEN in PRD v2 Refactor)

6 Apex service classes. **Scoring and selection were rewritten** in the PRD v2 refactor (14 sessions) to replace Impact×Urgency with Expected Incremental ARR + stage priority.

| Class | Purpose | Coverage | Tests |
|-------|---------|----------|-------|
| `NbaSignalService` | CRM signal detection (7 SOQL/batch) | 84% | 8 |
| `NbaActionCreationService` | Eligibility + Expected ARR scoring | 89% | 14 |
| `NbaActionStateService` | Lifecycle: complete, snooze, dismiss, expire | 85% | 12 |
| `NbaActionSelectionService` | Stage Priority → Expected ARR ranking | 91% | 10 |
| `NbaAutomatedOutreachService` | SMS (Mogli) + Email automation | 89% | 8 |
| `NbaActionExpirationSchedulable` | Expire stale + unsnooze due | 100% | 2 |

#### Key Engine Architecture (PRD v2 Aligned)

**Signal Detection** (NbaSignalService): Queries 7 CRM data sources per Opp batch — Opportunity, Talkdesk Activity, Mogli SMS, Events, Tasks, Account_Scoring__c (Likelihood_To_Win, Incremental_If_Won), existing NBA_Queue__c. Returns `Map<Id, OpportunitySignal>` with 40+ fields.

**Action Creation** (NbaActionCreationService): Evaluates signals through pipeline: suppress? → determine cadence step (stage-scoped) → calculate Expected Incremental ARR (`LTW × IIW × ConnectRate(attempt)`) → assign Stage_Priority__c → create NBA_Queue__c candidate. UniqueKey: `'V2|' + oppId + '|' + actionType`.

**State Management** (NbaActionStateService): AE-invoked transitions (complete, snooze, dismiss) + system-invoked (expire). Writes cadence audit fields (Cadence_Name, Step_Number, Step_Outcome, Step_Method) to NBA_Queue__c.

**Selection** (NbaActionSelectionService): Time-Bound Override → Timezone Gate (8 AM local) → Stage Priority (hard boundary) → Expected ARR DESC → Oldest Opp tiebreaker. No urgency blending.

**Automated Outreach** (NbaAutomatedOutreachService): Hybrid scheduling — immediate execution via Queueable for no-delay steps + 5-min Schedulable batch for delayed sends. SMS via Mogli, Email via Messaging.SingleEmailMessage. Compliance checks (opt-out, deliverability).

### Phase 3 — LWC Integration — COMPLETE (Sprint 13)

Wired the engine into the Demo LWC so AEs can see and interact with V2 actions on a dedicated App Page.

**UX**: AE opens App Page → sees top-priority action with full Opp context → Complete/Snooze/Dismiss → next action loads → "All caught up!" when done.

#### What Was Built

| Component | Purpose |
|-----------|---------|
| `NbaActionController.cls` + test (10 tests, 96% coverage) | Thin controller: getActiveAction, complete, snooze, dismiss. Delegates to NbaActionStateService. |
| `nbaEmptyState` LWC | "All caught up!" display when AE has no actions |
| `nbaActionBar` LWC | Fixed bottom bar (viewport-pinned, clears SF utility bar): Complete (green), Snooze (modal overlay 15m/1h/4h + reason), Dismiss (modal overlay with category + reason) |
| `nbaDemoWorkspace` dual-mode refactor | connectedCallback detects App Page, imperative getActiveAction + getPageData, effectiveRecordId getter, transition overlay |
| `nbaDemoHeader` action badge | Color-coded action type badge (5 types), snooze hidden in action mode |
| `nbaDemoInsightsPanel` "Why This Action" | Dual title, shows action instruction + reason in action mode |
| `nbaDemoAlertBanner` urgency banner | Red time-bound urgency banner with countdown |
| `NBA_V2_Workspace.flexipage-meta.xml` | App Page FlexiPage (defaultAppHomeTemplate) |

#### Architecture: Dual-Mode Workspace

- **Record Page mode**: `@api recordId` auto-set → `@wire(getPageData)` fires normally → unchanged from Sprint 10
- **App Page mode**: No recordId → `connectedCallback` → `getActiveAction()` → imperative `getPageData(action.oppId)` → `_applyPageData(data)` helper → action bar at bottom

Both paths share `_applyPageData(data)`. Children receive `effectiveRecordId` (action's oppId or recordId). Action lifecycle dispatches events up from `nbaActionBar` → workspace handlers call controller → reload if different Opp.

#### Key Gotcha: LWC Template Ternary
LWC does not allow ternary operators in HTML `class={}` attributes. Use computed `cssClass` properties in JS getters instead. Example: `{ label: '15 min', value: 15, cssClass: this.snoozeDuration === 15 ? 'selected' : '' }`.

#### Key Gotcha: SF Utility Bar Offset
The Salesforce utility bar (app tabs at the bottom) is ~44px tall and sits at the viewport bottom. Any `position: fixed; bottom: 0` element will be hidden behind it. The action bar uses `bottom: 44px` to clear it, and snooze/dismiss panels use `bottom: 116px` (44px utility + 72px bar).

### Phase 4 — Triggers + Real-Time Events — COMPLETE (Sprint 14)

Added real-time trigger-based action creation so actions appear instantly when CRM events occur.

#### What Was Built

| Component | Purpose |
|-----------|---------|
| `OpportunityTrigger` + `NbaOpportunityTriggerHandler` | New opp → SLA First Touch, stage change → re-evaluation via async Queueable |
| `EventTrigger` + `NbaEventTriggerHandler` | Meeting scheduled → Layer 1 time-bound action (synchronous), reschedule/cancel support |
| `TaskTrigger` + `NbaTaskTriggerHandler` | Activity logged → context update, auto-completes First Touch/Re-engage on connected calls |
| `NbaRealTimeEvaluationQueueable` | Async wrapper reusing full engine pipeline (signal → evaluate → create → promote) |
| `NbaTriggerContext` | Recursion guards, shared constants, helper methods for all trigger handlers |
| `NbaActionCreationService` additions | `createTimeBoundAction()`, `updateTimeBoundAction()`, `cancelTimeBoundAction()` |
| `nbaDemoWorkspace` polling | 60s auto-refresh on App Page for real-time action detection |

#### Architecture: Trigger → Handler → Engine

- **Opportunity triggers** (heavy — full signal evaluation): Enqueue `NbaRealTimeEvaluationQueueable` → runs in async context with fresh governor limits → reuses `NbaSignalService.getSignals()` + `NbaActionCreationService.evaluateAndCreate()`.
- **Event triggers** (lightweight — synchronous): Call `NbaActionCreationService.createTimeBoundAction()` directly in trigger context (2-3 SOQL + 1-2 DML).
- **Task triggers** (lightweight — synchronous): Query existing actions for affected Opps, update context fields or auto-complete.
- **Recursion prevention**: `NbaTriggerContext` static booleans prevent re-entry when NBA_Queue__c DML causes cascading triggers.
- **Dedup**: Time-bound actions use UniqueKey `'V2|' + oppId + '|Meeting|' + eventId`.

#### Key Gotcha: Trigger-Test Interaction
When testing `createTimeBoundAction()` directly, set `NbaTriggerContext.setEventHandlerRun()` BEFORE inserting the Event to prevent the EventTrigger from creating the action first (dedup would return null). Tests that rely on the trigger firing should NOT set this guard.

### Phase 5 — On-Demand Engine + Platform Cache — COMPLETE (Sprint 15)

**PIVOTED** from persist-first to on-demand architecture. Full plan: `.claude/plans/cosmic-wondering-parasol.md`.

The persist-first model (scheduled jobs pre-create NBA_Queue__c records) had fundamental issues: capacity cap friction (MAX_ACTIVE_PENDING_PER_AE = 2 blocks promotion), stale records between batch runs, and actions not reflecting real-time CRM state. The new model evaluates on-demand, caches in Platform Cache, and persists NBA_Queue__c only as audit records on AE interaction.

#### Architecture Shift
```
OLD:  Scheduled Job → create NBA_Queue__c → LWC reads from DB
NEW:  LWC requests action → evaluate signals NOW → Platform Cache → serve
      AE interacts (complete/snooze/dismiss) → write audit record → re-evaluate → serve next
      Triggers (time-bound only) → write Layer 1 record → invalidate cache → 15s poll picks it up
```

#### Scope Decisions
- **Blitz campaigns**: DEFERRED. Layer 2 mode infrastructure built but Campaign linking skipped.
- **Method escalation**: On no-connect only (Attempted-LVM, Attempted-NVM). Integrated into evaluation pipeline.
- **Action bar UX**: Keep generic "Complete" button. Method shown as instruction text only.
- **Manager dashboard**: DEFERRED to Sprint 16.

#### Work Groups (7) — ALL COMPLETE
| Group | Goal | Status |
|-------|------|--------|
| **A. Platform Cache** | NbaCacheService for per-AE action caching (5min TTL) | DONE |
| **B. Cooldown + Escalation** | Snooze/completion suppression + method escalation in evaluation pipeline | DONE |
| **C. Simplified State** | NbaActionStateService → audit record writer + cache invalidation | DONE |
| **D. On-Demand Controller** | Rewrite getActiveAction as evaluation entry point, checkTimeBound for 15s poll | DONE |
| **E. Trigger Updates** | Add cache invalidation to all triggers, remove Queueable | DONE |
| **F. LWC Polling** | Dual poll (15s time-bound + 5min full refresh), pass full action context | DONE |
| **G. Cleanup + Permissions** | Archive schedulables, add NBA_Queue_AE permission set | DONE |

#### Key Architecture Changes
- **getActiveAction() flow** (NbaActionController): Check Layer 1 time-bound (1 SOQL) → check Platform Cache → cache miss: full evaluation (NbaSignalService + NbaActionCreationService + NbaActionSelectionService) ~12 SOQL → cache result → return.
- **completeAction()**: Now takes action details (not actionId). Writes NBA_Queue__c audit record → invalidates cache → re-evaluates → returns next action.
- **SOQL budget**: Cache hit = 1 SOQL. Cache miss = ~12 SOQL. Worst case with getPageData = ~24 SOQL. Safe within 100.
- **Deprecated**: NbaActionCreationSchedulable (6 creation jobs), NbaRealTimeEvaluationQueueable (replaced by on-demand). Capacity cap removed.

### Phase 6 — Cadence Rule Integration — COMPLETE (Sprint 17) — SUPERSEDED BY PHASE 7

Integrated NBA_Cadence_Rule__mdt into the on-demand evaluation pipeline so First Touch actions follow a structured 5-day cadence with spacing enforcement, daily caps, and method hints. **Note: Phase 7 (Sprints 18-20) replaces the flat CMDT approach with a 2-CMDT parent/child architecture with outcome branching.**

#### What Was Built

| Component | Purpose |
|-----------|---------|
| `NbaCadenceService.cls` + test (8 tests) | Core cadence logic: load CMDT rules, determine current step, enforce 60-min spacing + daily caps, build CadenceStep |
| `NBA_AE_Config__c` hierarchy custom setting | Per-AE cadence variant assignment (0 SOQL via `getInstance()`) |
| 5 new CMDT fields on NBA_Cadence_Rule__mdt | Cadence_Day__c, Variant__c, Step_Order__c, Hint_Text__c, Is_Primary__c |
| 12 redesigned CMDT records | First Touch Variant A: D0 (Call1→SMS1→Call2→Email1→Call3), D1 (Call4→Call5→SMS2→Email2), D3 (Email3→Call6), D5 (Breakup) |
| `NbaSignalService` enrichment | 3 new OpportunitySignal fields: `daysSinceCreation`, `todayCallCount`, `todayCallDates` (0 extra SOQL) |
| `NbaActionCreationService` integration | Cadence step resolution in `evaluateAndCreate()`, fallback to `determineNonCadenceActionType()` when cadence suppresses |
| `NbaActionController` ActionWrapper extension | 6 cadence fields: `cadenceStage`, `cadenceDay`, `todayCallCount`, `maxCallsToday`, `methodHints`, `cadenceProgress` |
| `NbaActionStateService` audit enhancement | Writes cadence metadata to audit records via `NbaCadenceService.lastEvaluatedSteps` |
| `nbaDemoInsightsPanel` cadence context | Shows cadence progress (step X of Y) + method hints in action mode |
| `nbaDemoHeader` cadence step badge | Shows "X/Y" call count badge (indigo pill) |

#### Architecture: Cadence Evaluation Flow

```
getActiveAction() → cache miss → NbaSignalService.getSignals()
  → OpportunitySignal now includes daysSinceCreation, todayCallCount, todayCallDates
  → NbaActionCreationService.evaluateAndCreate()
    → For First Touch: NBA_AE_Config__c.getInstance(ownerId) → variant (0 SOQL)
    → NbaCadenceService.getCurrentStep(signal, variant) → CadenceStep or null
      → loadRules() (1 SOQL, static-cached)
      → computeCadenceDay(daysSinceCreation) → 0/1/3/5/complete
      → Filter rules for scenario + variant + cadenceDay
      → Check daily cap (todayCallCount vs Max_Attempts_Per_Day__c)
      → Check spacing (todayCallDates vs Attempt_Spacing_Minutes__c)
      → Return CadenceStep with method, hints, stage info
    → If cadence suppresses → determineNonCadenceActionType() fallback
    → Build NBA_Queue__c with cadence fields (Cadence_Stage, Rule_Name, Action_Instruction)
  → NbaCadenceService.lastEvaluatedSteps (static map) → read by ActionWrapper mapping
```

#### Key Pattern: Transaction-Scoped Static Map

`NbaCadenceService.lastEvaluatedSteps` is a `Map<Id, CadenceStep>` populated during `getCurrentStep()` and read by `NbaActionController.toWrapperFromCandidate()` in the same Apex transaction. This avoids extra SOQL to retrieve cadence context when building the ActionWrapper response for the LWC.

#### SOQL Budget Update
Cache miss = ~13 SOQL (was ~12; +1 for CMDT query, static-cached after first call). No change to cache hit path.

### Phase 7 — NBA Cadence Redesign — COMPLETE (Sprints 18-20)

Redesigned the cadence system from a flat CMDT (NBA_Cadence_Rule__mdt with 12 records) to a 2-CMDT parent/child architecture mimicking Salesloft/Sales Engagement. Full plan: `.claude/plans/jiggly-inventing-candle.md`.

#### Sprint 18: Foundation (COMPLETE)

| Component | Purpose |
|-----------|---------|
| `NBA_Cadence__mdt` | Parent CMDT: cadence definition (scenario, variant, total steps/days, exit conditions, day map) |
| `NBA_Cadence_Step__mdt` | Child CMDT: individual steps with outcome branching (On_Connect/On_VM/On_No_Answer/On_Meeting actions) |
| `First_Touch_A` records | 1 parent + 12 step records (5-day cadence: D0×5, D1×4, D3×2, D5×1) |
| `NbaCadenceService.cls` rewrite | Complete rewrite with CadenceContext, CadenceStepDef, CadencePosition, CadenceResult classes |
| `NbaCadenceServiceTest.cls` rewrite | 19 tests (was 8). Covers branching, day gating, spacing, exit conditions, progress resolution |
| 4 NBA_Queue__c fields | Cadence_Name__c, Cadence_Step_Number__c, Step_Outcome__c, Step_Method__c |
| NbaSignalService OpportunitySignal | 4 new fields: lastCadenceName, lastCadenceStepNumber, lastCadenceStepOutcome, lastCadenceStepDate |

#### Sprint 19: Integration + LWC (COMPLETE)

Wired the new 2-CMDT engine into all service layers and added outcome capture to LWC.

**Apex changes (4 service classes):**

| Class | Changes |
|-------|---------|
| `NbaSignalService` | Added 4 cadence fields to queryExistingActions SELECT. Extracts cadence progress from most recent completed audit record. 0 extra SOQL. |
| `NbaActionCreationService` | Replaced Phase 6 First-Touch-only cadence block with universal `getNextStep()` for any action type. Uses CadenceResult instead of CadenceStep. Writes Cadence_Name__c, Cadence_Step_Number__c, Step_Method__c to action record. |
| `NbaActionController` | Extended ActionWrapper with 8 Phase 7 fields (cadenceName, cadenceStepNumber, cadenceTotalSteps, stepMethod, stepInstruction, cadenceProgress, progressFraction, upcomingSteps, isCadenceAction). Updated completeAction signature to accept stepOutcome. Updated toWrapperFromCandidate to read from lastEvaluatedResults. |
| `NbaActionStateService` | Updated completeAction to accept stepOutcome (6 params). Updated writeAuditRecord to write 4 cadence fields from lastEvaluatedResults + stepOutcome. |

**LWC changes (4 components):**

| Component | Changes |
|-----------|---------|
| `nbaActionBar` | Call outcome panel (Connected/Left VM/No Answer). SMS button "Mark SMS Sent" (auto-outcome=Sent). Email button "Mark Email Sent" (auto-outcome=Sent). Non-cadence: unchanged. |
| `nbaDemoWorkspace` | Passes stepOutcome from event detail to completeAction Apex call |
| `nbaDemoInsightsPanel` | Progress bar with fill width, fraction badge (e.g., "3/12"), upcoming steps preview list with method icons |
| `nbaDemoHeader` | Method-specific icon (call/sms/email) in cadence badge, step count "X/Y" |

**Test updates:** NbaActionControllerTest + NbaActionStateServiceTest updated for new completeAction signatures (stepOutcome parameter).

#### Architecture: Phase 7 Cadence Evaluation Flow

```
getActiveAction() → cache miss → NbaSignalService.getSignals()
  → OpportunitySignal includes: daysSinceCreation, todayCallCount, todayCallDates,
    lastCadenceName, lastCadenceStepNumber, lastCadenceStepOutcome (from audit records)
  → NbaActionCreationService.evaluateAndCreate()
    → NBA_AE_Config__c.getInstance(ownerId) → variant (0 SOQL)
    → NbaCadenceService.getNextStep(signal, variant, actionType) → CadenceResult
      → loadAndParseCadences() (2 SOQL, static-cached)
      → Match action type + variant to CadenceContext
      → Check exit conditions (Connected_Call? Meeting_Scheduled? Opp_Closed?)
      → computeCadenceDay(rawDays, dayMapJson) → cadence day
      → Get position from signal's lastCadenceStepNumber + lastCadenceStepOutcome
      → applyBranching(lastStep, outcome) → End_Cadence / Skip_To_Step / Skip_To_Day / Continue
      → Find target step, check day gate, check spacing
      → Populate lastEvaluatedResults static map
    → If suppressed → determineNonCadenceActionType() fallback
    → Build NBA_Queue__c with cadence fields
  → ActionWrapper reads from NbaCadenceService.lastEvaluatedResults
  → LWC displays progress bar + upcoming steps + method-specific buttons
```

#### Key Pattern: Transaction-Scoped Static Maps (Phase 7)

`NbaCadenceService.lastEvaluatedResults` (`Map<Id, CadenceResult>`) replaces Phase 6's `lastEvaluatedSteps`. Populated during `getNextStep()`, read by both `NbaActionController.toWrapperFromCandidate()` and `NbaActionStateService.writeAuditRecord()` in the same Apex transaction.

#### Sprint 20: Second Cadence + Cleanup (COMPLETE)

**Re_engage_A cadence (7 CMDT records):**

| Component | Purpose |
|-----------|---------|
| `NBA_Cadence.Re_engage_A` | Parent: 6 steps, 7 days, anchor=daysSinceLastInteraction, exit on Connected/Meeting/Closed |
| 6 `NBA_Cadence_Step.REA_*` records | D0: Call+Email, D1: Call, D3: SMS, D5: Email, D7: Call. Branching on calls. |

**Deprecated code removal:**

| Change | Details |
|--------|---------|
| `NbaCadenceService.cls` | Removed CadenceStep class, lastEvaluatedSteps map, getCurrentStep() wrapper |
| `NbaActionController.cls` | Removed 5 backward-compat ActionWrapper fields (cadenceStage, cadenceDay, todayCallCount, maxCallsToday, methodHints) + population logic |
| 12 `NBA_Cadence_Rule__mdt` records | Set Is_Active__c = false on all Phase 6 flat CMDT records |

**Test updates:** NbaCadenceServiceTest: 23 tests (was 19; -1 deprecated + 5 new Re_engage_A). 62 targeted tests passing across 4 service test classes.

### Signal Architecture Reference

Keep this reference for future phases — describes how the engine reads CRM data.

**Phone Calls → Talkdesk Activities** (`talkdesk__Talkdesk_Activity__c`): `talkdesk__Opportunity__c` direct lookup. Connected = `DispositionCode Label LIKE 'Connected%' AND Talk_Time > 0`. Connection triggers 24hr cooldown.

**Text Messages → Mogli SMS** (`Mogli_SMS__SMS__c`): `Mogli_SMS__Opportunity__c` direct lookup. Direction: `'Outgoing'`/`'Incoming'`. Inbound reply = connection (24hr cooldown).

**Meetings → Events**: `WhatId` link. Suppression: `StartDateTime` within 24h. Missed meeting triggers Post-Demo No-Show cadence.

**Tasks**: `WhatId` link. Use Talkdesk as PRIMARY call source, not Tasks. Follow-up Tasks with ReminderDateTime = time-bound commitment.

**Opportunity Signals**: `Days_Since_Last_Interaction__c` formula (0 SOQL cost, returns 99999 if no interaction).

**Account Scoring** (`Account_Scoring__c`): `Likelihood_To_Win__c` (mapped from `Prob_Payroll_Conversion__c`) and `Incremental_If_Won__c` feed Expected ARR formula. Fallback: stage-based probability × MRR/Amount.

### Pending Actions
- Merge `testing/sprint-22-20260303` to master (Post-Call Intelligence complete)
- Share data contract with Data Engineering for Account_Scoring__c pipeline
- Assign GTM OS FlexiPages in production org
- Assign GTM Queue AE permission set to AE profiles/users

### Known Org Issues
- **15 pre-existing test failures** in `QuotaGapSchedulerTest` (14) and `ProjectTriggerHandlerTest` (1) — unrelated to GTM OS work, block `--test-level RunLocalTests` deploys. Workaround: deploy with `NoTestRun`, then run targeted tests separately.
- **Org-wide test coverage at 26%** — well below the 75% production threshold. Not a UAT blocker but must be addressed before any production deployment.
- **2 pre-existing test failures** in targeted suite (unchanged from Sprint 21) — not GTM OS code.

## SF CLI Commands (v2)

### Deployment & Retrieval
- Deploy all: `sf project deploy start --source-dir force-app`
- Deploy specific file: `sf project deploy start --source-dir force-app/main/default/classes/MyClass.cls`
- Deploy validation only (dry run): `sf project deploy start --source-dir force-app --test-level RunLocalTests --dry-run`
- Retrieve all: `sf project retrieve start --source-dir force-app`
- Retrieve specific type: `sf project retrieve start --metadata ApexClass`
- Deploy preview: `sf project deploy preview --source-dir force-app`

### Testing
- Run all tests: `sf apex run test --synchronous --result-format human`
- Run specific test: `sf apex run test --class-names MyClassTest --synchronous --result-format human`
- Run specific method: `sf apex run test --tests MyClassTest.testMethodName --synchronous --result-format human`
- Run with coverage: `sf apex run test --class-names MyClassTest --synchronous --result-format human --code-coverage`

### Data & Debugging
- Run SOQL: `sf data query --query "SELECT Id, Name FROM Account LIMIT 10"`
- Execute anonymous Apex: `sf apex run --file scripts/apex/myScript.apex`
- View debug logs: `sf apex log list` then `sf apex log get --log-id <id>`
- List orgs: `sf org list`
- Open org in browser: `sf org open`

## Governor Limits — NEVER violate these
- **No SOQL inside loops.** Query outside the loop, use maps for lookups.
- **No DML inside loops.** Collect records in a list, do one DML operation after the loop.
- **Bulkify everything.** All triggers and classes must handle 200+ records.
- **SOQL 100 query limit per transaction.** Minimize queries.
- **DML 150 statements per transaction.** Batch DML operations.
- **Heap size 6MB (sync) / 12MB (async).** Avoid huge collections.

## Essential Commands

### Testing (Local)
- `npm test` -- Run all LWC unit tests
- `npm run test:unit:watch` -- Watch mode
- `npm run test:unit:coverage` -- Coverage reports
- `npm test -- --testPathPattern=<componentName>` -- Run specific LWC test

### Linting & Formatting
- `npm run lint` -- Lint all JS files
- `npm run prettier` -- Format all files
- `npm run prettier:verify` -- Check formatting

## Development Best Practices

### Salesforce Specific
- **Feature branches**: `feature/<name>`, `bugfix/<name>`, `hotfix/<name>`
- **Permission sets over profiles** for access management
- **75%+ Apex test coverage** required for production
- **Test data in tests**: Never rely on existing org data. Use `@testSetup` for shared data.
- **In this org**: Never query test Opportunities by Name (triggers rename them). Use Account.Name + StageName.

### LWC Specific
- **Collapsible sections**: `@track sectionExpanded = true` + chevron toggle (see `docs/architecture.md`)
- **Dropdown close-on-click-outside**: `setTimeout` + `document.addEventListener('click', handler, { once: true })`
- **No ternary in HTML templates**: Pre-compute CSS classes in JS getters
- **Icon colors**: Use `variant="inverse"` for white icons, triple CSS var declaration for custom colors

### Code Quality
- `npm run lint` + `npm test` + `npm run prettier:verify` before commits
- Pre-commit hooks (Husky/lint-staged) auto-format, lint, and test
- Static analysis: `sf scanner run --target "force-app/**/*.cls"`

## Common Gotchas
- **Mixed DML**: Cannot DML setup objects (User, PermissionSet) and non-setup objects in the same transaction. Use `System.runAs()` or `@future` to separate.
- **SOQL injection**: Use bind variables (`:variableName`) — never string concatenation.
- **LWC reactivity**: Reassign arrays/objects (`this.items = [...this.items, newItem]`), don't mutate.
- **@wire results**: Read-only — clone before modifying.
- **DOM access**: Use `this.template.querySelector`, never `document.querySelector` (Locker Service).
- **Mogli SMS**: Use `'Outgoing'` not `'Outbound'` for Direction. `Account__c` field on SMS__c is non-namespaced.
- **MRR__c**: Formula field — queryable but NOT writable. Use `Amount` in tests.
- **Source__c**: Required picklist on Opportunity — set to `'N/A'` in test data.
- **Days_Since_Last_Interaction__c**: Formula on Opportunity — queryable, NOT writable. MIN of Days_Since_Last_Call__c and Days_Since_Last_Meeting__c. Returns 99999 if both null.
- **Talkdesk Activity naming**: Name field has "Contact"/"Interaction" prefix — use `talkdesk__Type__c` for logic, not Name. "Interaction" is correct convention.
- **Talkdesk Opp link**: `talkdesk__Opportunity__c` exists but not all records have it (support reps). Filter by Opp ownership or null check.
- **NBA_Queue__c relationship paths**: Custom lookup fields use `__r` syntax — `Account__r.Name`, `Opportunity__r.Name`, NOT `Account.Name`.
- **Dismissal_Category__c picklist**: Restricted values — `'Call Scheduled'`, `'Time Zone'`, `'Other'`. Don't use arbitrary strings.
- **One Payroll Opp per Account**: Validation rule prevents multiple open Payroll Opps on same Account. In tests, use separate Accounts per Opportunity.
- **Decimal.subtract()**: Not visible in Apex. Use `-` operator on Long/Integer instead: `Long ms = Math.abs(dt1.getTime() - dt2.getTime())`.
- **SOQL CASE in ORDER BY**: Not supported in Apex SOQL. Query with simple ORDER BY, then sort in-memory with `System.Comparator`.
- **System.schedule() cron syntax**: Doesn't support step (`0/10`) or comma-separated (`0,10,20`) in minutes field. Create separate scheduled jobs at each fixed minute.
- **AuraHandledException message**: `e.getMessage()` doesn't reliably return the constructor message. Test that exception is thrown, not its text.
- **Platform Cache keys**: Must be alphanumeric only (`[a-zA-Z0-9]`). No underscores, hyphens, or special characters. Failures are silent (caught exceptions) and hard to diagnose.
- **CMDT suppression rules**: When adding new `Condition__c` handling in `checkSuppression()`, always deploy the corresponding NBA_Suppression_Rule__mdt record. Code without a matching CMDT record is a silent no-op.
- **Talkdesk trigger naming**: Production has managed `talkdesk.TalkdeskActivityTrigger`. Custom triggers on `talkdesk__Talkdesk_Activity__c` must use a distinct name (e.g., `NbaTalkdeskActivityTrigger`).
- **`talkdesk__Talkdesk_Id__c`**: Required unique External ID on Talkdesk Activity. Test data must include unique values.
- **empApi subscription**: Use `-1` replay ID for new events only. Always `unsubscribe` in `disconnectedCallback` to prevent memory leaks.
- **Event queue for Platform Events**: When a post-call panel is already open and another Platform Event arrives, queue it in `_pendingEventQueue` and process FIFO after confirm/skip. Skip stale events where Opp no longer matches.
- **Record Page mode Platform Events**: empApi subscription must be in `connectedCallback()` outside the `if (!this.recordId)` block so events work in both App Page and Record Page modes.
- **New-assignment interrupt dedup**: UniqueKey includes OwnerId (`V2|oppId|First Touch|NewAssignment|ownerId`) so reassignment to a different user creates a new interrupt even if the original insert interrupt still exists.
- **Owner change interrupt filter**: Only fires when `OwnerId` changed AND `UserInfo.getUserId() != new OwnerId` — self-assignment is excluded. This means the running user (router, manager, admin) must be different from the new owner.
- **postCallContext setter reset pattern**: Converting `@api` property to getter/setter in child LWC allows resetting edit state when parent passes a new context object.

## Detailed Patterns, Agents & Commands

See `.claude/rules/` for detailed coding patterns:
- `apex-patterns.md` — Trigger handlers, batch/queueable/schedulable, invocable actions, naming
- `lwc-patterns.md` — Reactivity, wire adapters, events, navigation, Jest testing
- `security.md` — CRUD/FLS, SOQL injection prevention, sharing model
- `testing.md` — Test class structure, assertions, coverage standards

See `.claude/agents/` for specialized workflows:
- `@sf-reviewer` — Read-only code review with severity report and deploy verdict
- `@sf-deployer` — Full deploy → test → verify cycle
- `@sf-retriever` — Pull metadata from org with change summary

See `.claude/commands/` for slash commands: `/create-lwc`, `/deploy`, `/retrieve`, `/run-tests`, `/review`, `/create-apex`, `/create-flow-apex`, `/soql`, `/debug`, `/local-dev`
