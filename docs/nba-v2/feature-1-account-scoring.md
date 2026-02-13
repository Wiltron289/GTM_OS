# Feature 1: Account Scoring Data Layer

**Status**: Metadata complete, pending deploy
**Branch**: `feature/account-scoring-data-layer`
**Last Updated**: 2026-02-13

---

## Architecture Decisions

### Relationship: Lookup(Account), not Master-Detail

**Decision**: Lookup with `deleteConstraint=Restrict` and `required=true`.

| Factor | Lookup (chosen) | Master-Detail |
|---|---|---|
| Account merge behavior | Child reparented (safe) | Child cascade-deleted (data loss) |
| Pipeline bulk operations | More forgiving | Requires parent in same transaction |
| Orphan prevention | Restrict-on-delete blocks Account deletion | Cascade-delete removes child |
| Sharing model | Independent OWD | Inherits from parent |
| Rollup summary fields | Not available | Available (but only aggregates) |

**Why Restrict delete?** Prevents Account deletion while a scoring record exists. Since scoring data is pipeline-managed and expensive to regenerate, losing records silently on Account delete is unacceptable. If an Account must be deleted, remove the scoring record first (or let the pipeline handle cleanup).

### 1:1 Enforcement: Entity_ID__c Uniqueness

**Primary mechanism**: `Entity_ID__c` is External ID + Unique, mirroring `Account.Entity_ID__c`. Since each Account has exactly one Entity_ID and Entity_ID__c on scoring is unique, one-to-one is guaranteed at the business key level.

**Defense-in-depth**: Validation rule `Entity_ID_Matches_Account` ensures the Entity_ID on the scoring record matches `Account__r.Entity_ID__c`. This catches API misuse where someone sets the correct Entity_ID but points `Account__c` to the wrong Account.

### Account Surfacing: Percent Fields (not Formula)

**Platform constraint**: Salesforce formula fields can only traverse UP to parent records, never DOWN to child records. Since Account_Scoring__c is a child of Account, formula fields on Account cannot reference scoring values.

**Solution**: Percent fields directly on Account, synced via:
- **Option A (recommended)**: Record-Triggered Flow on Account_Scoring__c (real-time sync)
- **Option B**: Pipeline updates both Account_Scoring__c and Account in the same daily job

These fields are formula-friendly for Opportunities: `Opportunity.Account.Account_Prob_Payroll_Conversion__c` works natively.

### Field Design for Apex Consumption

- **Percent(5,2)**: `record.Prob_Payroll_Conversion__c` returns a `Decimal` in the 0-100 range. No runtime conversion needed for comparisons, sorting, or bucketing in the Action Selection Engine.
- **LongTextArea(32768)**: Accommodates JSON-structured driver data for explainability parsing in LWC/Apex.
- **Entity_ID__c indexed as External ID**: Automatic custom index for fast SOQL lookups.

---

## SFDX Metadata Structure

```
force-app/main/default/
├── objects/
│   ├── Account/
│   │   └── fields/
│   │       ├── Account_Prob_Payroll_Conversion__c.field-meta.xml  (Percent 5,2)
│   │       └── Account_Prob_Tier_Upgrade__c.field-meta.xml        (Percent 5,2)
│   └── Account_Scoring__c/
│       ├── Account_Scoring__c.object-meta.xml                     (AutoNumber AS-{000000})
│       ├── fields/
│       │   ├── Account__c.field-meta.xml                          (Lookup, Required, Restrict)
│       │   ├── Entity_ID__c.field-meta.xml                        (Text 36, ExtID, Unique)
│       │   ├── Prob_Payroll_Conversion__c.field-meta.xml          (Percent 5,2)
│       │   ├── Prob_Tier_Upgrade__c.field-meta.xml                (Percent 5,2)
│       │   ├── Payroll_Top_Drivers__c.field-meta.xml              (LongTextArea 32768)
│       │   └── Tier_Upgrade_Top_Drivers__c.field-meta.xml         (LongTextArea 32768)
│       └── validationRules/
│           ├── Entity_ID_Matches_Account.validationRule-meta.xml
│           ├── Prob_Payroll_In_Range.validationRule-meta.xml
│           └── Prob_Tier_Upgrade_In_Range.validationRule-meta.xml
├── permissionsets/
│   ├── NBA_Account_Scoring_Admin.permissionset-meta.xml           (CRUD + FLS + Tab)
│   └── NBA_Account_Scoring_Read.permissionset-meta.xml            (Read + FLS + Tab)
└── tabs/
    └── Account_Scoring__c.tab-meta.xml
```

