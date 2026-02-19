# NBA V2 (GTM OS) — Product Requirements Document

**Based on implemented code as of 2026-02-19**
**Branch:** `feature/nba-v2-demo-lwc`
**Source of truth:** Apex classes, LWC components, Custom Metadata Type records, and trigger handlers in the `force-app/main/default/` directory.

---

## 1. Executive Summary

### What NBA V2 Does

NBA V2 (branded GTM OS) is a real-time, opportunity-level action orchestration engine built natively on Salesforce. It replaces static task lists and manual pipeline reviews with a system that continuously evaluates an AE's open opportunities, scores them against impact and urgency signals, determines the correct cadence step, and surfaces a single "next best action" — one at a time, in priority order.

The system does not pre-generate a queue of tasks for reps to scroll through. Instead, it evaluates the full pipeline on demand (when the AE opens the workspace or every 5 minutes), creates action candidates in memory, ranks them, and serves the single highest-priority action. When the AE completes, snoozes, or dismisses that action, the engine immediately re-evaluates and serves the next one. This is fundamentally different from a static task system: the ranking reflects the state of the pipeline *right now*, not an hour ago.

Separately, real-time interrupts (upcoming meetings, newly assigned opportunities) are pushed into the system via Salesforce triggers and surfaced to the AE every 15 seconds. These interrupts take priority over scored-queue actions — the AE can accept them, handle them, and return to their scored queue.

### How It Aligns with CRO Expectations

The system's design premise matches a CRO's core desire: **reps should always be working the highest-value, most-urgent opportunity in their pipeline.** The scoring model combines MRR/deal size (60% of impact) with close probability (40% of impact), balanced 50/50 against urgency signals (SLA, inactivity, stage pressure). High-MRR, high-probability, time-sensitive opportunities consistently surface first.

Cadence integration means reps don't just know *which* opportunity to work — they know *what to do* (Call step 3, send SMS, follow up on voicemail). The system enforces spacing between attempts, respects outcome-based branching (connected call ends cadence, voicemail continues), and tracks progress visually.

### Where There Is Ambiguity or Misalignment

**1. Low-MRR-score opportunities are effectively invisible.** The scoring model is a pure weighted sort. There is no floor, no random sampling, no experimental injection. If an opportunity has low MRR and low close probability, it will never surface as the top action for a rep who has even one higher-scoring opportunity. This is by design (prioritization integrity) but creates a data-science blind spot: we cannot validate whether the external scoring model's low scores are accurate if those opportunities are never worked.

**2. The "MRR score" is not a single external score.** The system uses two inputs that function as the "MRR score": (a) the opportunity's MRR__c formula field (or Amount as fallback), and (b) Account_Scoring__c.Prob_Payroll_Conversion__c from an external ML model. These are separate fields from separate sources. When stakeholders say "MRR score," it is unclear which they mean. The system uses MRR__c for the monetary component and Prob_Payroll_Conversion__c for the probability component. If one is missing, the system falls back to Amount and Deal_Stage_Probability__c (a static formula field), respectively.

**3. There is no starvation prevention.** This is acknowledged. If a rep has 50 open opportunities, the bottom 30 by score may never receive attention until the top 20 are completed, snoozed, or closed. This is a deliberate trade-off for rep focus, but it may conflict with expectations that "every opp gets at least one attempt."

**4. The "Shark Tank" / rep capacity model described in the brief does not exist in code.** There is no competitive assignment, no slot allocation, no load balancing. Each rep's queue is determined entirely by their Opportunity ownership. Actions are assigned to `Opportunity.OwnerId`, full stop. If 10 opps are created for one rep simultaneously, all 10 are that rep's responsibility. The term "Shark Tank" may refer to a planned feature, but it is not implemented.

**5. Suppression windows are extremely short.** The Recent Completion and Recent Valid Touch suppression rules use a CMDT-configured window of 0.083 hours (~5 minutes). The 60-minute CooldownUntil__c written to audit records does not effectively extend suppression beyond this window in the on-demand evaluation path. This means an opportunity can resurface as the top action within 5 minutes of being completed, which may or may not be intended.

---

## 2. System Architecture Overview

### Core Services / Modules

The engine is composed of 6 Apex service classes, 3 trigger handlers, 1 controller, and 1 cache service, plus 21 LWC components on the presentation layer.

**NbaActionController** (`NbaActionController.cls`, 462 lines)
The sole Apex entry point for the LWC. Exposes 5 `@AuraEnabled` methods: `getActiveAction()`, `checkInterrupts()`, `acceptInterrupt()`, `completeAction()`, `snoozeAction()`, `dismissAction()`. Orchestrates the full evaluation pipeline on cache miss. This is the traffic cop — it calls everything else.

**NbaSignalService** (`NbaSignalService.cls`, 434 lines)
Reads CRM state. Executes 7 batched SOQL queries (Opportunity, Talkdesk calls, Mogli SMS, Events, Tasks, Account_Scoring__c, existing NBA_Queue__c records) and assembles an `OpportunitySignal` wrapper per opportunity. This is the data layer — it does not make decisions, only observations.

**NbaActionCreationService** (`NbaActionCreationService.cls`, 856 lines)
The decision engine. For each signal: checks suppression rules, determines action type (First Touch / Re-engage / Stage Progression / Follow Up), resolves cadence step, calculates impact and urgency scores, assigns bucket and layer, builds an in-memory NBA_Queue__c record. Does NOT perform DML — returns a list of candidates.

**NbaCadenceService** (`NbaCadenceService.cls`, 505 lines)
The cadence engine. Loads 2-CMDT parent/child records (NBA_Cadence__mdt + NBA_Cadence_Step__mdt), determines the next cadence step based on prior outcomes and day gating, enforces spacing between calls, handles outcome-based branching (Connected → End, VM → Continue, No Answer → Continue, Meeting → End). Populates a transaction-scoped static map read by the controller and state service.

**NbaActionSelectionService** (`NbaActionSelectionService.cls`, 136 lines)
The ranking layer. Accepts a list of in-memory action candidates, applies gate filters (cooldown, workflow mode), then sorts by Layer (1 > 2 > 3) ascending, then Priority_Score descending. Returns the sorted list. The caller takes index [0].

**NbaActionStateService** (`NbaActionStateService.cls`, 289 lines)
The audit writer. When an AE completes, snoozes, or dismisses an action, this service writes an NBA_Queue__c record with the outcome, cadence progress, cooldown timestamps, and dismiss metadata. Also handles Layer 1 status transitions and stale action expiration.

**NbaCacheService** (`NbaCacheService.cls`, 130 lines)
Platform Cache wrapper. Stores the most recently evaluated ActionWrapper per AE user with a 5-minute TTL. Provides invalidation methods called by state transitions and trigger handlers.

### How Salesforce Interacts with the Engine

The system uses three interaction patterns:

**Pattern 1 — On-Demand Evaluation (Stream 1: Scored Queue)**
When the AE opens the GTM OS App Page, the LWC calls `getActiveAction()`. The controller checks Platform Cache. On cache miss, it executes the full pipeline: query open Opportunities (LIMIT 200) → NbaSignalService.getSignals() → NbaActionCreationService.evaluateAndCreate() → NbaActionSelectionService.rankActions() → return top action. Total cost: ~12 SOQL on miss, 0 on cache hit. Runs every 5 minutes via `setInterval()` in LWC.

