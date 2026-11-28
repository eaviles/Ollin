import Foundation
import Testing
import Ollin
import OllinTestSupport
@testable import OllinScreen

/// A screen capture's start takes its time: it asks the system what is on
/// screen and then waits for the stream to come up. What the sketch does
/// meanwhile decides what becomes of the stream that started: after a
/// `stop()` it is ended, and after the source changed only the newer one is
/// kept. The system's half is replaced here, since a test cannot grant itself
/// screen recording.
@MainActor
@Suite(.serialized) struct ScreenCaptureLifecycleTests {

    /// A start the test holds open, and a count of what happened to the
    /// streams it handed back.
    @MainActor
    final class SlowStart {
        var entered = 0
        var stopped: [String] = []
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func attempt(_ source: ScreenSource) async -> ScreenCapture.StartedStream? {
            entered += 1
            await withCheckedContinuation { waiting.append($0) }
            let label = source.label
            // A stream is stopped from the main actor everywhere but a
            // capture's own deinit, which no test here reaches with one held.
            return ScreenCapture.StartedStream(onStop: {
                MainActor.assumeIsolated { self.stopped.append(label) }
            })
        }

        /// Let the oldest start that is waiting finish.
        func finishOne() { waiting.removeFirst().resume() }
    }

    private func makeCapture(_ source: ScreenSource, _ slow: SlowStart) -> ScreenCapture {
        let capture = ScreenCapture(source)
        capture.hasAccess = { true }
        capture.startAttempt = { await slow.attempt($0) }
        return capture
    }

    /// Let the main actor run what a finished start queued on it.
    private func settle() async {
        for _ in 0..<8 { await Task { @MainActor in }.value }
    }

    @Test func aStartThatFinishesIsTheCapturesStream() async throws {
        let slow = SlowStart()
        let capture = makeCapture(.mainDisplay, slow)
        capture.start()
        _ = try await waitFor { slow.entered == 1 ? true : nil }
        #expect(capture.isRunning && !capture.streamIsLive)
        slow.finishOne()
        _ = try await waitFor { capture.streamIsLive ? true : nil }
        #expect(slow.stopped.isEmpty)

        capture.stop()
        #expect(!capture.isRunning && !capture.streamIsLive)
        #expect(slow.stopped.count == 1, "stop() ends the stream it holds")
    }

    /// `stop()` while the stream is still coming up: the stream that then
    /// starts is nobody's, so it is ended. Left running, the capture reads
    /// as off while the system goes on recording the screen.
    @Test func stoppingWhileAStartIsInFlightEndsTheStreamThatStarts() async throws {
        let slow = SlowStart()
        let capture = makeCapture(.mainDisplay, slow)
        capture.start()
        _ = try await waitFor { slow.entered == 1 ? true : nil }

        capture.stop()
        slow.finishOne()
        await settle()
        #expect(!capture.isRunning)
        #expect(!capture.streamIsLive, "a capture that was stopped holds a live stream")
        #expect(slow.stopped.count == 1, "the stream that started after stop() was left running")
        #expect(capture.unavailableReason == nil)
    }

    /// The source changes while the first stream is still coming up: the
    /// capture ends up on the new source, with the first stream ended.
    @Test func changingTheSourceWhileAStartIsInFlightKeepsOnlyTheNewOne() async throws {
        let slow = SlowStart()
        let capture = makeCapture(.app("First"), slow)
        capture.start()
        _ = try await waitFor { slow.entered == 1 ? true : nil }

        capture.source = .app("Second")
        _ = try await waitFor { slow.entered == 2 ? true : nil }
        // The first start comes up after the source it was for is no longer
        // the one wanted.
        slow.finishOne()        // the first, superseded
        await settle()
        #expect(!capture.streamIsLive, "the superseded start became the capture's stream")
        slow.finishOne()        // the second
        _ = try await waitFor { capture.streamIsLive ? true : nil }
        #expect(slow.stopped == [ScreenSource.app("First").label])

        capture.stop()
        #expect(slow.stopped.count == 2)
    }
}
