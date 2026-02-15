# NBA V2 Architecture

## Project Overview

**GTM_OS** - Salesforce DX project, API version 65.0. Deterministic sales workflow orchestration system for Account Executives. Evaluates CRM context, generates candidate actions, and serves a prioritized "Next Best Action" in a guided flow.

## Directory Structure

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

## LWC Naming Convention

- `lwc/nba*` - Production NBA components (e.g., `nbaActionCard`, `nbaWorkspace`)
- `lwc/nbaDemo*` - Demo/prototype components (e.g., `nbaDemoActionCard`)

---

## Feature 1: Account Scoring Data Layer

**Branch**: `feature/account-scoring-data-layer`

- Custom object `Account_Scoring__c` - stores latest ML scoring output per Account (1 record per Account)
- 6 custom fields: Account lookup, Entity_ID (external key), 2 Percent scores, 2 LongTextArea drivers
- 3 validation rules: Entity ID match (defense-in-depth), 2 percent range validators
- 2 surfacing fields on Account: `Account_Prob_Payroll_Conversion__c`, `Account_Prob_Tier_Upgrade__c`
- 2 permission sets: `NBA_Account_Scoring_Admin` (CRUD), `NBA_Account_Scoring_Read` (read-only)

**Architecture decisions:**
- **Lookup(Account)** over Master-Detail: merge safety, pipeline flexibility, no cascade-delete risk
- **1:1 enforced via Entity_ID__c uniqueness**: mirrors Account.Entity_ID__c (External ID + Unique)
- **deleteConstraint=Restrict**: prevents Account deletion while scoring record exists (no orphans)

**Data contract:**
- Upsert key: `Account_Scoring__c.Entity_ID__c`
- Pipeline converts probabilities from 0-1 to 0-100 before load
- Pipeline populates `Account__c` by matching `company_uuid` to `Account.Entity_ID__c`

---

## Feature 2: NBA V2 Demo LWC

**Branch**: `feature/nba-v2-demo-lwc`

### Component Tree

```
nbaDemoWorkspace (parent - manages layout, data, tabs)
├── nbaDemoAlertBanner (meeting reminder banner)
├── nbaDemoHeader (breadcrumb, MRR badge, Close %, Email Now, SMS, Snooze)
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
├── nbaDemoSidebar (pill toggle: Notes | Activity | Messages)
│   └── nbaDemoConversationView (chat-style SMS thread)
├── nbaDemoEmailModal (custom email composer)
├── nbaDemoSmsModal (SMS composer via Mogli SMS)
└── nbaDemoSnoozeDropdown (visual only)
```

### Data Flow Pattern

- Single Apex call `getPageData(oppId)` returns `PageDataWrapper` with ALL data
- Parent `nbaDemoWorkspace` loads data via `@wire`, passes to children via `@api` properties
- Child components are pure display - zero Apex calls
- 9 SOQL queries total (Opp+Account, Account_Scoring__c, OCR Contacts, Account Contacts, Products, Events, Tasks, Aggregate, Mogli SMS)

### Key Architecture Decisions

- **Single parent LWC** over multiple FlexiPage components: full control over two-column layout
- **Centralized data loading**: one Apex call reduces wire calls, keeps children stateless
- **Screen flow embedding**: reuses existing `Opportunity_Stage_Progression_Screen_Flow` and `Opportunity_Screen_Flow_Opportunity_Product_Wizard`
- **SVG donut chart**: custom SVG with `stroke-dasharray` - no external dependencies
- **FlexiPage template**: `flexipage:recordHomeTwoColEqualHeaderTemplateDesktop` with component in header region (full width)
- **Quota uses Amount field**: `MRR__c` is a formula field (not writable in tests), so quota aggregates `SUM(Amount)` instead

### Known Field Issues

