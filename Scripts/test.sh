#!/bin/zsh
#
# Scripts/test.sh: run the test suite in an order that keeps it honest.
#
#   Scripts/test.sh              # the whole suite, in phases (see below)
#   Scripts/test.sh quick        # the sub-minute pass: skips the GPU snapshot
#                                # table and the nested-build suite
#   Scripts/test.sh milestone    # the whole suite plus the five nested
#                                # signed-bundle builds (+940 s), which the
#                                # everyday run leaves out
#   Scripts/test.sh shard        # the same suite with OllinTests split
#                                # across processes: fewer minutes, more fans
#   Scripts/test.sh ci           # the runner's recipe (build.yml), which is
#                                # this same order with two shards and the
#                                # other targets running beside them
#   Scripts/test.sh tsan         # the handoffs under Thread Sanitizer: the
#                                # targets whose tests run without the GPU,
#                                # in a second, instrumented build of their
#                                # own under .build/tsan
#   Scripts/test.sh <pattern>    # swift test --filter <pattern>
#
# One rule decides the order: a suite that measures the outside world against a
# clock, or that holds a device or a name only one process can have, runs on a
# quiet machine; everything else runs together. Three of the lists below are
# its cases, the fourth is what a CI runner cannot run at all, and the fifth is
# what runs under the sanitizer. Tests/README.md says why each is there, what a phase does NOT fix (a
# suite that starves inside its own target, a parked pool, a deadline read
# before its probe, a main-actor hop), and how to place a new test. Read that
# before adding anything to a list here.
#
# The sharded run exists because OllinTests draws through `Sketch`, which is
# main-actor isolated, so one process can only ever use one thread for it. See
# Scripts/shard-tests.sh for what that costs and what it buys.
#
# What the everyday run leaves out: the five cases in `Generated projects
# build` that build a whole signed bundle. They repeat, per bundle shape, the
# check the plain generated-package build already makes, and they take the
# suite from 228 s to 1,174 s. `Scripts/preflight.sh --milestone` runs them; so
# does `Scripts/test.sh milestone`. They report as skipped otherwise, so a run
# that did not make that check cannot be mistaken for one that did.
#
# The sanitizer run is a milestone check rather than a preflight gate, by its
# cost: an instrumented build is a whole second build (a few minutes cold,
# under .build/tsan so it never shares an object with the plain one), and the
# tests run several times slower than they do plain. `Scripts/preflight.sh
# --milestone` runs it. The list below names the targets in it; Tests/README.md
# says why those, why the GPU suites stay out, and what a run measured.
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

# Phase one: the suites that want a device or a wall clock to themselves.
# DataFeedTests counts polls per elapsed second, ListeningTests waits on the
# speech stack, FrameSourceTests and ModelTrackerTests want the Vision compute
# device, and SpatialVideoTests and PhonePictureRoundTripTests go through the
# hardware video decoder, whose wait has wedged rather than failed under a full
# parallel run.
sensitive='OllinTests.DataFeedTests|OllinVisionTests.FrameSourceTests|OllinVisionTests.ModelTrackerTests|OllinAudioTests.ListeningTests|OllinTests.SpatialVideoTests|OllinPhoneTests.PhonePictureRoundTripTests'

# Phase two, part one: the suites that send something through a real system
# service and measure what comes back (Core MIDI, the Link session's socket,
# the laser's stand-in DAC). Beside a full run they starve.
loopback='OllinMIDITests.CoreMIDILoopback|OllinLinkTests.LinkLoopbackTests|OllinLaserTests.EtherDreamLoopbackTests'

# Phase two, part two: the suites that cannot share the machine with the rest.
# PushFeedTests drives a real local HTTP server against deadlines,
# MaterialSourceTests spawns a swiftc, and PhoneTouchTests is the one
# @MainActor suite carrying a per-test time limit.
crowded='OllinTests.PushFeedTests|OllinTests.MaterialSourceTests|OllinPhoneTests.PhoneTouchTests'

# What the CI runner cannot run at all, on top of the phases above, which it
# skips outright (it has none of the devices they want). Found one runner
# failure at a time, and kept here rather than in the workflow so the knowledge
# lives beside the rest of it. Tests/README.md lists what each one needs.
# A new device test belongs behind an `.enabled(if:)` probe of its device,
# not here: it then refuses itself wherever the device is absent.
runner='OllinTests.SnapshotTests|FlowTrackerTests|measuresAPairInline|OllinScreenTests.ScreenCaptureTests|liveWiringPublishesMatteCutoutAndCount|theGateNeedsACameraAndAHostThatCanSpareARefresh|GeneratedProjectBuildTests|PhoneProjectBuildTests|OllinCameraTests.VirtualCameraTests'

