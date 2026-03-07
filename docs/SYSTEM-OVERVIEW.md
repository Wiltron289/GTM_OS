# GTM OS — How It Works (Post-Refactor)

> **As of**: 2026-03-06 (PRD v2.2 refactor complete)
> **Purpose**: High-level explanation of the entire system for validation before merge.

---

## What Is GTM OS?

GTM OS is a Salesforce-native sales workflow engine that serves Account Executives (AEs) **one action at a time** — the single most valuable thing they should do right now. It eliminates manual prioritization by continuously evaluating CRM data, generating cadence-aligned work, and ranking actions by expected economic return.

The AE opens a dedicated workspace, sees their top action, executes it, and the system immediately serves the next one. Low-effort outreach (SMS, email) is automated so AEs focus only on calls and meetings.

---

## The Three Engines

Everything flows through three engines that run **on-demand** when the AE opens their workspace:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  1. SIGNAL       │ ──► │  2. CREATION     │ ──► │  3. SELECTION    │
│  (What's going   │     │  (What work      │     │  (What wins?)    │
│   on in CRM?)    │     │   should exist?)  │     │                  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

### Engine 1: Signal Detection (`NbaSignalService`)

Queries 7 CRM data sources for each of the AE's opportunities:
- **Opportunity** — stage, amount, owner, close date, days since last interaction
- **Talkdesk Activities** — recent calls, dispositions, talk time, call counts
- **Mogli SMS** — recent text messages, direction (inbound/outbound)
- **Events** — upcoming meetings within 24 hours
- **Tasks** — completed activities
- **Account Scoring** — ML-generated `Likelihood_To_Win` and `Incremental_If_Won` from Data Science pipeline
- **Existing Actions** — active NBA_Queue__c records (prevents duplicates)

Output: a `Map<Id, OpportunitySignal>` — one signal bundle per opportunity, containing everything the engine needs to make decisions.

### Engine 2: Action Creation (`NbaActionCreationService`)

For each opportunity signal, runs a pipeline:

1. **Suppress?** — Skip if: closed opp, active action already exists, recent touch within cooldown, upcoming meeting already handled
2. **Determine action type** — Based on opp stage and history:
   - **First Touch** — New opp, no prior contact
   - **Stage Progression** — Opp advanced stages (e.g., New → Connect)
   - **Re-engage** — Stale opp with no recent interaction
3. **Resolve cadence step** — Looks up which step of the cadence this opp is on (see Cadences below)
4. **Score** — `Expected Incremental ARR = Likelihood_To_Win × Incremental_If_Won × ConnectRate(attempt_i)`
   - Connect rate decreases with each attempt (attempt 1 = 10.4%, attempt 10 = 1.5%)
   - If no Account Scoring data, falls back to `stage probability × Opp Amount`
5. **Assign stage priority** — Closing = 1, Consult = 2, Connect = 3, New = 4

Output: a scored action candidate with all context needed for ranking.

### Engine 3: Selection (`NbaActionSelectionService`)

Ranks all candidates and picks the single best action:

```
1. TIME-BOUND OVERRIDE — Meetings within 5 min always win (ordered by deadline proximity)
2. TIMEZONE GATE — Filter out opps where it's before 8 AM in the account's local time
3. STAGE PRIORITY — Closing (1) beats Consult (2) beats Connect (3) beats New (4)
4. EXPECTED ARR — Within the same stage, highest Expected Incremental ARR wins
5. TIEBREAKER — Oldest opportunity wins (longest time in pipeline)
```

Output: the single top-priority `ActionWrapper` served to the AE.

---

## On-Demand Architecture

The system does **not** pre-create actions on a schedule. Instead:

```
AE opens workspace
  → LWC calls getActiveAction()
  → Check Platform Cache (5-min TTL)
    → Cache HIT: return cached action (1 SOQL)
    → Cache MISS: run all 3 engines (~12 SOQL) → cache result → return
  → AE sees their top action
  → AE completes/dismisses → write audit record → invalidate cache → re-evaluate → serve next
```

