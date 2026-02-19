# NBA V2 End-to-End Test Plan

**Date**: 2026-02-18
**Org**: UAT (lwilson@joinhomebase.com.uat)
**User**: 005Hp00000iHg58IAC
**Branch**: feature/nba-v2-demo-lwc

---

## Test Data Summary (20 Opportunities)

| # | Code | Opp ID | Account | Amount | Prob% | Stage | Action Type | Cadence |
|---|------|--------|---------|--------|-------|-------|-------------|---------|
| — | TB1 | 006Po00000zH7unIAC | Mamacita's Taqueria | $288 | 75 | Closing | Meeting (Layer 1) | — |
| — | TB2 | 006Po000013tYN4IAM | Two Cumberland | $285 | 60 | Closing | Meeting (Layer 1) | — |
| — | TB3 | 006Po000013Q7LNIA0 | QUENCH IT SODA SHACK | $225 | 45 | Connect | Meeting (Layer 1) | — |
| 1 | FT1 | 006dy00000Kf39iAAB | E2E FT1 High Value | $175 | 90 | New | First Touch | First_Touch_A Step 1 |
| 2 | FT2 | 006dy00000Kf39jAAB | E2E FT2 Premium | $150 | 80 | New | First Touch | First_Touch_A Step 1 |
| 3 | FT3 | 006dy00000Kf39kAAB | E2E FT3 Mid Value | $140 | 70 | New | First Touch | First_Touch_A Step 1 |
| 4 | FT4 | 006dy00000Kf39lAAB | E2E FT4 Standard | $130 | 60 | New | First Touch | First_Touch_A Step 1 |
| 5 | FT5 | 006dy00000Kf39mAAB | E2E FT5 Growth | $120 | 45 | New | First Touch | First_Touch_A Step 1 |
| 6 | FT6 | 006dy00000Kf39nAAB | E2E FT6 Starter | $110 | 35 | New | First Touch | First_Touch_A Step 1 |
| 7 | FT7 | 006dy00000Kf39oAAB | E2E FT7 Entry | $100 | 25 | New | First Touch | First_Touch_A Step 1 |
| 8 | SP1 | 006Po00000yuZwbIAE | THE PIZZA PLACE | $183 | 80 | Closing | Stage Progression | — |
| 9 | SP2 | 006Po00000zHRWvIAO | Steve's Coffee | $107 | 65 | Closing | Stage Progression | — |
| 10 | RE1 | 006Po000010UGzhIAG | BLO Mt.Juliet | $165 | 85 | Consult | Re-engage | Re_engage_A Step 1 |
| 11 | RE2 | 006Po00000xlyjWIAQ | Jersey Mike's Subs | $129 | 50 | Consult | Re-engage | Re_engage_A Step 1 |
| 12 | RE3 | 006Po00000xoCFKIA2 | Simone Stalling MD | $99 | 35 | Consult | Re-engage | Re_engage_A Step 1 |
| 13 | CF1 | 006Po000013uczeIAA | Reflections Group Home | $207 | 70 | New | Follow Up | — |
| 14 | FU2 | 006Po000010pK2bIAE | Scooter's Coffee | $315 | 40 | Consult | Follow Up | — |
| 15 | FU1 | 006Po00000zGw6XIAS | Oconomowoc Lake Club | $327 | 55 | Connect | Follow Up | — |
| 16 | FU3 | 006Po000013nrqXIAQ | Adventure West, Inc. | $255 | 30 | Consult | Follow Up | — |
| 17 | CF2 | 006Po0000120nv8IAA | Centurion Security | $199 | 50 | Connect | Follow Up | — |

---

## Scoring Calculations

### Constants
- `maxMrr = MAX(50000, max amount in batch) = 50000` (highest amount is $327 << 50000)
- Impact weights: MRR=0.60, CloseProb=0.40
- Priority weights: Impact=0.50, Urgency=0.50
- BASE_URGENCY = 0.5, MAX_URGENCY_CAP = 2.0

### Urgency Multiplier Rules (NBA_Urgency_Rule__mdt)

| Rule | Signal Type | Condition | Multiplier |
|------|-------------|-----------|------------|
| SLA_First_Touch | SLA | actionType == 'First Touch' | 2.0 |
| Late_Stage_Inactivity | Inactivity | stage >= 4 AND days >= 3 | 1.5 |
| Re_Engage_Cold | Inactivity | days >= 5 | 1.3 |
| Stage_Pressure | Stage Pressure | stage >= 3 | 1.2 |

