# NBA V2 — Action Orchestration Engine: Phase Plan

**Created**: 2026-02-14
**Branch**: `feature/nba-v2-demo-lwc` (continuing from Demo LWC work)
**PRD Source**: PRD - Next Best Action (NBA) V2.pdf
**Status**: Planning

---

## 1. Phase Overview

### What We're Building

NBA V2 is a deterministic sales workflow orchestration system that serves AEs a single Next Best Action at a time on a dedicated **App Page**. The existing Demo LWC (18 components, 1 Apex controller) becomes the **action execution view** — dynamically rendering context for whatever action the engine serves.

### Core UX Loop

```
AE opens NBA App Page
  → Sees current action (rendered via Demo LWC, fed by NBA_Queue__c)
  → Works the action (call, email, SMS, update stage)
  → Hits Complete / Snooze / Dismiss
  → Engine evaluates and selects next highest-priority action
  → Page re-renders with new action context
  → Repeat
```

### What Already Exists

| Asset | Status |
|---|---|
| 18 LWC components (Demo) | Deployed, Sprint 10 stable |
| NbaDemoController.cls (~955 lines) | Deployed, 19 tests passing |
| Account_Scoring__c (ML scoring layer) | Deployed, pipeline-ready |
| NBA_V2_Demo FlexiPage | Deployed (unassigned) |
| Permission sets (scoring) | Deployed |
| **NBA_Queue__c (96 fields)** | **Deployed to UAT — core action record with relationships, status lifecycle, priority scoring, call disposition, sales motions, timing fields, explainability** |
| NBA_Queue_Record_Page FlexiPage | Deployed (record page override on NBA_Queue__c) |

### What Needs to Be Built

| Asset | Description |
|---|---|
| ~12 new fields on NBA_Queue__c | Impact/Urgency scores, Priority Bucket/Layer, Cadence Stage, etc. |
| New picklist values on NBA_Queue__c | Action_Type__c additions (First Touch, Re-engage, etc.) |
| Custom Metadata Types (5) | Rule configuration (cadence, urgency, suppression, impact weights, cooldown) |
| Action Creation Engine | Scheduled Apex + triggers that evaluate CRM state and create candidate actions |
| Action State Engine | Apex service managing action lifecycle + constraints |
| Action Selection Engine | Apex service implementing Gate → Bucket → Rank |
| Demo LWC refactor | Wire to NBA_Queue__c, add Complete/Snooze/Dismiss, dynamic re-render |
| NBA App Page | New FlexiPage (App Page type) hosting the workspace |

---

## 2. NBA_Queue__c Data Model

**Decision: Reuse the existing NBA_Queue__c object** (96 fields already deployed to UAT). It has core relationships, status lifecycle, priority scoring, timing fields, call disposition tracking, and sales motion support. We add ~12 new fields and new picklist values rather than building from scratch.

### Existing Fields We'll Use (Key Mappings)

These fields already exist and map directly to PRD concepts:

