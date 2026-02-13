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
