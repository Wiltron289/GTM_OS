// Insert sample NBA_Queue__c records for Phase 5 demo
// Uses Opportunities owned by lwilson (System Admin) in UAT

Id aeUserId = '005Hp00000iHg58IAC'; // lwilson@joinhomebase.com.uat

List<NBA_Queue__c> actions = new List<NBA_Queue__c>();

// 1. First Touch — TOPSAIL STEAMER LLC ($496) — Pending, Layer 3, Call method
actions.add(new NBA_Queue__c(
    Opportunity__c = '006Po00000y2AokIAE',
    Account__c = '001Hp00002pLQjUIAW',
    Sales_Rep__c = aeUserId,
    Status__c = 'Pending',
    Action_Type__c = 'First Touch',
    Priority_Score__c = 82.50,
    Impact_Score__c = 0.7800,
    Urgency_Score__c = 0.8700,
    Priority_Bucket__c = 'Cadence Due Today',
    Priority_Layer__c = 'Layer 3 - Impact+Urgency',
    Is_Time_Bound__c = false,
    Cadence_Stage__c = 1,
    Attempt_Count_Today__c = 0,
    Last_Attempt_Method__c = 'Call',
    Source_Path__c = 'Immediate',
    Rule_Name__c = 'First Touch_SLA',
    Action_Instruction__c = 'Call TOPSAIL STEAMER LLC — new $496 opp, SLA first touch within 1 hour',
    ReasonText__c = 'High-MRR new opportunity. Impact: 0.78 (MRR $496). Urgency: 0.87 (SLA first touch).',
    Workflow_Mode__c = 'Pipeline',
    UniqueKey__c = 'V2|006Po00000y2AokIAE|First Touch',
    Workstream__c = 'Cadence',
    Description__c = 'SLA-driven first touch for new Payroll opportunity',
    Subject__c = 'First Touch Call — TOPSAIL STEAMER LLC'
));

// 2. Re-engage — Cubed Solutions ($357) — Pending, Layer 3, Call method
actions.add(new NBA_Queue__c(
    Opportunity__c = '006Po00000y1oJaIAI',
    Account__c = '001Po000013Xv79IAC',
    Sales_Rep__c = aeUserId,
    Status__c = 'Pending',
    Action_Type__c = 'Re-engage',
    Priority_Score__c = 71.30,
    Impact_Score__c = 0.6200,
    Urgency_Score__c = 0.8040,
    Priority_Bucket__c = 'Neglected',
    Priority_Layer__c = 'Layer 3 - Impact+Urgency',
    Is_Time_Bound__c = false,
    Cadence_Stage__c = 1,
    Attempt_Count_Today__c = 0,
    Last_Attempt_Method__c = 'Call',
    Source_Path__c = 'Pipeline Cadence',
    Rule_Name__c = 'Re-engage_Inactivity',
    Action_Instruction__c = 'Re-engage Cubed Solutions — 7 days since last interaction, deal going cold',
    ReasonText__c = 'Inactivity alert. Impact: 0.62 (MRR $357). Urgency: 0.80 (7 days inactive at Hand-Off).',
    Workflow_Mode__c = 'Pipeline',
    UniqueKey__c = 'V2|006Po00000y1oJaIAI|Re-engage',
    Workstream__c = 'Cadence',
    Description__c = 'Re-engagement outreach for stalled deal',
    Subject__c = 'Re-engage Call — Cubed Solutions'
));

// 3. Stage Progression — Playa Bowls ($321) — In Progress (Active), Layer 3
actions.add(new NBA_Queue__c(
    Opportunity__c = '006Po00000y6PCUIA2',
    Account__c = '001Hp00002pJVzPIAW',
    Sales_Rep__c = aeUserId,
    Status__c = 'In Progress',
    Action_Type__c = 'Stage Progression',
    Priority_Score__c = 68.90,
    Impact_Score__c = 0.5900,
    Urgency_Score__c = 0.7880,
    Priority_Bucket__c = 'Late-Stage Stalled',
    Priority_Layer__c = 'Layer 3 - Impact+Urgency',
    Is_Time_Bound__c = false,
    Cadence_Stage__c = 2,
    Attempt_Count_Today__c = 1,
    Last_Attempt_Method__c = 'Call',
    Source_Path__c = 'Pipeline Cadence',
    Rule_Name__c = 'Stage_Progression_HandOff',
    Action_Instruction__c = 'Push Playa Bowls to close — stalled at Hand-Off for 5+ days, schedule implementation call',
    ReasonText__c = 'Late-stage stall. Impact: 0.59 (MRR $321). Urgency: 0.79 (5 days at Hand-Off, stage pressure).',
    Workflow_Mode__c = 'Pipeline',
    UniqueKey__c = 'V2|006Po00000y6PCUIA2|Stage Progression',
    Workstream__c = 'Cadence',
    Description__c = 'Stage progression push for Hand-Off opportunity',
    Subject__c = 'Stage Progression — Playa Bowls'
));