This means actions always reflect **real-time CRM state** — no stale records from batch delays.

### Two-Stream Delivery

The workspace runs two independent polling streams:

| Stream | Poll Interval | What It Checks | Purpose |
|--------|--------------|----------------|---------|
| **Scored Queue** | 5 min | Full on-demand evaluation | Normal prioritized actions |
| **Interrupts** | 15 sec | Meetings within 5 min + new opp assignments | Urgent items that can't wait |

When an interrupt arrives, the AE sees an indigo banner ("Jump to it" / "Later"). If accepted, the current action is paused and resumes after the interrupt is handled.

---

## Cadences

Each opp stage has its own multi-day cadence defining the sequence of outreach steps. Cadences use a **2-CMDT parent/child architecture**:

- **`NBA_Cadence__mdt`** (parent) — defines the cadence: which stage, how many steps, how many days, exit conditions
- **`NBA_Cadence_Step__mdt`** (child) — individual steps with method (Call/SMS/Email), day, execution type (Human/Automated), and **outcome branching**

### Active Cadences

| Cadence | Stage | Steps | Days | Pattern |
|---------|-------|-------|------|---------|
| **First_Touch_A (New)** | New | 12 | 5 | D0: Call→SMS→Call→Email→Call, D1: Call×4→SMS→Email, D3: Email→Call, D5: Breakup email |
| **Connect_A** | Connect | TBD | — | Defined in CMDT, ready for records |
| **Consult_A** | Consult | TBD | — | Defined in CMDT, ready for records |
| **Closing_A** | Closing | TBD | — | Defined in CMDT, ready for records |
| **Re_engage_A** | Re-engage | 6 | 7 | D0: Call+Email, D1: Call, D3: SMS, D5: Email, D7: Call |

### Outcome Branching

After each call step, the system checks the Talkdesk disposition:
- **Connected** (talk time > 0) → Exit cadence + 24-hour cooldown
- **Left Voicemail** → Continue to next step (may trigger auto-send)
- **No Answer** → Continue to next step (may trigger auto-send)
- **Meeting Scheduled** → Exit cadence

### Stage Changes Reset Cadence

When an opp moves stages (e.g., New → Connect), the old cadence is discarded and the new stage's cadence starts at Step 1. **Ownership changes do NOT reset** — cadence continues at the same position for the new owner.

### Spacing & Gating

- **60-minute spacing** between attempts on the same opp
- **Day gating** — steps are assigned to cadence days; can't jump ahead
- **Daily caps** — configurable max attempts per day per opp

---

## Automated Outreach

Some cadence steps are marked `Execution_Type__c = 'Automated'` — these fire without AE involvement:

- **SMS** — Sends via Mogli SMS integration. Checks opt-out (`Mogli_Opt_Out__c`) before sending.
- **Email** — Sends via Salesforce email. Checks opt-out (`HasOptedOutOfEmail`) before sending.

Automated sends are **outcome-conditional** in the New stage: SMS/Email only fire if the preceding call did NOT connect. If the AE connected on the call, the cadence exits and no auto-send fires.

The `NbaAutomatedOutreachSchedulable` runs on a schedule to process pending automated actions.

---

## Triggers (Real-Time Events)

Three Salesforce triggers feed the engine in real-time:

| Trigger | Fires On | What Happens |
|---------|----------|-------------|
| **OpportunityTrigger** | New opp / stage change | Creates new-assignment interrupt (instant). Stage change → cache invalidation → re-evaluation picks up new cadence. |
| **EventTrigger** | Meeting scheduled / rescheduled / cancelled | Creates time-bound action with deadline. Reschedule updates deadline. Cancel expires the action. |
| **TaskTrigger** | Activity logged (call/email completed) | Updates context (attempt counts). Connected call → cache invalidation for re-engage evaluation. |

### Talkdesk Activity Trigger

A fourth trigger on `talkdesk__Talkdesk_Activity__c` handles post-call automation:

