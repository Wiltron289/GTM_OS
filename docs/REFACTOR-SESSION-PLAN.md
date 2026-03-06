# GTM OS — Refactor Session Plan

> **Purpose**: Phased implementation plan for the PRD v2.2 refactor, chunked into context-window-sized sessions.
> **Created**: 2026-03-05
> **Source of Truth**: [GTM_OS_DOCS](https://github.com/Wiltron289/GTM_OS_DOCS) — PRD, REFACTOR-PLAN, TESTING-PLAN, TAG-TAXONOMY, UX-FEATURES

---

## Overview

Major refactor of GTM_OS codebase based on PRD v2.2. 14 sessions across 4 phases.

### Key Breaking Changes (Current → Target)

- **Scoring**: Blended (0.6×Impact + 0.4×Urgency) → Pure economic (`LTW × IIW × ConnectRate`)
- **Selection**: Layer+Score → Time-Bound → TZ Gate → Stage Priority → Expected ARR
- **Cadences**: 2 (First_Touch_A, Re_engage_A) → 5 stage-scoped (New, Connect, Consult, Closing, Re-engage)
- **Cooldown**: Variable → 24 hours (connection)
- **Outcomes**: Manual AE → Talkdesk disposition auto-detect
- **New**: Automated outreach (SMS+Email), tag system, follow-up modal

Each session has:
- **Entry**: What to read before starting (keeps context lean)
- **Work**: What to build/refactor
- **Test Milestone**: Unit tests that must pass before moving on
- **Functional Checkpoint**: Something you can see/interact with (where applicable)
- **Exit**: What to commit
- **Split Signal**: When to break the session if context is getting heavy

---

## Context Management Rules

### When to Split a Session
Watch for these signals — if ANY occur, commit what you have and start a new session:

1. **Claude says "conversation is getting long"** or context compaction fires
2. **You've been in-session for 60+ minutes** of active back-and-forth
3. **More than 8 files have been read** in the session (context filling up with code)
4. **A sub-task balloons** — e.g., a "simple" refactor reveals cascading changes across 5+ files
5. **Tests are failing for non-obvious reasons** and debugging is eating context with repeated reads

### How to Split Cleanly
1. Commit whatever is done (even partial — use a `WIP:` prefix)
2. Note which step you stopped at in this file
3. Start new session — Claude reads memory files + picks up from the noted step

### Session Size Targets
- **Small** (Sessions 3, 4, 10): ~30-45 min. Single service + test class. Low split risk.
- **Medium** (Sessions 5, 6, 7, 8, 9, 12): ~45-75 min. Larger refactors but scoped. May split if debugging.
- **Large** (Sessions 11, 13): ~60-90 min. Many files touched (LWC renames, integration tests). Plan to split.
- **XL** (Session 5 specifically): `NbaActionCreationService` is 856 lines. High split risk — may become 5a/5b.

---

## Phase Map

```
Session 3 (Schema) → Session 4 (Selection) → Session 5 (Scoring) → Session 6 (Signals/Cleanup)
    [Phase A: Core Engine]                                           ★ Functional Checkpoint

Session 7 (Cadences) → Session 8 (Auto Outreach) → Session 9 (Talkdesk)
    [Phase B: Cadence & Automation]                  ★ Functional Checkpoint

Session 10 (Tags/Follow-Up) → Session 11 (LWC) → Session 12 (Controller Wiring)
    [Phase C: UX & Features]                         ★ Full Visual Walkthrough

Session 13 (Monitoring/E2E) → Session 14 (Merge/Deploy)
    [Phase D: Polish & Ship]   ★ Full E2E Test       ★ UAT Checklist
```

Phase A must complete before Phase B (scoring/selection used by cadence routing).
Phase B should complete before Phase C (auto-outreach triggers used in LWC flows).
Sessions within a phase are sequential.

---

## Completed Sessions

### Session 1: Deep Analysis + Doc Sync — COMPLETE (2026-03-05)
- Cloned repos, analyzed codebase, updated 4 doc files
- Created memory files for session continuity

### Session 2: Planning + Schema Prep — COMPLETE (2026-03-05)
- Read entire PRD, REFACTOR-PLAN, TESTING-PLAN, TAG-TAXONOMY, UX-FEATURES
- Created this refactoring session plan

---

## Phase A: Core Engine Refactor

### Session 3: Test Stabilization + Schema Deploy [SMALL] — COMPLETE (2026-03-05)

- 31 metadata components deployed — 7 NBA_Queue__c fields, 2 Account_Scoring__c fields, 2 NBA_Cadence_Step__mdt fields, NBA_Stage_Priority__mdt (4 records), NBA_Connect_Rate__mdt (10 records). 125/127 tests pass (no regressions).

**Entry**: Read `CLAUDE.md` first 70 lines. Read `REFACTOR-PLAN.md` Section 7 (field changes).

**Work**:
1. Run current targeted test suite — record baseline pass/fail
2. Fix any new failures (not pre-existing 2)
3. Deploy new NBA_Queue__c fields:
   - `Stage_Priority__c` (Number)
   - `Expected_Incremental_ARR__c` (Currency)
   - `Action_Tags__c` (LongTextArea)
   - `Execution_Type__c` (Picklist: Human/Automated)
   - `Automated_Send_Status__c` (Picklist: Pending/Sent/Failed/Skipped)
   - `Template_Name__c` (Text)
   - `Scheduled_Send_Time__c` (DateTime)
   - `Dismissal_Category__c` (Picklist)
4. Deploy new Account_Scoring__c fields (if not exist):
   - `Likelihood_To_Win__c` (Decimal 5,4)
   - `Incremental_If_Won__c` (Currency)
5. Create new CMDTs:
   - `NBA_Stage_Priority__mdt` (4 records: Closing=1, Consult=2, Connect=3, New=4)
   - `NBA_Connect_Rate__mdt` (10 records: attempt 1-10 with rates from PRD Section 21)
6. Add `Stage__c` and `Execution_Type__c` fields to `NBA_Cadence_Step__mdt`
7. Re-run targeted tests — confirm no regressions from schema changes

**Test Milestone**: All new fields/CMDTs deployed. Pre-existing tests still pass.
**Functional Checkpoint**: None (schema only).
**Split Signal**: Low risk. Only split if test debugging balloons.
**Exit**: Commit schema changes.

---

### Session 4: Selection Engine Rewrite [SMALL] — COMPLETE (2026-03-05)

- Commit `be81e58`: Full rewrite of NbaActionSelectionService. Stage priority + Expected ARR ranking. Timezone gate stubbed (implemented in Session 12). 4 new tests.

**Entry**: Read `NbaActionSelectionService.cls` (~136 lines). Read PRD Section 8 (Selection Engine).

**Work**:
1. Full rewrite of `NbaActionSelectionService`:
   - Replace Layer+Score sort with: Time-Bound Override → Timezone Gate → Stage Priority → Expected ARR
   - Read `NBA_Stage_Priority__mdt` for stage ordering
   - Implement timezone gating (9AM local time check using Contact timezone)
   - Implement deterministic tiebreaker (oldest Opp CreatedDate)
2. Update `NbaActionSelectionServiceTest`:
   - Test time-bound override serves first
   - Test timezone gate filters out early-timezone contacts
   - Test stage priority ordering (Closing > Consult > Connect > New)
   - Test Expected ARR ranking within same stage
   - Test tiebreaker for identical ARR

**Test Milestone**: `NbaActionSelectionServiceTest` passes with all new scenarios.
**Functional Checkpoint**: None (backend only).
**Split Signal**: Low risk (136-line class).
**Exit**: Commit selection engine rewrite.

---

### Session 5: Scoring Logic Rewrite [XL — likely splits to 5a/5b] — COMPLETE (2026-03-05)

- Commit `1bda64c`: Replaced blended scoring with `LTW × IIW × Connect_Rate(attempt)`. Stage-based fallback. Connect rate CMDT lookup. Urgency references removed. 22 creation tests passing.

**Entry**: Read `NbaActionCreationService.cls` (~856 lines). Read PRD Section 8.3 (Scoring Formula).

**Work**:
1. Rewrite scoring in `NbaActionCreationService`:
   - Replace blended `(0.6 × Impact) + (0.4 × Urgency)` with: `Likelihood_To_Win × Incremental_If_Won × Connect_Rate(attempt)`
   - Read `NBA_Connect_Rate__mdt` for attempt-based rates
   - Read `Account_Scoring__c` for LTW and IIW values
   - Implement fallback: stage-based probability (New=10%, Connect=25%, Consult=50%, Closing=75%) + Opp Amount when no scoring data
   - Remove bucket/layer assignment code
   - Store result in `Expected_Incremental_ARR__c` and `Priority_Score__c`
2. Split eligibility logic from scoring (cleaner separation)
3. Delete urgency scoring references
4. Update `NbaActionCreationServiceTest`

**Likely Split**: 5a = Steps 1-2 (rewrite + split), 5b = Steps 3-4 (cleanup + tests).
**Test Milestone**: Scoring formula produces correct Expected ARR. Fallbacks work.
**Functional Checkpoint**: None (backend scoring).
**Exit**: Commit scoring rewrite.

---

### Session 6: Signal Service + Cooldown + Cleanup [MEDIUM] — COMPLETE (2026-03-05)

- Commit `f319f74`: 24hr cooldown, Talkdesk-first outcomes, deprecated field cleanup. **PHASE A COMPLETE.**

**Entry**: Read `NbaSignalService.cls` (~434 lines), `NbaActionStateService.cls` (~289 lines).

**Work**:
1. Refactor `NbaSignalService` — Talkdesk-first outcomes, remove urgency signals
2. Refactor `NbaActionStateService` — 24hr cooldown, no manual outcome required
3. Delete deprecated assets (`NBA_Urgency_Rule__mdt`, `NBA_Impact_Weight__mdt`, Priority_Bucket/Layer fields)
4. Update tests + suppression rules

**Test Milestone**: All targeted tests pass. No urgency/weight references remain.

**Functional Checkpoint — PHASE A E2E VERIFICATION**:
Run anonymous Apex script:
1. Create 4 test Opps (one per stage) with Account_Scoring data
2. Trigger evaluation for a test AE
3. **Verify in workspace**: Closing-stage opp served first (stage priority works)
4. Complete it → Consult-stage opp served next
5. Create meeting Event 5 min from now → urgency banner appears (time-bound override works)

**Exit**: Commit. **PHASE A COMPLETE.**

---

## Phase B: Cadence & Automation

### Session 7: Stage-Scoped Cadences [MEDIUM] — COMPLETE (2026-03-05)

- Commit `27cda20` (7a): 5 parent cadences with Stage__c, 39 step records with Execution_Type__c + Template_Name__c.
- Commit `f38dbe3` (7b): NbaCadenceService refactored for stage-scoped lookup, stage change resets, ownership continuity. 33 cadence tests passing.

**Entry**: Read `NbaCadenceService.cls` (~505 lines). Read PRD Section 11 (cadence definitions).

**Work**:
1. Create CMDT records for 4 stage-scoped cadences (New: 12 steps, Connect: 7, Consult: 8, Closing: 6)
2. Add `Stage__c` to `NBA_Cadence__mdt`, `Execution_Type__c` + `Template_Name__c` to steps
3. Refactor `NbaCadenceService` — stage change resets, ownership continues, Human/Automated routing
4. Update `NbaCadenceServiceTest`

**Test Milestone**: All 4 cadences work. Stage change resets. Ownership preserves position.
**Functional Checkpoint**: None (backend — visible after Session 8).
**Split Signal**: 7a = CMDT records, 7b = service refactor + tests.
**Exit**: Commit cadence refactor.

---

### Session 8: Automated Outreach Engine [MEDIUM] — COMPLETE (2026-03-05)

- Commit `6c2f25b`: NbaAutomatedOutreachService (SMS Mogli + Email), NbaAutomatedOutreachSchedulable (5-min batch), wired into NbaActionCreationService.evaluateAndCreate().
- 19 new tests (16 service + 3 schedulable), all passing. 0 regressions (152/155 targeted, 3 pre-existing).
- **Gotcha**: When calling service methods directly in tests, ensure Contact is queried with all compliance fields (HasOptedOutOfEmail, Mogli_SMS__Mogli_Opt_Out__c, etc.)

**Entry**: Read PRD Section 12 (Automated Outreach Engine).

**Work**:
1. Create `NbaAutomatedOutreachService.cls` — SMS via Mogli, Email via SF, compliance checks, hybrid scheduling
2. Create `NbaAutomatedOutreachSchedulable.cls` — scheduled pickup of Pending_Automated records
3. Create tests for both

**Test Milestone**: SMS creates Mogli record. Email sends. Opt-out skips correctly.
**Functional Checkpoint**: Check Mogli SMS records and email logs in org after tests.
**Split Signal**: 8a = outreach service, 8b = schedulable.
**Exit**: Commit automated outreach.

---

### Session 9: Talkdesk Trigger Handler [MEDIUM]

**Entry**: Read `NbaTalkdeskActivityTriggerHandler.cls` (~138 lines). Read PRD Sections 14.1, 17.

**Work**:
1. Expand trigger handler — disposition detection, 24hr cooldown, cadence advance, auto-send firing, ContentNote creation, follow-up modal trigger, cache invalidation
2. Update trigger and tests (including bulk 200 records)

**Test Milestone**: All dispositions handled. ContentNote creation works. Bulk-safe.

**Functional Checkpoint — PHASE B E2E VERIFICATION**:
Run anonymous Apex script:
1. Create test Opp in New stage, advance to Step 1 (Call)
2. Insert mock Talkdesk Activity "No Answer" → verify SMS auto-send fired
3. Insert mock Activity "Connected" + talk_time=120 → verify cooldown, cadence end, ContentNote
4. Check NBA_Queue__c status transitions

**Exit**: Commit. **PHASE B COMPLETE.**

---

## Phase C: UX & Features

### Session 10: Tag System + Follow-Up Service [SMALL-MEDIUM]

**Entry**: Read TAG-TAXONOMY.md. Read PRD Sections 15, 16.

**Work**:
1. Create `NbaTagService.cls` — 23 tag definitions, priority ordering, 4-tag cap, JSON serialization
2. Create `NbaFollowUpService.cls` — Task creation, cadence pause, time-bound on due date
3. Create tests for both

**Test Milestone**: Correct JSON output. 4-tag cap. Follow-up pauses cadence.
**Split Signal**: 10a = tags, 10b = follow-ups.
**Exit**: Commit tag + follow-up services.

---

### Session 11: LWC Refactor [LARGE — plan to split 11a/11b]

**Entry**: Read UX-FEATURES.md.

**Work 11a — New Components**:
1. `nbaTagChip` LWC (expand/collapse)
2. `nbaTagPanel` LWC (2-4 chips container)
3. `nbaFollowUpModal` LWC (date/time, method, notes)
4. Dismiss categorization UI

**Work 11b — Refactor + Rename**:
5. Refactor `nbaActionBar` — remove outcome buttons, add follow-up trigger
6. Refactor `nbaDemoInsightsPanel` → tag display
7. Rename demo components → production names
8. Update workspace data flow for new ActionWrapper

**Test Milestone**: Components render. Follow-up modal creates Task. Dismiss shows categories.
**Functional Checkpoint**: After 11b, full workspace renders with new UX.
**Exit**: Commit LWC refactor.

---

### Session 12: Controller Update + Integration Wiring [MEDIUM]

**Entry**: Read `NbaActionController.cls` (~462 lines).

**Work**:
1. Refactor controller — new selection model, follow-up/dismiss endpoints, updated ActionWrapper
2. Wire all services together (evaluation cycle, Talkdesk flow, follow-up flow)
3. Update `NbaActionControllerTest`

**Test Milestone**: Full evaluation cycle correct. All endpoints work. Full test suite green.

**Functional Checkpoint — PHASE C FULL VISUAL WALKTHROUGH**:
1. Action card shows tag chips, opp details, contact info
2. Click tag chip → expanded explanation
3. Click Complete → follow-up modal
4. Set follow-up → Task created
5. Click Dismiss → category selector
6. Create meeting Event → urgency banner (amber, countdown)
7. "Go to Action" → meeting displayed
8. Complete all → "All caught up!" empty state

**Exit**: Commit. **PHASE C COMPLETE.**

---

## Phase D: Polish & Ship

### Session 13: Monitoring, Polish, E2E [LARGE — plan to split 13a/13b]

**Entry**: Read PRD Section 19. Read TESTING-PLAN Section 4.

**Work 13a**: Monitoring fields, Custom Report Type, `NbaTestDataFactory`
**Work 13b**: 9 integration test scenarios (TESTING-PLAN 4.1-4.9), fix issues

**Test Milestone**: All 9 integration scenarios pass.

**Functional Checkpoint — FULL E2E**:
1. AE logs in → Closing-stage action served
2. Complete → Consult served
3. New Opp → interrupt banner
4. Meeting → urgency banner
5. Call → follow-up modal → cadence pauses
6. Verify auto-sends
7. Dismiss with reasons
8. Empty state

**Exit**: Commit. **PHASE D COMPLETE.**

---

### Session 14: Merge + Production Readiness [MEDIUM]

**Work**:
1. Full targeted test suite — all green
2. Org-wide tests — document coverage
3. Address coverage gaps
4. Merge to master (or PR)
5. Deploy to UAT
6. Execute UAT checklist (TESTING-PLAN Section 11 — 34 steps)

**Test Milestone**: All tests green. UAT happy path passes.
**Functional Checkpoint**: Full UAT checklist (Parts A-D).

---

## Quick Reference

### Functional Checkpoints

| After | What You Test | How |
|-------|--------------|-----|
| Session 6 (Phase A) | Stage priority, ARR ranking, time-bound override | Anon Apex + observe workspace |
| Session 9 (Phase B) | Cadence progression, auto SMS/email, Talkdesk cooldown | Anon Apex + check records |
| Session 12 (Phase C) | Full new UX — tags, follow-up, dismiss | Interactive browser walkthrough |
| Session 13 (Phase D) | Complete E2E with realistic data | Full manual test |
| Session 14 | UAT checklist (34 steps) | Structured walkthrough |

### Split Risk

| Session | Size | Risk | Natural Split |
|---------|------|------|--------------|
| 3 | Small | Low | test stab / schema |
| 4 | Small | Low | unlikely |
| 5 | XL | **High** | scoring / cleanup+tests |
| 6 | Medium | Medium | signal refactor / cleanup |
| 7 | Medium | Medium | CMDTs / service refactor |
| 8 | Medium | Medium | service / schedulable |
| 9 | Medium | Medium | core handler / auto-send wiring |
| 10 | Small-Med | Low | tags / follow-ups |
| 11 | **Large** | **High** | new components / rename+refactor |
| 12 | Medium | Low-Med | unlikely |
| 13 | **Large** | **High** | monitoring / integration tests |
| 14 | Medium | Low | unlikely |