- `MRR__c` is a Formula(Currency) on Opportunity - queryable but NOT writable
- `MRR_Potential__c` does NOT exist on Opportunity - removed from controller
- `Source__c` is a required Picklist on Opportunity - must be set in test data (value: 'N/A')
- Opportunity Name may be overwritten by org triggers/flows - don't query by Name in tests

---

## Design Token System

All design tokens defined as CSS custom properties on `nbaDemoWorkspace :host`. Child components reference via `var(--token-name, fallback)`. Tokens cascade through Shadow DOM.

**Token categories:**
- `--nba-text-{900/700/500/400/300}` -- Slate text scale
- `--nba-blue-{50/100/200/500/600/700}` -- Primary/brand colors
- `--nba-emerald-{50/500/600}` -- Success/positive states
- `--nba-amber-{50/100/500/700/800}` -- Warning states
- `--nba-purple-{50/100/600/700/900}` -- AI/special elements
- `--nba-indigo-{50/100/600/900}` -- Insights/accent
- `--nba-bg-{page/card/hover}`, `--nba-border`, `--nba-border-light`
- `--nba-shadow-sm`, `--nba-shadow`, `--nba-radius-{sm/default/lg/full}`
- `--nba-font-family` -- System font stack (`ui-sans-serif, system-ui, ...`)

---

## Reusable Patterns

### Collapsible Section Pattern
Each component uses `@track sectionExpanded = true` with `toggleSection()` handler. Chevron icon (`utility:chevrondown` / `utility:chevronright`) positioned left of header text. Content wrapped in `<template if:true={sectionExpanded}>`. CSS class `.collapsible-header` for cursor/flex layout.

### Dropdown Close-on-Click-Outside
On open: register a `{ once: true }` click listener on `document` via `setTimeout(..., 0)` (deferred to avoid capturing the opening click). On item select: call `event.stopPropagation()` to prevent the document listener from firing, then close manually. The `{ once: true }` option auto-removes the listener.

### SLDS Icon Color Pattern
- `variant="inverse"` on `lightning-icon` is the reliable way to get white icons on dark backgrounds
- CSS variables `--sds-c-icon-color-foreground-default` / `--sds-c-icon-color-foreground` work for custom colors but need triple declaration (both vars + `color`) for reliability across SLDS versions

### Quota Donut SVG Pattern
- CSS `transform: rotate(-90deg)` on SVG positions arc start at 12 o'clock
- Do NOT also use `stroke-dashoffset = CIRCUMFERENCE * 0.25` -- that creates a double-rotation
- Two-layer approach: blue arc = combined total (bottom), green arc = closedWon (top)
- `stroke-linecap="round"` gives rounded arc endpoints
- Only render green arc when `hasClosedWon` to avoid phantom dot at zero

### Messaging.SingleEmailMessage Pattern
- When using `setTemplateId()`: do NOT also call `setSubject()` or `setHtmlBody()` -- Salesforce will use the raw values instead of processing the template merge fields
- `setTargetObjectId(contactId)` resolves Contact/Lead merge fields
- `setWhatId(oppId)` resolves Opportunity/Account merge fields AND links the activity Task to the Opportunity
- `setSaveAsActivity(true)` creates a Task record -- it needs `WhatId` to appear on the related record's activity timeline

---

## Mogli SMS Architecture

- **Namespace**: `Mogli_SMS`
- **Message object**: `Mogli_SMS__SMS__c` -- stores all SMS/MMS records, has lookups to Contact, Opportunity, Account (non-namespaced `Account__c`)
- **Template object**: `Mogli_SMS__SMS_Template__c` -- `Mogli_SMS__Name__c` (unique name), `Mogli_SMS__Text__c` (body)
- **Gateway object**: `Mogli_SMS__Gateway__c` -- 38 active Telnyx gateways, filtered by `Mogli_SMS__Inactive__c = false`
- **Contact fields**: `Mogli_SMS__Mogli_Number__c` (SMS phone number), `Mogli_SMS__Mogli_Opt_Out__c` (opt-out flag)
- **Delivery**: Insert `SMS__c` with `Direction__c = 'Outgoing'` and `Status__c = 'Queued'` -> Mogli's managed package triggers pick up queued records and handle Telnyx delivery
- **Activity linking**: SMS records link to Opportunity via `Mogli_SMS__Opportunity__c` lookup (NOT Task/WhatId like email)

