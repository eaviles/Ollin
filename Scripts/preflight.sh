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
# What runs when, cheapest first, so a failure that takes seconds to find
# is reported before the gate that takes minutes starts:
#   always
#       -> the em-dash and invisible-character net over the added diff lines
#       -> the parked-thread net over Tests/
#       -> Scripts/check-flags.sh (the command's flags against the table the
#          shell completes from, and the checked-in completion file)
#       -> Scripts/check-api-names.sh (the public surface under API/ against
#          the settled naming rules; a listing is recorded on purpose, so
#          this reads the whole surface rather than the diff; under a second)
#       -> Scripts/check-names.sh (every backticked name in the prose is real,
#          every labeled call matches a public overload, every pointer from
#          the contributor files lands; a rename in Sources/ stales prose the
#          diff never touched, so this one is not scoped to the diff; ~2 s)
#       -> Scripts/check-api-pages.sh (the same two sides the other way: every
#          public name under API/ is named by some Docs page, or listed with
#          its reason; a page deleted stales this whether or not the diff
#          touched it, so it is not scoped either; ~2 s)
#   any .md prose, any image, or anything under Examples/ changed
#       -> Scripts/check-links.sh and Scripts/guide-coverage.sh
#     a Guide or Docs prose change, or a framework change
#       -> Scripts/check-snippets.sh (the code in the prose, compiled)
#   Guide/ or Docs/ prose changed
#       -> Scripts/prose-lint.sh over just those files
#   the expander's sources changed (Sources/OllinExpander, the wasm entry,
#   the vendored tessellator)
#       -> Scripts/build-web-expander.sh --check (the committed WebAssembly
#          resource must have been built from these sources)
#   Sources/, External/, or Package.* changed
#       -> Scripts/api-surface.sh (the public surface of every library
#          product, written down under API/; a change there has to be
#          recorded on purpose, and from 1.0 on a removal needs its shim;
#          about a minute warm, most of it the per-target build)
#       -> Scripts/api-diff.sh --summary (the listings against the last tag,
#          read as a version: the bump the release needs and the shim rule,
#          a rehearsal count before 1.0 and a gate from 1.0 on; also on any
#          change under API/; its self-test runs first; under a second)
#       -> xcodebuild for generic iOS (nothing else compiles the framework
#          for the phone, and a macOS-only call in a core file broke it
#          silently within a day of the last hand check; about 30 s warm)
#       -> Scripts/api-docs.sh (the generated API reference, the one gate
#          that reads doc comments: a link at a symbol that has gone, or a
#          parameter documented under a name the signature dropped; about a
#          minute and a half warm)
#   the ring sketch, the web exporter, the shader rewriter, or the shaders
#   changed
#       -> Scripts/site-hero.sh (the site's front-page ring is the sketch's
#          recorded web page, committed as source; any of those moves it)
#   Sources/, External/, Package.*, or figure sketches changed
#       -> Scripts/guide-figures.sh, last: the probe decides how much
#          renders, and when it hands the run to the full render that is the
#          one gate here that takes half an hour, so everything else has
#          reported by then
#   --milestone adds
#       -> Scripts/test.sh milestone (both phases plus the four nested
#          signed-bundle builds the everyday run leaves out), guide-figures
#          --no-probe, site-hero, and swift build --package-path Examples (the
#          examples anti-rot guard; CI runs on pull requests only, so nothing
#          else compiles them)
#
# The figure gate's worker count follows the machine's memory (see
# defaultJobs in the runner; OLLIN_FIGURE_JOBS overrides it). Four workers on
# 8 GB put the machine into swap and got the whole preflight killed twice in
# one day (2026-09-08), so leave that to the runner rather than raising it.
#
# This does not commit and does not replace the docs audit's judgment passes
# (stale prose, snippet APIs, comment leaks); it is the mechanical half.

cd "$(dirname "$0")/.." || exit 1

emulate -L zsh

milestone=0
case "$1" in
--milestone) milestone=1 ;;
--help | -h)
    sed -n '3,55p' "$0" | sed 's|^# \?||'
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
examples=$(grep -E '^Examples/' <<<"$changed")
reader_prose=$(grep -E '^(Guide|Docs)/.*\.md$' <<<"$changed" | grep -vE '^Guide/(PLAN|AUTHORING)\.md$')
guide_prose=$(grep -E '^Guide/.*\.md$' <<<"$changed" | grep -vE '^Guide/(PLAN|AUTHORING)\.md$')
hero=$(grep -E '^(Examples/Web/BreathingRing/|Sources/Ollin/Export/Web|Sources/OllinShaderText/|Sources/Ollin/Renderer/Shader|Scripts/site-hero\.sh$)' <<<"$changed")
expander=$(grep -E '^(Sources/OllinExpander/|Scripts/web-expander/|External/CLibtess2/|Scripts/build-web-expander\.sh$)' <<<"$changed")