| Existing Field | PRD Concept | Notes |
|---|---|---|
| `Account__c` | Account relationship | Lookup, SetNull on delete |
| `Opportunity__c` | Opportunity relationship | Lookup, SetNull on delete |
| `Lead__c` | Lead relationship | Lookup, SetNull on delete |
| `Sales_Rep__c` | Assigned AE | Lookup to User |
| `Status__c` | Action lifecycle state | Has: New, Pending, In Progress, Accepted, Completed, Dismissed, Snoozed, Deferred, Expired, Archive |
| `Action_Type__c` | Action type guidance | Has: Call, Email, Follow Up, Meeting, Task, Review, Event |
| `Priority_Score__c` | Final priority score | Number(7,2) |
| `PriorityBand__c` | Priority classification | Picklist |
| `WithinBandScore__c` | Within-band ranking | Number |
| `Workstream__c` | Creation path | Events, Cadence, Motion, Prospecting |
| `Sales_Motion__c` | Blitz mode cadences | 13 values (Clover Embedded Outreach steps, etc.) |
| `CooldownUntil__c` | Cooldown enforcement | DateTime |
| `FocusUntil__c` | Focus period | DateTime |
| `Snoozed_Until__c` | Snooze expiration | DateTime |
| `Last_Call_Date__c` | Last attempt tracking | DateTime |
| `DueAt__c` | Scheduled action time | DateTime (Layer 1 time-bound) |
| `Due_Date__c` | Action due date | Date |
| `Call_Disposition__c` | Call outcome | Connected-DM, Connected-GK, Attempted-LVM, Attempted-NVM, Not Interested, Invalid Number |
| `ReasonJson__c` | Explainability data | JSON payload |
| `ReasonText__c` | Human-readable reason | "Why this action" for AE |
| `Model_Reason__c` | Model-generated reason | AI/rule reason |
| `Model_Version__c` | Model version tracking | Which scoring model version |
| `LastEvaluatedAt__c` | Last engine evaluation | DateTime |
| `EligibilityFingerprint__c` | Dedup/eligibility hash | Prevents duplicate creation |
| `UniqueKey__c` | Deduplication key | Uniqueness enforcement |
| `Completed_Date__c` | Completion timestamp | DateTime |
| `Actioned_Date__c` | When action was taken | DateTime |
| `First_Viewed_Date__c` | First view by AE | DateTime |
| `Last_Viewed_Date__c` | Last view by AE | DateTime |
| `Dismissed_Reason__c` | Dismiss reason | Text |
| `Dismissal_Category__c` | Dismiss category | Picklist |
| `Next_Steps__c` | Rep next steps | Text |
| `Next_Step_Date__c` | Next step due date | Date |
| `Rep_Notes__c` | Rep notes | Text |
| `Contact_Name__c` | Contact for action | Text |
| `Contact_Phone__c` | Phone to call | Phone |
| `Best_Number_to_Call__c` | Preferred phone | Phone |
| `Best_Person_to_Call__c` | Preferred contact | Text |
| `Opportunity_Stage__c` | Current opp stage | Text |
| `Close_Date__c` | Opp close date | Date |
| `Active_Employees__c` | Account employee count | Number |
| `Inception_Switcher__c` | Account type | Picklist |
| `Description__c` | Action description | Text |
| `Subject__c` | Subject line | Text |
| `Start_Time__c` | Event start time | DateTime |
| `Event__c` | Event relationship | Lookup |
| `Not_Surfaced_Reasons__c` | Why action was suppressed | Text |

### Status Mapping (Existing → PRD)

| Existing Value | PRD Value | Action |
|---|---|---|
| New | — | Keep as initial creation state |
| Pending | Pending | Direct match |
| In Progress | Active | Map "In Progress" = Active in engine logic |
| Accepted | — | Keep (AE acknowledged but not yet working) |
| Completed | Completed | Direct match |
| Dismissed | Dismissed | Direct match |
| Snoozed | Snoozed | Direct match |
| Deferred | — | Keep (system-deferred vs AE-snoozed) |
| Expired | Expired | Direct match |
| Archive | — | Keep for historical records |

**No status picklist changes needed.** We use "In Progress" as the "Active" state in engine logic.

### New Fields to Add (~12)

| Field API Name | Type | Description |
|---|---|---|
| `Impact_Score__c` | Number(5,4) | Computed impact score (MRR weight + Close weight) — separated from Priority_Score for transparency |
| `Urgency_Score__c` | Number(5,4) | Computed urgency score (cadence + inactivity + pressure) |
| `Priority_Bucket__c` | Picklist | `Cadence Due Today` · `Late-Stage Stalled` · `High Impact Focus` · `Neglected` · `General Pipeline` |
| `Priority_Layer__c` | Picklist | `Layer 1 - Time Bound` · `Layer 2 - Mode` · `Layer 3 - Impact+Urgency` |
| `Is_Time_Bound__c` | Checkbox | True if this is a Layer 1 time-bound action |
| `Cadence_Stage__c` | Number | Current position in the outreach cadence (1, 2, 3...) |
| `Attempt_Count_Today__c` | Number | Number of attempts on this opp today (cooldown enforcement) |
| `Last_Attempt_Method__c` | Picklist | `Call` · `SMS` · `Email` — last method used (complements Last_Call_Date__c) |
| `Source_Path__c` | Picklist | `Immediate` · `Pipeline Cadence` · `Context Update` — which creation path |
| `Rule_Name__c` | Text(100) | Links to Custom Metadata rule that created this action |
| `Action_Instruction__c` | Text(255) | Human-readable instruction (e.g., "Call to schedule demo — high MRR account") |
| `Workflow_Mode__c` | Picklist | `Pipeline` · `Blitz` — Layer 2 mode classification |

