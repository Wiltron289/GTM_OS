// Phase 1B: Create NBA_AE_Config__c, clean NBA_Queue__c, invalidate Platform Cache

Id userId = UserInfo.getUserId();
System.debug('Current User: ' + UserInfo.getUserName() + ' (' + userId + ')');

// 1. Upsert NBA_AE_Config__c with Cadence_Variant__c = 'A'
NBA_AE_Config__c config = NBA_AE_Config__c.getInstance(userId);
if (config == null || config.Id == null) {
    config = new NBA_AE_Config__c(
        SetupOwnerId = userId,
        Cadence_Variant__c = 'A'
    );
    upsert config;
    System.debug('CREATED NBA_AE_Config__c with Variant A');
} else {
    config.Cadence_Variant__c = 'A';
    update config;
    System.debug('UPDATED NBA_AE_Config__c to Variant A');
}

// 2. Clean active NBA_Queue__c records — set to Expired
List<NBA_Queue__c> activeRecords = [
    SELECT Id, Status__c, Action_Type__c, Opportunity__c
    FROM NBA_Queue__c
    WHERE Sales_Rep__c = :userId
      AND Status__c IN ('New', 'Pending', 'In Progress', 'Accepted', 'Snoozed')
];

System.debug('Found ' + activeRecords.size() + ' active NBA_Queue__c records to expire');

for (NBA_Queue__c rec : activeRecords) {
    rec.Status__c = 'Expired';
    System.debug('  Expiring: ' + rec.Action_Type__c + ' on Opp ' + rec.Opportunity__c);
}

if (!activeRecords.isEmpty()) {
    update activeRecords;
    System.debug('Expired ' + activeRecords.size() + ' records');
}

// 3. Invalidate Platform Cache
NbaCacheService.invalidate(userId);
System.debug('Platform Cache invalidated for user ' + userId);

System.debug('=== Phase 1B COMPLETE ===');
