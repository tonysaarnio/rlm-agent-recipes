# Revenue Promotions — Troubleshooting

Symptoms, causes and fixes for Global Promotions setup, recorded on release 264: from the
manual run on the meshmesh org, and from setting promotions up on a fresh scratch org.

## Promotions and activation

### No `RevPromotionsManagement` permission set, or the Context Tag search offers nothing

**Cause:** `IndustriesUnifiedPromotionsSettings.enableGlobalPromotionsForRevenueCloud` is
`false`. No Setup switch sets it on a fresh org, Promotions for Transactions included.
**Fix:** deploy it (walkthrough step 1b), then query the permission set again and reopen
the rule library version page.

### "Permission Set Licenses were not found: GlobalPromotionsManagementPsl", or no `PromotionDesigner`

**Cause:** that license and permission set come with Loyalty Management. A Revenue Cloud org,
and every scratch org built from this repo's shapes, has Global Promotions Management
**Basic** instead.
**Fix:** assign `GlobalPromotionsMgmtBasicPsl` and `PromotionDesignerBasic` (walkthrough
step 2). The recipe's pair works only where Loyalty Management is licensed.

### "Invalid value for Product type error: Bundle" when creating a bundle promotion

**Cause:** the promotions API accepts only `SimpleProduct` here. `Bundle`, `BundleProduct`,
`ProductBundle`, `BundleRoot`, `SimpleBundle`, `Set`, `Kit` and `RootBundle` are all rejected.
**Fix:** use `"productType": "SimpleProduct"` and `"scope": "SimpleProduct"` with the bundle
root's product Id.

### Coupon promotion activation fails: "couldn't find mappings ... for these attributes: [shouldEvaluatePromotions, cartCouponCode, cartLineCouponCode]"

**Cause:** the rule library version is missing required tag mappings.
**Fix:** add `shouldEvaluatePromotions → ShouldEvaluatePromotions__std` and
`cartLineCouponCode → SalesTransactionItemCouponCode__std`. The Custom Tag Mapping card's
**New** button works on an *active* version, so there's no need to deactivate. With those
two mapped, activation succeeds even though `cartCouponCode` stays unmapped.

### A promotion is active but the quote line isn't discounted

Check these in order:

1. **Window:** today must fall between `StartDateTime` and `EndDateTime`. Change the dates,
   or delete the promotion and create it again with a fresh window.
2. **Selling model:** the line's selling model must be in the reward's `rewardDetailsList`.
   Compare it with the product's `ProductSellingModelOption` rows.
3. **Pricing procedure:** the default pricing procedure in Revenue Settings must contain the
   Promotion Execution step, and its version must be active. A redeploy of the `force-app`
   procedure (`activate_and_deploy_expression_sets`) replaces the definition without the
   step; add it again (walkthrough step 5).
4. **Revenue Settings:** Promotions for Transactions must be on, with this rule library
   selected.
5. **Pricing source:** the step skips lines whose `ItemPricingSource` is `LastTransaction`,
   so a line carried over from an asset keeps its earlier price.
6. **Created outside the API:** a Promotion loaded with SFDMU or a plain insert has no
   compiled rule and never applies. Delete it and create it through the API.

### Rule library version can't be deactivated or cloned

**Cause:** "couldn't be deactivated/deleted as it's referenced Pricing Procedure". Clone did
nothing either.
**Fix:** add missing mappings straight on the active version (above). Make all mappings
before the first activation.

### Coupon code typed on the quote is rejected as "not eligible"

**Cause:** the header-level `cartCouponCode` mapping couldn't be saved ("these fields should
be non null: [mappingName]"). The standard sales transaction context has line-level coupon
tags only.
**Status:** unresolved. For demos, switch the coupon promotion on from the line's
**Promotions** tab. Supporting code entry would likely need a header-level coupon tag in
the context definition (context-service skill), mapped to `cartCouponCode`. Verify that on
an org before promising code entry.

### Promotions workspace "New" fails: "We couldn't create the promotion. Try again."

**Cause:** that form is the Commerce promotion form, and it needs a web store.
**Fix:** create promotions through the API (walkthrough steps 7–8).
The created record's **View Configuration** opens a guided view of its rule.

### Pricing procedure page shows "Unsupported Item"

**Cause:** the Billing console app can't render expression set pages, and there is no
Pricing Procedures tab or App Launcher item.
**Fix:** switch to the Revenue Cloud app, then open `/lightning/r/ExpressionSet/<ID>/view`.

### The Promotion Execution element's Rule Library looks filled in but isn't

**Cause:** typing only echoes the search text; nothing is selected.
**Fix:** click the result row (`<API> (GlobalPromotionsForRLM)`). It is selected when it
shows as a pill.

### A Setup switch or Quick Find doesn't respond, or typed text comes out garbled

**Fix:** for a switch, click its label or input element directly; the faux container in
front of it can swallow the click. For a text box, select all and delete, then type again,
and watch for a stray leading character.

### The Context Tag box shows no options

**Cause:** first, `enableGlobalPromotionsForRevenueCloud` is off (top of this page). The box
also searches on keystrokes, so a value pasted or set by script may return nothing. On a
fresh scratch org it was still sometimes empty in a headless browser with the setting on;
no cause was found, and typing more slowly or waiting longer didn't change it.
**Fix:** check the setting, then type one character at a time. If it is still empty,
cancel the dialog, reload the page and try again. Options match the tag name
case-insensitively; check the spelling against the context definition with
`trace_context.py --tag`.

### New Rule Library doesn't offer the Global Promotions Management usage type

**Cause:** `GlobalPromotionsForRLM` is offered only once Global Promotions Management is on.
A library with the same API Name under another usage type also blocks the save.
**Fix:** do walkthrough step 1 first. Rename or remove a clashing library, or choose
another API Name.

### A mapping already points at a different tag

**Fix:** edit or delete that row on the version's Custom Tag Mapping card, then add it with
the tag from walkthrough step 4.