### Action_Type__c Picklist Updates

Add new values (keep existing active ones):

| New Value | Purpose |
|---|---|
| `First Touch` | SLA-driven initial contact |
| `Re-engage` | Deal going cold, inactivity threshold crossed |
| `Stage Progression` | Late-stage push / stage pressure |
| `SLA Response` | Time-sensitive SLA-driven action |
| `Blitz Outreach` | Campaign-driven blitz action |

### Legacy Fields (Leave In Place, Don't Remove)

These 30+ fields are V1/legacy but should NOT be deleted — they may have historical data or active integrations:
- 14 feature engagement booleans (Break_Preferences, Scheduling, etc.)
- Talkdesk integration fields
- Configuration__c, Implementation_Project__c, Oam_Activity__c
- Data_Fix_Boolean__c, Last_Reconcile_Enqueue__c
- Payroll_Buyer_Stage__c, Current_Payroll_Provider__c
- Talk_Time__c, Talk_Time_Sec__c, Number_Dialed__c, Person_Called__c

---

## 3. Custom Metadata Types (Rule Configuration)

All business rules stored as Custom Metadata so admins can tune without code deploys.

### NBA_Cadence_Rule__mdt

Defines outreach cadence timing per scenario.

| Field | Type | Example Value |
|---|---|---|
| `Rule_Name__c` | Text | `Day1_Pressure` |
| `Scenario__c` | Text | `First Touch` |
| `Cadence_Stage__c` | Number | `1` |
| `Attempt_Spacing_Minutes__c` | Number | `60` |
| `Max_Attempts_Per_Day__c` | Number | `3` |
| `Method__c` | Text | `Call` |
| `Next_Method_On_Fail__c` | Text | `SMS` |
| `Is_Active__c` | Checkbox | `true` |
| `Description__c` | Text | `First call attempt on Day 1, 1-hour spacing` |

### NBA_Urgency_Rule__mdt

Defines urgency escalation thresholds.

| Field | Type | Example Value |
|---|---|---|
| `Rule_Name__c` | Text | `Late_Stage_Inactivity` |
| `Signal_Type__c` | Text | `Inactivity` |
| `Stage_Minimum__c` | Text | `Stage 4` |
| `Threshold_Days__c` | Number | `3` |
| `Urgency_Multiplier__c` | Number | `1.5` |
| `Is_Active__c` | Checkbox | `true` |
| `Description__c` | Text | `Escalate urgency for late-stage opps with 3+ days inactivity` |

### NBA_Suppression_Rule__mdt

Defines when actions should NOT be created.

| Field | Type | Example Value |
|---|---|---|
| `Rule_Name__c` | Text | `Meeting_Scheduled_Suppress` |
| `Condition__c` | Text | `Upcoming Meeting` |
| `Suppression_Window_Hours__c` | Number | `24` |
| `Is_Active__c` | Checkbox | `true` |
| `Description__c` | Text | `Suppress outreach creation when meeting is within 24 hours` |

### NBA_Impact_Weight__mdt

Defines scoring weights (single active config record).

| Field | Type | Example Value |
|---|---|---|
| `Config_Name__c` | Text | `Default_V2` |
| `MRR_Weight__c` | Number(3,2) | `0.60` |
| `Close_Probability_Weight__c` | Number(3,2) | `0.40` |
| `Impact_vs_Urgency_Impact_Weight__c` | Number(3,2) | `0.50` |
| `Impact_vs_Urgency_Urgency_Weight__c` | Number(3,2) | `0.50` |
| `Is_Active__c` | Checkbox | `true` |
| `Description__c` | Text | `Default V2 impact weights — 60% MRR, 40% Close Prob` |

### NBA_Cooldown_Rule__mdt

Defines cooldown/spacing constraints.

