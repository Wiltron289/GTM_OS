# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Detailed Documentation

Sprint-by-sprint change logs, architecture details, and resolved bugs live in separate files to keep this file lean:

- **`docs/architecture.md`** -- Component tree, data flow, design tokens, Mogli SMS architecture, reusable patterns
- **`docs/sprint-history.md`** -- Detailed sprint logs (Sprints 2-10), commit history, files changed per sprint
- **`docs/troubleshooting.md`** -- All resolved bugs with root causes, fixes, and prevention notes
- **`docs/nba-v2-field-mapping.csv`** -- 107 field mappings across all 13 visual sections
- **`docs/nba-v2-phase-plan.md`** -- Full implementation plan for NBA V2 Action Orchestration Engine (Phases 1-5). Covers NBA_Queue__c data model, Custom Metadata rule framework, 3-engine architecture (Creation, State, Selection), Demo LWC refactor, App Page setup, and phased sprint plan.
- **`docs/nba-v2-phase6-cadence-plan.md`** -- Phase 6 cadence integration plan (IMPLEMENTED in Sprint 17). Covers First Touch cadence (5-Day Variant A), CMDT redesign (12 step-sequence records), NbaCadenceService, signal enrichment, spacing enforcement, ActionWrapper extension, LWC display updates, and NBA_AE_Config__c variant assignment.

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
- **Command**: `sf lightning dev app --target-org lwilson@joinhomebase.com.uat --device-type desktop --name "Homebase NBA"`
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

**Last Updated**: 2026-02-16

| Item | Value |
|------|-------|
| **Active Branch** | `feature/nba-v2-demo-lwc` |
| **Deployment Target** | vscodeOrg (Homebase UAT sandbox) |
| **Apex Tests** | 101 total (8 cache + 10 controller + 10 state + 8 signal + 19 creation + 5 selection + 6 opp trigger + 5 event trigger + 7 task trigger + 3 creation sched + 2 expiration sched + 2 queueable + 8 cadence + 19 existing) |
| **Current Phase** | **Phase 6 COMPLETE — Cadence Rule Integration (Sprint 17)** |
| **Phase Plan** | `docs/nba-v2-phase6-cadence-plan.md` (Phase 6), `docs/nba-v2-phase-plan.md` (Phases 1-5) |
| **GitHub** | https://github.com/Wiltron289/GTM_OS |

### What Exists

- **Feature 1**: Account Scoring Data Layer -- `Account_Scoring__c` custom object + permission sets (deployed)
- **Feature 2**: NBA V2 Demo LWC -- 20 LWC components (18 original + nbaEmptyState + nbaActionBar), 2 Apex controllers (NbaDemoController + NbaActionController), 2 FlexiPages (Record Page + App Page). Deployed through Sprint 13.
- **Feature 3**: NBA_Queue__c -- 108-field custom object deployed to UAT (96 original + 12 V2 fields: Impact_Score, Urgency_Score, Priority_Bucket, Priority_Layer, Is_Time_Bound, Cadence_Stage, Attempt_Count_Today, Last_Attempt_Method, Source_Path, Rule_Name, Action_Instruction, Workflow_Mode). Action_Type__c updated with 5 new values (First Touch, Re-engage, Stage Progression, SLA Response, Blitz Outreach).
- **Feature 4**: 5 Custom Metadata Types for NBA V2 rule engine -- NBA_Cadence_Rule__mdt (12 records — redesigned in Sprint 17 with 5 new fields), NBA_Urgency_Rule__mdt (4 records), NBA_Suppression_Rule__mdt (6 records — added Recent_Completion + Snoozed_Action in Sprint 16), NBA_Impact_Weight__mdt (1 record), NBA_Cooldown_Rule__mdt (3 records). All deployed to UAT.
- **Feature 5**: 5 sample NBA_Queue__c records with V2 fields populated (First Touch/Time-Bound, Re-engage, Stage Progression, Snoozed, Blitz Outreach)
- **Feature 6**: NBA V2 Engine Core (Phase 2) -- 6 Apex service classes + 6 test classes, all deployed to UAT. See details below.
- **Feature 7**: NBA V2 Triggers (Phase 4) -- 3 triggers (Opportunity, Event, Task) + 3 handler classes + 1 utility class + 4 test classes. All deployed to UAT.
- **Feature 8**: NBA V2 On-Demand Engine (Phase 5) -- NbaCacheService (Platform Cache), rewritten NbaActionController (on-demand evaluation), simplified NbaActionStateService (audit writer), LWC dual polling (15s/5min), cache invalidation in all triggers. Schedulables archived, Queueable no-op'd. NBA_Queue_AE permission set. All deployed to UAT (93/93 tests passing).
- **Feature 9**: NBA V2 Cadence Integration (Phase 6) -- NbaCadenceService (cadence step resolution, spacing enforcement, daily caps), NBA_AE_Config__c hierarchy custom setting (variant assignment), 5 new CMDT fields + 12 redesigned cadence records (First Touch Variant A, 5-day cadence), signal enrichment (todayCallCount, daysSinceCreation), ActionWrapper cadence fields, LWC cadence display (progress + method hints). All deployed to UAT (52 targeted tests passing).

