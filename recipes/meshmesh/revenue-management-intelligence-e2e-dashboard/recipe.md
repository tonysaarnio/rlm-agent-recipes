# Revenue Management Intelligence (Revenue Cloud) - End-to-End Dashboard Setup

## Overview
Sets up **Revenue Management Intelligence (RMI)** in a Revenue Cloud (Revenue Management) demo org from scratch. The end state is working Tableau Next dashboards for **DRO (order fulfillment) Analytics**, **Billing Analytics**, and **Subscription Analytics**, plus dedicated navigation tabs.

The recipe follows the Salesforce guided setup (Setup > Revenue Management Intelligence Setup) in its required order:
1. Data 360 connection
2. Connector access
3. Data kit bundles
4. Stream refresh
5. App installs, one at a time

It adds pre-flight checks, a data-readiness gate (with an optional sample-data generator that runs only with user consent), install monitoring, and recovery steps for every failure observed when this was first built on a Release 264 (Winter '27) org.

**Audience:** SEs and demo builders. Optimize for a reliable, demo-ready result with minimal user decisions.

---

## KNOWN ISSUE - tell the user before starting
> **Pricing Analytics has a product bug and will be fixed by product in the next release.** Do NOT install Pricing Analytics in this run. The other three apps (DRO, Billing, Subscription) install and work normally.
>
> **Technical detail (for support cases):**
> - The Price Analytics app template `sfdc_internal__ngp` **v1.1** defines an `OrderCostBook` custom-SQL semantic view.
> - That view joins on `ssot__CostBookEntry__dlm.ssot__CostBookId__c` but omits that field from its `referenceIntegritySemanticDataObjects`. The sibling `DefaultCostBook` view includes it.
> - The install always fails at task `SemanticModelUpsert` with: `Failed to create Semantic Model [PriceAnalyticsSemanticModel] ... Field ssot__CostBookId__c in Table ssot__CostBookEntry__dlm is not exist in reference data objects`.
> - No org-side mapping change fixes it.
>
> **Check whether the fix has shipped:**
> ```bash
> sf api request rest "/services/data/v65.0/app-framework/templates/sfdc_internal__ngp" -o {{ORG_ALIAS}} | python3 -c "import json,sys;print(json.load(sys.stdin)['releaseInfo']['templateVersion'])"
> ```
> Install Pricing Analytics only when the version is greater than `1.1`. Follow Step 9.

---

## Prerequisites

### Required Connections
- **Salesforce org (System Administrator)**: a Revenue Cloud / Revenue Management demo org, Release 264+ (API v68.0), with Data Cloud (Data 360) provisioned. If more than one org is connected, ASK the user which org to use. Never assume.

### Licenses / features (verified in Step 1)
- Data Cloud (`GenieDataPlatformStarterPsl`)
- Tableau Next Creator (`TableauEinsteinUserPsl`) and Consumer (`TableauBusinessUserPsl`)
- CRM Analytics Plus (`EinsteinAnalyticsPlusPsl`)
- Revenue Cloud User (`RevenueLifecycleManagementUserPsl`)
- Billing Analytics additionally requires the **Revenue Cloud Advanced** and **Revenue Cloud Billing** licenses (per Salesforce Help)
- Revenue Cloud catalog loaded. The default sample-data products are from the **QuantumBit (QB)** demo dataset, for example from a Revenue Cloud Foundations build.
- For sample data: several accounts, each with a billing or shipping address and at least one contact. Order activation needs a billing address and a Bill To contact. Accounts in other currencies need price book entries in that currency (QB data has USD, GBP, EUR, AUD, CAD, CHF and JPY).

### Tools and references
- Authenticated `sf` CLI (pre-authenticated through the connection; never use credential placeholders for Salesforce), Python 3 (stdlib only)
- Browser automation. Several steps have no API and must be done in the Setup UI. Read the `salesforce-browser` skill before any browser navigation, then use `openSalesforceOrg`.
- Supporting files in this recipe:
  - `config-defaults.json`: all names, bundles, app order, permissions and sample-data defaults
  - `sample-data-generator.md` (Appendix A): tested, generalized quote > order > activate > invoice generator
  - `metadata/`: Lightning pages, tabs and profile tab visibility for the dashboard tabs
  - `revenue_management_intelligence.pdf`: Salesforce Help for RMI (setup steps, bundles, install notes, dashboards)
- Recommended references to attach alongside: **Call Revenue Cloud Business APIs** (transaction API contracts) and **Revenue Cloud Foundations (R264)** (permissions background)

---

## Execution Rules (apply to every step)
1. **Strict sequence.** Finish and verify each step before starting the next. Never run two bundle deployments or two app installs at the same time.
2. **Wait gates.** Data bundle deploys, stream refreshes, Data Cloud sync (about 10-15 minutes behind the CRM) and app installs (2-10 minutes each) are asynchronous. Poll; do not assume.
3. **Stop and report each phase** to the user in plain business language. Do not show CLI commands, file paths or internal tool names to the user.
4. **Session expiry.** If any call returns `INVALID_SESSION_ID` / "Session expired", call `RequestConnectionUpdate`, then re-check the org alias (`GetTaskConnections`; it can change after a refresh) and resume from the last verified step. The browser session may also expire: re-run `openSalesforceOrg`.
5. **Placeholders.**
   - `{{ORG_ALIAS}}` is the connected org alias (from `GetTaskConnections`).
   - `{{MYDOMAIN}}` is the subdomain of `instanceUrl` from `sf org display -o {{ORG_ALIAS}} --json`. For example, `https://acme-dev.my.salesforce.com` gives `acme-dev`.
   - `{{LIGHTNING}}` = `https://{{MYDOMAIN}}.lightning.force.com`
   - `{{SETUP}}` = `https://{{MYDOMAIN}}.my.salesforce-setup.com`

   Open the first page with `openSalesforceOrg` (path parameter), then navigate with full URLs.
6. **Do not put literal double-brace placeholders inside shell commands.** Substitute real values first. Build `config.json` with Python, as in Appendix A.

---

## Steps

### Step 1: Run pre-flight checks (read-only) and report the current state
```bash
ORG={{ORG_ALIAS}}
sf api request rest "/services/data/" -o $ORG | python3 -c "import json,sys;print('max API', json.load(sys.stdin)[-1]['version'])"   # expect 68.0+

# Licenses
sf data query -o $ORG -q "SELECT MasterLabel, DeveloperName, TotalLicenses, UsedLicenses FROM PermissionSetLicense WHERE DeveloperName IN ('GenieDataPlatformStarterPsl','TableauEinsteinUserPsl','TableauBusinessUserPsl','EinsteinAnalyticsPlusPsl','RevenueLifecycleManagementUserPsl')"

# Data Cloud provisioned + data space + Salesforce CRM connection
sf api request rest "/services/data/v65.0/ssot/data-spaces" -o $ORG
sf api request rest "/services/data/v65.0/ssot/connections?connectorType=SalesforceDotCom" -o $ORG     # expect connectionStatus = Connected

# Existing RMI data streams (Revenue objects)
sf data query -o $ORG -q "SELECT Name, DataStreamStatus FROM DataStream WHERE Name IN ('Asset_Home','Order_Home','OrderItem_Home','FulfillmentPlan_Home','Invoice_Home','BillingSchedule_Home','CostBookEntry_Home')"

# Existing analytics assets (detects re-runs / leftovers)
sf api request rest "/services/data/v65.0/tableau/workspaces" -o $ORG
sf api request rest "/services/data/v65.0/ssot/semantic/models" -o $ORG

# Admin permissions
sf data query -o $ORG -q "SELECT PermissionSet.Name FROM PermissionSetAssignment WHERE AssigneeId = '<ADMIN_USER_ID>' AND (PermissionSet.Name IN ('AnalyticsStoreUser','PulseRuntimeUser','CDPAdmin','GenieAdmin') OR PermissionSet.Name LIKE 'Tableau%')"
```
In the browser, open `{{SETUP}}/lightning/setup/RevenueLifecycleIntelligence/home` and `{{SETUP}}/lightning/setup/AppHub/home`. Record each app's state on the RMI page ("No Apps Installed", or Name/Version/Status) and list every app in App Hub.

**Decision rules**
- A required license is missing: STOP. Tell the user which license is needed (contact their account executive).
- Data Cloud is not provisioned or there's no `default` data space: STOP. Data Cloud must be set up first (Data Cloud Setup > Get Started).
- Any **failed or leftover** RMI app is in App Hub (any Pricing Analytics app included): delete it before installing (Troubleshooting > "Allowed apps exceeded").
- An app is already installed successfully: skip it and report it.

Report a short summary table to the user and continue to Step 1b.

### Step 1b: Pre-flight - ask the user to refresh all decision tables and rebuild the product search index
Quoting, pricing and order activation (needed for the sample data and for accurate dashboards) depend on current decision tables and a built Product Catalog search index. Check their state first (read-only):
```bash
# Decision tables: count of active tables, and any that never synced or did not complete
sf data query --use-tooling-api -o {{ORG_ALIAS}} -q "SELECT COUNT() FROM DecisionTable WHERE Status = 'Active'"
sf data query --use-tooling-api -o {{ORG_ALIAS}} -q "SELECT DeveloperName, LastSyncDate, RefreshStatus FROM DecisionTable WHERE Status = 'Active' ORDER BY LastSyncDate NULLS FIRST LIMIT 10"

# Product Catalog search index: expect a snapshot with activationStatus = ACTIVE
sf api request rest "/services/data/v68.0/connect/pcm/index/snapshots" -o {{ORG_ALIAS}} | python3 -c "import json,sys;d=json.load(sys.stdin);print([(s.get('activationStatus'),s.get('activationDate')) for s in d.get('snapshots',[])])"
```
**ALWAYS ask the user (AskUserQuestion) before the build starts**, showing what was found. For example: "Before we start, please make sure all decision tables have been refreshed and the product search index has been built. I found N active decision tables (last refreshed <oldest LastSyncDate>, M not Completed) and the search index was last activated <date | never>. Have you refreshed all decision tables and run the index since the last catalog or pricing change?" Options:
- **Already done - continue**
- **I'll do it now** - give the UI paths, then wait for the user to confirm:
  - Decision tables: Setup > Quick Find "Decision Tables" > open each active table > **Refresh** (or the org's bulk-refresh flow, e.g. `RLM_Refresh_Decision_Tables_Bulk`, if present)
  - Search index: Product Catalog Management (Revenue Cloud) > **Build Index** / Build Catalog Index > Full build
- **Do it for me** - only with explicit consent:
  ```bash
  # Refresh every active decision table (full refresh; async - queues work)
  sf data query --use-tooling-api -o {{ORG_ALIAS}} -q "SELECT DeveloperName FROM DecisionTable WHERE Status = 'Active'" --json \
   | python3 -c "import json,sys;[print(r['DeveloperName']) for r in json.load(sys.stdin)['result']['records']]" \
   | while read DT; do
       echo "{\"inputs\":[{\"DecisionTableApiName\":\"$DT\",\"isDecisionTableIncremental\":false}]}" > /tmp/dt.json
       sf api request rest "/services/data/v68.0/actions/standard/refreshDecisionTable" --method POST --body @/tmp/dt.json -o {{ORG_ALIAS}} | python3 -c "import json,sys;d=json.load(sys.stdin);print('$DT', d[0].get('isSuccess'), d[0].get('errors'))"
     done
  # Rebuild the Product Catalog search index (FULL; async, several minutes)
  echo '{"buildType":"FULL"}' > /tmp/idx.json
  sf api request rest "/services/data/v68.0/connect/pcm/index/deploy" --method POST --body @/tmp/idx.json -o {{ORG_ALIAS}}
  ```
  Verify before continuing: re-run the decision-table query until every active table shows `RefreshStatus = Completed` with a `LastSyncDate` after the refresh started (full-refresh pools: 40 Standard / 60 Advanced per hour - large orgs may take a while), and the snapshots call shows a new `ACTIVE` snapshot.

Do not start Step 2 until the user confirms (or the automated refresh/index verification passes).

### Step 2: Enable Tableau Next and assign admin permission sets
1. Assign the RMI permission sets to the running admin. Errors saying the set is already assigned are fine.
   ```bash
   sf org assign permset -n AnalyticsStoreUser -n PulseRuntimeUser -o {{ORG_ALIAS}}
   ```
2. Browser: open `{{SETUP}}/lightning/setup/EasySetup/home` (Setup > Tableau Next > Tableau Next Setup). If the switch `Enable Tableau Next` is not `[checked]`, click it. Wait until the button "Go to Tableau Next" is enabled.
   - "Install Data 360 Components" must show **Completed**.
   - The optional setup steps (Add Admins, Turn On AI Features, Load Data, Configure Access) are not needed.
3. Verify. Expect `AnalyticsStoreUser`, `PulseRuntimeUser`, and a Tableau admin set such as `TableauUnmeteredAdmin`:
   ```bash
   sf data query -o {{ORG_ALIAS}} -q "SELECT PermissionSet.Name FROM PermissionSetAssignment WHERE Assignee.Username = '<ADMIN_USERNAME>' AND (PermissionSet.Name LIKE '%Tableau%' OR PermissionSet.Name IN ('AnalyticsStoreUser','PulseRuntimeUser'))"
   ```

### Step 3: Verify the Data 360 connection (RMI guided step 1)
The RMI page's step buttons only open Help articles; they do not run anything. This step is satisfied when all of these are true:
- Data Cloud is provisioned
- The Salesforce CRM connection (usually alias `Home`) shows `connectionStatus: Connected` (Step 1 query)
- A data space exists (`default`)

If the CRM connection is missing: Setup > Salesforce CRM > New > Connect to a Salesforce org, then verify it is Active.

### Step 4: Configure access - Data Cloud Salesforce Connector permissions (RMI guided step 2)
1. Find the connector permission set. It's managed, namespace `sfdcInternalInt`, label "Data Cloud Salesforce Connector":
   ```bash
   sf data query -o {{ORG_ALIAS}} -q "SELECT Id, Name FROM PermissionSet WHERE Label = 'Data Cloud Salesforce Connector'"
   ```
2. Turn on the system permissions required for Pricing, DRO and Billing ingestion (field API names are in `config-defaults.json > connector_system_permissions`):
   ```bash
   cat > /tmp/ps_patch.json <<'EOF'
   {"PermissionsCorePricingRunTimeUser":true,"PermissionsQuoteToOrderUser":true,"PermissionsCoreCPQUser":true,"PermissionsDfoAdminUser":true,"PermissionsBillingSetupAccess":true,"PermissionsEditBillingInfo":true,"PermissionsRlmBillingAccess":true,"PermissionsRunDPEDefForNextGenBilling":true,"PermissionsViewAllData":true,"PermissionsViewAllFieldsGlobal":true}
   EOF
   sf api request rest "/services/data/v68.0/sobjects/PermissionSet/<CONNECTOR_PS_ID>" --method PATCH --body @/tmp/ps_patch.json -o {{ORG_ALIAS}}
   ```
   An empty response means success.

   | Help-article label | API field |
   |---|---|
   | Salesforce Pricing: Run time user | `PermissionsCorePricingRunTimeUser` |
   | Create Orders from Quotes | `PermissionsQuoteToOrderUser` |
   | Manage Revenue Cloud | `PermissionsCoreCPQUser` |
   | Grants administrator access to DRO | `PermissionsDfoAdminUser` |
   | Configure Billing Settings | `PermissionsBillingSetupAccess` |
   | Manage Billing | `PermissionsEditBillingInfo` |
   | Manage Billing Access | `PermissionsRlmBillingAccess` |
   | Run DPE Definitions for Billing | `PermissionsRunDPEDefForNextGenBilling` |
   | View All Data | `PermissionsViewAllData` |
   | View All Fields (Global) | `PermissionsViewAllFieldsGlobal` |
3. Re-query those fields on the permission set and confirm all are `true`. View All Data plus View All Fields (Global) cover the object-level Read / View All grants that Help lists per object.

### Step 5: Deploy the RMI data kit - 5 bundles, ONE AT A TIME (RMI guided step 3)
There is no API for standard bundle deployment; use the browser. Bundle order (from `config-defaults.json`): **Asset Bundle > Pricing Bundle > DRO Bundle > Common Billing Bundle > Advanced Billing Bundle**. (Asset + Pricing serve Subscription/Pricing Analytics, DRO serves DRO Analytics, and both Billing bundles serve Billing Analytics.)

For each bundle:
1. Find the Data Cloud app ID:
   ```bash
   sf data query -o {{ORG_ALIAS}} -q "SELECT DurableId FROM AppDefinition WHERE DeveloperName = 'Audience360'"
   ```
   Open `{{LIGHTNING}}/lightning/app/<DATA_CLOUD_APP_ID>/o/DataStream/home`. Do NOT use `/lightning/o/DataStream/new` directly: it opens a raw record form, not the wizard.
2. Click **New**, select the **Salesforce CRM** tile (click its label text; the radio must show `[checked]`), then click **Next**.
3. Keep the default Salesforce org (the home org). Under **Standard Bundles**, select exactly one bundle by clicking its label, for example "Asset Bundle". Then click **Next** through the object and field review screens, keeping the defaults.
4. On the final screen, set **Data Space = default**. It sometimes shows "Select Data Space" and the Deploy button stays disabled until a data space is chosen. Then click **Deploy**.
5. The page shows "Hang tight while your data streams are being deployed." Poll until that text is gone and the bundle's streams exist and are `ACTIVE`:
   ```bash
   sf data query -o {{ORG_ALIAS}} -q "SELECT Name, DataStreamStatus FROM DataStream WHERE CreatedDate = TODAY ORDER BY CreatedDate DESC"
   ```
   New-stream counts are lower than the bundle's object count when some objects already had streams (Account, Pricebook2, Product, Order). Those existing streams are reused, and inactive ones are reactivated.

Reference result on a fresh QB org:

| Bundle | New streams |
|---|---|
| Asset | 4 |
| Pricing | 8 |
| DRO | 5 |
| Common Billing | 9 |
| Advanced Billing | 15 |

That's 41 new streams in total.

### Step 6: Refresh streams until every RMI stream shows Success
Salesforce Help requires every data stream to show Last Run = Success before any app is installed.
```bash
sf api request rest '/services/data/v65.0/ssot/data-streams?limit=200&offset=0' -o {{ORG_ALIAS}} > /tmp/ds.json
python3 - <<'EOF'
import json
rmi=set("""Asset AssetAction AssetActionSource AssetStatePeriod Account ContactPointAddress CostBook CostBookEntry Product2 Order OrderItem ProductSellingModel ProductCategoryProduct Pricebook2 ProductCategory FulfillmentStepSource FulfillmentStepDependency FulfillmentPlan FulfillmentStep SalesTransactionFulfillReq AccountingPeriod Invoice BillingSchedule InvoiceBatchRun InvoiceLine BsgRelationship InvoiceAddressGroup InvoiceLineTax BillingScheduleGroup BillingForecast PaymentTerm Payment BillingTreatmentItem LegalEntity TaxPolicy CreditMemo LegalEntyAccountingPeriod PaymentTermItem TaxTreatment BillingTreatment CreditMemoLine BillingPolicy RevenueTransactionErrorLog CreditMemoLineTax CurrencyType User""".split())
for s in json.load(open('/tmp/ds.json'))['dataStreams']:
    n=s['name'].replace('_Home','')
    if n in rmi and s.get('lastRunStatus')!='SUCCESS': print('PENDING', s['name'], s.get('lastRunStatus'))
EOF
```
- New streams run their first sync automatically within about 10 minutes. Poll every 60s.
- CRM connector streams **cannot** be refreshed through the API (`actions/run` returns "Connector type SalesforceDotCom is not allowed to run in non-interactive mode").
- For any stream still pending after about 10 minutes, typically one that has never run, such as `User_Home`: in the browser, open `{{LIGHTNING}}/lightning/app/<DATA_CLOUD_APP_ID>/r/DataStream/<STREAM_ID>/view`, click **Refresh Now**, choose **Full Refresh**, then click **Refresh Now**. Poll until the stream shows `SUCCESS`.

### Step 7: Data-readiness gate (ask the user before generating any data)
The apps' install validation checks that their Data Cloud objects actually contain rows. With empty Sales Order or Asset objects, an install stalls indefinitely: tasks sit in status `New` after the validation phase. Check the CRM:
```bash
for q in "SELECT COUNT() FROM Order WHERE Status='Activated'" "SELECT COUNT() FROM Asset" "SELECT COUNT() FROM FulfillmentPlan" "SELECT COUNT() FROM Invoice WHERE Status='Posted'"; do
  printf '%-55s ' "$q"; sf data query -o {{ORG_ALIAS}} -q "$q" --json | python3 -c "import json,sys;print(json.load(sys.stdin)['result']['totalSize'])"; done
```
Compare against `config-defaults.json > data_readiness_minimums`: 25 activated orders, 25 assets, 10 fulfillment plans, 5 posted invoices.

- **All minimums met:** continue to the sync check below.
- **Any minimum not met:** STOP and ASK the user (use AskUserQuestion). First run Appendix A `discover` (read-only) so you can name the accounts. For example: "This org has N activated orders, N assets and N posted invoices. The analytics apps need transaction data to install and to show meaningful dashboards. Should I generate sample data? That's 50 transactions in total, spread across these N accounts (<names and currencies>):
  - 30 new quote-to-order sales of subscription and one-time products
  - 10 QuantumBit Complete Solution bundle orders with posted invoices
  - 10 subscription lifecycle changes on existing subscriptions: upsells, downsells (churn) and renewals"
  Offer these options: use the defaults, change the accounts or volumes, or skip. **Default volume is 50 transactions total - do not generate more unless the user explicitly asks.**
  - **Yes:** follow **Appendix A** (`sample-data-generator.md`) in this order:
    1. `discover`, then resolve any `missing` items
    2. `coverage-simple` and `coverage-bundle`, then remove any failing product from config
    3. `simple` bulk, then `bundle` bulk, then `lifecycle`. Size them so the totals are **30 simple + 10 bundle + 10 lifecycle = 50 transactions**. Coverage runs count toward the totals, so with the defaults run `simple 13`, `bundle 6` and `lifecycle 10`. `lifecycle` must run after `simple`, because it amends and renews the term assets those orders create. See Appendix A.
    4. Verify with the Step 7 counts
  - **No:** warn the user that installs may stall and dashboards will be empty. Continue only if they insist.

**Data Cloud sync check (always).** Before any install, wait until Data Cloud matches the CRM. Compare each stream's `totalRecords` (from the data-streams endpoint) with the CRM `COUNT()` for these objects:
- Order, OrderItem, Asset
- FulfillmentPlan, FulfillmentStep, SalesTransactionFulfillReq
- Invoice, InvoiceLine, BillingSchedule

Proceed only when they are equal. Re-check every 2 minutes. A full sync typically lands within 10-20 minutes of the last write.

### Step 8: Install the analytics apps - ONE AT A TIME (RMI guided "Install" sections)
Order: **DRO Analytics > Billing Analytics > Subscription Analytics**. Skip **Pricing Analytics** (Known Issue).

For each app:
1. Browser: open `{{SETUP}}/lightning/setup/RevenueLifecycleIntelligence/home`. In the app's section, which shows "No Apps Installed", click **Install**:
   - "Revenue Cloud Dynamic Revenue Orchestrator Analytics"
   - "Billing Analytics"
   - "Subscription Analytics"
2. In the **Select Data Space** dialog, confirm `default` and click **Save**. The section shows "Installing...".
3. Monitor: open `{{SETUP}}/lightning/setup/AppHub/home` and click the **Monitor** tab. Each row shows: event `Create <app>_<MM_DD_YYYY>`, status, duration, and task counts (completed / warning / failed / new). Re-read every 60-75s.
   - Success: the status becomes **Warning** or **Success** with all tasks complete. Typical times: DRO about 30s (76 tasks), Billing about 2 minutes (211), Subscription about 2 minutes (127).
   - The only warning seen on all three apps is the final `SendEmail`/finish notification step. This is cosmetic.
4. To diagnose any non-success, click the event name to open its task list (paginated, 50 rows per page). Read the page text and find tasks whose status is not `Success`; the message column has the error.
5. Verify the delivered assets:
   ```bash
   sf api request rest "/services/data/v65.0/tableau/workspaces" -o {{ORG_ALIAS}}          # DRO Workspace, Billing Central Analytics, QOCAL Workspace
   sf api request rest "/services/data/v65.0/tableau/dashboards" -o {{ORG_ALIAS}}          # see expected list below
   sf api request rest "/services/data/v65.0/ssot/semantic/models" -o {{ORG_ALIAS}}        # DRO_SDM, BillingCentralSemanticModel, QOCAL Semantic Model
   ```
   The RMI setup page's App Details should show `Status SuccessWithWarningsStatus` (or `Success`).
6. Only then start the next app.

| App | Workspace | Dashboards (API name) | Semantic model |
|---|---|---|---|
| DRO Analytics | DRO Workspace | Order Analysis (`Order_Analysis`), Order Details (`Order_Details`) | DRO_SDM |
| Billing Analytics | Billing Central Analytics | Billing Insights (`BillingInsights`), Aging Invoices (`AgeingInvoices`), Net Account Balance (`AccountSummary`), Billing Forecast Console (`BillingForecastConsole`) | BillingCentralSemanticModel |
| Subscription Analytics | QOCAL Workspace | QOCAL Overview (`QOCAL_Overview`), QOCAL Renewals and Churn (`QOCAL_Renewals_and_Churn`) | QOCAL Semantic Model |

**If an install fails or stays "In Progress" with no change in task counts for more than 15 minutes:**
1. In App Hub > Monitor, open the event's action menu and choose **Cancel Request**, then confirm.
2. In the App Hub > Apps tab, delete every entry for that app. There are often two: `<App> MM-DD-YYYY - App` and `<App> MM-DD-YYYY`. Use the row action menu > Delete > Delete, and check the dialog title names the right app before confirming. Deletion is asynchronous, so wait until the row disappears (30-90s) before deleting the next entry.
3. Confirm the app's workspace is gone (`/tableau/workspaces`).
4. Fix the root cause (see Troubleshooting) and retry from step 1.

### Step 9: Pricing Analytics - deferred until the product fix ships
Tell the user: "Pricing Analytics has a known product bug that will be fixed in the next release; it is skipped for now."

When the template version is greater than 1.1 (see the Known Issue check):
1. Make sure App Hub has no Pricing Analytics entries.
2. Install it like the other apps. It creates the **Pricing Pulse** app and needs the `PulseRuntimeUser` permission set (assigned in Step 2).

Expect about 7 minutes for the install. If it fails, read the `SemanticModelUpsert` task message, delete both app entries, and report the error to the user.

### Step 10: Create dedicated dashboard tabs (Order Analytics in DRO, Subscription Analytics in Revenue Cloud)
Billing already ships its own tab (Billing app > **Billing Central** tab, `standard-BillingCentralDashboard`). DRO and Subscription dashboards are not added to any app automatically, so this step creates Lightning App Page tabs that use the standard **Tableau Next Dashboard** component (`analytics_embedding:dashboard`, property `dashboardId` = dashboard API name).

1. Create an SFDX project and copy in the recipe metadata:
   ```bash
   mkdir -p rmi_tabs/force-app/main/default && cd rmi_tabs
   echo '{"packageDirectories":[{"path":"force-app","default":true}],"sourceApiVersion":"65.0"}' > sfdx-project.json
   mkdir -p force-app/main/default/{flexipages,tabs,profiles,applications}
   # The recipe's metadata files live in the attached reference folder (usually flat: .refs/revenue-management-intelligence-setup/)
   REF=$(find .. ../.refs -maxdepth 3 -name 'RMI_Order_Analytics.flexipage-meta.xml' 2>/dev/null | head -1 | xargs dirname)
   cp "$REF"/RMI_Order_Analytics.flexipage-meta.xml "$REF"/RMI_Subscription_Analytics.flexipage-meta.xml force-app/main/default/flexipages/
   TREF=$(find .. ../.refs -maxdepth 3 -name 'RMI_Order_Analytics.tab-meta.xml' 2>/dev/null | head -1 | xargs dirname)
   cp "$TREF"/RMI_Order_Analytics.tab-meta.xml "$TREF"/RMI_Subscription_Analytics.tab-meta.xml force-app/main/default/tabs/
   PREF=$(find .. ../.refs -maxdepth 3 -name 'Admin.profile-meta.xml' -path '*revenue-management-intelligence*' 2>/dev/null | head -1)
   cp "$PREF" force-app/main/default/profiles/
   ls force-app/main/default/*/     # expect 2 flexipages, 2 tabs, 1 profile
   ```
   - `RMI_Order_Analytics`: an App Page (template `flexipage:defaultAppHomeTemplate`) with one dashboard, `Order_Analysis`, height 1200.
   - `RMI_Subscription_Analytics`: an App Page with a tabset of two tabs: **Overview** (`QOCAL_Overview`) and **Renewals and Churn** (`QOCAL_Renewals_and_Churn`), each height 1200.
2. Deploy the pages first, because the tabs reference them:
   ```bash
   sf project deploy start --source-dir force-app/main/default/flexipages -o {{ORG_ALIAS}} --wait 10
   ```
3. Retrieve the two target apps. **Patch them; never overwrite them with copies from another org**, because the Revenue Cloud app carries org-specific profile overrides.
   ```bash
   sf project retrieve start -m "CustomApplication:standard__IndustriesDfo" -m "CustomApplication:RLM_Revenue_Cloud" -o {{ORG_ALIAS}}
   python3 - <<'EOF'
   p='force-app/main/default/applications/'
   t=open(p+'standard__IndustriesDfo.app-meta.xml').read()
   if 'RMI_Order_Analytics' not in t:
       t=t.replace('<tabs>standard-Order</tabs>','<tabs>standard-Order</tabs>\n    <tabs>RMI_Order_Analytics</tabs>',1)
       t=t.replace('<workspaceConfig>','<workspaceConfig>\n        <mappings>\n            <tab>RMI_Order_Analytics</tab>\n        </mappings>',1)  # DRO is a console app
   open(p+'standard__IndustriesDfo.app-meta.xml','w').write(t)
   t=open(p+'RLM_Revenue_Cloud.app-meta.xml').read()
   if 'RMI_Subscription_Analytics' not in t:
       anchor='<tabs>standard-Asset</tabs>' if '<tabs>standard-Asset</tabs>' in t else '<tabs>standard-Order</tabs>'
       t=t.replace(anchor, anchor+'\n    <tabs>RMI_Subscription_Analytics</tabs>',1)
   open(p+'RLM_Revenue_Cloud.app-meta.xml','w').write(t)
   EOF
   ```
   If `RLM_Revenue_Cloud` does not exist in the org, ask the user which app should hold Subscription Analytics.
4. Validate, then deploy the tabs, the apps and the System Administrator tab visibility (`DefaultOn`):
   ```bash
   sf project deploy start --source-dir force-app/main/default/tabs --source-dir force-app/main/default/applications --source-dir force-app/main/default/profiles -o {{ORG_ALIAS}} --dry-run --wait 10
   sf project deploy start --source-dir force-app/main/default/tabs --source-dir force-app/main/default/applications --source-dir force-app/main/default/profiles -o {{ORG_ALIAS}} --wait 10
   sf project deploy report --use-most-recent -o {{ORG_ALIAS}}     # if the deploy CLI only prints "Pending", confirm Succeeded here
   ```
   The profile file only adds `tabVisibilities`; it does not change other profile settings. For non-admin users, grant tab access through their profile or a permission set.

---

## Verification
1. **RMI setup page:** DRO, Billing and Subscription each show App Details with Status `SuccessWithWarningsStatus` or `Success`. Pricing shows "No Apps Installed" (deferred).
2. **App Hub:** exactly three apps (DRO, Billing, Subscription), with no Failed or Canceled entries.
3. **APIs:** 3 workspaces, 8 dashboards and 3 semantic models, as listed in the Step 8 table.
4. **Browser checks:**
   - `{{LIGHTNING}}/lightning/n/RMI_Order_Analytics` shows the Order Analysis dashboard with KPI tiles (Total Orders, Failed Orders, Orders in Jeopardy).
   - `{{LIGHTNING}}/lightning/n/RMI_Subscription_Analytics` shows Overview and Renewals and Churn sub-tabs with tiles (MRR, Active Subscriptions, New Subscriptions, Booking Revenue, Renewals).
   - `{{LIGHTNING}}/lightning/n/standard-BillingCentralDashboard` shows the Billing dashboards.
   - In the DRO app, **Order Analytics** appears in the navigation bar. In the Revenue Cloud app, **Subscription Analytics** appears in the navigation, often under **More** when the bar is full.
5. **Data:** Data Cloud `totalRecords` equals the CRM counts for Order, Asset, FulfillmentPlan, Invoice and BillingSchedule.

Report to the user a summary table: each app with its status and dashboards, where to open each dashboard, the Pricing known issue, and any data gaps.

**Where users find the dashboards**

| Dashboards | Location |
|---|---|
| Billing | Billing app > Billing Central tab |
| Order Analysis | DRO app > Order Analytics tab |
| Subscription | Revenue Cloud app > Subscription Analytics tab |
| Order Details | Tableau Next app > DRO Workspace (optional: add it to the Order record page with a record filter) |
| All dashboards | Tableau Next app > workspaces |

---

## Troubleshooting
(All of these were encountered during the original build on a 264 org.)

### Issue: Pricing Analytics fails at `SemanticModelUpsert` (CostBookId "not exist in reference data objects")
**Cause:** Product defect in template `sfdc_internal__ngp` v1.1 (see Known Issue).
**Fix:** Do not retry until a newer template version ships. Delete both Pricing entries in App Hub so they don't count against the template limit.

### Issue: App install stays "In Progress" with tasks stuck at status `New` (for example 117 of 352 done)
**Cause:** The validation phase passed, but the execute phase is waiting on Data Cloud row-count readiness (`DataCloudRowCountReadiness`, `MonitorDataCloud`) because the required objects (Sales Order, Sales Order Product, Asset) are empty in Data Cloud.
**Fix:** Cancel the request, delete the app entries, populate transaction data (Step 7 / Appendix A), wait for the Data Cloud sync, then retry.

### Issue: "Allowed apps exceeded" for a template
**Cause:** A leftover failed or canceled app from a previous attempt counts against the template's app limit.
**Fix:** Delete every entry for that app in App Hub. Deletion is asynchronous, so wait for each row to disappear before retrying.

### Issue: A semantic model fails because fields are missing on `ssot__Invoice__dlm` / `ssot__BillingSchedule__dlm` (field reports, Billing on 264)
**Cause:** Required fields are not in the data stream > DMO field mappings. An unmapped `ssot__Id__c` can also block the readiness check.
**Fix:**
1. Read the missing field and DMO from the App Hub task message (set log verbosity to Finest if the message is truncated).
2. Add that field in the data stream's Field Mappings.
3. Let the stream sync, delete the failed app, and retry.

To pre-check, list each billing/DRO DMO's mapped fields with:
```bash
sf api request rest "/services/data/v65.0/ssot/data-model-object-mappings?dataspace=default&dmoDeveloperName=<DMO>" -o {{ORG_ALIAS}}
```
(The original build installed Billing cleanly with the default bundle mappings.)

### Issue: `ssot__BillingScheduleGroup__dlm` not enabled
**Cause:** The Billing data kits were not deployed.
**Fix:** Deploy Common Billing Bundle and Advanced Billing Bundle (Step 5).

### Issue: Bundle wizard Deploy button disabled
**Cause:** The data space was not selected; it can show "Select Data Space".
**Fix:** Open the Data Space combobox and pick `default`.

### Issue: Order activation fails with FAILED_ACTIVATION "Enter the billing address and bill to contact associated with the account"
**Cause:** `createOrderFromQuote` does not copy addresses or contacts to the Order.
**Fix:** Before setting `Status = Activated`, PATCH these fields:
- the Order Billing* and Shipping* address fields
- `BillToContactId` and `ShipToContactId`

Appendix A does this automatically.

### Issue: Quote placement fails with INVALID_PERIOD_BOUNDARY
**Cause:** The product has a proration policy.
**Fix:** Send `PeriodBoundary: Anniversary` plus a `BillingFrequency` (Annual or Monthly) on Term-Defined and Evergreen lines.

### Issue: Quote placement fails with UNKNOWN_EXCEPTION "hydrating additional context fields" for one product
**Cause:** A product setup issue in the dataset (seen with `QB-TRN-FUND`).
**Fix:** Run `coverage-simple` first and remove any failing product from `simple_products`.

### Issue: "Session expired or invalid" midway through a bulk run
**Cause:** The connection's access token expired. Transactions that failed have `INVALID_SESSION_ID` or empty (`null`) errors in the manifest.
**Fix:**
1. Call `RequestConnectionUpdate` and re-check the alias.
2. Re-run the generator with a new `--tag` for the shortfall count. Runs are additive.
3. Failed transactions may leave orphan quotes or draft orders. These are harmless, or can be deleted by ID from the manifest.

### Issue: Lifecycle mode reports "No eligible assets"
**Cause:** No active, pristine term-defined assets exist yet. Lifecycle needs assets from term subscriptions that have only an Initial Sale action, are not expired, and have quantity greater than 1.
**Fix:** Run `simple` first. If eligible assets exist but are far from expiry, renewal picks fall back to upsells; raise `renewal_window_days` to allow more renewals.

### Issue: Quote fails or misprices for a non-USD account
**Cause:** The quote was placed without `CurrencyIsoCode`, so it defaulted to the user's currency and didn't match the price book entries.
**Fix:** Set `CurrencyIsoCode` on the Quote to the account's currency, and use price book entries in that currency. The generator does both.

### Issue: Data Cloud counts lag the CRM
**Cause:** CRM connector streams run on a system schedule, about every 10-15 minutes.
**Fix:** Wait and re-check. Use **Refresh Now** in the UI for a stream that has never run.

### Issue: `/lightning/o/DataStream/new` opens a plain record form
**Fix:** Open Data Streams inside the Data Cloud app (`/lightning/app/<Audience360 id>/o/DataStream/home`) and click **New**.

### Issue: App Builder drag-and-drop does not register (if editing pages manually)
**Fix:** Prefer the metadata deployment in Step 10. If you must use the UI, drag with stepwise mouse moves (mouse down on the palette item, about 25 intermediate moves into the canvas iframe, then mouse up).

---

## Notes
- **What the user sees on the dashboards:** sample data produces realistic signals. For example, Order Analysis may show a high Failed Orders count, which is real DRO fulfillment fallout on sample orders and can make a useful demo story. With the lifecycle mode, the Subscription dashboards show upsells, downsells (contraction/churn) and renewals across many accounts and currencies. Without it, Renewals show 0. Some Billing tiles (payments, credit memos, forecasts) stay empty until that data exists.
- **Re-running:** Step 1 detects existing streams, apps and tabs. Every later step is idempotent or skippable, and the tab patching script won't add duplicates.
- **Do not change** the DRO home page or the org default home page. Dedicated tabs are the agreed pattern.
- **Reference build (264 org, Acme):**
  - 342 sample transactions: 288 simple and 54 bundle
  - 360 activated orders, 839 assets, 1,036 billing schedules, 55 posted invoices (about $4.9M)
  - 353 fulfillment plans and 12,628 fulfillment steps
  - Total time about 3-4 hours, mostly asynchronous waits
- **Related references:** Call Revenue Cloud Business APIs (quote, order, activation and invoice contracts), Revenue Cloud Foundations (R264) (permission sets; the `RLM_RMI` permission set group = `AnalyticsStoreUser` + `PulseRuntimeUser`), and the attached `revenue_management_intelligence.pdf`.