| Field | Type | Example Value |
|---|---|---|
| `Rule_Name__c` | Text | `Default_Call_Spacing` |
| `Method__c` | Text | `Call` |
| `Min_Spacing_Minutes__c` | Number | `60` |
| `Daily_Cap__c` | Number | `3` |
| `Is_Active__c` | Checkbox | `true` |
| `Description__c` | Text | `Minimum 1 hour between call attempts, max 3 per day` |

---

## 4. Engine Architecture

### 4.1 Action Creation Engine

**Role**: Evaluate CRM state → create candidate NBA_Queue__c records.

**Implementation**: `NbaActionCreationService.cls` + `NbaActionCreationSchedulable.cls`

**Execution model**:
- Scheduled Apex runs every 10 minutes
- Evaluates all open Opportunities for the AE
- Checks against suppression rules
- Creates candidate actions with Status = `Pending`

**Creation Paths**:

| Path | Trigger | Implementation |
|---|---|---|
| A. Immediate / Time-Based | Event starting ≤5 min, new opp assigned, SLA | Trigger on Event, Opportunity (after insert/update) |
| B. Pipeline Cadence | Day 1 pressure, no-connect follow-up, re-engage | Scheduled Apex (batch evaluation) |
| C. Context Updates | Call connected, stage change, activity logged | Trigger on Task, Event, Opportunity (field change) |

**Suppression checks** (before creating):
- Upcoming meeting within suppression window → suppress
- Recent valid touch within cadence spacing → suppress
- Closed/Won/Lost opportunity → suppress
- Active action already exists for this opp → suppress (prevent duplicates)
- User-created opportunities → suppress SLA first-touch (per PRD)

### 4.2 Action State Engine

**Role**: Manage lifecycle transitions + enforce constraints.

**Implementation**: `NbaActionStateService.cls`

**State transitions**:
```
Pending → Active       (when AE has open slot, promoted by Selection Engine)
Active → Completed     (AE marks complete)
Active → Snoozed       (AE snoozes with reason + duration)
Active → Dismissed      (AE dismisses)
Active → Expired        (non-timebound: 1 hour. time-bound: 15 min after scheduled time)
Snoozed → Pending      (snooze period expires, re-enters queue)
Expired → [regenerated] (if conditions still relevant, Creation Engine may recreate)
```

**Constraints**:
| Rule | Limit |
|---|---|
| Max Active + Pending per AE | 2 |
| Active actions per Opportunity | 1 |
| Snoozed count toward cap | No |

**Key methods**:
- `completeAction(actionId)` → mark complete, trigger re-evaluation
- `snoozeAction(actionId, reason, snoozeDuration)` → mark snoozed, set Snooze_Until__c
- `dismissAction(actionId, reason)` → mark dismissed
- `expireStaleActions()` → called by scheduled job, expires old actions
- `unsnoozeDueActions()` → called by scheduled job, moves snoozed → pending
- `promoteNextAction(aeUserId)` → promote highest-ranked pending to active

### 4.3 Action Selection Engine (Prioritization)

**Role**: Gate → Bucket → Rank to decide which action is served next.

**Implementation**: `NbaActionSelectionService.cls`

**Pipeline**:

```
STEP 1: GATING (Hard Filters)
  ├── Cooldown spacing met?
  ├── Meeting suppression?
  ├── Cadence window reached?
  ├── Not expired?
  └── Mode scope (Pipeline or Blitz)?
       ↓ (only eligible actions pass)
STEP 2: BUCKETING
  ├── Cadence Due Today
  ├── Late-Stage Stalled
  ├── High Impact Focus
  ├── Neglected (simplified, no aging boost for now)
  └── General Pipeline
       ↓
STEP 3: RANKING (within bucket)
  ├── Impact Score = (0.6 × MRR_Score) + (0.4 × Close_Probability_Score)
  ├── Urgency Score = f(cadence_stage, time_since_activity, same_day_pressure, stage_pressure)
  └── Final Score = (0.5 × Impact) + (0.5 × Urgency)
       ↓
  Return top-ranked action
```

