# flake8: noqa: E501
"""Generate Markdown API reference from Godot doctool XML output.

Run from the repo root after generating XML with:
    godot --headless --path . --doctool docs/xml --gdscript-docs res://<addon_dir>/

Then:
    python generate_api_docs.py --outer-class MyAddonClass

Outputs one .md file per public class into docs/api/ (override with --out-dir).
"""

import argparse
import re
import textwrap
import xml.etree.ElementTree as ET
from pathlib import Path

DEFAULT_XML_DIR = Path("docs/xml")
DEFAULT_OUT_DIR = Path("docs/api")

GODOT_DOCS_BASE = "https://docs.godotengine.org/en/stable/classes/class_{}.html"

# Godot built-in classes whose names should link to the official docs.
GODOT_CLASSES: frozenset[str] = frozenset(
    {
        "Array",
        "Callable",
        "Dictionary",
        "Engine",
        "FileAccess",
        "HTTPClient",
        "HTTPRequest",
        "Mutex",
        "Node",
        "NodePath",
        "OS",
        "Object",
        "PackedByteArray",
        "PackedFloat32Array",
        "PackedInt32Array",
        "PackedStringArray",
        "RefCounted",
        "Resource",
        "SceneTree",
        "Semaphore",
        "Signal",
        "StreamPeer",
        "StreamPeerGZIP",
        "String",
        "StringName",
        "TLSOptions",
        "Thread",
        "Variant",
    }
)


def _strip_outer(name: str, outer_class: str) -> str:
    prefix = outer_class + "."
    if name.startswith(prefix):
        return name[len(prefix) :]
    return name


def _godot_url(class_name: str, anchor: str = "") -> str:
    url = GODOT_DOCS_BASE.format(class_name.lower())
    return f"{url}#{anchor}" if anchor else f"{url}#class-{class_name.lower()}"


def _md_type(type_str: str, known_classes: dict[str, str]) -> str:
    """Render a type as inline code, linked to its page if it's a known class."""
    if type_str in known_classes:
        return f"[`{type_str}`]({known_classes[type_str]})"
    if "." in type_str:
        cls, member = type_str.split(".", 1)
        if cls in GODOT_CLASSES:
            anchor = f"enum-{cls.lower()}-{member.lower()}"
            return f"[`{type_str}`]({_godot_url(cls, anchor)})"
    if type_str in GODOT_CLASSES:
        return f"[`{type_str}`]({_godot_url(type_str)})"
    return f"`{type_str}`"


def _bbcode_to_md(text: str, outer_class: str, known_classes: dict[str, str]) -> str:
    if not text:
        return ""

    def replace_codeblock(m: re.Match) -> str:
        code = textwrap.dedent(m.group(1)).strip("\n")
        return f"\n\n```gdscript\n{code}\n```\n\n"

    text = re.sub(
        r"\[codeblock\](.*?)\[/codeblock\]", replace_codeblock, text, flags=re.DOTALL
    )
    text = re.sub(
        r"\[code\](.*?)\[/code\]",
        lambda m: f"`{m.group(1).replace(chr(10), ' ')}`",
        text,
        flags=re.DOTALL,
    )
    text = re.sub(r"\[i\](.*?)\[/i\]", r"*\1*", text)
    text = re.sub(r"\[b\](.*?)\[/b\]", r"**\1**", text)

    def _replace_method_ref(m: re.Match) -> str:
        raw = m.group(1)
        name = _strip_outer(raw, outer_class)
        if "." in name:
            cls, method = name.split(".", 1)
            if cls in known_classes:
                return f"[`{method}()`]({known_classes[cls]}#method-{method})"
            if cls in GODOT_CLASSES:
                return f"[`{cls}.{method}()`]({_godot_url(cls)})"
        elif raw != name and outer_class in known_classes:
            # [method OuterClass.method] — outer prefix was stripped; cross-link to its page
            return f"[`{name}()`]({known_classes[outer_class]}#method-{name})"
        return f"[`{name}()`](#method-{name})"

    def _replace_member_ref(m: re.Match) -> str:
        name = _strip_outer(m.group(1), outer_class)
        if "." in name:
            cls, member = name.split(".", 1)
            if cls in known_classes:
                return f"[`{name}`]({known_classes[cls]}#property-{member})"
        return f"[`{name}`](#property-{name})"

    text = re.sub(r"\[method ([^\]]+)\]", _replace_method_ref, text)
    text = re.sub(r"\[member ([^\]]+)\]", _replace_member_ref, text)
    text = re.sub(r"\[param ([^\]]+)\]", r"`\1`", text)
    text = re.sub(
        r"\[enum ([^\]]+)\]",
        lambda m: f"`{_strip_outer(m.group(1), outer_class)}`",
        text,
    )
    text = re.sub(
        r"\[constant ([^\]]+)\]",
        lambda m: f"`{_strip_outer(m.group(1), outer_class)}`",
        text,
    )
    text = re.sub(
        r"\[signal ([^\]]+)\]",
        lambda m: f"`{_strip_outer(m.group(1), outer_class)}`",
        text,
    )

    def _replace_class_ref(m: re.Match) -> str:
        name = _strip_outer(m.group(1), outer_class)
        if name in known_classes:
            return f"[`{name}`]({known_classes[name]})"
        if name in GODOT_CLASSES:
            return f"[`{name}`]({_godot_url(name)})"
        return f"`{name}`"

    # Bare class references like [Node], [HTTPClient], [TLSOptions]
    text = re.sub(r"\[([A-Z][A-Za-z0-9_.]*)\]", _replace_class_ref, text)

    text = text.replace("[br][br]", "\n\n")
    text = text.replace("[br]", "\n\n")

    # Strip trailing whitespace from each line to avoid accidental Markdown hard breaks
    text = "\n".join(line.rstrip() for line in text.split("\n"))

    return text.strip()