---

## Field Reference

### Account_Scoring__c Fields

| API Name | Type | Details | Required | Description |
|---|---|---|---|---|
| `Name` | AutoNumber | `AS-{000000}` | Auto | System record name |
| `Account__c` | Lookup(Account) | Restrict delete | Yes | Parent Account |
| `Entity_ID__c` | Text(36) | External ID, Unique, Case-insensitive | Yes | Pipeline upsert key, mirrors Account.Entity_ID__c |
| `Prob_Payroll_Conversion__c` | Percent(5,2) | Range: 0-100 (validated) | No | ML probability of payroll conversion |
| `Prob_Tier_Upgrade__c` | Percent(5,2) | Range: 0-100 (validated) | No | ML probability of tier upgrade |
| `Payroll_Top_Drivers__c` | LongTextArea(32768) | - | No | Top drivers for payroll prediction (explainability) |
| `Tier_Upgrade_Top_Drivers__c` | LongTextArea(32768) | - | No | Top drivers for tier upgrade prediction (explainability) |

### Account Surfacing Fields

| API Name | Type | Details | Description |
|---|---|---|---|
| `Account_Prob_Payroll_Conversion__c` | Percent(5,2) | Synced from scoring | Payroll conversion score surfaced for cross-object access |
| `Account_Prob_Tier_Upgrade__c` | Percent(5,2) | Synced from scoring | Tier upgrade score surfaced for cross-object access |

### Validation Rules

| Rule Name | Active | Error Condition | Purpose |
|---|---|---|---|
| `Entity_ID_Matches_Account` | Yes | Entity_ID__c != Account__r.Entity_ID__c (when Account has Entity_ID) | Defense-in-depth: prevents mismatched scoring-to-account mapping |
| `Prob_Payroll_In_Range` | Yes | Value populated AND (< 0 OR > 100) | Ensures percent is within valid range |
| `Prob_Tier_Upgrade_In_Range` | Yes | Value populated AND (< 0 OR > 100) | Ensures percent is within valid range |

---

## Permission Sets

### NBA_Account_Scoring_Admin

**Assign to**: Pipeline integration user, system administrators, NBA V2 admins

| Permission | Setting |
|---|---|
| Account_Scoring__c CRUD | Create, Read, Edit, Delete |
| Account_Scoring__c View/Modify All | Yes / Yes |
| All Account_Scoring__c fields | Read + Edit |
| Account.Entity_ID__c | Read only |
| Account surfacing fields | Read + Edit |
| Account_Scoring__c Tab | Visible |

### NBA_Account_Scoring_Read

**Assign to**: Account Executives, general users who need scoring visibility

| Permission | Setting |
|---|---|
| Account_Scoring__c CRUD | Read only |
| Account_Scoring__c View All | Yes |
| All Account_Scoring__c fields | Read only |
| Account.Entity_ID__c | Read only |
| Account surfacing fields | Read only |
| Account_Scoring__c Tab | Visible |

---

## Data Contract (Pipeline <> Salesforce)

### Source-to-Target Mapping

| Source Field | Target Field | Transform | Notes |
|---|---|---|---|
| `company_uuid` | `Entity_ID__c` | None (direct map) | Upsert key |
| `company_uuid` | `Account__c` | Resolve: find Account where `Entity_ID__c` = `company_uuid`, set to Account.Id | Required lookup |
| `prob_payroll_conversion` | `Prob_Payroll_Conversion__c` | `value * 100`, round to 2 decimals | 0.7342 -> 73.42 |
| `prob_tier_upgrade` | `Prob_Tier_Upgrade__c` | `value * 100`, round to 2 decimals | 0.7342 -> 73.42 |
| `payroll_top_drivers` | `Payroll_Top_Drivers__c` | None (direct map) | Max 32768 chars |
| `tier_upgrade_top_drivers` | `Tier_Upgrade_Top_Drivers__c` | None (direct map) | Max 32768 chars |

### Upsert Strategy

- **API endpoint**: `POST /services/data/v65.0/composite/sobjects/Account_Scoring__c/Entity_ID__c`
- **Method**: Bulk API 2.0 upsert or Composite API upsert
- **Upsert key**: `Entity_ID__c`
- **Behavior**: Insert if missing, update if present
- **Batch size**: Up to 10,000 records per batch (Bulk API)

### Required Transforms

```
# Percent conversion (pipeline-side)
sf_prob_payroll = round(source_prob_payroll * 100, 2)
sf_prob_tier    = round(source_prob_tier_upgrade * 100, 2)

# Account resolution (pipeline-side)
sf_account_id = lookup_account_by_entity_id(company_uuid)
if sf_account_id is None:
    skip_row()  # Do not create orphan records
```

