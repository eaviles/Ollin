#!/bin/zsh
#
# Scripts/preflight.sh: run exactly the gates the current diff calls for.
#
#   Scripts/preflight.sh              # gates for the working-tree diff vs HEAD
#   Scripts/preflight.sh --plan       # say which gates that diff would run and
#                                     # which it would pass over, and run none
#   Scripts/preflight.sh --plan Sources/OllinLive/A.swift Docs/B.md
#                                     # the same question for a change to
#                                     # these paths, whatever the tree holds
#   Scripts/preflight.sh --milestone  # everything, regardless of the diff:
#                                     # every figure re-rendered, the whole
#                                     # test suite, the Examples build, and the
#                                     # same-seed pass over every example
#
# The ship checklist names five gate scripts, and the right subset depends on
# what changed; remembering that subset per commit is a habit, and habits
# lose. This reads the diff (staged, unstaged, and untracked files together),
# runs every gate that applies, says what it skipped and why, and exits
# nonzero if any gate failed. Gates keep running after a failure so one pass
# reports everything.
#
# What runs when. The gates that only read files come first and have all
# reported within about fifteen seconds; the gates that build come after,
# cheapest first, so a failure that takes seconds to find is on screen before
# a gate that takes minutes starts. The run ends on a table of what each gate
# cost.
#
#   reading only
#     always
#       -> the em-dash and invisible-character net over the added diff lines
#       -> the parked-thread net over Tests/
#       -> the attribute net (a doc comment directly under an attribute line)
#          over every Swift file in Sources/, Examples/ and Tests/
#       -> Scripts/check-names.sh (every backticked name in the prose is real,
#          every labeled call matches a public overload, every pointer from
#          the contributor files lands; a rename in Sources/ stales prose the
#          diff never touched, so this one is not scoped to the diff; ~3 s)
#       -> Scripts/check-api-names.sh (the public surface under API/ against
#          the settled naming rules; a listing is recorded on purpose, so
#          this reads the whole surface rather than the diff; under a second)
#       -> Scripts/check-api-pages.sh (the same two sides the other way: every
#          public name under API/ is named by some Docs page, or listed with
#          its reason; a page deleted stales this whether or not the diff
#          touched it, so it is not scoped either; ~1 s)
#     any .md prose, any image, or anything under Examples/ changed
#       -> Scripts/check-links.sh and Scripts/guide-coverage.sh
#     Guide/ or Docs/ prose changed
#       -> Scripts/prose-lint.sh over just those files
#     Guide/ prose changed
#       -> Scripts/prose-density.sh over just those pages, which fails when
#          one framing device passes its per-page cap
#     the expander's sources changed (Sources/OllinExpander, the wasm entry,
#     the vendored tessellator)
#       -> Scripts/build-web-expander.sh --check (the committed WebAssembly
#          resource must have been built from these sources)
#     Sources/, External/, Package.*, or API/ changed
#       -> Scripts/api-diff.sh --summary (the listings against the last tag,
#          read as a version: the bump the release needs and the shim rule,
#          a rehearsal count before 1.0 and a gate from 1.0 on; its self-test
#          runs first; about a second)
#   building. A gate marked "reaches" runs on a change under Sources/,
#   External/, or to Package.* only when that change can move what the gate
#   reads: the changed file's target is the one the gate builds or one it
#   depends on, by the package's own manifest (Scripts/preflight-reach.py). A
#   change to a host app reaches none of them, a change to one satellite
#   reaches all but the phone build, a change to the core reaches all, and any
#   doubt (the manifest itself, a file in no target's folder) reaches all.
#     always
#       -> Scripts/check-flags.sh (the command's flags against the table the
#          shell completes from, and the checked-in completion file)
#       -> Scripts/llms.sh --check (the checkout's llms.txt against what the
#          reference writes; every line comes from a page title or an index
#          line, so any prose change can stale it)
#     a change that reaches a library product
#       -> Scripts/api-surface.sh (the public surface of every library
#          product, written down under API/; a change there has to be
#          recorded on purpose, and from 1.0 on a removal needs its shim;
#          one build of the modules and about 13 s of reading them)
#     a Guide or Docs prose change, or a change that reaches the snippet
#     checker or a module a block can import
#       -> Scripts/check-snippets.sh (the code in the prose, compiled: only
#          the blocks whose text, compiler, or module files changed since
#          they last ran, so seconds after a prose edit and three and a half
#          minutes when the core's interface moved)
#     a change that reaches a library product
#       -> Scripts/api-docs.sh (the generated API reference, the one gate
#          that reads doc comments: a link at a symbol that has gone, or a
#          parameter documented under a name the signature dropped; it
#          builds in a folder of its own, about 20 s when nothing it reads
#          changed and two minutes after a change to the core)
#     a change that reaches the Ollin product
#       -> xcodebuild for generic iOS (nothing else compiles the framework
#          for the phone, and a macOS-only call in a core file broke it
#          silently within a day of the last hand check; under 10 s warm,
#          about a minute after a change to the core)
#     Sources/, External/, Package.*, Tests/, or the script changed
#       -> Scripts/check-ci-swift.sh (every target under the CI runner's
#          Swift, which refuses expressions the desk's newer compiler
#          accepts; the tests too when Tests/ changed; about three minutes
#          cold, six to eight with the tests; also on a change to Tests/ or
#          the script; when that toolchain is not installed the gate cannot
#          check, and the table and the last line say NOT RUN)
#     a host app or the runtime they share changed (OllinLive,
#     OllinLiveCoding, OllinRuntime, OllinRun, the generator, the gallery)
#       -> Scripts/host-gates.sh (the hosts' own headless gates; --all,
#          with the gallery's cycle, on a gallery change)
#     the ring sketch, the web exporter, the shader rewriter, or the shaders
#     changed
#       -> Scripts/site-hero.sh (the site's front-page ring is the sketch's
#          recorded web page, committed as source; any of those moves it)
#     a change that reaches the figure runner or a module a figure can
#     import, or a figure sketch or image changed
#       -> Scripts/guide-figures.sh, last: the probe decides how much
#          renders (about two minutes for the sample), and when it hands the
#          run to the full render that is the one gate here that takes half
#          an hour, so everything else has reported by then
#   --milestone adds
#       -> Scripts/test.sh milestone (both phases plus the five nested
#          signed-bundle builds the everyday run leaves out), Scripts/test.sh
#          tsan (the handoffs under Thread Sanitizer: a second, instrumented
#          build of the non-GPU targets, which is why it is not a gate on
#          every commit), guide-figures --force, check-snippets --no-cache
#          (every block compiled, whatever the last run remembers),
#          site-hero, swift build --package-path Examples (the examples
#          anti-rot guard; CI runs on pull requests only, so nothing else
#          compiles them), and Scripts/check-determinism.sh (every example
#          that runs alone, drawn twice in two processes under one seed and
#          compared pixel for pixel; its self-test first; about an hour)
#
# What a run costs on the M2 (8 GB), measured 2026-11-10 on a diff touching
# the core, a test, a Docs page and a Guide page: ten and a half minutes when
# the core's interface changed (every module downstream recompiles in three
# build folders and every snippet compiles again), and a minute and a half
# when the same run is repeated after a fix that touched no source. Both
# figures leave out the runner's compiler, whose toolchain was not installed
# that day: its own build adds to them (about three minutes cold by its
# script's notes, six to eight with the tests, not measured here).
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
plan=0
case "$1" in
--milestone) milestone=1 ;;
--plan) plan=1 ;;
--help | -h)
    sed -n '3,146p' "$0" | sed -E 's|^# ?||'
    exit 0
    ;;