### Formulas
```
normalizedMRR = min(amount / 50000, 1.0)
closeProb = probPayrollConversion / 100   (from Account_Scoring__c)
Impact = (0.60 x normalizedMRR) + (0.40 x closeProb)

urgencyProduct = product of all matching rule multipliers
Urgency = 0.5 x min(urgencyProduct, 2.0)

Priority = (0.50 x Impact) + (0.50 x Urgency)
```

### Score Table

| Code | normMRR | closeProb | Impact | Urgency Rules | urgProduct | Urgency | Priority | Layer | Bucket |
|------|---------|-----------|--------|---------------|------------|---------|----------|-------|--------|
| **FT1** | 0.0035 | 0.90 | **0.362** | SLA(2.0) | 2.0 | **1.000** | **0.681** | L1 | Cadence Due Today |
| **FT2** | 0.0030 | 0.80 | **0.322** | SLA(2.0) | 2.0 | **1.000** | **0.661** | L1 | Cadence Due Today |
| **FT3** | 0.0028 | 0.70 | **0.282** | SLA(2.0) | 2.0 | **1.000** | **0.641** | L1 | Cadence Due Today |
| **FT4** | 0.0026 | 0.60 | **0.242** | SLA(2.0) | 2.0 | **1.000** | **0.621** | L1 | Cadence Due Today |
| **FT5** | 0.0024 | 0.45 | **0.181** | SLA(2.0) | 2.0 | **1.000** | **0.591** | L1 | Cadence Due Today |
| **FT6** | 0.0022 | 0.35 | **0.141** | SLA(2.0) | 2.0 | **1.000** | **0.571** | L1 | Cadence Due Today |
| **FT7** | 0.0020 | 0.25 | **0.101** | SLA(2.0) | 2.0 | **1.000** | **0.551** | L1 | Cadence Due Today |
| **SP1** | 0.0037 | 0.80 | **0.322** | LSI(1.5)xRE(1.3)xSP(1.2) | 2.34→cap 2.0 | **1.000** | **0.661** | L3 | Late-Stage Stalled |
| **SP2** | 0.0021 | 0.65 | **0.261** | LSI(1.5)xRE(1.3)xSP(1.2) | 2.34→cap 2.0 | **1.000** | **0.631** | L3 | Late-Stage Stalled |
| **RE1** | 0.0033 | 0.85 | **0.342** | RE(1.3)xSP(1.2) | 1.56 | **0.780** | **0.561** | L3 | General Pipeline |
| **RE2** | 0.0026 | 0.50 | **0.202** | RE(1.3)xSP(1.2) | 1.56 | **0.780** | **0.491** | L3 | General Pipeline |
| **RE3** | 0.0020 | 0.35 | **0.141** | RE(1.3)xSP(1.2) | 1.56 | **0.780** | **0.461** | L3 | General Pipeline |
| **CF1** | 0.0041 | 0.70 | **0.283** | none | 1.0 | **0.500** | **0.391** | L3 | General Pipeline |
| **FU2** | 0.0063 | 0.40 | **0.164** | SP(1.2) | 1.2 | **0.600** | **0.382** | L3 | General Pipeline |
| **FU1** | 0.0065 | 0.55 | **0.224** | none | 1.0 | **0.500** | **0.362** | L3 | General Pipeline |
| **FU3** | 0.0051 | 0.30 | **0.123** | SP(1.2) | 1.2 | **0.600** | **0.362** | L3 | General Pipeline |
| **CF2** | 0.0040 | 0.50 | **0.202** | none | 1.0 | **0.500** | **0.351** | L3 | General Pipeline |

---

## Expected Priority Queue Order

### Phase A: Time-Bound Meeting Actions (Layer 1 from DB)

These are served by `checkTimeBoundInternal()` before any on-demand evaluation.

| Order | Code | Action | DueAt | What to Verify |
|-------|------|--------|-------|----------------|
| **1** | TB1 | Meeting | ~15:01 ET | Red urgency banner with countdown. No cadence. Click Complete. |
| **2** | TB2 | Meeting | ~17:01 ET | Same meeting UX. Complete. |
| **3** | TB3 | Meeting | ~20:01 ET | Same meeting UX. Complete. |

### Phase B: First Touch Cadence Actions (Layer 1 On-Demand)

After all meetings completed, `evaluateOnDemand()` runs. FT opps are Layer 1 (hoursSinceAssignment <= 1) and rank above all Layer 3 opps.

