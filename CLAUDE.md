# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working Rules for Claude Agents

**IMPORTANT**: All Claude agents working on this project must follow these rules:

### 1. Git Version Control
- Make frequent, atomic commits with detailed, descriptive commit messages
- Each commit message should clearly explain **what** changed and **why**
- Commit messages should follow best practices (clear subject line, detailed body when needed)
- Maintain good version control hygiene throughout development

### 2. Update CLAUDE.md for New Features
As you develop new features, update this file with:
- New architectural patterns or design decisions
- Important implementation details that aren't immediately obvious
- New commands, scripts, or tools added to the project
- Integration points between components
- Any context that future agents/conversations need to understand the codebase

### 3. Update CLAUDE.md During Troubleshooting
When debugging issues, document in this file:
- **The Problem**: Clear description of the issue encountered
- **Attempted Solutions**: List what has been tried (both successful and unsuccessful)
- **Root Cause**: Document the underlying cause once identified
- **Final Solution**: Record what ultimately fixed the issue
- **Prevention**: Note how to avoid this issue in the future

This creates a living knowledge base that prevents repeating past mistakes and helps future agents quickly understand the project context.

### 4. Deployment Target
- **Primary deployment org**: VSCode org (configured in VS Code Salesforce extensions)
- Always deploy to the VSCode org unless explicitly instructed otherwise
- Use `sf project deploy start` to deploy to the default org
- Verify org context with `sf org display` before deploying

### 5. Context Management & Conversation Restarts
- **Monitor token usage**: When approaching context limits (~150k-180k tokens used)
- **Before restarting**: Update CLAUDE.md with current state:
  - Document any in-progress work
  - Note decisions made and rationale
  - List next steps or pending tasks
  - Update troubleshooting section if debugging
- **After restart**: New agent should read CLAUDE.md first to understand full project context
- **Purpose**: Prevents context rot and maintains continuity across conversation sessions

### 6. Salesforce Metadata Context via MCP
- **MCP Server**: Salesforce DX MCP server is configured in `.mcp.json` for metadata access
- **Before writing SFDC code**: Query object metadata via MCP tools to:
  - Verify correct field API names and labels
  - Get accurate picklist values for test data
  - Review validation rules to ensure code compliance
  - Understand object relationships and dependencies
- **When to query metadata**:
  - Before creating test classes (get real field names and values)
  - Before writing triggers or Apex classes that reference objects
  - Before creating LWC components that use Salesforce data
  - When unsure about field types or picklist options
- **Available toolsets**: `metadata`, `data`, `orgs`, `users`
- **Purpose**: Ensures accurate code that respects org configuration and reduces errors

## Project Status

**Last Updated**: 2026-02-13

### NBA V2 - Next Best Action System

**Project purpose**: Deterministic sales workflow orchestration system for Account Executives. Evaluates CRM context, generates candidate actions, and serves a prioritized "Next Best Action" in a guided flow.

### Feature 1: Account Scoring Data Layer ✅ (deployed to vscodeOrg)

**Branch**: `feature/account-scoring-data-layer`

**What was built:**
- Custom object `Account_Scoring__c` - stores latest ML scoring output per Account (1 record per Account)
- 6 custom fields: Account lookup, Entity_ID (external key), 2 Percent scores, 2 LongTextArea drivers
- 3 validation rules: Entity ID match (defense-in-depth), 2 percent range validators
- 2 surfacing fields on Account: `Account_Prob_Payroll_Conversion__c`, `Account_Prob_Tier_Upgrade__c`
- Custom tab for Account_Scoring__c
- 2 permission sets: `NBA_Account_Scoring_Admin` (CRUD), `NBA_Account_Scoring_Read` (read-only)
  - Both include full FLS, object permissions, and tab visibility

