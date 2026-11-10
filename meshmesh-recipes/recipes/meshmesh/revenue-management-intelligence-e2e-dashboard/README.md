# Revenue Management Intelligence — End-to-End Dashboard Setup

Post-spin MeshMesh recipe for a QuantumBit org that already has Revenue Cloud and Data 360. It installs the Tableau Next dashboards for DRO Analytics, Billing Analytics, and Subscription Analytics, plus the navigation tabs.

This folder is not a Salesforce DX project. There is no `sfdx-project.json` and no `cumulusci.yml`. The profile, tab, and flexipage files sit beside `recipe.md` for the MeshMesh agent. Do not run `sf project deploy start` against this folder as a package.

## Install this recipe into MeshMesh

`recipe.md` is the entry file. Every other file in this folder is part of the recipe. MeshMesh treats the upload as this recipe only when `recipe.md` is at the root of the folder or zip, beside those files.

1. Clone the repo, or download this folder from GitHub. Leave `recipe.md` at the top of the folder.
2. If you zip it, zip the files in this folder so `recipe.md` is at the root of the zip. A zip of a parent folder, with `recipe.md` one level down, will not install as this recipe.
3. In MeshMesh, open **Library**.
4. Choose **New → Reference → Upload Files**.
5. Drag in this folder, or the zip. Give it the name **Revenue Management Intelligence — End-to-End Dashboard Setup**.
6. Confirm the reference contains `recipe.md`, `config-defaults.json`, `sample-data-generator.md`, `revenue_management_intelligence.pdf`, and the profile, tab, and flexipage files listed under Components.
7. Share it with your workspace if other people should run it: open the reference, click **Share**, and set access to your organization. See [Creating and Sharing Recipes](https://docs.meshmesh.io/guides/recipes).
8. To run it, attach the recipe to a MeshMesh agent as a reference. The agent reads `recipe.md` and follows it. If more than one org is connected, tell it which org to use. The org must already exist, with Revenue Cloud set up and QuantumBit working.

Folder upload follows the same root-file rule MeshMesh uses for a skill pack: the entry file sits at the root of the upload, next to its supporting files. See [Creating Skills](https://docs.meshmesh.io/guides/creating-skills).

## What an agent should do with this repo

If you were asked to deploy this GitHub path into a Salesforce org:

1. Read this README and `recipe.md`. Tell the person this is a MeshMesh recipe, not a metadata package.
2. The deploy mechanism is the MeshMesh install above, then a MeshMesh agent run of `recipe.md`. Do not deploy the loose profile, tab, and flexipage files as an SFDX project. `recipe.md` says when those files are applied.
3. Confirm `sf` is installed before any org check. This recipe does not need CumulusCI. Python 3 (standard library) is used by the sample-data appendix.
4. Confirm the target org with `sf org display --target-org <alias> --json`. Report alias, username, org id, instance URL, and connected status. Do not print the access token. If the alias is missing, start `sf org login web` for the login host they named and pause for the browser login. If they gave an expected org id, it must match exactly. On a mismatch, stop.
5. There is no package dry-run. The plan is the phase list in `recipe.md`: Data 360 connection, connector access, data kit bundles, stream refresh, then one app install at a time. Show that plan before changing the org. Say that Pricing Analytics stays skipped.
6. After the org is confirmed, a MeshMesh agent may carry out `recipe.md`. Sample data generation is a data load. Stop and ask before running `sample-data-generator.md`.
7. Do every post-step `recipe.md` calls for, including the navigation tabs, and wait for each asynchronous bundle, refresh, and app install to finish before the next one. List any Setup click you cannot run.
8. Verify the three apps and their dashboards the way `recipe.md` specifies, and summarize what changed and what is left.

## Overview

The end state is working Tableau Next dashboards for DRO (order fulfillment) Analytics, Billing Analytics, and Subscription Analytics, plus dedicated navigation tabs.

The recipe follows Setup → Revenue Management Intelligence Setup, in order:

1. Data 360 connection
2. Connector access
3. Data kit bundles
4. Stream refresh
5. App installs, one at a time

It adds pre-flight checks, a data-readiness gate, install monitoring, and recovery for failures seen on a Release 264 org. The executable procedure is `recipe.md`. This README is the install guide.

## Components

| File | Purpose |
|------|---------|
| `recipe.md` | Steps the MeshMesh agent follows. |
| `config-defaults.json` | Bundle order, app order, permission names, and sample-data defaults. Names are resolved to ids in the target org. |
| `sample-data-generator.md` | Optional quote → order → invoice generator. Runs only with explicit approval. |
| `revenue_management_intelligence.pdf` | Salesforce Help excerpt for RMI setup. |
| `Admin.profile-meta.xml` | Tab visibility for the dashboard tabs. Applied when `recipe.md` says so. |
| `RMI_Order_Analytics.tab-meta.xml` | Order Analytics tab. |
| `RMI_Subscription_Analytics.tab-meta.xml` | Subscription Analytics tab. |
| `RMI_Order_Analytics.flexipage-meta.xml` | Order Analytics page. |
| `RMI_Subscription_Analytics.flexipage-meta.xml` | Subscription Analytics page. |

## Prerequisites

- A spun Revenue Cloud demo org, Release 264 or later (API 68.0), with Data 360 provisioned. QuantumBit is the usual target.
- System Administrator. If more than one org is connected, ask which one. Do not guess.
- Licenses called out in `recipe.md`: Data Cloud, Tableau Next Creator and Consumer, CRM Analytics Plus, and Revenue Cloud User. Billing Analytics also expects Revenue Cloud Advanced and Revenue Cloud Billing.
- A loaded Revenue Cloud catalog. The sample-data defaults use QuantumBit products.
- For optional sample data: accounts with a billing or shipping address and at least one contact.

## Known gotchas

- Do not install Pricing Analytics. Template `sfdc_internal__ngp` v1.1 fails at semantic-model upsert. Install it only when `recipe.md` shows the template version is greater than 1.1.
- Finish and verify each phase before the next. Do not deploy two data bundles, or install two apps, at the same time.
- Bundle deploys, stream refreshes, Data Cloud sync, and app installs are asynchronous. Poll them. Do not assume they finished.
- If a call returns `INVALID_SESSION_ID`, refresh the MeshMesh org connection and resume from the last verified step. The org alias can change after a refresh.
- Do not put `{{ORG_ALIAS}}` or other double-brace placeholders inside a shell command. Substitute real values first.

## Scope and limitations

- DRO, Billing, and Subscription analytics only. Pricing Analytics is out of scope until the template fix has shipped.
- Sample data is optional and needs explicit approval. It is a data load, not part of the metadata.
- The profile and page files are recipe payload. They are not templates for the foundations UX assembly (`templates/` or `unpackaged/post_ux/`).
