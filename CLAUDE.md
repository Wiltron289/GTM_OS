# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Detailed Documentation

Sprint-by-sprint change logs, architecture details, and resolved bugs live in separate files to keep this file lean:

- **`docs/architecture.md`** -- Component tree, data flow, design tokens, Mogli SMS architecture, reusable patterns
- **`docs/sprint-history.md`** -- Detailed sprint logs (Sprints 2-10), commit history, files changed per sprint
- **`docs/troubleshooting.md`** -- All resolved bugs with root causes, fixes, and prevention notes
- **`docs/nba-v2-field-mapping.csv`** -- 107 field mappings across all 13 visual sections
- **`docs/nba-v2-phase-plan.md`** -- **READ THIS FIRST for new work.** Full implementation plan for NBA V2 Action Orchestration Engine. Covers NBA_Queue__c data model, Custom Metadata rule framework, 3-engine architecture (Creation, State, Selection), Demo LWC refactor, App Page setup, and phased sprint plan.

Read these when needed (debugging, building new features, understanding history). Don't load them every session.
**Exception**: Always read `docs/nba-v2-phase-plan.md` when starting work on the NBA V2 engine (Sprints 11+).

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

**Last Updated**: 2026-02-15

| Item | Value |
|------|-------|
| **Active Branch** | `feature/nba-v2-demo-lwc` |
| **Deployment Target** | vscodeOrg (Homebase UAT sandbox) |
| **Apex Tests** | 43 passing (Phase 2 engine) + 10 controller + 19 existing = 72 total |
| **Current Phase** | **Phase 3 COMPLETE — Phase 4 (Triggers + Real-Time) next** |
| **Phase Plan** | `docs/nba-v2-phase-plan.md` |
| **GitHub** | https://github.com/Wiltron289/GTM_OS |

### What Exists

- **Feature 1**: Account Scoring Data Layer -- `Account_Scoring__c` custom object + permission sets (deployed)
- **Feature 2**: NBA V2 Demo LWC -- 20 LWC components (18 original + nbaEmptyState + nbaActionBar), 2 Apex controllers (NbaDemoController + NbaActionController), 2 FlexiPages (Record Page + App Page). Deployed through Sprint 13.
- **Feature 3**: NBA_Queue__c -- 108-field custom object deployed to UAT (96 original + 12 V2 fields: Impact_Score, Urgency_Score, Priority_Bucket, Priority_Layer, Is_Time_Bound, Cadence_Stage, Attempt_Count_Today, Last_Attempt_Method, Source_Path, Rule_Name, Action_Instruction, Workflow_Mode). Action_Type__c updated with 5 new values (First Touch, Re-engage, Stage Progression, SLA Response, Blitz Outreach).
- **Feature 4**: 5 Custom Metadata Types for NBA V2 rule engine -- NBA_Cadence_Rule__mdt (7 records), NBA_Urgency_Rule__mdt (4 records), NBA_Suppression_Rule__mdt (4 records), NBA_Impact_Weight__mdt (1 record), NBA_Cooldown_Rule__mdt (3 records). All deployed to UAT.
- **Feature 5**: 5 sample NBA_Queue__c records with V2 fields populated (First Touch/Time-Bound, Re-engage, Stage Progression, Snoozed, Blitz Outreach)
- **Feature 6**: NBA V2 Engine Core (Phase 2) -- 6 Apex service classes + 6 test classes, all deployed to UAT (43/43 tests passing). See details below.

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
| `nbaActionBar` LWC | Fixed bottom bar: Complete (green), Snooze (panel 15m/1h/4h + reason), Dismiss (panel with category + reason) |
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

### Next: Phase 4 — Triggers + Real-Time Events (Sprint 14)

Phase 4 adds triggers on Opportunity, Event, Task for real-time action creation (new opp → SLA First Touch, meeting → time-bound action, activity → context update). See `docs/nba-v2-phase-plan.md`.

### Signal Architecture Reference

Keep this reference for future phases — describes how the engine reads CRM data.

**Phone Calls → Talkdesk Activities** (`talkdesk__Talkdesk_Activity__c`): `talkdesk__Opportunity__c` direct lookup. Connected = `DispositionCode Label LIKE 'Connected%' AND Talk_Time > 0`.

**Text Messages → Mogli SMS** (`Mogli_SMS__SMS__c`): `Mogli_SMS__Opportunity__c` direct lookup. Direction: `'Outgoing'`/`'Incoming'`.

**Meetings → Events**: `WhatId` link. Suppression: `StartDateTime` within 24h.

**Tasks**: `WhatId` link. Use Talkdesk as PRIMARY call source, not Tasks.

**Opportunity Signals**: `Days_Since_Last_Interaction__c` formula (0 SOQL cost, returns 99999 if no interaction). Account_Scoring__c has only 3 records — fallback via `Opp.Amount + Opp.Probability`.

### Pending Actions (from Demo LWC phase)
- Share data contract with Data Engineering for Account_Scoring__c pipeline
- Merge feature branch to master (after V2 engine work stabilizes)

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
