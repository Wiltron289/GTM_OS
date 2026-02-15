Create an Apex Invocable Action for use in Salesforce Flows.

Ask me these questions before generating anything:
1. What should this action do? (describe the functionality)
2. What inputs does it need from the Flow? (e.g., Record IDs, text values, numbers)
3. What outputs should it return to the Flow? (e.g., success/failure, processed records, messages)
4. What object(s) does it work with?

Then generate:

**The Invocable class** — Following these rules:
- Use `with sharing` by default
- Use `@InvocableMethod` with clear `label` and `description` (these appear in Flow Builder)
- Create inner `Request` class with `@InvocableVariable` for each input
- Create inner `Response` class with `@InvocableVariable` for each output
- Method must accept `List<Request>` and return `List<Response>` (even for single invocations)
- Bulkify: process all requests in the list, not just the first one
- Include error handling — catch exceptions and return error info in the Response
- No SOQL or DML inside loops
- Use bind variables in SOQL
- Use `WITH SECURITY_ENFORCED` in SOQL queries

Example structure:
```apex
public with sharing class MyFlowAction {
    @InvocableMethod(label='My Action Label' description='What this does for Flow builders')
    public static List<Response> execute(List<Request> requests) {
        List<Response> responses = new List<Response>();
        // Collect all IDs first (bulkify)
        Set<Id> recordIds = new Set<Id>();
        for (Request req : requests) {
            recordIds.add(req.recordId);
        }
        // Single query outside loop
        Map<Id, Account> recordMap = new Map<Id, Account>(
            [SELECT Id, Name FROM Account WHERE Id IN :recordIds WITH SECURITY_ENFORCED]
        );
        // Process each request
        for (Request req : requests) {
            Response res = new Response();
            try {
                // Business logic here
                res.isSuccess = true;
            } catch (Exception e) {
                res.isSuccess = false;
                res.errorMessage = e.getMessage();
            }
            responses.add(res);
        }
        return responses;
    }

    public class Request {
        @InvocableVariable(label='Record ID' description='The record to process' required=true)
        public Id recordId;
    }

    public class Response {
        @InvocableVariable(label='Success' description='Whether the action succeeded')
        public Boolean isSuccess;
        @InvocableVariable(label='Error Message' description='Error details if failed')
        public String errorMessage;
    }
}
```

**The test class** — Following these rules:
- Name it `<ClassName>Test`
- Use `@isTest` annotation
- Use `@TestSetup` for test data
- Test positive case (valid input → expected output)
- Test negative case (invalid input → error response, not exception)
- Test bulk case (200+ requests in a single call)
- Test that the action works inside a Flow context (if applicable)
- Use `System.assertEquals` with descriptive messages

Place class files in: `force-app/main/default/classes/`

After generating, remind me to:
1. Deploy: `sf project deploy start --source-dir force-app/main/default/classes/`
2. Run tests: `sf apex run test --class-names <TestClassName> --synchronous --result-format human`
3. In Flow Builder: look for the action under "Action" element → search by the label you defined