**Direction values:**
- `'Outgoing'` -- correct value for programmatic outbound SMS
- `'Incoming'` -- inbound SMS from contacts (set by Mogli's receive webhook)
- Never use `'Outbound'` -- Mogli ignores it

**Org-specific notes:**
- `Account__c` on `Mogli_SMS__SMS__c` is **non-namespaced** (created manually) -- do NOT use `Mogli_SMS__Account__c`
- Mogli auto-populates `Mogli_Number__c` from Contact's `Phone` field via trigger
- `AuraHandledException.getMessage()` returns "Script-thrown exception" in test context -- must call `setMessage()` explicitly

---

## Trigger Architecture (Phase 4)

### Overview

Three triggers create/update NBA actions in real-time:

```
                    ┌──────────────────────────────────────┐
                    │        Trigger Framework             │
                    ├──────────┬──────────┬────────────────┤
                    │ Opp      │ Event    │ Task           │
                    │ (async)  │ (sync)   │ (sync)         │
                    └────┬─────┴────┬─────┴───────┬────────┘
                         │          │             │
                    ┌────▼─────┐    │        ┌────▼────────┐
                    │Queueable │    │        │Context Upd  │
                    │Signal→   │    │        │Auto-Complete│
                    │Create→   │    │        └─────────────┘
                    │Promote   │    │
                    └──────────┘    │
                              ┌─────▼──────────┐
                              │TimeBound Action │
                              │createTimeBound  │
                              │updateTimeBound  │
                              │cancelTimeBound  │
                              └────────────────┘
```

### Execution Models

| Trigger | Model | Why | SOQL Budget |
|---------|-------|-----|-------------|
| Opportunity | Queueable (async) | Full signal eval ~12 SOQL | Fresh limits in async |
| Event | Synchronous | 2-3 SOQL + 1-2 DML | Safe in trigger |
| Task | Synchronous | 1-2 SOQL + 1-2 DML | Safe in trigger |

### Recursion Prevention

`NbaTriggerContext` provides per-object static boolean guards:
- `hasOppHandlerRun()` / `setOppHandlerRun()`
- `hasEventHandlerRun()` / `setEventHandlerRun()`
- `hasTaskHandlerRun()` / `setTaskHandlerRun()`
- `resetAll()` -- `@TestVisible` for test reset between scenarios

Reset per transaction. Prevents re-entry when NBA_Queue__c DML triggers downstream cascades.

### Time-Bound Actions (Layer 1)

Events trigger Layer 1 time-bound actions:
- **Created**: Event insert with `WhatId = Opportunity`, `StartDateTime` within 24h
- **Updated**: Event StartDateTime changes → update `DueAt__c`
- **Cancelled**: Event deleted → expire action (`Status = 'Expired'`)
- **UniqueKey**: `'V2|' + oppId + '|Meeting|' + eventId`

### Task Context Updates

Tasks DON'T create new actions. They update existing ones:
1. `LastEvaluatedAt__c = now()` on all active actions for the Opp
2. Call tasks: increment `Attempt_Count_Today__c`, set `Last_Attempt_Method__c`
3. Connected calls (Connected-DM/GK): auto-complete First Touch / Re-engage / Follow Up actions

### LWC Polling

`nbaDemoWorkspace` polls `getActiveAction()` every 60 seconds in App Page mode. Silent refresh — no loading spinner, no error display. Only updates if the action ID changed.

---

## Pending Actions

- **Share data contract** with Data Engineering for Account_Scoring__c pipeline
- **Merge feature branch** to master + push to GitHub
