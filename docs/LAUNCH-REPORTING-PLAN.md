# GTM OS — Launch Reporting & Dashboard Plan

> **Version**: 1.0
> **Last Updated**: 2026-03-11
> **Audience**: CRO, Sales Leadership
> **Status**: Data model ready, dashboards to be built pre-launch

---

## Overview

GTM OS logs every action served, completed, dismissed, and expired as an audit record (`NBA_Queue__c`). Combined with Opportunity monitoring fields and Account Scoring data, we have full visibility into engine health, AE behavior, cadence compliance, and pipeline progression.

This document outlines the reports and dashboards planned for launch.

---

## Dashboard 1: Engine Health & Operations

**Purpose**: "Is the engine functioning properly? Is it serving the right actions?"

| Report | What It Shows | Key Fields | Refresh |
|--------|--------------|------------|---------|
| **Actions Served Today** | Count of actions served per AE, broken down by action type | `CreatedDate = TODAY`, `Action_Type__c`, `Sales_Rep__c` | Real-time |
| **Action Status Distribution** | Pie chart: Completed vs Dismissed vs Expired vs Snoozed | `Status__c`, count by status | Real-time |
| **Dismiss Rate by AE** | % of actions dismissed per AE (high dismiss rate = possible engine misalignment) | `Status__c = 'Dismissed'` / total by `Sales_Rep__c` | Daily |
| **Dismiss Reasons** | Top dismiss categories and free-text reasons | `Dismissal_Category__c`, `Dismissed_Reason__c` | Daily |
| **Time-Bound Compliance** | % of time-bound actions completed before expiry (meetings, SLA) | `Is_Time_Bound__c = true`, `Status__c` (Completed vs Expired) | Daily |
| **Engine Errors** | Actions that expired without being served (indicates engine gap) | `Status__c = 'Expired'`, `First_Viewed_Date__c = null` | Daily |

---

## Dashboard 2: Starvation & Coverage

**Purpose**: "Are any opportunities being missed? Is anything stuck?"

| Report | What It Shows | Key Fields | Refresh |
|--------|--------------|------------|---------|
| **Never-Served Opportunities** | Open opps that have never received an NBA action | `Opportunity.Last_NBA_Served_Date__c = null`, `IsClosed = false` | Daily |
| **Stale Opportunities** | Open opps not served in 7+ days | `Last_NBA_Served_Date__c < TODAY-7` | Daily |
| **Starvation by Stage** | Stale opps grouped by stage — shows where pipeline is getting stuck | Same as above, grouped by `StageName` | Daily |
| **Starvation by AE** | Stale opps grouped by owner — shows which AEs have neglected opps | Same as above, grouped by `OwnerId` | Daily |
| **Action Coverage Rate** | % of open opps that received at least 1 action in the last 7 days | `NBA_Action_Count__c > 0` AND `Last_NBA_Served_Date__c >= TODAY-7` | Daily |

**Report Type**: "Opportunities with NBA Actions" (already deployed — outer join so opps with zero actions show up)

---

## Dashboard 3: Cadence Compliance

**Purpose**: "Are AEs following the cadences? Are they going deep enough on each opp?"

| Report | What It Shows | Key Fields | Refresh |
|--------|--------------|------------|---------|
| **Cadence Completion Rate** | % of cadences that reached final step vs abandoned/dismissed | `Cadence_Name__c`, max `Cadence_Step_Number__c` per Opp vs `cadenceTotalSteps` | Weekly |
| **Average Steps Completed** | Mean cadence depth per AE and per stage | `Cadence_Step_Number__c` avg by `Sales_Rep__c`, `Opportunity_Stage__c` | Weekly |
| **Attempt Depth vs Breadth** | Steps per opp vs # of unique opps touched — shows if AEs are going deep or spreading thin | Count of actions per Opp vs count of distinct Opps per AE | Weekly |
| **Cadence by Stage** | Completion rates broken down by stage cadence (First Touch, Post-Demo, Closing) | `Cadence_Name__c`, `Status__c` | Weekly |
| **Step Outcomes** | Connected / Left VM / No Answer breakdown per cadence step | `Step_Outcome__c` by `Cadence_Step_Number__c` | Weekly |
| **Automated vs Manual** | Ratio of system-executed (SMS/Email) to human-executed (Call) actions | `Execution_Type__c` or `Step_Method__c` | Weekly |

---

## Dashboard 4: Follow-Up & Commitment Tracking

**Purpose**: "Are follow-ups happening? Are commitments being kept?"

| Report | What It Shows | Key Fields | Refresh |
|--------|--------------|------------|---------|
| **Follow-Ups Created** | Count of follow-up Tasks created via GTM OS by AE | Task where `Subject LIKE 'Follow-Up%'` and `Description LIKE '%GTM OS%'` | Daily |
| **Follow-Up Completion Rate** | % of follow-ups marked complete vs overdue/open | Task `Status` (Completed vs Not Started/In Progress), `ActivityDate < TODAY` | Daily |
| **Meeting Prep Rate** | % of meeting time-bound actions completed before meeting start | `Action_Type__c = 'Meeting'`, `Status__c = 'Completed'` vs `'Expired'` | Daily |
| **Post-Call Actions** | Follow-up creation rate after connected calls (Connected outcome → follow-up created?) | Cross-reference `Step_Outcome__c = 'Connected'` with subsequent Task creation | Weekly |

---

## Dashboard 5: Pipeline Progression & Revenue Impact

**Purpose**: "Is GTM OS actually moving the funnel?"