**Pattern 2 — Real-Time Interrupts (Stream 2: Push + Poll)**
Salesforce triggers fire on Event insert/update/delete and Opportunity insert. These create persisted NBA_Queue__c records with Layer 1 priority and invalidate the AE's Platform Cache. The LWC polls `checkInterrupts()` every 15 seconds (2 SOQL) to detect these records and surface them as interrupt banners.

**Pattern 3 — AE Interaction → Audit → Re-evaluate**
When the AE clicks Complete/Snooze/Dismiss, the LWC calls the corresponding controller method. The controller delegates to NbaActionStateService (writes audit record, invalidates cache), then immediately re-evaluates via `getActiveAction()` to serve the next action.

### Where Evaluation Logic Lives

All scoring and ranking happens in `NbaActionCreationService.evaluateAndCreate()` (impact + urgency calculation, bucket/layer assignment) and `NbaActionSelectionService.rankActions()` (gate filtering + sort). Cadence resolution lives in `NbaCadenceService.getNextStep()`. The controller is thin — it orchestrates but does not decide.

### How Scoring Enters the System

External ML scoring enters via the `Account_Scoring__c` custom object. The only fields currently consumed are `Prob_Payroll_Conversion__c` and `Prob_Tier_Upgrade__c`. These are joined to opportunities via `Account__c` lookup. If Account_Scoring__c has no record for an account, the system falls back to `Opportunity.Deal_Stage_Probability__c` (a formula field).

MRR enters via `Opportunity.MRR__c` (formula field, not writable). Fallback is `Opportunity.Amount`.

### How Actions Are Stored

**Stream 1 (Scored Queue) actions are NOT stored.** They exist only in memory during evaluation, then in Platform Cache (5-min TTL) as serialized JSON. NBA_Queue__c records are created only as audit records when the AE interacts (complete/snooze/dismiss).

**Stream 2 (Interrupt) actions ARE stored.** Layer 1 records are persisted to NBA_Queue__c by triggers with status Pending. They transition to In Progress (accepted), Completed, Dismissed, Expired, or Snoozed.

### How Rep Assignment Works

Assignment is strictly by Opportunity ownership. `NBA_Queue__c.Sales_Rep__c = Opportunity.OwnerId`. There is no reassignment, no load balancing, no competitive claiming. The AE sees only their own opportunities.

### Push vs Polling

**Push** refers to trigger-based action creation. When an Event or Opportunity is inserted, the trigger handler synchronously creates an NBA_Queue__c Layer 1 record and invalidates the AE's cache. This is "push" in the sense that the system proactively creates the action without the AE requesting it.

**Polling** refers to the LWC's two `setInterval()` timers:
- Every 15 seconds: `checkInterrupts()` — 2 SOQL queries looking for Layer 1 records
- Every 5 minutes: `getActiveAction()` — cache check, full re-evaluation on miss

There is no WebSocket, no Platform Event, no Streaming API. The system is poll-based on the client side, push-based on the CRM side.

---

## 3. Data Inputs

### 3.1 Opportunity Fields

**Source:** Standard Opportunity object + custom formula fields.

**Fields consumed (NbaSignalService.cls lines 277-284):**
- `Id`, `Name`, `StageName`, `Amount`, `MRR__c` (formula), `OwnerId`, `AccountId`
- `CloseDate`, `IsClosed`
- `Deal_Stage_Probability__c` (formula or custom)
- `Days_Since_Last_Interaction__c` (formula — MIN of Days_Since_Last_Call and Days_Since_Last_Meeting, returns 99999 if both null)
- `Hours_Since_Assignment__c` (formula)
- `Days_Since_Creation__c` (formula)

**Refresh frequency:** Real-time (queried on every cache-miss evaluation).

**Usage in logic:**
- `MRR__c` / `Amount` → Impact score normalization (60% weight within impact)
- `Deal_Stage_Probability__c` → Close probability fallback (40% weight within impact)
- `Days_Since_Last_Interaction__c` → Action type determination (First Touch if 99999, Re-engage if >= 5, Late Stage if >= 3 at stage 4+)
- `Hours_Since_Assignment__c` → SLA First Touch detection (<= 1 hour)
- `StageName` → Stage number mapping (New=1, Connect=2, Consult=3, Evaluating=3, Closing=4, Verbal Commit=5, Ready to Convert=5, Hand-Off=0)
- `IsClosed` → Hard suppression

**Failure implications:** If formula fields return null (broken formula, missing source fields), the system defaults safely: `Days_Since_Last_Interaction = null` maps to action type Follow Up (the catch-all). `MRR__c = null` falls back to Amount, then to 0. Scoring degrades but does not break.

### 3.2 External MRR Score / Account-Level Scoring

**Source:** `Account_Scoring__c` custom object, populated by an external data pipeline (not part of this codebase).

**Fields consumed (NbaSignalService.cls lines 377-387):**
- `Account__c` (lookup to Account)
- `Prob_Payroll_Conversion__c` (Decimal, 0-100 range)
- `Prob_Tier_Upgrade__c` (Decimal, 0-100 range — present but not used in scoring)

**Refresh frequency:** Unknown to the engine. The service queries whatever is in the table at evaluation time. Per CLAUDE.md: "Account_Scoring__c has only 3 records" currently, indicating the pipeline is not yet at scale.

**Usage in logic (NbaActionCreationService.cls lines 626-633):**
- If `Account_Scoring__c` exists for the account, `Prob_Payroll_Conversion__c / 100` is used as the close probability component (40% of impact score)
- If no Account_Scoring__c record exists, falls back to `Opportunity.Deal_Stage_Probability__c / 100`
- If both are null, defaults to `0.30`

**Failure implications:** If the Account_Scoring__c table is empty, stale, or missing records, the system silently falls back to Deal_Stage_Probability__c. There is no alerting, no staleness check, no timestamp validation. The engine does not know whether a Prob_Payroll_Conversion value of 0.12 was calculated yesterday or six months ago. This is a critical dependency gap.

### 3.3 Expansion Value

**Not explicitly implemented as a standalone input.** The term "expansion value" from the brief does not correspond to a specific field or scoring component. The closest equivalent is the MRR__c / Amount field on the opportunity, which is used in the impact score. There is no separate "expansion" scoring path.

### 3.4 Talkdesk Call Activity

**Source:** `talkdesk__Talkdesk_Activity__c` (managed package object).

**Fields consumed (NbaSignalService.cls lines 290-300):**
- `talkdesk__Opportunity__c` (lookup)
- `talkdesk__Type__c` (filtered to 'Outbound'/'Inbound')
- `talkdesk__DispositionCode__r.talkdesk__Label__c` (disposition label via relationship)
- `talkdesk__Total_Talk_Time_sec__c` (call duration)
- `CreatedDate`

**Refresh frequency:** Queried with `CreatedDate >= LAST_N_DAYS:7`. Returns up to 1000 records per evaluation batch.

**Usage in logic:**
- Most recent call date → `lastCallDate` (used for spacing checks, Connected Follow-up 4h window)
- Disposition starts with "Connected" AND talk time > 0 → `hadConnectedCall` (triggers Stage Progression action type, cadence exit condition)
- Disposition starts with "Attempted" OR talk time = 0 → `hadNoConnect` (triggers method escalation hints: "Try SMS")
- Count of today's calls → `todayCallCount` (available for spacing/caps)
- Today's call timestamps → `todayCallDates` (available for spacing)

