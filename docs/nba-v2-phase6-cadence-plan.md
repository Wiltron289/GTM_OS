# Plan: Integrate NBA Cadence Rules into V2 Engine (Phase 6)

## Context

The NBA V2 engine currently evaluates signals, scores opportunities, and surfaces the top-priority action to AEs. However, the `NBA_Cadence_Rule__mdt` records (7 deployed) are **never queried** by the engine. The engine hardcodes `Cadence_Stage__c = 1`, `Attempt_Count_Today__c = 0`, `Last_Attempt_Method__c = 'Call'`.

Sales Leadership has published a detailed multi-channel cadence strategy (PDF) with specific step-by-step sequences across Days 0-5. The engine needs to know where the AE is in the cadence, tell them which call to make next, enforce 1-hour spacing, and provide method hints (SMS/Email) for non-call steps.

**Scope decisions:**
- **Channels**: Calls + method hints (no auto-sending SMS/Email)
- **Cadences**: First Touch only (Variant A: 5-Day High-Intent). Framework extensible for others.
- **Variants**: Admin-selectable per AE via Hierarchy Custom Setting

### Sales Leadership Cadence Strategy (First Touch Variant A — 5-Day)

From the "Homebase Sales Full Cadence Strategy" PDF:

- **Day 0**: Call #1 (within 5 min) -> [SMS if no connect] -> Call+VM #2 (+1hr) -> [Email #1 EOD] -> Call #3 (+1hr)
- **Day 1**: Call #4 (Morning) -> Call #5 (+1hr) -> [SMS #2 Midday] -> [Email #2 EOD]
- **Day 3**: [Email #3] -> Call #6 (if VM-heavy)
- **Day 5**: [SMS Breakup]
- **Total**: 6 Calls, 3 SMS hints, 3 Email hints

Key insight: 1-hour spacing between calls increases connect rates by 52% (11% -> 17%).

### Current Architecture Summary

- **NbaActionCreationService.cls**: Evaluates signals, determines action type (First Touch/Re-engage/Stage Progression/Follow Up), scores, builds NBA_Queue__c candidates. Currently hardcodes cadence fields.
- **NbaActionController.cls**: On-demand entry point. `getActiveAction()` → Layer 1 check → cache → full evaluation (~12 SOQL). Returns `ActionWrapper` to LWC.
- **NbaSignalService.cls**: Queries 7 CRM data sources. `OpportunitySignal` already has `lastCallDate`, `lastCallDisposition`, `hadConnectedCall`, `hadNoConnect`. Already queries `Days_Since_Creation__c` on Opp (line 246) but doesn't map it to signal.
- **NbaActionStateService.cls**: Writes audit NBA_Queue__c records on complete/snooze/dismiss.
- **NbaCacheService.cls**: Platform Cache per AE, 5min TTL.
- **LWC**: `nbaDemoInsightsPanel` shows `actionInstruction` + `reasonText`. `nbaDemoHeader` shows action type badge.

## Work Groups

### A. CMDT Schema Extension + New Records

**Goal**: Add 5 fields to NBA_Cadence_Rule__mdt, replace 7 old records with 12 new First Touch Variant A records, create Hierarchy Custom Setting for variant assignment.

**New CMDT fields** (5 files under `force-app/main/default/objects/NBA_Cadence_Rule__mdt/fields/`):

| Field | Type | Purpose |
|-------|------|---------|
| `Cadence_Day__c` | Number(2,0) | Which day in cadence (0, 1, 3, 5) |
| `Variant__c` | Text(30) | A/B variant identifier |
| `Step_Order__c` | Number(2,0) | Ordering within same day (1, 2, 3...) |
| `Hint_Text__c` | Text(255) | Method hint shown to AE |
| `Is_Primary__c` | Checkbox | True = call action, false = hint-only step |

**Delete** 7 old CMDT records (`Day1_Pressure_Call_1` through `Connected_Followup_4hr`).

**Create** 12 new CMDT records modeling the PDF cadence:

| DeveloperName | Day | StepOrder | Method | IsPrimary | Spacing(min) | Max/Day | HintText | NextOnFail |
|---|---|---|---|---|---|---|---|---|
| FT_A_D0_Call1 | 0 | 1 | Call | Y | 5 | 3 | - | SMS |
| FT_A_D0_Hint_SMS1 | 0 | 2 | SMS | N | 0 | - | Send SMS if no connect | - |
| FT_A_D0_Call2 | 0 | 3 | Call | Y | 60 | 3 | Leave voicemail | Email |
| FT_A_D0_Hint_Email1 | 0 | 4 | Email | N | 0 | - | Send intro email EOD | - |
| FT_A_D0_Call3 | 0 | 5 | Call | Y | 60 | 3 | - | SMS |
| FT_A_D1_Call4 | 1 | 1 | Call | Y | 60 | 2 | - | SMS |
| FT_A_D1_Call5 | 1 | 2 | Call | Y | 60 | 2 | - | Email |
| FT_A_D1_Hint_SMS2 | 1 | 3 | SMS | N | 0 | - | Send SMS #2 midday | - |
| FT_A_D1_Hint_Email2 | 1 | 4 | Email | N | 0 | - | Send follow-up email EOD | - |
| FT_A_D3_Hint_Email3 | 3 | 1 | Email | N | 0 | - | Send email #3 | - |
| FT_A_D3_Call6 | 3 | 2 | Call | Y | 0 | 1 | Only if VM-heavy | - |
| FT_A_D5_Hint_Breakup | 5 | 1 | SMS | N | 0 | - | Send breakup SMS | - |

All records: `Scenario__c = 'First Touch'`, `Variant__c = 'A'`, `Is_Active__c = true`.

**New Hierarchy Custom Setting**: `NBA_AE_Config__c`
- File: `force-app/main/default/objects/NBA_AE_Config__c/`
- Field: `Cadence_Variant__c` (Text 30) -- Org default = `'A'`, overridable per User
- 0 SOQL: uses `getInstance(userId)` from cache

---

### B. Signal Enrichment

**Goal**: Add cadence-relevant data to `OpportunitySignal` without additional SOQL.

**File**: `force-app/main/default/classes/NbaSignalService.cls`

**New fields on OpportunitySignal** (after line 72):
```apex
public Decimal daysSinceCreation;      // From Opp query (already fetched at line 246)
public Integer todayCallCount;         // Count of today's Talkdesk activities
public List<Datetime> todayCallDates;  // Timestamps for spacing check
```

**Change `queryRecentTalkdesk()`** (line 253): Change return type from `Map<Id, talkdesk__Talkdesk_Activity__c>` to `Map<Id, List<talkdesk__Talkdesk_Activity__c>>`. Keep all activities per Opp (not just most recent). **No SOQL change** -- same query, different in-memory processing.

**Change signal assembly** (around line 140): Process the activity list to:
- Extract most recent call (existing logic)
- Count today's calls + collect timestamps (new)
- Map `daysSinceCreation` from `opp.Days_Since_Creation__c` (already queried at line 246, just not mapped)

**SOQL impact**: 0 additional

---

### C. New `NbaCadenceService` Class

**Goal**: Encapsulate all cadence logic: load CMDT rules, determine AE's current step, enforce spacing, return cadence context.

**New files**:
- `force-app/main/default/classes/NbaCadenceService.cls`
- `force-app/main/default/classes/NbaCadenceServiceTest.cls`

**Key methods**:

```
getCurrentStep(signal, variant) -> CadenceStep or null
  1. Load CMDT rules (cached static, 1 SOQL first call)
  2. Compute cadenceDay from signal.daysSinceCreation
  3. Find next primary (call) step on today's cadenceDay that AE hasn't done
  4. Check daily cap (todayCallCount vs Max_Attempts_Per_Day__c)
  5. Check spacing (lastCallDate vs Attempt_Spacing_Minutes__c)
  6. If spacing not met or cap hit -> return null
  7. Build CadenceStep with instruction, progress text, method hints
```

**CadenceStep wrapper**:
- `ruleName`, `cadenceStage`, `cadenceDay`, `method`, `isPrimary`
- `spacingMinutes`, `maxCallsToday`, `nextMethodOnFail`, `hintText`
- `instruction` -- rich text: "Call 2 of 3 today (Day 0). If no connect: SMS."
- `progressText` -- "Call 2 of 3 today (Day 0)"
- `upcomingHints` -- list of hint-only steps after this call

**Transaction-scoped static map** `lastEvaluatedSteps`: `Map<Id, CadenceStep>` keyed by oppId, populated during `getCurrentStep()`, read by `toWrapperFromCandidate()` in the same transaction.

**SOQL impact**: 1 (CMDT query, cached after first call)

**Tests** (~8 methods): correct step for Day 0/0 calls, spacing enforcement, daily cap, cadence complete, hint collection, progress text, variant mismatch returns null, backwards compat for non-First-Touch.

---

### D. Creation Service Integration

**Goal**: Wire `NbaCadenceService` into `NbaActionCreationService.evaluateAndCreate()` for First Touch actions.

**File**: `force-app/main/default/classes/NbaActionCreationService.cls`

**Changes to `evaluateAndCreate()`** (line 57):
1. After loading CMDT rules, resolve AE variant via `NBA_AE_Config__c.getInstance(ownerId)` (0 SOQL)
2. After `determineActionType()` returns `'First Touch'`:
   - Call `NbaCadenceService.getCurrentStep(signal, variant)`
   - If null (spacing/cap/complete) -> fall through to `determineNonCadenceActionType()` helper
   - If step returned -> use its instruction, ruleName, cadenceStage, attemptCount

**Changes to NBA_Queue__c build block** (line 112):
- `Cadence_Stage__c` = cadenceStep.cadenceStage (instead of hardcoded 1)
- `Attempt_Count_Today__c` = signal.todayCallCount (instead of 0)
- `Last_Attempt_Method__c` = cadenceStep.method (instead of 'Call')
- `Rule_Name__c` = cadenceStep.ruleName (instead of actionType + '_Auto')
- `Action_Instruction__c` = cadenceStep.instruction (rich cadence text)

**New helper** `determineNonCadenceActionType()`: Skips First Touch checks, only returns Stage Progression / Re-engage / Follow Up. Handles the case when cadence suppresses but Opp still needs a different action type.

**Backwards compatibility**: Non-First-Touch actions skip cadence entirely -- zero behavior change.

---

### E. ActionWrapper Extension + Controller

**Goal**: Pass cadence metadata to LWC.

**File**: `force-app/main/default/classes/NbaActionController.cls`

**New fields on ActionWrapper** (after line 341):
```apex
@AuraEnabled public Integer cadenceStage;     // Step number (1-12)
@AuraEnabled public Integer cadenceDay;       // Day in cadence (0, 1, 3, 5)
@AuraEnabled public Integer todayCallCount;   // Calls made today
@AuraEnabled public Integer maxCallsToday;    // Max allowed today
@AuraEnabled public String methodHints;       // Next method hint text
@AuraEnabled public String cadenceProgress;   // "Call 2 of 3 today (Day 0)"
```

**Changes to `toWrapperFromCandidate()`** (line 285): Read from `NbaCadenceService.lastEvaluatedSteps` map by oppId:
```apex
CadenceStep step = NbaCadenceService.lastEvaluatedSteps.get(candidate.Opportunity__c);
if (step != null) {
    w.cadenceStage = step.cadenceStage;
    w.cadenceDay = step.cadenceDay;
    w.todayCallCount = step.todayCalls;
    w.maxCallsToday = step.maxCallsToday;
    w.methodHints = step.hintText;
    w.cadenceProgress = step.progressText;
}
```

Also map in `toWrapperFromRecord()` (line 260) from NBA_Queue__c fields for Layer 1 records.

---

### F. State Service Audit Updates

**Goal**: Write cadence metadata to audit NBA_Queue__c records.

**File**: `force-app/main/default/classes/NbaActionStateService.cls`

**Changes to `writeAuditRecord()`**: Accept optional `cadenceStage` and `attemptCountToday` params. Write to `Cadence_Stage__c` and `Attempt_Count_Today__c` on the audit record.

Use method overloading for backwards compatibility (existing callers pass 2 fewer args).

---

### G. LWC Display Updates

**Goal**: Show cadence progress and method hints in the LWC.

#### G1. nbaDemoInsightsPanel
**Files**: `force-app/main/default/lwc/nbaDemoInsightsPanel/` (`.js` + `.html`)

Add a cadence context section inside the "Why This Action" panel:
- **Cadence progress**: "Call 2 of 3 today (Day 0)" with steps icon
- **Method hints**: "If no connect: Send SMS" with forward icon
- Guarded by `lwc:if={showCadenceContext}` -- only renders when cadence fields present

#### G2. nbaDemoHeader
**Files**: `force-app/main/default/lwc/nbaDemoHeader/` (`.js` + `.html`)

Add a small badge next to action type showing call count: `2/3`
- Guarded by `lwc:if={showCadenceStep}` -- only for cadence actions

No changes needed to `nbaActionBar`, `nbaDemoAlertBanner`, or `nbaDemoWorkspace` (currentAction passthrough is automatic).

---

## SOQL Budget

| Source | SOQL |
|--------|------|
| Existing cache miss pipeline | ~12 |
| New: NbaCadenceService CMDT | +1 (cached) |
| New: NBA_AE_Config__c | +0 (getInstance) |
| **Total on cache miss** | **~13** |
| + getPageData | ~9 |
| **Worst case total** | **~22 of 100** |

---

## File Summary

### New Files (~20)
- `NbaCadenceService.cls` + `NbaCadenceServiceTest.cls`
- `NBA_AE_Config__c` object + `Cadence_Variant__c` field
- 5 new CMDT field definitions on NBA_Cadence_Rule__mdt
- 12 new CMDT record files (FT_A_D0_Call1 through FT_A_D5_Hint_Breakup)

### Modified Files (8)
- `NbaSignalService.cls` -- add 3 fields to signal, refactor Talkdesk processing
- `NbaActionCreationService.cls` -- wire cadence for First Touch, add variant resolution
- `NbaActionController.cls` -- extend ActionWrapper with 6 fields, map in toWrapper methods
- `NbaActionStateService.cls` -- pass cadence metadata to audit records
- `nbaDemoInsightsPanel.js` + `.html` -- cadence progress + method hints display
- `nbaDemoHeader.js` + `.html` -- call count badge

### Deleted Files (7)
- 7 old NBA_Cadence_Rule CMDT records (replaced by 12 new ones)

### Test Updates
- `NbaCadenceServiceTest.cls` -- ~8 new test methods
- `NbaSignalServiceTest.cls` -- ~2 new methods for enriched signals
- `NbaActionCreationServiceTest.cls` -- ~3 new methods for cadence integration
- `NbaActionControllerTest.cls` -- ~2 new methods for ActionWrapper cadence fields

## Verification

1. **Unit tests**: Run `sf apex run test --synchronous --result-format human` -- target 93+ existing + ~15 new = 108+ all passing
2. **Manual test**: Open App Page as AE -> see "Call 1 of 3 today (Day 0)" instruction for a new First Touch Opp -> Complete -> see "Call 2 of 3 today (Day 0)" with hint "If no connect: Send SMS" -> verify 1-hour spacing suppresses Call 3 if called too soon
3. **Backwards compat**: Verify Re-engage and Stage Progression actions display exactly as before (no cadence fields)
4. **Variant test**: Set `NBA_AE_Config__c` for a test user to `'B'` -> verify no cadence steps returned (Variant B records not created yet, falls through to non-cadence)
5. **Deploy**: `sf project deploy start --source-dir force-app --test-level RunLocalTests`