| Report | What It Shows | Key Fields | Refresh |
|--------|--------------|------------|---------|
| **Stage Velocity** | Average days in each stage for GTM OS-served opps vs non-served | `Opportunity.StageName` change timestamps, filtered by `NBA_Action_Count__c > 0` | Weekly |
| **Conversion by Action Depth** | Win rate correlated with # of GTM OS actions taken | `Opportunity.IsWon`, `NBA_Action_Count__c` buckets (1-5, 6-10, 11+) | Monthly |
| **Expected ARR Served** | Total Expected Incremental ARR of actions served per day/week | Sum of `Expected_Incremental_ARR__c` by `CreatedDate` | Daily |
| **Stage Priority Distribution** | % of actions served per stage bucket — confirms Closing opps are getting priority | `Stage_Priority__c` (1=Closing, 2=Consult, 3=Connect, 4=New) | Weekly |
| **Connection Rate by Attempt** | Empirical connection rate per attempt number — validates the MCR model | `Step_Outcome__c = 'Connected'` / total by `Cadence_Step_Number__c` | Monthly |

---

## Dashboard 6: AE Activity & Engagement

**Purpose**: "How are individual AEs engaging with the system?"

| Report | What It Shows | Key Fields | Refresh |
|--------|--------------|------------|---------|
| **Actions Per AE Per Day** | Daily throughput by AE | `Status__c = 'Completed'`, count by `Sales_Rep__c`, `Completed_Date__c` | Daily |
| **Average Response Time** | Time between action served and AE interaction | `First_Viewed_Date__c` - `CreatedDate` | Daily |
| **Snooze Patterns** | Frequency and duration of snoozes per AE | `Status__c = 'Snoozed'`, `Snoozed_Until__c` - `CreatedDate` | Weekly |
| **Time-Bound Response** | Time between SLA/Meeting action creation and AE acceptance | `Actioned_Date__c` - `CreatedDate` for time-bound actions | Daily |
| **Leaderboard** | Top AEs by actions completed, connection rate, follow-up compliance | Composite of above metrics | Daily |

---

## Implementation Approach

### Phase 1: Launch Day (Must-Have)

These reports use the existing custom report type and can be built in Salesforce UI:

1. **Starvation Report** — Never-served + stale opps (report type already deployed)
2. **Action Status Distribution** — Simple NBA_Queue__c report grouped by Status
3. **Actions Per AE Per Day** — NBA_Queue__c grouped by Sales_Rep + CreatedDate
4. **Dismiss Rate** — NBA_Queue__c filtered by Status=Dismissed, grouped by Sales_Rep
5. **Time-Bound Compliance** — NBA_Queue__c filtered by Is_Time_Bound=true, grouped by Status

**Effort**: 2-3 hours in Salesforce report builder. No code changes.

### Phase 2: Week 1 Post-Launch

6. **Cadence Completion Rate** — Requires grouping by Cadence_Name + max step per Opp
7. **Attempt Depth vs Breadth** — Requires count of distinct Opps per AE vs actions per Opp
8. **Follow-Up Tracking** — Cross-reference Tasks with NBA_Queue__c

**Effort**: 4-6 hours. May need a second custom report type (NBA_Queue__c with Tasks).

### Phase 3: Week 2-4 Post-Launch

9. **Pipeline Progression** — Stage velocity requires historical stage change data
10. **Connection Rate Validation** — Needs enough data volume (2+ weeks of cadence execution)
11. **Revenue Impact** — Needs closed-won outcomes to measure (1-2 month lag)

**Effort**: Ongoing analysis. May need Salesforce Flow or batch Apex for aggregation.

---

## Data Already Available

| Data Point | Source | Available Now? |
|-----------|--------|:--------------:|
| Action served/completed/dismissed | NBA_Queue__c audit records | Yes |
| Cadence step + outcome | Cadence_Name__c, Cadence_Step_Number__c, Step_Outcome__c | Yes |
| Starvation (never served) | Opportunity.Last_NBA_Served_Date__c | Yes |
| Action count per opp | Opportunity.NBA_Action_Count__c | Yes |
| Expected economic value | Expected_Incremental_ARR__c | Yes |
| DS model probability | Account_Scoring__c.Prob_Payroll_Conversion__c | Yes (daily pipeline) |
| AE response time | First_Viewed_Date__c, Actioned_Date__c | Yes |
| Follow-ups created | Task records with GTM OS description | Yes |
| Dismiss reasons | Dismissal_Category__c, Dismissed_Reason__c | Yes |
| Time-bound compliance | Is_Time_Bound__c, Status__c, DueAt__c | Yes |
| Connection rate empirical | Step_Outcome__c by attempt number | Yes (needs data volume) |

---

## What's NOT Available Yet

| Gap | What's Needed | Effort |
|-----|--------------|--------|
| Dashboard components | Build in Salesforce UI (no code) | 2-3 hours for Phase 1 |
| Second report type | "NBA Actions with Tasks" for follow-up cross-reference | 1 hour |
| Stage velocity calculation | Historical stage change tracking (or Flow-based snapshot) | 4-6 hours |
| Scheduled report delivery | Configure email subscriptions for daily/weekly reports | 30 min per report |

---

## Summary for CRO

**"Which reports will be live at launch?"**

At launch, we will have 5 core reports available:

1. **Starvation Monitor** — Which opps are being missed? (report type already deployed)
2. **Action Throughput** — How many actions per AE per day?
3. **Dismiss Rate** — Are AEs rejecting the engine's recommendations?
4. **Time-Bound Compliance** — Are meetings and SLAs being handled on time?
5. **Status Distribution** — Overall engine health (completed vs expired vs dismissed)

Within the first week, we add cadence compliance, attempt depth analysis, and follow-up tracking. Revenue impact and funnel velocity reports come online in weeks 2-4 as data volume builds.

**The data model is fully instrumented.** Every action, outcome, cadence step, and AE interaction is logged. We're not missing any data — we just need to build the views.
