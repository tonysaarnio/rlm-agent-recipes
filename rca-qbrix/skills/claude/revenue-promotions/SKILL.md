---
name: revenue-promotions
description: >-
  RCA Qbrix post-spin skill: set up, verify and troubleshoot Revenue Cloud Global
  Promotions on quotes, by hand, in an org that is already built and pricing QuantumBit
  quotes. Covers the Global Promotions Management settings, licenses and permission sets,
  a promotions rule library with its Custom Tag Mappings, the Promotion Execution step in
  the pricing procedure, Promotions for Transactions in Revenue Settings, and automatic
  and coupon promotions created through the Global Promotions Management API. Use for
  "set up promotions", an automatic or coupon promotion, a promotion that does not apply
  on a quote line, or a coupon promotion that will not activate. Not for org creation or
  the base build.
---

# Revenue Promotions — Global Promotions on Quotes (Automatic + Coupon)

An RCA Qbrix post-spin skill. Use it to turn on Revenue Cloud **Global Promotions** in an
org where they are off, then create promotions that apply at pricing. An **automatic**
promotion discounts a quote line on its own. A **coupon** (manual) promotion is one a
seller switches on from the line's Promotions tab.

It is the skill form of the MeshMesh recipe
`rca-qbrix/recipes/meshmesh/revenue-cloud-promotions-automatic-coupon/recipe.md`, with what
the run taught. The router for RCA Qbrix bundles is `.cursor/skills/rca-qbrix/SKILL.md`,
which Claude Code reaches as `.claude/skills/rca-qbrix`. Run this bundle from where it sits;
don't copy it into `.claude/skills/` or `.cursor/skills/`.

It assumes `prepare_rlm_org` has already built the org, and it never runs or changes that
build. Run the Discovery queries first and do only the steps they show are missing.

> **Pinned to Release 264 / API v68.0.** The procedure in
> [`setup-walkthrough.md`](setup-walkthrough.md) was run end to end on a release 264
> QuantumBit org (`salesforcemeshmeshtest-6pswgq`, November 2026). Two differences surfaced
> on a fresh scratch org, and the walkthrough covers both: the Basic license pair, and the
> `enableGlobalPromotionsForRevenueCloud` setting, which no Setup switch sets.

> ⚠️ **Irreversible.** Global Promotions Management cannot be turned off once it is on.
> Get the org owner's explicit approval before step 1, on every org. Also tell them that
> Promotion Execution in the default pricing procedure can change other pricing beats
> (derived pricing such as Software Maintenance), and that those need a re-test.

## Running it in Claude Code

Run `sf` commands with the Bash tool. Do the UI-only steps by driving the pages with a
browser tool the session has, such as a Playwright MCP server. The playwright-cli tips in
[`browser-automation-appendix.md`](browser-automation-appendix.md) are optional. If that
doesn't work, give the user the step from [`setup-walkthrough.md`](setup-walkthrough.md)
and wait for them to confirm it is done before going on.

## Quick Rules

1. **Post-spin only.** Start once the org exists, Revenue Cloud is set up, and QuantumBit
   quotes price. Ask which org to use; don't assume an alias. Run Discovery first and skip
   any step that is already done.
2. **Follow the order.** Settings → licenses and permission sets → rule library with
   **all** its tag mappings → activate the rule library version → Promotion Execution in
   the pricing procedure → Promotions for Transactions in Revenue Settings → promotions.
   Each step needs the one before it.
3. **Create promotions through the API**, `POST /services/data/v68.0/global-promotions-management/promotions`.
   The API compiles the promotion's rule into the rule library. A Promotion record loaded
   any other way never applies: SFDMU, an sObject insert, or the Commerce-style Promotions
   workspace form.
4. **Use `SimpleProduct` for `productType` and `scope`, bundle roots included.** The API
   rejects every bundle variant.
5. **Add one `rewardDetailsList` entry per selling model on the product.** A line priced
   under a selling model that is missing from the list gets no discount.
6. **Activate after creating, inside the window.** The API creates promotions inactive;
   set `IsActive = true`. A coupon promotion activates only once the `shouldEvaluatePromotions`
   and `cartLineCouponCode` tag mappings exist. A promotion applies only while today falls
   inside its window.
7. **Make every tag mapping before activating the rule library version.** Once a pricing
   procedure references the version, it can't be deactivated or cloned. New mappings
   can still be added to an active version.
8. **Check `enableGlobalPromotionsForRevenueCloud` after step 1.** The Setup switches don't
   set it on a fresh org. Until it is `true`, the `RevPromotionsManagement` permission set
   doesn't exist and the Context Tag search on the rule library version stays empty.

