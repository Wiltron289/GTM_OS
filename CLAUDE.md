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
| **Current Phase** | **Sprint 11 — NBA V2 Action Orchestration Engine (Phase 1: Data Foundation)** |
| **Phase Plan** | `docs/nba-v2-phase-plan.md` |
| **GitHub** | https://github.com/Wiltron289/GTM_OS |

### What Exists

- **Feature 1**: Account Scoring Data Layer -- `Account_Scoring__c` custom object + permission sets (deployed)
- **Feature 2**: NBA V2 Demo LWC -- 18 LWC components, 1 Apex controller (~955 lines), 1 test class (~560 lines), 1 FlexiPage (deployed through Sprint 10)
- **Feature 3**: NBA_Queue__c -- 96-field custom object deployed to UAT (V1 action record with relationships, status lifecycle, priority scoring, call disposition, sales motions, timing/cooldown fields, explainability). Metadata retrieved to local project.

### Current Work: Phase 1 — Data Foundation (Sprint 11)

See `docs/nba-v2-phase-plan.md` for full details. Summary:
- Add ~12 new fields to NBA_Queue__c (Impact_Score, Urgency_Score, Priority_Bucket, Priority_Layer, Cadence_Stage, etc.)
- Add new picklist values to Action_Type__c (First Touch, Re-engage, Stage Progression, SLA Response, Blitz Outreach)
- Create 5 Custom Metadata Types for rule configuration (cadence, urgency, suppression, impact weights, cooldown)
- Seed default rule records
- Deploy to UAT

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
