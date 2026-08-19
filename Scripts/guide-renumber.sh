#!/bin/zsh
#
# Scripts/guide-renumber.sh: move Guide chapters to new numbers, everywhere.
#
#   Scripts/guide-renumber.sh 7=8 8=9 9=10       # chapter 7 becomes 8, and so on
#   Scripts/guide-renumber.sh --from 7 --shift 1 # chapters 7 and up move up by one
#   Scripts/guide-renumber.sh --dry-run ...      # print what would change
#
# Splitting a chapter renumbers every chapter after it, and the number is
# carried by more surfaces than anyone can hold in their head: the file itself,
# both asset trees, the breadcrumb, the H1, two footer links per neighbour, the
# contents list, the status table, the coverage matrix, Appendix D's 226 rows,
# and the section pointers in CAPABILITIES.md. Doing that by hand once is a
# long afternoon. Doing it eleven times is how a Guide quietly stops matching
# itself, so it is a command instead.
#
# Two rules make it safe:
#
#   Every rename happens in one pass. Moving 7 to 8 while 8 moves to 9 cannot
#   be done as two edits, because the first turns the old 7 into an 8 and the
#   second then moves it again. The substitution reads the whole map at once,
#   so each number is rewritten from what it was, never from what it became.
#
#   Only forms that unambiguously mean a chapter are touched: a `NN-Name.md`
#   filename, an `Images/NN-Name` or `Figures/NN-Name` path, a `[Chapter N]` or
#   `[Ch N]` link label, `Guide Ch N`, a breadcrumb, an H1, and the bare `Ch N`
#   and `Chapter N` tokens inside the Guide's own files and PLAN.md, where a
#   bare number can only mean a chapter. Nothing under Examples/, Sources/ or
#   Scripts/ is read at all, which keeps the Osamu Sato recreations safe: their
#   "Chapter N" comments are chapters of somebody else's book.
#
# Run Scripts/guide-links.sh afterwards. That is the check that the move landed.

cd "$(dirname "$0")/.." || exit 1

emulate -L zsh
setopt no_nomatch

[[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]] && { sed -n '3,35p' "$0" | sed 's|^# \?||'; exit 0 }

python3 - "$@" <<'PY'
import pathlib, re, subprocess, sys

args = sys.argv[1:]
dry_run = "--dry-run" in args
args = [a for a in args if a != "--dry-run"]

GUIDE = pathlib.Path("Guide")
chapters = sorted(GUIDE.glob("[0-9]*.md"))
by_number = {int(c.name[:2]): c for c in chapters}

# ------------------------------------------------------------------ the map
mapping = {}
if "--from" in args:
    start = int(args[args.index("--from") + 1])
    shift = int(args[args.index("--shift") + 1])
    for n in by_number:
        if n >= start:
            mapping[n] = n + shift
else:
    for pair in args:
        old, _, new = pair.partition("=")
        try:
            mapping[int(old)] = int(new)
        except ValueError:
            print(f"guide-renumber: not a chapter pair: {pair}", file=sys.stderr)
            sys.exit(2)

mapping = {o: n for o, n in mapping.items() if o != n}
if not mapping:
    print("guide-renumber: nothing to do")
    sys.exit(0)

for old in mapping:
    if old not in by_number:
        print(f"guide-renumber: chapter {old} does not exist", file=sys.stderr)
        sys.exit(2)

landing = list(mapping.values())
if len(set(landing)) != len(landing):
    print("guide-renumber: two chapters would land on the same number", file=sys.stderr)
    sys.exit(2)

untouched = {n for n in by_number if n not in mapping}
if untouched & set(landing):
    clash = sorted(untouched & set(landing))
    print(f"guide-renumber: would land on occupied chapter(s) {clash}", file=sys.stderr)
    sys.exit(2)

stems = {old: by_number[old].name[3:-3] for old in mapping}


def renumbered(old, name):
    return f"{mapping[old]:02d}-{name}"


# --------------------------------------------------------------- the rewrite
# One alternation, matched left to right in a single scan. Running these as
# separate passes is the obvious way to write it and it is wrong: the label
# pass turns `[Chapter 7,` into `[Chapter 8,`, and a later bare-`Chapter` pass
# then reads that 8 as an original and moves it again. One scan means every
# match is consumed once, so a number is only ever rewritten from what it was.
#
# Order inside the alternation is the tie-break where two forms could start at
# the same place, so the specific ones come before the bare ones.
FORMS = (
    r"(?P<pnum>\d\d)-(?P<pname>[A-Za-z0-9]+)\.md"
    r"|(?P<atree>(?:Images|Figures)/)(?P<anum>\d\d)-(?P<aname>[A-Za-z0-9]+)"
    # A figure is often cited by its folder alone, with no tree in front of it
    # (`16-Simulations/ArtificialLife`). Gated on the stem matching a chapter,
    # so an ordinary number followed by a slash cannot be caught by accident.
    r"|(?<![\w/-])(?P<dnum>\d\d)-(?P<dname>[A-Za-z0-9]+)(?=/)"
    r"|\[Chapter (?P<label>\d+)(?=[,:\]])"
    r"|\[Ch (?P<short>\d+)\]"
    r"|\bGuide(?:'s)? Ch\.? *(?P<named>\d+)"
    r"|→ Chapter (?P<crumb>\d+)</sup>"
    r"|(?P<sect>\bCh\.? *(?P<sectnum>\d+)(?= *§))"
    r"|^# (?P<title>\d+)\. "
)

