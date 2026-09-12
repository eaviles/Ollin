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
`Media/media.json`, so nothing here is typed by hand and moving the host is
still one edit.

A listing whose sketches all live on pages of their own, like the examples
front page or the 3D and recreations indexes, shows one picture per group
instead, and that picture is a 2x2 of four of the group's sketches so a cell
reads as a group rather than as a sketch that happened to be first. Which
four is a choice rather than a rule, so it is written down in the manifest
under `covers` and drawn by `Scripts/example-covers.py`.

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
        cover = media.get("groups", {}).get(group.relative_to(EXAMPLES).as_posix())
        if cover:
            here = group.relative_to(home).as_posix()
            cells.append((f"[![{group.name}]({media['base']}/{cover['imageSmall']})]({here}/)",
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
    """Put the grid straight under the title, wherever the last one sat."""
    lines = list(lines)
    # Any grid already there comes out first, so a run that moves the grid
    # moves it rather than leaving one behind and adding another.
    at = next((i for i, l in enumerate(lines) if l.startswith("| [![")), None)
    if at is not None:
        stop = at
        while stop < len(lines) and lines[stop].startswith("|"):
            stop += 1
        while stop < len(lines) and not lines[stop].strip():
            stop += 1
        del lines[at:stop]
    if not table:
        return lines
    # Under the title, so the sketches are the first thing seen rather than
    # four paragraphs down the page.
    title = next((i for i, l in enumerate(lines) if l.startswith("## ")), None)
    if title is None:
        title = max(next((i for i, l in enumerate(lines) if l.startswith("|")), len(lines)) - 1, 0)
    put = title + 1
    while put < len(lines) and not lines[put].strip():
        put += 1
    return lines[:put] + table + [""] + lines[put:]


def main():
    media = json.load(open(EXAMPLES.parent / "Media" / "media.json"))
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
