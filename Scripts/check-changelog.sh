#!/bin/zsh
#
# Scripts/check-changelog.sh: keep a changelog entry short enough to read.
#
#   Scripts/check-changelog.sh             # CHANGELOG.md, from 0.18.0 up
#   Scripts/check-changelog.sh --selftest  # a long entry and an untitled one must fail
#
# Somebody reading the changelog, or the release page made from it, wants two
# things from an entry: what changed, and what to type or do about it. The
# measurements, the cause of a defect, and the full list of what a call takes
# live on the reference page the entry links, and in CAPABILITIES.md.
#
# The form, for every entry from 0.18.0 on:
#
#   - **A title in plain words.** One or two short sentences with the call to
#     type. For a change: what is different, and what to do to get the old
#     behavior. [The page](Docs/...) when one exists.
#
# What fails:
#
#   - an entry that does not open with its bold title;
#   - an entry over 60 words, link targets not counted (a second thing to say
#     is a second entry);
#   - a paragraph over 80 words (the few lines that open a release, or a
#     section).
#
# Under a heading, a bold line by itself (**Drawing**) groups the entries by
# area once a list is long. The sections for 0.17.0 and before keep the form
# they were published in, so this reads only what stands above that heading.
#
# Why a gate: the entries were cut to two sentences once, on 2026-09-12, and
# were back at a median of 91 words with one of 401 two months later, each
# written by a session with every number still in its head. Milliseconds, so
# preflight runs it every time.

cd "$(dirname "$0")/.." || exit 1

python3 - "$@" <<'PY'
import re, sys, pathlib

ENTRY_WORDS = 60
PARAGRAPH_WORDS = 80
FLOOR = "## [0.17.0]"


def words(line):
    return len(re.sub(r"\]\([^)]*\)", "]", line).split())


def check(text, name="CHANGELOG.md"):
    problems = []
    inside = False
    for number, line in enumerate(text.split("\n"), 1):
        if line.startswith("## ["):
            if line.startswith(FLOOR):
                break
            inside = True
            continue
        if not inside or not line.strip() or line.startswith("#"):
            continue
        if re.fullmatch(r"\*\*[^*]+\*\*", line.strip()):
            continue
        if re.match(r"\[[^\]]+\]: \S+$", line):
            continue
        count = words(line)
        where = f"{name}:{number}"
        if line.startswith("- "):
            if not re.match(r"- \*\*(?:[^*]|\*(?!\*))+[.?!]\*\*( |$)", line):
                problems.append(f"{where}: an entry opens with its title in bold, ending in a period")
            if count > ENTRY_WORDS:
                problems.append(f"{where}: {count} words, over {ENTRY_WORDS}: {line[2:60]}...")
        elif count > PARAGRAPH_WORDS:
            problems.append(f"{where}: a paragraph of {count} words, over {PARAGRAPH_WORDS}")
    return problems


if "--selftest" in sys.argv[1:]:
    good = "- **A pen.** `strokeMedium(.ink())` draws ink from a nib. [Marks](Docs/Drawing/Marks.md#ink)"
    long_entry = "- **A pen.** " + " ".join(["word"] * ENTRY_WORDS)
    untitled = "- A pen draws ink."
    old = "- " + " ".join(["word"] * 300)
    link_heavy = "- **A pen.** " + " ".join(["[a](" + "x" * 40 + " y z)"] * 20)
    cases = [
        ("a short titled entry", f"## [Unreleased]\n\n### Added\n\n**Drawing**\n\n{good}\n", 0),
        ("an entry over the cap", f"## [Unreleased]\n\n{long_entry}\n", 1),
        ("an entry with no title", f"## [Unreleased]\n\n{untitled}\n", 1),
        ("a title with a work's name in italics", "## [Unreleased]\n\n- **A *plate* redrawn.** It is.\n", 0),
        ("link targets are not counted", f"## [Unreleased]\n\n{link_heavy}\n", 0),
        ("a long paragraph", "## [Unreleased]\n\n" + " ".join(["word"] * (PARAGRAPH_WORDS + 1)) + "\n", 1),
        ("the sections already published", f"## [Unreleased]\n\n{good}\n\n{FLOOR} - 2026-10-25\n\n{old}\n", 0),
    ]
    failed = 0
    for label, text, expected in cases:
        found = len(check(text, "selftest"))
        if found != expected:
            failed += 1
            print(f"check-changelog selftest: {label}: expected {expected} problem(s), found {found}")
    if failed:
        sys.exit(1)
    print(f"check-changelog selftest: {len(cases)} cases behave")
    sys.exit(0)

problems = check(pathlib.Path("CHANGELOG.md").read_text(encoding="utf-8"))
for problem in problems:
    print(problem)
if problems:
    print(f"check-changelog: {len(problems)} problem(s). An entry is a title and a line or two; "
          "the rest belongs on the page it links (Scripts/check-changelog.sh has the form).")
    sys.exit(1)
print("check-changelog: every entry since 0.17.0 is a title and a line or two")
PY
