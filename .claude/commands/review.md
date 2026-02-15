Review my Salesforce code for best practices, security issues, and governor limit violations.

If I don't specify files, ask me which files or components to review.

Check for these issues and flag them clearly:

**Governor Limit Violations (Critical):**
- SOQL queries inside loops
- DML statements inside loops
- Unbounded SOQL queries (missing LIMIT or WHERE clause)
- Excessive SOQL/DML that could hit 100/150 limits

**Security Issues (Critical):**
- SOQL injection (string concatenation instead of bind variables)
- Missing CRUD/FLS checks (no `WITH SECURITY_ENFORCED` or manual checks)
- `without sharing` used without justification
- Hardcoded IDs or credentials
- Sensitive data exposed in debug logs

**Bulkification (High):**
- Methods that only handle single records
- Triggers not bulkified for 200+ records
- Inefficient collection usage (lists where maps would be better)

**LWC Issues (High):**
- Using deprecated `if:true`/`if:false` instead of `lwc:if`
- Missing error handling on Apex calls
- Direct DOM manipulation instead of reactive properties
- Missing loading states
- Not cloning @wire results before modifying

**Code Quality (Medium):**
- Missing test coverage for key scenarios
- Hardcoded strings that should be Custom Labels or Custom Metadata
- Overly complex methods that should be broken down
- Missing null checks on collections or query results

For each issue found:
1. State the severity (Critical / High / Medium)
2. Explain the problem in plain language
3. Show the specific line(s)
4. Provide the fix
