#!/bin/zsh
#
# Scripts/test.sh: run the test suite in an order that keeps it honest.
#
#   Scripts/test.sh              # the whole suite, in two phases (see below)
#   Scripts/test.sh quick        # the sub-minute pass: skips the GPU snapshot
#                                # table and the nested-build suite
#   Scripts/test.sh milestone    # the whole suite plus the four nested
#                                # signed-bundle builds (+570 s), which the
#                                # everyday run leaves out
#   Scripts/test.sh shard        # the same suite with OllinTests split
#                                # across processes: fewer minutes, more fans
#   Scripts/test.sh <pattern>    # swift test --filter <pattern>
#
# The sharded run exists because OllinTests draws through `Sketch`, which is
# main-actor isolated, so one process can only ever use one thread for it. See
# Scripts/shard-tests.sh for what that costs and what it buys.
#
# What the everyday run leaves out: the four cases in `Generated projects
# build` that build a whole signed bundle. They repeat, per bundle shape, the
# check the plain generated-package build already makes, and they take the
# suite from 155 s to 725 s. `Scripts/preflight.sh --milestone` runs them; so
# does `Scripts/test.sh milestone`. They report as skipped otherwise, so a run
# that did not make that check cannot be mistaken for one that did.
#
# Why phases: a few suites measure the world against a wall clock or a system
# ML model (DataFeedTests counts polls per elapsed second; ListeningTests waits
# on the speech stack), and one waits on the hardware video decoder. Run beside
# the heavy neighbors (241 off-screen GPU renders, nested package builds) they
# compete for a device they need to themselves, so they run FIRST on a quiet
# machine and everything else runs after.
#
# What phases do NOT fix, measured 2026-08-26: a suite that starves inside its
# own target. OllinVisionTests reached 113 s and 129 s running completely alone
# at 15% CPU, and PushFeedTests was frozen by its own helper parking all eight
# cooperative-pool threads. Both looked exactly like load and neither was. So
# the list below is only for a suite competing with OTHER targets for a
# device. A suite that fails while running alone has a defect, and moving it
# here only hides it. Before
# adding anything to the list below, run that suite's whole target by itself:
# if it still fails, this is the wrong tool. Check the process CPU too, since
# a timeout at 2% CPU is a parked thread pool, not a busy machine.
#
# Nor do phases fix a test that measures its own wall clock, since the clock
# starts when the test does and a run this size hands a task back minutes
# later. Two rules kill that at the root, and both are in CLAUDE.md: probe
# before reading the clock, and never touch the main actor from a suite that is
# not on it (measured 2026-08-29 at 74.8 s for no hop, 142.6 s for one, 617.0 s
# for two, in one 3,107-test run, against 2.5 s for the same suite alone).
# DataFeedTests keeps its place below all the same: its last test loads through
# the real system rather than a stub, and that load timed out inside a batch of
# every target at once even with both rules applied.
#
# Agent sessions: the full run takes many minutes, well past a default command
# timeout. Run it in the background or with an explicit long timeout, never as
# a plain foreground call. To re-check a single "flaky" suite after a full-run
# failure, `Scripts/test.sh <SuiteName>` is the isolation rerun.
#
# The skip patterns are anchored with the module name on purpose: swift-test
# patterns are unanchored regexes, and a bare `SnapshotTests` also matches
# OllinPhysicsTests.PhysicsSnapshotTests, silently dropping 46 real tests.

cd "$(dirname "$0")/.." || exit 1

# The suites that need a quiet machine, as anchored ID prefixes.
# SpatialVideoTests is here for a different reason than the wall-clock ones:
# its stereo HEVC readback goes through the hardware video decoder, and under
# a full parallel run that wait has wedged indefinitely rather than failing.
sensitive='OllinTests.DataFeedTests|OllinVisionTests.FrameSourceTests|OllinVisionTests.ModelTrackerTests|OllinAudioTests.ListeningTests|OllinTests.SpatialVideoTests'

phases() {
    echo "test.sh: phase 1 of 2, the wall-clock and device suites alone"
    swift test --filter "$sensitive" || exit 1
    echo "test.sh: phase 2 of 2, everything else"
    exec swift test --skip "$sensitive"
}

case "$1" in
--help | -h)
    sed -n '3,46p' "$0" | sed 's|^# \?||'
    exit 0
    ;;
quick)
    exec swift test --skip "OllinTests.SnapshotTests|GeneratedProjectBuildTests|$sensitive"
    ;;
shard | --shard)
    echo "test.sh: phase 1 of 3, the wall-clock and device suites alone"
    swift test --filter "$sensitive" || exit 1
    failed=0
    echo "test.sh: phase 2 of 3, OllinTests across several processes"
    Scripts/shard-tests.sh || failed=1
    echo "test.sh: phase 3 of 3, every other target"
    swift test --skip "$sensitive|^OllinTests\\." || failed=1
    exit $failed
    ;;
milestone | --milestone)
    echo "test.sh: milestone run; the four signed-bundle builds are included"
    export OLLIN_BUNDLE_BUILDS=1
    phases
    ;;
"")
    phases
    ;;
*)
    exec swift test --filter "$1"
    ;;
esac
