# Revenue Cloud Promotions (Automatic + Coupon)

Post-spin MeshMesh recipe for a QuantumBit org that already prices quotes. It turns on Global Promotions and creates one automatic promotion and one coupon promotion.

This folder is not a Salesforce DX project. There is no `sfdx-project.json` and no `cumulusci.yml`. Do not run `sf project deploy start` against this folder.

## Install this recipe into MeshMesh

`recipe.md` is the entry file. The JSON templates next to it are part of the recipe. MeshMesh treats the upload as this recipe only when `recipe.md` is at the root of the folder or zip, beside those files.

1. Clone the repo, or download this folder from GitHub. Leave `recipe.md` at the top of the folder.
2. If you zip it, zip the files in this folder so `recipe.md` is at the root of the zip. A zip of a parent folder, with `recipe.md` one level down, will not install as this recipe.
3. In MeshMesh, open **Library**.
4. Choose **New → Reference → Upload Files**.
5. Drag in this folder, or the zip. Give it the name **Revenue Cloud Promotions (Automatic + Coupon)**.
6. Confirm the reference contains `recipe.md`, `promotion-automatic-template.json`, and `promotion-coupon-template.json`.
7. Share it with your workspace if other people should run it: open the reference, click **Share**, and set access to your organization. See [Creating and Sharing Recipes](https://docs.meshmesh.io/guides/recipes).
8. To run it, attach the recipe to a MeshMesh agent as a reference. The agent reads `recipe.md` and follows it. Tell it which org to use. The org must already exist, with Revenue Cloud set up and QuantumBit working.

Folder upload follows the same root-file rule MeshMesh uses for a skill pack: the entry file sits at the root of the upload, next to its supporting files. See [Creating Skills](https://docs.meshmesh.io/guides/creating-skills).

## What an agent should do with this repo

If you were asked to deploy this GitHub path into a Salesforce org:

1. Read this README and `recipe.md`. Tell the person this is a MeshMesh recipe, not a metadata package.
2. The deploy mechanism is the MeshMesh install above, then a MeshMesh agent run of `recipe.md`. Do not invent an SFDX deploy of the JSON files.
3. Confirm `sf` is installed before any org check. This recipe does not need CumulusCI.
4. Confirm the target org with `sf org display --target-org <alias> --json`. Report alias, username, org id, instance URL, and connected status. Do not print the access token. If the alias is missing, start `sf org login web` for the login host they named and pause for the browser login. If they gave an expected org id, it must match exactly. On a mismatch, stop.
5. There is no metadata dry-run. The plan is the step list in `recipe.md`. Show that plan before changing the org.
6. After the org is confirmed, a MeshMesh agent may carry out the setup steps in `recipe.md`. Creating promotion and coupon records is a data load. Stop and ask before those creates.
7. Do every post-step `recipe.md` lists: license and permission-set assignment, rule library and tag mappings, pricing-procedure change, Revenue Settings, then the two promotions. List any UI step you cannot run.
8. Run the verification queries in `recipe.md` and summarize what changed and what is left.

Stop before Step 1 of `recipe.md`. Turning on Global Promotions Management cannot be undone.

## Overview

Use this after `prepare_rlm_org` has already built the org. It is the "Promotions (requires Promotions post-spin setup)" demo beat.

When it finishes:

- Browse Catalogs shows a **1 Promotion** badge on the targeted products.
- The automatic promotion applies at pricing and shows on the quote line's **Promotions** tab.
- The coupon promotion can be turned on from that same tab.

The executable procedure is `recipe.md`. This README is the install guide.

## Components

| File | Purpose |
|------|---------|
| `recipe.md` | Steps the MeshMesh agent follows. |
| `promotion-automatic-template.json` | Body for the automatic promotion API create. Fill the placeholders, one reward row per product selling model. |
| `promotion-coupon-template.json` | Body for the manual coupon promotion. `isAutomatic` is false. |

## Prerequisites

- A spun org with Revenue Cloud Advanced and Context Service on. QuantumBit is the usual target.
- System Administrator access. The agent must use the org alias literally in commands.
- Permission set license **Revenue Management Promotions Run Time** (`RevPromotionsManagementPsl`) present in the org.
- The active pricing procedure and its sales transaction context. In QuantumBit those are `RLM_DefaultPricingProcedure` and `RLM_SalesTransactionContext`.
- Product ids for each promotion target, and every product selling model on those products.
- Browser access to the same org. Several steps are Setup UI only.

## Known gotchas

- Global Promotions Management cannot be turned off after Step 1. Get approval before that step. Adding promotion execution to the default pricing procedure can change derived-pricing behavior, such as Software Maintenance. Re-test those beats afterward.
- Create the promotions through the Global Promotions Management API. The Promotions workspace form expects a web store and fails with "We couldn't create the promotion."
- For a bundle, the API still wants `"productType": "SimpleProduct"` and the bundle root's product id.
- Create all 10 rule-library tag mappings before activating the rule library version. A version referenced by an active pricing procedure cannot be deactivated later.
- Header-level coupon code entry was unresolved in the original run. Demo the coupon from the quote line's Promotions tab.
- Promotions are created inactive. Set `IsActive` to true. The current date must fall inside the promotion window.
- The Billing console shows "Unsupported Item" on expression set pages. Switch to the Revenue Cloud app before editing the pricing procedure.

## Scope and limitations

- One automatic promotion and one coupon promotion, on products you name. It does not load a full promotion catalog.
- Coupon code typed on the quote header is not a finished demo path. Use the line-level Promotions toggle.
- Record creates in Steps 7 and 8 of `recipe.md` need explicit approval. They are data loads, not metadata deploys.
