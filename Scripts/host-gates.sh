#!/bin/zsh
#
# Scripts/host-gates.sh: run the host apps' own headless gates.
#
#   Scripts/host-gates.sh          # every gate but the gallery's cycle
#   Scripts/host-gates.sh --all    # the gallery's cycle too (about two
#                                  # minutes more: it runs 42 examples)
#
# Each host carries its tests as flags of its own binary, since what they
# check (a compile and swap, a file watcher, a drag that writes source, a
# session carried across an evaluation) lives in an executable target that
# `swift test` cannot import. OllinLive: --selftest, --watchtest,
# --dragtest, --paramtest, --savetest, --inspectortest. OllinLiveCoding: --selftest,
# --sessiontest, --dragtest, --controltest. OllinRun: --selftest. The
# generator: --stagetest. The gallery: --cycletest. They passed whenever
# someone typed them, and no script did: under the test suite alone, the
# coverage read of 2026-10-10 counted every host at 0% of its lines and
# OllinRuntime at 64%, and these gates take the live hosts to 46%, the
# generator to 55%, the gallery to 80%, and the runtime to 90%.
#
# Preflight runs this on a change to a host or to the runtime they share,
# and with --all at a milestone; `Scripts/test.sh coverage` runs it so the
# read counts the hosts. Measured on the M2 in a debug build: about 75 s,
# plus about 125 s for the cycle. Each gate writes its own log, and a
# failing gate's tail is printed under its name.

cd "$(dirname "$0")/.." || exit 1
emulate -L zsh

typeset -a gates=(
    "OllinLive --selftest"
    "OllinLive --watchtest"
    "OllinLive --dragtest"
    "OllinLive --paramtest"
    "OllinLive --savetest"
    "OllinLive --inspectortest"
    "OllinLiveCoding --selftest"
    "OllinLiveCoding --sessiontest"
    "OllinLiveCoding --dragtest"
    "OllinLiveCoding --controltest"
    "OllinRun --selftest"
    "OllinProjectGenerator --stagetest"
)
[[ "$1" == "--all" ]] && gates+=("OllinExamples --cycletest")

# The same flags as every other build here (OLLIN_SWIFT_FLAGS, empty on the
# desk), so this finds the products the last build made rather than
# rebuilding them under another command line.
if ! build=$(swift build ${=OLLIN_SWIFT_FLAGS} 2>&1); then
    print -r -- "$build" >&2
    exit 1
fi
bin=$(swift build --show-bin-path ${=OLLIN_SWIFT_FLAGS}) || exit 1

logs=$(mktemp -d) || exit 1
trap 'rm -rf "$logs"' EXIT
typeset -a failed=()
started=$SECONDS
for gate in $gates; do
    set -- ${=gate}
    log="$logs/${1}${2}.log"
    began=$SECONDS
    # Stdin closed, so a gate that ever waits on the terminal fails instead
    # of hanging the run.
    if "$bin/$1" "$2" > "$log" 2>&1 < /dev/null; then
        echo "host-gates: $gate passed in $((SECONDS - began)) s"
    else
        echo "host-gates: $gate FAILED after $((SECONDS - began)) s:" >&2
        tail -15 "$log" | sed 's/^/    /' >&2
        failed+=("$gate")
    fi
done
echo "host-gates: ${#gates} gates in $((SECONDS - started)) s"
if (( ${#failed} > 0 )); then
    echo "host-gates: failed: ${(j:, :)failed}" >&2
    exit 1
fi