**Layer precedence**:
1. **Layer 1 (Time-Bound)**: Upcoming meeting, SLA first-touch, scheduled follow-up → always served first
2. **Layer 2 (Mode)**: Pipeline vs Blitz → filters which actions enter Layer 3
3. **Layer 3 (Impact + Urgency)**: Gate → Bucket → Rank

**Data sources for scoring**:
- `MRR__c` (formula field on Opportunity) → normalized to 0-1 for MRR_Score
- `Account_Scoring__c.Prob_Payroll_Conversion__c` → Close_Probability_Score
- `Account_Scoring__c.Prob_Tier_Upgrade__c` → MRR potential boost modifier
- `Account_Scoring__c.Payroll_Top_Drivers__c` → Explainability / Reason Codes
- Activity timestamps from Task/Event → urgency signals

---

## 5. Demo LWC Refactor

### Current State
- `nbaDemoWorkspace` takes `recordId` (Opportunity ID) from the record page
- Calls `NbaDemoController.getPageData(oppId)` to load everything
- Stateless child components receive data via `@api`

### Target State
- `nbaDemoWorkspace` lives on an **App Page** (not record page)
- Takes context from an NBA_Queue__c action record
- Loads Opp/Account data through the action's relationships
- Displays action type + reason code in header
- Complete/Snooze/Dismiss buttons trigger state engine
- On action completion → fetches next action → re-renders

### Key Changes

| Component | Change |
|---|---|
| `nbaDemoWorkspace` | New data source: `NbaActionController.getCurrentAction(userId)` instead of `getPageData(oppId)`. Add action lifecycle methods. Remove `recordId` wire — use App Page context. |
| `nbaDemoHeader` | Show Action Type badge + Reason Code. Wire Snooze button to state engine. Add Complete + Dismiss buttons. |
| `nbaDemoAlertBanner` | Wire to Layer 1 time-bound alerts from the engine (not just next-24h events). |
| `nbaDemoInsightsPanel` | "Why This Action" instead of "Why This Account" — show `Reason_Code__c` + Account_Scoring drivers. |
| New: `nbaActionBar` | Bottom action bar: Complete (primary), Snooze (with reason/duration modal), Dismiss (with reason). Triggers re-render on success. |
| New: `nbaEmptyState` | Shown when AE has 0 actions in queue ("All caught up!") |

### New Apex Controller

`NbaActionController.cls` — thin controller for the App Page LWC.

```
@AuraEnabled(cacheable=true)
getActiveAction(userId) → returns active NBA_Queue__c + related Opp/Account data
   (replaces getPageData — same data, sourced through the action record)

@AuraEnabled
completeAction(actionId) → calls NbaActionStateService.completeAction()
   returns next active action

@AuraEnabled
snoozeAction(actionId, reason, duration) → calls NbaActionStateService.snoozeAction()
   returns next active action

@AuraEnabled
dismissAction(actionId, reason) → calls NbaActionStateService.dismissAction()
   returns next active action
```

---

## 6. App Page Setup

### FlexiPage: NBA_V2_Workspace

- **Type**: App Page (one-region, full-width)
- **Component**: `c:nbaDemoWorkspace` (refactored)
- **Tab**: NBA (custom tab in the Homebase app)
- **No recordId** — the component self-resolves the current user's active action

---

## 7. Implementation Phases

### Phase 1: Data Foundation (Sprint 11)
**Goal**: Extend existing NBA_Queue__c with V2 fields + deploy rule framework.

- [ ] Add ~12 new fields to NBA_Queue__c (Impact_Score, Urgency_Score, Priority_Bucket, Priority_Layer, etc.)
- [ ] Add new picklist values to Action_Type__c (First Touch, Re-engage, Stage Progression, SLA Response, Blitz Outreach)
- [ ] Add Workflow_Mode__c picklist (Pipeline, Blitz)
- [ ] Create Custom Metadata Types (5 types with default rule records)
- [ ] Seed default cadence/urgency/suppression/impact/cooldown rules
- [ ] Deploy field additions + CMDTs to UAT sandbox
- [ ] Seed sample NBA_Queue__c records with V2 fields populated for development

### Phase 2: Engine Core (Sprint 12)
**Goal**: Working action creation + state management + selection.

