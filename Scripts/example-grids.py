#!/usr/bin/env python3
"""Write the picture grid at the top of each examples listing.

    Scripts/example-grids.py            # rewrite every listing
    Scripts/example-grids.py Patterns   # just one folder

A listing owns every sketch folder beneath it except the ones a nested listing
owns instead, which is the same rule `Scripts/check-links.sh` gates, so a group
with a page of its own shows up there rather than twice.

The grid is a plain markdown table of linked stills, four across, with the
names on the row beneath each row of pictures. It is markdown rather than HTML
because the site's own renderer passes only a few tags through and escapes the
rest, and because GitHub has to show the same file. The addresses come from
`Examples/media.json`, so nothing here is typed by hand and moving the host is
still one edit.

A listing whose sketches all live on pages of their own, like the examples
front page or the 3D and recreations indexes, shows one picture per group
instead. Which sketch stands for a group is a choice rather than a rule, so
it is written down in the manifest under `covers` and read from there.

An example with no row in the manifest has no picture and simply does not
appear in the grid; it is still in the listing table underneath with the
sentence that says what it shows. Running this twice changes nothing: an
existing grid is recognized by its shape and replaced.
"""
import json
import pathlib
import re
import sys

COLUMNS = 4
EXAMPLES = pathlib.Path("Examples")


def delegated(listing):
    """The folders under this listing that have a page of their own."""
    return sorted(nested.parent for nested in listing.parent.glob("*/README.md"))


def owned(listing):
    """The sketch folders this listing is responsible for, in name order."""
    home = listing.parent
    delegated = {nested.parent for nested in home.glob("*/README.md")}
    found = []
    for sketch in home.rglob("Sketch.swift"):
        folder = sketch.parent
        if any(folder == d or d in folder.parents for d in delegated):
            continue
        found.append(folder)
    return sorted(found)


def grid(listing, media):
    """The table, or nothing when nothing under this listing has a picture."""
    home = listing.parent
    cells = []
    for group in delegated(listing):
        cover = media.get("covers", {}).get(group.relative_to(EXAMPLES).as_posix())
        entry = media["examples"].get(cover) if cover else None
        if entry:
            here = group.relative_to(home).as_posix()
            cells.append((f"[![{group.name}]({media['base']}/{entry['stillSmall']})]({here}/)",
                          f"[{group.name}]({here}/)"))
    for folder in owned(listing):
        name = folder.name
        entry = media["examples"].get(folder.relative_to(EXAMPLES).as_posix())
        if entry:
            here = folder.relative_to(home).as_posix()
            cells.append((f"[![{name}]({media['base']}/{entry['stillSmall']})]({here}/)",
                          f"[{name}]({here}/)"))
    if not cells:
        return []
    out = []
    for start in range(0, len(cells), COLUMNS):
        band = cells[start:start + COLUMNS]
        pad = [("", "")] * (COLUMNS - len(band))
        pictures = " | ".join(c[0] for c in band + pad)
        names = " | ".join(c[1] for c in band + pad)
        out.append(f"| {pictures} |")
        if start == 0:
            out.append("|" + "---|" * COLUMNS)
        out.append(f"| {names} |")
    return out


def place(lines, table):
    """Put the grid where the last one was, or above the listing table."""
    start = next((i for i, l in enumerate(lines) if l.startswith("| [![")), None)
    if start is not None:
        end = start
        while end < len(lines) and lines[end].startswith("|"):
            end += 1
        if not table:                     # every example here lost its picture
            while end < len(lines) and not lines[end].strip():
                end += 1
            return lines[:start] + lines[end:]
        return lines[:start] + table + lines[end:]
    if not table:
        return lines
    # Above the first table, with a blank line between it and the prose.
    first = next((i for i, l in enumerate(lines) if l.startswith("|")), len(lines))
    return lines[:first] + table + [""] + lines[first:]


def main():
    media = json.load(open(EXAMPLES / "media.json"))
    only = sys.argv[1] if len(sys.argv) > 1 else None
    written = 0
    for listing in sorted(EXAMPLES.rglob("README.md")):
        if only and only not in listing.parent.as_posix():
            continue
        table = grid(listing, media)
        text = listing.read_text()
        lines = text.split("\n")
        placed = place(lines, table)
        if placed != lines:
            listing.write_text("\n".join(placed))
            written += 1
            print(f"{listing}: {sum(1 for l in table if l.startswith('| [!'))} rows of pictures")
    print(f"grids: {written} listings rewritten")


main()