| Order | Code | Score | Cadence | Step | Method | What to Verify |
|-------|------|-------|---------|------|--------|----------------|
| **4** | FT1 | 0.681 | First_Touch_A | 1/12 | Call | Blue "First Touch" badge. Call icon. Progress "1/12". Outcome panel: Connected/Left VM/No Answer. |
| **5** | FT2 | 0.661 | First_Touch_A | 1/12 | Call | Same FT UX. Pick different outcome than FT1. |
| **6** | FT3 | 0.641 | First_Touch_A | 1/12 | Call | Continue through FT opps. |
| **7** | FT4 | 0.621 | First_Touch_A | 1/12 | Call | |
| **8** | FT5 | 0.591 | First_Touch_A | 1/12 | Call | |
| **9** | FT6 | 0.571 | First_Touch_A | 1/12 | Call | |
| **10** | FT7 | 0.551 | First_Touch_A | 1/12 | Call | Last FT opp. |

**Cadence step progression**: After completing FT1 Step 1, FT1 enters 5-min cooldown. FT2 surfaces next. After the cooldown expires, FT1 reappears with Step 2 (SMS — "Mark SMS Sent" button). FT opps interleave as you work through them.

### Phase C: Scored Non-FT Actions (Layer 3 On-Demand)

After FT opps lose their 1-hour window (hoursSinceAssignment > 1), OR after all FT Step 1s are completed, Layer 3 opps surface in priority order.

| Order | Code | Score | Type | Cadence | What to Verify |
|-------|------|-------|------|---------|----------------|
| **11** | SP1 | 0.661 | Stage Progression | none | Green "Stage Prog" badge. "Late-Stage Stalled" bucket. No cadence. Generic Complete. |
| **12** | SP2 | 0.631 | Stage Progression | none | Same. |
| **13** | RE1 | 0.561 | Re-engage | Re_engage_A 1/6 | Amber "Re-engage" badge. Call step. Outcome panel. Progress "1/6". Upcoming steps preview. |
| **14** | RE2 | 0.491 | Re-engage | Re_engage_A 1/6 | Same. |
| **15** | RE3 | 0.461 | Re-engage | Re_engage_A 1/6 | Same. |
| **16** | CF1 | 0.391 | Follow Up | none | No cadence. Generic Complete. |
| **17** | FU2 | 0.382 | Follow Up | none | |
| **18** | FU1 | 0.362 | Follow Up | none | |
| **19** | FU3 | 0.362 | Follow Up | none | Tied with FU1 — order may vary. |
| **20** | CF2 | 0.351 | Follow Up | none | Last action. After this → "All caught up!" |

---

## Critical Timing Constraint

**First Touch detection expires after ~1 hour.** The `hoursSinceAssignment <= 1` check uses `Hours_Since_Assignment__c`, a formula based on `Date_Time_Last_Reassignment__c` (set to NOW() during data setup). After 1 hour, FT opps no longer qualify as First Touch and revert to Follow Up with no cadence.

**Recommendation**: Start testing within 15 minutes of data setup. Complete Phase A (3 meetings, ~5 min) and at least Phase B (7 First Touch Step 1 completions, ~10 min) within the first hour.

---

## Test Walkthrough

### Session 1: Time-Bound Meetings (~5 min)

1. Open the App Page ("Homebase NBA")
2. **Verify TB1**: Red urgency banner with countdown ("Meeting in X min"). No cadence badge. "Meeting" action type.
3. **Complete TB1**: Click Complete. No outcome panel (meetings are non-cadence). TB2 appears.
4. **Complete TB2**: Same flow. TB3 appears.
5. **Complete TB3**: Same flow. After this, Layer 1 DB actions exhausted → on-demand evaluation → FT1 appears.

### Session 2: First Touch Cadence (~15 min)

