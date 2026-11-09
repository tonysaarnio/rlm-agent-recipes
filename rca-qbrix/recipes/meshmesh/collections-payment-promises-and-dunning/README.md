# Collections, Payment Promises, and Dunning

Post-spin MeshMesh recipe for an org that already has Revenue Cloud Billing. It sets up collection plans, the Collections console, payments, saved payment methods, payment promises, payment runs, and dunning orchestration.

This folder is not a Salesforce DX project. There is no `sfdx-project.json` and no `cumulusci.yml`. The XML, Apex, and CSV files sit beside `recipe.md` so the MeshMesh agent can deploy them in the order `recipe.md` specifies. Do not run `sf project deploy start` against this folder as a package.

## Install this recipe into MeshMesh

`recipe.md` is the entry file. Every other file in this folder is part of the recipe. MeshMesh treats the upload as this recipe only when `recipe.md` is at the root of the folder or zip, beside those files.

1. Clone the repo, or download this folder from GitHub. Leave `recipe.md` at the top of the folder.
2. If you zip it, zip the files in this folder so `recipe.md` is at the root of the zip. A zip of a parent folder, with `recipe.md` one level down, will not install as this recipe.
3. In MeshMesh, open **Library**.
4. Choose **New → Reference → Upload Files**.
5. Drag in this folder, or the zip. Give it the name **Collections, Payment Promises, and Dunning**.
6. Confirm the reference contains `recipe.md` and every file listed under Components.
7. Share it with your workspace if other people should run it: open the reference, click **Share**, and set access to your organization. See [Creating and Sharing Recipes](https://docs.meshmesh.io/guides/recipes).
8. To run it, attach the recipe to a MeshMesh agent as a reference. The agent reads `recipe.md` and follows it. Tell it which org to use. Billing Guided Setup must already be done, and QuantumBit (or the billing demo org) must already be working.

Folder upload follows the same root-file rule MeshMesh uses for a skill pack: the entry file sits at the root of the upload, next to its supporting files. See [Creating Skills](https://docs.meshmesh.io/guides/creating-skills).

## What an agent should do with this repo

If you were asked to deploy this GitHub path into a Salesforce org:

1. Read this README and `recipe.md`. Tell the person this is a MeshMesh recipe, not a metadata package.
2. The deploy mechanism is the MeshMesh install above, then a MeshMesh agent run of `recipe.md`. That procedure deploys individual metadata files in a required order, then does UI installs. Do not point `sf project deploy start` at this folder.
3. Confirm `sf` is installed before any org check. This recipe does not need CumulusCI. Some Collections metadata is downloaded from `bgaldino/rlm-base-dev` during the run, as `recipe.md` describes.
4. Confirm the target org with `sf org display --target-org <alias> --json`. Report alias, username, org id, instance URL, and connected status. Do not print the access token. If the alias is missing, start `sf org login web` for the login host they named and pause for the browser login. If they gave an expected org id, it must match exactly. On a mismatch, stop. This is not a production install.
5. Show the plan in `recipe.md` before changing the org. Call out the irreversible toggles and the data creates.
6. Metadata deploys that `recipe.md` spells out (settings bundle, orchestration context mapping, mock gateway on a test org, Collections tier from rlm-base-dev) may proceed after the org is confirmed. Creating collection plans, saved payment methods, payment promises, and payment runs is a data load. Stop and ask before those creates.
7. Do every post-step `recipe.md` lists: permission sets, Company Information, Salesforce Go dunning install, email-template folder move, merchant account or mock gateway, then plans, promises, payment runs, and dunning timing. Stripe onboarding cannot be automated. Say so and leave it for a person.
8. Run the verification queries in `recipe.md` and summarize what changed and what is left.

Stop and ask before Step 4 of `recipe.md`. Timeline and dunning toggles cannot be turned off afterward.

## Overview

When it finishes, a billing org can:

- Open collection plans and plan items for overdue invoices in the Billing - Collections app.
- Take a payment promise against a saved payment method and process it with a payment run.
- Start dunning orchestration from the plan, with timed reminder and suspension emails.

Validated on a Revenue Cloud Billing org (API 68.0) in November 2026. The executable procedure is `recipe.md`. This README is the install guide.

## Components

| File | Purpose |
|------|---------|
| `recipe.md` | Steps the MeshMesh agent follows, including deploy order and troubleshooting. |
| `settings-bundle.xml` | Timeline, DRO, dunning, and Salesforce Payments settings. Split and deploy as `recipe.md` says. API 68.0. |
| `BillingOrchPlanCtxMapping.orchestrationPlanCtxMapping.xml` | Billing orchestration context mapping. Required or Initiate Dunning fails. |
| `DetermineCaseReasonAndRelatedAttributes.decisionMatrixDefinition-meta.xml` | Case-reason decision matrix definition. |
| `decision_matrix_case_rows.csv` | Matrix row content. The seed script hashes these rows. |
| `Collection_Console_App.timelineObjectDefinition-meta.xml` | Collection console timeline. |
| `RLM_MockPaymentGatewayAdapter.cls` | Test-org payment adapter. Approves every request. No callouts. |
| `RLM_MockPaymentGateway.namedCredential.xml` | Named credential for the mock gateway. Anonymous, no authentication, endpoint `https://mock-gateway.invalid`. |
| `RLM_MockGatewayProvider.paymentGatewayProvider.xml` | Mock gateway provider. |
| `saved-payment-method-template.json` | `SavedPaymentMethod` body. The promise flow does not list a `CardPaymentMethod` alone. |

## Prerequisites

- Revenue Cloud Billing already turned on, with default billing treatment, tax treatment, legal entity, and payment term (Billing Guided Setup steps 1–6).
- Permission set licenses present: `RevLifecycleMgmtBillingPsl`, `BillingAdvancedPsl`, `CollectionsAndRecoveryPsl`, `DynamicRevenueOrchestratorUserPsl`.
- Subscription Management off. Billing cannot run beside it.
- System Administrator. Browser access for Salesforce Go, Company Information, and Stripe.
- Access to `https://raw.githubusercontent.com/bgaldino/rlm-base-dev/main/` for the Collections metadata `recipe.md` downloads.

## Known gotchas

- Timeline, Collection Plan Event Timeline, and Automate Dunning Orchestration cannot be turned off after the settings deploy. Confirm first.
- Enabling dunning in metadata does not create `BillingOrchPlanCtxMapping`. Without Step 5 of `recipe.md`, Initiate Dunning fails with `SF_DRO_ORCH_IA_00016`.
- The dunning email templates land in the installing admin's private folder. Move them to a public folder or other users' runs cannot use them.
- Stripe onboarding does not load in an automation browser. A person finishes it. Use the mock gateway only on a test or demo org.
- A `CardPaymentMethod` from the tokenize API does not appear in the promise flow. Create the `SavedPaymentMethod` from the template.
- Cancel the draft payment schedule Billing created at invoice posting before the first promise, or the new schedule is rejected.
- Shipped dunning steps have no timing, and risk-group conditions did not gate groups in testing. Set timing in `recipe.md` and test a low-risk plan and a high-risk plan. Do not delete the shipped cross-group dependency.
- Only one orchestration plan per collection plan. A second Initiate Dunning returns `SF_DRO_ORCH_IA_00018`.
- Remove the mock gateway, mock saved payment methods, and test plans before any production use.

## Scope and limitations

- Test and demo orgs. Not a production payments install.
- The mock gateway approves every charge. It is for proving promises and payment runs without a processor.
- Creating plans, promises, saved payment methods, and payment runs writes data. Those steps need explicit approval.
- Industries Collections & Recovery features are separate from Billing Collections. This recipe sets up the billing path.
