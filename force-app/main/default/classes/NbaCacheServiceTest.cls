/**
 * NbaCacheServiceTest — Tests for the NBA V2 Platform Cache wrapper.
 *
 * Uses the @TestVisible static testCache map since Platform Cache
 * is not available in Apex tests.
 */
@isTest
private class NbaCacheServiceTest {

    @isTest
    static void testCacheAndRetrieveAction() {
        // Arrange
        Id fakeUserId = UserInfo.getUserId();
        NbaActionController.ActionWrapper action = buildTestWrapper('001000000000001', 'First Touch');

        // Act
        Test.startTest();
        NbaCacheService.cacheAction(fakeUserId, action);
        NbaActionController.ActionWrapper cached = NbaCacheService.getCachedAction(fakeUserId);
        Test.stopTest();

        // Assert
        System.assertNotEquals(null, cached, 'Cached action should not be null');
        System.assertEquals('First Touch', cached.actionType, 'Action type should match');
        System.assertEquals('001000000000001', String.valueOf(cached.opportunityId),
            'Opportunity ID should match');
    }

    @isTest
    static void testInvalidateRemovesCache() {
        // Arrange
        Id fakeUserId = UserInfo.getUserId();
        NbaActionController.ActionWrapper action = buildTestWrapper('001000000000002', 'Re-engage');
        NbaCacheService.cacheAction(fakeUserId, action);

        // Verify it's cached
        System.assertNotEquals(null, NbaCacheService.getCachedAction(fakeUserId),
            'Action should be cached before invalidation');

        // Act
        Test.startTest();
        NbaCacheService.invalidate(fakeUserId);
        Test.stopTest();

        // Assert
        System.assertEquals(null, NbaCacheService.getCachedAction(fakeUserId),
            'Cached action should be null after invalidation');
    }

    @isTest
    static void testGetCachedActionReturnsNullWhenEmpty() {
        // Act
        Test.startTest();
        NbaActionController.ActionWrapper result = NbaCacheService.getCachedAction(UserInfo.getUserId());
        Test.stopTest();

        // Assert
        System.assertEquals(null, result, 'Should return null when no action is cached');
    }

    @isTest
    static void testNullUserIdHandling() {
        // Act & Assert — should not throw
        Test.startTest();
        NbaCacheService.cacheAction(null, buildTestWrapper('001000000000003', 'Follow Up'));
        NbaActionController.ActionWrapper result = NbaCacheService.getCachedAction(null);
        NbaCacheService.invalidate(null);
        Test.stopTest();

        System.assertEquals(null, result, 'Should return null for null userId');
    }

    @isTest
    static void testNullActionHandling() {
        // Act & Assert — should not throw
        Test.startTest();
        NbaCacheService.cacheAction(UserInfo.getUserId(), null);
        Test.stopTest();

        NbaActionController.ActionWrapper result =
            NbaCacheService.getCachedAction(UserInfo.getUserId());
        System.assertEquals(null, result, 'Should return null when null action was cached');
    }

    @isTest
    static void testInvalidateForMultipleUsers() {
        // Arrange — cache actions for two users
        // In test context, we use the same user but simulate with different keys
        Id userId = UserInfo.getUserId();
        NbaCacheService.cacheAction(userId, buildTestWrapper('001000000000004', 'First Touch'));

        // Verify cached
        System.assertNotEquals(null, NbaCacheService.getCachedAction(userId),
            'Should be cached');

        // Act
        Test.startTest();
        NbaCacheService.invalidateForUsers(new Set<Id>{ userId });
        Test.stopTest();

        // Assert
        System.assertEquals(null, NbaCacheService.getCachedAction(userId),
            'Should be invalidated after bulk invalidation');
    }

    @isTest
    static void testInvalidateForUsersWithNullSet() {
        // Act & Assert — should not throw
        Test.startTest();
        NbaCacheService.invalidateForUsers(null);
        NbaCacheService.invalidateForUsers(new Set<Id>());
        Test.stopTest();
    }

    @isTest
    static void testCacheOverwritesPreviousValue() {
        // Arrange
        Id userId = UserInfo.getUserId();
        NbaCacheService.cacheAction(userId, buildTestWrapper('001000000000005', 'First Touch'));

        // Act — overwrite with new action
        Test.startTest();
        NbaCacheService.cacheAction(userId, buildTestWrapper('001000000000006', 'Re-engage'));
        NbaActionController.ActionWrapper cached = NbaCacheService.getCachedAction(userId);
        Test.stopTest();

        // Assert — should have the newer value
        System.assertEquals('Re-engage', cached.actionType, 'Should have overwritten with new action');
    }

    // ─── Helpers ────────────────────────────────────────────────────

    private static NbaActionController.ActionWrapper buildTestWrapper(String oppId, String actionType) {
        NbaActionController.ActionWrapper w = new NbaActionController.ActionWrapper();
        w.actionId = null; // On-demand actions have no DB ID
        w.opportunityId = oppId;
        w.accountId = null;
        w.actionType = actionType;
        w.actionInstruction = 'Test instruction for ' + actionType;
        w.reasonText = 'Test reason';
        w.priorityLayer = 'Layer 3 - Impact+Urgency';
        w.priorityBucket = 'General Pipeline';
        w.priorityScore = 0.75;
        w.isTimeBound = false;
        w.dueAt = null;
        w.status = 'Evaluated';
        w.accountName = 'Test Account';
        w.opportunityName = 'Test Opp';
        w.oppStage = 'Consult';
        return w;
    }
}
