// ============================================================
// Phase 2: E2E Test Data Creation (20 Opportunities)
// ============================================================
// 7 First Touch (new) + 3 Re-engage + 2 Stage Prog +
// 3 Follow Up + 3 Time-Bound + 2 Connected Follow-up = 20
// ============================================================

Id userId = '005Hp00000iHg58IAC';
Id salesRT = '012Po00000Bz9HlIAJ';

// ── PHASE 2A: Create 7 First Touch Accounts + Opps + Scoring ──

Long ts = Datetime.now().getTime();
List<Account> ftAccts = new List<Account>();
String[] ftNames = new String[]{
    'E2E FT1 High Value', 'E2E FT2 Premium', 'E2E FT3 Mid Value',
    'E2E FT4 Standard', 'E2E FT5 Growth', 'E2E FT6 Starter', 'E2E FT7 Entry'
};

for (Integer i = 0; i < 7; i++) {
    ftAccts.add(new Account(
        Name = ftNames[i],
        Entity_ID__c = 'e2e-ft' + (i+1) + '-' + ts
    ));
}
insert ftAccts;
System.debug('Created 7 FT Accounts');

// Create FT Opportunities
Decimal[] ftAmounts = new Decimal[]{175, 150, 140, 130, 120, 110, 100};
List<Opportunity> ftOpps = new List<Opportunity>();
for (Integer i = 0; i < 7; i++) {
    ftOpps.add(new Opportunity(
        Name = ftNames[i],
        AccountId = ftAccts[i].Id,
        RecordTypeId = salesRT,
        StageName = 'New',
        Amount = ftAmounts[i],
        CloseDate = Date.today().addDays(30),
        OwnerId = userId,
        Source__c = 'N/A'
    ));
}
insert ftOpps;
System.debug('Created 7 FT Opportunities');

// Create FT Account_Scoring records
Decimal[] ftProbs = new Decimal[]{90, 80, 70, 60, 45, 35, 25};
List<Account_Scoring__c> ftScoring = new List<Account_Scoring__c>();
for (Integer i = 0; i < 7; i++) {
    ftScoring.add(new Account_Scoring__c(
        Account__c = ftAccts[i].Id,
        Entity_ID__c = ftAccts[i].Entity_ID__c,
        Prob_Payroll_Conversion__c = ftProbs[i]
    ));
}
insert ftScoring;
System.debug('Created 7 FT Account_Scoring records');

// ── PHASE 2B: Reassign 13 Existing Opps + Create Scoring ──

// Opp IDs by category
Id re1 = '006Po000010UGzhIAG'; // BLO Mt.Juliet $165 54d Consult
Id re2 = '006Po00000xlyjWIAQ'; // Jersey Mike's $129 65d Consult
Id re3 = '006Po00000xoCFKIA2'; // Simone Stalling $99 56d Consult
Id sp1 = '006Po00000yuZwbIAE'; // THE PIZZA PLACE $183 62d Closing
Id sp2 = '006Po00000zHRWvIAO'; // Steve's Coffee $107 35d Closing
Id fu1 = '006Po00000zGw6XIAS'; // Oconomowoc Lake $327 0d Connect
Id fu2 = '006Po000010pK2bIAE'; // Scooter's Coffee $315 0d Consult
Id fu3 = '006Po000013nrqXIAQ'; // Adventure West $255 0d Consult
Id tb1 = '006Po00000zH7unIAC'; // Mamacita's Taqueria $288 0d Closing
Id tb2 = '006Po000013tYN4IAM'; // Two Cumberland $285 0d Closing
Id tb3 = '006Po000013Q7LNIA0'; // QUENCH IT $225 0d Connect
Id cf1 = '006Po000013uczeIAA'; // Reflections Group $207 0d New
Id cf2 = '006Po0000120nv8IAA'; // Centurion Security $199 0d Connect

Set<Id> existingIds = new Set<Id>{
    re1, re2, re3, sp1, sp2, fu1, fu2, fu3,
    tb1, tb2, tb3, cf1, cf2
};

List<Opportunity> existingOpps = [
    SELECT Id, OwnerId, AccountId, Account.Entity_ID__c
    FROM Opportunity WHERE Id IN :existingIds
];

// Log original owners for cleanup
for (Opportunity o : existingOpps) {
    System.debug('ORIGINAL_OWNER|' + o.Id + '|' + o.OwnerId);
    o.OwnerId = userId;
}
update existingOpps;
System.debug('Reassigned ' + existingOpps.size() + ' existing opps');