## DO NOT

- **DO NOT** turn on Global Promotions Management without the org owner's explicit
  approval. It is permanent.
- **DO NOT** run this skill during org creation, scratch-org spin or `prepare_rlm_org`, and
  don't run `prepare_rlm_org` or any of its flows from it. It is post-spin: the base build
  must already be finished.
- **DO NOT** hand-write the Promotion Execution step in expression set XML. Use the
  Pricing Procedure builder (walkthrough step 5).
- **DO NOT** load `Promotion` records with SFDMU or a plain sObject insert. Use the API.
- **DO NOT** activate the rule library version before all tag mappings exist, if you can
  avoid it. A referenced version can't be deactivated to fix one.
- **DO NOT** promise a demo where a coupon code is typed on the quote header. The header
  `cartCouponCode` mapping has no tag in the standard sales transaction context, and that
  path is unresolved (see [`troubleshooting.md`](troubleshooting.md)). Show the coupon
  promotion from the line's Promotions tab instead.
- **DO NOT** pass `access_token` to `sf`. Use the org username or alias as `--target-org`.

## Entry Conditions

| Task | Use this skill? | Notes |
|------|-----------------|-------|
| Set up promotions on a built QuantumBit org that doesn't have them | Yes | Discovery, then the walkthrough from the first missing step. |
| Add, change or recreate a promotion or coupon | Yes | Walkthrough steps 7–8, with the request templates in this folder. |
| A promotion doesn't apply, or a coupon promotion won't activate | Yes | [`troubleshooting.md`](troubleshooting.md). |
| The org isn't built yet, or QuantumBit quotes don't price | No | Finish the base build first (`prepare_rlm_org`, cci-orchestration skill). |
| Edit the Promotion Execution step or where it sits in the procedure | Partly | Capture a new overlay (`.cursor/skills/expression-sets/authoring-and-overlays.md`). |
| Find or add a context tag (for example a header coupon tag) | Partly | `.cursor/skills/context-service/SKILL.md`. |

## Discovery

Read the org's state before changing it. Replace `<sf_alias>` with the SF CLI alias or
username; the CCI alias `beta` maps to `rlm-base__beta`.

```bash
# Licenses: GlobalPromotionsMgmtBasicPsl (step 2) and RevPromotionsManagementPsl (the base build assigns it)
sf data query --query "SELECT MasterLabel, DeveloperName, TotalLicenses, UsedLicenses FROM PermissionSetLicense WHERE DeveloperName IN ('GlobalPromotionsMgmtBasicPsl','RevPromotionsManagementPsl')" --target-org <sf_alias>

# Permission sets. RevPromotionsManagement exists only once enableGlobalPromotionsForRevenueCloud is true
sf data query --query "SELECT Name, Label FROM PermissionSet WHERE Name IN ('PromotionDesignerBasic','PromotionViewer','RevPromotionsManagement')" --target-org <sf_alias>

# Promotions rule libraries and their versions (UsageType is the discriminator)
sf data query --query "SELECT Id, Name, ApiName, ContextDefinitionName FROM RuleLibrary WHERE UsageType = 'GlobalPromotionsForRLM'" --target-org <sf_alias>
sf data query --query "SELECT Id, ApiName, VersionNumber, Status, RuleLibrary.ApiName FROM RuleLibraryVersion WHERE RuleLibrary.UsageType = 'GlobalPromotionsForRLM'" --target-org <sf_alias>

# Promotions and coupons
sf data query --query "SELECT Id, Name, IsActive, IsAutomatic, PriorityNumber, StartDateTime, EndDateTime FROM Promotion" --target-org <sf_alias>
sf data query --query "SELECT CouponCode, Status, Type, Promotion.Name FROM Coupon" --target-org <sf_alias>

# Every selling model on a target product (one reward entry each)
sf data query --query "SELECT ProductSellingModel.Id, ProductSellingModel.Name FROM ProductSellingModelOption WHERE Product2.StockKeepingUnit = '<SKU>'" --target-org <sf_alias>

# Context tags a mapping can use (substring match on the tag name)
python scripts/context_service/definition/trace_context.py --target-org <sf_alias> \
  --developer-name <CONTEXT_DEFINITION> --tag CouponCode
```

The Setup toggles can be read as metadata, `IndustriesUnifiedPromotionsSettings`. Retrieve it
into a metadata directory, which works from anywhere:

```bash
sf project retrieve start --metadata "Settings:IndustriesUnifiedPromotions" --target-org <sf_alias> --target-metadata-dir /tmp/promo-settings --unzip
```