**Failure implications:** If Talkdesk activities are not linked to opportunities (common for support calls), they are not fetched. If the managed package is unavailable, the SOQL query will fail and the entire evaluation fails. There is no try-catch around the Talkdesk query.

### 3.5 Mogli SMS Activity

**Source:** `Mogli_SMS__SMS__c` (managed package object).

**Fields consumed (NbaSignalService.cls lines 314-323):**
- `Mogli_SMS__Opportunity__c` (lookup)
- `Mogli_SMS__Direction__c` (Incoming/Outgoing)
- `Mogli_SMS__Status__c` (filtered: != 'Error')
- `CreatedDate`

**Refresh frequency:** `CreatedDate >= LAST_N_DAYS:7`. Most recent SMS per opp (LIMIT 1000, first per opp wins).

**Usage in logic:**
- `lastSmsDate` → contributes to `lastValidTouchDate` computation
- `hadIncomingReply` → available in signal but not directly used in scoring (reserved for future)

### 3.6 Meeting / Event Data

**Source:** Standard Event object.

**Fields consumed (NbaSignalService.cls lines 335-343):**
- `WhatId` (filtered to Opportunity IDs)
- `StartDateTime`

**Query window:** `StartDateTime >= NOW AND <= NOW + 24 hours`. Nearest event per opp.

**Usage in logic:**
- `hasUpcomingMeeting` → Suppression (meeting within 24h suppresses scored-queue action creation)
- `upcomingMeetingStart` → Available in signal
- Trigger: Event insert within 24h → creates Layer 1 time-bound action with `DueAt__c = StartDateTime`
- Trigger: Event update → updates DueAt__c on existing Layer 1 record
- Trigger: Event delete → expires existing Layer 1 record

### 3.7 Task Completion Data

**Source:** Standard Task object.

**Fields consumed (NbaSignalService.cls lines 355-362):**
- `WhatId` (filtered to Opportunity IDs)
- `ActivityDate`, `TaskSubtype`, `CreatedDate`
- Filtered: `Status = 'Completed'`

**Query window:** No time limit (all completed tasks, ordered by ActivityDate DESC, LIMIT 1000).

**Usage in logic:**
- `lastTaskDate` → contributes to `lastValidTouchDate`
- TaskTriggerHandler: completed call task → increment `Attempt_Count_Today__c` on existing active actions, update context, invalidate cache

### 3.8 Cadence Stage / Progress

**Source:** NBA_Queue__c audit records (self-referential).

**Fields consumed (NbaSignalService.cls lines 394-408):**
- From completed audit records within last 1 hour: `Cadence_Name__c`, `Cadence_Step_Number__c`, `Step_Outcome__c`, `Step_Method__c`
- `Completed_Date__c`, `Snoozed_Until__c`, `CooldownUntil__c`

**Usage in logic:**
- `lastCadenceName` + `lastCadenceStepNumber` + `lastCadenceStepOutcome` → CadenceService resolves next step via branching logic
- `lastCompletedDate` → Recent Completion suppression check
- `snoozedUntilDate` → Snoozed Action suppression check

### 3.9 Rep Capacity Data

**Not implemented as an explicit input.** There is no rep capacity table, no slot count, no workload measurement. The system evaluates all of a rep's open opportunities (up to 200) and returns the top-ranked one. The implicit "capacity" is 1 action at a time — the rep works one action, completes it, gets the next.

### 3.10 Time-Based Signals

All time-based signals are derived from Salesforce formula fields or computed at evaluation time:
- `Days_Since_Last_Interaction__c` — Opportunity formula (real-time)
- `Hours_Since_Assignment__c` — Opportunity formula (real-time)
- `Days_Since_Creation__c` — Opportunity formula (real-time)
- `Datetime.now()` comparisons — computed during evaluation for spacing, cooldown, expiration
- `DueAt__c` on Layer 1 records — compared to now for interrupt surfacing (meeting within 5 min)

There is no cron-based time signal, no batch recalculation. All time comparisons happen at the moment of evaluation.

---

## 4. Prioritization Logic

This is the most critical section. The following describes exactly how the engine decides which action to surface, based on the implemented code.

### 4.1 How Priority Score Is Calculated

Priority is a composite numeric score stored as `Priority_Score__c` on the in-memory NBA_Queue__c candidate. It is calculated in `NbaActionCreationService.evaluateAndCreate()` (lines 120-124):

```
Priority_Score = (Impact_Weight × Impact_Score) + (Urgency_Weight × Urgency_Score)
```

Where from the active CMDT record `NBA_Impact_Weight.Default_V2`:
- `Impact_Weight` = 0.50
- `Urgency_Weight` = 0.50

**Impact Score** (line 636-637):
```
Impact_Score = (MRR_Weight × Normalized_MRR) + (Close_Prob_Weight × Close_Probability)
```
Where:
- `MRR_Weight` = 0.60
- `Close_Prob_Weight` = 0.40
- `Normalized_MRR` = `min(opp.MRR / maxMRR_across_all_opps, 1.0)` — MRR is normalized **relative** to the highest MRR in the current evaluation batch (with a floor of $50,000)
- `Close_Probability` = `Account_Scoring.Prob_Payroll_Conversion / 100` (if available), else `Opportunity.Deal_Stage_Probability / 100` (if available), else `0.30`

**Urgency Score** (lines 646-675):
```
Urgency = Base_Urgency × (multiplier₁ × multiplier₂ × ... ), capped at 2.0
```
Where:
- `Base_Urgency` = 0.50
- Multipliers come from active NBA_Urgency_Rule__mdt records:
  - **SLA_First_Touch** (multiplier 2.0): Applied when action type is First Touch. Result: `0.50 × 2.0 = 1.0`
  - **Late_Stage_Inactivity** (multiplier 1.5): Applied when Stage >= 4 AND Days_Since_Last_Interaction >= 3
  - **Stage_Pressure** (multiplier 1.2): Applied when Stage >= 3 AND Days_Since_Last_Interaction >= 7
  - **Re_Engage_Cold** (multiplier — value not in local CMDT but exists): Applied for cold inactivity scenarios
- Urgency multipliers are **multiplicative**, not additive. Multiple rules can fire. Example: Stage 4 with 8 days inactivity → Late_Stage_Inactivity (1.5) × Stage_Pressure (1.2) = `0.50 × 1.5 × 1.2 = 0.90`, which is under the 2.0 cap.

**Final score range:** The practical range of Priority_Score is approximately 0.25 (low MRR, no urgency) to ~1.25 (high MRR, max urgency). A theoretical maximum is `(0.50 × 1.0) + (0.50 × 2.0) = 1.50` but this requires maximum impact AND maximum urgency simultaneously.

### 4.2 Whether MRR Score Is Absolute or Relative

**MRR normalization is RELATIVE.** The `calculateMaxMrr()` method (line 804-813) computes the maximum MRR across all opportunities in the current evaluation batch. Each opportunity's MRR is then divided by this maximum. This means the MRR component of impact is always relative to the rep's current pipeline.

The minimum divisor is `DEFAULT_MRR_CEILING = 50000`. If no opportunity exceeds $50K, that floor is used. If any opportunity exceeds $50K, the actual max becomes the divisor.

