# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Detailed Documentation

Sprint-by-sprint change logs, architecture details, and resolved bugs live in separate files to keep this file lean:

- **`docs/architecture.md`** -- Component tree, data flow, design tokens, Mogli SMS architecture, reusable patterns
- **`docs/sprint-history.md`** -- Detailed sprint logs (Sprints 2-10), commit history, files changed per sprint
- **`docs/troubleshooting.md`** -- All resolved bugs with root causes, fixes, and prevention notes
- **`docs/nba-v2-field-mapping.csv`** -- 107 field mappings across all 13 visual sections

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

**Last Updated**: 2026-02-14

| Item | Value |
|------|-------|
| **Active Branch** | `feature/nba-v2-demo-lwc` |
| **Deployment Target** | vscodeOrg (Homebase UAT sandbox) |
| **Apex Tests** | 19 passing |
| **Latest Sprint** | Sprint 10 (sidebar UX polish, contact dropdown, hidden scrollbars) |
| **GitHub** | https://github.com/Wiltron289/GTM_OS |

### What Exists

- **Feature 1**: Account Scoring Data Layer -- `Account_Scoring__c` custom object + permission sets (deployed)
- **Feature 2**: NBA V2 Demo LWC -- 18 LWC components, 1 Apex controller (~910 lines), 1 test class (~560 lines), 1 FlexiPage (deployed through Sprint 10)

### Pending Actions
- Assign NBA_V2_Demo FlexiPage (Setup > Object Manager > Opportunity > Lightning Record Pages)
- Not connected to NBA Queue yet (standalone record page UX)
- Share data contract with Data Engineering for Account_Scoring__c pipeline
- Merge feature branch to master

## Essential Commands

### Testing
- `npm test` -- Run all LWC unit tests
- `npm run test:unit:watch` -- Watch mode
- `npm run test:unit:coverage` -- Coverage reports
- `sf apex test run` -- Run Apex tests in org
- `sf apex test run -t <TestClassName>` -- Run specific Apex test
- `npm test -- --testPathPattern=<componentName>` -- Run specific LWC test

### Linting & Formatting
- `npm run lint` -- Lint all JS files
- `npm run prettier` -- Format all files
- `npm run prettier:verify` -- Check formatting

### Deployment
- `sf project deploy start` -- Deploy to default org
- `sf project deploy start -m ApexClass:MyClass` -- Deploy specific metadata
- `sf project retrieve start` -- Retrieve from org

## Development Best Practices

### Salesforce Specific
- **Feature branches**: `feature/<name>`, `bugfix/<name>`, `hotfix/<name>`
- **Permission sets over profiles** for access management
- **75%+ Apex test coverage** required for production
- **Bulkification**: Always write Apex for 200+ records
- **Governor limits**: Use collections to minimize SOQL/DML
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
