#!/bin/zsh
#
# Scripts/guide-links.sh: check that the Guide's navigation is real.
#
#   Scripts/guide-links.sh           # check, exit nonzero on any error
#   Scripts/guide-links.sh --list    # also print every note, including the quiet ones
#
# The Guide navigates by number. Prose says "Chapter 5's noise hands back a
# value at every point", the footer chain runs 1 to 22 and on into the
# appendices, Appendix D keys 226 rows to a chapter, the coverage matrix keys
# 272 more, and CAPABILITIES.md points at chapters by section heading. All of
# that was verified by hand, which works until a chapter moves. Then 658 links,
# 408 image tags and 498 chapter tokens go stale at once and nothing notices,
# because no gate ever read them.
#
# This is that gate. Nine checks, in the order a reader would trip over them:
#
#   1. Every relative link target exists, from the file that names it.
#   2. Every `#anchor` resolves to a heading in the file it points at.
#   3. Every <img src> file exists, in Guide pages and in Docs/ pages, which
#      reuse Guide figures by relative path.
#   4. Every image under Guide/Images/ is referenced by some page. Both halves
#      of that rule are in Guide/AUTHORING.md and neither was enforced.
#   5. The footer chain is contiguous, and each Previous/Next title matches the
#      title of the file it points at.
#   6. A chapter's filename number, breadcrumb number and H1 number agree.
#   7. Guide/README.md's contents list matches the files on disk.
#   8. Guide/PLAN.md's status table matches the files on disk.
#   9. Every chapter token names a chapter that exists: `Ch N` in PLAN.md and
#      Appendix D, and `Guide Ch N § *Heading*` in CAPABILITIES.md, where the
#      heading itself has to exist in that chapter.
#
# Check 9 is the one worth having. A pointer that carries a section heading
# survives a renumber looking correct and aiming at nothing, and that is
# exactly the failure this repository has already had twice.
#
# Notes are drift that a human should look at rather than a build should block:
# a pointer that names the first half of a heading somebody later extended, or
# a quoted phrase in the coverage matrix that is prose and not a heading.
#
# Guide authoring conventions live in Guide/AUTHORING.md.

cd "$(dirname "$0")/.." || exit 1

emulate -L zsh
setopt no_nomatch

[[ "$1" == "--help" || "$1" == "-h" ]] && { sed -n '3,40p' "$0" | sed 's|^# \?||'; exit 0 }

python3 - "$@" <<'PY'
import pathlib, re, sys, collections

list_notes = "--list" in sys.argv[1:]

GUIDE = pathlib.Path("Guide")
ROOT = pathlib.Path(".")

errors = []
notes = []


def fail(where, msg):
    errors.append(f"{where}: {msg}")


def note(where, msg):
    notes.append(f"{where}: {msg}")


# --------------------------------------------------------------- the corpus
chapters = sorted(GUIDE.glob("[0-9]*.md"))
appendices = sorted(GUIDE.glob("[A-D]-*.md"))
pages = chapters + appendices + [GUIDE / "README.md"]
authoring = [GUIDE / "PLAN.md", GUIDE / "AUTHORING.md"]

text = {p: p.read_text() for p in pages + authoring}
lines = {p: text[p].splitlines() for p in text}

if not chapters:
    print("guide-links: no chapter files found", file=sys.stderr)
    sys.exit(2)


def chapter_number(path):
    return str(int(path.name[:2]))


numbers = {chapter_number(c): c for c in chapters}


def slug(heading):
    """The anchor GitHub derives from a heading."""
    s = re.sub(r"<[^>]+>", "", heading)
    s = s.lower()
    s = re.sub(r"[^\w\s-]", "", s)
    return re.sub(r"\s+", "-", s.strip())


def headings(path):
    out = []
    fenced = False
    for line in lines.get(path, []):
        if line.startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        m = re.match(r"^(#{1,6})\s+(.*?)\s*$", line)
        if m:
            out.append((len(m.group(1)), m.group(2)))
    return out


anchors = {}
for p in pages + authoring:
    seen = collections.Counter()
    have = set()
    for _, h in headings(p):
        s = slug(h)
        have.add(s if not seen[s] else f"{s}-{seen[s]}")
        seen[s] += 1
    anchors[p] = have

heading_text = {}
for c in chapters:
    heading_text[chapter_number(c)] = [h for level, h in headings(c) if level >= 2]

