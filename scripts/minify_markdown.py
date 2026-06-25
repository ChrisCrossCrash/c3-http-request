"""Deterministic Markdown minifier"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Code-span masking helpers
# ---------------------------------------------------------------------------

_MASK_TOKEN = "\x00CODESPAN{}\x00"
_MASK_RE = re.compile(_MASK_TOKEN.format(r"(\d+)"))


def _mask_code_spans(line: str) -> tuple[str, list[str]]:
    """Replace inline code spans with numbered placeholders. Returns (masked_line, spans)."""
    spans: list[str] = []
    result = []
    i = 0
    while i < len(line):
        if line[i] == "`":
            # Count opening backticks
            j = i
            while j < len(line) and line[j] == "`":
                j += 1
            fence = line[i:j]
            # Find matching closing fence
            close = line.find(fence, j)
            if close == -1:
                result.append(line[i:])
                i = len(line)
            else:
                end = close + len(fence)
                placeholder = _MASK_TOKEN.format(len(spans))
                spans.append(line[i:end])
                result.append(placeholder)
                i = end
        else:
            result.append(line[i])
            i += 1
    return "".join(result), spans


def _unmask_code_spans(line: str, spans: list[str]) -> str:
    return _MASK_RE.sub(lambda m: spans[int(m.group(1))], line)


# ---------------------------------------------------------------------------
# Transformation 1: emphasis normalization
# ---------------------------------------------------------------------------

# Matches __...__ or _..._ (non-greedy, not across newlines)
_DOUBLE_UNDER_RE = re.compile(r"(?<![*_])__(?!_)(.+?)__(?![*_])")
_SINGLE_UNDER_RE = re.compile(r"(?<![*_])_(?!_)(.+?)_(?![*_])")


def _convert_emphasis(line: str) -> str:
    masked, spans = _mask_code_spans(line)
    masked = _DOUBLE_UNDER_RE.sub(r"**\1**", masked)
    masked = _SINGLE_UNDER_RE.sub(r"*\1*", masked)
    return _unmask_code_spans(masked, spans)


# ---------------------------------------------------------------------------
# Transformation 2: link absolutization
# ---------------------------------------------------------------------------

_LINK_RE = re.compile(r"(!?\[(?:[^\[\]]|\[[^\[\]]*\])*\])\(([^)]+)\)")


def _git_origin_base() -> str | None:
    try:
        url = subprocess.check_output(
            ["git", "remote", "get-url", "origin"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    # SSH → HTTPS
    ssh = re.match(r"git@([^:]+):(.+?)(?:\.git)?$", url)
    if ssh:
        return f"https://{ssh.group(1)}/{ssh.group(2)}"
    return url.removesuffix(".git") if url else None


def _absolutize_url(url: str, base: str) -> str:
    if not url or url.startswith(("http://", "https://", "//", "#", "mailto:")):
        return url
    path = url.lstrip("/")
    # Heuristic: trailing slash or no extension → directory
    if url.endswith("/") or "." not in Path(path).name:
        return f"{base}/tree/main/{path}"
    return f"{base}/blob/main/{path}"


def _absolutize_links(line: str, base: str) -> str:
    def replace(m: re.Match) -> str:
        label, url = m.group(1), m.group(2)
        # Preserve title attribute if present: url may be `path "title"`
        parts = url.split(None, 1)
        new_url = _absolutize_url(parts[0], base) if parts else url
        rest = f" {parts[1]}" if len(parts) > 1 else ""
        return f"{label}({new_url}{rest})"

    masked, spans = _mask_code_spans(line)
    masked = _LINK_RE.sub(replace, masked)
    return _unmask_code_spans(masked, spans)


# ---------------------------------------------------------------------------
# Transformation 3: table minification
# ---------------------------------------------------------------------------

_SEPARATOR_CELL_RE = re.compile(r":?-+:?")


def _is_table_line(line: str) -> bool:
    stripped = line.strip()
    return stripped.startswith("|") and stripped.endswith("|")


def _minify_table_line(line: str) -> str:
    stripped = line.strip()
    # Split on | but keep edge pipes
    parts = stripped.split("|")
    # parts[0] and parts[-1] are empty strings from leading/trailing |
    cells = parts[1:-1]
    new_cells = []
    for cell in cells:
        content = cell.strip()
        # Separator cell?
        if _SEPARATOR_CELL_RE.fullmatch(content):
            # Preserve alignment colons, minimise dashes to one
            left = ":" if content.startswith(":") else ""
            right = ":" if content.endswith(":") and len(content) > 1 else ""
            new_cells.append(f" {left}-{right} ")
        else:
            new_cells.append(f" {content} ")
    return "|" + "|".join(new_cells) + "|"


# ---------------------------------------------------------------------------
# Transformation 4: general whitespace
# ---------------------------------------------------------------------------


def _strip_trailing_spaces(line: str) -> str:
    return line.rstrip()


def _collapse_blank_lines(text: str) -> str:
    return re.sub(r"\n{3,}", "\n\n", text)


# ---------------------------------------------------------------------------
# Main pipeline
# ---------------------------------------------------------------------------


def transform(text: str, *, emphasis: bool, base_url: str | None) -> str:
    lines = text.splitlines()
    in_code_block = False
    result = []

    for line in lines:
        # Track fenced code blocks (``` or ~~~)
        fence_match = re.match(r"^(`{3,}|~{3,})", line)
        if fence_match:
            in_code_block = not in_code_block

        if in_code_block:
            result.append(line)
            continue

        # Apply ordered transformations
        if emphasis:
            line = _convert_emphasis(line)
        if base_url:
            line = _absolutize_links(line, base_url)
        if _is_table_line(line):
            line = _minify_table_line(line)
        line = _strip_trailing_spaces(line)

        result.append(line)

    text = "\n".join(result)
    text = _collapse_blank_lines(text)
    # Ensure single trailing newline
    return text.rstrip("\n") + "\n"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Minify a Markdown file for the Godot Asset Store."
    )
    parser.add_argument("input", type=Path, help="Source Markdown file")
    parser.add_argument("output", type=Path, help="Destination Markdown file")
    parser.add_argument(
        "--emphasis",
        choices=["asterisks"],
        help="Convert underscore emphasis to asterisks",
    )
    parser.add_argument(
        "--abs-url",
        metavar="BASE_URL",
        help="Base URL for absolutizing relative links (auto-detected from git origin if omitted)",
    )
    args = parser.parse_args()

    src = args.input.read_text(encoding="utf-8")

    # Resolve base URL
    if args.abs_url:
        base_url: str | None = args.abs_url.rstrip("/")
    else:
        base_url = _git_origin_base()

    result = transform(
        src,
        emphasis=(args.emphasis == "asterisks"),
        base_url=base_url,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(result, encoding="utf-8")
    print(f"Written to {args.output}", file=sys.stderr)
    print(f"Input:  {len(src):,} chars", file=sys.stderr)
    print(f"Output: {len(result):,} chars", file=sys.stderr)


if __name__ == "__main__":
    main()
