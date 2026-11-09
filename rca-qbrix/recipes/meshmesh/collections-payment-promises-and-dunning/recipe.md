# Set Up the Collections App, Payment Promises and Dunning Orchestration (Revenue Cloud Billing)

## Overview
Configures Revenue Cloud (Agentforce Revenue Management) Billing **Collections** end to end:
collection plans and plan items for overdue invoices, the Collections console app (repo assets from
`bgaldino/rlm-base-dev`), payments (Salesforce Payments merchant account + optional mock gateway for
test orgs), saved payment methods, **payment promises**, payment runs, and **dunning orchestration**
(Dynamic Revenue Orchestrator templates installed from Salesforce Go).

Validated live on a Revenue Cloud Billing org (API v68.0, release 262/264) in Nov 2026. Every error
listed in Troubleshooting was actually hit and fixed during validation.

Sources: Agentforce Revenue Management Guide (Summer '26) — "Manage Collections for Accounts in Billing",
"Create Collection Plans and Collection Plan Items" (help id `ind.billing_collection_plans_and_plan_items_create`),
"Set Up Orchestrated Dunning for Collections", "Set Up Payment Features"; Salesforce Help
"Collections and Recovery" setup; repo `bgaldino/rlm-base-dev` (`prepare_collections`, `prepare_payments` flows).

## Prerequisites

### Required Connections
- Salesforce org (System Administrator) with the **Revenue Cloud Billing** license — alias below is `{{ORG_ALIAS}}`.
- Internet access to `raw.githubusercontent.com/bgaldino/rlm-base-dev` (repo Collections assets).
- Browser access to the org (some steps are UI-only: Salesforce Go install, Company Information, Stripe onboarding).

### Other Requirements
- Billing already turned on (`BillingSettings.enableBillingSetup=true`), default billing treatment, tax treatment, legal entity and payment term configured (Billing Guided Setup Steps 1–6).
- Permission set licenses present: `RevLifecycleMgmtBillingPsl`, `BillingAdvancedPsl`, `CollectionsAndRecoveryPsl`, `DynamicRevenueOrchestratorUserPsl`.
- Subscription Management must be OFF (Billing can't coexist with it).
- Use the `metadata` capability for deploys; use the browser for UI-only steps (read the salesforce-browser guide first).
- **Never** pass the org alias through a shell variable in commands — write it literally.
- **Never** put `{{...}}` placeholders inside shell commands (they trigger credential prompts) — write such files with the file editor.
- Supporting files in this recipe: `settings-bundle.xml`, `BillingOrchPlanCtxMapping.orchestrationPlanCtxMapping.xml`,
  `DetermineCaseReasonAndRelatedAttributes.decisionMatrixDefinition-meta.xml`, `decision_matrix_case_rows.csv`,
  `Collection_Console_App.timelineObjectDefinition-meta.xml`, `RLM_MockPaymentGatewayAdapter.cls`,
  `RLM_MockPaymentGateway.namedCredential.xml`, `RLM_MockGatewayProvider.paymentGatewayProvider.xml`,
  `saved-payment-method-template.json`.

## Steps

### Step 1: Discover current state (read-only)
```bash
sf data query -o {{ORG_ALIAS}} --query "SELECT DeveloperName, TotalLicenses, UsedLicenses FROM PermissionSetLicense WHERE DeveloperName IN ('RevLifecycleMgmtBillingPsl','BillingAdvancedPsl','CollectionsAndRecoveryPsl','DynamicRevenueOrchestratorUserPsl')"
sf data query -o {{ORG_ALIAS}} --query "SELECT Code, Name, IsActive FROM CollectionPlanReason"
sf data query -o {{ORG_ALIAS}} --query "SELECT Id, Name FROM FulfillmentWorkspace"
sf data query -o {{ORG_ALIAS}} --query "SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName LIKE 'RLM_%Collection%' OR ApiName LIKE 'RLM_Create_%' OR ApiName = 'OrchestrateDunningRmndr'"
sf org list metadata -o {{ORG_ALIAS}} -m OrchestrationPlanCtxMapping --api-version 68.0
```
Retrieve `Settings:Billing`, `Settings:Industries`, `Settings:DynamicFulfillmentOrchestrator`, `Settings:Payments`
(API 68.0) and note what is already on. If a Collections setup already exists, stop and ask the user how to proceed.

### Step 2: Assign permission sets to the admin and collections users
```bash
sf org assign permset -o {{ORG_ALIAS}} -n RevenueLifecycleManagementBillingAdmin -n RevenueLifecycleManagementBillingOperations -n BillingCollectionsAndRecoverySpecialist -n CollectionsAndRecoveryAdmin -n BillingAdvancedPaymentOperations -n BillingAdvancedPaymentAdministrator -n DROOrchestrateTransactionUser
```
- `BillingCollectionsAndRecoverySpecialist` — create collection plans/items, payment promises.
- `BillingAdvancedPaymentOperations` / `BillingAdvancedPaymentAdministrator` — payment schedules, merchant accounts, payment runs.
- `DROOrchestrateTransactionUser` ("Submit Transactions and Orchestrate User") — **required** to click Initiate Dunning Orchestration (otherwise `SF_DRO_ORCH_IA_00003 Access Denied`).
- Collections reps also need `OmniStudioUser` (flexcards on the plan page). For collections reps, assign `BillingCollectionsAndRecoverySpecialist`, `BillingAdvancedPaymentOperations`, `DROOrchestrateTransactionUser`, `OmniStudioUser`.

### Step 3: Fill Company Information (UI — required for dunning emails)
Organization address is not API-writable. Browser: `/lightning/setup/CompanyProfileInfo/home` → Edit →
Street, City, Zip/Postal Code (keep Country) → Save.

### Step 4: Deploy org settings (timeline, DRO, dunning, payments)
Split `settings-bundle.xml` into individual files under `settings/` (no `-meta.xml` suffix) and deploy in
metadata-dir format with `package.xml` version **68.0**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
  <types><members>Billing</members><members>Industries</members><members>DynamicFulfillmentOrchestrator</members><members>Payments</members><name>Settings</name></types>
  <version>68.0</version>
</Package>
```
```bash
sf project deploy start -o {{ORG_ALIAS}} --metadata-dir ./settings-deploy --wait 15
```
This turns on: Timeline, **Collection Plan Event Timeline**, DRO + **Future-Dated Steps**, **Automate Dunning
Orchestration**, Salesforce Payments. All timeline/dunning toggles are **irreversible** — confirm with the user first.
Optionally (UI) Setup → Collections Settings → enable **View Account & Contact Details** (irreversible).

### Step 5: Deploy the Billing orchestration context mapping (CRITICAL)
Enabling dunning through metadata does **not** create `BillingOrchPlanCtxMapping`; without it Initiate Dunning
fails with `SF_DRO_ORCH_IA_00016 Missing Context Mapping ... usage type Billing`. Deploy
`BillingOrchPlanCtxMapping.orchestrationPlanCtxMapping.xml` as
`orchestrationPlanCtxMappings/BillingOrchPlanCtxMapping.orchestrationPlanCtxMapping` (API 68.0):
```xml
<OrchestrationPlanCtxMapping xmlns="http://soap.sforce.com/2006/04/metadata">
    <label>Billing Orchestration Plan Context Mapping</label>
    <orchestrationType>Billing</orchestrationType>
    <contextDefinition>BillingCollectionPlanContext__stdctx</contextDefinition>
    <objectName>CollectionPlan</objectName>
    <contextMapping>CollectionPlanBillingMapping</contextMapping>
    <contextRootNode>CollectionPlan__std</contextRootNode>
    <contextItemNode>CollectionPlanItem__std</contextItemNode>
</OrchestrationPlanCtxMapping>
```
Node and mapping names come from `GET /services/data/v68.0/connect/context-definitions/BillingCollectionPlanContext__stdctx`
(standard `__stdctx` definitions can't be retrieved via Metadata API). Use the `__std` node names — the dunning
scenario conditions reference tags like `CollectionPlan_OverdueRiskIndicator__std`.

### Step 6: Install the Dunning Orchestration Solution (UI, Salesforce Go — irreversible)
Browser: Setup → Salesforce Go (`/lightning/setup/SalesforceGo/home`) → search **Dunning** → Data Packs →
**Dunning Orchestration Solution** → Set Up (`/lightning/setup/page/solution/billing-dunning-orchestration/home`)
→ Get Started → Install → Next → **Run Conflict Check** (expect "No conflicts were found") → **Turn On**.
Wait until "Install Templates" completes (2–5 min). Verify:
```bash
sf data query -o {{ORG_ALIAS}} --query "SELECT Id, Name FROM FulfillmentWorkspace WHERE Name = 'Collections Dunning Orchestration Workspace'"
sf data query -o {{ORG_ALIAS}} --query "SELECT DeveloperName, Name, FolderName FROM EmailTemplate WHERE Name IN ('Early Reminder Email Template','Invoice Due Notice Email Template','Suspension Notice Email Template')"
```
The 3 email templates land in the installing admin's **My Private Email Templates** folder — move them to a
public folder so other users' dunning runs can use them.

### Step 7: Deploy the repo Collections tier (strict order)
Download from `https://raw.githubusercontent.com/bgaldino/rlm-base-dev/main/`:
`unpackaged/post_collections/**`, `unpackaged/post_collections_case_flow/**`,
`scripts/apex/deactivateCollectionsCaseMatrix.apex`, `scripts/apex/seedCollectionsCaseMatrix.apex`,
and UX templates `templates/flexipages/standalone/collections/*`, `templates/applications/conditional/collections/*`,
`templates/objects/collections/**`. Create `sfdx-project.json` with both package directories, then:
```bash
sf apex run -o {{ORG_ALIAS}} -f scripts/apex/deactivateCollectionsCaseMatrix.apex      # no-op on first run
sf project deploy start -o {{ORG_ALIAS}} -d unpackaged/post_collections --wait 20       # flows, quick actions, timelines, matrix schema, value sets, omniUiCard, queue
sf apex run -o {{ORG_ALIAS}} -f scripts/apex/seedCollectionsCaseMatrix.apex            # CPR01-05 reasons + matrix rows + activation + self-check
sf project deploy start -o {{ORG_ALIAS}} -d unpackaged/post_collections_case_flow --wait 20  # RLM_Create_Case_for_Collection (needs active matrix)
```
Expected seed log: `SEED_MATRIX_SELFCHECK OK: CPR01 -> {"Reason":"Missed Payments","Priority":"Medium","Type":"Collections"}`.
The seed uses portable row-name hashes for the 5 rows in `decision_matrix_case_rows.csv`; if you change row
content, re-import via Decision Matrix Designer and re-capture hashes.
Then deploy the UX (flexipages `RLM_Collection_Plan_Record_Page`, `RLM_Collections_Account_Record_Page`,
`RLM_Collections_Home_Page`, app `standard__CollectionConsole` ("Billing - Collections"), list view
`RLM_All_Collection_Plans`). The plan page carries: highlights with **Charge Late Fee** and **Initiate Dunning
Orchestration**, Timeline ("Collection Plan Activities"), tabs **Details / Collect Payment Promises / More ▸ Invoices / Related**.
The Invoices tab runs flow `billing__CreateCollPlnItmForInvc`; the promise tab runs `billing__CreateBillingPromisetoPay`.
If the Initiate Dunning Orchestration action is missing on a layout, add it to the Collection Plan page layout.

### Step 8: Set up payments
**8a. Merchant account (production path — Salesforce Payments + Stripe).** Browser: Setup Quick Find "Payment" →
Billing ▸ Guided Setup ▸ **Step 7: Payment Configurations** (`/lightning/setup/BillingPaymentConfigurations/home`)
→ Configure Native Payment Gateways → **Configure Payments Merchant Accounts** (`/lightning/n/standard-PaymentsSettings`)
→ Add Account → "Create a merchant account through Salesforce Payments" → country + name → Add Account.
Creates `MerchantAccount` (Mode `Test`, Status `Restricted`). **A human must complete Stripe onboarding** (Stripe
email login, business address, bank routing, tax ID) in their own browser — the embedded Stripe frame refuses to
load in automation browsers. Activation can take hours to days. Requires the Payments Webhook Experience site
(repo `prepare_payments`: community "Payments Webhook", URL prefix `sfpwebhook`, published).

**8b. Mock gateway (TEST/DEMO orgs only, to validate promises and payment runs without a live processor).**
Deploy (API 64.0+) `RLM_MockPaymentGatewayAdapter.cls` (implements `commercepayments.PaymentGatewayAdapter`,
approves every request, no callouts), `RLM_MockPaymentGateway.namedCredential.xml` (Anonymous / NoAuthentication,
endpoint `https://mock-gateway.invalid`) and `RLM_MockGatewayProvider.paymentGatewayProvider.xml`, then create the gateway:
```bash
# get ids
sf data query -o {{ORG_ALIAS}} --query "SELECT Id FROM PaymentGatewayProvider WHERE DeveloperName='RLM_MockGatewayProvider'"
sf data query -o {{ORG_ALIAS}} --query "SELECT Id FROM NamedCredential WHERE DeveloperName='RLM_MockPaymentGateway'"
sf data create record -o {{ORG_ALIAS}} --sobject PaymentGateway --values "PaymentGatewayName='RLM Mock Gateway' PaymentGatewayProviderId='<provider id>' MerchantCredentialId='<named credential id>' Status='Active'"
```

**8c. Saved payment method for a customer account.** Tokenize a card on the gateway:
```bash
sf api request rest -o {{ORG_ALIAS}} --method POST "/services/data/v68.0/commerce/payments/payment-methods" --body '{"paymentGatewayId":"<gateway id>","cardPaymentMethod":{"cardHolderName":"Test Holder","expiryMonth":12,"expiryYear":2030,"cardNumber":"4242424242424242","cvv":"123","cardCategory":"CreditCard","cardType":"Visa","accountId":"<account id>"},"email":"holder@example.com"}'
```
This creates a `CardPaymentMethod`, which the promise flow does **not** list. Create a `SavedPaymentMethod`
using `saved-payment-method-template.json` (MerchantAccountId = the merchant account from 8a,
PaymentGatewayId = gateway, GatewayToken = `gatewayResponse.gatewayToken`, Type `card`, UsageType `OffSession`,
Status `Active`, GatewayReference any gateway ref).

### Step 9: Create collection plans and items (per Help article)
UI (App Launcher → Collection Plans → New, or Billing - Collections app): Account, Contact (with email), Collection
Plan Reason, **Usage Type = Billing**, Due Date, Overdue Risk Indicator (Low/Medium/High), optional Days Past Due
(not auto-calculated). API equivalent:
```bash
sf data create record -o {{ORG_ALIAS}} --sobject CollectionPlan --values "AccountId='<acc>' ContactId='<con>' CollectionPlanReasonId='<CPR01 id>' UsageType='Billing' Duedate='<yyyy-mm-dd>' OverdueRiskIndicator='High' DaysPastDue=10 CurrencyIsoCode='USD'"
```
Do NOT set `BillingAccountId` to an Account Id (expects a BillingAccount record). Then open the plan in the
**Billing - Collections** app → More ▸ **Invoices** tab → select up to 10 unsettled invoices → **Create**
("Collection plan items for selected invoices were created."). Failures are logged on the invoice's Revenue
Transaction Error Logs. API alternative: create `CollectionPlanItem` with `CollectionPlanId`, `InvoiceId`.

### Step 10: Collect a payment promise
Before the first promise on an invoice, cancel the Draft payment schedule Billing auto-created at posting
(only when no payment method existed):
```bash
sf data query -o {{ORG_ALIAS}} --query "SELECT Id, Status, PaymentScheduleId FROM PaymentScheduleItem WHERE PaymentSchedule.ReferenceEntityId='<invoice id>' AND Status='Draft'"
sf data update record -o {{ORG_ALIAS}} --sobject PaymentScheduleItem --record-id <psi id> --values "Status='Canceled'"
sf data update record -o {{ORG_ALIAS}} --sobject PaymentSchedule --record-id <ps id> --values "Status='Canceled'"
```
Plan record → **Collect Payment Promises** tab → **New Payment Promise** → select the plan item → Next → number
of partial payments (1–3), amount(s) ≤ invoice balance, date(s) → select the **Saved Payment Method** → Next →
"A payment promise was created with the relevant payment schedules." → Finish. Result: `PaymentSchedule`
Status `Open` with `CollectionPlanItemId` + `DefaultPaymentMethodId`; items `Ready for Processing`.

### Step 11: Process promises with a payment run
```bash
sf api request rest -o {{ORG_ALIAS}} --method POST "/services/data/v68.0/commerce/payments/payment-schedulers/" --body '{"schedulerName":"Collections Payment Run","startDate":"<yyyy-mm-dd>","preferredTime":"<HH:mm in running user TZ>","frequencyCadence":"Daily","status":"Active"}'
```
Use `Once` for a test. Items whose `TargetPaymentProcessingDate` ≤ run date are charged; the payment is applied
to the invoice (item status `Applied`).

### Step 12: Configure the dunning workflow (timing + risk routing)
The installed workspace ships **untimed** steps: groups "Low and Medium Risk Accounts" (friendly reminder →
reminder → suspension notice) and "High Risk Accounts" (friendly reminder ×2 → reminder → suspension notice),
flow `DunningOrch__OrchestrateDunningRmndr`, no manual "call customer" step. Without timing, every step fires
the moment dunning starts. Set timing per `FulfillmentStepDefinition` (UI: DRO workspace, or API):
```bash
sf data update record -o {{ORG_ALIAS}} --sobject FulfillmentStepDefinition --record-id <step def id> --values "ExecuteOn='PreviousStepExecutionDate' DelayOf=7 DelayUnit='Days'"
```
`ExecuteOn` ∈ `SourceLineStartDate | CustomDate | PreviousStepExecutionDate`, `DelayUnit` ∈ `Minutes | Hours | Days`
(verified: step becomes `Scheduled` with `NextEarliestRunTime` = +7 days). Target timings from the guide —
Low/Medium: −5d, due date, +7d, +10d call; High: −10d, −5d, due date, +3d, +4d call (relative to plan due date → use `CustomDate`).
**Risk routing caveat (observed, unresolved):** in testing, scenario `ConditionData` on `OverdueRiskIndicator`
did NOT exclude the other group — low-risk plans still got the high-risk steps, held back only by the shipped
cross-group dependency (High "Send a friendly reminder email" depends on Low "Send a suspension notice").
Do **not** delete that dependency (doing so made high-risk emails fire immediately). Add execute-on conditions
on each step for `OverdueRiskIndicator` and validate with a Low and a High plan before go-live.

### Step 13: Initiate dunning
Plan requirements: Due Date, Overdue Risk Indicator, Contact with email, ≥1 plan item, Usage Type Billing.
Plan record → **Initiate Dunning Orchestration** → toast "Billing Collection Plan Dunning Orchestration started
successfully." Only **one** orchestration per plan (`SF_DRO_ORCH_IA_00018` on re-submit).

## Verification
```bash
sf data query -o {{ORG_ALIAS}} --query "SELECT Name, State, SourceIdentifier FROM FulfillmentPlan WHERE UsageType='Billing' ORDER BY CreatedDate DESC LIMIT 1"
sf data query -o {{ORG_ALIAS}} --query "SELECT Name, State, NextEarliestRunTime, ActualCompletionDate FROM FulfillmentStep WHERE FulfillmentPlan.SourceIdentifier='<plan id>'"
sf data query -o {{ORG_ALIAS}} --query "SELECT Subject, Status FROM EmailMessage WHERE RelatedToId='<plan id>'"
sf data query -o {{ORG_ALIAS}} --query "SELECT PaymentScheduleItemNumber, Status, PaymentId FROM PaymentScheduleItem WHERE PaymentSchedule.CollectionPlanItem.CollectionPlanId='<plan id>'"
sf data query -o {{ORG_ALIAS}} --query "SELECT PaymentNumber, Status, Amount, NetApplied FROM Payment ORDER BY CreatedDate DESC LIMIT 3"
```
Success looks like: plan items listed on the plan; promise schedule `Open` → item `Applied` after the run with a
`Processed` payment and reduced invoice balance; FulfillmentPlan `InProgress`/`Completed` with timed steps
`Scheduled`; emails "Upcoming invoices for your …", "Invoices due for …", "Suspension notice for …" logged as
completed Tasks and visible on the plan timeline.

## Troubleshooting

### Issue: "Property 'enableDunningOrchestration' not valid in version 66.0"
**Cause:** setting introduced in API 68. **Fix:** package.xml `<version>68.0</version>`.

### Issue: "settings metadata is missing from the 'settings' folder"
**Cause:** metadata-dir deploys need `settings/Billing.settings` (no `-meta.xml`). **Fix:** rename files.

### Issue: SF_DRO_ORCH_IA_00003 Access Denied: missing permission sets to orchestrate
**Fix:** assign `DROOrchestrateTransactionUser`.

### Issue: SF_DRO_ORCH_IA_00016 Missing Context Mapping for usage type Billing
**Cause:** metadata-enabled dunning setting doesn't create the mapping (the UI toggle is locked on afterwards).
**Fix:** Step 5 mapping with `__std` node names.

### Issue: All dunning emails sent at once / both risk groups run
**Cause:** shipped step definitions have no timing; scenario conditions didn't gate groups in testing.
**Fix:** Step 12 timing + execute-on conditions; test with separate plans.

### Issue: SF_DRO_ORCH_IA_00018 Orchestration Plan Already Exists
**Cause:** one orchestration per collection plan. **Fix:** new plan (or amendment).

### Issue: Promise flow shows "Select 1 or more rows." under Saved Payment Method / empty grid
**Cause:** no `SavedPaymentMethod` for the account (CardPaymentMethod isn't listed). **Fix:** Step 8c. In
automation, click the row's "Select Item 1" label, not the radio.

### Issue: "We can't create this Payment Schedule because its invoice is associated with another Payment Schedule that's in Draft or Open status"
**Cause:** auto-created Draft schedule at invoice posting. **Fix:** cancel it (Step 10).

### Issue: "Cannot edit Target Payment Processing Date while Payment Schedule Item status is Ready for Processing" / can't revert to Draft
**Fix:** create a new promise with the desired date.

### Issue: Payment scheduler "Enter the time in HH:mm format."
**Fix:** `preferredTime` like `23:26` (running user's time zone), no seconds/Z.

### Issue: CollectionPlan "Billing Account ID: id value of incorrect type"
**Fix:** leave `BillingAccountId` blank or use a BillingAccount record id.

### Issue: OrderItem "Unable to create/update fields: ProductSellingModelId" (test data)
**Fix:** omit it — derived from the PricebookEntry.

### Issue: Plan page has no Invoices / Collect Payment Promises tabs
**Cause:** default layout/app. **Fix:** open in the Billing - Collections app with `RLM_Collection_Plan_Record_Page`; Invoices is under "More".

### Issue: Stripe onboarding frame "refused to connect"
**Fix:** a human completes onboarding in a normal browser; use the mock gateway for test validation.

### Issue: Session expired (INVALID_SESSION_ID) mid-run
**Fix:** reconnect the org connection and continue; verify org Id matches before resuming.

## Notes
- Test data recipe (when no invoices exist): Account + Contact (email) → Order (EffectiveDate in past, Bill To Contact, billing/shipping address) → OrderItem (PricebookEntry with billing policy) → activate → `POST /commerce/invoicing/billing-schedules/actions/create {"billingTransactionIds":["<order id>"]}` (async ~10 s) → `POST /commerce/invoicing/invoices/collection/actions/generate {"billingScheduleIds":[...],"action":"Posted","invoiceDate":"<past>","targetDate":"<past>"}` (async ~30–90 s).
- Collection Plan `Status` picklist may have no values; add Active/Pending if using Industries case/legal features.
- Dunning works at plan level (plan due date), not per invoice; each email lists all plan invoices.
- Invoices tab balances show in the user's personal currency; set the user currency to the invoice currency.
- Alternative email path: Data Cloud + Marketing Cloud Next campaigns, or send email from the plan record.
- Industries "Collections & Recovery" (FSC/Automotive) features (action launcher, actionable lists, risk scoring) are separate from Billing Collections; the native `CollectionsAndRecoveryPsl` is still assigned by the repo.
- Remove the mock gateway, mock saved payment methods and test plans before any production use.
