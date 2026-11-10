# Revenue Promotions — Manual Setup Walkthrough

The full procedure for turning on Global Promotions and creating one automatic and one
coupon promotion, step by step. It was run end to end on a release 264 QuantumBit org
(`salesforcemeshmeshtest-6pswgq`, November 2026), and step 1b comes from a fresh scratch
org. It assumes `prepare_rlm_org` has already built the org. Run only the steps the SKILL.md
Discovery queries show are missing.

Placeholders use `<ANGLE_BRACKETS>`. Run `sf` commands with long flags (`--sobject`,
`--values`, `--target-org`) and the org alias or username written out, not in a shell
variable. The UI steps describe what to click, not how; any browser tool works. Tips
for playwright-cli are in [`browser-automation-appendix.md`](browser-automation-appendix.md).

> ⚠️ **Step 1 is irreversible.** Get explicit approval from the org owner first.

## Before you start

- System Administrator access to the org, and a browser session on it (`sf org open --target-org <sf_alias>`).
- Revenue Cloud Advanced licensing with Context Service on (the default in Revenue Cloud orgs).
- `RevPromotionsManagementPsl` ("Revenue Management Promotions Run Time") in the org:

  ```bash
  sf data query --query "SELECT MasterLabel, DeveloperName, TotalLicenses, UsedLicenses FROM PermissionSetLicense WHERE MasterLabel LIKE '%romotion%'" --target-org <sf_alias>
  ```

- The active default pricing procedure `<PRICING_PROCEDURE_API>` and its context definition
  `<CONTEXT_DEFINITION>`. In an org built by `prepare_rlm_org`: `RLM_DefaultPricingProcedure` and `RLM_SalesTransactionContext`.
- The products to promote, and **every** selling model on each (see the SKILL.md Discovery queries).

## Step 1 — Global Promotions Management settings (Setup UI)


1. Open Setup → Quick Find "Promot" → **Global Promotions Management Settings**
   (`/lightning/setup/UnifiedPromotionsSetupNode/home`). The URL
   `GlobalPromotionsManagementSettings/home` returns "Page not found".
2. Turn on **Global Promotions Management**, then click **OK** in the confirmation dialog.
3. **Promotion Evaluation and Execution** turns on by itself.
4. Turn on **Product Catalog Management** (needed for bundle promotions), then click **OK**.

**Verify:** reload the page. All three switches are on, and Global Promotions
Management is disabled, because it can no longer be turned off. Their switch inputs are
named `UpsPref`, `PromotionEvalPref` and `PcmPref`.

If a click on a switch does nothing, the click probably landed on the toggle's faux
container. Click the switch's own label or input element instead.

## Step 1b — Global Promotions for Revenue Cloud (metadata deploy)

`IndustriesUnifiedPromotionsSettings.enableGlobalPromotionsForRevenueCloud` must be `true`.
No Setup switch sets it on a fresh org, Promotions for Transactions included. Until it is
on, the `RevPromotionsManagement` permission set doesn't exist (step 2) and the Context Tag
search in step 4 offers nothing. Retrieve the settings (SKILL.md Discovery); if it is
missing or `false`, deploy it:

```bash
mkdir -p /tmp/promo-settings-deploy/settings
cat > /tmp/promo-settings-deploy/package.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>IndustriesUnifiedPromotions</members>
        <name>Settings</name>
    </types>
    <version>68.0</version>
</Package>
XML
cat > /tmp/promo-settings-deploy/settings/IndustriesUnifiedPromotions.settings <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<IndustriesUnifiedPromotionsSettings xmlns="http://soap.sforce.com/2006/04/metadata">
    <enableGlobalPromotionsForRevenueCloud>true</enableGlobalPromotionsForRevenueCloud>
</IndustriesUnifiedPromotionsSettings>
XML
sf project deploy start --metadata-dir /tmp/promo-settings-deploy --target-org <sf_alias> --wait 10
```

The file holds only that field, so the deploy leaves step 1's switches as they are.

