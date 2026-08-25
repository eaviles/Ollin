#!/bin/zsh
#
# Scripts/preflight.sh: run exactly the gates the current diff calls for.
#
#   Scripts/preflight.sh              # gates for the working-tree diff vs HEAD
#   Scripts/preflight.sh --milestone  # everything, regardless of the diff:
#                                     # full --no-probe figure render, the whole
#                                     # test suite, and the Examples build
#
# The ship checklist names five gate scripts, and the right subset depends on
# what changed; remembering that subset per commit is a habit, and habits
# lose. This reads the diff (staged, unstaged, and untracked files together),
# runs every gate that applies, says what it skipped and why, and exits
# nonzero if any gate failed. Gates keep running after a failure so one pass
# reports everything.
#
# What runs when:
#   Sources/, External/, Package.*, or figure sketches changed
#       -> Scripts/guide-figures.sh (the probe decides how much renders)
#   any .md prose or any image changed
#       -> Scripts/check-links.sh and Scripts/guide-coverage.sh
#   Guide/ or Docs/ prose changed
#       -> Scripts/prose-lint.sh over just those files
#   always
#       -> the em-dash and invisible-character net over the added diff lines
#   --milestone adds
#       -> Scripts/test.sh (both phases), guide-figures --no-probe, and
#          swift build --package-path Examples (the examples anti-rot guard;
#          CI runs on pull requests only, so nothing else compiles them)
#
# This does not commit and does not replace the docs audit's judgment passes
# (stale prose, snippet APIs, comment leaks); it is the mechanical half.

cd "$(dirname "$0")/.." || exit 1

emulate -L zsh

milestone=0
case "$1" in
--milestone) milestone=1 ;;
--help | -h)
    sed -n '3,31p' "$0" | sed 's|^# \?||'
    exit 0
    ;;
esac

changed=$({ git diff --name-only --diff-filter=d HEAD; git ls-files --others --exclude-standard; } | sort -u)

if [[ -z "$changed" && $milestone -eq 0 ]]; then
    echo "preflight: nothing changed against HEAD, nothing to gate"
    exit 0
fi

typeset -a failures
run() {
    local label="$1"
    shift
    echo "preflight: running $label"
    "$@" || failures+=("$label")
}
skip() { echo "preflight: skipping $1 ($2)"; }

framework=$(grep -E '^(Sources/|External/|Package\.(swift|resolved)$)' <<<"$changed")
figures=$(grep -E '^(Guide|Docs)/Figures/' <<<"$changed")
images=$(grep -E '^(Guide|Docs)/Images/' <<<"$changed")
prose=$(grep -E '\.md$' <<<"$changed")
reader_prose=$(grep -E '^(Guide|Docs)/.*\.md$' <<<"$changed" | grep -vE '^Guide/(PLAN|AUTHORING)\.md$')

# The figure gate: a framework change may move any figure (the probe decides),
# and an edited figure sketch or a hand-touched image must re-render or fail.
if [[ $milestone -eq 1 ]]; then
    run "guide-figures --no-probe" Scripts/guide-figures.sh --no-probe
elif [[ -n "$framework" || -n "$figures" || -n "$images" ]]; then
    run "guide-figures" Scripts/guide-figures.sh
else
    skip "guide-figures" "no framework, figure, or image change"
fi

# Navigation and coverage read the whole tree in seconds, so any prose or
# image change buys both.
if [[ -n "$prose" || -n "$images" || $milestone -eq 1 ]]; then
    run "check-links" Scripts/check-links.sh
    run "guide-coverage" Scripts/guide-coverage.sh
else
    skip "check-links and guide-coverage" "no prose or image change"
fi

# Vale, scoped to the reader-facing files actually touched.
if [[ -n "$reader_prose" ]]; then
    run "prose-lint" Scripts/prose-lint.sh ${(f)reader_prose}
elif [[ $milestone -eq 1 ]]; then
    run "prose-lint" Scripts/prose-lint.sh
else
    skip "prose-lint" "no Guide/ or Docs/ prose change"
fi

# The em-dash and invisible-character net over added lines, for text written
# through heredocs or scripts that the editing hooks never saw. CLAUDE.md and
# CAPABILITIES.md are agent-facing and exempt; External/ is other people's
# code. The pattern is built from UTF-8 octal escapes (em dash, zero-width
# space, zero-width non-joiner, zero-width joiner, BOM) so this file stays
# clean under its own rule.
banned="$(printf '\342\200\224|\342\200\213|\342\200\214|\342\200\215|\357\273\277')"
net=$(git diff HEAD -- . ':(exclude)CLAUDE.md' ':(exclude)CAPABILITIES.md' ':(exclude)External' \
    | grep -nE "^\+.*($banned)")
if [[ -n "$net" ]]; then
    echo "preflight: em dash or invisible character in added lines:" >&2
    echo "$net" >&2
    failures+=("em-dash net")
fi

if [[ $milestone -eq 1 ]]; then
    run "test.sh (full suite)" Scripts/test.sh
    run "examples build" swift build --package-path Examples
fi

echo ""
if (( ${#failures} > 0 )); then
    echo "preflight: FAILED: ${(j:, :)failures}" >&2
    exit 1
fi
echo "preflight: every applicable gate passed"