def _render_type(type_attr: str, outer_class: str, enum_attr: str = "") -> str:
    if enum_attr:
        return _strip_outer(enum_attr, outer_class)
    return _strip_outer(type_attr, outer_class)


def _method_signature(method_el: ET.Element, outer_class: str) -> tuple[str, str]:
    """Return (return_type, signature_string) for a method element."""
    name = method_el.get("name", "")
    qualifiers = method_el.get("qualifiers", "")

    ret_el = method_el.find("return")
    ret_type = (
        _render_type(ret_el.get("type", "void"), outer_class, ret_el.get("enum", ""))
        if ret_el is not None
        else "void"
    )

    params = []
    for p in method_el.findall("param"):
        pname = p.get("name", "")
        ptype = _render_type(p.get("type", ""), outer_class, p.get("enum", ""))
        pdefault = p.get("default")
        if pdefault is not None:
            params.append(f"{pname}: {ptype} = {pdefault}")
        else:
            params.append(f"{pname}: {ptype}")

    sig = f"{name}({', '.join(params)})"
    if qualifiers:
        sig += f" {qualifiers}"
    return ret_type, sig


def _is_private(name: str) -> bool:
    return name.startswith("_")


def _is_private_class(xml_stem: str) -> bool:
    """True if any dotted segment of the class name starts with _."""
    return any(seg.startswith("_") for seg in xml_stem.split("."))


def _text(el: ET.Element | None) -> str:
    return (el.text or "").strip() if el is not None else ""


def _section(title: str) -> str:
    return f"## {title}\n"