### Relationship Population

1. Pipeline queries Account: `SELECT Id FROM Account WHERE Entity_ID__c = '{company_uuid}'`
2. If match found: set `Account__c` = Account.Id
3. If no match: **skip the row entirely** (no orphan scoring records)
4. Pipeline should pre-resolve all Account IDs in a batch query before upserting

### Data Quality & Monitoring

**Daily checks (required):**

| Check | Alert Threshold | Action |
|---|---|---|
| % rows rejected (missing Account) | > 5% | Investigate Account data gaps |
| % rows with out-of-range percents | > 0% | Fix model output or transform |
| Record count reconciliation | Source rows != upserted count | Investigate rejections |
| Duplicate Entity_ID__c errors | Any occurrence | Should be impossible; investigate |

**Optional logging fields (future):**
- `pipeline_run_id` - trace back to specific pipeline execution
- `load_timestamp` - when the record was last loaded
- `model_version` - which model version produced the scores

---

## Performance Notes

### Indexed Fields

| Field | Index Type | Notes |
|---|---|---|
| `Entity_ID__c` | Custom index (External ID) | Automatic. O(1) lookup for `WHERE Entity_ID__c = :uuid` |
| `Account__c` | Custom index (Lookup) | Automatic. Efficient for `WHERE Account__c IN :ids` |
| `Name` (AutoNumber) | Standard index | Automatic. Rarely queried directly |

### Expected Engine Query Patterns

```sql
-- Single account scoring lookup (Action Creation Engine)
SELECT Prob_Payroll_Conversion__c, Prob_Tier_Upgrade__c,
       Payroll_Top_Drivers__c, Tier_Upgrade_Top_Drivers__c
FROM Account_Scoring__c
WHERE Account__c = :accountId

-- Bulk scoring fetch (Impact weighting across opportunity set)
SELECT Account__c, Prob_Payroll_Conversion__c, Prob_Tier_Upgrade__c
FROM Account_Scoring__c
WHERE Account__c IN :accountIds

-- Pipeline upsert pre-check (verify existing records)
SELECT Id, Entity_ID__c
FROM Account_Scoring__c
WHERE Entity_ID__c IN :entityIds
```

All patterns hit indexed fields. No full table scans expected. For the bulk fetch pattern, expect selectivity well within Salesforce query optimizer thresholds even at scale (100k+ scoring records).

### Governor Limit Considerations

- Object has no triggers, flows, or processes - DML operations are lightweight
- Bulk API upserts bypass most governor limits (runs in async context)
- For Apex engine queries: use `WHERE Account__c IN :accountIds` with collections to minimize SOQL calls

---

## Deploy Steps

```bash
# 1. Deploy all Feature 1 metadata to vscodeOrg
sf project deploy start --target-org vscodeOrg

# 2. Assign admin permission set to yourself
sf org assign permset --name NBA_Account_Scoring_Admin --target-org vscodeOrg

# 3. Assign read permission set to AE users (or via permission set group)
sf org assign permset --name NBA_Account_Scoring_Read --target-org vscodeOrg

# 4. Verify in org
sf org open --target-org vscodeOrg
# Navigate to Setup > Object Manager > Account Scoring to confirm
```

---

## Account Surfacing Sync (Post-Deploy)

The Account fields (`Account_Prob_Payroll_Conversion__c`, `Account_Prob_Tier_Upgrade__c`) require a sync mechanism.

### Option A: Record-Triggered Flow (Recommended)

Build in Flow Builder:
1. **Object**: Account_Scoring__c
2. **Trigger**: After Insert, After Update
3. **Entry Conditions**: None (run for every scoring record change)
4. **Action**: Update Records > Account__r
   - `Account_Prob_Payroll_Conversion__c` = `{!$Record.Prob_Payroll_Conversion__c}`
   - `Account_Prob_Tier_Upgrade__c` = `{!$Record.Prob_Tier_Upgrade__c}`
5. Retrieve to source: `sf project retrieve start -m Flow:Sync_Account_Scoring_to_Account`

### Option B: Pipeline-Side Update

Pipeline updates both objects in the daily job:
1. Upsert `Account_Scoring__c` records (existing behavior)
2. Update `Account` records with scoring values (additional step)
   - `UPDATE Account SET Account_Prob_Payroll_Conversion__c = :prob_payroll, Account_Prob_Tier_Upgrade__c = :prob_tier WHERE Entity_ID__c = :company_uuid`