- [ ] `NbaActionCreationService.cls` — rule evaluation + candidate creation
- [ ] `NbaActionStateService.cls` — lifecycle transitions + constraint enforcement
- [ ] `NbaActionSelectionService.cls` — Gate → Bucket → Rank pipeline
- [ ] `NbaActionCreationSchedulable.cls` — 10-minute scheduled job
- [ ] `NbaActionExpirationSchedulable.cls` — expire stale actions, unsooze due actions
- [ ] Test classes for all services (75%+ coverage, bulk-safe)
- [ ] Integration test: full cycle (create → promote → serve → complete → next)

### Phase 3: LWC Refactor + App Page (Sprint 13)
**Goal**: The Demo LWC becomes action-driven on a dedicated App Page.

- [ ] `NbaActionController.cls` — thin controller for LWC
- [ ] Refactor `nbaDemoWorkspace` to load from action context
- [ ] Refactor `nbaDemoHeader` with action type + reason code + action buttons
- [ ] Build `nbaActionBar` component (Complete/Snooze/Dismiss)
- [ ] Build `nbaEmptyState` component
- [ ] Create App Page FlexiPage + custom tab
- [ ] Wire action completion → re-render cycle
- [ ] End-to-end demo: open App Page → see action → complete → next action appears

### Phase 4: Triggers + Real-Time Events (Sprint 14)
**Goal**: Actions created in real-time from CRM events, not just scheduled batch.

- [ ] Opportunity trigger handler — new opp assigned → SLA First Touch
- [ ] Event trigger handler — upcoming meeting → time-bound action
- [ ] Task trigger handler — activity logged → context update (may suppress/fulfill)
- [ ] Opportunity field change handler — stage change → stage-specific rules
- [ ] Snoozed action re-entry (scheduled job for unsnooze)
- [ ] Layer 1 alert integration (time-bound actions surface as alerts in LWC)

### Phase 5: Blitz Mode + Polish (Sprint 15)
**Goal**: Mode switching, blitz campaigns, production readiness.

- [ ] Blitz mode data model (Campaign-linked actions)
- [ ] Layer 2 mode filtering in Selection Engine
- [ ] Mode toggle in LWC (Pipeline vs Blitz indicator)
- [ ] Method escalation logic (Call → SMS → Email)
- [ ] Cooldown tuning and testing
- [ ] Manager dashboard / reporting (if in scope)
- [ ] Permission set assignment to AE profiles
- [ ] Production deployment planning

---

## 8. Decisions Made (To Confirm)

These decisions were made to unblock development. All should be reviewed with stakeholders before production rollout.

| Decision | Choice | Rationale | Confirmed? |
|---|---|---|---|
| Impact model | Two-Factor Weighted (Option B) | Keeps big deals visible, weights tunable via Custom Metadata | No |
| Impact formula | `(0.6 × MRR) + (0.4 × Close Prob)` | Revenue-biased for payroll sales motion | No |
| Impact vs Urgency balance | 50/50 | Balanced start, tunable | No |
| Day 1 attempt pressure | 3 attempts, 1-hour spacing | Aggressive but not overwhelming | No |
| No-connect progression | 1hr → 2hr → next day | Standard sales cadence | No |
| Connected follow-up | Same day, 4-hour default | Keeps momentum after connection | No |
| Late-stage inactivity | 3 days at Stage 4+ | Early enough to intervene | No |
| Re-engagement trigger | 5 days inactivity at any stage | Catches deals going cold | No |
| Per-day attempt cap | 3 per opp per day | Prevents over-calling | No |
| Cadence constraint type | Soft (Layer 1 can override) | Time-bound commitments shouldn't wait | No |
| Method escalation | Call → SMS → Email | Phone-first sales culture | No |
| Action expiration | Non-timebound: 1hr, Time-bound: 15min after | Keeps queue fresh | No |
| Aging boost | Removed (V2) | Simplify initial release, add later if needed | Yes |
| MRR data source | `MRR__c` formula on Opportunity | Already exists and queryable | No |
| Close probability source | `Account_Scoring__c.Prob_Payroll_Conversion__c` | ML-generated, already deployed | No |

