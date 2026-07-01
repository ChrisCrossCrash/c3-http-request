---
description: Regenerate the API reference docs from GDScript source
---

Generate (or update) the Markdown API reference in `docs/api/` by running both steps from the repo root.

**Step 1** — delete the old XML docs in `docs/xml/`:

```
rm -rf docs/xml/*
```

**Step 2** — extract XML documentation from GDScript source:

```
godot --headless --path . --doctool docs/xml --gdscript-docs res://c3_http_request/
```

**Step 3** — delete the old API reference in `docs/api/`:

```
rm -rf docs/api/*
```

**Step 4** — convert the XML to Markdown:

```
c3-godot-docs-gen docs/xml/ docs/api/
```

**Step 5** — verify the site builds without errors:

```
mkdocs build --strict
```

`--strict` promotes warnings (broken links, missing pages) to errors. After all steps complete, inspect the generated files in `docs/api/` for correctness (types, cross-links, method signatures, descriptions), note any build warnings or errors, and report your findings.

> [!NOTE]
> `mkdocs build` will always print a warning block from the Material for MkDocs team about upcoming MkDocs 2.0 breaking changes. This is expected and can be ignored — it is not a build error.
