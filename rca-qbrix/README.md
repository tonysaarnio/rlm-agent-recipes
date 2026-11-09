# RCA Qbrix skills and recipes

Post-spin bundles for a demo org that already exists and already has Revenue Cloud set up. QuantumBit is the usual target. Org creation and the base Revenue Cloud build stay in `prepare_rlm_org`.

RCA Qbrix skills and recipes are not the skills agents load from `.cursor/skills/`. They are exported bundles stored here so an agent can follow them after spin. The router for this library is the normal skill `.cursor/skills/rca-qbrix/SKILL.md`.

| Kind | Path | Entry file |
|------|------|------------|
| RCA Qbrix recipe (MeshMesh) | `rca-qbrix/recipes/meshmesh/<name>/` | `recipe.md` |
| RCA Qbrix skill (Claude) | `rca-qbrix/skills/claude/<name>/` | `SKILL.md` |
| RCA Qbrix skill (Cursor) | `rca-qbrix/skills/cursor/<name>/` | `SKILL.md` |

Keep every file the entry file names beside that entry file. Metadata that ships inside a bundle stays in the bundle. UX metadata for the org build stays in `templates/`.

The CumulusCI `qbrix` feature flag is the xDO base layer for an org build. It is not this directory.
