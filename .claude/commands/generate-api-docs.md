---
description: Regenerate the API reference docs from GDScript source
---

Generate (or update) the Markdown API reference in `docs/api/` by running both steps from the repo root.

**Step 1** — extract XML documentation from GDScript source:

```
godot --headless --path . --doctool docs/xml --gdscript-docs res://c3_http_request/
```

**Step 2** — convert the XML to Markdown:

```
python scripts/generate_api_docs.py --outer-class C3HTTPRequest
```

**Step 3** — verify the site builds without errors:

```
mkdocs build --strict
```

`--strict` promotes warnings (broken links, missing pages) to errors. After all three steps complete, inspect the generated files in `docs/api/` for correctness (types, cross-links, method signatures, descriptions), note any build warnings or errors, and report your findings.
