# MeshMesh recipes

Holding repository for post-spin MeshMesh recipes. The `meshmesh-recipes/` directory uses the same path it will have in [rlm-base-dev](https://github.com/bgaldino/rlm-base-dev), so it can be copied in later without renaming.

These recipes run after a demo org already exists and Revenue Cloud is already set up. QuantumBit is the usual target. They cover follow-on work such as promotions, Revenue Management Intelligence dashboards, and Collections with payment promises and dunning. Org creation and the base Revenue Cloud build stay in rlm-base-dev.

Copy `meshmesh-recipes/` to the root of rlm-base-dev. Leave this README here; rlm-base-dev already has its own. The router that agents load is `.cursor/skills/meshmesh-recipes/SKILL.md` in that repository, not a file in this one.

When sending it, add this block to the tree in `docs/references/repository-layout.md`, between `docs/salesforce/` and `orgs/`:

```text
├── meshmesh-recipes/           # Post-spin MeshMesh recipes (not the live skill catalog)
│   ├── recipes/meshmesh/       # MeshMesh recipes; recipe.md at each bundle root
│   └── skills/                 # Exported Claude and Cursor skills (SKILL.md)
```

| Kind | Path | Entry file |
|------|------|------------|
| MeshMesh recipe | `meshmesh-recipes/recipes/meshmesh/<name>/` | `recipe.md` |
| Claude skill | `meshmesh-recipes/skills/claude/<name>/` | `SKILL.md` |
| Cursor skill | `meshmesh-recipes/skills/cursor/<name>/` | `SKILL.md` |

The CumulusCI `qbrix` feature flag is the xDO base layer for an org build. It is not this directory.
