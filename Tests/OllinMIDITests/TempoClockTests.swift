import Foundation
import Testing
@testable import OllinMIDI

/// The tempo/position math behind `TempoClock`, driven with synthetic
/// timestamps so every scenario is deterministic: no Core MIDI, no real clock,
/// runs everywhere including CI. The one end-to-end loopback test lives at the
/// bottom and soft-skips where Core MIDI isn't available.
@Suite
struct TempoEngineTests {

    /// The tick interval for a given BPM (24 ticks per beat).
    func interval(bpm: Double) -> Double { 60 / (bpm * 24) }

    /// An engine that saw `start` at `t0` and then `count` ticks spaced evenly.
    /// Returns the engine and the time of the last tick.
    func playing(bpm: Double, ticks count: Int, from t0: Double = 1.0) -> (TempoEngine, Double) {
        var engine = TempoEngine()
        engine.handle(.start, at: t0)
        let dt = interval(bpm: bpm)
        var last = t0
        for k in 0..<count {
            last = t0 + 0.005 + Double(k) * dt
            engine.handle(.clock, at: last)
        }
        return (engine, last)
    }

    // MARK: Tempo

    @Test func locksTempoFromASteadyTrain() {
        let (engine, _) = playing(bpm: 120, ticks: 49)
        #expect(abs(engine.tempo - 120) < 0.001)
    }

    @Test func flattensTypicalJitter() {
        // ±1 ms of alternating jitter around a 120 BPM train.
        var engine = TempoEngine()
        engine.handle(.start, at: 0)
        let dt = interval(bpm: 120)
        for k in 0..<96 {
            let wobble = (k % 2 == 0 ? 0.001 : -0.001)
            engine.handle(.clock, at: Double(k) * dt + wobble)
        }
        #expect(abs(engine.tempo - 120) < 1.0)
    }

    /// A moderate tempo change converges as the window turns over.
    @Test func tracksAModerateTempoChange() {
        var (engine, last) = playing(bpm: 120, ticks: 49)
        let dt = interval(bpm: 90)
        for k in 1...60 { engine.handle(.clock, at: last + Double(k) * dt) }
        #expect(abs(engine.tempo - 90) < 0.5)
    }

    /// A large jump flushes the window, so the new tempo locks within a few ticks.
    @Test func relocksFastOnALargeJump() {
        var (engine, last) = playing(bpm: 120, ticks: 49)
        let dt = interval(bpm: 240)
        for k in 1...4 { engine.handle(.clock, at: last + Double(k) * dt) }
        #expect(abs(engine.tempo - 240) < 0.001)
    }

    /// A long gap is a stream break: the stale intervals are dropped, not averaged.
    @Test func aStreamBreakDoesNotPoisonTheTempo() {
        var (engine, last) = playing(bpm: 120, ticks: 49)
        let dt = interval(bpm: 120)
        engine.handle(.clock, at: last + 2.0)   // the break
        for k in 1...48 { engine.handle(.clock, at: last + 2.0 + Double(k) * dt) }
        #expect(abs(engine.tempo - 120) < 0.001)
    }

    // MARK: Position and transport

    /// `start` resets to zero and arms; the next tick is the downbeat itself.
    @Test func startArmsOnTheNextTick() {
        var engine = TempoEngine()
        engine.handle(.start, at: 1.0)
        #expect(engine.beats(at: 1.0) == 0)
        engine.handle(.clock, at: 1.1)
        #expect(engine.beats(at: 1.1) == 0)           // the downbeat instant
        engine.handle(.clock, at: 1.2)
        #expect(engine.beats(at: 1.2) == 1.0 / 24)    // one tick later
    }

    @Test func countsTicksIntoBeats() {
        let (engine, last) = playing(bpm: 120, ticks: 49)   // tick 0 anchors, 48 advance
        #expect(engine.beats(at: last) == 2.0)
    }

    /// Between ticks the position glides at the smoothed tempo.
    @Test func extrapolatesBetweenTicks() {
        let (engine, last) = playing(bpm: 120, ticks: 49)
        let dt = interval(bpm: 120)
        let mid = engine.beats(at: last + dt / 2)
        #expect(abs(mid - (2.0 + 0.5 / 24)) < 0.001)
    }

    /// A late tick can't run the position backward: extrapolation clamps just
    /// short of the next tick and waits.
    @Test func extrapolationClampsWhenTheClockStalls() {
        let (engine, last) = playing(bpm: 120, ticks: 49)
        let dt = interval(bpm: 120)
        let stalled = engine.beats(at: last + 3 * dt)
        #expect(stalled < 2.0 + 1.0 / 24)
        #expect(stalled >= 2.0)
    }

