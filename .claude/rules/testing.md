# Testing Patterns

## Apex Test Class Structure
```apex
@isTest
private class MyServiceTest {

    @TestSetup
    static void setupData() {
        // Create test data shared across all test methods
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) {
            accounts.add(new Account(Name = 'Test Account ' + i));
        }
        insert accounts;
    }

    @isTest
    static void testPositiveCase() {
        // Arrange
        List<Account> accounts = [SELECT Id, Name FROM Account];

        // Act
        Test.startTest();
        List<Account> result = MyService.processAccounts(accounts);
        Test.stopTest();

        // Assert
        System.assertEquals(200, result.size(), 'Should process all 200 accounts');
    }

    @isTest
    static void testNegativeCase() {
        // Test with invalid input
        Test.startTest();
        try {
            MyService.processAccounts(null);
            System.assert(false, 'Should have thrown an exception');
        } catch (MyCustomException e) {
            System.assert(e.getMessage().contains('cannot be null'),
                'Exception message should mention null input');
        }
        Test.stopTest();
    }

    @isTest
    static void testBulkOperation() {
        // Test with 200+ records to verify bulkification
        List<Account> accounts = [SELECT Id FROM Account];
        System.assertEquals(200, accounts.size(), 'Setup should create 200 records');

        Test.startTest();
        MyService.processAccounts(accounts);
        Test.stopTest();

        // Verify results — check limits weren't exceeded
        System.assert(Limits.getQueries() < 100,
            'Should not use more than 100 queries, used: ' + Limits.getQueries());
    }
}
```

## Test Data Rules
- Use `@TestSetup` for data shared across test methods — runs once, saves time.
- Create test data in the test — never rely on org data (tests must be org-independent).
- Use `SeeAllData=false` (the default) — never set `SeeAllData=true` unless testing reports or standard price books.
- Create 200+ records for bulk tests to verify governor limit compliance.

## Test.startTest() / Test.stopTest()
- Always wrap the method under test with `Test.startTest()` and `Test.stopTest()`.
- This resets governor limits — the code between start/stop gets a fresh set of limits.
- `Test.stopTest()` also forces async operations (future, queueable, batch) to execute synchronously.

## Assertion Standards
- Always include a message: `System.assertEquals(expected, actual, 'message explaining what failed')`.
- Use `System.assertEquals` / `System.assertNotEquals` for value comparisons.
- Use `System.assert(condition, 'message')` for boolean conditions.
- Test the business logic outcome, not just "it didn't throw."
- Verify record counts, field values, and side effects (child records created, emails sent, etc.).

## Test Scenarios to Cover
1. **Positive case** — happy path with valid data.
2. **Negative case** — invalid input, null values, missing required fields.
3. **Bulk case** — 200+ records to verify bulkification.
4. **Permission case** — use `System.runAs()` to test as different profiles/permission sets.
5. **Edge cases** — empty lists, single record, boundary values.

## System.runAs()
```apex
@isTest
static void testAsStandardUser() {
    User stdUser = [SELECT Id FROM User WHERE Profile.Name = 'Standard User' AND IsActive = true LIMIT 1];
    System.runAs(stdUser) {
        // Code runs as Standard User — tests sharing rules and FLS
    }
}
```
- Required when testing code that checks permissions or sharing.
- Also required when performing mixed DML (setup + non-setup objects).

## Coverage Requirements
- Minimum: **75%** code coverage to deploy to production.
- Target: **90%+** for quality code.
- Use `--code-coverage` flag to see per-class coverage:
  ```
  sf apex run test --class-names MyServiceTest --synchronous --result-format human --code-coverage
  ```
- Identify uncovered lines and write tests targeting those code paths.

## Jest Testing for LWC
- See `.claude/rules/lwc-patterns.md` for Jest setup and examples.
- Run: `npx lwc-jest --coverage`
- Test: rendering, user interactions, wire adapter responses, error states.
- Mock all `@salesforce/` imports.