**Implication:** If a rep has one $100K opportunity and ninety-nine $1K opportunities, the $100K opp gets a normalized MRR of 1.0 and the $1K opps get 0.01. The relative normalization ensures the high-value opp dominates. But it also means that in a pipeline of only low-value opps (all under $50K), the relative differences become compressed — a $5K opp might score 0.10 while a $4K opp scores 0.08, making urgency the tiebreaker.

### 4.3 Whether Scoring Is Weighted or Sorted

**Scoring is weighted (not tier-sorted).** Impact and urgency are combined into a single continuous score. There is no bucketing where "all High impact opps come before Medium impact opps." A low-impact, high-urgency opportunity CAN outrank a high-impact, low-urgency one.

However, there IS a layer-based sort that happens AFTER scoring. The sort order is:
1. **Layer (ascending):** Layer 1 > Layer 2 > Layer 3
2. **Within each layer, Priority_Score (descending)**

In practice, Layer 1 is only assigned to SLA First Touch opps (assigned <= 1 hour ago) in the scored-queue path. Most opps are Layer 3. So layer sorting rarely changes the outcome for the scored queue — it mainly ensures that SLA First Touch opps surface before everything else.

### 4.4 Where in the Pipeline Ranking Happens

Ranking happens at two points:

**Point 1 — Creation-time ordering (NbaActionCreationService):**
Each opportunity gets a Priority_Score during `evaluateAndCreate()`. The SOQL query in `NbaActionSelectionService.selectTop()` (for DB-persisted actions) orders by `Priority_Score__c DESC`. But in the on-demand path, ranking is applied in-memory.

**Point 2 — Final selection (NbaActionSelectionService.rankActions()):**
The full list of in-memory candidates is gated (cooldown, mode filter), then sorted via a custom Comparator: Layer ASC, then Score DESC. The first element is returned.

### 4.5 Whether Ranking Happens Before or After Cadence Evaluation

**Cadence evaluation happens BEFORE ranking.** The pipeline is:

1. For each opportunity signal → check suppression
2. Determine action type (First Touch, Re-engage, etc.)
3. **Resolve cadence step** (NbaCadenceService.getNextStep) — this can suppress the action if day-gated or spacing-restricted
4. If cadence suppresses → try fallback non-cadence action type
5. Calculate impact and urgency scores
6. Assign bucket and layer
7. Build candidate record
8. After all candidates are built → gate filter + sort → return top

Cadence does not influence the priority score directly. Cadence determines *what* the action instruction is (Call vs SMS vs Email) and *whether* the action is eligible at all (day gating, spacing). But it does not add or subtract from the numeric score. A First Touch opp at cadence step 1 has the same priority score as the same opp at cadence step 12 (all else equal).

### 4.6 How Low-Score Opportunities Behave Today

**Low-score opportunities are systematically deprioritized with no recovery mechanism.**

Consider a rep with 100 open opportunities. The engine:
1. Queries all 100 (LIMIT 200)
2. Evaluates all 100 through suppression → type → cadence → scoring
3. Suppressed opps are removed (maybe 20 for cooldown, meetings, snoozed, closed)
4. Remaining ~80 are scored
5. The top 1 is served

The bottom-ranked opportunities never surface unless:
- All higher-ranked opportunities are suppressed (completed/snoozed/dismissed)
- The higher-ranked opportunities are closed
- The lower-ranked opportunity's urgency increases over time (e.g., days of inactivity trigger urgency multipliers)

There is no random injection, no rotation, no minimum-attempts-per-opp rule, no time-based promotion.

**Natural urgency escalation does exist.** As an opportunity goes unworked, `Days_Since_Last_Interaction__c` increases. At 3 days + Stage 4+, Late_Stage_Inactivity fires (1.5x). At 7 days + Stage 3+, Stage_Pressure fires (1.2x). These multipliers can eventually push a neglected opp above a recently-worked one. But this only works if the opp is at a sufficient stage — early-stage opps with low MRR will stay at the bottom indefinitely.

### 4.7 The 100-Opportunity Question

**If we have 100 opps, how does the engine decide which 10 appear first?**

The engine does not show 10 — it shows exactly 1. But the implicit ordering of the top 10 would be:

1. Any Layer 1 SLA First Touch (assigned < 1 hour ago): These get both Layer 1 priority AND a 2.0x urgency multiplier, making them virtually always #1.
2. Remaining opps are all Layer 3, sorted by `(0.50 × Impact) + (0.50 × Urgency)` descending.
3. High MRR + high Prob_Payroll_Conversion + urgency multipliers → top of list.
4. Low MRR + default probability (0.30) + base urgency (0.50) → bottom of list.

A $50K MRR opp with ML-scored 80% conversion probability and 5 days cold would score approximately: `(0.50 × (0.60 × 1.0 + 0.40 × 0.80)) + (0.50 × min(0.50 × 1.5, 2.0))` = `(0.50 × 0.92) + (0.50 × 0.75)` = `0.46 + 0.375` = `0.835`.

A $5K MRR opp with no ML scoring and no urgency would score: `(0.50 × (0.60 × 0.10 + 0.40 × 0.30)) + (0.50 × 0.50)` = `(0.50 × 0.18) + (0.50 × 0.50)` = `0.09 + 0.25` = `0.34`.

The $50K opp would be worked before the $5K opp, period.

**What prevents low-score opps from never being worked?**

**Nothing prevents it today.** The only mechanisms that could eventually surface a low-score opp are:
1. The AE completes/snoozes/dismisses all higher-scored opps (unlikely with 100 opps)
2. Higher-scored opps close (won or lost)
3. Urgency multipliers eventually fire on the low-score opp (requires sufficient stage progression and time — may never happen for Stage 1 opps)
4. The AE manually navigates to the opp record page and works it outside the system

There is no randomization, no guaranteed minimum touches, no experimentation bucket. **This is stated clearly because it is a deliberate design choice, but it has consequences for scoring model validation.**

---

## 5. Cadence Logic

### 5.1 How Cadence State Is Stored

Cadence state is distributed across three locations:

**Definition (what the cadence looks like):** Stored in Custom Metadata Types.
- `NBA_Cadence__mdt` (parent): Defines the cadence name, scenario (action type), variant (A/B), total steps, total days, anchor field, exit conditions, and day map.
- `NBA_Cadence_Step__mdt` (child): Defines individual steps — step number, day number, method (Call/SMS/Email), instruction text, spacing minutes, and per-outcome branching actions.

Currently deployed cadences:
- **First_Touch_A**: 12 steps across 5 days (D0: Call→SMS→Call→Email→Call, D1: Call→Call→SMS→Email, D3: Email→Call, D5: Breakup email). Exit on Connected_Call, Meeting_Scheduled, or Opp_Closed.
- **Re_engage_A**: 6 steps across 7 days (D0: Call+Email, D1: Call, D3: SMS, D5: Email, D7: Call). Same exit conditions.

**Progress (where the AE is in the cadence):** Stored on NBA_Queue__c audit records.
- `Cadence_Name__c` — which cadence was active
- `Cadence_Step_Number__c` — which step was just completed
- `Step_Outcome__c` — what happened (Connected, VM, No_Answer, Sent)
- `Completed_Date__c` — when the step was completed

