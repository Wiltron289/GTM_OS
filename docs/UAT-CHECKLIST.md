# GTM OS — Pre-Beta UAT Checklist

> **Source**: TESTING-PLAN Section 11
> **Created**: 2026-03-06 (Session 14)
> **Environment**: Full Sandbox (Homebase UAT)
> **Prerequisites**: All 261 Apex unit tests passing. All integration test scenarios pass.

---

## Pre-Requisites

- [ ] All Apex unit tests pass (75%+ coverage)
- [ ] All integration test scenarios pass
- [ ] GTM OS workspace deployed and accessible
- [ ] Test data created (TESTING-PLAN Section 13)
- [ ] Mogli gateway configured for SMS sends
- [ ] Email deliverability enabled in sandbox

---

## Part A: Happy Path (30-45 minutes)

| # | Step | Action | Expected Result | Pass/Fail | Notes |
|---|------|--------|-----------------|:---------:|-------|
| 1 | Log in as test AE | Navigate to GTM OS workspace | Workspace loads. If no actions exist, empty state displays. | | |
| 2 | Trigger new Opp | Create a new Opportunity in "New" stage assigned to the test AE | SLA action appears within 5 minutes. Time-bound urgency banner may display. | | |
| 3 | Verify Call #1 served | Check primary action card | Shows: Call action, Step 1 of First Touch cadence, Opp details, Contact info, tag chips | | |
| 4 | Complete Call #1 | Insert mock Talkdesk Activity (No Answer disposition) | Follow-up modal appears. Cadence advances. Step 2 (SMS) fires automatically (if not connected). | | |
| 5 | Dismiss follow-up modal | Click "No Follow-Up" | Modal closes. Cadence continues normally. | | |
| 6 | Verify automated SMS | Check Mogli SMS records for the Opportunity | SMS record created with correct template and contact. In sandbox: message actually sent. | | |
| 7 | Verify Call #2 served | After spacing (60 min), check workspace | Call #2 (Step 3) appears as primary action. | | |
| 8 | Set follow-up | Insert mock Talkdesk Activity (Left VM). In modal, set follow-up for +2 hours. | Task created on Opp. Cadence pauses. | | |
| 9 | Verify cadence paused | Check workspace while follow-up is in future | No new cadence actions served. Other Opp actions may be served instead. | | |
| 10 | Follow-up becomes due | Advance time (or wait). When follow-up Task is due: | Time-bound action surfaces (urgency banner). | | |
| 11 | Complete follow-up | Mark time-bound action complete | Cadence resumes from next incomplete step. | | |
| 12 | Verify automated email | Advance cadence to an Email step | Email sent. Activity record created on Opp. Check inbox (sandbox). | | |
| 13 | Dismiss an action | When next action appears, click "Dismiss" | Reason selector appears. Select "Not relevant" + notes. Action dismissed. Next action served. | | |
| 14 | Verify dismiss recorded | Query `NBA_Queue__c` for the dismissed action | `Status__c` = "Dismissed", `Dismissal_Category__c` = "Not relevant", `Dismissed_Reason__c` populated. | | |
| 15 | Verify empty state | Complete or dismiss all remaining actions | "All caught up!" message displays. | | |

---

## Part B: Multi-Opp Prioritization (15-20 minutes)

| # | Step | Action | Expected Result | Pass/Fail | Notes |
|---|------|--------|-----------------|:---------:|-------|
| 16 | Create 3 opps | Create Opps in Closing ($3K), Consult ($5K), New ($8K) stages for test AE | Closing-stage Opp's action served first (stage priority). | | |
| 17 | Verify stage priority | Check primary action card | Closing-stage action displayed, even though New-stage has higher dollar value. | | |
| 18 | Complete Closing action | Complete the Closing-stage action | Consult-stage action served next (priority 2 > New priority 4). | | |
| 19 | Verify Consult served | Check primary action card | Consult-stage action displayed. | | |
| 20 | Create time-bound meeting | Create Event on the New-stage Opp, starting in 5 minutes | Urgency banner appears for the meeting, overriding Consult-stage ranking. | | |
| 21 | Complete meeting action | Complete the time-bound meeting action | Economic ranking resumes. Consult-stage action served (higher priority than New). | | |
| 22 | Verify ARR ranking within stage | Create 2 more Consult-stage Opps with different scoring | Higher Expected Incremental ARR Opp served first within Consult stage. | | |

---

## Part C: Automated Outreach (15-20 minutes)

| # | Step | Action | Expected Result | Pass/Fail | Notes |
|---|------|--------|-----------------|:---------:|-------|
| 23 | Trigger SMS step | Advance cadence to an automated SMS step | Mogli SMS record created. Message sent to Contact's phone. | | |
| 24 | Verify SMS delivery | Check Contact's phone (if using real number in sandbox) | SMS received with correct content. | | |
| 25 | Trigger email step | Advance cadence to an automated Email step | Email sent via Salesforce. Activity record created. | | |
| 26 | Verify email delivery | Check inbox for the Contact's email address | Email received with correct template and merge fields. | | |
| 27 | Test SMS opt-out | Set `Mogli_SMS__Mogli_Opt_Out__c` = true on Contact. Advance to SMS step. | Step skipped. `Automated_Send_Status__c` = "Skipped". Reason logged. Cadence advances. | | |
| 28 | Test email opt-out | Set `HasOptedOutOfEmail` = true on Contact. Advance to Email step. | Step skipped. Reason logged. Cadence advances. | | |

---

## Part D: Edge Cases (15-20 minutes)

| # | Step | Action | Expected Result | Pass/Fail | Notes |
|---|------|--------|-----------------|:---------:|-------|
| 29 | Re-own Opportunity | Change Opp owner from test AE1 to test AE2 (Opp mid-cadence at Step 4) | Cadence continues at Step 4 for AE2. AE2 sees the action. Attempt counters preserved. | | |
| 30 | Change Opp stage | Change Opp from New to Connect | New cadence discarded. Connect cadence starts at Step 1. | | |
| 31 | Opp with no scoring | Create Opp on Account with no `Account_Scoring__c` record | Fallback values used (stage-based probability, Opp Amount). Action still served. | | |
| 32 | Verify fallback values | Check `Priority_Score__c` on the action | Score calculated using fallback: stage probability x Opp Amount x connect rate. | | |
| 33 | Connected call cooldown | Insert mock Talkdesk Activity (Connected, talk time = 60s) | 24-hour cooldown. No cadence actions for this Opp. Other Opp actions served. | | |
| 34 | Verify cooldown expiry | After 24 hours (simulate): | Cadence resumes from next step. Actions eligible again. | | |

---

## UAT Sign-Off

| Role | Name | Date | Result |
|------|------|------|--------|
| Developer | _________________ | ____/____/____ | [ ] All checks pass / [ ] Issues found |
| Intern | _________________ | ____/____/____ | [ ] All checks pass / [ ] Issues found |

**Issues Found During UAT**:

| # | Step | Issue Description | Severity | Resolution |
|---|------|-------------------|----------|------------|
| 1 | — | — | — | — |
| 2 | — | — | — | — |
| 3 | — | — | — | — |
