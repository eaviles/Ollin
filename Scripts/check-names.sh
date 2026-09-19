#!/bin/zsh
#
# Scripts/check-names.sh: check that every name the prose puts in backticks
# is real, and that every pointer from the contributor files lands.
#
#   Scripts/check-names.sh           # check, exit nonzero on any error
#   Scripts/check-names.sh --list    # also print every note
#
# A rename sweeps the code and leaves the prose behind. The old word keeps
# reading fine, a grep for it still finds hits (in the prose itself), the
# snippets still compile (they never used it), and every link still resolves.
# The review pass of 2026-09-12 found this class by hand across 32 chapters:
# `minimumSpan` after the min/max naming rule, `spatialHash` after the make…
# rule, `.bloom(threshold:intensity:radius:)` after intensity became amount,
# `--debug` after the flag became `--no-optimize`. None of the other gates
# reads an inline backtick, so nothing could see it. This is that gate.
#
# What it reads: every `code span` in Docs/, Guide/, the root README and
# CAPABILITIES.md, with fenced blocks set aside (check-snippets.sh compiles
# those). What it reads against: every identifier in every tracked code file
# (Swift, Metal, C, scripts, workflows, the figure and snippet sketches),
# every tracked path and its components, and the public surface written down
# under API/. A page's own fenced Swift widens the oracle for that page by the
# names it defines (a `func drawMeteor` in the fence makes `drawMeteor` real
# in the prose around it); a fenced shell or text block widens it by every
# word it holds.
#
# Six checks:
#
#   1. Every identifier in a code span exists somewhere in that oracle.
#      Arguments inside parentheses are the reader's (`textured(maskImage)`),
#      quoted strings are the reader's, hex colors are colors, a name that
#      starts My… or Your… is a placeholder, and a prefix written with a
#      trailing underscore or a glob (`ollin_mesh_*`) matches any name that
#      starts with it.
#   2. A call written with its labels, `name(a:b:)`, matches a public overload
#      in API/ by name and by label, in order. Labels may be left out (the
#      prose often names the interesting ones), and a variadic parameter takes
#      a run of them, but a label the surface does not spell is a failure.
#      `Type.name(...)` is looked up on that type when Ollin declares it, and
#      left alone when the type is the platform's (`Double.random(in:)`).
#      A name the page defines in its own fence is not checked here.
#   3. A `--flag` is spelled somewhere in Sources/, Scripts/, Apps/, Tests/,
#      or the workflows.
#   4. A repository path exists, a `Group/Name` names an example (either
#      level of the examples' two-level catalog), and a `.md#anchor` lands on
#      a heading or an explicit `<a id>`. The bare `Docs/…` and `Guide/…`
#      pointers in CAPABILITIES.md, CLAUDE.md, DESIGN-NOTES.md, ROADMAP.md,
#      ARCHITECTURE.md, AGENTS.md and the Guide's PLAN and AUTHORING pages
#      get the same check; check-links.sh reads none of those files.
#   5. Appendix D's Contents line lists its sections, in order.
#   6. Every CAPABILITIES.md bullet that names a Docs/ page can be found in
#      Appendix D by a word of its name (stemmed, stop words dropped). A
#      bullet that names no Docs/ page is internal and only noted.
#
# What it cannot see: a stale name whose spelling survives elsewhere as an
# unrelated identifier (`physarum(agents:)` after the facade became
# `makePhysarum`, while `physarum` lives on as a variable), and a call written
# without labels. Both are what the label check is for, so write selectors
# with their labels where the prose is about the call.
#
# Foreign names the prose has reason to use, from p5 and Processing in
# Appendix C to Apple types the code never spells as an identifier, live in
# Scripts/check-names-allow.txt, one per line with a comment saying which
# class it belongs to. The p5 column of a comparison table is skipped without
# being listed: a table whose first header cell names p5, Processing,
# openFrameworks or OPENRNDR has a foreign first column by construction.
#
# About two seconds. Run it on every change, since a rename in Sources/ stales
# prose the diff never touched; preflight does.

