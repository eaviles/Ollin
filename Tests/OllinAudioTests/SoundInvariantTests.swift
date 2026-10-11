import AVFoundation
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

    // MARK: Survey B (2026-10-11): pitch, modes, and the models' promises

    /// A measured gap stands as a known issue only where it was measured; the
    /// statement runs plain everywhere else.
    private func pinned(_ reason: Comment, when active: Bool = true, _ body: () -> Void) {
        if active { withKnownIssue(reason, body) } else { body() }
    }

    /// Magnitude of the DFT at one frequency over a slice, by the direct sum.
    private func magnitude(_ s: ArraySlice<Float>, hz: Double, sampleRate: Double = sampleRate) -> Double {
        var re = 0.0, im = 0.0
        let w = 2 * Double.pi * hz / sampleRate
        var n = 0.0
        for v in s { re += Double(v) * cos(w * n); im -= Double(v) * sin(w * n); n += 1 }
        return (re * re + im * im).squareRoot()
    }

    /// The strongest line within a semitone of `near`, refined by a parabola over
    /// the neighboring scan steps.
    private func peak(_ s: ArraySlice<Float>, near: Double, sampleRate: Double = sampleRate) -> Double {
        let lo = near / pow(2, 1.0 / 12), hi = near * pow(2, 1.0 / 12)
        let step = max(0.25, near * 0.002)
        var best = lo, bestMag = -1.0
        var f = lo
        while f <= hi {
            let m = magnitude(s, hz: f, sampleRate: sampleRate)
            if m > bestMag { bestMag = m; best = f }
            f += step
        }
        let a = magnitude(s, hz: best - step, sampleRate: sampleRate)
        let c = magnitude(s, hz: best + step, sampleRate: sampleRate)
        let denom = a - 2 * bestMag + c
        return best + (denom != 0 ? 0.5 * (a - c) / denom : 0) * step
    }

    private func cents(_ measured: Double, _ expected: Double) -> Double { 1200 * log2(measured / expected) }

    private func hertz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    /// Like `render`, in blocks, with the pressure taken away at `liftAt`.
    private func renderLifting(_ voice: Voice, midi: Double, seconds: Double, drive: Double,
                               liftAt: Double) -> [Float] {
        let events = EventRing()
        let renderer = SynthRenderer(voice: voice, polyphony: 4, sampleRate: Self.sampleRate,
                                     events: events, seed: 5)
        renderer.gain = 1
        renderer.pressure = drive
        events.push(SynthEvent(kind: .noteOn, pitch: midi, velocity: 0.9))
        let count = Int(seconds * Self.sampleRate)
        var samples = [Float](repeating: 0, count: count)
        var done = 0
        samples.withUnsafeMutableBufferPointer { buffer in
            while done < count {
                let n = min(256, count - done)
                let t = Double(done) / Self.sampleRate
                if t >= liftAt, t - Double(n) / Self.sampleRate < liftAt { renderer.pressure = 0 }
                renderer.render(into: UnsafeMutableBufferPointer(rebasing: buffer[done..<(done + n)]),
                                frameCount: n)
                done += n
            }
        }
        return samples
    }

    /// A plucked string sounds the note it was asked for: its fundamental sits
    /// within a cent of the pitch at every octave, which is what the tuning
    /// allpass is for (a whole-sample loop is up to a third of a semitone sharp
    /// at the top).
    @Test(arguments: [PluckedString.nylon, .steel, .harp])
    func aPluckedStringSoundsItsNote(string: PluckedString) {
        for midi in [33.0, 45, 57, 69, 81, 93] {
            let s = render(Voice(plucked: string, envelope: Self.flat, gain: 1), midi: midi, seconds: 1.0)
            let f = peak(s[Int(0.3 * Self.sampleRate)...], near: hertz(midi))
            let off = cents(f, hertz(midi))
            #expect(abs(off) <= 1, "MIDI \(midi) sounds \(off) cents off")
        }
    }

    /// A bowed string and a blown tube sound their note too, within five cents
    /// (their junctions switch on sample boundaries, so the top of the range
    /// cannot hold the string's tenth of a cent): measured 2026-10-11 at up to
    /// four cents sharp from MIDI 69 up.
    @Test(arguments: [("violin", Voice(bowed: .violin, gain: 0.7)), ("cello", Voice(bowed: .cello, gain: 0.7)),
                      ("clarinet", Voice(blown: .clarinet, gain: 0.6)), ("reedy", Voice(blown: .reedy, gain: 0.6)),
                      ("hollow", Voice(blown: .hollow, gain: 0.6))])
    func aDrivenVoiceSoundsItsNote(name: String, voice: Voice) {
        for midi in [45.0, 57, 69, 81, 93] {
            let s = render(voice, midi: midi, seconds: 1.2, velocity: 0.9, drive: 0.8)
            let slice = s[Int(0.4 * Self.sampleRate)...]
            let f = peak(slice, near: hertz(midi))
            let off = cents(f, hertz(midi))
            pinned("the reedy tube's pitch moves with pressure at the top of its range, 14 cents flat at MIDI 93 at pressure 0.8 (measured 2026-10-11)",
                   when: name == "reedy" && midi == 93) {
                #expect(abs(off) <= 5, "\(name) at MIDI \(midi) sounds \(off) cents off")
            }
        }
    }

    /// A shape struck is a membrane of that shape: a disc rings at the Bessel
    /// zeros a circular membrane does, in order and in ratio.
    @Test func aStruckDiscRingsAtAMembranesModes() {
        let disc = Shape((0..<160).map { step in
            let angle = Double(step) / 160 * .tau
            return Vector2(cos(angle) * 100, sin(angle) * 100)
        })
        let measured = StruckShape(disc, modes: 8, resolution: 44)
        #expect(measured != nil)
        let membrane = [1.0, 1.593, 1.593, 2.136, 2.136, 2.295, 2.653, 2.653]
        for (ratio, expected) in zip(measured?.ratios ?? [], membrane) {
            #expect(abs(ratio / expected - 1) < 0.01, "a mode at \(ratio) where the membrane has \(expected)")
        }
    }

    /// A struck body is a handful of pure tones fading at their own rates, so
    /// nothing in its sound should sit on the renderer's ceiling, and a bell's
    /// sound should hold nothing at 1.4 or 3.4 times the note, which are not
    /// among its partials.
    ///
    /// Measured 2026-10-11 and filed: the strike's push is a raised cosine whose
    /// area grows with its length, and nothing divides it out, so every preset
    /// but `.wood` drives the renderer's soft clip at its attack (the bell sits
    /// above 0.95 for 56% of its first second, glass 92%, the drum 6%) and the
    /// clip's intermodulation puts lines at 1.4 and 3.4 times the note 7 dB
    /// under the bell's prime. At hardness 1 (a push two samples long) the same
    /// bell peaks at 0.59 and those lines sit 50 dB down.
    @Test(arguments: [("bell", ModalBody.bell), ("glass", .glass), ("drum", .drum), ("wood", .wood)])
    func aStruckBodyIsASumOfTones(name: String, body: ModalBody) {
        let s = render(Voice(struck: body, envelope: Self.flat, gain: 1), midi: 60, seconds: 1.5, velocity: 0.9)
        let first = s[0..<Int(1.0 * Self.sampleRate)]
        let onTheCeiling = Double(first.filter { abs($0) > 0.95 }.count) / Double(first.count)
        pinned("the strike's push is not normalized by its area, so the bell, glass, and drum presets clip at their attack (measured 2026-10-11)", when: name != "wood") {
            #expect(onTheCeiling < 0.01, "\(name) sat on the ceiling \(onTheCeiling * 100)% of its first second")
            if name == "bell" {
                let slice = s[Int(0.1 * Self.sampleRate)..<Int(0.6 * Self.sampleRate)]
                let prime = magnitude(slice, hz: 2 * 261.63)
                let foreign = max(magnitude(slice, hz: 1.4 * 261.63), magnitude(slice, hz: 3.4 * 261.63))
                #expect(20 * log10(foreign / prime) < -40, "a line \(20 * log10(foreign / prime)) dB under the prime at a frequency the bell has no partial at")
            }
        }
    }

    /// `decay` is how long the note takes to fade at the note being played, so
    /// the fundamental's T60 is `decay` at every pitch.
    ///
    /// Measured 2026-10-11 and filed: the loop gain is set as if the loop filter
    /// were lossless at the fundamental, and the one-zero's own loss at a high
    /// note is not compensated, so the steel string's 3.6 s is 3.6 s at MIDI 45
    /// and 0.64 s at MIDI 93 (nylon's 1.8 s becomes 0.42 s).
    @Test(arguments: [PluckedString.steel, .nylon])
    func aPluckedStringRingsForItsDecayAtEveryPitch(string: PluckedString) {
        for midi in [45.0, 93] {
            let s = render(Voice(plucked: string, envelope: Self.flat, gain: 1), midi: midi, seconds: 4.0)
            var points: [(Double, Double)] = []
            var t = 0.05
            while t < 3.9 {
                let a = Int(t * Self.sampleRate), b = a + Int(0.05 * Self.sampleRate)
                let m = magnitude(s[a..<b], hz: hertz(midi))
                if m > 1e-3 { points.append((t, 20 * log10(m))) }
                t += 0.05
            }
            let top = points.first?.1 ?? 0
            let fit = points.filter { $0.1 > top - 40 }
            let n = Double(fit.count)
            let sx = fit.reduce(0) { $0 + $1.0 }, sy = fit.reduce(0) { $0 + $1.1 }
            let sxx = fit.reduce(0) { $0 + $1.0 * $1.0 }, sxy = fit.reduce(0) { $0 + $1.0 * $1.1 }
            let slope = (n * sxy - sx * sy) / (n * sxx - sx * sx)
            let t60 = -60 / slope
            pinned("the loop filter's loss at the fundamental is not compensated, so a high note rings a fraction of its decay (measured 2026-10-11)", when: midi > 80) {
                #expect(abs(t60 / string.decay - 1) < 0.15, "MIDI \(midi) rings for \(t60) s where decay is \(string.decay)")
            }
        }
    }

    /// A bowed string's `decay` is how long it would ring if the bow were
    /// lifted, so once the pressure is taken away the string keeps most of its
    /// sound for the first 60 ms (a 2.2 s decay loses 1.6 dB in that time).
    ///
    /// Measured 2026-10-11 and filed: at pressure 0 the bow is parked on the
    /// string rather than lifted, so the junction keeps its grip and mutes the
    /// string in about 60 ms (-25 dB at 40 to 60 ms after the lift at decay 2.2,
    /// -20 dB at decay 8), and what is left rings at the bridge segment's own
    /// pitch, about six times the note.
    @Test func aLiftedBowLetsTheStringRingDown() {
        let spec = BowedString(position: BowedString.cello.position, force: BowedString.cello.force,
                               decay: 2.2, damping: BowedString.cello.damping)
        let s = renderLifting(Voice(bowed: spec, gain: 1), midi: 48, seconds: 2.0, drive: 0.8, liftAt: 1.0)
        let before = rms(s[Int(0.9 * Self.sampleRate)..<Int(1.0 * Self.sampleRate)])
        let after = rms(s[Int(1.04 * Self.sampleRate)..<Int(1.06 * Self.sampleRate)])
        let fell = 20 * log10(after / before)
        pinned("a bow at pressure 0 is parked, not lifted, and mutes the string in 60 ms (measured 2026-10-11)") {
            #expect(fell > -6, "the string fell \(fell) dB in the 60 ms after the bow was lifted")
        }
    }

    /// A tube blown at half pressure speaks: `pressure` is a dial from nothing
    /// to full, and the sweep the docs show (0.3 to 0.8) is meant to swell a
    /// note, not to gate it.
    ///
    /// Measured 2026-10-11 and filed: the clarinet speaks from about 0.6 and
    /// the hollow tube from 0.7 (the reedy one from 0.4).
    @Test(arguments: [("clarinet", Voice(blown: .clarinet, gain: 0.6)), ("reedy", Voice(blown: .reedy, gain: 0.6)),
                      ("hollow", Voice(blown: .hollow, gain: 0.6))])
    func aBlownTubeSpeaksAtHalfPressure(name: String, voice: Voice) {
        let s = render(voice, midi: 57, seconds: 1.0, velocity: 0.9, drive: 0.5)
        let slice = s[Int(0.4 * Self.sampleRate)...]
        let f0 = magnitude(slice, hz: hertz(57)) / (Double(slice.count) / 2)
        pinned("the clarinet and hollow tubes do not speak below pressure 0.6 to 0.7 (measured 2026-10-11)", when: name != "reedy") {
            #expect(f0 > 0.05, "\(name) at pressure 0.5 has a fundamental of \(f0)")
        }
    }

    /// Whatever the pressure, a blown tube's output has no standing offset: a
    /// reed pushed shut and held makes no sound, and a speaking one swings
    /// about zero.
    ///
    /// Measured 2026-10-11 and filed: the tube holds a DC offset that shrinks
    /// with pressure and never quite goes (the clarinet -0.13 at 0.5, where it
    /// does not speak, -0.05 at 0.8 and -0.01 at 1.0 where it does; the hollow
    /// tube -0.17 and -0.13), which eats headroom in a mix and thumps when the
    /// pressure steps.
    @Test(arguments: [("clarinet", Voice(blown: .clarinet, gain: 0.6)), ("reedy", Voice(blown: .reedy, gain: 0.6)),
                      ("hollow", Voice(blown: .hollow, gain: 0.6))])
    func aBlownTubeHoldsNoOffset(name: String, voice: Voice) {
        for pressure in [0.5, 0.8] {
            let s = render(voice, midi: 57, seconds: 1.0, velocity: 0.9, drive: pressure)
            let slice = s[Int(0.4 * Self.sampleRate)...]
            let mean = slice.reduce(0.0) { $0 + Double($1) } / Double(slice.count)
            pinned("a blown tube holds a DC offset at every pressure under full (measured 2026-10-11)") {
                #expect(abs(mean) < 0.01, "\(name) at pressure \(pressure) holds an offset of \(mean)")
            }
        }
    }

    // MARK: Survey B: the chain and the export

    /// A note through the chain, in the export, with a custom first effect that
    /// replaces the synth's sound with the test signal.
    @MainActor
    private func exported(effects: [Effect], seconds: Double) -> [Float] {
        let synth = Synth(.bell)
        synth.effects = effects
        var out: [Float] = []
        exporting {
            var elapsed = 0.0
            while elapsed < seconds {
                if elapsed == 0 { synth.play(72, velocity: 0.9, for: 0.3) }
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            out = synth.renderExportAudio(upTo: seconds, sampleRate: Self.sampleRate)
        }
        return out
    }

    /// One sample of 1 at time zero, then nothing.
    private static func impulse() -> Effect {
        .custom("impulse") { block in
            let start = Int((block.time * block.sampleRate).rounded())
            for ch in 0..<block.channelCount {
                let b = block[ch]
                for i in 0..<block.frameCount { b[i] = (start + i) == 0 ? 1 : 0 }
            }
        }
    }

    private func leftChannel(_ stereo: [Float]) -> [Float] {
        stride(from: 0, to: stereo.count, by: 2).map { stereo[$0] }
    }

    /// Four rooms are four rooms: the same note through `.room` and through
    /// `.cathedral` cannot be the same samples.
    ///
    /// Measured 2026-10-11 and filed: in an export the four built-in rooms
    /// render byte for byte alike (a click through each has the same 1.41 s
    /// decay and the same peak), so choosing one changes nothing in the file.
    /// The preset is loaded before the engine enters its offline mode, which
    /// is read as the moment it is lost.
    @MainActor
    @Test func theBuiltInRoomsAreFourRooms() {
        let room = exported(effects: [Self.impulse(), .reverb(Reverb(.room, mix: 1))], seconds: 2)
        let cathedral = exported(effects: [Self.impulse(), .reverb(Reverb(.cathedral, mix: 1))], seconds: 2)
        var differ = 0.0
        for i in 0..<min(room.count, cathedral.count) { differ = max(differ, Double(abs(room[i] - cathedral[i]))) }
        pinned("the four built-in rooms export as one room (measured 2026-10-11)") {
            #expect(differ > 0.01, "a room and a cathedral rendered the same samples")
        }
    }

    /// A delay waits as long as it was asked: an echo asked for at 3 s arrives
    /// at 3 s, as one asked for at 1.5 s arrives at 1.5 s.
    ///
    /// Measured 2026-10-11 and filed: the unit under the delay takes at most
    /// 2 s, and `Delay.time` is handed over unclamped and undocumented, so a
    /// time of 3 s echoes at 2.000 s.
    @MainActor
    @Test func aDelayWaitsAsLongAsItWasAsked() {
        func echo(after time: Double) -> Double {
            let out = leftChannel(exported(effects: [Self.impulse(), .delay(Delay(time: time, feedback: 0, mix: 1, damping: 20000))], seconds: time + 1))
            var at = 0, best = 0.0
            for i in 200..<out.count where Double(abs(out[i])) > best { best = Double(abs(out[i])); at = i }
            return Double(at) / Self.sampleRate
        }
        #expect(abs(echo(after: 1.5) - 1.5) < 0.002)
        pinned("a delay past 2 s is capped at 2 s by the unit (measured 2026-10-11)") {
            let at = echo(after: 3)
            #expect(abs(at - 3) < 0.002, "an echo asked for at 3 s arrived at \(at) s")
        }
    }

    /// A limiter holds a ceiling without flattening the wave: a 0 dBFS sine
    /// through a -6 dB ceiling comes out a sine 6 dB down, not a flat-topped
    /// one, so its distortion stays under a third of a percent and no stretch
    /// of samples sits exactly on the ceiling.
    ///
    /// Measured 2026-10-11 and filed: the limiter has no lookahead and
    /// applies its gain on the sample that asked for it, so every crest over
    /// the ceiling is flattened to it: 1.2% THD and 10% of the samples on the
    /// ceiling. The doc page says it ducks "rather than tearing".
    @Test func theLimiterLimitsWithoutClipping() {
        let x = (0..<Int(0.5 * Self.sampleRate)).map { Float(sin(2 * .pi * 220 * Double($0) / Self.sampleRate)) }
        let effect = DynamicsEffect(.limiter(Limiter(ceiling: -6, release: 0.05)), sampleRate: Self.sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var y = [Float]()
        var position = 0
        while position < x.count {
            let count = min(512, x.count - position)
            buffer.frameLength = AVAudioFrameCount(count)
            let data = buffer.floatChannelData!
            for i in 0..<count { data[0][i] = x[position + i]; data[1][i] = x[position + i] }
            let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            effect.process(AudioBlock(list: list, frameCount: count, sampleRate: Self.sampleRate,
                                      time: Double(position) / Self.sampleRate))
            y += Array(UnsafeBufferPointer(start: data[0], count: count))
            position += count
        }
        let tail = y[Int(0.3 * Self.sampleRate)...]
        let ceiling = Float(pow(10, -6.0 / 20))
        let onTheCeiling = Double(tail.filter { abs(abs($0) - ceiling) < 1e-5 }.count) / Double(tail.count)
        let f = magnitude(tail, hz: 220)
        var harmonics = 0.0
        for h in 2...9 { let m = magnitude(tail, hz: 220 * Double(h)); harmonics += m * m }
        let thd = harmonics.squareRoot() / f
        pinned("the limiter flattens every crest over its ceiling (measured 2026-10-11)") {
            #expect(thd < 0.003, "THD \(thd * 100)% through the limiter")
            #expect(onTheCeiling < 0.01, "\(onTheCeiling * 100)% of the samples sat exactly on the ceiling")
        }
    }

    /// An effect at the setting that asks for none of it passes the sound
    /// unchanged, sample for sample.
    ///
    /// Measured 2026-10-11: the delay, the built-in room, the equalizer, and
    /// the convolution hold to the byte; the distortion at mix 0 moves a bell
    /// by 0.027 of 0.38 (filed).
    @MainActor
    @Test(arguments: [("delay at mix 0", Effect.delay(Delay(mix: 0))),
                      ("room at mix 0", .reverb(Reverb(.hall, mix: 0))),
                      ("flat equalizer", .equalizer(Equalizer())),
                      ("convolution at mix 0", .reverb(Reverb(ImpulseResponse.decay(seconds: 0.1, sampleRate: 44100), mix: 0))),
                      ("distortion at mix 0", .distortion(Distortion(mix: 0)))])
    func aNeutralEffectPassesTheSoundUnchanged(name: String, effect: Effect) {
        let dry = exported(effects: [], seconds: 1)
        let wet = exported(effects: [effect], seconds: 1)
        #expect(wet.count == dry.count)
        var moved = 0.0
        for i in 0..<min(dry.count, wet.count) { moved = max(moved, Double(abs(wet[i] - dry[i]))) }
        pinned("the distortion unit at mix 0 is not the identity (measured 2026-10-11)", when: name.hasPrefix("distortion")) {
            #expect(moved < 1e-6, "\(name) moved a sample by \(moved)")
        }
    }

    /// A sketch holding its instruments inside a struct, an array, or an
    /// optional still exports them: the finder reads what the sketch holds,
    /// not only what it holds directly.
    ///
    /// Measured 2026-10-11 and filed: only a direct stored property or an
    /// optional is found; three synths inside structs in an array and one in a
    /// bare array are not, so the Spatial example's three chimes are missing
    /// from its own exported soundtrack.
    final class NestedInstruments: Sketch {
        struct Post { let synth: Synth }
        var posts: [Post] = []
        var walker: Synth!
        var inArray: [Synth] = []
        var optional: Synth?
        override var canvasSize: CanvasSize { .square(16) }
        override func setup() {
            posts = [Post(synth: Synth(.bell)), Post(synth: Synth(.bell)), Post(synth: Synth(.bell))]
            walker = Synth(.bell)
            inArray = [Synth(.bell)]
            optional = Synth(.bell)
        }
        override func draw() {}
    }

    @MainActor
    @Test func anInstrumentInsideAnArrayReachesTheExport() {
        let sketch = NestedInstruments()
        sketch.runSetup()
        let found = sketch.exportAudioSources().count
        pinned("instruments inside an array or a struct are not found by the export (measured 2026-10-11)") {
            #expect(found == 6, "found \(found) of the sketch's 6 instruments")
        }
    }

    /// A note asked for on a frame starts on that frame's first sample: the
    /// exporter advances the sketch and then draws it, and the note the draw
    /// asks for belongs to the time the frame is stamped with.
    ///
    /// Measured 2026-10-11 and filed: the export clock is advanced before the
    /// draw, so a note asked for on frame 0 starts at sample 736 (one frame at
    /// 60 fps) while the picture is stamped at 0; every note lands one frame
    /// late, 42 ms at 24 fps.
    final class PlaysOnFirstDraw: Sketch {
        var synth: Synth!
        var played = false
        override var canvasSize: CanvasSize { .square(16) }
        override func setup() { synth = Synth(.bell) }
        override func draw() {
            if !played { played = true; synth.play(72, velocity: 0.9, for: 0.5) }
        }
    }

    @MainActor
    @Test func aNoteAskedForOnAFrameStartsOnThatFrame() {
        var onset = -1
        exporting {
            let sketch = PlaysOnFirstDraw()
            sketch.runSetup()
            // The exporter's own order: advance, then draw.
            sketch.advance(time: 0, deltaTime: 1.0 / 60, frameRate: 60)
            sketch.performDraw()
            let s = sketch.synth.renderExportAudio(upTo: 1, sampleRate: Self.sampleRate)
            onset = s.firstIndex { abs($0) > 1e-4 }.map { $0 / 2 } ?? -1
        }
        pinned("a note lands one frame late in an export (measured 2026-10-11)") {
            #expect(onset >= 0 && onset < 32, "the frame-0 note starts at sample \(onset)")
        }
    }

    /// A change of `hearingDistance` while an export runs is heard: a note
    /// placed 12 units away after the range was widened to start at 0.2 is
    /// five times quieter than one under the default range starting at 1.
    ///
    /// Measured 2026-10-11 and filed: the offline machine reads the range once
    /// when it is built, after the first frame, so a range set later (by a
    /// parameter, a cue, or the Spatial example's own slider) is ignored in
    /// the file while the live window honors it at once.
    @MainActor
    @Test func aHearingDistanceChangedMidExportIsHeard() {
        func secondNoteLevel(changing: Bool) -> Double {
            let synth = Synth(.bell)
            synth.hearingDistance = changing ? 1...50 : 0.2...50
            var samples: [Float] = []
            exporting {
                var frame = 0
                while frame < 90 {
                    if changing && frame == 30 { synth.hearingDistance = 0.2...50 }
                    synth.place(at: Vector3(0, 0, -12), heardFrom: Self.listener())
                    if frame == 0 { synth.play(72, velocity: 0.9, for: 0.3) }
                    if frame == 45 { synth.play(72, velocity: 0.9, for: 0.5) }
                    synth.advance(by: 1.0 / 60)
                    if frame == 0 { _ = synth.renderExportAudio(upTo: 1.0 / 60, sampleRate: Self.sampleRate) }
                    frame += 1
                }
                samples = synth.renderExportAudio(upTo: 1.5, sampleRate: Self.sampleRate)
            }
            let start = Int(0.8 * Self.sampleRate), end = Int(1.4 * Self.sampleRate)
            var acc = 0.0
            for f in start..<end { let v = Double(samples[f * 2]); acc += v * v }
            return (acc / Double(end - start)).squareRoot()
        }
        let changed = secondNoteLevel(changing: true), fromTheStart = secondNoteLevel(changing: false)
        pinned("a hearing range changed after the first frame does not reach the export (measured 2026-10-11)") {
            #expect(abs(changed / fromTheStart - 1) < 0.05, "the changed range played the note at \(changed / fromTheStart) of the range set from the start")
        }
    }

    /// Taking a sound out of space puts it back where it started: as loud as
    /// one that was never placed, in both ears.
    ///
    /// Measured 2026-10-11 and filed: `unplace()` moves the source to the
    /// listener's own position, where the offline pan plays it at half level
    /// in each ear (0.50 of never placed; a source one unit ahead plays at
    /// 0.71), so an instrument placed once and unplaced is 6 dB down for the
    /// rest of the piece.
    @MainActor
    @Test func anUnplacedSoundIsHeardAtFullLevel() {
        let never = placed(at: nil)
        let synth = Synth(.bell)
        synth.hearingDistance = 1...50
        var unplaced: [Float] = []
        exporting {
            var frame = 0
            while frame < 90 {
                if frame == 0 { synth.place(at: Vector3(0, 0, -8), heardFrom: Self.listener()) } else { synth.unplace() }
                if frame == 0 { synth.play(72, velocity: 0.9, for: 1.0) }
                synth.advance(by: 1.0 / 60)
                frame += 1
            }
            unplaced = synth.renderExportAudio(upTo: 1.5, sampleRate: Self.sampleRate)
        }
        let ratio = level(unplaced, channel: 0) / level(never, channel: 0)
        pinned("an unplaced sound plays at half level (measured 2026-10-11)") {
            #expect(abs(ratio - 1) < 0.05, "unplaced plays at \(ratio) of never placed")
        }
    }
}
