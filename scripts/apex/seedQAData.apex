// ============================================================
// QA Seed Script — NBA V2 Phase 6 Testing
// ============================================================
// 1. Re-own 3 existing opps to your user (First Touch + Stage Progression)
// 2. Create 3 brand-new opps (triggers First Touch via Opp trigger)
// 3. Create an Event starting in 10 minutes (triggers time-bound action)
// ============================================================

Id myUserId = '005Hp00000iHg58IAC'; // lwilson (System Admin)

// ── 1. Re-own existing opps ──────────────────────
List<Opportunity> reownOpps = [
    SELECT Id, OwnerId, StageName, Account.Name
    FROM Opportunity
    WHERE Id IN (
        '006dy00000KVT73AAH',   // Placemakr - New Opportunity stage
        '006dy00000KVKLbAAP',   // Dynamic Integrated Security - New stage
        '006dy00000KVSvlAAH'    // Alchemy Works - Ready to Convert stage
    )
];

for (Opportunity opp : reownOpps) {
    opp.OwnerId = myUserId;
    System.debug('Re-owning: ' + opp.Account.Name + ' (' + opp.StageName + ')');
}
update reownOpps;
System.debug('✓ Re-owned ' + reownOpps.size() + ' opps');

// ── 2. Create new opps on accounts without open opps ──
List<Opportunity> newOpps = new List<Opportunity>();

// Shroyer Ranch (Primary Account, no open opps)
newOpps.add(new Opportunity(
    AccountId = '001Po00001QsScaIAF',
    Name = 'Shroyer Ranch - QA Test',
    StageName = 'New',
    CloseDate = Date.today().addDays(30),
    Amount = 1500,
    OwnerId = myUserId,
    Source__c = 'N/A'
));

// Drip Drip Cafe (Primary Account, no open opps)
newOpps.add(new Opportunity(
    AccountId = '001Po00001QsXfZIAV',
    Name = 'Drip Drip Cafe - QA Test',
    StageName = 'New',
    CloseDate = Date.today().addDays(30),
    Amount = 2200,
    OwnerId = myUserId,
    Source__c = 'N/A'
));

// Gulf Coast Yacht & Marine (Primary Account, no open opps)
newOpps.add(new Opportunity(
    AccountId = '001Po00001QslqeIAB',
    Name = 'Gulf Coast Yacht & Marine - QA Test',
    StageName = 'New',
    CloseDate = Date.today().addDays(30),
    Amount = 3400,
    OwnerId = myUserId,
    Source__c = 'N/A'
));

insert newOpps;
System.debug('✓ Created ' + newOpps.size() + ' new opps');
for (Opportunity o : newOpps) {
    System.debug('  → ' + o.Name + ' (' + o.Id + ')');
}

// ── 3. Create event in ~10 minutes on first new opp (time-bound) ──
Event mtg = new Event(
    WhatId = newOpps[0].Id,  // Paris Baguette Redwood
    OwnerId = myUserId,
    Subject = 'Discovery Call - Paris Baguette',
    StartDateTime = Datetime.now().addMinutes(10),
    EndDateTime = Datetime.now().addMinutes(40),
    Description = 'QA test: time-bound event for NBA V2'
);
insert mtg;
System.debug('✓ Created Event: ' + mtg.Subject + ' at ' + mtg.StartDateTime + ' (Id: ' + mtg.Id + ')');

System.debug('');
System.debug('========== QA SEED COMPLETE ==========');
System.debug('Re-owned opps: Placemakr (New Opportunity), Dynamic Integrated Security (New), Alchemy Works (Ready to Convert)');
System.debug('New opps: Paris Baguette ($1500), Drip Drip Cafe ($2200), Gulf Coast Yacht ($3400)');
System.debug('Event: Discovery Call on Paris Baguette in 10 min');
System.debug('');
System.debug('TEST SCENARIOS:');
System.debug('1. First Touch cadence → new opps should generate First Touch actions');
System.debug('2. Time-bound event → Paris Baguette should get Layer 1 time-bound action');
System.debug('3. Stage Progression → Alchemy Works (Ready to Convert) should get Stage Progression');
System.debug('4. Re-owned opps → Placemakr + Dynamic should get First Touch (new to you)');
