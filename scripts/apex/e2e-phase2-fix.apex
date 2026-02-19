// ============================================================
// Phase 2 Fix: Set source DateTime fields for correct detection
// ============================================================
// Formula chain:
//   Date_Time_Last_Reassignment__c → Hours_Since_Assignment__c
//   Last_Call_Date_Time__c → Days_Since_Last_Call__c (business days)
//   Last_Meeting_Date__c → Days_Since_Last_Meeting__c (business days)
//   Days_Since_Last_Interaction__c = MIN(Call, Meeting)
// ============================================================

Id userId = '005Hp00000iHg58IAC';

// FT opp IDs
List<Id> ftIds = new List<Id>{
    '006dy00000Kf39iAAB', '006dy00000Kf39jAAB', '006dy00000Kf39kAAB',
    '006dy00000Kf39lAAB', '006dy00000Kf39mAAB', '006dy00000Kf39nAAB',
    '006dy00000Kf39oAAB'
};

// RE opp IDs
List<Id> reIds = new List<Id>{
    '006Po000010UGzhIAG', '006Po00000xlyjWIAQ', '006Po00000xoCFKIA2'
};

Datetime now = Datetime.now();

// ── Fix FT opps ──
// Set Date_Time_Last_Reassignment__c = NOW() → Hours_Since_Assignment ≈ 0
// First Touch: hoursSinceAssignment <= 1 AND lastValidTouchDate == null
List<Opportunity> ftOpps = [SELECT Id FROM Opportunity WHERE Id IN :ftIds];
for (Opportunity o : ftOpps) {
    o.Date_Time_Last_Reassignment__c = now;
}
update ftOpps;
System.debug('Set Date_Time_Last_Reassignment=NOW on ' + ftOpps.size() + ' FT opps');

// ── Fix RE opps ──
// Set Last_Call_Date_Time = 7 calendar days ago → 5 business days (Wed to Wed)
// Set Last_Meeting_Date = 2 years ago → very large business days
// MIN(5, large) = 5 → Re-engage at cadence Day 0
Datetime callDate = now.addDays(-7);      // 7 cal days ago = 5 biz days
Datetime meetingDate = now.addDays(-730);  // ~2 years ago

List<Opportunity> reOpps = [SELECT Id FROM Opportunity WHERE Id IN :reIds];
for (Opportunity o : reOpps) {
    o.Last_Call_Date_Time__c = callDate;
    o.Last_Meeting_Date__c = meetingDate;
}
update reOpps;
System.debug('Set Last_Call_Date_Time=-7d, Last_Meeting_Date=-730d on ' + reOpps.size() + ' RE opps');

// ── Verify formula outputs ──
Set<Id> allIds = new Set<Id>();
allIds.addAll(ftIds);
allIds.addAll(reIds);
List<Opportunity> verify = [
    SELECT Id, Name, Days_Since_Last_Interaction__c,
           Days_Since_Last_Call__c, Days_Since_Last_Meeting__c,
           Hours_Since_Assignment__c, Date_Time_Last_Reassignment__c,
           Last_Call_Date_Time__c, Last_Meeting_Date__c
    FROM Opportunity WHERE Id IN :allIds ORDER BY Name
];
for (Opportunity o : verify) {
    System.debug('VERIFY|' + o.Name +
        '|DaysSinceInteraction=' + o.Days_Since_Last_Interaction__c +
        '|DaysSinceCall=' + o.Days_Since_Last_Call__c +
        '|DaysSinceMtg=' + o.Days_Since_Last_Meeting__c +
        '|HrsSinceAssign=' + o.Hours_Since_Assignment__c);
}

NbaCacheService.invalidate(userId);
System.debug('Cache invalidated. Phase 2 Fix COMPLETE.');
