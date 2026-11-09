# Set Up Revenue Cloud Promotions (Automatic + Coupon) on Quotes

## Overview
This recipe turns on Revenue Cloud (Agentforce Revenue Management) **Global Promotions** end to end in an org where they're off, then creates one automatic promotion and one coupon/manual promotion. When it's done:
- Browse Catalogs shows a "1 Promotion" badge on targeted products.
- Automatic promotions apply at pricing (for example 10% off, visible on the quote line and in the line's **Promotions** tab).
- Manual promotions can be toggled on a quote line.

Use it for QuantumBit (CDO) or any Revenue Cloud org that needs the "Promotions (requires Promotions post-spin setup)" demo beat.

Placeholders use `<ANGLE_BRACKETS>`. The **QuantumBit worked example** values are shown beside each step.

> ⚠️ **Irreversible:** turning on Global Promotions Management can't be undone. Get explicit user approval before Step 1. Also tell the user that adding promotion execution to the default pricing procedure might affect derived-pricing beats (for example Software Maintenance), and re-test those beats afterwards.

## Prerequisites

### Required Connections
- Salesforce org (salesforce-core connection) with System Administrator access. Example alias: `salesforcemeshmeshtest-6pswgq`. Use the org alias **literally** in every command (not through a shell variable), and use long flags (`--sobject`, `--values`, `--target-org`).
- Browser access to the same org (open it via openSalesforceOrg). Several steps are UI-only.

### Other Requirements
- Revenue Cloud Advanced licensing, with **Context Service** on (default in Revenue Cloud orgs).
- The permission set license **Revenue Management Promotions Run Time** (`RevPromotionsManagementPsl`) must exist in the org. Check with:
  ```bash
  sf data query --query "SELECT MasterLabel, DeveloperName, TotalLicenses, UsedLicenses FROM PermissionSetLicense WHERE MasterLabel LIKE '%romotion%'" --target-org <ORG_ALIAS>
  ```
- The active pricing procedure and its sales transaction context definition. In QuantumBit these are `RLM_DefaultPricingProcedure` and `RLM_SalesTransactionContext`.
- Product IDs for each promotion target, and the IDs of **every** Product Selling Model (PSM) on those products.
- Use the salesforce-browser instructions for navigation, and the metadata instructions if you retrieve the pricing procedure.

## Steps

### Step 1: Turn on the Global Promotions Management settings (Setup UI)
1. Open Setup and Quick Find "Promot" → **Global Promotions Management Settings** (`/lightning/setup/UnifiedPromotionsSetupNode/home`). The URL `GlobalPromotionsManagementSettings/home` returns "Page not found".
2. Turn on **Global Promotions Management**, then click **OK** in the confirmation dialog.
   - Normal clicks can be blocked by the toggle's faux container ("intercepts pointer events"). If so, click the switch element directly with `playwright-cli eval "el => el.click()" <ref>`.
3. **Promotion Evaluation and Execution** turns on automatically.
4. Turn on **Product Catalog Management** (needed for bundle promotions) and click **OK**.
5. Verify in the snapshot that all three switches show `[checked]`, and that Global Promotions Management is `[disabled]` (permanent).

### Step 2: Assign the license and permission sets to the demo user
```bash
sf data query --query "SELECT Id FROM User WHERE Username='<ADMIN_USERNAME>'" --target-org <ORG_ALIAS>
sf data query --query "SELECT Id, Name FROM PermissionSet WHERE Name IN ('PromotionDesigner','PromotionViewer','RevPromotionsManagement')" --target-org <ORG_ALIAS>
sf data query --query "SELECT Id, DeveloperName FROM PermissionSetLicense WHERE DeveloperName IN ('GlobalPromotionsManagementPsl','RevPromotionsManagementPsl')" --target-org <ORG_ALIAS>
# Assign PSLs the user doesn't already have (RevPromotionsManagementPsl was already assigned in QuantumBit)
sf data create record --sobject PermissionSetLicenseAssign --values "AssigneeId=<USER_ID> PermissionSetLicenseId=<GlobalPromotionsManagementPsl_ID>" --target-org <ORG_ALIAS>
# Permission sets: Promotion Designer, Promotion Viewer, Apply Promotions on Sales Transactions
sf data create record --sobject PermissionSetAssignment --values "AssigneeId=<USER_ID> PermissionSetId=<PromotionDesigner_ID>" --target-org <ORG_ALIAS>
sf data create record --sobject PermissionSetAssignment --values "AssigneeId=<USER_ID> PermissionSetId=<PromotionViewer_ID>" --target-org <ORG_ALIAS>
sf data create record --sobject PermissionSetAssignment --values "AssigneeId=<USER_ID> PermissionSetId=<RevPromotionsManagement_ID>" --target-org <ORG_ALIAS>
```
`RevPromotionsManagement` ("Apply Promotions on Sales Transactions") might only appear after Step 1. Re-query it if it's missing.

### Step 3: Create the rule library (UI)
1. Go to `/lightning/o/RuleLibrary/home` and click **New**.
2. Fill in:
   - Name `<RULE_LIBRARY_NAME>` (QB: `QB Promotions`)
   - API Name `<RULE_LIBRARY_API>` (QB: `QB_Promotions`)
   - Context Definition `<CONTEXT_DEFINITION>` (QB: `RLM_SalesTransactionContext`)
   - Usage Type **Global Promotions Management** (API value `GlobalPromotionsForRLM`)
3. Save, then record the rule library ID (QB: `9Qsbm000000OR2HCAW`).
4. Open its version record (`<RULE_LIBRARY_API>_v1`) from the rule library page.

### Step 4: Add Custom Tag Mappings to the rule library version (UI), then activate it
On the version page, go to the **Custom Tag Mapping** section → **New**. For each row, pick the **Mapping Name**, then type the tag into **Context Tag** and pick the exact option. Use **Save & New** between rows.

Create **all 10 mappings before activating**. A version referenced by an active pricing procedure can't be deactivated later (see Troubleshooting).

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

Optional: `cartCouponCode` is the header-level coupon. The standard sales transaction context has no header-level coupon tag; see Troubleshooting.

Helper used for the browser loop. Save it as `tools/map.sh` and run it with `bash tools/map.sh <mappingName> <tagSearch> [exactTag]`; without `exactTag` it lists candidate tags.
```bash
S(){ playwright-cli snapshot 2>&1; }
ref(){ S | grep -oP "$1 \[ref=\K[a-z0-9]+" | head -1; }
M=$(ref 'combobox "Mapping Name"'); playwright-cli click $M >/dev/null; sleep 1.5
O=$(ref "option \"$1\""); playwright-cli click $O >/dev/null; sleep 1
T=$(ref 'combobox "Context Tag"'); playwright-cli click $T >/dev/null; playwright-cli type "$2" >/dev/null; sleep 3
if [ -z "$3" ]; then S | grep -E 'option "' | sed -n '1,15p'; exit; fi
O2=$(ref "option \"$3\""); [ -z "$O2" ] && { echo "TAG NOT FOUND"; exit 1; }
playwright-cli click $O2 >/dev/null; sleep 1
B=$(ref 'button "Save & New"'); playwright-cli click $B >/dev/null; sleep 5
S | grep -oE "Tag mapping was created|rror[^\"]{0,160}" | tail -2
```
Reload the page and confirm all 10 tags in the grid. Then, on the version, go to **Show more actions → Activate → Continue** in the Confirm Mapping dialog. Verify:
```bash
sf data query --query "SELECT Status FROM RuleLibraryVersion WHERE RuleLibraryId='<RULE_LIBRARY_ID>'" --target-org <ORG_ALIAS>   # expect Active
```

### Step 5: Add Promotion Execution to the active pricing procedure (Pricing Procedure builder UI)
Don't hand-write the expression set XML for this element; use the builder.
1. Open the builder. The Billing console app shows "Unsupported Item" for ExpressionSet pages, so switch to the **Revenue Cloud** app first.
   - Find the procedure's ExpressionSet ID with: `SELECT Id FROM ExpressionSet WHERE ApiName='<PRICING_PROCEDURE_API>'`.
   - Open `/lightning/r/ExpressionSet/<ID>/view` → **Pricing Procedure Versions** → open the active version. The builder URL is `builder_industries_interaction_rule/ruleBuilder.app?ruleId=...`.
2. Click **Deactivate**, then confirm.
3. On the canvas, find the **Apply bundle-based adjustments** group. Click the top-level **Add** right after it → add a **List Group**.
4. In the new group's **List Operation**, set Filter Condition Requirements to: Resource `SalesTransactionItem > ItemPricingSource`, Operator **Not Equals**, Value `LastTransaction`. This is the same filter the bundle step uses.
5. Inside the group, after the filter, use **Add** → **Calculate discounts based on promotion rules** (Promotion Execution).
   - **Rule Library:** type part of the name and click the result row (`<RULE_LIBRARY_API> (GlobalPromotionsForRLM)`). It counts as selected only when it shows as a pill.
   - **Promotion Scope:** `Line`.
   - **Input variables:**
     - Subtotal → `ItemNetTotalPrice`
     - Quantity → `LineItemQuantity`
     - Unit Price → `NetUnitPrice`
   - **Output variables:**
     - Unit Price → `NetUnitPrice`
     - Subtotal → `ItemNetTotalPrice`
   - Some dropdown options have no clickable ref. Type the value, then press **ArrowDown** and **Enter**. If a box still holds leftover text, click it, press Control+A and Backspace, then retype.
6. Click **Save**, then **Activate**. The page is heavy, so allow 60–120 s per action.

### Step 6: Turn on promotions for transactions (Revenue Settings)
1. Go to Setup → `/lightning/setup/RevenueSettings/home`.
2. Turn on **Promotions for Transactions** (click via `eval el.click()` if the click is blocked).
3. In the **Rule Library** combobox that appears, pick `<RULE_LIBRARY_NAME>`. It auto-saves; there's no Save button.
4. Reload the page and verify the switch is `[checked]` and the Rule Library still shows the library.
5. Confirm Price Waterfall is on: retrieve `Settings:IndustriesPricing` and check that `enablePricingWaterfall` and `enablePricingWaterfallPersistence` are both `true`. They were already true in QuantumBit.
6. The packaged product configurator flow (`runtime_industries_cfg` / ProductConfig template) can't be edited, and no change is needed. Promotions show in Browse Catalogs and on quote lines without it.

### Step 7: Create the automatic promotion (API, not the Promotions workspace UI)
The Promotions workspace form (Commerce-style) fails with "We couldn't create the promotion" because it expects a web store. Use the Global Promotions Management API instead.
1. Get every PSM on the target product:
   ```bash
   sf data query --query "SELECT ProductSellingModel.Id, ProductSellingModel.Name FROM ProductSellingModelOption WHERE Product2Id='<TARGET_PRODUCT_ID>'" --target-org <ORG_ALIAS>
   ```
2. Copy `promotion-automatic-template.json`, fill in the placeholders, and add one `rewardDetailsList` entry per PSM. Remove `_notes`. QB used 10% off QuantumBit Subscription (`01tbm00000Uaub2AAB`), with start 2026-11-01T08:00:00.000Z and end 2026-11-30T23:59:00.000Z.
3. POST it, then activate (promotions are created inactive):
   ```bash
   sf api request rest "/services/data/v66.0/global-promotions-management/promotions" --method POST --body @promo-auto.json --target-org <ORG_ALIAS>
   sf data query --query "SELECT Id, Name, IsActive FROM Promotion WHERE Name='<PROMO_NAME>'" --target-org <ORG_ALIAS>
   sf data update record --sobject Promotion --record-id <PROMOTION_ID> --values "IsActive=true" --target-org <ORG_ALIAS>
   ```

### Step 8: Create the coupon / manual promotion and its coupon code
1. Copy `promotion-coupon-template.json` (`isAutomatic=false`). For a **bundle**, still use `"productType": "SimpleProduct"` and `"scope": "SimpleProduct"` with the bundle root's product ID. QB used QuantumBit Complete Solution, `01tbm00000UaluyAAB`, on its Term Annual, Term Monthly, Evergreen Monthly and One-Time PSMs.
2. POST it as in Step 7.
3. Create the coupon code record:
   ```bash
   sf data create record --sobject Coupon --values "PromotionId=<PROMOTION_ID> CouponCode=<COUPON_CODE> Status=Active Type=Single-Code StartDateTime=<START_DATETIME_UTC> EndDateTime=<END_DATETIME_UTC> Description='<COUPON_DESCRIPTION>'" --target-org <ORG_ALIAS>
   ```
4. Activate it:
   ```bash
   sf data update record --sobject Promotion --record-id <PROMOTION_ID> --values "IsActive=true" --target-org <ORG_ALIAS>
   ```
   Activation fails unless the `shouldEvaluatePromotions` and `cartLineCouponCode` mappings exist (Step 4).

## Verification
```bash
sf data query --query "SELECT Name, IsActive, IsAutomatic, StartDateTime, EndDateTime FROM Promotion" --target-org <ORG_ALIAS>
sf data query --query "SELECT CouponCode, Status, Promotion.Name FROM Coupon" --target-org <ORG_ALIAS>
```
- Both promotions show `IsActive=true`. The automatic one has `IsAutomatic=true` and the coupon one `false`. The coupon shows `Active`.
- **Today must fall inside the promotion's date window**, or nothing applies.
- In the UI, open a quote → **Browse Catalogs**. The targeted product card shows a **"1 Promotion"** badge, and clicking the badge shows the promotion details.
- Add the automatic-promo product to the quote. The line's net price drops by the promo percentage. QB example: $360 list → 10% discount → $324.
- Click the product name in the line editor to open the side panel → **Promotions** tab. The applied promotion shows its discount and end date.
- On a line with the coupon-promo product, the manual promotion appears as eligible in the line's Promotions tab and can be switched on.

## Troubleshooting

### Issue: "Invalid value for Product type error: Bundle" when creating a bundle promotion
**Cause:** The promotions API only accepts `SimpleProduct` here. `Bundle`, `BundleProduct`, `ProductBundle`, `BundleRoot`, `SimpleBundle`, `Set`, `Kit` and `RootBundle` are all rejected.
**Fix:** Use `"productType": "SimpleProduct"` and `"scope": "SimpleProduct"` with the bundle root's product ID.

### Issue: Coupon promotion activation fails with "couldn't find mappings ... for these attributes: [shouldEvaluatePromotions, cartCouponCode, cartLineCouponCode]"
**Cause:** Required tag mappings are missing on the active rule library version.
**Fix:** Add `shouldEvaluatePromotions → ShouldEvaluatePromotions__std` and `cartLineCouponCode → SalesTransactionItemCouponCode__std`. The **New** button in the Custom Tag Mapping section still works on an *active* version, so you can add mappings without deactivating. With those two in place, activation succeeds even though `cartCouponCode` is unmapped.

### Issue: Rule library version can't be deactivated or cloned
**Cause:** "couldn't be deactivated/deleted as it's referenced Pricing Procedure". Clone also silently did nothing.
**Fix:** Add any missing mappings directly on the active version (see above). Best practice is to create all mappings before activating it in Step 4.

### Issue: Coupon code typed on the quote is rejected as "not eligible"
**Cause:** The header-level `cartCouponCode` mapping couldn't be saved ("these fields should be non null: [mappingName]"). The standard sales transaction context only has line-level coupon tags.
**Fix:** This was **unresolved** in the original run. For demos, show the coupon promotion through the line's **Promotions** tab toggle (manual promotion). To fully support code entry, you'd likely need to add a header-level coupon context tag to the context definition and map `cartCouponCode` to it. Validate this before promising code entry in a demo.

### Issue: Promotions workspace "New" form fails with "We couldn't create the promotion. Try again."
**Cause:** That form is the Commerce promotion form, which requires a web store.
**Fix:** Create promotions through the Global Promotions Management API (Steps 7–8). The record page's **View Configuration** opens the guided view of the created rule.

### Issue: Pricing procedure page shows "Unsupported Item"
**Cause:** The Billing console app can't render ExpressionSet pages, and there's no Pricing Procedures tab or App Launcher item.
**Fix:** Switch to the Revenue Cloud app, then open `/lightning/r/ExpressionSet/<ID>/view`.

### Issue: Rule Library field in the Promotion Execution element looks filled but isn't
**Cause:** Typing echoes the search text without selecting anything.
**Fix:** Click the result row itself (the text `<API> (GlobalPromotionsForRLM)`). The selection must show as a pill.

### Issue: Toggles or Setup Quick Find don't respond, or typed text is garbled
**Fix:** For toggles, use `playwright-cli eval "el => el.click()" <ref>`. For text fields, clear with Control+A and Backspace, then type again. Watch for a leftover leading character.

## Notes
- **Order matters:** settings → permissions → rule library with all mappings → activate version → pricing procedure step → Revenue Settings → promotions.
- Promotions are created **inactive**, so always set `IsActive=true`.
- Leave Exclusivity as "No" (the default) so promotions can stack.
- Include every PSM the product sells under. A line using a PSM that isn't in `rewardDetailsList` gets no discount.
- Promotions also feed amendments: an amended asset compares Last Transaction Price with List Price (script beat "Promotions on Amend").
- Related demo beats in the QuantumBit script: Browse Catalog promo badge, line Promotions tab, bundle coupon, and Promotions on Amend.