cd "$(dirname "$0")/.." || exit 1

list=0
case "$1" in
--list) list=1 ;;
--help | -h)
    sed -n '3,66p' "$0" | sed 's|^# \?||'
    exit 0
    ;;
esac

python3 - "$list" <<'PY'
import bisect
import collections
import os
import pathlib
import re
import subprocess
import sys

list_notes = sys.argv[1] == "1"

IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
SPAN = re.compile(r"`([^`\n]+)`")
DEFN = re.compile(r"\b(?:func|var|let|class|struct|enum|protocol|typealias|case|actor|for)\s+([A-Za-z_][A-Za-z0-9_]*)")
PHRASE = re.compile(r"^[A-Z][a-z]+(?: [a-z]+)+$")
POINTER = re.compile(r"(?:Docs|Guide)/[A-Za-z0-9_./-]+\.md(?:#[A-Za-z0-9_-]+)?")
SELECTOR = re.compile(r"^((?:[A-Za-z_][A-Za-z0-9_]*\.)*)\.?([A-Za-z_][A-Za-z0-9_]*)\(((?:(?:[A-Za-z_][A-Za-z0-9_]*|_):)*)(…|\.\.\.)?\)$")
PLACEHOLDER = re.compile(r"^(?:my|your)[A-Z]|(?:My|Your)[A-Z]|^yourthing$", re.I)
FOREIGN_TABLE = re.compile(r"\bp5(?:\.js)?\b|Processing|openFrameworks|OPENRNDR", re.I)
CODE_EXT = {".swift", ".metal", ".h", ".c", ".cpp", ".mm", ".m", ".py", ".sh", ".js", ".yml", ".yaml", ".json", ".txt", ".plist", ".entitlements", ".html", ".css", ".toml"}
FLAG_ROOTS = ("Sources/", "Scripts/", "Apps/", "Tests/", ".github/")
TOP = ("Sources", "Tests", "Scripts", "Examples", "Docs", "Guide", "API", "External", "Apps", "Media", "Logo", "Web")
CONTRIBUTOR = ("CAPABILITIES.md", "CLAUDE.md", "DESIGN-NOTES.md", "ROADMAP.md", "ARCHITECTURE.md", "AGENTS.md", "Guide/PLAN.md", "Guide/AUTHORING.md")
STOP = {"the", "and", "for", "with", "from", "that", "this", "their", "every", "into", "over", "under", "your", "when", "what", "where", "which", "them", "than", "then", "there", "these", "those", "have", "been", "were", "will", "also", "more", "most", "some", "such", "each", "only", "very", "much", "many", "here", "part", "thing", "things", "ones", "between", "drawn", "other", "world", "worlds", "flat", "scale", "sketch", "output", "mode", "input", "one", "two", "its", "own", "out", "off", "all", "any", "how", "why", "who", "not", "but", "you", "can", "may", "are", "was", "has", "had", "did", "does", "per", "via", "etc", "core"}

errors, notes = [], []


def fail(where, message):
    errors.append(f"{where}: {message}")


def note(where, message):
    notes.append(f"{where}: {message}")


def stem(word):
    """A rough stem, the same on both sides: wavetables, wavetable and sampled, samples, sample agree."""
    for suffix in ("ings", "ing", "ies", "ed", "es", "s"):
        if len(word) > len(suffix) + 2 and word.endswith(suffix):
            word = word[: -len(suffix)]
            break
    if len(word) > 3 and word[-1] == word[-2] and word[-1] not in "aeiou":
        word = word[:-1]                     # cutting -> cutt -> cut
    return word[:-1] if len(word) > 3 and word.endswith("e") else word