    @Test func stopFreezesAndContinueResumes() {
        var (engine, last) = playing(bpm: 120, ticks: 49)   // at beat 2.0
        engine.handle(.stop, at: last + 0.01)
        let dt = interval(bpm: 120)

        // Clock keeps arriving while stopped: tempo updates, position holds.
        for k in 1...24 { engine.handle(.clock, at: last + Double(k) * dt) }
        #expect(engine.beats(at: last + 24 * dt) == 2.0)
        #expect(!engine.isPlaying(at: last + 24 * dt))
        #expect(abs(engine.tempo - 120) < 0.001)

        // Continue: the next tick advances one tick from the frozen position.
        engine.handle(.continue, at: last + 25 * dt)
        engine.handle(.clock, at: last + 26 * dt)
        #expect(engine.beats(at: last + 26 * dt) == 2.0 + 1.0 / 24)
        #expect(engine.isPlaying(at: last + 26 * dt))
    }

    /// Song position jumps the position; the tick after a continue lands on it
    /// exactly (it anchors, it does not advance).
    @Test func songPositionRepositionsAContinue() {
        var (engine, last) = playing(bpm: 120, ticks: 49)
        engine.handle(.stop, at: last + 0.01)
        engine.handle(.songPosition(sixteenths: 16), at: last + 0.02)   // 16 sixteenths = 4 beats
        engine.handle(.continue, at: last + 0.03)
        engine.handle(.clock, at: last + 0.04)
        #expect(engine.beats(at: last + 0.04) == 4.0)
    }

    /// A master that only sends clock (no transport messages) free-runs: the
    /// first tick is beat zero and the position advances from there.
    @Test func freeRunsWithoutTransportMessages() {
        var engine = TempoEngine()
        let dt = interval(bpm: 100)
        for k in 0..<25 { engine.handle(.clock, at: Double(k) * dt) }
        #expect(engine.beats(at: 24 * dt) == 1.0)
        #expect(engine.isPlaying(at: 24 * dt))
        #expect(!engine.isPlaying(at: 24 * dt + 5))   // clock gone quiet
        #expect(abs(engine.tempo - 100) < 0.001)
    }

    @Test func reportsReceivingWithinASecond() {
        let (engine, last) = playing(bpm: 120, ticks: 49)
        #expect(engine.isReceiving(at: last + 0.5))
        #expect(!engine.isReceiving(at: last + 1.5))
    }
}

/// End-to-end over Core MIDI in-process: a `MIDIOutput` virtual source feeding a
/// `TempoClock` through a `MIDIInput`. Soft-skips when Core MIDI isn't
/// available (the engine tests above are the always-on guard).
@Suite
struct TempoClockLoopbackTests {

    /// The probe comes before the clock is read: a starved task can wake past
    /// its own deadline having never looked, and giving up then reports nothing
    /// arrived over a value that is already there.
    func waitFor<T>(timeout: Double = 3.0, _ probe: () -> T?) async -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { return nil }
            try? await Task.sleep(nanoseconds: 5_000_000)   // 5 ms
        }
    }

    @Test func followsAClockTrainAcrossTheLoopback() async {
        let output = MIDIOutput(name: "OllinTempoTest")
        let input = MIDIInput(name: "OllinTempoTestIn")
        do {
            try output.openVirtual(named: "OllinTempoTest Loopback")
            try input.start()
        } catch { return }   // soft-skip
        defer { output.close(); input.stop() }
        let clock = TempoClock(from: input)

        // The input connects to the new virtual source asynchronously; resend
        // a warmup CC until the link is live.
        let connected = await waitFor { () -> Bool? in
            output.controlChange(1, value: 1)
            return input.controlValue(1) != nil ? true : nil
        }
        guard connected == true else { return }   // soft-skip

        output.send(MIDIMessage(.start))

        // ~250 BPM nominal: 10 ms per tick, 30 ticks. What this test is for is
        // the crossing, that a train sent on a real port arrives and moves a
        // real clock. The tempo it settles at is not this test's business and
        // cannot be: a loaded machine oversleeps unevenly, and the reading is
        // then honestly slower than the mean, since the window is over the
        // ticks that arrived last. The number is pinned upstairs, where the
        // engine tests feed it timestamps of their own choosing (a steady
        // train to a thousandth, jitter flattened, a change tracked, a jump
        // relocked, a break survived).
        let started = Date()
        for _ in 0..<30 {
            output.send(MIDIMessage(.clock))
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        let sent = 60 / (24 * max(Date().timeIntervalSince(started) / 30, 1e-6))
        let advanced = await waitFor { clock.beatCount >= 1 ? true : nil }
        #expect(advanced == true)
        #expect(clock.isPlaying)
        #expect(clock.tempo > 1 && clock.tempo < 1000,
                "the clock reads \(clock.tempo) from a train sent at \(sent)")
    }
}
