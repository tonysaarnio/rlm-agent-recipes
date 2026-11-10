# MeshMesh recipes

One directory per MeshMesh recipe. `recipe.md` sits at the root of that directory, next to the config, sample-data, metadata, and PDF files the recipe uses.

```text
meshmesh-recipes/recipes/meshmesh/<recipe-name>/
  recipe.md
  config-defaults.json
  sample-data-generator.md
  ...
```

Name the directory in lower-kebab-case. Drop browser download suffixes such as ` (1)` from the folder name before adding it. These are MeshMesh recipes, not skills in `.cursor/skills/`.

Each recipe folder has a `README.md` that says how to install that folder into MeshMesh. `recipe.md` stays the procedure the MeshMesh agent runs after the install.