6. **Verify FT1**: Blue "First Touch" badge. Cadence badge with Call icon + "1/12". Progress bar at 1/12. "Why This Action" shows step instruction. Upcoming steps preview.
7. **Complete FT1 Step 1 (Call)**: Outcome panel appears → Select **"Left VM"**. FT1 enters 5-min cooldown. FT2 appears.
8. **Complete FT2 Step 1**: Select **"No Answer"**. FT3 appears.
9. **Test Connected outcome on FT3**: Select **"Connected"** → FT3 cadence terminates (won't reappear). FT4 appears.
10. **Continue FT4-FT7**: Complete Step 1 with various outcomes.

### Session 3: Cadence Step Progression (~10 min, after cooldowns)

11. **Wait ~5 min** after FT1 completion.
12. **Refresh / check**: FT1 should reappear with **Step 2 (SMS)**. Blue "Mark SMS Sent" button (no outcome panel). Progress "2/12".
13. **Complete Step 2**: Click "Mark SMS Sent" → auto-outcome "Sent". FT1 enters cooldown again.
14. **After cooldown**: FT1 Step 3 (Call, 60-min spacing from Step 1). If < 60 min since Step 1 call → spacing suppresses → falls to next opp.

### Session 4: Stage Progression (~5 min)

15. **Verify SP1**: Green "Stage Prog" badge. Bucket: "Late-Stage Stalled". No cadence badge. Generic "Complete" button (no outcome panel).
16. **Complete SP1**: Next action (SP2) appears.
17. **Complete SP2**: RE1 appears.

### Session 5: Re-engage Cadence (~10 min)

18. **Verify RE1**: Amber "Re-engage" badge. Cadence: Re_engage_A, Step 1/6, Day 0, Call. Progress bar 1/6. Upcoming steps: "Day 0: Email", "Day 1: Call", "Day 3: SMS".
19. **Complete RE1 Step 1 (Call)**: Outcome panel → Select "Left VM". RE1 enters cooldown.
20. **After cooldown**: RE1 Step 2 (Email, Day 0). "Mark Email Sent" button.
21. **Complete RE1 Step 2**: RE1 Step 3 = Day 1 Call → **day-gated** (only available tomorrow). RE1 falls to non-cadence or next opp.
22. **Continue RE2, RE3**: Same Step 1 Call flow.

### Session 6: Follow Up + Snooze/Dismiss (~10 min)

23. **Verify CF1 or FU2**: "Follow Up" type. No cadence. Generic Complete.
24. **Snooze test** on one Follow Up: Click Snooze → Duration chips (15 min, 1 hour, 4 hours). Select **15 min**. Enter reason "Testing snooze". Submit. Action disappears, next loads. Verify snoozed opp doesn't reappear for 15 min.
25. **Dismiss test** on another Follow Up: Click Dismiss → Category chips (Call Scheduled, Time Zone, Other). Select **"Other"**. Enter reason "Testing dismiss". Submit. Action disappears.
26. **Continue** through remaining Follow Up opps.

### Session 7: Empty State (~1 min)

27. After all actions processed → **"All caught up!"** empty state with green checkmark.

---

## Feature Verification Checklist

### Engine Logic
- [ ] Layer 1 time-bound (TB) actions appear before Layer 3 scored actions
- [ ] Time-bound sorted by DueAt (earliest first): TB1 → TB2 → TB3
- [ ] Layer 1 on-demand (FT) actions appear before Layer 3 scored actions
- [ ] Layer 3 sorted by Priority Score DESC: SP1 → SP2 → RE1 → ... → CF2
- [ ] First Touch detected via hoursSinceAssignment <= 1 path
- [ ] Re-engage detected for Days_Since_Last_Interaction = 5
- [ ] Stage Progression detected for stage 4+ with days >= 3
- [ ] Follow Up assigned as default fallback
- [ ] Upcoming Meeting suppression: TB opps don't appear in on-demand evaluation
- [ ] Recent Completion suppression: completed opp doesn't reappear for ~5 min
- [ ] Snoozed opp doesn't reappear until snooze expires
- [ ] Account_Scoring__c probPayroll used for closeProb (not dealStageProbability)

### Scoring
- [ ] Higher probPayroll = higher priority (FT1 90% > FT2 80% > ... > FT7 25%)
- [ ] First Touch urgency = 1.0 (SLA 2.0x multiplier)
- [ ] Stage Prog urgency = 1.0 (capped: 1.5 x 1.3 x 1.2 = 2.34 → cap 2.0)
- [ ] Re-engage urgency = 0.78 (1.3 x 1.2 = 1.56)
- [ ] Follow Up urgency = 0.50 (stage < 3) or 0.60 (stage >= 3 with Stage_Pressure)

### Cadence — First_Touch_A
- [ ] Cadence matched for First Touch action type
- [ ] Step 1 = Call → outcome panel (Connected / Left VM / No Answer)
- [ ] Step 2 = SMS → "Mark SMS Sent" button (auto-outcome "Sent")
- [ ] Step 3 = Call → outcome panel again
- [ ] Connected outcome ends cadence (opp won't show next step)
- [ ] VM/No Answer continues cadence
- [ ] Progress bar updates (2/12, 3/12, etc.)
- [ ] Upcoming steps preview shows next 2-3 steps
- [ ] 60-min spacing enforced between Call steps

### Cadence — Re_engage_A
- [ ] Cadence matched for Re-engage action type
- [ ] Step 1 = Call (Day 0) → outcome panel
- [ ] Step 2 = Email (Day 0) → "Mark Email Sent"
- [ ] Step 3 = Call (Day 1) → day-gated, won't appear on Day 0
- [ ] Day gating works correctly

### LWC UX
- [ ] Action type badge colors: blue=First Touch, amber=Re-engage, green=Stage Prog
- [ ] Cadence step badge: method icon (call/sms/email) + "X/Y" fraction
- [ ] Urgency banner on time-bound actions with countdown
- [ ] "Why This Action" panel: instruction text + reason
- [ ] Snooze panel: 3 duration options, reason field, submit
- [ ] Dismiss panel: 3 category chips, reason field, submit
- [ ] Action bar fixed at bottom, clears utility bar
- [ ] "All caught up!" empty state when queue is empty
- [ ] 15s polling detects new Layer 1 actions
- [ ] 5-min full refresh for score changes

### Audit Records
- [ ] NBA_Queue__c created on complete (Status=Completed)
- [ ] Cadence fields written: Cadence_Name__c, Cadence_Step_Number__c, Step_Outcome__c, Step_Method__c
- [ ] Snooze audit: Snoozed_Until__c, Snooze_Reason__c
- [ ] Dismiss audit: Dismissal_Category__c, Dismissed_Reason__c

---

## Environment Changes to Revert After Testing

| Change | File/Object | Original Value | Test Value |
|--------|-------------|----------------|------------|
| Suppression cooldown | NBA_Suppression_Rule.Recent_Completion | 1.0 hours | 0.083 hours |
| Valid touch window | NBA_Suppression_Rule.Recent_Valid_Touch | 4.0 hours | 0.083 hours |
| 7 test Accounts | E2E FT1-FT7 | — | Delete |
| 7 test Opps | FT opp IDs | — | Delete |
| 7 Account_Scoring | FT scoring IDs | — | Delete |
| 13 Account_Scoring | Existing opp scoring IDs | — | Delete |
| 13 Opp reassignments | See ORIGINAL_OWNER log | Various AEs | Restore |
| 3 test Events | TB Events | — | Delete |
| RE opp date fields | Last_Call_Date_Time, Last_Meeting_Date | Original values | Restore |
| FT opp date field | Date_Time_Last_Reassignment | Original (null) | Restore |
| NBA_AE_Config__c | Cadence_Variant__c = 'A' | Did not exist | Delete |
| NBA_Queue__c audits | E2E test records | — | Expire/delete |

### Original Opp Owners (for restoration)

| Opp ID | Original Owner |
|--------|---------------|
| 006Po00000xlyjWIAQ | 005Hp00000iHgEvIAK |
| 006Po00000xoCFKIA2 | 005Hp00000iHgEvIAK |
| 006Po00000yuZwbIAE | 005Hp00000iHgATIA0 |
| 006Po00000zGw6XIAS | 005Hp00000iHgFtIAK |
| 006Po00000zH7unIAC | 005Hp00000iHgEvIAK |
| 006Po00000zHRWvIAO | 005Hp00000iHgFtIAK |
| 006Po000010UGzhIAG | 005Hp00000ebdF3IAI |
| 006Po000010pK2bIAE | 005Hp00000iHgATIA0 |
| 006Po0000120nv8IAA | 005Po00000ZbCFlIAN |
| 006Po000013Q7LNIA0 | 005Hp00000iHgM7IAK |
| 006Po000013nrqXIAQ | 005Hp00000iHgATIA0 |
| 006Po000013tYN4IAM | 005Hp00000iHgFtIAK |
| 006Po000013uczeIAA | 005Hp00000ebdF3IAI |

---

## Data Setup Scripts (for reference)

All scripts saved in `scripts/apex/`:
- `e2e-phase1b-setup.apex` — NBA_AE_Config, queue cleanup, cache invalidation
- `e2e-phase2-data.apex` — Account/Opp/Scoring creation, opp reassignment, Event creation
- `e2e-phase2-fix.apex` — Formula-backing DateTime field fixes for correct detection