# The handoffs under Thread Sanitizer: every target whose tests run without
# the GPU, which is where the producer-to-reader shape (an `@unchecked
# Sendable` producer handing off through an `OSAllocatedUnfairLock`) lives:
# the wires (OSC, MIDI, MQTT, Link, Serial, DMX, the laser, Bluetooth, the
# controllers, haptics, the remote surface, the room), the phone's codecs
# and readers, the audio engine, the mutation harness, and the two feeds.
# The drawing suites stay out: a render's threads run in Metal, which the
# sanitizer never instrumented, and a snapshot compares pixels, not orderings.
tsan='^OllinOSCTests\.|^OllinMIDITests\.|^OllinMQTTTests\.|^OllinLinkTests\.|^OllinRoomTests\.|^OllinSerialTests\.|^OllinRemoteTests\.|^OllinAudioTests\.|^OllinPhoneTests\.|^OllinRecord3DTests\.|^OllinBluetoothTests\.|^OllinControllerTests\.|^OllinHapticsTests\.|^OllinLaserTests\.|^OllinDMXTests\.|^OllinMutationTests\.|^OllinTests\.DataFeedTests|^OllinTests\.PushFeedTests'

phases() {
    echo "test.sh: phase 1 of 3, the wall-clock and device suites alone"
    swift test --filter "$sensitive" || exit 1
    echo "test.sh: phase 2 of 3, the suites that want the machine to themselves"
    swift test --filter "$loopback|$crowded" || exit 1
    echo "test.sh: phase 3 of 3, everything else"
    exec swift test --skip "$sensitive|$loopback|$crowded"
}

case "$1" in
--help | -h)
    sed -n '3,56p' "$0" | sed 's|^# \?||'
    exit 0
    ;;
quick)
    exec swift test --skip "OllinTests.SnapshotTests|GeneratedProjectBuildTests|$sensitive"
    ;;
shard | --shard)
    echo "test.sh: phase 1 of 4, the wall-clock and device suites alone"
    swift test --filter "$sensitive" || exit 1
    echo "test.sh: phase 2 of 4, the suites that want the machine to themselves"
    swift test --filter "$loopback|$crowded" || exit 1
    failed=0
    echo "test.sh: phase 3 of 4, OllinTests across several processes"
    # The crowded suites ran alone above, so the shards leave them out.
    OLLIN_SHARD_SKIP="$crowded" Scripts/shard-tests.sh || failed=1
    echo "test.sh: phase 4 of 4, every other target"
    swift test --skip "$sensitive|$loopback|$crowded|^OllinTests\\." || failed=1
    exit $failed
    ;;
milestone | --milestone)
    echo "test.sh: milestone run; the five signed-bundle builds are included"
    export OLLIN_BUNDLE_BUILDS=1
    phases
    ;;
tsan | --tsan)
    # One process, one phase: the sanitizer's own slowdown spreads the
    # suites out, and the loopback windows held in the measured runs. The
    # reports go to files of their own (log_path) so that the test output
    # stays readable and a report cannot scroll off unread; they are printed
    # after the run, and any report fails it whatever the tests said, since
    # the sanitizer only sets the exit status when its own runtime finalizes.
    # Scripts/tsan-suppressions.txt excuses one class of report, an ordering
    # that runs through a system framework the sanitizer cannot see into,
    # and says so per entry.
    echo "test.sh: the handoffs under Thread Sanitizer; an instrumented build under .build/tsan, then the non-GPU targets"
    reports=$(mktemp -d) || exit 1
    export TSAN_OPTIONS="halt_on_error=0 log_path=$reports/tsan suppressions=$PWD/Scripts/tsan-suppressions.txt${TSAN_OPTIONS:+ $TSAN_OPTIONS}"
    swift test --sanitize=thread --scratch-path .build/tsan --filter "$tsan"
    outcome=$?
    # A clean run leaves no report file: the (N) qualifier makes the empty
    # glob expand to nothing rather than an error, and stdin is closed so a
    # `cat` with no files cannot sit waiting on the terminal.
    found=$(cat "$reports"/tsan.*(N) < /dev/null 2>/dev/null | grep -c '^SUMMARY: ThreadSanitizer') || true
    if (( found > 0 )); then
        cat "$reports"/tsan.*
        echo "test.sh: Thread Sanitizer reported $found finding(s); the reports are above" >&2
        rm -rf "$reports"
        exit 1
    fi
    rm -rf "$reports"
    (( outcome == 0 )) && echo "test.sh: Thread Sanitizer reported nothing"
    exit $outcome
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
    swift build --build-tests ${=OLLIN_SWIFT_FLAGS} || exit 1
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