# The em-dash and invisible-character net over added lines, for text written
# through heredocs or scripts that the editing hooks never saw. CLAUDE.md and
# CAPABILITIES.md are agent-facing and exempt; External/ is other people's
# code; SiteHero.swift is nobody's prose, being the ring's recorded page, which
# carries the framework's own shader comments through the translation verbatim.
# The pattern is built from UTF-8 octal escapes (em dash, zero-width
# space, zero-width non-joiner, zero-width joiner, BOM) so this file stays
# clean under its own rule.
banned="$(printf '\342\200\224|\342\200\213|\342\200\214|\342\200\215|\357\273\277')"
net=$(git diff HEAD -- . ':(exclude)CLAUDE.md' ':(exclude)CAPABILITIES.md' ':(exclude)External' \
    ':(exclude)Sources/OllinReference/SiteHero.swift' \
    | grep -nE "^\+.*($banned)")
if [[ -n "$net" ]]; then
    echo "preflight: em dash or invisible character in added lines:" >&2
    echo "$net" >&2
    failures+=("em-dash net")
fi

# No blocking wait in a test. Test bodies run on the concurrency pool, which is
# one thread per core; parking one costs the whole process a worker, and a suite
# running enough of them at once takes every worker there is. Measured
# 2026-08-26: one helper froze a 2902-test run at 2% CPU for minutes at a time,
# and the tests that failed were whichever ones held a stopwatch. Costs
# milliseconds, so it runs every time rather than on a diff match.
#
# One file is exempt, on the rule's own reasoning. The hazard is parking a
# cooperative worker; HeadlessFlagSupport.swift blocks the *main* thread while a
# detached real thread runs, which parks no worker at all. Blocking there is
# also the point rather than a cost: while the main thread waits, no other
# main-actor test can run, so the process-global that helper guards is invisible
# to every reader that could be fooled by it. Suspending instead of blocking is
# exactly what let PushFeedTests hand its export to SessionRecorderTests and
# fail it on CI (2026-09-01).
# `downloadBlocking` is the same park one call down: it waits on a semaphore for
# a worker's task, which is right on the main thread (the export path) and wrong
# in a test body (the other parked thread in every CI wedge sample, 2026-09-06).
# A test wants the cache's `download(_:)`, which suspends instead.
parked=$(grep -rn 'DispatchSemaphore\|\.wait(\|downloadBlocking(' Tests/ 2>/dev/null \
    | grep -v '^Tests/OllinTests/HeadlessFlagSupport.swift:')
if [[ -n "$parked" ]]; then
    echo "preflight: a test parks a thread; hop with 'await MainActor.run' instead:" >&2
    echo "$parked" >&2
    failures+=("parked thread in Tests/")
fi

# Every name the prose puts in backticks, against the tree and the public
# surface. Not scoped to the diff on purpose: a rename in Sources/ stales a
# Docs page the diff never touched, and that is the case it exists for.
run "check-names" Scripts/check-names.sh

# The public surface against the settled naming rules. The listings under
# API/ are what a change to the surface records, so this reads them whole:
# a name that broke a rule a week ago is as wrong as one in this diff.
run "check-api-names" Scripts/check-api-names.sh

# And the same listings against the reference: every public name written down
# under API/ has to be named by some page under Docs/, or be listed with its
# reason. check-names reads a backtick back to the tree; this reads the tree
# back to the backticks, which is the direction nothing else covers.
run "check-api-pages" Scripts/check-api-pages.sh

# The command's flags against the table the shell completes from, both ways,
# and the checked-in completion file against what the table generates. Not
# scoped to the diff either: a flag dropped from a host stales the table
# whether or not the table was touched.
run "check-flags" Scripts/check-flags.sh

# Navigation and coverage read the whole tree in seconds, so any prose or
# image change buys both. A new example is a navigation change too: its folder
# appears and the group README does not follow it by itself.
if [[ -n "$prose" || -n "$images" || -n "$examples" || $milestone -eq 1 ]]; then
    run "check-links" Scripts/check-links.sh
    run "guide-coverage" Scripts/guide-coverage.sh
else
    skip "check-links and guide-coverage" "no prose, image, or example change"
fi