esac

changed=$({ git diff --name-only --diff-filter=d HEAD; git ls-files --others --exclude-standard; } | sort -u)
# A plan can be asked about paths instead of the tree's own diff: what would a
# change to these cost?
if (( plan )) && [[ $# -gt 1 ]]; then
    changed=$(print -l -- "${@:2}" | sort -u)
fi

if [[ -z "$changed" && $milestone -eq 0 ]]; then
    echo "preflight: nothing changed against HEAD, nothing to gate"
    exit 0
fi

zmodload zsh/datetime
preflight_began=$EPOCHREALTIME

# Every gate is timed, and the run ends on a table of what each one cost, so
# "preflight is slow" is a question with a row to point at.
#
# A gate that exits 77 is saying it could not check here (the runner's
# compiler, when its toolchain is not installed). That is not a failure, and
# it is not a pass: the table and the last line name it as not run.
typeset -a failures timings unchecked
run() {
    local label="$1"
    shift
    if (( plan )); then
        echo "preflight: would run $label"
        return
    fi
    echo "preflight: running $label"
    local began=$EPOCHREALTIME outcome=ok code=0
    "$@" || code=$?
    if (( code == 77 )); then
        unchecked+=("$label")
        outcome="NOT RUN"
    elif (( code != 0 )); then
        failures+=("$label")
        outcome=FAILED
    fi
    timings+=("$(printf '%8.1f s  %-7s  %s' $((EPOCHREALTIME - began)) "$outcome" "$label")")
}
skip() { echo "preflight: skipping $1 ($2)"; }

framework=$(grep -E '^(Sources/|External/|Package\.(swift|resolved)$)' <<<"$changed")
figures=$(grep -E '^(Guide|Docs)/Figures/' <<<"$changed")
images=$(grep -E '^(Guide|Docs)/Images/' <<<"$changed")
prose=$(grep -E '\.md$' <<<"$changed")
examples=$(grep -E '^Examples/' <<<"$changed")
reader_prose=$(grep -E '^(Guide|Docs)/.*\.md$' <<<"$changed" | grep -vE '^Guide/(PLAN|AUTHORING)\.md$')
guide_prose=$(grep -E '^Guide/.*\.md$' <<<"$changed" | grep -vE '^Guide/(PLAN|AUTHORING)\.md$')
hosts=$(grep -E '^(Sources/(OllinLive|OllinLiveCoding|OllinRuntime|OllinRun|OllinProjectGenerator|OllinExamples)/|Scripts/host-gates\.sh$)' <<<"$changed")
gallery=$(grep -E '^Sources/OllinExamples/' <<<"$changed")
hero=$(grep -E '^(Examples/Web/BreathingRing/|Sources/Ollin/Export/Web|Sources/OllinShaderText/|Sources/Ollin/Renderer/Shader|Scripts/site-hero\.sh$)' <<<"$changed")
expander=$(grep -E '^(Sources/OllinExpander/|Scripts/web-expander/|External/CLibtess2/|Scripts/build-web-expander\.sh$)' <<<"$changed")

# Which build gates a framework change can reach. A gate reads what some
# target builds, so a change to a target it neither is nor depends on cannot
# move it: a host app's sources cannot move a figure, the phone build, the
# public listings, or what a snippet compiles against. The package's own
# manifest says who depends on whom (Scripts/preflight-reach.py, whose
# self-test runs first so a change to it cannot pass on a wrong reading), and
# every doubt reaches everything: a manifest that will not print, a path in no
# target's folder, a milestone.
reach_libraries=1 reach_snippets=1 reach_ios=1 reach_figures=1
if [[ -n "$framework" && $milestone -eq 0 ]]; then
    run "preflight-reach (selftest)" Scripts/preflight-reach.py --selftest
    if reached=$(swift package dump-package 2>/dev/null | Scripts/preflight-reach.py ${(f)framework}); then
        for line in ${(f)reached}; do
            case "$line" in
            libraries=0) reach_libraries=0 ;;
            snippets=0) reach_snippets=0 ;;
            ios=0) reach_ios=0 ;;
            figures=0) reach_figures=0 ;;
            esac
        done
    else
        echo "preflight: could not read which targets the diff reaches, so every build gate runs"
    fi