1. **Disposition detection** — Classifies the call outcome (Connected / VM / No Answer) from Talkdesk data
2. **Cooldown enforcement** — Connected calls apply 24-hour cooldown on the opportunity
3. **Cadence advancement** — Updates cadence position based on outcome branching rules
4. **Auto-send wiring** — If not connected and next step is automated, creates pending SMS/Email action
5. **Call notes** — Publishes `Call_Completed_Event__e` Platform Event → LWC shows overlay for AE to review/edit AI-generated call notes → saved as ContentNote on the Opportunity
6. **Cache invalidation** — Ensures next workspace load reflects the call outcome

---

## Tag System

Each action gets up to 4 context tags displayed as chips in the workspace. Tags help the AE understand **why** this action was selected and what context matters. Tags are derived from signals and scored by priority.

**Tag categories** (13 types, priority-ordered):

| Priority | Tag | Condition |
|----------|-----|-----------|
| 1 | Time-Bound | Meeting within 24h |
| 2 | SLA Active | New opp, within SLA window |
| 3 | High Value | Expected ARR above threshold |
| 4 | High Win Likelihood | LTW above threshold |
| 5 | Inbound Reply | Recent inbound SMS/email |
| 6 | Last Attempt | Last outreach > 3 days ago |
| 7 | Call Attempt | Multiple call attempts today |
| 8 | Meeting Upcoming | Meeting scheduled (not immediate) |
| 9 | Re-engaged | Re-engage cadence active |
| 10 | Cadence: First Touch | On First Touch cadence |
| 11-13 | (other context tags) | Various engagement signals |

Tags are serialized as JSON to `Action_Tags__c` on the action record and rendered as colored chips in the LWC.

---

## Follow-Up System

After completing a call, the AE can schedule a follow-up:

1. AE clicks "Set Follow-Up" in the post-call modal
2. System creates a Task on the Opportunity with the scheduled time
3. **Cadence pauses** — no new cadence actions served for this opp while follow-up is pending
4. When the follow-up becomes due, it surfaces as a **time-bound action** (urgency banner)
5. After completing the follow-up, cadence resumes from the next step

AEs can also cancel follow-ups, which removes the snooze and lets the cadence resume immediately.

---

## The Workspace (LWC)

The AE-facing UI is a single-page workspace (`nbaDemoWorkspace`) running on a Salesforce App Page:

```
┌──────────────────────────────────────────────┐
│  [GTM OS Header]  Action type badge + method │
│  Account: Acme Corp  │  Opp: Renewal $50K    │
├──────────────────────────────────────────────┤
│  ⚠️ URGENCY BANNER (if time-bound)           │
│  "Meeting in 4 minutes — Prep now"           │
├──────────────────────────────────────────────┤
│  🏷️ Tags: [High Value] [SLA Active] [First Touch] │
├──────────────────────────────────────────────┤
│  Why This Action:                            │
│  "First Touch — New $50K renewal, high win   │
│   likelihood. Call Step 3 of 12."            │
│                                              │
│  Cadence Progress: ████████░░░░ 3/12         │
│  Upcoming: Step 4 (SMS), Step 5 (Call)       │
├──────────────────────────────────────────────┤
│  [Contact Info] [Opp Details] [Activities]   │
├──────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ Complete  │  │  Snooze  │  │ Dismiss  │   │
│  └──────────┘  └──────────┘  └──────────┘   │
└──────────────────────────────────────────────┘
```

- **Complete** → For calls: shows outcome panel (Connected / Left VM / No Answer) → writes audit → advances cadence → serves next action
- **Snooze** → 15min / 1hr / 4hr options → pauses this action, serves next
- **Dismiss** → Category selector (Not relevant / Wrong timing / etc.) + notes → writes audit → serves next
- **Empty state** → "All caught up!" when no actions remain

---

## Data Model Summary