# The code inside the prose, the Guide's and the reference pages'. A prose
# change can break a snippet outright, and a framework change can rename what
# every snippet calls, so both buy this one. About two minutes for both trees
# on the M2, so it runs whole rather than scoped: a rename in Sources/ shows
# up in a page the diff never touched.
if [[ -n "$reader_prose" || -n "$framework" || $milestone -eq 1 ]]; then
    run "check-snippets" Scripts/check-snippets.sh
else
    skip "check-snippets" "no Guide or Docs prose change, and no framework change"
fi

# Vale, scoped to the reader-facing files actually touched.
if [[ -n "$reader_prose" ]]; then
    run "prose-lint" Scripts/prose-lint.sh ${(f)reader_prose}
elif [[ $milestone -eq 1 ]]; then
    run "prose-lint" Scripts/prose-lint.sh
else
    skip "prose-lint" "no Guide/ or Docs/ prose change"
fi

# The page's expander: the shared expander module compiled to WebAssembly and
# committed as a resource with a hash of the sources it was built from. An
# edit to those sources without a rebuild would ship a page that expands its
# strokes differently from the Mac, so the check fails until
# Scripts/build-web-expander.sh has run (it needs the swift.org toolchain).
if [[ -n "$expander" || $milestone -eq 1 ]]; then
    run "web-expander --check" Scripts/build-web-expander.sh --check
else
    skip "web-expander" "no change to the expander's sources"
fi

# The public surface: every library product's API is written down under API/
# and diffed against the build, so a public change is a deliberate one
# (Scripts/api-surface.sh --record) and shows up in review beside the change
# that made it. From 1.0 on this is where a rename without its shim fails.
if [[ -n "$framework" || $milestone -eq 1 ]]; then
    run "api-surface" Scripts/api-surface.sh
else
    skip "api-surface" "no framework change"
fi

# The same listings read as a version: against the last tag, what was added,
# removed, renamed, changed, or deprecated, and the bump that costs. Before
# 1.0 the shim rule is a count in the output; from 1.0 on a public spelling
# that went away with no deprecated twin fails here, and a shim outside its
# module's Deprecations.swift fails in either era. The reader's own self-test
# runs first, so a change to it cannot pass on a wrong reading.
api=$(grep -E '^API/' <<<"$changed")
if [[ -n "$framework" || -n "$api" || $milestone -eq 1 ]]; then
    run "api-diff (selftest)" Scripts/api-diff.sh --selftest
    run "api-diff" Scripts/api-diff.sh --summary
else
    skip "api-diff" "no framework or API/ change"
fi

# The generated API reference: DocC over every module `.spi.yml` publishes.
# Nothing else here reads a doc comment, and the two things this catches are a
# link at a symbol that no longer exists and a parameter documented under a
# name the signature dropped. Warm, about a minute and a half.
if [[ -n "$framework" || $milestone -eq 1 ]]; then
    run "api-docs" Scripts/api-docs.sh
else
    skip "api-docs" "no framework change"
fi

# The iOS build: nothing else compiles the framework for the phone, so a
# macOS-only SwiftUI call in a core file breaks it without a word (2026-09-02:
# a seed-box `onExitCommand`). Warm, this is about 30 s.
if [[ -n "$framework" || $milestone -eq 1 ]]; then
    run "iOS build" xcodebuild -scheme Ollin -destination 'generic/platform=iOS' -quiet build
else
    skip "iOS build" "no framework change"
fi

# The front page's ring: the sketch's own web page, recorded into
# Sources/OllinReference/SiteHero.swift. The recording is deterministic, so
# rerunning it rewrites the file only when something it carries moved, and
# the rewrite then shows in the diff to be committed with the change.
if [[ -n "$hero" || $milestone -eq 1 ]]; then
    run "site-hero" Scripts/site-hero.sh
else
    skip "site-hero" "no change to the ring sketch, the web exporter, or the shaders it carries"
fi

# The figure gate, last: a framework change may move any figure (the probe
# decides), and an edited figure sketch or a hand-touched image must
# re-render or fail. When the probe finds a mover this is the long gate, and
# the runner says how long before it starts.
if [[ $milestone -eq 1 ]]; then
    run "guide-figures --no-probe" Scripts/guide-figures.sh --no-probe
elif [[ -n "$framework" || -n "$figures" || -n "$images" ]]; then
    run "guide-figures" Scripts/guide-figures.sh
else
    skip "guide-figures" "no framework, figure, or image change"
fi

if [[ $milestone -eq 1 ]]; then
    run "test.sh (full suite + bundle builds)" Scripts/test.sh milestone
    run "examples build" swift build --package-path Examples
fi

echo ""
if (( ${#failures} > 0 )); then
    echo "preflight: FAILED: ${(j:, :)failures}" >&2
    exit 1
fi
echo "preflight: every applicable gate passed"