Progress is read from the most recent completed audit record for an opportunity during signal enrichment (NbaSignalService.cls lines 229-237). It is not stored on the Opportunity itself.

**Current position (derived):** Computed in NbaCadenceService.getNextStep(). Not stored anywhere — recalculated on every evaluation.

### 5.2 How Cadence Steps Are Triggered

Cadence steps are **not triggered by events**. They are resolved during on-demand evaluation:

1. AE completes current action → audit record written with `Step_Outcome__c`
2. Cache invalidated → next `getActiveAction()` re-evaluates
3. During evaluation, NbaCadenceService reads the last audit record's step number and outcome
4. Branching logic determines the next step number
5. Day gating checks whether that step's day has arrived
6. Spacing checks whether enough time has passed since the last call
7. If all gates pass, the step becomes the current action instruction

Cadence progression is inherently tied to AE interaction — the cadence does not advance on its own. It advances when the AE completes a step and the system re-evaluates.

### 5.3 Whether Cadence Is Deterministic or Conditional

**Cadence is conditional.** The outcome of each step determines the next step via branching rules:

- **Connected** → Default: End_Cadence. Can be overridden per step to Skip_To_Step or Skip_To_Day.
- **VM (Voicemail)** → Default: Continue (next sequential step). Can be overridden.
- **No_Answer** → Default: Continue. Can be overridden.
- **Meeting_Scheduled** → Default: End_Cadence. Can be overridden.
- **Sent** (SMS/Email) → Always: Continue to next sequential step.
- **null outcome** (first step or missing data) → Continue.

So two reps running the same cadence may follow different paths. One gets a connection on step 1 and exits. Another gets voicemails for 12 steps and follows the full cadence.

### 5.4 What Signals Feed Cadence Progression

- `signal.lastCadenceStepNumber` — extracted from most recent completed NBA_Queue__c audit record
- `signal.lastCadenceStepOutcome` — extracted from same
- `signal.lastCadenceStepDate` — extracted from same
- `signal.daysSinceCreation` (or `daysSinceLastInteraction` depending on anchor) — used for day computation
- `signal.lastCallDate` — used for spacing enforcement
- `signal.hadConnectedCall` — exit condition check
- `signal.hasUpcomingMeeting` — exit condition check
- `signal.isClosed` — exit condition check

### 5.5 Whether Cadence Influences Priority

**Cadence does NOT influence priority score.** A cadenced action has the same Impact_Score and Urgency_Score as a non-cadenced action for the same opportunity. Cadence only determines (a) the instruction text, (b) whether the action is suppressed (day gate, spacing), and (c) the method (Call/SMS/Email).

### 5.6 Whether Cadence Can Override Priority

**Cadence can suppress an action but cannot boost it.** If a cadence step is day-gated (e.g., step 6 is scheduled for Day 1 but today is Day 0), the entire action for that opportunity is suppressed. The cadence fallback logic then tries `determineNonCadenceActionType()` — if that also returns null, the opportunity is fully suppressed for this evaluation cycle.

Cadence cannot force an opportunity to the top of the queue regardless of its score.

### 5.7 Ordering: Cadence Creates Eligibility, Then Priority Sorts

The ordering is:

1. **Cadence creates eligibility:** For each opp, cadence determines *whether* an action is eligible (pass day gate, pass spacing, not exited) and *what* the action instruction is.
2. **Priority sorts among eligible actions:** All eligible candidates (both cadenced and non-cadenced) are scored identically by impact + urgency, then sorted by layer + score.

Cadence does not create a separate eligibility tier. A cadenced First Touch at step 3 competes on equal footing with a non-cadenced Re-engage, scored purely by the numeric priority.

---

## 6. Action Creation Engine

### 6.1 When Actions Are Created

Actions are created at two distinct times:

**On-Demand (Stream 1):** When `getActiveAction()` encounters a cache miss, it runs the full evaluation pipeline. `NbaActionCreationService.evaluateAndCreate()` builds in-memory NBA_Queue__c records for all eligible opportunities. These are NOT inserted into the database — they exist only for the duration of the ranking step. The top-ranked action is serialized to Platform Cache and returned to the LWC.

**Trigger-Based (Stream 2):** When specific CRM events occur, trigger handlers create persisted NBA_Queue__c records:
- `EventTrigger` (AFTER_INSERT) → `createTimeBoundAction()`: Meeting within 24h → Layer 1 time-bound record
- `EventTrigger` (AFTER_UPDATE) → `updateTimeBoundAction()`: Rescheduled meeting → update DueAt__c
- `EventTrigger` (AFTER_DELETE) → `cancelTimeBoundAction()`: Cancelled meeting → Status = Expired
- `OpportunityTrigger` (AFTER_INSERT) → `createNewAssignmentActions()`: New opp → Layer 1 non-time-bound interrupt record

### 6.2 What Triggers Action Creation

**Stream 1:** The AE opening the App Page, or the 5-minute `setInterval` timer firing, or the AE completing an action (which triggers immediate re-evaluation).

**Stream 2:**
- Insert of an Event linked to an Opportunity with StartDateTime within 24 hours
- Insert of an Opportunity in a non-excluded stage (not Hand-Off, Closed Won, Closed Lost)

### 6.3 Whether Actions Are Pre-Generated or On-Demand

**Stream 1 actions are generated on demand.** There is no pre-generation, no batch job, no scheduled creation. The original Phase 2 architecture used `NbaActionCreationSchedulable` (10-minute cron jobs) to pre-create records, but this was **deactivated in Phase 5**. The schedulable classes still exist in the codebase but are no-ops.

**Stream 2 actions are pre-generated** (trigger-based, synchronous). They are created the moment the CRM event occurs.

### 6.4 The 5-Minute Evaluation and 15-Second Poll

**5-Minute Full Refresh (Stream 1)** — `nbaDemoWorkspace.js` line 78:
```javascript
this._fullRefreshInterval = setInterval(() => {
    if (!this.isTransitioning && !this.isLoading) {
        this._refreshActiveAction();
    }
}, 300000);  // 5 minutes
```
This calls `getActiveAction()` which checks Platform Cache (5-min TTL). On cache hit: returns cached action (0 SOQL). On cache miss: runs full evaluation (~12 SOQL). In practice, the cache almost always hits within 5 minutes of the last miss, so the "snapshot" is the most recently evaluated state, refreshed every ~5 minutes.

**15-Second Interrupt Poll (Stream 2)** — `nbaDemoWorkspace.js` line 70:
```javascript
this._interruptPollInterval = setInterval(() => {
    if (!this.isTransitioning && !this.isLoading) {
        this._checkInterrupts();
    }
}, 15000);  // 15 seconds
```
This calls `checkInterrupts()` which runs 2 lightweight SOQL queries:
1. Meetings with `DueAt__c <= now+5min AND DueAt__c >= now-15min` (not expired, not too far out)
2. New-assignment interrupts with `CreatedDate >= now-24h`

Both queries only return records in Status New/Pending/Accepted, excluding In Progress (already accepted).

### 6.5 How Time-Bound Events Are Handled

When a meeting is scheduled on an opportunity:
1. `EventTrigger.AFTER_INSERT` fires
2. `NbaEventTriggerHandler` filters: `WhatId` is Opportunity, `StartDateTime` within 24h, future only
3. `NbaActionCreationService.createTimeBoundAction()` builds a Layer 1 record with `Is_Time_Bound__c = true`, `DueAt__c = StartDateTime`
4. Dedup via UniqueKey: `'V2|' + oppId + '|Meeting|' + eventId`
5. Record is inserted to NBA_Queue__c
6. Cache is invalidated for the AE