**Architecture decisions:**
- **Lookup(Account)** over Master-Detail: merge safety, pipeline flexibility, no cascade-delete risk
- **1:1 enforced via Entity_ID__c uniqueness**: mirrors Account.Entity_ID__c (External ID + Unique)
- **Account surfacing fields deferred**: Percent fields exist on Account but sync is deferred. The NBA engine queries Account_Scoring__c directly via indexed `Account__c` lookup - no duplication needed. Sync flow only needed if Opportunity formulas or reporting require Account-level scores later.
- **deleteConstraint=Restrict**: prevents Account deletion while scoring record exists (no orphans)

**Pending actions:**
- Share data contract with Data Engineering for pipeline implementation
- Merge feature branch to master + push to GitHub

**Data contract key points:**
- Upsert key: `Account_Scoring__c.Entity_ID__c`
- Pipeline converts probabilities from 0-1 to 0-100 before load
- Pipeline populates `Account__c` by matching `company_uuid` to `Account.Entity_ID__c`
- No orphan records: skip rows where Account match fails

### Setup Complete ✅

All project infrastructure and tooling has been configured.

**Completed Setup:**
- ✅ Git repository initialized and pushed to GitHub (https://github.com/Wiltron289/GTM_OS)
- ✅ Comprehensive working rules established (6 rules documented above)
- ✅ Development best practices defined
- ✅ Salesforce MCP server configured and verified working
  - Connected to vscodeOrg (lwilson@joinhomebase.com.uat)
  - Toolsets enabled: metadata, data, orgs, users
- ✅ GitHub CLI installed and authenticated
- ✅ All documentation complete and committed

**Current State:**
- **Active Branch**: `feature/nba-v2-demo-lwc` (branched from `feature/account-scoring-data-layer`)
- **Deployment Target**: vscodeOrg (Homebase UAT sandbox)
- **Status**: Feature 2 (Demo LWC) deployed to vscodeOrg, all 13 tests passing

### Feature 2: NBA V2 Demo LWC UX ✅ (deployed to vscodeOrg, tests passing)

**Branch**: `feature/nba-v2-demo-lwc`

**What was built:**
- 16 Lightning Web Components implementing the product designer's NBA V2 prototype
- 1 Apex controller (`NbaDemoController.cls`) with centralized data loading pattern
- 1 Apex test class (`NbaDemoControllerTest.cls`) - 13 tests, all passing
- 1 FlexiPage (`NBA_V2_Demo`) - dedicated demo record page for Opportunity

**Component Architecture:**
```
nbaDemoWorkspace (parent - manages layout, data, tabs)
├── nbaDemoAlertBanner (meeting reminder banner)
├── nbaDemoHeader (breadcrumb, MRR badge, Close %, Email Now, Snooze)
├── nbaDemoInsightsPanel (Why This Account - expandable, Account_Scoring__c drivers)
├── Overview Tab:
│   ├── nbaDemoAccountDetails (employees, locations, plan, tier)
│   ├── nbaDemoPayrollStatus (type, next step, check status)
│   ├── nbaDemoQuotaProgress (SVG donut chart, hardcoded $5k target)
│   └── nbaDemoSalesEngagement (metrics + AI insight banner)
├── nbaDemoUpdatesTab (embeds Opportunity_Stage_Progression_Screen_Flow)
├── nbaDemoPayrollTab (payroll readiness, progression, check info)
├── nbaDemoProductsTab (product table + Product Wizard flow embed)
├── nbaDemoContactsTab (contact cards from OpportunityContactRole + Account Contacts)
├── nbaDemoAdminTab (field updates, SLA, history)
├── nbaDemoSidebar (notes & activity panel)
├── nbaDemoEmailModal (custom email composer)
└── nbaDemoSnoozeDropdown (visual only)
```

**Data Flow Pattern:**
- Single Apex call `getPageData(oppId)` returns `PageDataWrapper` with ALL data
- Parent `nbaDemoWorkspace` loads data via `@wire`, passes to children via `@api` properties
- Child components are pure display - zero Apex calls
- 8 SOQL queries total (Opp+Account, Account_Scoring__c, OCR Contacts, Account Contacts, Products, Events, Tasks, Aggregate)

**Key Architecture Decisions:**
- **Single parent LWC** over multiple FlexiPage components: full control over two-column layout
- **Centralized data loading**: one Apex call reduces wire calls, keeps children stateless
- **Screen flow embedding**: reuses existing `Opportunity_Stage_Progression_Screen_Flow` and `Opportunity_Screen_Flow_Opportunity_Product_Wizard`
- **SVG donut chart**: custom SVG with `stroke-dasharray` - no external dependencies
- **FlexiPage template**: `flexipage:recordHomeTwoColEqualHeaderTemplateDesktop` with component in header region (full width)
- **Quota uses Amount field**: `MRR__c` is a formula field (not writable in tests), so quota aggregates `SUM(Amount)` instead

**Known Field Issues (discovered during deploy):**
- `MRR__c` is a Formula(Currency) on Opportunity - queryable but NOT writable
- `MRR_Potential__c` does NOT exist on Opportunity - removed from controller
- `Source__c` is a required Picklist on Opportunity - must be set in test data (value: 'N/A')
- Opportunity Name may be overwritten by org triggers/flows - don't query by Name in tests

**Files Created (69 total):**
- `classes/NbaDemoController.cls` + meta (~690 lines)
- `classes/NbaDemoControllerTest.cls` + meta (~440 lines)
- `flexipages/NBA_V2_Demo.flexipage-meta.xml`
- 16 LWC components × 4 files each = 64 files under `lwc/nbaDemo*`

**Commits on branch:**
1. `feat: Add NbaDemoController Apex class for NBA V2 demo LWC`
2. `feat: Add 16 NBA V2 demo LWC components`
3. `feat: Add NbaDemoControllerTest and NBA V2 Demo FlexiPage`
4. `fix: Resolve deploy issues - remove MRR_Potential__c, fix snooze HTML, add Source__c to tests`
5. `docs: Update CLAUDE.md with Feature 2 (NBA V2 Demo LWC) status and troubleshooting`
6. `fix: Resolve Apex test failures - resilient Opp queries and Comparable sort`
7. `docs: Update CLAUDE.md - mark Feature 2 tests as passing, add resolved troubleshooting`
8. `fix: Correct wire data property names in nbaDemoWorkspace`
9. `fix: Resolve field mapping bugs, contacts query, and payroll tab layout`

**Demo data created in org (not in repo - org data only):**
- 3 `Account_Scoring__c` records for: Bluegrass Pools (7%/43%), Focus Group Services LLC (6%/31%), Makenna Koffee Franchise (5%/30%)
- Best demo Opportunity: **Bluegrass Pools** (`006Po000011vxwjIAA`) - 179 emp, 10 locations, aio tier, $2,421, 4 tasks, 3 events, contact, product, scoring record

**Bugs fixed (commit 9):**
- **Payroll Tab JS property mismatches**: `inceptionSwitcher` should be `inceptionOrSwitcher`, `currentNextStep` mapped to nonexistent field (now `nextStepLabel`), `nextStep` mapped to wrong field (now `nextStepLabel`)
- **Contacts Tab data access bug**: `this.contactsData?.contacts` tried to access `.contacts` on what was already an array. Changed to `Array.isArray(this.contactsData) ? this.contactsData : []`
- **Contacts query only hit OpportunityContactRole**: Now also queries all Account contacts (deduped by ContactId), so Contact tab shows both OCR contacts and Account contacts
- **Payroll tab layout restructured**: Changed from 4-column grid to 2-pair label-value layout matching prototype, added Admin Link and Check Console Link to Progression section

**Pending actions / Next steps (Sprint 2 - UX Refinement):**

#### Issue 1: Notes Not Showing in Sidebar
- **Problem**: Notes tab shows "No notes yet" even after creating notes. The `saveNote()` method creates `ContentNote` (ContentDocument) records, but `buildSidebar()` only queries Tasks with `Subject.startsWithIgnoreCase('Note')` — it never queries actual ContentNote records.
- **Root Cause**: Mismatch between write path (ContentNote) and read path (Task-based "notes")
- **Fix Plan**:
  1. In `NbaDemoController.buildSidebar()`, add a SOQL query for `ContentDocumentLink WHERE LinkedEntityId = :oppId` joined to `ContentDocument` to get `ContentNote` records
  2. Map `ContentNote.Title`, `ContentNote.Content`, `ContentNote.CreatedDate`, `ContentNote.CreatedBy.Name` into `NoteData` wrapper objects
  3. Merge ContentNote-based notes with any Task-based notes, sort by date descending
  4. After `saveNote()` succeeds in the sidebar JS, call `refreshApex` or imperative reload to re-fetch data so the new note appears immediately
- **Files**: `NbaDemoController.cls` (buildSidebar), `nbaDemoSidebar.js` (refresh after save), `NbaDemoControllerTest.cls` (verify ContentNote in tests)

#### Issue 2: Products Tab Redundant Header
- **Problem**: "Current Opportunity Details" header/description/amounts appear twice — once from the LWC HTML and again from the embedded screen flow `Opportunity_Screen_Flow_Opportunity_Product_Wizard` which renders its own header
- **Root Cause**: The LWC template has a static "Current Opportunity Details" section AND the flow also renders one
- **Also**: `productsData` has the same `.products` access bug as contacts — workspace passes `data.products` (already an array) but the products tab accesses `this.productsData?.products` (returns undefined). The static LWC amounts show $0.00 because `currentAmount` and `attainedAmount` don't exist on the array.
- **Fix Plan**:
  1. Remove the static LWC "Current Opportunity Details" header, description, and amount row from `nbaDemoProductsTab.html` — let the flow handle that display
  2. Fix the products data access: change `this.productsData?.products` to just `this.productsData` (same pattern as contacts fix)
  3. Keep the products table from the LWC (above the flow) so users see products without starting the flow
  4. Pass `Amount` and `Attained_Amount__c` from Apex in a products wrapper if needed, OR just remove the amounts section since the flow shows it
- **Files**: `nbaDemoProductsTab.html`, `nbaDemoProductsTab.js`

#### Issue 3: Email Modal — Template Picker
- **Problem**: No way to select/insert an email template when composing email
- **Fix Plan**:
  1. Add new Apex method `getEmailTemplates()` that queries `EmailTemplate WHERE IsActive = true` (or a filtered set for NBA templates)
  2. Add a `lightning-combobox` for template selection above the Subject field in `nbaDemoEmailModal.html`
  3. When a template is selected, populate Subject and Body from the template (or pass `templateId` to the existing `sendEmail` method which already accepts it)
  4. Add "None" as default template option
- **Files**: `NbaDemoController.cls` (new method), `nbaDemoEmailModal.js`, `nbaDemoEmailModal.html`

#### Issue 4: Email Modal — Larger Body Section
- **Problem**: Email body textarea is too small by default
- **Root Cause**: `style="min-height: 200px;"` on `lightning-textarea` doesn't work reliably in LWC — inline styles on standard base components are limited
- **Fix Plan**:
  1. Add CSS in `nbaDemoEmailModal.css` targeting the textarea: `.email-body-area { --slds-c-textarea-sizing-min-height: 300px; }` or use a wrapper class with min-height
  2. Alternatively, use a plain `<textarea>` HTML element instead of `lightning-textarea` for full styling control
- **Files**: `nbaDemoEmailModal.css`, `nbaDemoEmailModal.html`

#### Issue 5: Email Modal — Contacts Not in To Dropdown
- **Problem**: "To" combobox shows no contact options
- **Root Cause**: Same array-vs-wrapper bug. Workspace passes `contacts={contactsData}` where `contactsData` is already the contacts array. But `nbaDemoEmailModal.js` accesses `this.contacts?.contacts?.length` and `this.contacts.contacts.map(...)` — `.contacts` on an array is `undefined`.
- **Fix Plan**:
  1. In `nbaDemoEmailModal.js`, change `this.contacts?.contacts` to just `this.contacts` (or `Array.isArray(this.contacts) ? this.contacts : []`)
  2. Update `connectedCallback`, `contactOptions` getter, and `selectedContactName` getter accordingly
- **Files**: `nbaDemoEmailModal.js`

#### Issue 6: Admin Tab — "Same Lane" Badge Should Not Show
- **Problem**: Admin tab always shows "Same Lane ✓" badge next to the owner name. This was a misread of the prototype — the prototype owner was named "Sierra Lane", not a badge.
- **Root Cause**: `nbaDemoAdminTab.js` has `get isSameLane() { return true; // demo placeholder }` which is always true
- **Fix Plan**:
  1. Remove the `isSameLane` getter from `nbaDemoAdminTab.js`
  2. Remove the `<template if:true={isSameLane}><span class="same-lane-badge">Same Lane ✓</span></template>` from `nbaDemoAdminTab.html`
  3. Remove `.same-lane-badge` CSS from `nbaDemoAdminTab.css`
- **Files**: `nbaDemoAdminTab.js`, `nbaDemoAdminTab.html`, `nbaDemoAdminTab.css`

#### Issue 7: MRR Badge Should Show Opp Amount
- **Problem**: Header badge shows "$0 MRR" because `MRR__c` is a formula field that's null for this Opp. Should display Opp Amount instead.
- **Fix Plan**:
  1. In `NbaDemoController.buildHeader()`, change: `h.mrr = opp.Amount != null ? opp.Amount : (opp.MRR__c != null ? opp.MRR__c : 0);` — use Amount as primary, MRR as fallback
  2. In `nbaDemoHeader.js`, update `formattedMrr` to display as `$X,XXX MRR` with proper number formatting (toLocaleString)
- **Files**: `NbaDemoController.cls` (buildHeader), `nbaDemoHeader.js`

#### Issue 8: Collapsible Section Headers
- **Problem**: All section headers should be collapsible (click to expand/collapse content)
- **Scope**: Affects Account Details, Payroll Status, Quota Progress, Sales Engagement, Payroll tab sections (Current Next Step, Progression, Check Info, Activity), Admin tab sections (Field Updates, SLA Info, History, Audit), Insights panel, and Sidebar sections
- **Fix Plan**:
  1. Create a reusable pattern: `@track` boolean per section, toggle on header click
  2. Add chevron icon (▸/▾) to each section header that rotates on toggle
  3. Wrap section content in `<template if:true={sectionExpanded}>` for show/hide
  4. Default all sections to expanded (`true`) so nothing changes on first load
  5. Components to update:
     - `nbaDemoAccountDetails` — wrap metrics grid
     - `nbaDemoPayrollStatus` — wrap status list
     - `nbaDemoQuotaProgress` — wrap quota content
     - `nbaDemoSalesEngagement` — wrap metrics + AI insight
     - `nbaDemoPayrollTab` — each section (Current Next Step, Progression, Check Info, Activity)
     - `nbaDemoAdminTab` — each section (Field Updates, SLA Info, History, Audit)
     - `nbaDemoInsightsPanel` — already has expand/collapse behavior, verify it works
  6. Add shared CSS classes for the collapsible pattern: `.section-header-collapsible`, `.chevron`, `.chevron-expanded`
- **Files**: All overview card components JS/HTML, `nbaDemoPayrollTab`, `nbaDemoAdminTab`, shared CSS patterns

#### Priority Order for Implementation:
1. **Issue 5** (Email contacts dropdown) — quick fix, same pattern as contacts tab fix
2. **Issue 6** (Remove Same Lane badge) — quick delete
3. **Issue 7** (MRR → Amount) — quick Apex + JS fix
4. **Issue 2** (Products redundancy + data access) — moderate, remove HTML + fix JS
5. **Issue 4** (Email body size) — quick CSS
6. **Issue 1** (Notes) — moderate, new SOQL + refresh logic
7. **Issue 3** (Email templates) — moderate, new Apex method + UI
8. **Issue 8** (Collapsible headers) — largest scope, touches many components

#### Additional Items (from previous sprint):
- **Assign NBA_V2_Demo FlexiPage** — Currently unassigned; activate via Setup > Object Manager > Opportunity > Lightning Record Pages > NBA V2 Demo > Activation
- **Not connected to NBA Queue** — This is standalone record page UX, not wired to an action queue yet

### LWC Repo Structure Convention

For future LWC development, use this naming convention:
- `lwc/nba*` - Production NBA components (e.g., `nbaActionCard`, `nbaWorkspace`)
- `lwc/nbaDemo*` - Demo/prototype components (e.g., `nbaDemoActionCard`)
- This keeps demo UX and production components clearly separated in the repo.

**Note for New Agents:**
If you're a new agent picking up this project, all context is preserved in this file. Review the Working Rules, Development Best Practices, and Feature 1 architecture decisions above before starting work.

## Development Best Practices

**All agents must follow these practices to ensure consistency and quality:**

### Git & Branching Strategy
- **Use feature branches**: Never work directly on `master`/`main`
  - Branch naming: `feature/<feature-name>`, `bugfix/<issue-name>`, `hotfix/<critical-fix>`, `refactor/<component-name>`
  - Examples: `feature/account-management`, `bugfix/login-validation`
- **Small, focused commits**: Commit early and often with single-purpose changes
- **Pull Request workflow**: Create PRs even when working solo - documents the "why" behind changes

### Salesforce Development Workflow
- **Scratch orgs are disposable**: Create new scratch orgs for each feature to test in isolation
- **Always retrieve before editing**: Run `sf project retrieve start` before modifying metadata through the org UI
- **Avoid clicking in Setup**: Prefer metadata-based changes (trackable in git) over UI modifications
- **Test coverage requirement**: Maintain 75%+ Apex test coverage (required for production deployments)
- **Permission sets over profiles**: Use permission sets for access management - easier to manage and test
- **Custom metadata for config**: Prefer custom metadata types over custom settings when possible

### Code Organization & Quality
- **Trigger handler pattern**: Keep trigger logic minimal, delegate to dedicated handler classes
- **Bulkification**: Always write Apex code with bulk operations in mind (200+ records)
- **SOQL/DML limits**: Be mindful of governor limits - use collections to minimize queries/DML statements
- **Mock external callouts**: Always mock HTTP callouts in Apex tests using `Test.setMock()`
- **Use TODO comments**: Mark future work with `// TODO:` comments for tracking

### Testing Standards
- **LWC Tests**:
  - Mock all wire adapters and imported Apex methods
  - Test user interactions and component lifecycle
  - Aim for 80%+ code coverage
- **Apex Tests**:
  - Use `@isTest` annotation on test classes
  - Create test data within test methods (don't rely on existing org data)
  - Use `Test.startTest()` and `Test.stopTest()` to reset governor limits
  - Assert expected outcomes - every test should have assertions
  - Use `@testSetup` for shared test data across test methods

### Code Review & Quality Checks
- **Run checks before commit**:
  - `npm run lint` - Check code style
  - `npm test` - Run all LWC tests
  - `npm run prettier:verify` - Verify formatting
- **Pre-commit hooks**: Trust the automated checks - they catch common issues
- **Static code analysis**: Use Salesforce CLI Scanner for security/quality issues
  - Install: `sf plugins install @salesforce/sfdx-scanner`
  - Run: `sf scanner run --target "force-app/**/*.cls"`

### Communication & Documentation
- **Descriptive commit messages**: Explain the "why" not just the "what"
- **Update CLAUDE.md**: Keep this file current with architectural decisions and patterns
- **Code comments**: Only add comments when the "why" isn't obvious from the code itself
- **API versioning**: Keep components on the same API version unless there's a specific reason

## Project Overview

This is a Salesforce DX project named **GTM_OS** using Salesforce API version 65.0. The project follows the standard Salesforce DX structure with metadata stored in `force-app/main/default/`.

## Essential Commands

### Testing
- `npm test` - Run all Lightning Web Component (LWC) unit tests via sfdx-lwc-jest
- `npm run test:unit:watch` - Run tests in watch mode for active development
- `npm run test:unit:debug` - Run tests in debug mode
- `npm run test:unit:coverage` - Generate test coverage reports
- `sf apex test run` - Run Apex tests in the connected org

### Linting and Formatting
- `npm run lint` - Lint all Aura and LWC JavaScript files
- `npm run prettier` - Format all files (Apex classes, triggers, LWC, Aura, XML, JSON, etc.)
- `npm run prettier:verify` - Check if files are properly formatted without modifying them

### Salesforce Deployment
- `sf org create scratch -f config/project-scratch-def.json -d -a <alias>` - Create a scratch org
- `sf project deploy start` - Deploy source to the default org
- `sf project deploy start -m ApexClass:MyClass` - Deploy specific metadata
- `sf project retrieve start` - Retrieve source from the default org
- `sf org open` - Open the default org in a browser

### Running Individual Tests
- For LWC: `npm test -- --testPathPattern=<componentName>` - Run tests for a specific LWC component
- For Apex: `sf apex test run -t <TestClassName>` - Run a specific Apex test class

## Troubleshooting Log

### Permission Set FLS on Required Fields (2026-02-13)
- **Problem**: Permission sets failed to deploy with "You cannot deploy to a required field" error
- **Root Cause**: Salesforce does not allow field-level security (FLS) to be set on required fields (`required=true`) or required lookup fields. These are automatically visible to users with object access.
- **Fix**: Remove `<fieldPermissions>` entries for required fields (e.g., `Entity_ID__c`, `Account__c`) from permission set metadata
- **Prevention**: When creating permission sets, never include FLS entries for fields marked `required=true` in their field definition

### NbaDemoControllerTest "List has no rows" (2026-02-13) ✅ RESOLVED
- **Problem**: All test methods fail with `System.QueryException: List has no rows for assignment to SObject` when querying `SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp'`
- **Root Cause**: UAT org has triggers/flows that rename Opportunities on insert. The query-by-Name pattern breaks.
- **Fix**: Changed all 12 test queries from `WHERE Name = 'Test NBA Demo Opp'` to `WHERE Account.Name = 'Test Demo Account' AND StageName = 'Prospecting'`. Also relaxed the assertion on `opportunityName` to `assertNotEquals(null, ...)`.
- **Prevention**: In this org, never query test Opportunities by Name. Use Account.Name + StageName or store the Id in a class-level variable.

### ActivityData sort() ListException (2026-02-13) ✅ RESOLVED
- **Problem**: `System.ListException: One or more of the items in this list is not Comparable` at `NbaDemoController.buildSidebar: line 582`
- **Root Cause**: `ActivityData` inner class called `sort()` but did not implement `Comparable`
- **Fix**: Added `implements Comparable` and `compareTo()` method to `ActivityData` (descending by `activityDate`, null-safe)
- **Prevention**: Any inner class used in a `List.sort()` call must implement `Comparable` with a `compareTo(Object)` method

### Payroll Tab JS Property Name Mismatches (2026-02-13) ✅ RESOLVED
- **Problem**: Multiple fields on the Payroll tab showing "—" even when data exists (e.g., Inception/Switcher has "Switcher" in org but displayed as "—")
- **Root Cause**: JS getter property names didn't match Apex `@AuraEnabled` property names: `inceptionSwitcher` vs `inceptionOrSwitcher`, `currentNextStep` (nonexistent) vs `nextStepLabel`, `nextStep` vs `nextStepLabel`
- **Fix**: Corrected all JS getters to match exact Apex property names
- **Prevention**: Always verify JS property access matches the `@AuraEnabled` property name in the Apex wrapper class exactly

### Contacts Tab Empty (2026-02-13) ✅ RESOLVED
- **Problem**: Contacts tab showed "No contacts associated with this opportunity" despite OCR and Account contacts existing
- **Root Cause**: Two bugs: (1) `nbaDemoContactsTab.js` accessed `this.contactsData?.contacts` but `contactsData` was already the contacts array (not a wrapper), so `.contacts` returned `undefined`. (2) Only OpportunityContactRole was queried - Account had 19 contacts but only 1 OCR.
- **Fix**: (1) Changed getter to `Array.isArray(this.contactsData) ? this.contactsData : []`. (2) Expanded `buildContacts` to also query `Contact WHERE AccountId = :accountId AND Id NOT IN :seenContactIds`
- **Prevention**: When passing data from parent to child, verify the shape of the data at each level. When `@wire` returns an array, don't try to access properties on it.

### Wire Property Name Mismatch (2026-02-13) ✅ RESOLVED
- **Problem**: `Cannot read properties of undefined (reading 'accountName')` in `nbaDemoHeader` at runtime
- **Root Cause**: `nbaDemoWorkspace.js` wire handler read `data.headerData`, `data.accountData`, etc. but the Apex `PageDataWrapper` uses `header`, `account`, `payrollStatus`, etc. All child components received `undefined`.
- **Fix**: Changed all property mappings in the wire handler to match Apex names (e.g., `data.header` not `data.headerData`)
- **Prevention**: Always verify `@AuraEnabled` property names in the Apex wrapper match the JS wire handler property access

### LWC HTML Ternary Operators (2026-02-13)
- **Problem**: `nbaDemoSnoozeDropdown` deploy failed with `LWC1058: Invalid HTML syntax: unexpected-character-in-attribute-name`
- **Root Cause**: LWC templates do NOT support JavaScript ternary operators (`? :`) in HTML attribute values. The expression `class={option.isCustom ? 'a' : 'b'}` is invalid.
- **Fix**: Pre-compute the CSS class string in JavaScript and pass it as a property (e.g., `className: 'option-label custom'`)
- **Prevention**: Never use ternary operators in LWC HTML template attributes. Always use computed getters or pre-computed properties.

## Project Architecture

### Directory Structure
```
force-app/main/default/
├── applications/      # Custom apps
├── aura/             # Aura components (legacy)
├── classes/          # Apex classes
├── contentassets/    # Static content assets
├── flexipages/       # Lightning page layouts
├── layouts/          # Page layouts
├── lwc/              # Lightning Web Components
├── objects/          # Custom objects and fields
├── permissionsets/   # Permission sets
├── staticresources/  # Static resources (JS libraries, CSS, images)
├── tabs/             # Custom tabs
└── triggers/         # Apex triggers
```

### Code Organization
- **Apex Classes**: Business logic, controllers, and utility classes go in `classes/`
- **Apex Triggers**: Database triggers go in `triggers/` - keep logic minimal, delegate to handler classes
- **LWC Components**: Each component has its own folder in `lwc/` with `.js`, `.html`, `.css`, and `.js-meta.xml` files
- **LWC Tests**: Test files are colocated with components as `<componentName>.test.js`

### Testing Patterns
- **LWC Tests**: Use Jest with `@salesforce/sfdx-lwc-jest`. Mock wire adapters and imported Apex methods. Test files run automatically on commit via lint-staged.
- **Apex Tests**: Write test classes with `@isTest` annotation. Follow Salesforce best practices: use `Test.startTest()` and `Test.stopTest()`, create test data in methods, assert expected outcomes.

### Code Quality
- **Pre-commit Hooks**: Husky runs lint-staged before each commit, which:
  - Formats all staged files with Prettier
  - Lints Aura/LWC JavaScript files with ESLint
  - Runs related LWC tests for changed components
- **ESLint Configuration**: Separate configs for Aura (with Locker Service rules), LWC, and Jest test files

### Scratch Org Configuration
The `config/project-scratch-def.json` defines the default scratch org setup:
- Developer Edition
- Lightning Experience enabled
- Configured for demo/development purposes

## Development Workflow

1. **Create or connect to an org**: Use `sf org create scratch` for new development or `sf org login web` for existing orgs
2. **Develop locally**: Create/modify metadata in `force-app/main/default/`
3. **Write tests**: Add Jest tests for LWC components and Apex test classes for Apex code
4. **Validate**: Run `npm run lint` and `npm test` before committing
5. **Deploy**: Use `sf project deploy start` to push changes to the org
6. **Commit**: Pre-commit hooks will automatically format, lint, and test your changes
