// Seed 5 sample NBA_Queue__c records with V2 fields populated
// Covers different scenarios: First Touch, Re-engage, Stage Progression, Time-Bound, Blitz

// Get a sales rep (Andrew Sanchez or first active user)
User salesRep = [SELECT Id, Name FROM User WHERE IsActive = true AND Name = 'Andrew Sanchez' LIMIT 1];

// Get open opportunities with accounts
List<Opportunity> opps = [
    SELECT Id, Name, AccountId, Account.Name, StageName, Amount
    FROM Opportunity
    WHERE IsClosed = false AND AccountId != null AND Amount > 0
    ORDER BY Amount DESC NULLS LAST
    LIMIT 5
];

if (opps.size() < 5) {
    System.debug('Not enough open opps with accounts. Found: ' + opps.size());
    return;
}

List<NBA_Queue__c> records = new List<NBA_Queue__c>();

// Record 1: Layer 1 Time-Bound — SLA First Touch (highest priority)
records.add(new NBA_Queue__c(
    Account__c = opps[0].AccountId,
    Opportunity__c = opps[0].Id,
    Sales_Rep__c = salesRep.Id,
    Status__c = 'In Progress',
    Action_Type__c = 'First Touch',
    Priority_Score__c = 95.50,
    Impact_Score__c = 0.8200,
    Urgency_Score__c = 0.9500,
    Priority_Bucket__c = 'Cadence Due Today',
    Priority_Layer__c = 'Layer 1 - Time Bound',
    Is_Time_Bound__c = true,
    Cadence_Stage__c = 1,
    Attempt_Count_Today__c = 0,
    Source_Path__c = 'Immediate',
    Rule_Name__c = 'SLA_First_Touch',
    Action_Instruction__c = 'Call to introduce yourself — new high-MRR opportunity assigned today',
    Workflow_Mode__c = 'Pipeline',
    Workstream__c = 'Cadence',
    ReasonText__c = 'New $' + String.valueOf(opps[0].Amount) + ' opportunity assigned — SLA requires first touch within 1 hour',
    Subject__c = 'SLA First Touch: ' + opps[0].Account.Name,
    DueAt__c = Datetime.now().addHours(1),
    Due_Date__c = Date.today()
));

// Record 2: Layer 3 Late-Stage Stalled — Re-engage
records.add(new NBA_Queue__c(
    Account__c = opps[1].AccountId,
    Opportunity__c = opps[1].Id,
    Sales_Rep__c = salesRep.Id,
    Status__c = 'Pending',
    Action_Type__c = 'Re-engage',
    Priority_Score__c = 78.30,
    Impact_Score__c = 0.7100,
    Urgency_Score__c = 0.6500,
    Priority_Bucket__c = 'Late-Stage Stalled',
    Priority_Layer__c = 'Layer 3 - Impact+Urgency',
    Is_Time_Bound__c = false,
    Cadence_Stage__c = 2,
    Attempt_Count_Today__c = 1,
    Last_Attempt_Method__c = 'Call',
    Source_Path__c = 'Pipeline Cadence',
    Rule_Name__c = 'Re_Engage_Cold',
    Action_Instruction__c = 'Re-engage — deal going cold, 5 days since last activity',
    Workflow_Mode__c = 'Pipeline',
    Workstream__c = 'Cadence',
    ReasonText__c = 'No activity in 5 days on $' + String.valueOf(opps[1].Amount) + ' opportunity at ' + opps[1].StageName + ' stage',
    Subject__c = 'Re-engage: ' + opps[1].Account.Name,
    Last_Call_Date__c = Datetime.now().addDays(-5),
    Due_Date__c = Date.today()
));