**Verify:** retrieve again and confirm the field is `true`, then run the step 2 permission
set query: `RevPromotionsManagement` is listed.

## Step 2 — License and permission sets (API)


```bash
sf data query --query "SELECT Id FROM User WHERE Username = '<ADMIN_USERNAME>'" --target-org <sf_alias>
sf data query --query "SELECT Id, Name FROM PermissionSet WHERE Name IN ('PromotionDesignerBasic','PromotionViewer','RevPromotionsManagement')" --target-org <sf_alias>
sf data query --query "SELECT Id, DeveloperName FROM PermissionSetLicense WHERE DeveloperName IN ('GlobalPromotionsMgmtBasicPsl','RevPromotionsManagementPsl')" --target-org <sf_alias>

# Licenses the user doesn't have yet (prepare_rlm_org already assigns RevPromotionsManagementPsl)
sf data create record --sobject PermissionSetLicenseAssign --values "AssigneeId=<USER_ID> PermissionSetLicenseId=<GlobalPromotionsMgmtBasicPsl_ID>" --target-org <sf_alias>

# Promotion Designer Basic, Promotion Viewer, Apply Promotions on Sales Transactions
sf data create record --sobject PermissionSetAssignment --values "AssigneeId=<USER_ID> PermissionSetId=<PromotionDesignerBasic_ID>" --target-org <sf_alias>
sf data create record --sobject PermissionSetAssignment --values "AssigneeId=<USER_ID> PermissionSetId=<PromotionViewer_ID>" --target-org <sf_alias>
sf data create record --sobject PermissionSetAssignment --values "AssigneeId=<USER_ID> PermissionSetId=<RevPromotionsManagement_ID>" --target-org <sf_alias>
```

`RevPromotionsManagement` ("Apply Promotions on Sales Transactions") appears only after
step 1b. If it's missing, go back to step 1b.

These are the Revenue Cloud licenses: Global Promotions Management **Basic**
(`GlobalPromotionsMgmtBasicPsl`, the license the `GlobalPromotionsMgmtBasic` scratch feature
provisions) and Revenue Management Promotions Run Time. The recipe assigns
`GlobalPromotionsManagementPsl` and `PromotionDesigner` instead. Those come with Loyalty
Management, which the meshmesh org has and the repo's scratch orgs don't.

## Step 3 — Rule library


In the UI: go to `/lightning/o/RuleLibrary/home` → **New**, and fill in:

| Field | Value | QuantumBit (meshmesh) |
|-------|-------|-----------------------|
| Name | `<RULE_LIBRARY_NAME>` | `QB Promotions` |
| API Name | `<RULE_LIBRARY_API>` | `QB_Promotions` |
| Context Definition | `<CONTEXT_DEFINITION>` | `RLM_SalesTransactionContext` |
| Usage Type | **Global Promotions Management** (API value `GlobalPromotionsForRLM`) | |

Save. The platform creates the first version, `<RULE_LIBRARY_API>_v1`. Open it from the
rule library page.

**Verify:**

```bash
sf data query --query "SELECT Id, ApiName, Status FROM RuleLibraryVersion WHERE RuleLibrary.ApiName = '<RULE_LIBRARY_API>'" --target-org <sf_alias>
```

## Step 4 — Custom Tag Mappings, then activate the version (UI)


On the version page, go to the **Custom Tag Mapping** card → **New**. For each row, pick
the **Mapping Name**, type the tag into **Context Tag**, and pick the exact option. Use
**Save & New** between rows.

Create **all 10 before activating**. A version that an active pricing procedure references
can't be deactivated later.

| Mapping Name | Context Tag |
|---|---|
| productSellingModel | `ProductSellingModel` |
| accountId | `QuoteAccount` |
| cartLineItemId | `LineItem` |
| cartLineProductId | `Product` |
| currencyISOCode | `CurrencyIsoCode` |
| cartLineProductCategoryId | `ProductCategory` |
| activityStartDate | `StartDate` |
| cartLineCouponCode | `SalesTransactionItemCouponCode__std` |
| productBundleRootId | `RootItemProduct` |
| shouldEvaluatePromotions | `ShouldEvaluatePromotions__std` |