def slug(heading):
    """The anchor GitHub derives from a heading (the same rule check-links.sh uses)."""
    s = re.sub(r"<[^>]+>", "", heading)
    s = s.lower()
    s = re.sub(r"[^\w\s-]", "", s)
    return re.sub(r"\s+", "-", s.strip())


def blank_fences(text):
    """The prose with every fenced line blanked (line numbers hold), and the fences by language."""
    out, fences, fenced, lang, buf = [], [], False, "", []
    for line in text.split("\n"):
        if line.startswith("```"):
            if fenced:
                fences.append((lang, "\n".join(buf)))
                buf = []
            else:
                lang = line[3:].strip().lower()
            fenced = not fenced
            out.append("")
            continue
        if fenced:
            buf.append(line)
            out.append("")
        else:
            out.append(line)
    return out, fences


# ------------------------------------------------------------------ oracle
# Tracked and untracked alike, so a file added in the same change as the prose
# that names it is already real (preflight runs before the commit).
files = [f for f in subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"], capture_output=True, text=True).stdout.split("\n") if f and os.path.exists(f)]
tracked = set(files)
dirs = set()
for f in files:
    parts = f.split("/")
    for i in range(1, len(parts)):
        dirs.add("/".join(parts[:i]))
example_groups = {d.split("/")[1] for d in dirs if d.startswith("Examples/") and d.count("/") == 1}

oracle = set()
flag_text = []
for f in files:
    for part in f.split("/"):
        oracle.update(IDENT.findall(part))
        oracle.add(part)
    path = pathlib.Path(f)
    if path.suffix in CODE_EXT:
        try:
            text = path.read_text(errors="ignore")
        except OSError:
            continue
        oracle.update(IDENT.findall(text))
        if f.startswith(FLAG_ROOTS) and path.suffix in (".swift", ".sh", ".py", ".metal", ".yml"):
            flag_text.append(text)
    elif f.startswith("Scripts/") and path.suffix == "":
        flag_text.append(path.read_text(errors="ignore"))    # the extensionless wrappers: ollin, OllinLive, …
flag_text = "\n".join(flag_text)
oracle_sorted = sorted(oracle)


def has_prefix(fragment):
    i = bisect.bisect_left(oracle_sorted, fragment)
    return i < len(oracle_sorted) and oracle_sorted[i].startswith(fragment)


def has_suffix(fragment):
    return any(name.endswith(fragment) for name in oracle_sorted)


# The public surface: every callable under API/ with its labels, by name and
# by the type it belongs to. Types nest by indentation in the listings.
DECL = re.compile(
    r"^(\s*)(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:open |public |final |indirect |static |class |mutating |nonisolated |convenience |override |required |unowned |weak |lazy |optional |dynamic |unsafe |nonmutating )*"
    r"(?:(?P<kind>func|case|init|subscript)[?!]?\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)?"
    r"|(?P<tkind>struct|class|enum|actor|protocol|extension)\s+(?P<tname>[A-Za-z_][A-Za-z0-9_.]*))"
)
overloads = collections.defaultdict(list)          # name -> [(labels, variadics)]
members = collections.defaultdict(lambda: collections.defaultdict(list))  # type -> name -> [...]
declared_types = set()                            # types Ollin declares (not merely extends)
type_paths = collections.defaultdict(set)          # short name -> {dotted paths}


def parameters(rest):
    """Labels and variadic flags from the text after a declaration's name."""
    if not rest.startswith("("):
        return [], []
    depth = 0
    end = 0
    for end, ch in enumerate(rest):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                break
    labels, variadics = [], []
    for param in re.split(r",(?![^\[(<]*[\])>])", rest[1:end]):
        param = param.strip()
        if not param:
            continue
        m = re.match(r"([A-Za-z_][A-Za-z0-9_]*|_)\s*(?:[A-Za-z_][A-Za-z0-9_]*)?\s*:", param)
        if m:
            labels.append(m.group(1))
            variadics.append(param.rstrip().endswith("...") or "..." in param.split("=")[0])
        else:
            labels.append("_")            # an unlabeled case payload
            variadics.append(False)
    return labels, variadics


for listing in sorted(pathlib.Path("API").glob("*.txt")):
    stack = []                                     # [(indent, type path)]
    for line in listing.read_text().split("\n"):
        m = DECL.match(line)
        if not m:
            continue
        indent = len(m.group(1))
        while stack and stack[-1][0] >= indent:
            stack.pop()
        if m.group("tname"):
            short = m.group("tname").split(".")[-1].split("<")[0]
            path = ".".join([t for _, t in stack] + [short]) if m.group("tkind") != "extension" else m.group("tname").split("<")[0]
            if m.group("tkind") != "extension":
                declared_types.add(path)
            type_paths[short].add(path)
            stack.append((indent, path))
            continue
        kind, name = m.group("kind"), m.group("name")
        owner = stack[-1][1] if stack else ""
        if kind == "init":
            name = owner.split(".")[-1] if owner else None
        if not name:
            continue
        labels, variadics = parameters(line[m.end():].lstrip("?!").lstrip())
        overloads[name].append((labels, variadics))
        if owner:
            members[owner][name].append((labels, variadics))


# Every declaration in Sources/ and Apps/, public or not, by name. The
# contributor files name internals beside the public surface, so a label
# there has to match something in the tree rather than something exported.
# An initializer is kept under "init" without its type: a contributor page
# writing `Type(a:b:)` for an internal type is matched against every internal
# init, which is loose, and the public surface is what the reader pages are
# held to.
internal = collections.defaultdict(list)
SIGNATURE = re.compile(r"\b(func|init|case)\s*[?!]?\s*([A-Za-z_][A-Za-z0-9_]*)?\s*(?=\()")
for f in files:
    if not f.startswith(("Sources/", "Apps/")) or not f.endswith(".swift"):
        continue
    text = pathlib.Path(f).read_text(errors="ignore")
    for m in SIGNATURE.finditer(text):
        kind, name = m.group(1), m.group(2)
        if kind == "init":
            name = "init"
        if not name:
            continue
        labels, variadics = parameters(text[m.end():m.end() + 4000])
        internal[name].append((labels, variadics))


def labels_match(prose, labels, variadics):
    i = 0
    for label, variadic in zip(labels, variadics):
        if i < len(prose) and prose[i] == label:
            i += 1
            while variadic and i < len(prose) and prose[i] == label:
                i += 1
    return i == len(prose)


def spell(name, candidates):
    return ", ".join(f"{name}({''.join(l + ':' for l in labels)})" for labels, _ in candidates[:4])


# --------------------------------------------------------------- allowlist
allow = set()
allow_file = pathlib.Path("Scripts/check-names-allow.txt")
if allow_file.exists():
    for line in allow_file.read_text().split("\n"):
        line = line.split("#")[0].strip()
        if line:
            allow.add(line)

# ------------------------------------------------------------------ anchors
anchor_cache = {}


def anchors_of(path):
    if path not in anchor_cache:
        lines, _ = blank_fences(pathlib.Path(path).read_text())
        found = set()
        for line in lines:
            m = re.match(r"^(#{1,6})\s+(.*?)\s*$", line)
            if m:
                found.add(slug(m.group(2)))
            found.update(re.findall(r'<a (?:id|name)="([^"]+)"', line))
        anchor_cache[path] = found
    return anchor_cache[path]


def check_path(where, spelled):
    """A repository path as the prose spells it: with :line, #anchor, a trailing slash."""
    if "<" in spelled or "…" in spelled or "*" in spelled:
        return
    s = re.sub(r":\d+(?::\d+)?$", "", spelled)
    path, _, anchor = s.partition("#")
    path = path.rstrip("/")
    parts = path.split("/")
    if any(part.startswith(".") for part in parts) or any(PLACEHOLDER.search(part) for part in parts):
        return
    candidates = [path]
    if path.startswith("Examples/") and len(parts) == 3:
        group, name = parts[1], parts[2]
        candidates += [d for d in dirs if d.startswith(f"Examples/{group}/") and d.count("/") == 3 and d.endswith("/" + name)]
    found = next((c for c in candidates if c in tracked or c in dirs), None)
    if found is None:
        fail(where, f"names {spelled}, which does not exist")
        return
    if anchor and found.endswith(".md") and anchor not in anchors_of(found):
        fail(where, f"points at {spelled}, and no heading in {found} has that anchor")


# --------------------------------------------------------------- the prose
def prepared(span):
    """The span with the reader's parts removed: quoted strings and hex colors."""
    s = re.sub(r'"[^"]*"', '""', span)
    s = re.sub(r"'[^']*'", "''", s)
    return re.sub(r"#[0-9a-fA-F]{3,8}\b", "", s)


def is_argument(span, match):
    """An identifier inside parentheses that is neither a label nor a member."""
    depth = 0
    for i, ch in enumerate(span[: match.start()]):
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
    if depth <= 0:
        return False
    if match.start() > 0 and span[match.start() - 1] == ".":
        return False
    return not re.match(r"\s*:", span[match.end():])


prose = [f for f in files if f.endswith(".md") and (f.startswith(("Docs/", "Guide/")) or f in ("README.md", "CAPABILITIES.md"))]
spans = 0
for f in prose:
    lines, fences = blank_fences(pathlib.Path(f).read_text())
    reader_facing = f not in CONTRIBUTOR
    local = set()
    for lang, code in fences:
        if lang in ("swift", "metal"):
            local.update(DEFN.findall(code))
        else:
            local.update(IDENT.findall(code))
    foreign_column = False
    for n, line in enumerate(lines, 1):
        if line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if not foreign_column and cells and FOREIGN_TABLE.search(cells[0]):
                foreign_column = True
                continue
            if foreign_column:
                line = "|" + "|".join(cells[1:])
        else:
            foreign_column = False
        where = f"{f}:{n}"
        for span in SPAN.findall(line):
            s = span.strip()
            spans += 1
            if not s or s in allow or PHRASE.match(s):
                continue
            if s.startswith("--"):
                m = re.match(r"--[a-z0-9-]+", s)
                if m and m.group(0) not in flag_text:
                    fail(where, f"names the flag {m.group(0)}, which no host or script spells")
                continue
            if "/" in s and " " not in s:
                head = s.split("/")[0]
                if ".md" in s and f"Docs/{s.partition('#')[0]}" in tracked:
                    check_path(where, "Docs/" + s)   # a Docs-relative pointer, as the matrix writes them
                    continue
                if head in TOP:
                    check_path(where, s)
                    continue
                if head in example_groups and re.match(r"^[A-Za-z0-9-]+/[A-Za-z0-9-]+(?:/[A-Za-z0-9.-]+)?$", s):
                    check_path(where, "Examples/" + s)
                    continue
            sel = SELECTOR.match(s)
            if sel and sel.group(3) and sel.group(2) not in local:
                qualifier, name = sel.group(1).rstrip("."), sel.group(2)
                prose_labels = [x for x in sel.group(3).split(":") if x]
                candidates = overloads.get(name, [])
                owner, paths = "", set()
                if qualifier:
                    owner = qualifier.split(".")[-1]
                    paths = type_paths.get(owner, set())
                    nested = [p for p in type_paths.get(name, set()) if p.endswith(f"{owner}.{name}")]
                    if nested:                           # `A.B(...)` is B's initializer, B nested in A
                        candidates = [o for p in nested for o in members[p].get(name, [])]
                    elif paths:
                        candidates = [o for p in paths for o in members[p].get(name, [])]
                        if not candidates and not any(p in declared_types for p in paths):
                            candidates = None            # a platform type Ollin only extends
                    else:
                        candidates = None                # not a type the listings know
                if candidates is None or (name[0].isupper() and not any(p in declared_types for p in type_paths.get(name, ()))):
                    continue                             # the platform's own type: `String(describing:)`
                if not reader_facing:
                    candidates = candidates + internal.get(name, []) + (internal.get("init", []) if name[0].isupper() else [])
                if candidates:
                    if not any(labels_match(prose_labels, L, V) for L, V in candidates):
                        fail(where, f"writes {s}, and no {'public ' if reader_facing else ''}{name} takes those labels (declared: {spell(name, candidates)})")
                    continue
                if reader_facing and qualifier and paths:
                    fail(where, f"writes {s}, and {owner} has no public member {name}")
                    continue
            s = prepared(s)
            glob = "*" in s or "…" in s
            for m in IDENT.finditer(s):
                token = m.group(0)
                if token in oracle or token in local or token in allow:
                    continue
                if sum(c.isalpha() for c in token) < 4 or PLACEHOLDER.search(token):
                    continue
                if is_argument(s, m):
                    continue
                if (glob or token.endswith("_")) and has_prefix(token):
                    continue
                if (glob or token.startswith("_")) and has_suffix(token):
                    continue
                fail(where, f"names {token}, which exists nowhere in the tree")

# The bare pointers in the contributor files.
for f in CONTRIBUTOR:
    if not pathlib.Path(f).exists():
        continue
    seen = set()
    for n, line in enumerate(pathlib.Path(f).read_text().split("\n"), 1):
        for m in POINTER.finditer(line):
            if (n, m.group(0)) in seen:
                continue
            seen.add((n, m.group(0)))
            check_path(f"{f}:{n}", m.group(0))

# --------------------------------------------------------------- Appendix D
appendix = "Guide/D-CompleteToolbox.md"
appendix_text = pathlib.Path(appendix).read_text()
appendix_lines, _ = blank_fences(appendix_text)
contents = [a for line in appendix_lines if line.startswith("**Contents:**") for a in re.findall(r"\(#([a-z0-9-]+)\)", line)]
sections = [slug(m.group(1)) for line in appendix_lines if (m := re.match(r"^## (.*)$", line))]
if contents != sections:
    fail(appendix, f"the Contents line lists {contents} but the sections are {sections}")
appendix_stems = {stem(w) for w in re.findall(r"[a-z0-9]+", appendix_text.lower())}
bullets = 0
started = False
for n, line in enumerate(pathlib.Path("CAPABILITIES.md").read_text().split("\n"), 1):
    if line.startswith("## "):
        started = True
    m = re.match(r"^- \*\*(.+?)\*\*(.*)$", line) if started else None
    if not m:
        continue
    bullets += 1
    name, rest = m.group(1).rstrip("."), m.group(2)
    if "Docs/" not in rest and "Docs/" not in name:
        note(f"CAPABILITIES.md:{n}", f"bullet '{name}' names no Docs/ page, so Appendix D is not asked for it")
        continue
    words = [w for w in re.findall(r"[a-z0-9]+", name.lower()) if len(w) >= 3 and w not in STOP]
    if words and not any(stem(w) in appendix_stems for w in words):
        fail(f"CAPABILITIES.md:{n}", f"bullet '{name}' has none of {words} anywhere in Appendix D")

# ------------------------------------------------------------------- report
for message in notes if list_notes else notes[:12]:
    print(f"check-names: note: {message}")
if notes and not list_notes and len(notes) > 12:
    print(f"check-names: note: {len(notes) - 12} more, run with --list")
for message in errors:
    print(f"check-names: {message}", file=sys.stderr)
print(
    f"check-names: {len(prose)} pages, {spans} code spans, {len(oracle)} names in the tree, "
    f"{sum(len(v) for v in overloads.values())} public overloads, {bullets} capability bullets, "
    f"{len(errors)} errors, {len(notes)} notes"
)
sys.exit(1 if errors else 0)
PY
