import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// Invariants of the sound that hold whatever the implementation: a passive body only
/// ever loses the energy it was given, a driven one stays bounded however hard it is
/// driven, and a sound placed in space is mirrored by a mirrored place and never
/// amplified by the placing. Each is read off rendered samples against an analytic
/// statement or a twin render, never against the engine's own arithmetic.
@Suite(.serialized)
struct SoundInvariantTests {
    static let sampleRate = 44100.0

    // MARK: Sample support

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        var acc = 0.0
        for s in samples { acc += Double(s) * Double(s) }
        return (acc / Double(samples.count)).squareRoot()
    }

    /// Window loudness from `start` on, every `window` seconds.
    private func envelope(_ samples: [Float], start: Double, window: Double) -> [Double] {
        let step = Int(window * Self.sampleRate)
        var out: [Double] = []
        var at = Int(start * Self.sampleRate)
        while at + step <= samples.count {
            out.append(rms(samples[at..<(at + step)]))
            at += step
        }
        return out
    }

    /// The first window the loudness rose past the one before it by more than the
    /// allowed ripple, or nil when it only ever fell.
    private func firstRise(in env: [Double], ripple: Double) -> (index: Int, from: Double, to: Double)? {
        for i in 1..<env.count where env[i] > env[i - 1] * (1 + ripple) + 1e-5 {
            return (i, env[i - 1], env[i])
        }
        return nil
    }

    private func render(_ voice: Voice, midi: Double, seconds: Double, velocity: Double = 0.8,
                        drive: Double? = nil, seed: UInt64 = 5) -> [Float] {
        let events = EventRing()
        let renderer = SynthRenderer(voice: voice, polyphony: 4, sampleRate: Self.sampleRate,
                                     events: events, seed: seed)
        renderer.gain = 1
        if let drive { renderer.pressure = drive }
        events.push(SynthEvent(kind: .noteOn, pitch: midi, velocity: velocity))
        let count = Int(seconds * Self.sampleRate)
        var samples = [Float](repeating: 0, count: count)
        samples.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: count) }
        return samples
    }

    /// A flat envelope, so what is measured is the body and not the shape laid over it.
    private static let flat = Envelope(attack: 0.0002, decay: 0.001, sustain: 1, release: 0.1)

    // MARK: Passive bodies

    /// A plucked string is passive: once the pick leaves it, every window of its sound
    /// is no louder than the one before. A loop that gains, a filter that rings up, or
    /// an excitation that keeps arriving all read as a rise.
    @Test(arguments: [PluckedString.nylon, .steel, .harp, .muted])
    func aPluckedStringOnlyEverLosesEnergy(string: PluckedString) {
        let samples = render(Voice(plucked: string, envelope: Self.flat, gain: 1), midi: 57, seconds: 2.0)
        // Eleven whole periods a window at this pitch, so the harmonics' cross
        // terms cancel and the ripple allowance can be small.
        let env = envelope(samples, start: 0.1, window: 0.1)
        #expect(env.first ?? 0 > 0.001, "the string made no sound")
        if let rise = firstRise(in: env, ripple: 0.005) {
            Issue.record("the string got louder in window \(rise.index): \(rise.from) to \(rise.to)")
        }
    }

    /// A struck body is passive too: its modes ring down and nothing feeds them.
    @Test(arguments: [ModalBody.drum, .plate, .bar, .bell, .wood, .glass])
    func aStruckBodyOnlyEverLosesEnergy(body: ModalBody) {
        let samples = render(Voice(struck: body, envelope: Self.flat, gain: 1), midi: 60, seconds: 2.2,
                             velocity: 0.9)
        let env = envelope(samples, start: 0.1, window: 0.2)
        #expect(env.first ?? 0 > 0.001, "the body made no sound")
        if let rise = firstRise(in: env, ripple: 0.03) {
            Issue.record("the body got louder in window \(rise.index): \(rise.from) to \(rise.to)")
        }
    }

    // MARK: Driven bodies

    private static let drivenVoices: [(String, Voice)] = [
        ("violin", Voice(bowed: .violin, gain: 0.7)), ("cello", Voice(bowed: .cello, gain: 0.7)),
        ("ponticello", Voice(bowed: .ponticello, gain: 0.7)), ("clarinet", Voice(blown: .clarinet, gain: 0.6)),
        ("reedy", Voice(blown: .reedy, gain: 0.6)), ("hollow", Voice(blown: .hollow, gain: 0.6)),
    ]

    /// A driven body is stable at every drive: however hard it is bowed or blown, at
    /// a low note or a high one, the sound stays inside the range and does not sit on
    /// the ceiling (a model that ran away and got clipped reads as a square wave).
    @Test(arguments: [0.02, 0.3, 1.0], [48.0, 72.0])
    func aDrivenBodyStaysBoundedAtAnyDrive(drive: Double, midi: Double) {
        for (name, voice) in Self.drivenVoices {
            let samples = render(voice, midi: midi, seconds: 1.0, velocity: 0.9, drive: drive)
            let peak = samples.reduce(0) { max($0, abs($1)) }
            let onTheCeiling = Double(samples.filter { abs($0) > 0.95 }.count) / Double(samples.count)
            #expect(peak <= 1.0, "\(name) at drive \(drive), note \(midi) peaked at \(peak)")
            #expect(onTheCeiling < 0.05, "\(name) at drive \(drive), note \(midi) sat on the ceiling \(onTheCeiling * 100)% of the time")
        }
    }

    // MARK: Placing a sound

    /// A listener at the origin looking down -z, where a camera looks.
    private static func listener() -> Camera3D {
        Camera3D(eye: .zero, target: Vector3(0, 0, -1))
    }

    @MainActor
    private func exporting(_ body: () -> Void) {
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        body()
    }

    /// One note, held still somewhere (or nowhere), for a second and a half.
    @MainActor
    private func placed(at position: Vector3?, seconds: Double = 1.5) -> [Float] {
        let synth = Synth(.bell)
        synth.hearingDistance = 1...50
        exporting {
            let step = 1.0 / 60
            var elapsed = 0.0
            while elapsed < seconds {
                if let position { synth.place(at: position, heardFrom: Self.listener()) }
                if elapsed == 0 { synth.play(72, velocity: 0.9, for: 1.0) }
                synth.advance(by: step)
                elapsed += step
            }
        }
        return synth.renderExportAudio(upTo: seconds, sampleRate: Self.sampleRate)
    }

    /// Loudness of one channel of interleaved stereo over the note.
    private func level(_ samples: [Float], channel: Int) -> Double {
        let start = Int(0.05 * Self.sampleRate), end = min(samples.count / 2, Int(1.4 * Self.sampleRate))
        var acc = 0.0
        for frame in start..<end { let v = Double(samples[frame * 2 + channel]); acc += v * v }
        return (acc / Double(end - start)).squareRoot()
    }

    /// A sound mirrored across the listener's nose is heard mirrored: the left ear's
    /// share of one is the right ear's share of the other.
    @MainActor
    @Test func aMirroredPlaceSwapsTheEars() {
        let toTheLeft = placed(at: Vector3(-6, 0, -2))
        let toTheRight = placed(at: Vector3(6, 0, -2))
        let ll = level(toTheLeft, channel: 0), lr = level(toTheLeft, channel: 1)
        let rl = level(toTheRight, channel: 0), rr = level(toTheRight, channel: 1)
        #expect(ll > 0.005 && rr > 0.005, "a placed note was silent")
        #expect(abs(ll / rr - 1) < 0.02, "the near ears differ: left \(ll) against right \(rr)")
        #expect(abs(lr / rl - 1) < 0.02, "the far ears differ: \(lr) against \(rl)")
    }

    /// Placing never amplifies: however near the listener a sound is put, it carries
    /// no more power than the same note unplaced. The listener's centered pan sits at
    /// about 0.6 of the dry stream in each ear (measured at half a unit), so the bound
    /// has that much headroom: a stream doubled on its way to the listener reads, a
    /// stream and a half does not.
    @MainActor
    @Test(arguments: [0.5, 2.0, 8.0])
    func placingNeverAmplifies(distance: Double) {
        let unplaced = placed(at: nil)
        let near = placed(at: Vector3(0, 0, -distance))
        func power(_ s: [Float]) -> Double {
            let l = level(s, channel: 0), r = level(s, channel: 1)
            return l * l + r * r
        }
        let ratio = power(near) / power(unplaced)
        #expect(ratio <= 1.02, "a sound \(distance) away carried \(ratio) of its unplaced power")
    }
}