These are the tags of the standard sales transaction context as extended by this repo.
For another context definition, find each tag with
`scripts/context_service/definition/trace_context.py --tag <part of the name>` (see
SKILL.md Discovery). `cartCouponCode` is the header-level coupon, and it is left unmapped:
see [`troubleshooting.md`](troubleshooting.md).

The Context Tag box searches as you type; on the meshmesh run, typing a character at a
time worked. If it offers nothing for a tag that exists, check step 1b first. On a fresh
scratch org it was still sometimes empty in a headless browser after step 1b, for no
cause found yet: cancel the dialog, reload the page and try again. The Mapping Name list
leaves out names that are already mapped.

Reload, and confirm all 10 rows in the grid. Then on the version: **Show more actions** →
**Activate** → **Continue** in the Confirm Mapping dialog.

**Verify:** the version query from step 3 shows `Active`.

## Step 5 — Promotion Execution in the pricing procedure


Use the Pricing Procedure builder; don't hand-write the expression set XML.

1. Switch to the **Revenue Cloud** app. The Billing console shows "Unsupported Item" for
   expression set pages. Find the procedure's Id:

   ```bash
   sf data query --query "SELECT Id FROM ExpressionSet WHERE ApiName = '<PRICING_PROCEDURE_API>'" --target-org <sf_alias>
   ```

   Open `/lightning/r/ExpressionSet/<ID>/view` → **Pricing Procedure Versions** → the active
   version. It opens the builder (`builder_industries_interaction_rule/ruleBuilder.app?ruleId=...`).
2. Click **Deactivate** and confirm.
3. On the canvas, find the **Apply bundle-based adjustments** group. Click the top-level
   **Add** right after it, and add a **List Group**.
4. In the new group's **List Operation**, set the filter condition: Resource
   `SalesTransactionItem > ItemPricingSource`, Operator **Not Equals**, Value
   `LastTransaction`. That is the same filter the bundle step uses.
5. Inside the group, after the filter: **Add** → **Calculate discounts based on promotion
   rules** (Promotion Execution).
   - **Rule Library:** type part of the name, then click the result row
     (`<RULE_LIBRARY_API> (GlobalPromotionsForRLM)`). It is selected only when it shows as a pill.
   - **Promotion Scope:** `Line`.
   - **Inputs:** Subtotal → `ItemNetTotalPrice`, Quantity → `LineItemQuantity`, Unit Price → `NetUnitPrice`.
   - **Outputs:** Unit Price → `NetUnitPrice`, Subtotal → `ItemNetTotalPrice`.
6. **Save**, then **Activate**. The page is heavy; allow 60–120 seconds per action.

## Step 6 — Promotions for Transactions (Revenue Settings)


1. Go to Setup → **Revenue Settings** (`/lightning/setup/RevenueSettings/home`).
2. Turn on **Promotions for Transactions**.
3. In the **Rule Library** box that appears, pick `<RULE_LIBRARY_NAME>`. It saves on its
   own; there is no Save button.
4. Reload. The switch is still on and the Rule Library still shows the library.
5. Check that Price Waterfall is on: retrieve `Settings:IndustriesPricing`, and confirm
   `enablePricingWaterfall` and `enablePricingWaterfallPersistence` are both `true`. This
   repo's `unpackaged/pre/2_settings` sets them; they were already on at meshmesh.
6. The packaged product configurator flow can't be edited, and doesn't need to be.
   Promotions show in Browse Catalogs and on quote lines without a change to it.

## Step 7 — Automatic promotion (API)


Use the Global Promotions Management API. The Promotions workspace **New** form is the
Commerce form, and it fails with "We couldn't create the promotion" without a web store.