def generate_page(
    xml_path: Path, outer_class: str, known_classes: dict[str, str]
) -> str:
    root = ET.parse(xml_path).getroot()

    class_name = root.get("name", "")
    short_name = _strip_outer(class_name, outer_class)
    inherits = root.get("inherits", "")

    out: list[str] = []

    out.append(f"# {short_name}\n")

    if inherits:
        inherits_short = _strip_outer(inherits, outer_class)
        out.append(f"**Inherits:** {_md_type(inherits_short, known_classes)}\n")

    brief = _bbcode_to_md(
        _text(root.find("brief_description")), outer_class, known_classes
    )
    desc = _bbcode_to_md(_text(root.find("description")), outer_class, known_classes)
    if brief:
        out.append(f"{brief}\n")
    if desc and desc != brief:
        out.append(f"{desc}\n")

    # --- Properties table ---
    members_el = root.find("members")
    pub_members = [
        m
        for m in (members_el.findall("member") if members_el is not None else [])
        if not _is_private(m.get("name", ""))
    ]

    if pub_members:
        out.append(_section("Properties"))
        out.append("| Type | Name | Default |")
        out.append("|------|------|---------|")
        for m in pub_members:
            mtype = _render_type(m.get("type", ""), outer_class, m.get("enum", ""))
            mname = m.get("name", "")
            mdefault = m.get("default")
            default_cell = f"`{mdefault}`" if mdefault is not None else ""
            out.append(
                f"| {_md_type(mtype, known_classes)} | `{mname}` | {default_cell} |"
            )
        out.append("")

    # --- Methods table ---
    methods_el = root.find("methods")
    def _has_private_params(method_el: ET.Element) -> bool:
        return any(p.get("name", "").startswith("_") for p in method_el.findall("param"))

    pub_methods = [
        m
        for m in (methods_el.findall("method") if methods_el is not None else [])
        if not _is_private(m.get("name", "")) and not _has_private_params(m)
    ]

    if pub_methods:
        out.append(_section("Methods"))
        out.append("| Returns | Signature |")
        out.append("|---------|-----------|")
        for m in pub_methods:
            mname = m.get("name", "")
            ret, sig = _method_signature(m, outer_class)
            linked_sig = f"[`{mname}`](#method-{mname})`{sig[len(mname):]}`"
            out.append(f"| {_md_type(ret, known_classes)} | {linked_sig} |")
        out.append("")

    # --- Constants ---
    constants_el = root.find("constants")
    if constants_el is not None:
        constants = constants_el.findall("constant")
        if constants:
            out.append(_section("Constants"))
            enums: dict[str, list[ET.Element]] = {}
            standalone: list[ET.Element] = []
            for c in constants:
                enum_attr = c.get("enum", "")
                if enum_attr:
                    enums.setdefault(enum_attr, []).append(c)
                else:
                    standalone.append(c)

            for c in standalone:
                cname = c.get("name", "")
                cval = c.get("value", "")
                cdesc = _bbcode_to_md(_text(c), outer_class, known_classes)
                out.append(f"**`{cname}` = `{cval}`**")
                if cdesc:
                    out.append(f"\n{cdesc}\n")

            for enum_attr, members in enums.items():
                out.append(f"### enum `{_strip_outer(enum_attr, outer_class)}`\n")
                out.append("| Name | Value | Description |")
                out.append("|------|-------|-------------|")
                for c in members:
                    cname = c.get("name", "")
                    cval = c.get("value", "")
                    cdesc = _bbcode_to_md(_text(c), outer_class, known_classes)
                    # Escape pipes in descriptions so they don't break the table
                    cdesc_cell = cdesc.replace("\n", " ").replace("|", "\\|")
                    out.append(f"| `{cname}` | `{cval}` | {cdesc_cell} |")
                out.append("")

    # --- Property Descriptions ---
    if pub_members:
        out.append(_section("Property Descriptions"))
        for m in pub_members:
            mtype = _render_type(m.get("type", ""), outer_class, m.get("enum", ""))
            mname = m.get("name", "")
            mdefault = m.get("default")
            heading = f"{_md_type(mtype, known_classes)} {mname}"
            if mdefault is not None:
                heading += f" = `{mdefault}`"
            out.append(f'<a id="property-{mname}"></a>\n\n### {heading}\n')
            mdesc = _bbcode_to_md(_text(m), outer_class, known_classes)
            if mdesc:
                out.append(f"{mdesc}\n")

    # --- Method Descriptions ---
    if pub_methods:
        out.append(_section("Method Descriptions"))
        for m in pub_methods:
            ret, sig = _method_signature(m, outer_class)
            out.append(
                f'<a id="method-{m.get("name", "")}"></a>\n\n### {_md_type(ret, known_classes)} `{sig}`\n'
            )
            mdesc = _bbcode_to_md(
                _text(m.find("description")), outer_class, known_classes
            )
            if mdesc:
                out.append(f"{mdesc}\n")

    return "\n".join(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--outer-class",
        required=True,
        metavar="NAME",
        help="Name of the top-level GDScript class (e.g. C3HTTPRequest)",
    )
    parser.add_argument("--xml-dir", type=Path, default=DEFAULT_XML_DIR, metavar="DIR")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR, metavar="DIR")
    args = parser.parse_args()

    outer_class: str = args.outer_class
    xml_dir: Path = args.xml_dir
    out_dir: Path = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    xml_files = sorted(xml_dir.glob(f"{outer_class}*.xml"))

    # Build the class→filename map first so generate_page can emit cross-links.
    known_classes: dict[str, str] = {}
    for xml_path in xml_files:
        if _is_private_class(xml_path.stem):
            continue
        short_name = _strip_outer(xml_path.stem, outer_class)
        known_classes[short_name] = short_name.lower() + ".md"

    generated = 0
    cwd = Path.cwd().resolve()
    for xml_path in xml_files:
        if _is_private_class(xml_path.stem):
            continue

        short_name = _strip_outer(xml_path.stem, outer_class)
        out_path = out_dir / known_classes[short_name]

        md = generate_page(xml_path, outer_class, known_classes)
        out_path.write_text(md, encoding="utf-8")
        try:
            display = out_path.resolve().relative_to(cwd)
        except ValueError:
            display = out_path
        print(f"  {xml_path.stem} -> {display}")
        generated += 1

    try:
        out_dir_display = out_dir.resolve().relative_to(cwd)
    except ValueError:
        out_dir_display = out_dir
    print(f"\nGenerated {generated} files in {out_dir_display}/")


if __name__ == "__main__":
    main()
