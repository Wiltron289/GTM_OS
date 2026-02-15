# Troubleshooting Log

Resolved issues encountered during NBA V2 development. Search this file when debugging similar problems.

---

## Salesforce Metadata & Deploy

### Permission Set FLS on Required Fields (2026-02-13)
- **Problem**: Permission sets failed to deploy with "You cannot deploy to a required field" error
- **Root Cause**: Salesforce does not allow field-level security (FLS) to be set on required fields (`required=true`) or required lookup fields. These are automatically visible to users with object access.
- **Fix**: Remove `<fieldPermissions>` entries for required fields (e.g., `Entity_ID__c`, `Account__c`) from permission set metadata
- **Prevention**: When creating permission sets, never include FLS entries for fields marked `required=true` in their field definition

### LWC HTML Ternary Operators (2026-02-13)
- **Problem**: `nbaDemoSnoozeDropdown` deploy failed with `LWC1058: Invalid HTML syntax: unexpected-character-in-attribute-name`
- **Root Cause**: LWC templates do NOT support JavaScript ternary operators (`? :`) in HTML attribute values. The expression `class={option.isCustom ? 'a' : 'b'}` is invalid.
- **Fix**: Pre-compute the CSS class string in JavaScript and pass it as a property (e.g., `className: 'option-label custom'`)
- **Prevention**: Never use ternary operators in LWC HTML template attributes. Always use computed getters or pre-computed properties.

---

## Apex Test Failures

### NbaDemoControllerTest "List has no rows" (2026-02-13)
- **Problem**: All test methods fail with `System.QueryException: List has no rows for assignment to SObject` when querying `SELECT Id FROM Opportunity WHERE Name = 'Test NBA Demo Opp'`
- **Root Cause**: UAT org has triggers/flows that rename Opportunities on insert. The query-by-Name pattern breaks.
- **Fix**: Changed all 12 test queries from `WHERE Name = 'Test NBA Demo Opp'` to `WHERE Account.Name = 'Test Demo Account' AND StageName = 'Prospecting'`. Also relaxed the assertion on `opportunityName` to `assertNotEquals(null, ...)`.
- **Prevention**: In this org, never query test Opportunities by Name. Use Account.Name + StageName or store the Id in a class-level variable.

### ActivityData sort() ListException (2026-02-13)
- **Problem**: `System.ListException: One or more of the items in this list is not Comparable` at `NbaDemoController.buildSidebar: line 582`
- **Root Cause**: `ActivityData` inner class called `sort()` but did not implement `Comparable`
- **Fix**: Added `implements Comparable` and `compareTo()` method to `ActivityData` (descending by `activityDate`, null-safe)
- **Prevention**: Any inner class used in a `List.sort()` call must implement `Comparable` with a `compareTo(Object)` method

---

## LWC Data Binding Bugs

### Payroll Tab JS Property Name Mismatches (2026-02-13)
- **Problem**: Multiple fields on the Payroll tab showing "---" even when data exists
- **Root Cause**: JS getter property names didn't match Apex `@AuraEnabled` property names: `inceptionSwitcher` vs `inceptionOrSwitcher`, `currentNextStep` (nonexistent) vs `nextStepLabel`, `nextStep` vs `nextStepLabel`
- **Fix**: Corrected all JS getters to match exact Apex property names
- **Prevention**: Always verify JS property access matches the `@AuraEnabled` property name in the Apex wrapper class exactly

### Contacts Tab Empty (2026-02-13)
- **Problem**: Contacts tab showed "No contacts associated with this opportunity" despite OCR and Account contacts existing
- **Root Cause**: Two bugs: (1) `nbaDemoContactsTab.js` accessed `this.contactsData?.contacts` but `contactsData` was already the contacts array (not a wrapper), so `.contacts` returned `undefined`. (2) Only OpportunityContactRole was queried - Account had 19 contacts but only 1 OCR.
- **Fix**: (1) Changed getter to `Array.isArray(this.contactsData) ? this.contactsData : []`. (2) Expanded `buildContacts` to also query `Contact WHERE AccountId = :accountId AND Id NOT IN :seenContactIds`
- **Prevention**: When passing data from parent to child, verify the shape of the data at each level. When `@wire` returns an array, don't try to access properties on it.

### Wire Property Name Mismatch (2026-02-13)
- **Problem**: `Cannot read properties of undefined (reading 'accountName')` in `nbaDemoHeader` at runtime
- **Root Cause**: `nbaDemoWorkspace.js` wire handler read `data.headerData`, `data.accountData`, etc. but the Apex `PageDataWrapper` uses `header`, `account`, `payrollStatus`, etc. All child components received `undefined`.
- **Fix**: Changed all property mappings in the wire handler to match Apex names (e.g., `data.header` not `data.headerData`)
- **Prevention**: Always verify `@AuraEnabled` property names in the Apex wrapper match the JS wire handler property access

---

## Mogli SMS Integration

### Mogli SMS Records Created But Not Sent (2026-02-14)
- **Problem**: SMS records were being created in Salesforce but never actually delivered via Telnyx
- **Root Cause**: Mogli's managed package triggers only process SMS records with `Mogli_SMS__Status__c = 'Queued'`. Without this status, the record exists but Mogli ignores it.
- **Fix**: Added `sms.Mogli_SMS__Status__c = 'Queued';` to the `sendSms()` method before insert
- **Prevention**: When creating `Mogli_SMS__SMS__c` records programmatically, always set `Status__c = 'Queued'` for outbound messages. The status field is the trigger for Mogli's delivery automation.

### Mogli Auto-Populates Mogli_Number from Phone (2026-02-14)
- **Problem**: Test `testSendSms_NoMogliNumber_ThrowsError` failed -- even after setting `Mogli_SMS__Mogli_Number__c = null`, the contact still had a Mogli number
- **Root Cause**: Org has a Mogli trigger that auto-populates `Mogli_SMS__Mogli_Number__c` from the Contact's `Phone` field
- **Fix**: Test now also clears `Phone = null` and `MobilePhone = null` before updating the contact
- **Prevention**: When writing tests that need contacts without Mogli numbers, clear `Phone` and `MobilePhone` in addition to `Mogli_SMS__Mogli_Number__c`

### Non-Namespaced Field on Managed Package Object (2026-02-14)
- **Problem**: Deploy failed with `Variable does not exist: Mogli_SMS__Account__c` on `Mogli_SMS__SMS__c`
- **Root Cause**: The Account lookup field on `Mogli_SMS__SMS__c` was created manually (not by the managed package), so it uses the non-namespaced API name `Account__c` instead of `Mogli_SMS__Account__c`
- **Fix**: Changed to `sms.Account__c = con.AccountId;`
- **Prevention**: Always verify field API names via MCP Tooling API query before referencing managed package object fields -- some fields may have been added manually and won't have the namespace prefix

### Mogli SMS Direction Value 'Outbound' vs 'Outgoing' (2026-02-14)
- **Problem**: SMS records created programmatically were stuck at `'Queued'` status and never delivered via Telnyx
- **Root Cause**: Our code set `Mogli_SMS__Direction__c = 'Outbound'`, but Mogli's managed package triggers only process records with `Direction = 'Outgoing'`. Org data confirmed: 125,907 successfully sent messages all use `'Outgoing'`, while our programmatic record had `'Outbound'` and was stuck.
- **Fix**: Changed `sendSms()` to set `Direction__c = 'Outgoing'`
- **Prevention**: Always use `'Outgoing'` (not `'Outbound'`) for outbound Mogli SMS records. When in doubt, query existing successful records to verify the correct picklist values.
