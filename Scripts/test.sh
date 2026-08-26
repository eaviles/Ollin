#!/bin/zsh
#
# Scripts/test.sh: run the test suite in an order that keeps it honest.
#
#   Scripts/test.sh              # the whole suite, in two phases (see below)
#   Scripts/test.sh quick        # the sub-minute pass: skips the GPU snapshot
#                                # table and the nested-build suite
#   Scripts/test.sh <pattern>    # swift test --filter <pattern>
#
# Why phases: a handful of suites measure the world against a wall clock or a
# system ML model (DataFeedTests counts polls per elapsed second; the Vision
# live-wiring tests poll an analyzer; ListeningTests waits on the speech
# stack). Run beside the heavy neighbors (241 off-screen GPU renders, nested
# package builds), they starve and fail while passing alone in under a second,
# and the machine's GPU/ANE state right after heavy load can degrade model
# output too. So the sensitive suites run FIRST, on a cold quiet machine, and
# everything else runs after. A failure in phase 1 is a real signal; a failure
# of one of these suites inside a plain `swift test` usually is not.
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

case "$1" in
--help | -h)
    sed -n '3,26p' "$0" | sed 's|^# \?||'
    exit 0
    ;;
quick)
    exec swift test --skip "OllinTests.SnapshotTests|GeneratedProjectBuildTests|$sensitive"
    ;;
"")
    echo "test.sh: phase 1 of 2, the wall-clock and model suites alone"
    swift test --filter "$sensitive" || exit 1
    echo "test.sh: phase 2 of 2, everything else"
    exec swift test --skip "$sensitive"
    ;;
*)
    exec swift test --filter "$1"
    ;;
esac
