# RCA Qbrix skills and recipes

Holding repository for post-spin RCA Qbrix bundles. The `rca-qbrix/` directory uses the same path it will have in [rlm-base-dev](https://github.com/bgaldino/rlm-base-dev), so it can be copied in later without renaming.

These skills and recipes run after a demo org already exists and Revenue Cloud is already set up. QuantumBit is the usual target. They cover follow-on work such as promotions, Revenue Management Intelligence dashboards, and Collections with payment promises and dunning. Org creation and the base Revenue Cloud build stay in rlm-base-dev.

Copy `rca-qbrix/` to the root of rlm-base-dev. Leave this README here; rlm-base-dev already has its own. The router that agents load is `.cursor/skills/rca-qbrix/SKILL.md` in that repository, not a file in this one.

When sending it, add this block to the tree in `docs/references/repository-layout.md`, between `docs/salesforce/` and `orgs/`:

```text
├── rca-qbrix/                  # Post-spin RCA Qbrix skills and recipes (not the live skill catalog)
│   ├── recipes/meshmesh/       # MeshMesh RCA Qbrix recipes; recipe.md at each bundle root
│   └── skills/                 # Exported Claude and Cursor RCA Qbrix skills (SKILL.md)
```

| Kind | Path | Entry file |
|------|------|------------|
| RCA Qbrix recipe (MeshMesh) | `rca-qbrix/recipes/meshmesh/<name>/` | `recipe.md` |
| RCA Qbrix skill (Claude) | `rca-qbrix/skills/claude/<name>/` | `SKILL.md` |
| RCA Qbrix skill (Cursor) | `rca-qbrix/skills/cursor/<name>/` | `SKILL.md` |

The CumulusCI `qbrix` feature flag is the xDO base layer for an org build. It is not this directory.