title = {}
for c in chapters + appendices:
    for line in lines[c]:
        m = re.match(r"^# (?:(\d+)|Appendix ([A-D]))\.\s+(.+?)\s*$", line)
        if m:
            title[c] = (m.group(1) or m.group(2), m.group(3))
            break

# --------------------------------------------- 1 and 2: links and anchors
LINK = re.compile(r"\[(?:[^\]]*)\]\(([^)\s]+)\)")

for p in pages + authoring:
    for n, line in enumerate(lines[p], 1):
        for target in LINK.findall(line):
            if target.startswith(("http://", "https://", "mailto:")):
                continue
            path_part, _, anchor = target.partition("#")
            if path_part:
                dest = (p.parent / path_part).resolve()
                if not dest.exists():
                    fail(f"{p}:{n}", f"link target does not exist: {target}")
                    continue
                dest = pathlib.Path(dest)
            else:
                dest = p
            if not anchor:
                continue
            try:
                rel = dest.relative_to(pathlib.Path.cwd())
            except ValueError:
                continue
            if rel.suffix != ".md":
                continue
            if rel not in anchors:
                if rel.parts[0] == "Guide":
                    fail(f"{p}:{n}", f"anchor into an unread Guide file: {target}")
                continue
            if anchor not in anchors[rel]:
                fail(f"{p}:{n}", f"anchor does not resolve: {target}")

# ------------------------------------------------- 3 and 4: the two image rules
IMG = re.compile(r"<img\s+[^>]*src=\"([^\"]+)\"")
# A themed figure's dark sibling rides in a <picture> tag's <source srcset>;
# it rots the same way the <img> beside it does, and it counts as a reference
# for the orphan rule, or every -dark image would be flagged.
SRCSET = re.compile(r"<source\s+[^>]*srcset=\"([^\"]+)\"")

referenced = set()
# Docs pages reuse Guide figures by relative path, so their <img> tags rot the
# same way a chapter's do when a figure moves; they get the existence check.
# They stay out of the orphan rule: a figure lives or dies by its chapter.
docs_pages = sorted(pathlib.Path("Docs").rglob("*.md"))
for p in pages + docs_pages:
    page_lines = lines[p] if p in lines else p.read_text().splitlines()
    for n, line in enumerate(page_lines, 1):
        for src in IMG.findall(line) + SRCSET.findall(line):
            if src.startswith(("http://", "https://")):
                continue
            dest = (p.parent / src).resolve()
            if not dest.exists():
                fail(f"{p}:{n}", f"image does not exist: {src}")
            else:
                referenced.add(dest)

for image in sorted((GUIDE / "Images").rglob("*")):
    if image.is_file() and image.resolve() not in referenced:
        fail(str(image), "image is not referenced by any page")

# Nearly every figure sketch opens by naming the chapter it serves. That is a
# chapter reference like any other, and it goes stale on a renumber, so it gets
# checked like any other.
for sketch in sorted((GUIDE / "Figures").rglob("*.swift")):
    folder = re.match(r"(\d+)-", sketch.parent.name)
    if not folder:
        continue
    # Only the first mention identifies the figure. A header may name another
    # chapter after it ("the Chapter 11 flock, rebuilt out of light"), and that
    # is a cross-reference, checked below like any other chapter token.
    for n, line in enumerate(sketch.read_text().splitlines(), 1):
        if not line.lstrip().startswith("//"):
            break
        found = re.findall(r"\bChapter (\d+)\b", line)
        if not found:
            continue
        if found[0] != str(int(folder.group(1))):
            fail(f"{sketch}:{n}", f"names Chapter {found[0]}, but sits in chapter {int(folder.group(1))}")
        for other in found[1:] + []:
            if other not in numbers:
                fail(f"{sketch}:{n}", f"cross-references Chapter {other}, which is not a chapter")
        break

# --------------------------------------------------------- 5: the footer chain
FOOTER = re.compile(
    r"^\[Contents\]\(README\.md#contents\)"
    r"(?: · Previous: \[([^\]]+)\]\(([^)]+)\))?"
    r"(?: · Next: \[([^\]]+)\]\(([^)]+)\))?\s*$"
)