// 4. Follow Up — Visions Odeum ($315) — Pending, Layer 1 Time-Bound (meeting prep)
actions.add(new NBA_Queue__c(
    Opportunity__c = '006Po00000yGnVFIA0',
    Account__c = '001Po00000OFqAFIA1',
    Sales_Rep__c = aeUserId,
    Status__c = 'Pending',
    Action_Type__c = 'Follow Up',
    Priority_Score__c = 90.00,
    Impact_Score__c = 0.5700,
    Urgency_Score__c = 0.9500,
    Priority_Bucket__c = 'Cadence Due Today',
    Priority_Layer__c = 'Layer 1 - Time Bound',
    Is_Time_Bound__c = true,
    DueAt__c = Datetime.now().addHours(2),
    Cadence_Stage__c = 1,
    Attempt_Count_Today__c = 0,
    Last_Attempt_Method__c = 'Call',
    Source_Path__c = 'Immediate',
    Rule_Name__c = 'Meeting_Prep_TimeBound',
    Action_Instruction__c = 'Prep call for Visions Odeum meeting in 2 hours — review demo notes and pricing',
    ReasonText__c = 'Time-bound: meeting in 2 hours. Impact: 0.57 (MRR $315). Urgency: 0.95 (imminent meeting).',
    Workflow_Mode__c = 'Pipeline',
    UniqueKey__c = 'V2|006Po00000yGnVFIA0|Follow Up',
    Workstream__c = 'Events',
    Description__c = 'Pre-meeting prep call for upcoming demo',
    Subject__c = 'Meeting Prep — Visions Odeum'
));

// 5. SLA Response — Courtyard Marriott ($225) — Pending, Layer 3, SMS method (escalated)
actions.add(new NBA_Queue__c(
    Opportunity__c = '006Po00000yBaonIAC',
    Account__c = '001Po000019fjN0IAI',
    Sales_Rep__c = aeUserId,
    Status__c = 'Pending',
    Action_Type__c = 'SLA Response',
    Priority_Score__c = 55.80,
    Impact_Score__c = 0.4100,
    Urgency_Score__c = 0.7060,
    Priority_Bucket__c = 'General Pipeline',
    Priority_Layer__c = 'Layer 3 - Impact+Urgency',
    Is_Time_Bound__c = false,
    Cadence_Stage__c = 2,
    Attempt_Count_Today__c = 1,
    Last_Attempt_Method__c = 'SMS',
    Source_Path__c = 'Pipeline Cadence',
    Rule_Name__c = 'SLA_Response_Escalated',
    Action_Instruction__c = 'Send SMS to Courtyard Marriott — call attempt was no-connect, escalating to text',
    ReasonText__c = 'Method escalation: previous call no-connect. Impact: 0.41 (MRR $225). Urgency: 0.71 (SLA response).',
    Workflow_Mode__c = 'Pipeline',
    UniqueKey__c = 'V2|006Po00000yBaonIAC|SLA Response',
    Workstream__c = 'Cadence',
    Description__c = 'SLA response via SMS after failed call attempt',
    Subject__c = 'SLA SMS — Courtyard Marriott'
));

insert actions;
System.debug('Inserted ' + actions.size() + ' NBA_Queue__c records');
for (NBA_Queue__c a : actions) {
    System.debug('  → ' + a.Action_Type__c + ' | ' + a.Subject__c + ' | Status: ' + a.Status__c + ' | Id: ' + a.Id);
}
