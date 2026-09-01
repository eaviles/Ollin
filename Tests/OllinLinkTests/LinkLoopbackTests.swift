import Foundation
import Testing
@testable import OllinLink

/// End-to-end over real UDP multicast on `127.0.0.1`: two clocks in this
/// process must discover each other, converge into one session, follow tempo
/// and transport changes, agree on bar phase, and part cleanly. Both
/// instances are restricted to the loopback interface on purpose, so a test
/// run never reaches (or is reached by) a real session on the local network.
/// The port is the protocol's fixed one and every clock here shares the one
/// loopback multicast group, so the tests run serialized: run together they
/// would join one another's sessions and wait forever for peers to leave.
/// (The same holds across processes; two overlapping test runs on one
/// machine can disturb each other's peer counts.)
@Suite(.serialized)
struct LinkLoopbackTests {

    struct Timeout: Error {}

    /// Polls `probe` until it returns a value or the timeout elapses. The
    /// probe comes before the clock is read: a starved task can wake past its
    /// own deadline having never looked, and giving up then would throw over
    /// an answer already in hand.
    func waitFor<T>(timeout: Double = 15.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 10_000_000)   // 10 ms
        }
    }

    @Test func aloneItFreeRuns() async throws {
        let clock = LinkClock(tempo: 120, restrictsToLoopback: true)
        #expect(!clock.isRunning)
        #expect(clock.peerCount == 0)
        #expect(abs(clock.tempo - 120) < 0.01)

        // The beat grid runs with no session and no network: at 120 BPM the
        // position advances two beats per second.
        //
        // Measured against the sleep that happened rather than the one that was
        // asked for. A loaded machine can oversleep by a wide margin, and the
        // grid keeps running while it does, so half a second of sleep is a
        // reading rather than a given: on CI this asked for 500ms inside a test
        // that took 520 seconds, and a fixed window called that a broken clock.
        // Each read of the grid is bracketed by a read of the wall clock, so
        // what the test knows is a window rather than an instant: the beats can
        // have advanced by as little as the inner gap and as much as the outer
        // one. Reading the two as though they happened together is what failed
        // here before, twice. This machine put 150ms between two adjacent
        // statements and 477 seconds into a test that sleeps for half of one,
        // and a window widens under that while a fixed tolerance cannot.
        let beforeStart = Date()
        let start = clock.beats
        let afterStart = Date()
        try await Task.sleep(nanoseconds: 500_000_000)
        let beforeEnd = Date()
        let advanced = clock.beats - start
        let afterEnd = Date()

        let least = beforeEnd.timeIntervalSince(afterStart) * 2
        let most = afterEnd.timeIntervalSince(beforeStart) * 2
        #expect(advanced >= least - 0.01 && advanced <= most + 0.01,
                "expected \(least) to \(most) beats, got \(advanced)")

        // The derived reads agree with each other.
        let beats = clock.beats
        #expect(clock.beatCount == Int(beats.rounded(.down)))
        #expect(clock.phase >= 0 && clock.phase < 1)
        #expect(clock.barPhase >= 0 && clock.barPhase < 1)
        #expect(clock.progress(over: 8) >= 0 && clock.progress(over: 8) < 1)

        clock.beatsPerBar = 3
        #expect(clock.beatsPerBar == 3)
    }

    @Test func twoClocksConvergeAndPart() async throws {
        let a = LinkClock(tempo: 120, restrictsToLoopback: true)
        let b = LinkClock(tempo: 95, restrictsToLoopback: true)
        a.start()
        b.start()
        defer {
            a.stop()
            b.stop()
        }
        #expect(a.isRunning && b.isRunning)

        // Discovery, measurement, and arbitration into a single session.
        _ = try await waitFor { a.peerCount >= 1 && b.peerCount >= 1 ? true : nil }

        // One tempo wins (whichever side's session prevailed).
        _ = try await waitFor { abs(a.tempo - b.tempo) < 0.01 ? true : nil }

        // A tempo change on one side propagates to the other.
        a.tempo = 150
        _ = try await waitFor { abs(b.tempo - 150) < 0.01 ? true : nil }

        // Transport started on B reaches A.
        #expect(!a.isPlaying)
        b.isPlaying = true
        _ = try await waitFor { a.isPlaying ? true : nil }

        // Bar phase agrees at (nearly) the same instant: both map onto the
        // session's shared grid. Read A, B, then A again, and require the
        // B sample to sit inside the A bracket (circularly), so scheduling
        // hiccups between the reads cannot fail a correct clock.
        _ = try await waitFor {
            let before = a.barPhase
            let sample = b.barPhase
            let after = a.barPhase
            let low = min(before, after), high = max(before, after)
            let inside = (high - low) < 0.5
                ? (sample >= low - 0.02 && sample <= high + 0.02)
                : (sample >= high - 0.02 || sample <= low + 0.02)   // wrapped past 1
            return inside ? true : nil
        }

        // A clean goodbye leaves the survivor alone, still on the shared
        // tempo, and its beat keeps running.
        b.stop()
        _ = try await waitFor { a.peerCount == 0 ? true : nil }
        #expect(abs(a.tempo - 150) < 0.01)
        let start = a.beats
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(a.beats > start)
    }

    @Test func stopAndRestartJoinAgain() async throws {
        let a = LinkClock(tempo: 120, restrictsToLoopback: true)
        let b = LinkClock(tempo: 120, restrictsToLoopback: true)
        a.start()
        b.start()
        defer {
            a.stop()
            b.stop()
        }
        _ = try await waitFor { a.peerCount >= 1 && b.peerCount >= 1 ? true : nil }

        b.stop()
        #expect(!b.isRunning)
        _ = try await waitFor { a.peerCount == 0 ? true : nil }

        // A restart begins with a fresh identity and joins again.
        b.start()
        _ = try await waitFor { a.peerCount >= 1 && b.peerCount >= 1 ? true : nil }
    }
}
