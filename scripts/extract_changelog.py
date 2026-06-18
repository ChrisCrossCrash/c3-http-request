# flake8: noqa: E501
"""Print one version's section from CHANGELOG.md, for use as a release body."""

import argparse
import io
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
CHANGELOG_FILE = REPO_ROOT / "CHANGELOG.md"


def extract(version: str) -> str:
    # Accept either "v0.2.0" (the git tag form) or "0.2.0" (the heading form).
    number = version.lstrip("v")
    text = CHANGELOG_FILE.read_text(encoding="utf-8")

    # Grab everything between this version's "## [x.y.z]" heading and the next
    # "## " heading (or end of file). The heading line itself is dropped — the
    # GitHub Release already shows the version as its title.
    pattern = (
        r"^##\s*\[" + re.escape(number) + r"\][^\n]*\n"
        r"(.*?)"
        r"(?=^##\s|\Z)"
    )
    match = re.search(pattern, text, re.MULTILINE | re.DOTALL)
    if match is None:
        raise SystemExit(
            f"Could not find a '## [{number}]' section in {CHANGELOG_FILE.name}."
        )
    return match.group(1).strip()


if __name__ == "__main__":
    # Force UTF-8 output so characters like the em dash survive when this output
    # is captured into a git tag message on Windows, whose console encoding would
    # otherwise mangle them. (The CI redirect to release_notes.md is UTF-8 anyway.)
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("version", help="Version string, e.g. v0.2.0 or 0.2.0")
    args = parser.parse_args()
    print(extract(args.version))
