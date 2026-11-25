#!/bin/zsh
#
# Scripts/check-changelog.sh: keep a changelog entry short enough to read.
#
#   Scripts/check-changelog.sh             # CHANGELOG.md, every section
#   Scripts/check-changelog.sh --selftest  # a long entry and an untitled one must fail
#
# Somebody reading the changelog, or the release page made from it, wants two
# things from an entry: what changed, and what to type or do about it. The
# measurements, the cause of a defect, and the full list of what a call takes
# live on the reference page the entry links, and in CAPABILITIES.md.
#
# The form, for every entry:
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
# area once a list is long. Every section is read, the first release included:
# 0.7.0 to 0.17.0 were rewritten in this form on 2026-11-19 and 0.1.0 to 0.6.0
# on 2026-11-25. The link reference lines at the foot of the file are skipped.
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


def words(line):
    return len(re.sub(r"\]\([^)]*\)", "]", line).split())


def check(text, name="CHANGELOG.md"):
    problems = []
    inside = False
    for number, line in enumerate(text.split("\n"), 1):
        if line.startswith("## ["):
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
        ("the oldest section is read too", f"## [Unreleased]\n\n{good}\n\n## [0.1.0] - 2026-09-02\n\n{old}\n", 2),
        ("the link lines at the foot", f"## [0.1.0] - 2026-09-02\n\n{good}\n\n[0.1.0]: https://example.com/{'x' * 400}\n", 0),
        ("the lines above the first section", " ".join(["word"] * 200) + f"\n\n## [Unreleased]\n\n{good}\n", 0),
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
print("check-changelog: every entry is a title and a line or two")
PY
