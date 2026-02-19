/**
 * @description Controller class for NBA Lightning Web Components.
 * Provides AuraEnabled methods for LWC interactions with NBA queue.
 */
public with sharing class NBAQueueController {

    /**
     * @description Wrapper for NBA queue item with computed properties
     */
    public class NBAQueueItem {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String assigneeId { get; set; }
        @AuraEnabled public String priorityBand { get; set; }
        @AuraEnabled public String workstream { get; set; }
        @AuraEnabled public String targetObject { get; set; }
        @AuraEnabled public String targetRecordId { get; set; }
        @AuraEnabled public DateTime dueAt { get; set; }
        @AuraEnabled public Decimal withinBandScore { get; set; }
        @AuraEnabled public String reasonText { get; set; }
        @AuraEnabled public String reasonJson { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String uniqueKey { get; set; }
        @AuraEnabled public DateTime focusUntil { get; set; }
    }

    /**
     * @description Get NBA queue items for current user
     * @param limitCount Number of records to return
     * @return List of NBA queue items
     */
    @AuraEnabled(cacheable=true)
    public static List<NBAQueueItem> getMyQueue(Integer limitCount) {
        try {
            Id currentUserId = UserInfo.getUserId();
            List<NBA_Queue__c> queueRecords = NBAQueueSelector.getByAssignee(currentUserId, limitCount);

            return convertToWrappers(queueRecords);

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving queue: ' + e.getMessage());
        }
    }

    /**
     * @description Get NBA queue items for a specific target record
     * @param targetRecordId Record ID
     * @param targetObjectType Object API name
     * @return List of NBA queue items
     */
    @AuraEnabled(cacheable=true)
    public static List<NBAQueueItem> getQueueForRecord(String targetRecordId, String targetObjectType) {
        try {
            Id recordId = Id.valueOf(targetRecordId);
            List<NBA_Queue__c> queueRecords = NBAQueueSelector.getByTargetRecord(targetObjectType, recordId);

            return convertToWrappers(queueRecords);

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving queue for record: ' + e.getMessage());
        }
    }

    /**
     * @description Accept an NBA action
     * @param queueItemId NBA_Queue__c record ID
     * @return Updated queue item
     */
    @AuraEnabled
    public static NBAQueueItem acceptAction(Id queueItemId) {
        try {
            NBA_Queue__c updated = NBAActionLifecycleService.acceptAction(queueItemId);

            // Refetch with all fields
            List<NBA_Queue__c> refetched = NBAQueueSelector.getByUniqueKeys(
                new Set<String>{ String.valueOf(updated.get(NBASchema.NBA_QUEUE_UNIQUE_KEY)) }
            );

            if (refetched.isEmpty()) {
                throw new AuraHandledException('Failed to retrieve updated record');
            }

            List<NBAQueueItem> wrappers = convertToWrappers(refetched);
            return wrappers[0];

        } catch (Exception e) {
            throw new AuraHandledException('Error accepting action: ' + e.getMessage());
        }
    }

    /**
     * @description Dismiss an NBA action
     * @param queueItemId NBA_Queue__c record ID
     * @param cooldownHours Hours to prevent re-evaluation
     * @return Updated queue item
     */
    @AuraEnabled
    public static NBAQueueItem dismissAction(Id queueItemId, Integer cooldownHours) {
        try {
            NBA_Queue__c updated = NBAActionLifecycleService.dismissAction(queueItemId, cooldownHours);

            List<NBA_Queue__c> refetched = NBAQueueSelector.getByUniqueKeys(
                new Set<String>{ String.valueOf(updated.get(NBASchema.NBA_QUEUE_UNIQUE_KEY)) }
            );

            if (refetched.isEmpty()) {
                throw new AuraHandledException('Failed to retrieve updated record');
            }

            List<NBAQueueItem> wrappers = convertToWrappers(refetched);
            return wrappers[0];

        } catch (Exception e) {
            throw new AuraHandledException('Error dismissing action: ' + e.getMessage());
        }
    }

    /**
     * @description Snooze an NBA action
     * @param queueItemId NBA_Queue__c record ID
     * @param snoozeHours Hours to snooze
     * @return Updated queue item
     */
    @AuraEnabled
    public static NBAQueueItem snoozeAction(Id queueItemId, Integer snoozeHours) {
        try {
            NBA_Queue__c updated = NBAActionLifecycleService.snoozeAction(queueItemId, snoozeHours);

            List<NBA_Queue__c> refetched = NBAQueueSelector.getByUniqueKeys(
                new Set<String>{ String.valueOf(updated.get(NBASchema.NBA_QUEUE_UNIQUE_KEY)) }
            );

            if (refetched.isEmpty()) {
                throw new AuraHandledException('Failed to retrieve updated record');
            }

            List<NBAQueueItem> wrappers = convertToWrappers(refetched);
            return wrappers[0];

        } catch (Exception e) {
            throw new AuraHandledException('Error snoozing action: ' + e.getMessage());
        }
    }

    /**
     * @description Complete an NBA action
     * @param queueItemId NBA_Queue__c record ID
     * @return Updated queue item
     */
    @AuraEnabled
    public static NBAQueueItem completeAction(Id queueItemId) {
        try {
            NBA_Queue__c updated = NBAActionLifecycleService.completeAction(queueItemId);

            List<NBA_Queue__c> refetched = NBAQueueSelector.getByUniqueKeys(
                new Set<String>{ String.valueOf(updated.get(NBASchema.NBA_QUEUE_UNIQUE_KEY)) }
            );

            if (refetched.isEmpty()) {
                throw new AuraHandledException('Failed to retrieve updated record');
            }

            List<NBAQueueItem> wrappers = convertToWrappers(refetched);
            return wrappers[0];

        } catch (Exception e) {
            throw new AuraHandledException('Error completing action: ' + e.getMessage());
        }
    }

    /**
     * @description Request NBA cache refresh for current user (updated for new architecture)
     * @param includeEvents Deprecated - kept for backward compatibility
     * @param includeCadence Deprecated - kept for backward compatibility
     * @param includeProspecting Deprecated - kept for backward compatibility
     * @return Success message
     */
    @AuraEnabled
    public static String requestEvaluation(
        Boolean includeEvents,
        Boolean includeCadence,
        Boolean includeProspecting
    ) {
        try {
            Id currentUserId = UserInfo.getUserId();

            // Use new NBA architecture: refresh cache for active config
            NBASmartQueueService.refreshCache(currentUserId, null);

            return 'Cache refresh initiated successfully';

        } catch (Exception e) {
            throw new AuraHandledException('Error requesting evaluation: ' + e.getMessage());
        }
    }

    /**
     * @description Get workstream counts for current user
     * @return Map of workstream to count
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getWorkstreamCounts() {
        try {
            Id currentUserId = UserInfo.getUserId();
            return NBAQueueSelector.getActiveCountByWorkstream(currentUserId);

        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving workstream counts: ' + e.getMessage());
        }
    }

    /**
     * @description Convert NBA_Queue__c records to wrapper objects
     * @param records List of NBA_Queue__c records
     * @return List of wrapper objects
     */
    private static List<NBAQueueItem> convertToWrappers(List<NBA_Queue__c> records) {
        List<NBAQueueItem> wrappers = new List<NBAQueueItem>();

        for (NBA_Queue__c record : records) {
            NBAQueueItem wrapper = new NBAQueueItem();
            wrapper.id = record.Id;
            wrapper.assigneeId = (String) record.get(NBASchema.NBA_QUEUE_ASSIGNEE);
            wrapper.priorityBand = (String) record.get(NBASchema.NBA_QUEUE_PRIORITY_BAND);
            wrapper.workstream = (String) record.get(NBASchema.NBA_QUEUE_WORKSTREAM);
            wrapper.targetObject = (String) record.get(NBASchema.NBA_QUEUE_TARGET_OBJECT);
            wrapper.targetRecordId = (String) record.get(NBASchema.NBA_QUEUE_TARGET_RECORD_ID);
            wrapper.dueAt = (DateTime) record.get(NBASchema.NBA_QUEUE_DUE_AT);
            wrapper.withinBandScore = (Decimal) record.get(NBASchema.NBA_QUEUE_WITHIN_BAND_SCORE);
            wrapper.reasonText = (String) record.get(NBASchema.NBA_QUEUE_REASON_TEXT);
            wrapper.reasonJson = (String) record.get(NBASchema.NBA_QUEUE_REASON_JSON);
            wrapper.status = (String) record.get(NBASchema.NBA_QUEUE_STATUS);
            wrapper.uniqueKey = (String) record.get(NBASchema.NBA_QUEUE_UNIQUE_KEY);
            wrapper.focusUntil = (DateTime) record.get(NBASchema.NBA_QUEUE_FOCUS_UNTIL);

            wrappers.add(wrapper);
        }

        return wrappers;
    }
}