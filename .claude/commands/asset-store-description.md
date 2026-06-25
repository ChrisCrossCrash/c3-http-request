---
description: Regenerate the Godot Asset Store detailed description from README.md
---

Generate (or update) the Godot Asset Store detailed description at `build/asset-store-detailed-description.md` by running:

```
python scripts/minify_markdown.py README.md build/asset-store-detailed-description.md --emphasis=asterisks
```

After running the script, inspect the output file for correctness, and report your findings.