### Phase 2 Engine Core — COMPLETE (Sprint 12)

All 6 Apex service classes built, deployed, and tested. 43/43 tests passing.

| Class | Purpose | Coverage | Tests |
|-------|---------|----------|-------|
| `NbaSignalService` | CRM signal detection (7 SOQL/batch) | 84% | 8 |
| `NbaActionCreationService` | Rule evaluation + candidate creation | 89% | 14 |
| `NbaActionStateService` | Lifecycle: complete, snooze, dismiss, expire, promote | 85% | 12 |
| `NbaActionSelectionService` | Gate → Rank prioritization | 91% | 5 |
| `NbaActionCreationSchedulable` | 10-min creation job (6 scheduled jobs) | 89% | 2 |
| `NbaActionExpirationSchedulable` | Expire stale + unsnooze due (6 scheduled jobs) | 100% | 2 |

#### Key Engine Architecture

**Signal Detection** (NbaSignalService): Queries 7 CRM data sources per Opp batch — Opportunity, Talkdesk Activity, Mogli SMS, Events, Tasks, Account_Scoring__c, existing NBA_Queue__c. Returns `Map<Id, OpportunitySignal>`.

**Action Creation** (NbaActionCreationService): Evaluates signals through pipeline: suppress? → determine type (First Touch/Stage Progression/Re-engage/Follow Up) → score (Impact + Urgency) → assign bucket/layer → create NBA_Queue__c with Status='Pending'. UniqueKey: `'V2|' + oppId + '|' + actionType`.

**State Management** (NbaActionStateService): AE-invoked transitions (complete, snooze, dismiss) + system-invoked (expire, unsnooze). Promotion: Layer 1 > 2 > 3, then score DESC. Constraint: max 2 active+pending per AE.

**Selection** (NbaActionSelectionService): Gate (cooldown, mode filter) → Rank (layer + score sort). Lightweight — most scoring happens at creation time.

**Schedulables**: 6 jobs each at fixed minute offsets (SF cron doesn't support step/comma syntax). Creation: 0,10,20,30,40,50. Expiration: 5,15,25,35,45,55.

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

### Phase 6 — Cadence Rule Integration — COMPLETE (Sprint 17)

Integrated NBA_Cadence_Rule__mdt into the on-demand evaluation pipeline so First Touch actions follow a structured 5-day cadence with spacing enforcement, daily caps, and method hints.

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

### Signal Architecture Reference

Keep this reference for future phases — describes how the engine reads CRM data.

**Phone Calls → Talkdesk Activities** (`talkdesk__Talkdesk_Activity__c`): `talkdesk__Opportunity__c` direct lookup. Connected = `DispositionCode Label LIKE 'Connected%' AND Talk_Time > 0`.

**Text Messages → Mogli SMS** (`Mogli_SMS__SMS__c`): `Mogli_SMS__Opportunity__c` direct lookup. Direction: `'Outgoing'`/`'Incoming'`.

**Meetings → Events**: `WhatId` link. Suppression: `StartDateTime` within 24h.

**Tasks**: `WhatId` link. Use Talkdesk as PRIMARY call source, not Tasks.

**Opportunity Signals**: `Days_Since_Last_Interaction__c` formula (0 SOQL cost, returns 99999 if no interaction). Account_Scoring__c has only 3 records — fallback via `Opp.Amount + Opp.Probability`.

### Pending Actions
- Share data contract with Data Engineering for Account_Scoring__c pipeline
- Merge feature branch to master (after V2 engine work stabilizes)

### Known Org Issues
- **15 pre-existing test failures** in `QuotaGapSchedulerTest` (14) and `ProjectTriggerHandlerTest` (1) — unrelated to NBA V2 work, block `--test-level RunLocalTests` deploys. Workaround: deploy with `NoTestRun`, then run targeted tests separately.
- **Org-wide test coverage at 26%** — well below the 75% production threshold. Not a UAT blocker but must be addressed before any production deployment.

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
