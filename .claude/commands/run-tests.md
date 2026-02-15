Run Apex tests and help me understand the results.

Ask me: Do I want to run all local tests, a specific test class, or a specific test method?

**All local tests with coverage:**
```
sf apex run test --synchronous --result-format human --test-level RunLocalTests --code-coverage
```

**Specific class with coverage:**
```
sf apex run test --class-names <TestClassName> --synchronous --result-format human --code-coverage
```

**Specific method:**
```
sf apex run test --tests <TestClassName.methodName> --synchronous --result-format human
```

**Multiple test classes:**
```
sf apex run test --class-names "TestClass1,TestClass2,TestClass3" --synchronous --result-format human --code-coverage
```

After tests run:
1. Show me pass/fail results clearly
2. If `--code-coverage` was used, show per-class coverage percentages
3. Flag any classes below 75% coverage — these will block production deployment
4. If any tests failed, explain the failures in plain language
5. If coverage is low, identify which lines are not covered and suggest test scenarios to cover them
6. If all tests passed with good coverage, confirm everything looks good

If tests fail, help me fix them by:
- Reading the relevant Apex class and test class
- Identifying the root cause (assertion failure, null pointer, governor limit, etc.)
- Suggesting the fix with an explanation of why it failed