Step 1's switches set `enableUnifiedPromotions`, `enableGlobalPromotionsEvaluation` and
`enableGlobalPromotionsProductCatalogManagement`. `enableGlobalPromotionsForRevenueCloud`
must also be `true`. It was on the meshmesh org; on a fresh scratch org no Setup switch
sets it, including Promotions for Transactions on Revenue Settings, and step 1b deploys it.

The tag mappings have no API, metadata or sObject surface that this repo has found. The
retrieved `RuleLibraryDefinition` names the mappings (`cartLineCouponCode`) but not the tags
they map to, so read them on the rule library version's Custom Tag Mapping card. Promotions
for Transactions is not in the retrieved `RevenueManagementSettings`; read it on Revenue
Settings.

### Where this differs from the recorded run

| Recorded run (meshmesh) | This skill | Why |
|-------------------------|------------|-----|
| API v66.0 in the commands | v68.0 | The repo's pinned API version |
| `GlobalPromotionsManagementPsl` and `PromotionDesigner` | `GlobalPromotionsMgmtBasicPsl` and `PromotionDesignerBasic` | The recipe's pair comes with Loyalty Management. The Basic pair is the Revenue Cloud add-on, and the only one the repo's scratch orgs have |
| `enableGlobalPromotionsForRevenueCloud` already on | Deployed in step 1b | No Setup switch sets it on a fresh org |
| Fixed window, 1–30 November 2026 | Starts today | A fixed window stops applying once it passes |

The recorded run's tag-mapping helper uses `grep -oP`, which macOS's grep doesn't have;
see [`browser-automation-appendix.md`](browser-automation-appendix.md).

## Examples

### Worked example — QuantumBit, as recorded on the meshmesh org

Substitute your own names. On `salesforcemeshmeshtest-6pswgq` (release 264):

- Rule library `QB Promotions` (`QB_Promotions`) on `RLM_SalesTransactionContext`, with the
  10 tag mappings, version Active.
- **QuantumBit Launch Promotion**: automatic, priority 1, 10% off QuantumBit Subscription
  on Term Annual, Term Monthly, Evergreen Monthly and Evergreen Annual.
- **QBLAUNCH Coupon Promotion**: manual, priority 2, 10% off the QuantumBit Complete
  Solution bundle root (`productType` `SimpleProduct`) on Term Annual, Term Monthly,
  Evergreen Monthly and One-Time. Coupon `QBLAUNCH`, Single-Code, Active.
- Result: Browse Catalogs shows a **1 Promotion** badge on QuantumBit Subscription. Its
  quote line goes from $360 list to $324 net, and the line's Promotions tab shows the
  promotion and its end date.

### Add a promotion on another product

1. Query every selling model on the product (Discovery).
2. Copy `promotion-automatic-template.json` (or `promotion-coupon-template.json` for a
   manual promotion). Fill in the placeholders, give it a `priorityNumber` no other
   promotion uses, add one `rewardDetailsList` entry per selling model, start the window
   today or earlier, and remove `_notes`.
3. POST it, activate it, and for a coupon promotion create its coupon code, as in
   walkthrough steps 7–8. Then run the checks below.

## Validation Checks

```bash
sf data query --query "SELECT Name, IsActive, IsAutomatic, StartDateTime, EndDateTime FROM Promotion" --target-org <sf_alias>
sf data query --query "SELECT CouponCode, Status, Promotion.Name FROM Coupon" --target-org <sf_alias>
sf data query --query "SELECT ApiName, Status FROM RuleLibraryVersion WHERE RuleLibrary.ApiName = '<RULE_LIBRARY_API>'" --target-org <sf_alias>
```

- Every promotion shows `IsActive = true`, and today falls inside its window.
- The coupon shows `Active`, and the rule library version shows `Active`.
- On a quote, Browse Catalogs shows the promotion badge on the target product. Adding the
  product drops the line's net price by the promotion's percentage.
- The line's Promotions tab lists the automatic promotion as applied and the coupon
  promotion as eligible.
- Re-test derived-pricing beats (for example Software Maintenance) on the same quote.

## Files in this bundle

| File | Read when |
|------|-----------|
| [`setup-walkthrough.md`](setup-walkthrough.md) | Setting up promotions by hand, or repairing one step |
| [`troubleshooting.md`](troubleshooting.md) | A promotion doesn't apply, activation fails, or a setup page won't respond |
| [`browser-automation-appendix.md`](browser-automation-appendix.md) | Optional: driving the UI steps with playwright-cli (the recorded run's helper and tips) |
| `promotion-automatic-template.json` | The request body for an automatic promotion |
| `promotion-coupon-template.json` | The request body for a coupon (manual) promotion |