The LWC's 15-second poll picks up this record when `DueAt__c` is within 5 minutes of now. It surfaces as an indigo interrupt banner. The AE can accept it (sets status to In Progress, pauses scored-queue action) or dismiss it.

After the meeting time passes by 15 minutes, `NbaActionStateService.expireStaleActions()` would expire the record. However, this expiration method must be called explicitly — it is invoked by the now-deactivated `NbaActionExpirationSchedulable`. In the current architecture, stale time-bound records expire naturally when the 15s poll stops returning them (DueAt < now - 15min).

### 6.6 Is There a Remaining Cache Concept?

**Yes.** The Platform Cache (`Cache.OrgPartition` named `local.NbaActionCache`) serves as a 5-minute TTL cache for the scored-queue action. It stores a JSON-serialized `ActionWrapper` per AE user.

The cache is NOT a queue or a pre-computed list. It stores exactly one action per AE. On cache hit, that action is returned without any evaluation. On cache miss (expired, invalidated, or first load), the full pipeline runs.

Cache invalidation occurs:
- After complete/snooze/dismiss (NbaActionStateService)
- After Event trigger fires (NbaEventTriggerHandler)
- After Opportunity trigger fires (NbaOpportunityTriggerHandler)
- After stale action expiration (NbaActionStateService.expireStaleActions)

The cache is resilient: if the Platform Cache partition is unavailable, all operations silently degrade to cache-miss behavior (full evaluation on every call). Errors are caught and logged as warnings.

---

## 7. Rep Capacity & Shark Tank Logic

### 7.1 How Rep Slots Are Calculated

**There are no rep slots.** The system does not track, allocate, or limit the number of actions available to a rep. Every evaluation considers all of the rep's open opportunities (up to LIMIT 200) and returns the single best one.

The implicit "capacity" is 1 concurrent action. The rep works one action. When they complete it, the system serves the next. There is no parallel work queue.

### 7.2 What Defines "Available"

An opportunity is "available" (eligible for action creation) if it passes ALL suppression checks:

1. `isClosed == false` (not closed)
2. `StageName NOT IN ('Hand-Off', 'Closed Won', 'Closed Lost')` (not excluded stage)
3. `hasActiveAction == false` (no existing active/pending/in-progress NBA_Queue__c record)
4. `hasUpcomingMeeting == false` (no meeting within 24h — suppressed to avoid conflict)
5. No active snooze (`snoozedUntilDate` not in the future)
6. No recent completion (hoursSinceComplete > 0.083h ≈ 5 min)
7. No recent valid touch (hoursSinceTouch > 0.083h ≈ 5 min)
8. Cadence day gate passes (if cadenced)
9. Call spacing gate passes (if cadenced call step)

### 7.3 What Happens When a Rep Finishes a Task

1. LWC dispatches `actioncomplete` event with `stepOutcome`
2. `nbaDemoWorkspace` calls `NbaActionController.completeAction(actionId, oppId, actionType, stepOutcome)`
3. Controller → `NbaActionStateService.completeAction()`:
   - If Layer 1 (has actionId): updates persisted record to Status=Completed
   - Writes audit NBA_Queue__c record with Completed_Date, CooldownUntil (+60min), cadence fields, stepOutcome
   - Invalidates Platform Cache
4. Controller → `getActiveAction()` immediately re-evaluates
5. Returns `ActionResultWrapper` with the next best action (or null if "All caught up!")
6. LWC renders the new action (or empty state)

The entire cycle — complete → audit → re-evaluate → serve next — happens in a single Apex transaction.

### 7.4 How Next Action Is Selected

The next action is selected by running the full evaluation pipeline:
1. Query rep's open opps (1 SOQL)
2. Signal enrichment (7 SOQL)
3. Suppression → type → cadence → scoring → bucket/layer for each opp (3-4 SOQL for CMDT)
4. Gate filter → sort by Layer ASC, Score DESC (1 SOQL for cooldown rules)
5. Return index [0]

The just-completed opportunity is eligible again after ~5 minutes (Recent Completion suppression window). If the cadence has another step available, it may resurface immediately after the suppression window expires. This is by design — cadence steps progress one at a time.

### 7.5 Whether Assignment Is Deterministic or Competitive

**Assignment is fully deterministic.** Every action is assigned to `Opportunity.OwnerId`. There is no competitive claiming, no round-robin, no weighted distribution. Two reps never compete for the same action.

The only "competition" is between a rep's own opportunities — they compete for the single action slot via the priority score.

---

## 8. Low MRR Score Strategy Evaluation

### Current Behavior

Low-score opportunities are deprioritized by the weighted scoring model and remain at the bottom of the evaluation ranking indefinitely. If a rep has 50+ opportunities with varying scores, the bottom quartile may never be surfaced unless:
- Higher-ranked opps are cleared through the pipeline (completed, closed, snoozed long-term)
- Urgency multipliers fire (requires sufficient stage + time — early-stage low-MRR opps never benefit)
- The external Prob_Payroll_Conversion score is updated (the only way to change the probability component)

In the worst case, a Stage 1 opportunity with $2K MRR and no Account_Scoring would score approximately 0.31. It would need every opportunity scoring above 0.31 to be suppressed before it surfaces. For a rep with 30 active opps, this may never happen during the opportunity's lifecycle.

### Option A: Strict Prioritization (Current — Pure Score Ordering)

**Description:** No change. The engine always serves the highest-scoring eligible action. Low-score opps only surface when nothing better is available.

**Engineering complexity:** Zero — this is the current state.

**Impact on rep focus:** Maximum. Reps always work the mathematically highest-value action. No distractions.

**CRO alignment risk:** LOW for "focus the team on high-value opps." HIGH if the CRO expects "every opp gets at least one attempt" or wants to validate the scoring model's accuracy on low-score opps.

**Data science benefit:** None. Low-score opps are never worked, so there is no outcome data to validate whether the model correctly scored them low. The scoring model operates in a self-reinforcing loop: it scores opps low, they are never worked, we have no data to challenge the score.

### Option B: Weighted Random Sampling (5% Injection of Low-Score Opps)

**Description:** On every evaluation, there is a 5% chance the engine returns a randomly selected low-score opportunity instead of the top-ranked one. "Low-score" defined as bottom quartile by Priority_Score.

**Implementation sketch:**
- After ranking, if `Math.random() < 0.05`, select a random opp from bottom 25% of candidates
- Tag it with a flag `Is_Experiment__c = true` for analytics
- Return it instead of the top-ranked action

**Engineering complexity:** LOW. Approximately 15-20 lines of code in `NbaActionSelectionService.rankActions()`. Requires a new checkbox field on NBA_Queue__c for tracking.

**Impact on rep focus:** MINIMAL but noticeable. 1 in 20 actions would feel "wrong" to the rep — they'd be asked to call a low-value opp when they know a high-value one is waiting. This erodes trust in the system.

**CRO alignment risk:** MEDIUM. The CRO may object to "wasting" even 5% of rep capacity on low-priority work. The counter-argument is that it's 5% of capacity for scoring model validation, which improves future prioritization.