| Object | Role |
|--------|------|
| `NBA_Queue__c` | Action records (audit trail). Written on AE interaction, not pre-created. ~108 fields including scoring, cadence, tags, automated send status. |
| `Account_Scoring__c` | ML scores from Data Science pipeline. `Likelihood_To_Win__c` and `Incremental_If_Won__c`. |
| `NBA_Cadence__mdt` | Cadence definitions (parent). Stage, variant, steps, days, exit conditions. |
| `NBA_Cadence_Step__mdt` | Cadence steps (child). Method, day, execution type, outcome branching. |
| `NBA_Stage_Priority__mdt` | Stage ranking (Closing=1, Consult=2, Connect=3, New=4). |
| `NBA_Connect_Rate__mdt` | Connect rate curve by attempt number (attempt 1-10). |
| `NBA_AE_Config__c` | Hierarchy custom setting for per-AE cadence variant assignment. |
| `Call_Completed_Event__e` | Platform Event for post-call note capture flow. |

---

## Apex Class Map

| Class | Purpose |
|-------|---------|
| **NbaSignalService** | Engine 1 — queries 7 CRM sources, builds OpportunitySignal map |
| **NbaActionCreationService** | Engine 2 — suppression, type determination, cadence resolution, scoring |
| **NbaActionSelectionService** | Engine 3 — time-bound override, TZ gate, stage priority, ARR ranking |
| **NbaActionController** | LWC controller — getActiveAction, complete, snooze, dismiss, interrupts, call notes |
| **NbaActionStateService** | Audit record writer — writes NBA_Queue__c on AE interactions |
| **NbaCadenceService** | Cadence engine — step resolution, branching, day gating, spacing |
| **NbaCacheService** | Platform Cache wrapper — 5-min TTL per-AE action cache |
| **NbaTagService** | Tag derivation — 13 tag types, priority ordering, 4-cap |
| **NbaFollowUpService** | Follow-up task creation, cadence pause/resume |
| **NbaAutomatedOutreachService** | SMS (Mogli) and Email sends with opt-out handling |
| **NbaOpportunityTriggerHandler** | Opp insert/update → new-assignment interrupt, cache invalidation |
| **NbaEventTriggerHandler** | Event insert/update/delete → time-bound action CRUD |
| **NbaTaskTriggerHandler** | Task insert/update → context updates, connected-call detection |
| **NbaTalkdeskActivityTriggerHandler** | Call disposition → cooldown, cadence advance, auto-send, call notes |
| **NbaTriggerContext** | Shared recursion guards + constants for all triggers |
| **NbaDemoController** | Demo workspace data (page data, SMS/email sends, conversation history) |
| **NbaAutomatedOutreachSchedulable** | Scheduled job for processing pending automated sends |
| **NbaActionCreationSchedulable** | Archived (was batch creation, now on-demand) |
| **NbaActionExpirationSchedulable** | Expires stale time-bound + non-time-bound L1 actions |
| **NbaRealTimeEvaluationQueueable** | Async evaluation wrapper (used by Opp trigger) |
| **NbaTestDataFactory** | Shared test data builder for all test classes |

---

## Key Design Decisions

1. **On-demand, not batch** — Actions are evaluated when the AE needs them, not pre-created on a schedule. This ensures real-time accuracy and eliminates stale records.

2. **Audit-only persistence** — NBA_Queue__c records are only written when the AE interacts (complete/snooze/dismiss). The "active action" lives in Platform Cache, not the database.

3. **Stage priority over dollar value** — A $3K Closing-stage opp always beats an $8K New-stage opp. Within the same stage, dollar value (Expected ARR) determines ranking.

4. **24-hour connection cooldown** — After a connected call (real conversation), no cadence actions for that opp for 24 hours. Prevents over-contacting.

5. **Outcome-conditional auto-sends** — Automated SMS/email only fire if the preceding call didn't connect. A connected call means the AE handled it; no need for automated follow-up.

6. **Two-stream delivery** — Separates urgent items (meetings, new assignments) from the scored queue so interrupts surface within 15 seconds while the full evaluation runs on a 5-minute cycle.

7. **Cadence resets on stage change, not owner change** — Moving an opp forward means new context (new cadence). Re-assigning to a different AE should continue where the previous AE left off.
