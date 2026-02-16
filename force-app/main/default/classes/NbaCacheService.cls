/**
 * NbaCacheService — Platform Cache wrapper for NBA V2 per-AE action caching.
 *
 * Stores the current on-demand evaluated action per AE in Org cache with a
 * 5-minute TTL. Gracefully degrades if cache partition is unavailable —
 * the controller will simply re-evaluate on every request.
 *
 * In test context, uses a static Map (Platform Cache is not available in tests).
 */
public with sharing class NbaCacheService {

    private static final String PARTITION_NAME = 'local.NbaActionCache';
    private static final Integer DEFAULT_TTL_SECONDS = 300; // 5 minutes

    // ─── Test Double ────────────────────────────────────────────────
    // Platform Cache is not available in Apex tests. Use a static map.
    @TestVisible
    private static Map<String, String> testCache = new Map<String, String>();
    @TestVisible
    private static Boolean useTestCache = Test.isRunningTest();

    // ─── Public API ─────────────────────────────────────────────────

    /**
     * Cache an ActionWrapper for a given AE user.
     * @param userId The AE's User ID
     * @param action The evaluated action to cache (serialized to JSON)
     */
    public static void cacheAction(Id userId, NbaActionController.ActionWrapper action) {
        if (userId == null || action == null) {
            return;
        }
        String key = buildKey(userId);
        String jsonVal = JSON.serialize(action);

        if (useTestCache) {
            testCache.put(key, jsonVal);
            return;
        }

        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(PARTITION_NAME);
            partition.put(key, jsonVal, DEFAULT_TTL_SECONDS);
        } catch (Exception e) {
            // Cache not available — silent fallback. Controller will re-evaluate.
            System.debug(LoggingLevel.WARN,
                'NbaCacheService.cacheAction: Cache put failed for user ' + userId + ': ' + e.getMessage());
        }
    }

    /**
     * Retrieve a cached ActionWrapper for a given AE user.
     * @param userId The AE's User ID
     * @return The cached ActionWrapper, or null if not cached or expired
     */
    public static NbaActionController.ActionWrapper getCachedAction(Id userId) {
        if (userId == null) {
            return null;
        }
        String key = buildKey(userId);

        if (useTestCache) {
            String val = testCache.get(key);
            return val != null
                ? (NbaActionController.ActionWrapper) JSON.deserialize(val, NbaActionController.ActionWrapper.class)
                : null;
        }

        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(PARTITION_NAME);
            String val = (String) partition.get(key);
            return val != null
                ? (NbaActionController.ActionWrapper) JSON.deserialize(val, NbaActionController.ActionWrapper.class)
                : null;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'NbaCacheService.getCachedAction: Cache get failed for user ' + userId + ': ' + e.getMessage());
            return null;
        }
    }

    /**
     * Invalidate (remove) the cached action for a given AE user.
     * Called after AE interactions (complete/snooze/dismiss) and by triggers
     * when CRM state changes.
     * @param userId The AE's User ID
     */
    public static void invalidate(Id userId) {
        if (userId == null) {
            return;
        }
        String key = buildKey(userId);

        if (useTestCache) {
            testCache.remove(key);
            return;
        }

        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(PARTITION_NAME);
            partition.remove(key);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'NbaCacheService.invalidate: Cache remove failed for user ' + userId + ': ' + e.getMessage());
        }
    }

    /**
     * Invalidate cache for multiple AE users at once.
     * @param userIds Set of AE User IDs
     */
    public static void invalidateForUsers(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }
        for (Id userId : userIds) {
            invalidate(userId);
        }
    }

    // ─── Private Helpers ────────────────────────────────────────────

    /**
     * Build cache key from user ID. Uses first 15 chars of ID.
     * Platform Cache keys must be alphanumeric only (no underscores, hyphens, etc.).
     */
    private static String buildKey(Id userId) {
        return 'nba' + String.valueOf(userId).left(15);
    }
}