// Record 3: Layer 3 High Impact Focus — Stage Progression
records.add(new NBA_Queue__c(
    Account__c = opps[2].AccountId,
    Opportunity__c = opps[2].Id,
    Sales_Rep__c = salesRep.Id,
    Status__c = 'Pending',
    Action_Type__c = 'Stage Progression',
    Priority_Score__c = 72.10,
    Impact_Score__c = 0.8500,
    Urgency_Score__c = 0.4200,
    Priority_Bucket__c = 'High Impact Focus',
    Priority_Layer__c = 'Layer 3 - Impact+Urgency',
    Is_Time_Bound__c = false,
    Cadence_Stage__c = 1,
    Attempt_Count_Today__c = 0,
    Source_Path__c = 'Context Update',
    Rule_Name__c = 'Stage_Pressure',
    Action_Instruction__c = 'Push to next stage — high MRR, stuck at ' + opps[2].StageName + ' for 7 days',
    Workflow_Mode__c = 'Pipeline',
    Workstream__c = 'Motion',
    ReasonText__c = 'High-impact opportunity ($' + String.valueOf(opps[2].Amount) + ') stuck at ' + opps[2].StageName + ' — needs stage progression push',
    Subject__c = 'Stage Push: ' + opps[2].Account.Name,
    Due_Date__c = Date.today().addDays(1)
));

// Record 4: Snoozed action (to test snooze → re-entry)
records.add(new NBA_Queue__c(
    Account__c = opps[3].AccountId,
    Opportunity__c = opps[3].Id,
    Sales_Rep__c = salesRep.Id,
    Status__c = 'Snoozed',
    Action_Type__c = 'Follow Up',
    Priority_Score__c = 65.00,
    Impact_Score__c = 0.6000,
    Urgency_Score__c = 0.5500,
    Priority_Bucket__c = 'General Pipeline',
    Priority_Layer__c = 'Layer 3 - Impact+Urgency',
    Is_Time_Bound__c = false,
    Cadence_Stage__c = 3,
    Attempt_Count_Today__c = 2,
    Last_Attempt_Method__c = 'SMS',
    Source_Path__c = 'Pipeline Cadence',
    Rule_Name__c = 'NoConnect_Followup_2hr',
    Action_Instruction__c = 'Follow up after no-connect — snoozed by rep until tomorrow',
    Workflow_Mode__c = 'Pipeline',
    Workstream__c = 'Cadence',
    ReasonText__c = 'AE snoozed — 2 no-connect attempts today, will retry tomorrow',
    Subject__c = 'Snoozed Follow-up: ' + opps[3].Account.Name,
    Snoozed_Until__c = Datetime.now().addDays(1),
    Snooze_Reason__c = 'Will try again tomorrow morning',
    Due_Date__c = Date.today().addDays(1)
));

// Record 5: Layer 2 Blitz Mode — Blitz Outreach
records.add(new NBA_Queue__c(
    Account__c = opps[4].AccountId,
    Opportunity__c = opps[4].Id,
    Sales_Rep__c = salesRep.Id,
    Status__c = 'New',
    Action_Type__c = 'Blitz Outreach',
    Priority_Score__c = 88.00,
    Impact_Score__c = 0.7500,
    Urgency_Score__c = 0.8800,
    Priority_Bucket__c = 'Cadence Due Today',
    Priority_Layer__c = 'Layer 2 - Mode',
    Is_Time_Bound__c = false,
    Cadence_Stage__c = 1,
    Attempt_Count_Today__c = 0,
    Source_Path__c = 'Immediate',
    Rule_Name__c = 'Day1_Pressure_Call_1',
    Action_Instruction__c = 'Blitz campaign call — high-velocity outreach window',
    Workflow_Mode__c = 'Blitz',
    Workstream__c = 'Motion',
    ReasonText__c = 'Blitz outreach campaign active — $' + String.valueOf(opps[4].Amount) + ' opportunity targeted for rapid engagement',
    Subject__c = 'Blitz: ' + opps[4].Account.Name,
    Due_Date__c = Date.today()
));

insert records;
System.debug('Successfully created ' + records.size() + ' sample NBA V2 records:');
for (NBA_Queue__c r : records) {
    System.debug('  - ' + r.Name + ' | ' + r.Action_Type__c + ' | ' + r.Status__c + ' | ' + r.Priority_Layer__c);
}