// Build account maps
Map<Id, Id> oppToAcct = new Map<Id, Id>();
Map<Id, String> acctToEntity = new Map<Id, String>();
for (Opportunity o : existingOpps) {
    oppToAcct.put(o.Id, o.AccountId);
    acctToEntity.put(o.AccountId, o.Account.Entity_ID__c);
}

// Check which accounts already have scoring
Set<Id> acctIds = new Set<Id>(oppToAcct.values());
Set<Id> acctsWithScoring = new Set<Id>();
for (Account_Scoring__c s : [SELECT Account__c FROM Account_Scoring__c WHERE Account__c IN :acctIds]) {
    acctsWithScoring.add(s.Account__c);
}

// Probability map per opp
Map<Id, Decimal> probMap = new Map<Id, Decimal>{
    re1 => 85, re2 => 50, re3 => 35,
    sp1 => 80, sp2 => 65,
    fu1 => 55, fu2 => 40, fu3 => 30,
    tb1 => 75, tb2 => 60, tb3 => 45,
    cf1 => 70, cf2 => 50
};

// Create Account_Scoring for those that don't have one
List<Account_Scoring__c> newScoring = new List<Account_Scoring__c>();
Set<Id> processed = new Set<Id>();
for (Id oppId : probMap.keySet()) {
    Id acctId = oppToAcct.get(oppId);
    if (acctId == null || acctsWithScoring.contains(acctId) || processed.contains(acctId)) continue;

    String entityId = acctToEntity.get(acctId);
    if (String.isBlank(entityId)) {
        System.debug('WARN: No Entity_ID on account ' + acctId + ' for opp ' + oppId);
        continue;
    }
    newScoring.add(new Account_Scoring__c(
        Account__c = acctId,
        Entity_ID__c = entityId,
        Prob_Payroll_Conversion__c = probMap.get(oppId)
    ));
    processed.add(acctId);
}
if (!newScoring.isEmpty()) {
    insert newScoring;
}
System.debug('Created ' + newScoring.size() + ' Account_Scoring for existing opps');

// ── PHASE 2C: Create Time-Bound Events ──

Datetime now = Datetime.now();
List<Event> events = new List<Event>{
    new Event(WhatId=tb1, Subject='E2E Meeting 1h', StartDateTime=now.addHours(1), EndDateTime=now.addHours(1).addMinutes(30), OwnerId=userId),
    new Event(WhatId=tb2, Subject='E2E Meeting 3h', StartDateTime=now.addHours(3), EndDateTime=now.addHours(3).addMinutes(30), OwnerId=userId),
    new Event(WhatId=tb3, Subject='E2E Meeting 6h', StartDateTime=now.addHours(6), EndDateTime=now.addHours(6).addMinutes(30), OwnerId=userId)
};
insert events;
System.debug('Created 3 Time-Bound Events');

// ── INVALIDATE CACHE ──
NbaCacheService.invalidate(userId);

// ── SUMMARY OUTPUT ──
System.debug('========== E2E DATA SUMMARY ==========');
for (Integer i = 0; i < 7; i++) {
    System.debug('FT' + (i+1) + '|' + ftOpps[i].Id + '|' + ftNames[i] + '|$' + ftAmounts[i] + '|Prob=' + ftProbs[i]);
}
System.debug('RE1|' + re1 + '|BLO Mt.Juliet|$165|Prob=85');
System.debug('RE2|' + re2 + '|Jersey Mikes|$129|Prob=50');
System.debug('RE3|' + re3 + '|Simone Stalling|$99|Prob=35');
System.debug('SP1|' + sp1 + '|THE PIZZA PLACE|$183|Prob=80');
System.debug('SP2|' + sp2 + '|Steves Coffee|$107|Prob=65');
System.debug('FU1|' + fu1 + '|Oconomowoc Lake|$327|Prob=55');
System.debug('FU2|' + fu2 + '|Scooters Coffee|$315|Prob=40');
System.debug('FU3|' + fu3 + '|Adventure West|$255|Prob=30');
System.debug('TB1|' + tb1 + '|Mamacitas|$288|Prob=75|Event+1h');
System.debug('TB2|' + tb2 + '|Two Cumberland|$285|Prob=60|Event+3h');
System.debug('TB3|' + tb3 + '|QUENCH IT|$225|Prob=45|Event+6h');
System.debug('CF1|' + cf1 + '|Reflections Group|$207|Prob=70');
System.debug('CF2|' + cf2 + '|Centurion Security|$199|Prob=50');
for (Event e : events) {
    System.debug('EVENT|' + e.Id + '|' + e.Subject + '|' + e.StartDateTime);
}
System.debug('========== PHASE 2 COMPLETE ==========');
