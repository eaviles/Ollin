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
#   Scripts/test.sh ci           # the runner's recipe (build.yml): the loopback
#                                # suites alone, then OllinTests as two shards
#                                # with every other target running beside them,
#                                # minus the suites that want a device the
#                                # runner does not have
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

# What the CI runner cannot run, on top of the sensitive suites above, which
# it skips outright (it has none of the devices they want). Found one runner
# failure at a time, and kept here rather than in the workflow so the
# knowledge lives beside the rest of it. The snapshot references are recorded
# on a developer's GPU and the runner's paravirtual one anti-aliases
# differently; Vision reports no compute device there at all (optical flow,
# the segmenter's live wiring); screen capture is permitted and delivers no
# frame; the frame interpolation gate wants a camera; the two build suites run
# whole nested builds inside a test (the generated packages at 15 serialized
# minutes, the phone host at 9 minutes on the runner's three cores, with the
# framework's own iOS compile already made by preflight on every change).
# The virtual camera suite is the one no probe can guard: its first call into
# CoreMediaIO makes the framework initialize its extension plug-ins, which
# sends an XPC message to an extension host that never answers on the runner,
# and a thread parked in a synchronous C call is beyond any suite time limit.
# Two of the pool's three threads sat there for the rest of the run
# (2026-09-08, run 34236822231: 2,971 tests in seven minutes, then silence
# until the watchdog sampled and killed it; the sample names both tests),
# and a video export waiting on the main thread never got its worker.
# A new device test belongs behind an `.enabled(if:)` probe of its device,
# not here: it then refuses itself wherever the device is absent.
runner='OllinTests.SnapshotTests|FlowTrackerTests|measuresAPairInline|OllinScreenTests.ScreenCaptureTests|liveWiringPublishesMatteCutoutAndCount|theGateNeedsACameraAndAHostThatCanSpareARefresh|GeneratedProjectBuildTests|PhoneProjectBuildTests|OllinCameraTests.VirtualCameraTests'

# The runner's own quiet phase: the loopback suites send a clock train or a
# frame through a real system service (Core MIDI, the Link session's socket,
# the laser's stand-in DAC) and measure what arrives against a window. Beside
# two shards on three cores they starve: the timecode clock's one-second
# window closed before its probe ran, the tempo clock read no tempo at all
# (2026-09-08, run 34248343439, both in the third process at minute ten). Run
# alone first they take seconds, the same phasing the desk gives its
# wall-clock suites above.
loopback='OllinMIDITests.MIDILoopbackTests|OllinMIDITests.TempoClockLoopbackTests|OllinLinkTests.LinkLoopbackTests|OllinLaserTests.EtherDreamLoopbackTests'

# The same phase for the same reason, one target over: two suites inside
# OllinTests that cannot share three cores with two shards of themselves.
# PushFeedTests drives a real local HTTP server and measures what arrives
# against deadlines, and beside the shards its tasks resume so late that seven
# of them expired together at three minutes on a stopwatch none of them got to
# read (2026-09-09, run 34299549773). MaterialSourceTests spawns a swiftc to
# typecheck the source it prints, which is a minute of compiler on a quiet
# machine and neither finished nor useful on a crowded one. Run alone they cost
# a couple of minutes and say what they mean.
crowded='OllinTests.PushFeedTests|OllinTests.MaterialSourceTests'

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
ci)
    # The loopback suites alone, then two shards of OllinTests and one process
    # for every other target at once. Everything is built first so that
    # neither the shards (which invoke the bundle directly) nor
    # `swift test --skip-build` has anything left to compile. The third
    # process runs at a lower priority: the shards are main-thread bound and
    # their pools leave the cores to it, but with all three at the same
    # priority one shard's main thread got no time for six minutes while the
    # third process drained its own queue (the heartbeat showed it sitting at
    # zero). Each line says which of the three wrote it.
    echo "test.sh: the runner's recipe; the suites that need the machine alone, then OllinTests as ${OLLIN_CI_SHARDS:-2} shards with the other targets beside them"
    swift build --build-tests || exit 1
    echo "test.sh: phase 1 of 2, the suites that need the machine to themselves"
    swift test --skip-build --filter "$loopback|$crowded" || exit 1
    echo "test.sh: phase 2 of 2, the shards and the rest"
    export OLLIN_SHARD_SKIP="$sensitive|$runner|$crowded"
    Scripts/shard-tests.sh "${OLLIN_CI_SHARDS:-2}" > >(sed -l 's/^/[shards] /') 2>&1 &
    shardsPid=$!
    nice -n 10 swift test --skip-build --skip "$sensitive|$runner|$loopback|$crowded|^OllinTests\\." > >(sed -l 's/^/[rest] /') 2>&1 &
    restPid=$!
    failed=0
    wait $shardsPid || failed=1
    wait $restPid || failed=1
    exit $failed
    ;;
"")
    phases
    ;;
*)
    exec swift test --filter "$1"
    ;;
esac
