#!/bin/zsh
#
# Scripts/check-flags.sh: hold the command's flags and its completions to each
# other.
#
#   Scripts/check-flags.sh            # check, exit nonzero on any difference
#   Scripts/check-flags.sh --record   # rewrite Scripts/completions/_ollin
#
# A flag is read in one place and typed in another, and nothing joined the two
# until now. A flag added to a host and not to the table completes to nothing at
# somebody's prompt, which is a gap nobody reports; a flag dropped from a host
# and left in the table completes to something that no longer exists, which is
# worse. So the table (Sources/OllinReference/CommandFlags.swift) is read
# against the files that actually parse a command line, both ways:
#
#   1. Every "--flag" literal in a command-line-reading file is in the table.
#   2. Every flag in the table is spelled in one of those files.
#   3. Scripts/completions/_ollin is exactly what the table generates.
#
# The files are named here rather than swept, because a flag literal elsewhere
# in the tree belongs to another program: the git flags CaptureSource passes,
# the browser flags the page tests pass, the swift build flags the project
# tests pass. Those are not the command's surface and never complete.
# Foreign flags spelled *inside* one of these files (a device tool's own) are
# listed with their reason in Scripts/check-flags-allow.txt.

set -u
cd "${0:A:h:h}"

record=0
[[ "${1:-}" == "--record" ]] && record=1

# The files that read the ollin command line.
typeset -a readers
readers=(
    Sources/Ollin/Core/SketchView.swift
    Sources/Ollin/Core/ParamOverride.swift
    Sources/Ollin/Core/Displays.swift
    Sources/Ollin/Core/Installation.swift
    Sources/Ollin/Core/Checkpoint.swift
    Sources/OllinLive/OllinLiveApp.swift
    Sources/OllinRun/OllinRunMain.swift
    Sources/OllinLiveCoding/LiveCodingApp.swift
    Sources/OllinTether/TetherMain.swift
    Sources/OllinNew/OllinNewCommand.swift
    Sources/OllinDocs/OllinDocsCommand.swift
    Sources/OllinCheck/main.swift
    Sources/OllinDoctor/main.swift
    Sources/OllinExamples/GalleryHarness.swift
    Sources/OllinExamples/OllinExamplesApp.swift
    Sources/OllinProjectGenerator/GeneratorHarness.swift
    Scripts/ollin
)

echo "check-flags: building the table's reader"
swift build --quiet --product OllinDocs || {
    echo "check-flags: OllinDocs would not build" >&2
    exit 1
}
binary=$(swift build --product OllinDocs --show-bin-path)/OllinDocs

listing=$("$binary" completions --list) || {
    echo "check-flags: the table would not print" >&2
    exit 1
}
generated=$("$binary" completions)

OLLIN_FLAG_LISTING="$listing" OLLIN_FLAG_READERS="${readers[*]}" \
OLLIN_FLAG_GENERATED="$generated" OLLIN_FLAG_RECORD="$record" python3 - <<'PY'
import os, pathlib, re, sys

listing = os.environ["OLLIN_FLAG_LISTING"]
readers = os.environ["OLLIN_FLAG_READERS"].split()
# Command substitution strips trailing newlines, so the last one is put back:
# a text file ends with one, and `ollin completions > _ollin` writes it that way.
generated = os.environ["OLLIN_FLAG_GENERATED"].rstrip("\n") + "\n"
record = os.environ["OLLIN_FLAG_RECORD"] == "1"

table = {}
for line in listing.splitlines():
    if not line.strip():
        continue
    name, scope = line.split("\t")
    table.setdefault(name, set()).add(scope)

allow = {}
allow_path = pathlib.Path("Scripts/check-flags-allow.txt")
for line in allow_path.read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    flag, _, reason = line.partition(" ")
    allow[flag] = reason.strip()

problems = []
spelled = {}
literal = re.compile(r'"(--[a-z][a-z0-9-]*)"')
for reader in readers:
    path = pathlib.Path(reader)
    if not path.exists():
        problems.append(f"{reader}: named as a command-line reader, but it is not there")
        continue
    text = path.read_text(errors="ignore")
    for number, line in enumerate(text.splitlines(), 1):
        for flag in literal.findall(line):
            spelled.setdefault(flag, (reader, number))
            if flag not in table and flag not in allow:
                problems.append(f"{reader}:{number}: {flag} is read here and is not in the flag table"
                                " (add it to Sources/OllinReference/CommandFlags.swift,"
                                " or to Scripts/check-flags-allow.txt with its reason)")

for flag in sorted(table):
    if flag not in spelled:
        problems.append(f"the flag table names {flag}, which no command-line reader spells")

for flag in sorted(allow):
    if flag not in spelled:
        problems.append(f"Scripts/check-flags-allow.txt lists {flag}, which no command-line reader spells")
    if flag in table:
        problems.append(f"{flag} is both in the flag table and in the allow list; it can only be one")

completion = pathlib.Path("Scripts/completions/_ollin")
if record:
    completion.write_text(generated)
    print(f"check-flags: wrote {completion} ({len(table)} flags)")
elif not completion.exists():
    problems.append(f"{completion} is missing; write it with: Scripts/check-flags.sh --record")
elif completion.read_text() != generated:
    problems.append(f"{completion} is not what the flag table generates;"
                    " rewrite it with: Scripts/check-flags.sh --record")

if problems:
    for problem in problems:
        print("check-flags: " + problem, file=sys.stderr)
    print(f"check-flags: {len(problems)} problem(s)", file=sys.stderr)
    sys.exit(1)

print(f"check-flags: {len(table)} flags, all read and all completed")
PY