---

## 9. How Account_Scoring__c Feeds the Engine

```
Account_Scoring__c (ML Pipeline - Daily Refresh)
├── Prob_Payroll_Conversion__c  ──→  Close Probability Score (Layer 3 Impact)
├── Prob_Tier_Upgrade__c        ──→  MRR Potential boost modifier (Layer 3 Impact)
├── Payroll_Top_Drivers__c      ──→  Reason Codes / "Why This Action" (Explainability)
└── Tier_Upgrade_Top_Drivers__c ──→  Reason Codes / "Why This Action" (Explainability)

Surfaced on Account (for cross-object queries):
├── Account.Account_Prob_Payroll_Conversion__c
└── Account.Account_Prob_Tier_Upgrade__c

Used by:
├── NbaActionSelectionService  →  Impact score calculation
├── NbaActionCreationService   →  Candidate prioritization during cache refresh
└── nbaDemoInsightsPanel (LWC) →  "Why This Action" display
```

Account_Scoring__c **does not create actions**. It influences **which actions rank higher** when multiple candidates compete for the AE's 2 action slots.

---

## 10. Risk & Dependencies

| Risk | Mitigation |
|---|---|
| Scheduled Apex governor limits (100 SOQL per transaction) | Batch evaluation per AE, efficient queries |
| Account_Scoring__c data not populated | Graceful fallback — score without ML data using Opp fields only |
| Cadence timing values wrong | Custom Metadata makes them admin-tunable without deploys |
| AE adoption resistance | Explainability (reason codes) builds trust; snooze/dismiss gives control |
| Action queue floods with stale records | Expiration job + cooldown logic prevents buildup |
| MRR__c formula field limitations | Formula fields are queryable but not writable — use `Amount` for test data |

### External Dependencies

| Dependency | Owner | Status |
|---|---|---|
| MRR Potential Model (ML scores) | Data Engineering | Account_Scoring__c deployed, awaiting pipeline connection |
| Opportunity stage values | Salesforce Admin | Need to confirm stage names used in rules |
| AE User profiles/permission sets | Salesforce Admin | Need to assign NBA_Queue permissions |
| Mogli SMS integration | Already integrated | Working in Demo LWC |

---

## 11. File Inventory (Estimated New/Modified Files)

### Apex Classes (~8 new)
- `NbaActionCreationService.cls` + test
- `NbaActionStateService.cls` + test
- `NbaActionSelectionService.cls` + test
- `NbaActionController.cls` + test
- `NbaActionCreationSchedulable.cls`
- `NbaActionExpirationSchedulable.cls`

### NBA_Queue__c Field Additions (~12 new fields)
- `Impact_Score__c`, `Urgency_Score__c`
- `Priority_Bucket__c`, `Priority_Layer__c`
- `Is_Time_Bound__c`
- `Cadence_Stage__c`, `Attempt_Count_Today__c`
- `Last_Attempt_Method__c`, `Source_Path__c`
- `Rule_Name__c`, `Action_Instruction__c`
- `Workflow_Mode__c`

### Custom Metadata Types (5 new, with default records)
- `NBA_Cadence_Rule__mdt` + default records
- `NBA_Urgency_Rule__mdt` + default records
- `NBA_Suppression_Rule__mdt` + default records
- `NBA_Impact_Weight__mdt` + default record
- `NBA_Cooldown_Rule__mdt` + default records

### LWC (2 new, ~5 modified)
- `nbaActionBar` (new)
- `nbaEmptyState` (new)
- `nbaDemoWorkspace` (major refactor — action-driven data loading)
- `nbaDemoHeader` (refactor — action type + reason + Complete/Dismiss buttons)
- `nbaDemoAlertBanner` (refactor — Layer 1 time-bound alerts)
- `nbaDemoInsightsPanel` (refactor — "Why This Action" from engine)
- `nbaDemoSidebar` (minor — activity loaded from action context)

### FlexiPages (1 new)
- `NBA_V2_Workspace.flexipage-meta.xml` (App Page)

### Permission Sets (update existing or create new)
- Verify existing NBA_Queue__c permissions cover new fields
- Add field-level security for new fields to existing permission sets