**Data science benefit:** MODERATE. Generates outcome data for ~5% of low-score opps. Statistically useful over weeks, but small sample sizes per individual opp.

### Option C: Controlled Experimentation Bucket (Quota-Based Trial)

**Description:** Reserve a fixed number of daily "experiment slots" (e.g., 2 per rep per day). When the rep has completed their experiment quota for the day, the system reverts to pure score ordering. Experiment actions are drawn from the bottom quartile.

**Implementation sketch:**
- New field `Experiment_Count_Today__c` on NBA_Queue__c (or tracked in-memory per AE session)
- After the AE completes an action, check if `experimentCountToday < DAILY_EXPERIMENT_QUOTA`
- If under quota, next action is drawn from bottom 25% (oldest first, or random)
- Tag with `Is_Experiment__c = true`
- After quota is met, revert to pure score ordering for the rest of the day

**Engineering complexity:** MEDIUM. Requires:
- A daily counter per AE (could use Platform Cache or a field on NBA_AE_Config__c)
- Quota configuration (CMDT or custom setting)
- Modified selection logic in NbaActionSelectionService
- Reset mechanism (scheduled job or date-based check)
- ~50-80 lines of new code

**Impact on rep focus:** CONTROLLED. Reps know they'll get 2 "experimental" actions per day, then the system returns to pure prioritization. Predictable and bounded.

**CRO alignment risk:** LOW-MEDIUM. The CRO can set the quota (even 0 to disable). The rep's perception is managed: "The system occasionally tests lower-priority opps to improve its scoring — you'll get at most 2 per day."

**Data science benefit:** HIGH. Guaranteed outcome data for bottom-quartile opps. Over 20 reps × 2 per day × 20 work days = 800 experiment actions per month. Statistically significant for model validation.

### Recommendation

**Option C (Controlled Experimentation Bucket)** is recommended. Rationale:

1. It directly solves the data science validation problem with guaranteed sample sizes.
2. The quota bounds the CRO risk — it's not random interruption, it's a measurable, adjustable knob.
3. The engineering cost is modest (medium complexity, no architectural changes).
4. It preserves prioritization integrity for >90% of the rep's day.
5. The `Is_Experiment__c` flag enables clean before/after analysis by the data team.

A daily quota of 2 per rep is a reasonable starting point. This can be tuned via CMDT/custom setting without code changes.

---

## 9. Edge Cases & Failure Modes

### 9.1 Missing Score

**Missing MRR__c:** Falls back to `Opportunity.Amount`. If both null, MRR component = 0. The opportunity gets a low impact score but is not suppressed.

**Missing Account_Scoring__c:** Falls back to `Opportunity.Deal_Stage_Probability__c`. If null, defaults to 0.30 (30%). The opportunity is scored with a moderate probability assumption.

**Missing both:** Impact score becomes `(0.60 × 0) + (0.40 × 0.30) = 0.12`. Combined with base urgency of 0.50: Priority_Score ≈ 0.31. This is the floor — the opportunity is ranked but always near the bottom.

**No urgency rules match:** Urgency stays at base 0.50. Priority_Score = `(0.50 × Impact) + (0.50 × 0.50)`. The urgency component contributes 0.25 regardless of opp state.

### 9.2 Stale Score

**Account_Scoring__c data:** The engine does not check when Account_Scoring__c was last updated. If the record was populated 6 months ago and the account's situation has changed, the system uses the stale score with no warning.

**Platform Cache staleness:** The cache TTL is 5 minutes. If CRM data changes within 5 minutes of the last evaluation, the cached action may be based on outdated signals. Cache invalidation from triggers (Event, Opportunity, Task) mitigates this for trigger-based changes but not for manual field edits.

**Formula field staleness:** `Days_Since_Last_Interaction__c`, `Hours_Since_Assignment__c`, and `Days_Since_Creation__c` are formula fields evaluated by Salesforce at query time. They are always current within the evaluation transaction.

### 9.3 Conflicting Signals

**Upcoming meeting + scored-queue action:** If an opportunity has both a meeting within 24h AND a scored-queue action, the meeting suppresses the scored-queue action (Upcoming Meeting suppression rule). The time-bound Layer 1 action takes precedence via the interrupt stream. After the meeting passes, the scored-queue action becomes eligible again.

**Connected call + cadence continuation:** If the Talkdesk activity shows a connected call, the cadence exit condition `Connected_Call` fires and ends the cadence. But the `hadConnectedCall` flag is derived from the most recent call in the last 7 days. If a connected call happened 5 days ago and the cadence has already progressed past it (because the AE completed subsequent steps), the exit condition would retroactively fire and end the cadence. This is a potential edge case: the `hadConnectedCall` flag does not distinguish between a connection that has already been accounted for and a new one.

**Snoozed + completed in same evaluation:** If the NbaSignalService query returns both a Snoozed record and a Completed record for the same opp, both contribute to signal state. The Snoozed record sets `hasSnoozedAction = true` if `snoozedUntilDate > now()`. The Completed record sets `lastCompletedDate`. If both are active, suppression checks fire sequentially — the first matching rule wins. In practice, the Snoozed check fires before Recent Completion.

### 9.4 Duplicate Actions

**Stream 1 (Scored Queue):** Duplicates are impossible because actions are evaluated in memory and only one is returned. There is no persistence, so no duplicate records.

**Stream 2 (Layer 1 Interrupts):** Deduplication is enforced via `UniqueKey__c`:
- Meetings: `'V2|' + oppId + '|Meeting|' + eventId`
- New assignments: `'V2|' + oppId + '|First Touch|NewAssignment'`

The dedup check queries for existing records with the same UniqueKey. If found, creation is skipped and null is returned.

**Race condition:** If two Event inserts fire simultaneously for the same event (theoretically impossible in Salesforce but possible with API concurrent requests), both could pass the dedup SOQL check before either inserts. This would create duplicates. Mitigation: a unique index on `UniqueKey__c` would prevent DB-level duplicates but is not currently configured (the field is a standard text field, not a unique external ID).

### 9.5 Time Zone Issues

All datetime comparisons use `Datetime.now()`, which returns the server time (UTC in most Salesforce instances) or the running user's timezone depending on context. In Apex, `Datetime.now()` returns UTC. `Date.today()` returns the running user's locale date.

**Potential issue:** The "today's calls" count (`todayCallCount`) uses `a.CreatedDate.date() == Date.today()`. If the AE is in PST and a call was made at 11 PM PST (7 AM UTC next day), `Date.today()` (PST) would still be the same day, but `CreatedDate.date()` is UTC-based. This could cause off-by-one-day errors in call counting near midnight. This affects cadence daily caps and spacing calculations.

**DueAt__c for meetings:** Stored as a Datetime (includes timezone), so time-bound interrupt queries (`DueAt <= now + 5min`) are timezone-safe.

### 9.6 Race Conditions

**Cache invalidation race:** If two triggers fire simultaneously (e.g., an Event insert and a Task completion for the same AE), both call `NbaCacheService.invalidate()`. This is safe — both calls remove the same cache key. The next `getActiveAction()` will re-evaluate.

**Concurrent LWC polling:** If the 5-minute refresh and the 15-second poll fire simultaneously, two Apex transactions run in parallel. The 5-min refresh evaluates the scored queue; the 15-second poll checks interrupts. These are independent streams reading different data, so no conflict.

