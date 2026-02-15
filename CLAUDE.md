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

**Last Updated**: 2026-02-14

| Item | Value |
|------|-------|
| **Active Branch** | `feature/nba-v2-demo-lwc` |
| **Deployment Target** | vscodeOrg (Homebase UAT sandbox) |
| **Apex Tests** | 19 passing |
| **Current Phase** | **Sprint 11 — NBA V2 Action Orchestration Engine (Phase 1 COMPLETE, Phase 2 next)** |
| **Phase Plan** | `docs/nba-v2-phase-plan.md` |
| **GitHub** | https://github.com/Wiltron289/GTM_OS |

### What Exists

- **Feature 1**: Account Scoring Data Layer -- `Account_Scoring__c` custom object + permission sets (deployed)
- **Feature 2**: NBA V2 Demo LWC -- 18 LWC components, 1 Apex controller (~955 lines), 1 test class (~560 lines), 1 FlexiPage (deployed through Sprint 10)
- **Feature 3**: NBA_Queue__c -- 108-field custom object deployed to UAT (96 original + 12 V2 fields: Impact_Score, Urgency_Score, Priority_Bucket, Priority_Layer, Is_Time_Bound, Cadence_Stage, Attempt_Count_Today, Last_Attempt_Method, Source_Path, Rule_Name, Action_Instruction, Workflow_Mode). Action_Type__c updated with 5 new values (First Touch, Re-engage, Stage Progression, SLA Response, Blitz Outreach).
- **Feature 4**: 5 Custom Metadata Types for NBA V2 rule engine -- NBA_Cadence_Rule__mdt (7 records), NBA_Urgency_Rule__mdt (4 records), NBA_Suppression_Rule__mdt (4 records), NBA_Impact_Weight__mdt (1 record), NBA_Cooldown_Rule__mdt (3 records). All deployed to UAT.
- **Feature 5**: 5 sample NBA_Queue__c records with V2 fields populated (First Touch/Time-Bound, Re-engage, Stage Progression, Snoozed, Blitz Outreach)

### Current Work: Phase 2 — Engine Core (Sprint 12)

See `docs/nba-v2-phase-plan.md` for full phase plan. **Read this section first — it has critical signal mapping.**

#### Signal Architecture — How the Engine Reads CRM Data

The engine detects real-world events from 5 CRM data sources:

**A. Phone Calls → Talkdesk Activities** (`talkdesk__Talkdesk_Activity__c`, ~2.09M records)
- **Opp link**: `talkdesk__Opportunity__c` (DIRECT lookup exists — confirmed). Not all records have it (support reps use Talkdesk too), so filter by Opp ownership.
- **Connected call**: `talkdesk__DispositionCode__r.talkdesk__Label__c LIKE 'Connected%'` AND `talkdesk__Total_Talk_Time_sec__c > 0`
- **No-connect**: DispositionCode Label LIKE `'Attempted%'` OR Talk_Time = 0
- **Voicemail**: `talkdesk__Type__c = 'Voicemail'`
- **Not interested**: DispositionCode Label LIKE `'Not Interested%'`
- **Type values**: Outbound (765K), Inbound (507K), Abandoned (166K), Voicemail (41K), Outbound_Missed (140K)
- **30+ disposition codes**: Connected - Core Only, Connected - Call Scheduled, Connected - Not Interested, Attempted - Invalid Number, etc.
- **NBA_Queue__c integration**: `Talkdesk_Activity__c` (lookup), `Talkdesk_Disposition__c` (formula), `Talk_Time_Sec__c` (formula) auto-populate when linked
- **Name field gotcha**: Has "Contact" vs "Interaction" prefix — "Interaction" is correct but DON'T use Name for logic, use `talkdesk__Type__c`

**B. Text Messages → Mogli SMS** (`Mogli_SMS__SMS__c`, ~193K records)
- **Opp link**: `Mogli_SMS__Opportunity__c` (direct lookup, 36K linked)
- **Direction**: `'Outgoing'` (75%), `'Incoming'` (25% — customer reply = strong engagement signal)
- **Status**: Sent Successfully, Received Successfully, Error (10%)
- **Gotcha**: Use `'Outgoing'` not `'Outbound'`. `Account__c` is non-namespaced.

**C. Meetings → Events** (standard `Event`, ~25K records)
- **Opp link**: `WhatId` (12K linked, mostly Calendly-generated)
- **Suppression**: `StartDateTime` within 24h → suppress outreach

**D. Activity History → Tasks** (standard `Task`, ~685K records)
- Subtypes: Email (384K), Generic (267K), Call (8.5K, 68% missing disposition), Cadence (3.9K)
- Use Talkdesk as PRIMARY call source, not Tasks

**E. Opportunity Signals**
- **Stages**: New (532), Connect (74), Consult (43), Closing (14), Verbal Commit (1), Ready to Convert (4), Evaluating (4), Hand-Off (803)
- **Inactivity**: Use `Days_Since_Last_Interaction__c` (FORMULA on Opportunity) = `MIN(Days_Since_Last_Call__c, Days_Since_Last_Meeting__c)`. Returns 99999 if no interaction ever. **Use this, NOT LastActivityDate (70% NULL).**
- **Stage history**: `OpportunityFieldHistory` available for stage change detection
- **Account_Scoring__c**: Only 3 records (pilot) — must have fallback scoring via Opp.Amount + Opp.Probability

#### Design Decisions (Confirmed)
1. **Talkdesk→Opp**: Use `talkdesk__Opportunity__c` direct lookup. Filter out support activities.
2. **Inactivity**: Use `Opportunity.Days_Since_Last_Interaction__c` formula (0 SOQL cost).
3. **Eval scope**: Only AEs with < 2 active+pending actions (~50-100 opps per run).

#### Apex Classes to Build

| File | Purpose |
|------|---------|
| `NbaSignalService.cls` + test | Signal detection — queries Talkdesk, SMS, Events per Opp batch |
| `NbaActionCreationService.cls` + test | Rule evaluation + candidate creation (Status='Pending') |
| `NbaActionStateService.cls` + test | Lifecycle: complete, snooze, dismiss, expire, unsnooze, promote |
| `NbaActionSelectionService.cls` + test | Gate → Bucket → Rank prioritization |
| `NbaActionCreationSchedulable.cls` | 10-min scheduled job |
| `NbaActionExpirationSchedulable.cls` | Expire stale + unsnooze due actions |

#### NbaSignalService Query Plan (7 SOQL per batch of 200)
1. Opportunity data (stage, amount, Days_Since_Last_Interaction__c)
2. Recent Talkdesk Activity per Opp (`talkdesk__Opportunity__c`)
3. Recent SMS per Opp (`Mogli_SMS__Opportunity__c`)
4. Upcoming Events per Opp (`WhatId`)
5. Recent Task per Opp (`WhatId`)
6. Account_Scoring__c per Account
7. Existing active NBA_Queue__c per Opp (dedup check)

#### Creation Engine Flow
```
Schedulable (10 min) → AEs with < 2 active+pending
  → Per AE's open Opps (batch 200):
    1. SignalService.getSignals(oppIds)
    2. Per Opp: suppress? → cooldown? → determine type → score → create
    3. SelectionService.selectTop(aeId) → promote to In Progress
```

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
