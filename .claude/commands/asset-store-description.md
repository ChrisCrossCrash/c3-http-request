---
description: Regenerate the Godot Asset Store detailed description from README.md
---

Generate (or update) the Godot Asset Store detailed description at `gitignored/asset-store-detailed-description.md` by converting `README.md`.

The Asset Store file is a transformed copy of `README.md`. Read the current `README.md` and produce the Asset Store version by applying these transformations, then write the result to `gitignored/asset-store-detailed-description.md` (overwriting it):

1. **Emphasis uses `*asterisks*` exclusively, never `_underscores_`.** The Asset Store's Markdown renderer only recognizes asterisk-based emphasis. Convert every `_..._` to `*...*`.
2. **All links are absolute, pointing to GitHub — never relative paths.** Rewrite every relative link to an absolute URL on the `main` branch of the upstream repository: `https://github.com/ChrisCrossCrash/c3-http-request`. Use `/blob/main/<path>` for files and `/tree/main/<path>` for directories. Leave in-page anchor links (e.g. `#threaded-requests`) and already-absolute URLs unchanged.
3. **Minify the whitespace** to use the fewest characters possible, since the Asset Store has a character limit. The most impactful case is tables: collapse aligned/padded columns to minimal-width cells (e.g. `| - |` separators and single-space-padded cells). Apply the same principle anywhere else padding exists purely for source readability — but never at the cost of correct Markdown rendering or readable prose. Do not reflow or reword the prose itself; only remove cosmetic whitespace.

Otherwise keep the content identical to `README.md` — same headings, prose, code blocks, and table data. Do not add or remove sections.

After writing the file, briefly report what changed relative to the previous version (or that it was created fresh).