**Complete + poll overlap:** If the AE clicks Complete while the 15-second poll is in flight, the poll may return stale data (the interrupt that was just accepted). The LWC handles this with `_dismissedInterruptIds` — a client-side set tracking IDs the AE has already dismissed. This prevents re-displaying accepted interrupts even if the poll returns them.

### 9.7 Partial Data Loads

**Talkdesk package unavailable:** If the Talkdesk managed package is deactivated or the object is inaccessible, the SOQL query in `queryRecentTalkdesk()` will throw a runtime exception. This would fail the entire evaluation with an unhandled exception. There is no try-catch around individual signal queries.

**Account_Scoring__c empty:** Handled gracefully — the query returns an empty map, `hasAccountScoring` stays false, the system falls back to Deal_Stage_Probability__c.

**NBA_Queue__c audit records missing:** If all audit records are deleted (admin action, data loader error), the system loses cadence progress and suppression state. All opps would be eligible, and cadences would restart from step 1. Cooldown and snooze suppression would stop working until new audit records are created.

**Opportunity limit:** The evaluation queries a maximum of 200 open opportunities per rep. If a rep has more than 200, opportunities beyond the 200 limit are never evaluated. The 200 are selected by Salesforce's default ordering (which is by record ID, not by any meaningful priority). This means the "missing" opportunities above 200 are effectively random exclusions.

---

## 10. Open Questions / Ambiguities

### 10.1 Suppression Window vs Cooldown Duration Disconnect

The CMDT `NBA_Suppression_Rule.Recent_Completion` has a `Suppression_Window_Hours__c` of `0.083` (≈5 minutes). But `NbaActionStateService.writeAuditRecord()` sets `CooldownUntil__c` to `now + 60 minutes`. The 60-minute cooldown value on the audit record does not effectively suppress for 60 minutes — only the 0.083h CMDT window controls the actual suppression duration in the on-demand evaluation path.

**Question:** Is the intended suppression 5 minutes or 60 minutes? The code writes 60 minutes but enforces 5.

The `CooldownUntil__c` field IS checked in `NbaActionSelectionService.rankActions()` (line 100-103), but that gate only applies to DB-persisted Pending records — which don't exist in the on-demand path. For Stream 1, the gate is dead code.

### 10.2 MRR Normalization Is Batch-Relative

MRR is normalized against the max MRR in the current evaluation batch (the rep's open pipeline). This means the same $10K opportunity could have a normalized MRR of 0.20 if the rep's top opp is $50K, but 1.00 if the rep's top opp is $10K. The same opportunity is valued differently depending on what else the rep owns.

**Question:** Is this the intended behavior? A CRO might expect absolute scoring (a $10K opp is always a $10K opp), but the current normalization makes it relative.

### 10.3 "Expansion Value" Is Not a Separate Concept

The brief mentions "expansion value" as a scoring input. In code, there is no separate expansion score. The only monetary input is `MRR__c` / `Amount`, which represents the opportunity's value. `Prob_Tier_Upgrade__c` exists on Account_Scoring__c but is not used in any scoring calculation.

**Question:** Should Prob_Tier_Upgrade__c factor into scoring? Should there be a separate expansion-specific scoring path?

### 10.4 The Shark Tank Model Does Not Exist

The brief describes a "Shark Tank model" for rep capacity and competitive assignment. No such logic exists in the codebase. Actions are strictly tied to Opportunity.OwnerId. There is no load balancing, no competitive claiming, no capacity calculation.

**Question:** Is this a planned feature? If so, it requires significant architectural additions (rep capacity tracking, assignment algorithm, potentially reassignment logic).

### 10.5 Connected Call Exit Condition Is Retrospective

The cadence exit condition `Connected_Call` checks `signal.hadConnectedCall`, which is derived from the most recent Talkdesk activity in the last 7 days. If a connected call happened 5 days ago and the AE has already completed several cadence steps since then (including the follow-up after the connection), the exit condition would still fire and terminate the cadence.

**Question:** Should the exit condition only consider calls that occurred AFTER the last cadence step? This would require comparing `lastCallDate` with `lastCadenceStepDate`.

### 10.6 200-Opportunity Cap Is a Silent Truncation

The evaluation queries `LIMIT 200` open opportunities per rep. This is a governor-limit-driven constraint, not a business rule. If a rep has 250 opps, 50 are silently excluded. The excluded opps are determined by Salesforce's default query ordering (typically by Id, which is creation order), not by any business priority.

**Question:** Should we add an `ORDER BY` clause (e.g., by Amount DESC) to ensure the most valuable opps are always included in the evaluation batch?

### 10.7 hasActiveAction Suppression May Be Stale

The suppression check `hasActiveAction` looks for existing NBA_Queue__c records with Status IN (New, Pending, In Progress, Accepted). In the on-demand model, Stream 1 actions are not persisted. But Stream 2 (Layer 1) actions ARE persisted. If a new-assignment interrupt is created but the AE never accepts it, and it's not yet expired (within 24h), the `hasActiveAction` flag would be true, suppressing the scored-queue action for that opportunity.

**Question:** Is it intended that unaccepted interrupts suppress scored-queue action creation? This could cause a 24-hour blackout window for an opportunity if the AE dismisses the interrupt banner but the NBA_Queue__c record stays in Pending status.

### 10.8 Cadence Variant Is Only Configurable Per AE

The cadence variant (A/B/etc.) is set via `NBA_AE_Config__c`, a hierarchy custom setting. This means the variant is per-user, not per-opportunity. If a rep is assigned variant A, ALL their cadences (First Touch, Re-engage, etc.) use variant A.

**Question:** Is per-opportunity or per-account variant assignment needed for proper A/B testing? The current per-user approach means you can't test whether variant A works better than variant B for a specific customer segment — only whether it works better for a specific rep.

### 10.9 No Scheduled Expiration for Stale Layer 1 Records

The `NbaActionExpirationSchedulable` is deactivated (no-op since Phase 5). The `expireStaleActions()` method exists but is not called by any active scheduled job. Time-bound Layer 1 records naturally drop out of the interrupt poll when `DueAt < now - 15min`, but they remain in the database as Pending indefinitely.

Non-time-bound Layer 1 interrupts (new assignments) similarly remain Pending until the 15s poll's `CreatedDate >= now - 24h` filter stops returning them. The records stay Pending in the database.

**Question:** Should a scheduled job be reactivated to clean up stale Layer 1 records? Without it, old Pending records accumulate and the `hasActiveAction` check may produce false positives for Signal enrichment.

### 10.10 Hidden Dependency: Talkdesk Package Must Be Installed

The `queryRecentTalkdesk()` method references `talkdesk__Talkdesk_Activity__c` without any existence check. If the Talkdesk managed package is uninstalled or the object is inaccessible, the entire evaluation pipeline fails with a runtime exception. There is no graceful degradation for this dependency.

Similarly, `Mogli_SMS__SMS__c` has the same hard dependency on the Mogli SMS managed package.

---

*This document reflects the implemented behavior of the NBA V2 / GTM OS system as of 2026-02-19. All claims are based on direct code inspection of the Apex classes, LWC components, trigger handlers, and Custom Metadata Type records in the `force-app/main/default/` directory of the GTM_OS repository. Where behavior is unclear or potentially unintended, it is flagged explicitly.*
