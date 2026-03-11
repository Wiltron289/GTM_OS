# GTM OS — Explainability Model

> **Version**: 1.0
> **Last Updated**: 2026-03-11
> **Audience**: CRO, Sales Leadership, Product

---

## Overview

Every action served by GTM OS includes a plain-language explanation of **why** this opportunity was prioritized. The explainability model has three components that display differently depending on the action type.

---

## Two Display Modes

### 1. Time-Bound Actions (Meetings, SLA Assignments)

When GTM OS serves a time-bound action, the explanation is simple and contextual — there's no economic ranking involved, so we don't show model data.

| Action Type | What the AE Sees |
|-------------|-----------------|
| **Upcoming Meeting** | "Upcoming meeting — review context and prepare." + meeting details (subject, time, location) |
| **New Assignment (SLA)** | "Newly assigned opportunity — make initial contact within SLA window." |
| **Follow-Up Due** | "Your scheduled follow-up is now due." |

**Rationale**: Time-bound actions override economic ranking by design. The "why" is self-evident — you have a meeting, or you just got assigned an opp. No model explanation needed.

---

### 2. Engine-Generated Actions (Scored Queue)

When GTM OS serves an action from the economic ranking engine, the explanation has three parts:

#### Part A: Data Science Drivers (Tags)

The Data Science model outputs **2-3 behavioral drivers** per account explaining why this account scores high for payroll conversion. These are displayed as **tag chips** with expandable plain-language text.

**Driver Mapping (Model Output → AE-Facing)**:

| Model Driver | Tag Chip | Expanded Explanation |
|---|---|---|
| `Growing team size` | **Growing Team** | "This account is actively growing their team — payroll need increases with headcount" |
| `high hiring activity (9d)` | **Hiring Surge** | "High hiring activity in the last 9 days — strong signal for payroll adoption" |
| `High engagement across features` | **Power User** | "Account is highly engaged across multiple product features" |
| `enterprise-adjacent size` | **Enterprise-Adjacent** | "Company size is approaching enterprise scale — higher payroll complexity" |
| `low tier` / `essential tier` | **Room to Grow** | "Currently on a lower tier — strong upsell opportunity with payroll" |
| `Recent team management usage` | **Managing Teams** | "Account recently started using team management features — payroll is a natural next step" |
| `new location` | **New Location** | "Account just added a new location — expansion signal for payroll" |
| `active scheduling` | **Active Scheduling** | "Heavy scheduling usage signals operational maturity for payroll" |
| `Steady usage growth` | **Usage Growing** | "Account shows steady growth in platform usage over time" |
| `multi-location company` | **Multi-Location** | "Company operates multiple locations — payroll complexity drives need" |
| `Spike in timeclock punches (3d)` | **Timeclock Spike** | "Unusual spike in timeclock activity in the last 3 days — possible event or growth" |
| `High timeclock usage (30d)` | **Heavy Timeclock** | "Consistently high timeclock usage over the last 30 days" |
| `Consistent time tracking` | **Tracking Time** | "Account consistently tracks employee time — payroll is the next logical step" |
| `Frequent scheduling activity` | **Active Scheduler** | "Frequent scheduling activity signals operational reliance on the platform" |

**Source**: `Account_Scoring__c.Payroll_Top_Drivers__c` — populated daily by the Data Science ML pipeline. Each account receives 2-3 drivers from the model.

**If no drivers are available**: Tags section is hidden. This happens when the Account_Scoring record doesn't exist or the field is null (fallback scoring still works, but drivers aren't available).

#### Part B: Cadence Context

Below the tags, a brief cadence explanation tells the AE where they are in the outreach sequence:

- "Step 3 of 12 — Day 1, First Touch cadence"
- "Final attempt — breakup step"
- "Re-engagement cadence — 5 days since last interaction"

This includes a progress bar showing cadence completion.

#### Part C: Payroll Conversion Probability

Displayed separately (not as a tag), the payroll conversion probability gives the AE a quick confidence signal:

- **Display**: "{X}% payroll conversion probability" with a visual indicator
- **Source**: `Account_Scoring__c.Prob_Payroll_Conversion__c` (ML model, daily refresh)
- **Fallback**: If no Account_Scoring data, falls back to stage-based probability (New=10%, Connect=25%, Consult=50%, Closing=75%)

---

## Data Flow

```
Data Science Pipeline (daily batch)
  │
  ├── Account_Scoring__c.Prob_Payroll_Conversion__c    → Payroll probability display
  ├── Account_Scoring__c.Payroll_Top_Drivers__c        → Driver tags (2-3 per account)
  ├── Account_Scoring__c.Incremental_If_Won__c         → Economic ranking formula
  └── Account_Scoring__c.Prob_Tier_Upgrade__c          → (future use)
  │
  ▼
GTM OS Engine (on-demand evaluation)
  │
  ├── Selection: Expected_ARR = LTW × IIW × Connect_Rate(attempt)
  │   Stage Priority: Closing > Consult > Connect > New (hard boundary)
  │
  ├── Tag Generation: Parse Payroll_Top_Drivers, map to AE-facing chips
  │
  └── Serve to AE with: Driver tags + Cadence context + Probability
```

---

## What This Means for AEs

**Before GTM OS**: AE decides what to work on by scanning a list. No visibility into why one opp matters more than another.

**With GTM OS**: AE opens the workspace and sees:
1. **The single most important action** (already decided by the engine)
2. **2-3 tags** explaining the account's behavioral signals ("Growing Team", "Timeclock Spike", "Power User")
3. **Cadence position** so they know where they are in the outreach sequence
4. **Conversion probability** so they know the model's confidence level

The AE doesn't need to interpret data — the system translates model outputs into actionable context.

---

## Source Attribution Summary

| Component | Source | Refresh Frequency |
|-----------|--------|-------------------|
| Driver Tags (2-3 chips) | Data Science ML model (`Payroll_Top_Drivers__c`) | Daily batch |
| Payroll Probability | Data Science ML model (`Prob_Payroll_Conversion__c`) | Daily batch |
| Cadence Context | System logic (cadence engine, CMDT configuration) | Real-time |
| Time-Bound Rationale | System logic (Event/Opportunity triggers) | Real-time |
| Economic Ranking | Hybrid: ML scores × system logic (stage priority, connect rate) | Real-time eval, ML data daily |

---

## Adding New Drivers

When the Data Science team adds new driver strings to the model output:

1. Add the mapping to the `DRIVER_MAP` in `NbaTagService.cls` (chip label + expanded text)
2. Deploy to production
3. New drivers appear automatically on the next daily pipeline refresh

Unknown drivers (not yet mapped) fall back to displaying the raw model text — so new drivers are never silently hidden, they just show the technical label until mapped.