order = chapters + appendices
footer_of = {}
for p in order:
    found = [(n, line) for n, line in enumerate(lines[p], 1) if line.startswith("[Contents](README.md#contents)")]
    if len(found) != 1:
        fail(str(p), f"expected exactly one footer line, found {len(found)}")
        continue
    n, line = found[0]
    m = FOOTER.match(line)
    if not m:
        fail(f"{p}:{n}", "footer line does not match the house form")
        continue
    footer_of[p] = (n, m.group(1), m.group(2), m.group(3), m.group(4))


def label_for(path):
    if path not in title:
        return None
    number, name = title[path]
    kind = "Chapter" if number.isdigit() else "Appendix"
    return f"{kind} {number}, {name}"


for i, p in enumerate(order):
    if p not in footer_of:
        continue
    _, prev_label, prev_target, next_label, next_target = footer_of[p]
    for direction, label, target, want in (
        ("Previous", prev_label, prev_target, order[i - 1] if i else None),
        ("Next", next_label, next_target, order[i + 1] if i + 1 < len(order) else None),
    ):
        n = footer_of[p][0]
        if want is None:
            if label is not None:
                fail(f"{p}:{n}", f"{direction} link on the {'first' if not i else 'last'} page")
            continue
        if label is None:
            fail(f"{p}:{n}", f"missing {direction} link, should point at {want.name}")
            continue
        if target != want.name:
            fail(f"{p}:{n}", f"{direction} points at {target}, should be {want.name}")
        expected = label_for(want)
        if expected and label != expected:
            fail(f"{p}:{n}", f"{direction} reads \"{label}\", the target's title is \"{expected}\"")

# ------------------------------- 6: filename, breadcrumb and H1 agree
for c in chapters:
    n = chapter_number(c)
    if lines[c] and f"Chapter {n}</sup>" not in lines[c][0]:
        fail(f"{c}:1", f"breadcrumb does not read Chapter {n}")
    if c not in title:
        fail(str(c), "no `# N. Title` heading found")
    elif title[c][0] != n:
        fail(str(c), f"H1 reads chapter {title[c][0]}, filename says {n}")

for a in appendices:
    letter = a.name[0]
    if lines[a] and f"Appendix {letter}</sup>" not in lines[a][0]:
        fail(f"{a}:1", f"breadcrumb does not read Appendix {letter}")

# ---------------------------------------- 7 and 8: the two chapter listings
readme = text[GUIDE / "README.md"]
listed = set(re.findall(r"\]\((\d\d-[A-Za-z0-9]+\.md)\)", readme))
on_disk = {c.name for c in chapters}
for name in sorted(on_disk - listed):
    fail("Guide/README.md", f"contents list is missing {name}")
for name in sorted(listed - on_disk):
    fail("Guide/README.md", f"contents list names a file that does not exist: {name}")

# The list marker is written out rather than left to markdown's own counting,
# so it can disagree with the file it points at. It reads as the chapter number
# and a reader will quote it, so it has to be the chapter number.
for n, line in enumerate(lines[GUIDE / "README.md"], 1):
    m = re.match(r"^(\d+)\. \*\*\[[^\]]+\]\((\d\d)-[A-Za-z0-9]+\.md\)", line)
    if m and m.group(1) != str(int(m.group(2))):
        fail(f"Guide/README.md:{n}", f"contents entry is numbered {m.group(1)}, the chapter is {int(m.group(2))}")

# A row still at `not started` is a chapter the plan has reserved and nobody
# has written yet, so it is the one row allowed to name a file that is not
# there. Every other row has to match something on disk, and every file on disk
# has to have a row.
plan = text[GUIDE / "PLAN.md"]
status = dict(re.findall(r"^\|[^|]*\|\s*`([^`]+\.md)`\s*\|\s*([^|]+?)\s*\|", plan, re.M))
expected_status = on_disk | {a.name for a in appendices}
for name in sorted(expected_status - set(status)):
    fail("Guide/PLAN.md", f"status table is missing {name}")
for name in sorted(set(status) - expected_status):
    if status[name] != "not started":
        fail("Guide/PLAN.md", f"status table says {name} is `{status[name]}`, but the file does not exist")

# --------------------------------------------- 9: every chapter token resolves
for label, path in (("PLAN", GUIDE / "PLAN.md"), ("Appendix D", GUIDE / "D-CompleteToolbox.md")):
    for n, line in enumerate(lines[path], 1):
        for token in re.findall(r"\bCh\.? *(\d+)", line):
            if token not in numbers:
                fail(f"{path}:{n}", f"names Ch {token}, which is not a chapter")