1. Get every selling model on the target product:

   ```bash
   sf data query --query "SELECT ProductSellingModel.Id, ProductSellingModel.Name FROM ProductSellingModelOption WHERE Product2Id = '<TARGET_PRODUCT_ID>'" --target-org <sf_alias>
   ```

2. Copy `promotion-automatic-template.json`, fill in the placeholders, add one
   `rewardDetailsList` entry per selling model, and remove `_notes`. Start the window today
   or earlier; it applies only between `startDateTime` and `endDateTime`.
3. POST it, then activate it, since promotions are created inactive:

   ```bash
   sf api request rest "/services/data/v68.0/global-promotions-management/promotions" --method POST --body @promo-auto.json --target-org <sf_alias>
   sf data query --query "SELECT Id, Name, IsActive FROM Promotion WHERE Name = '<PROMO_NAME>'" --target-org <sf_alias>
   sf data update record --sobject Promotion --record-id <PROMOTION_ID> --values "IsActive=true" --target-org <sf_alias>
   ```

The recorded run used `v66.0` in this path; the repo is on `v68.0`.

## Step 8 — Coupon promotion and its coupon code


1. Copy `promotion-coupon-template.json` (`isAutomatic` is `false`). For a **bundle**, still
   use `"productType": "SimpleProduct"` and `"scope": "SimpleProduct"`, with the bundle
   root's product Id.
2. POST it as in step 7.
3. Create the coupon code:

   ```bash
   sf data create record --sobject Coupon --values "PromotionId=<PROMOTION_ID> CouponCode=<COUPON_CODE> Status=Active StartDateTime=<START_DATETIME_UTC> EndDateTime=<END_DATETIME_UTC> Description='<COUPON_DESCRIPTION>'" --target-org <sf_alias>
   ```

   The recorded run also set `Type=Single-Code`. Add it only where the org's Coupon has a
   `Type` field; a `prepare_rlm_org` scratch org has none and rejects the command with
   `No such column 'Type' on sobject of type Coupon`.

4. Activate the promotion:

   ```bash
   sf data update record --sobject Promotion --record-id <PROMOTION_ID> --values "IsActive=true" --target-org <sf_alias>
   ```

   Activation fails unless the `shouldEvaluatePromotions` and `cartLineCouponCode` mappings
   exist (step 4).

## Verification

```bash
sf data query --query "SELECT Name, IsActive, IsAutomatic, StartDateTime, EndDateTime FROM Promotion" --target-org <sf_alias>
sf data query --query "SELECT CouponCode, Status, Promotion.Name FROM Coupon" --target-org <sf_alias>
```

- Both promotions show `IsActive = true`. The automatic one has `IsAutomatic = true` and the
  coupon one `false`. The coupon shows `Active`.
- Today falls inside each promotion's window.
- Open a quote → **Browse Catalogs**. The target product's card shows a **1 Promotion**
  badge; click it for the promotion's details.
- Add the automatic promotion's product. The line's net price drops by the promotion's
  percentage (QuantumBit: $360 list, 10% off, $324).
- Click the product name in the line editor to open the side panel → **Promotions** tab.
  The applied promotion shows its discount and end date.
- On a line with the coupon promotion's product, the manual promotion is listed as
  eligible in the Promotions tab and can be switched on.

## Notes

- Leave Exclusivity at "No" (the default) so promotions can stack.
- Promotions also carry into amendments. An amended asset compares Last Transaction
  Price with List Price (the QuantumBit demo beat "Promotions on Amend").
- Related QuantumBit demo beats: the Browse Catalogs promotion badge, the line Promotions
  tab, the bundle coupon, and Promotions on Amend.
- `docs/enablement/master/02-salesforce-pricing.md` still describes Promotions as 260 Beta,
  and says Promotion Execution can't share a procedure with Derived Pricing or Price
  Propagation. The recorded 264 run added Promotion Execution to `RLM_DefaultPricingProcedure`,
  which has neither element type, and then flagged the derived-pricing demo beats (for
  example Software Maintenance) for a re-test. Do that re-test after step 5 on any procedure
  you change.
