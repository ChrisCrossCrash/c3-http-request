# flake8: noqa: E501
"""Build a .zip asset bundle for the Godot Asset Store."""

import argparse
import re
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
ASSET_DIR = REPO_ROOT / "c3_http_request"
SCRIPT_FILE = ASSET_DIR / "c3_http_request.gd"
LICENSE_FILE = REPO_ROOT / "LICENSE.md"
OUTPUT_DIR = REPO_ROOT / "build"


def read_script_version() -> str:
    match = re.search(
        r'^const VERSION\s*:?=\s*"([^"]*)"',
        SCRIPT_FILE.read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if match is None:
        raise SystemExit(f"Could not find `const VERSION` in {SCRIPT_FILE}.")
    return match.group(1)


def build(version: str):
    script_version = read_script_version()
    if version != script_version:
        raise SystemExit(
            f"Version mismatch: build argument is {version!r} but "
            f"`const VERSION` in {SCRIPT_FILE.name} is {script_version!r}. "
            "Bump the const to match the release tag."
        )

    output_zip = OUTPUT_DIR / f"c3_http_request_{version}.zip"
    OUTPUT_DIR.mkdir(exist_ok=True)

    with zipfile.ZipFile(output_zip, "w", zipfile.ZIP_DEFLATED) as zf:
        target_dir = Path("addons/c3_http_request")
        for file in sorted(ASSET_DIR.rglob("*")):
            if file.is_file():
                zf.write(file, target_dir / file.relative_to(ASSET_DIR))

        zf.write(LICENSE_FILE, target_dir / LICENSE_FILE.name)

    print(f"Built: {output_zip}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("version", help="Version string, e.g. v0.1.0")
    args = parser.parse_args()
    build(args.version)