# A pointer reads `Guide Ch 17 § *A heading*`, or `§§ *One* + *Another*`, and it
# may chain (`§ *One* + § *Another*`). The binding has to be tight, because `§`
# is how this repository points into every document: `ARCHITECTURE.md § *X*` and
# `Docs §§ *Y*` sit in the same sentence as a chapter pointer, and a loose read
# hands their headings to the chapter. So a `§` counts only when `Ch N` is the
# thing immediately before it. The run then ends at the first thing that is not
# another italic joined by `+`, `/` or a comma, since everything past that is
# ordinary prose that happens to carry emphasis.
SEGMENT = re.compile(r"\*{0,2}Ch\.? *(\d+)\*{0,2}\s*§{1,2}\s*")
ITALIC = re.compile(r"\s*\*([^*]{2,140})\*")
JOIN = re.compile(r"\s*(?:\([^)]*\))?\s*(?:\+|/|,)\s*(?:§{1,2}\s*)?")


def pointed_headings(line, at):
    """The headings a `§` at this offset points at, and where the run ends."""
    found = []
    while True:
        m = ITALIC.match(line, at)
        if not m:
            return found
        found.append(m.group(1))
        at = m.end()
        j = JOIN.match(line, at)
        if not j:
            return found
        at = j.end()


for source in (pathlib.Path("CAPABILITIES.md"), pathlib.Path("CLAUDE.md"), pathlib.Path("DESIGN-NOTES.md")):
    if not source.exists():
        continue
    for n, line in enumerate(source.read_text().splitlines(), 1):
        for token in re.findall(r"Guide Ch\.? *(\d+)", line):
            if token not in numbers:
                fail(f"{source}:{n}", f"names Guide Ch {token}, which is not a chapter")
        for m in SEGMENT.finditer(line):
            chapter = m.group(1)
            if chapter not in numbers:
                continue
            pool = heading_text[chapter]
            for quoted in pointed_headings(line, m.end()):
                if quoted in pool:
                    continue
                longer = [h for h in pool if h.startswith(quoted + ":")]
                if longer:
                    note(f"{source}:{n}", f"Ch {chapter} § *{quoted}* names only the front of \"{longer[0]}\"")
                else:
                    fail(f"{source}:{n}", f"Ch {chapter} § *{quoted}* is not a heading in chapter {chapter}")

# Coverage-matrix Depth cells quote headings too, but they also quote ordinary
# prose, so a miss here is a note rather than an error.
inside = False
for n, line in enumerate(lines[GUIDE / "PLAN.md"], 1):
    if line.startswith("## Feature-coverage matrix"):
        inside = True
        continue
    if inside and line.startswith("## "):
        break
    if not inside or not line.startswith("| ") or re.match(r"^\|[- ]*-", line) or line.startswith("| Capability"):
        continue
    cells = line.split("|")
    if len(cells) < 4:
        continue
    home, depth = cells[2].strip(), cells[3].strip()
    pool = []
    for token in re.findall(r"Ch\.? *(\d+)", home):
        pool += heading_text.get(token, [])
    if not pool:
        continue
    for quoted in re.findall(r"\"([^\"]{4,140})\"", depth):
        # Headings are sentence case, so a quote opening lower case is prose.
        if quoted in pool or not quoted[:1].isupper():
            continue
        longer = [h for h in pool if h.startswith(quoted + ":")]
        if longer:
            note(f"Guide/PLAN.md:{n}", f"\"{quoted}\" names only the front of \"{longer[0]}\"")
        else:
            note(f"Guide/PLAN.md:{n}", f"\"{quoted}\" is not a heading in {home}")

# ------------------------------------------------------------------- report
for message in notes if list_notes else notes[:12]:
    print(f"guide-links: note: {message}")
if notes and not list_notes and len(notes) > 12:
    print(f"guide-links: note: {len(notes) - 12} more, run with --list")

for message in errors:
    print(f"guide-links: {message}", file=sys.stderr)

pages_checked = len(pages)
print(
    f"guide-links: {pages_checked} pages, {len(chapters)} chapters, "
    f"{len(referenced)} images, {len(errors)} errors, {len(notes)} notes"
)
sys.exit(1 if errors else 0)
PY