# Two more only fire in files where a bare chapter token cannot mean anything
# else: the Guide's own pages, including its plan and Appendix D's tables.
BARE = r"|^(?P<rowpfx>\|\s*|\*\*)(?P<row>\d+)\. |\bCh\.? *(?P<barech>\d+)\b|\bChapter (?P<barechapter>\d+)\b"

WIDE = re.compile(FORMS, re.M)
NARROW = re.compile(FORMS + BARE, re.M)

scope = sorted(GUIDE.glob("*.md"))
scope += [pathlib.Path(p) for p in ("CAPABILITIES.md", "CLAUDE.md", "DESIGN-NOTES.md", "README.md", "ROADMAP.md", "ARCHITECTURE.md")]
scope += sorted(pathlib.Path("Docs").rglob("*.md"))
scope = [p for p in scope if p.exists()]

bare_scope = {p for p in scope if p.parts[0] == "Guide"}

# Nearly every figure sketch opens with a comment naming the chapter it serves,
# so those go stale on a renumber exactly like the prose does. Only comment
# lines are touched, and only the `Chapter N` form, so nothing can reach code.
# A line often names two chapters ("the Chapter 10 flock, rebuilt"), so the
# whole line is rewritten rather than its first match.
figures = sorted(GUIDE.glob("Figures/**/*.swift"))
CHAPTER = re.compile(r"\bChapter (\d+)\b")


def moved(n):
    return mapping.get(int(n), int(n))


def substitute(m):
    g = m.groupdict()
    if g["pnum"] is not None:
        n, name = int(g["pnum"]), g["pname"]
        return f"{renumbered(n, name)}.md" if stems.get(n) == name else m.group(0)
    if g["anum"] is not None:
        n, name = int(g["anum"]), g["aname"]
        return f"{g['atree']}{renumbered(n, name)}" if stems.get(n) == name else m.group(0)
    if g["dnum"] is not None:
        n, name = int(g["dnum"]), g["dname"]
        return renumbered(n, name) if stems.get(n) == name else m.group(0)
    if g["label"] is not None:
        return f"[Chapter {moved(g['label'])}"
    if g["short"] is not None:
        return f"[Ch {moved(g['short'])}]"
    if g["named"] is not None:
        return m.group(0).replace(g["named"], str(moved(g["named"])))
    if g["crumb"] is not None:
        return f"→ Chapter {moved(g['crumb'])}</sup>"
    if g["sect"] is not None:
        return m.group(0).replace(g["sectnum"], str(moved(g["sectnum"])))
    if g["title"] is not None:
        return f"# {moved(g['title'])}. "
    if g.get("row") is not None:
        return f"{g['rowpfx']}{moved(g['row'])}. "
    if g.get("barech") is not None:
        return m.group(0).replace(g["barech"], str(moved(g["barech"])))
    if g.get("barechapter") is not None:
        return f"Chapter {moved(g['barechapter'])}"
    return m.group(0)


def rewrite(path, body):
    return (NARROW if path in bare_scope else WIDE).sub(substitute, body)


changed = []
for path in scope:
    before = path.read_text()
    after = rewrite(path, before)
    if after != before:
        changed.append(path)
        if not dry_run:
            path.write_text(after)

for path in figures:
    before = path.read_text()
    after = "".join(
        CHAPTER.sub(lambda m: f"Chapter {moved(m.group(1))}", line) if line.lstrip().startswith("//") else line
        for line in before.splitlines(keepends=True)
    )
    if after != before:
        changed.append(path)
        if not dry_run:
            path.write_text(after)

# ------------------------------------------------------------------ the moves
moves = []
for old, name in stems.items():
    new = renumbered(old, name)
    moves.append((GUIDE / f"{old:02d}-{name}.md", GUIDE / f"{new}.md"))
    for tree in ("Figures", "Images"):
        source = GUIDE / tree / f"{old:02d}-{name}"
        if source.is_dir():
            moves.append((source, GUIDE / tree / new))

# Two hops, through a scratch name, so a chapter moving onto a number another
# chapter is vacating in the same run cannot collide on disk.
if not dry_run:
    for source, target in moves:
        subprocess.run(["git", "mv", str(source), f"{target}.moving"], check=True)
    for _, target in moves:
        subprocess.run(["git", "mv", f"{target}.moving", str(target)], check=True)

print(f"guide-renumber: {'would move' if dry_run else 'moved'} " + ", ".join(f"{o}->{n}" for o, n in sorted(mapping.items())))
print(f"guide-renumber: {len(moves)} paths, {len(changed)} files rewritten")
if dry_run:
    for path in changed:
        print(f"  {path}")
else:
    print("guide-renumber: now run Scripts/guide-links.sh")
PY
