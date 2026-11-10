# MeshMesh recipes

Post-spin bundles for a demo org that already exists and already has Revenue Cloud set up. QuantumBit is the usual target. Org creation and the base Revenue Cloud build stay in `prepare_rlm_org`.

MeshMesh recipes are not the skills agents load from `.cursor/skills/`. They are exported bundles stored here so an agent can follow them after spin. The router for this library is the normal skill `.cursor/skills/meshmesh-recipes/SKILL.md`.

| Kind | Path | Entry file |
|------|------|------------|
| MeshMesh recipe | `meshmesh-recipes/recipes/meshmesh/<name>/` | `recipe.md` |
| Claude skill | `meshmesh-recipes/skills/claude/<name>/` | `SKILL.md` |
| Cursor skill | `meshmesh-recipes/skills/cursor/<name>/` | `SKILL.md` |

Keep every file the entry file names beside that entry file. Metadata that ships inside a bundle stays in the bundle. UX metadata for the org build stays in `templates/`.

The CumulusCI `qbrix` feature flag is the xDO base layer for an org build. It is not this directory.
