#!/usr/bin/env python3
"""Render a single CHANGELOG version section as release-notes HTML.

Sparkle's ``generate_appcast`` embeds the contents of an ``.html`` file that
sits next to an update archive into the appcast's ``<description>``. Naming the
file after the archive (e.g. ``PastePilot-0.4.0-arm64.html``) lets the standard
updater UI show these notes when an update is available.

Usage:
    changelog-to-html.py <version> [changelog-path]

Writes the rendered HTML to stdout. Exits non-zero if the version section is
missing or empty so the release workflow can fail loudly.
"""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path


def extract_section(changelog: str, version: str) -> list[str]:
    """Return the lines of the ``## [version]`` section, headers excluded."""
    lines = changelog.splitlines()
    start = None
    header = re.compile(r"^## \[")
    for index, line in enumerate(lines):
        if line.startswith(f"## [{version}]"):
            start = index + 1
            break
    if start is None:
        return []

    section: list[str] = []
    for line in lines[start:]:
        if header.match(line):
            break
        section.append(line)

    # Trim leading and trailing blank lines.
    while section and not section[0].strip():
        section.pop(0)
    while section and not section[-1].strip():
        section.pop()
    return section


def render_inline(text: str) -> str:
    """Escape HTML then apply inline ``code`` and ``**bold**`` markup."""
    escaped = html.escape(text, quote=False)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    escaped = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", escaped)
    return escaped


def render(section: list[str]) -> str:
    """Convert changelog lines into a small HTML fragment."""
    out: list[str] = []
    items: list[str] = []  # accumulated <li> bodies for the open list

    def flush_list() -> None:
        if not items:
            return
        out.append("<ul>")
        out.extend(f"  <li>{render_inline(item)}</li>" for item in items)
        out.append("</ul>")
        items.clear()

    for line in section:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("### "):
            flush_list()
            out.append(f"<h3>{render_inline(stripped[4:])}</h3>")
        elif stripped.startswith(("- ", "* ")):
            items.append(stripped[2:])
        elif line[:1].isspace() and items:
            # Continuation of the previous list item (wrapped long line).
            items[-1] += " " + stripped
        else:
            flush_list()
            out.append(f"<p>{render_inline(stripped)}</p>")

    flush_list()
    return "\n".join(out)


def main(argv: list[str]) -> int:
    if not 2 <= len(argv) <= 3:
        print(__doc__, file=sys.stderr)
        return 2
    version = argv[1]
    path = Path(argv[2]) if len(argv) == 3 else Path("CHANGELOG.md")

    section = extract_section(path.read_text(encoding="utf-8"), version)
    if not section:
        print(f"No changelog section found for {version}", file=sys.stderr)
        return 1

    rendered = render(section)
    if not rendered.strip():
        print(f"Changelog section for {version} produced no content", file=sys.stderr)
        return 1
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
