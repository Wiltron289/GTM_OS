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
