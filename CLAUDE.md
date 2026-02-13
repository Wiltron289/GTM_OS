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

### Feature 1: Account Scoring Data Layer ✅ (metadata complete, pending deploy)

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
- **Account surfacing via Percent fields** (not formula): SF formula fields cannot traverse to child records. Sync via Record-Triggered Flow (recommended) or pipeline-side Account update.
- **deleteConstraint=Restrict**: prevents Account deletion while scoring record exists (no orphans)

**Pending actions:**
- Deploy to vscodeOrg
- Build Account-to-Scoring sync mechanism (Record-Triggered Flow recommended)
- Share data contract with Data Engineering for pipeline implementation

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
- **Active Branch**: `feature/account-scoring-data-layer`
- **Deployment Target**: vscodeOrg (Homebase UAT sandbox)
- **Status**: Feature 1 metadata complete, ready for deploy

**Next Steps (after Feature 1 deploy):**
- Build Account Scoring sync flow (stamps scores onto Account fields)
- Start Feature 2: NBA Action object + engines
- Implement configurable cadence logic (Custom Metadata Types)
- Begin LWC UI based on Figma designs

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
