# Agent recipes

Holding repository for MeshMesh recipes and Claude and Cursor skills. The `recipes/` directory uses the same paths it will have in [rlm-base-dev](https://github.com/bgaldino/rlm-base-dev), so it can be copied in later without renaming.

These recipes and skills run after a demo org already exists and Revenue Cloud is already set up. QuantumBit is the usual target. They cover the follow-on actions on that org, such as Revenue Management Intelligence dashboards and Global Promotions. Org creation and the base Revenue Cloud build stay in rlm-base-dev.

Copy `recipes/` to the root of rlm-base-dev. Leave this README here; rlm-base-dev already has its own.

When sending it, add this block to the tree in `docs/references/repository-layout.md`, between `docs/salesforce/` and `orgs/`:

```text
├── recipes/                    # Published MeshMesh, Claude, and Cursor bundles (not the live skill catalog)
│   ├── meshmesh/               # One directory per recipe; recipe.md at the bundle root
│   ├── claude/                 # Exported Claude skills (SKILL.md); Claude has no recipe format
│   └── cursor/                 # Exported Cursor skills (SKILL.md); Cursor has no recipe format
```

| Tool | Path | Entry file |
|------|------|------------|
| MeshMesh | `recipes/meshmesh/<name>/` | `recipe.md` |
| Claude | `recipes/claude/<name>/` | `SKILL.md` |
| Cursor | `recipes/cursor/<name>/` | `SKILL.md` |