fi
# Why a build gate is passed over: no framework change at all, or one that
# cannot reach what the gate reads.
unreached() {
    if [[ -n "$framework" ]]; then echo "the change reaches nothing $1"; else echo "no framework change"; fi
}

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

# An attribute stays on its declaration. A declaration inserted between an
# attribute and the one it was written for takes the attribute with it, and a
# doc comment directly under an attribute line is that shape: on 2026-09-22 a
# new helper went in under `@MainActor @discardableResult` and above
# `handleCommandLine`, which lost the attribute (a warning at every call that
# ignored its result) and its whole doc comment, and the API listing recorded
# the loss without anyone reading that line. About a second over every Swift
# file in the tree, so it runs every time.
stranded=$(awk 'FNR == 1 { prev = "" }
    prev ~ /^[ \t]*@[A-Za-z]+(\([^)]*\))?[ \t]*$/ && $0 ~ /^[ \t]*\/\/\// { print FILENAME ":" FNR - 1 ": " prev }
    { prev = $0 }' ${(f)"$(git ls-files 'Sources/*.swift' 'Examples/*.swift' 'Tests/*.swift')"})
if [[ -n "$stranded" ]]; then
    echo "preflight: a doc comment sits under an attribute, so the attribute belongs to the next declaration:" >&2
    echo "$stranded" >&2
    failures+=("an attribute off its declaration")
fi

# The gates from here to the next banner read files and build nothing, so all
# of them have reported within about fifteen seconds: a stale name, a broken
# link, or a prose rule is on screen before the first build starts.

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

# Navigation and coverage read the whole tree in seconds, so any prose or
# image change buys both. A new example is a navigation change too: its folder
# appears and the group README does not follow it by itself.
if [[ -n "$prose" || -n "$images" || -n "$examples" || $milestone -eq 1 ]]; then
    run "check-links" Scripts/check-links.sh
    run "guide-coverage" Scripts/guide-coverage.sh
else
    skip "check-links and guide-coverage" "no prose, image, or example change"
fi

# Vale, scoped to the reader-facing files actually touched.
if [[ -n "$reader_prose" ]]; then
    run "prose-lint" Scripts/prose-lint.sh ${(f)reader_prose}
elif [[ $milestone -eq 1 ]]; then
    run "prose-lint" Scripts/prose-lint.sh
else
    skip "prose-lint" "no Guide/ or Docs/ prose change"
fi

# One framing device repeated past its cap on a Guide page fails; the rest of
# prose-density's table is a report and prints with it.
if [[ -n "$guide_prose" ]]; then
    run "prose-density (framing cap)" Scripts/prose-density.sh ${(f)guide_prose}
elif [[ $milestone -eq 1 ]]; then
    run "prose-density (framing cap)" Scripts/prose-density.sh Guide/[0-9]*.md Guide/[A-E]-*.md
else
    skip "prose-density" "no Guide/ prose change"
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

# From here on every gate builds something, in the main build folder unless it
# says otherwise. None of them may change how that folder is built: a gate
# that builds it under other flags recompiles everything and makes the next
# gate recompile everything back (the API reference's symbol graphs, built
# there, cost 207 s of every run, measured 2026-11-10), so such a gate takes
# a folder of its own.

# The command's flags against the table the shell completes from, both ways,
# and the checked-in completion file against what the table generates. Not
# scoped to the diff either: a flag dropped from a host stales the table
# whether or not the table was touched.
run "check-flags" Scripts/check-flags.sh

# The checkout's llms.txt, the map an assistant reads, against what the
# reference writes for it. Every line comes from a page's title, the line the
# reference index says about it, or the group it is filed under, so an edit to
# any page or index can stale it; that is why this is not scoped to the diff.
run "llms" Scripts/llms.sh --check

# The public surface: every library product's API is written down under API/
# and diffed against the build, so a public change is a deliberate one
# (Scripts/api-surface.sh --record) and shows up in review beside the change
# that made it. From 1.0 on this is where a rename without its shim fails.
if [[ ( -n "$framework" && $reach_libraries -eq 1 ) || $milestone -eq 1 ]]; then
    run "api-surface" Scripts/api-surface.sh
else
    skip "api-surface" "$(unreached "a library product builds")"
fi

# The code inside the prose, the Guide's and the reference pages'. A prose
# change can break a snippet outright, and a framework change can rename what
# every snippet calls, so both buy this one, over every page: a rename in
# Sources/ shows up in a page the diff never touched. The checker keeps each
# block's answer under a digest of what its compile read, so it compiles only
# the blocks whose text, compiler, or module files changed: seconds after a
# prose edit or a change inside a function body, three and a half minutes
# when the core's interface moved. A milestone compiles every block.
if [[ $milestone -eq 1 ]]; then
    run "check-snippets --no-cache" Scripts/check-snippets.sh --no-cache
elif [[ -n "$reader_prose" || ( -n "$framework" && $reach_snippets -eq 1 ) ]]; then
    run "check-snippets" Scripts/check-snippets.sh
else
    skip "check-snippets" "no Guide or Docs prose change, and $(unreached "a snippet compiles against")"
fi

# The generated API reference: DocC over every module `.spi.yml` publishes.
# Nothing else here reads a doc comment, and the two things this catches are a
# link at a symbol that no longer exists and a parameter documented under a
# name the signature dropped. Its symbol graphs build in a folder of their
# own (see the script): about 20 s when nothing it reads changed, two minutes
# after a change to the core.
if [[ ( -n "$framework" && $reach_libraries -eq 1 ) || $milestone -eq 1 ]]; then
    run "api-docs" Scripts/api-docs.sh
else
    skip "api-docs" "$(unreached "a library product builds")"
fi

# The iOS build: nothing else compiles the framework for the phone, so a
# macOS-only SwiftUI call in a core file breaks it without a word (2026-09-02:
# a seed-box `onExitCommand`). Under 10 s when nothing changed, about a minute
# after a change to the core.
if [[ ( -n "$framework" && $reach_ios -eq 1 ) || $milestone -eq 1 ]]; then
    run "iOS build" xcodebuild -scheme Ollin -destination 'generic/platform=iOS' -quiet build
else
    skip "iOS build" "$(unreached "the phone build compiles")"
fi

# The runner's compiler: CI builds with an older Swift than the desk, and the
# two disagree about which expressions are too hard to type-check, so a
# change that builds here can fail there (four times between 2026-09-01 and
# 2026-10-21, none visible to the newer compiler's warnings). Its own build folder, so it
# never takes the main build's lock. Cold, about three minutes. Test code
# fails the same way, so a change under Tests/ builds the tests as well
# (six to eight minutes cold).
ci_swift=$(grep -E '^Scripts/check-ci-swift\.sh$' <<<"$changed")
tests=$(grep -E '^Tests/' <<<"$changed")
if [[ -n "$tests" || $milestone -eq 1 ]]; then
    run "ci-swift --tests (the runner's compiler)" Scripts/check-ci-swift.sh --tests
elif [[ -n "$framework" || -n "$ci_swift" ]]; then
    run "ci-swift (the runner's compiler)" Scripts/check-ci-swift.sh
else
    skip "ci-swift" "no framework, test, or script change"
fi

# The hosts' own headless gates: the live hosts, the runner, the generator,
# and the gallery test themselves through flags of their binaries, which no
# `swift test` run reaches. About 75 s; the gallery's cycle adds two minutes,
# so it runs on a gallery change and at a milestone.
if [[ -n "$gallery" || $milestone -eq 1 ]]; then
    run "host-gates --all" Scripts/host-gates.sh --all
elif [[ -n "$hosts" ]]; then
    run "host-gates" Scripts/host-gates.sh
else
    skip "host-gates" "no change to a host app or the runtime they share"
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
# the runner says how long before it starts. A milestone forces every figure:
# --no-probe only skips the sample after a framework change, and once a
# passing probe has trusted the new framework it renders nothing at all.
if [[ $milestone -eq 1 ]]; then
    run "guide-figures --force" Scripts/guide-figures.sh --force
elif [[ ( -n "$framework" && $reach_figures -eq 1 ) || -n "$figures" || -n "$images" ]]; then
    run "guide-figures" Scripts/guide-figures.sh
else
    skip "guide-figures" "no figure or image change, and $(unreached "a figure draws with")"
fi

if [[ $milestone -eq 1 ]]; then
    run "test.sh (full suite + bundle builds)" Scripts/test.sh milestone
    run "test.sh tsan (the handoffs under Thread Sanitizer)" Scripts/test.sh tsan
    run "examples build" swift build --package-path Examples
    run "check-determinism --selftest" Scripts/check-determinism.sh --selftest
    run "check-determinism (every example twice under one seed)" Scripts/check-determinism.sh
fi

if (( plan )); then
    exit 0
fi
echo ""
echo "preflight: what each gate cost"
print -l -- $timings
printf '%8.1f s           total\n' $((EPOCHREALTIME - preflight_began))
echo ""
if (( ${#unchecked} > 0 )); then
    echo "preflight: NOT CHECKED HERE: ${(j:, :)unchecked} (each says why on its own line above)"
fi
if (( ${#failures} > 0 )); then
    echo "preflight: FAILED: ${(j:, :)failures}" >&2
    exit 1
fi
if (( ${#unchecked} > 0 )); then
    echo "preflight: every gate that could run here passed, and ${#unchecked} could not run"
else
    echo "preflight: every applicable gate passed"
fi
