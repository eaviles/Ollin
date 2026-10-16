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
    func aPluckedStringOnlyEverLosesEnergy(string: PluckedString)  throws {
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
    func aStruckBodyOnlyEverLosesEnergy(body: ModalBody)  throws {
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
    func aDrivenBodyStaysBoundedAtAnyDrive(drive: Double, midi: Double)  throws {
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
    private func exporting(_ body: () throws -> Void) rethrows {
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        try body()
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
    @Test func aMirroredPlaceSwapsTheEars() throws {
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
    func placingNeverAmplifies(distance: Double)  throws {
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
    func aPluckedStringSoundsItsNote(string: PluckedString)  throws {
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
            pinned("the reedy and clarinet tubes leave their register at the top of the range: at MIDI 93 a tube speaks and jumps toward its twelfth within a tenth of breath of each other, so at pressure 0.8 the fundamental is a weak line read 6 to 14 cents flat (measured 2026-10-15)",
                   when: (name == "reedy" || name == "clarinet") && midi == 93) {
                #expect(abs(off) <= 5, "\(name) at MIDI \(midi) sounds \(off) cents off")
            }
        }
    }

    /// A shape struck is a membrane of that shape: a disc rings at the Bessel
    /// zeros a circular membrane does, in order and in ratio.
    @Test func aStruckDiscRingsAtAMembranesModes() throws {
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
    /// The strike's push is a raised cosine whose length grows as the hardness
    /// falls, divided by its own area, so a softer strike reaches fewer tones
    /// rather than pushing the same tones harder. Before that division every
    /// preset but `.wood` drove the renderer's soft clip at its attack (the bell
    /// sat above 0.95 for 56% of its first second, glass 92%, the drum 6%) and
    /// the clip's intermodulation put lines at 1.4 and 3.4 times the note 7 dB
    /// under the bell's prime.
    @Test(arguments: [("bell", ModalBody.bell), ("glass", .glass), ("drum", .drum), ("wood", .wood),
                      ("bar", .bar), ("plate", .plate)])
    func aStruckBodyIsASumOfTones(name: String, body: ModalBody) {
        let s = render(Voice(struck: body, envelope: Self.flat, gain: 1), midi: 60, seconds: 1.5, velocity: 0.9)
        let first = s[0..<Int(1.0 * Self.sampleRate)]
        let onTheCeiling = Double(first.filter { abs($0) > 0.95 }.count) / Double(first.count)
        #expect(onTheCeiling < 0.01, "\(name) sat on the ceiling \(onTheCeiling * 100)% of its first second")
        if name == "bell" {
            let slice = s[Int(0.1 * Self.sampleRate)..<Int(0.6 * Self.sampleRate)]
            let prime = magnitude(slice, hz: 2 * 261.63)
            let foreign = max(magnitude(slice, hz: 1.4 * 261.63), magnitude(slice, hz: 3.4 * 261.63))
            #expect(20 * log10(foreign / prime) < -40, "a line \(20 * log10(foreign / prime)) dB under the prime at a frequency the bell has no partial at")
        }
    }

    /// `hardness` is the color of a strike and not its level: a soft mallet
    /// reaches fewer of the tones, so the sound is darker, and it is never
    /// louder than a hard one. And a strike is a length of time, so it is as
    /// loud at 48 kHz as at 44.1, where a push counted in samples was 9%
    /// louder at the higher rate.
    @Test(arguments: [("bell", ModalBody.bell), ("glass", .glass), ("drum", .drum), ("bar", .bar), ("plate", .plate)])
    func aSofterStrikeIsDarkerAndNeverLouder(name: String, body: ModalBody)  throws {
        func peak(_ s: [Float]) -> Double { Double(s.map { abs($0) }.max() ?? 0) }
        func brightness(_ s: [Float]) -> Double {
            // The highest partial against the first, over the attack.
            let slice = s[0..<Int(0.2 * Self.sampleRate)]
            let modes = body.modes
            let low = magnitude(slice, hz: 261.63 * modes[0].ratio)
            let high = magnitude(slice, hz: 261.63 * modes[modes.count - 1].ratio)
            return high / low
        }
        var soft = body, hard = body
        soft.hardness = 0.2
        hard.hardness = 1.0
        let softly = render(Voice(struck: soft, envelope: Self.flat, gain: 1), midi: 60, seconds: 0.5, velocity: 0.9)
        let hardly = render(Voice(struck: hard, envelope: Self.flat, gain: 1), midi: 60, seconds: 0.5, velocity: 0.9)
        #expect(peak(softly) <= peak(hardly) * 1.02,
                "\(name) struck softly peaked at \(peak(softly)) against \(peak(hardly)) struck hard")
        #expect(brightness(softly) < brightness(hardly) * 0.5,
                "\(name) struck softly kept \(brightness(softly) / brightness(hardly)) of the hard strike's top partial")

        // The same note at two sample rates, read over the first tenth of a
        // second so the fade compares like with like.
        func level(at rate: Double) -> Double {
            let events = EventRing()
            let renderer = SynthRenderer(voice: Voice(struck: body, envelope: Self.flat, gain: 1),
                                         polyphony: 4, sampleRate: rate, events: events, seed: 5)
            renderer.gain = 1
            events.push(SynthEvent(kind: .noteOn, pitch: 60, velocity: 0.9))
            let count = Int(0.1 * rate)
            var samples = [Float](repeating: 0, count: count)
            samples.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: count) }
            return rms(samples[0..<count])
        }
        let ratio = level(at: 48000) / level(at: 44100)
        #expect(abs(ratio - 1) < 0.03, "\(name) played at \(ratio) of its level when rendered at 48 kHz")
    }

    /// How long the fundamental of `samples` takes to fall 60 dB, from a line
    /// fit to its level in 50 ms windows over the first 40 dB of its fall.
    private func ringTime(_ samples: ArraySlice<Float>, hz: Double) -> Double {
        var points: [(Double, Double)] = []
        var t = 0.05
        let start = samples.startIndex
        while Int(t * Self.sampleRate) + Int(0.05 * Self.sampleRate) <= samples.count {
            let a = start + Int(t * Self.sampleRate), b = a + Int(0.05 * Self.sampleRate)
            let m = magnitude(samples[a..<b], hz: hz)
            if m > 1e-3 { points.append((t, 20 * log10(m))) }
            t += 0.05
        }
        let top = points.first?.1 ?? 0
        let fit = points.filter { $0.1 > top - 40 }
        let n = Double(fit.count)
        let sx = fit.reduce(0) { $0 + $1.0 }, sy = fit.reduce(0) { $0 + $1.1 }
        let sxx = fit.reduce(0) { $0 + $1.0 * $1.0 }, sxy = fit.reduce(0) { $0 + $1.0 * $1.1 }
        let slope = (n * sxy - sx * sy) / (n * sxx - sx * sx)
        return -60 / slope
    }

    /// `decay` is how long the note takes to fade at the note being played, so
    /// the fundamental's T60 is `decay` at every pitch, within a tenth.
    ///
    /// Until 2026-10-15 the loop gain was set as if the loop filter were
    /// lossless at the fundamental, so the steel string's 3.6 s was 3.6 s at
    /// MIDI 45 and 0.64 s at MIDI 93 (nylon's 1.8 s became 0.42 s).
    @Test(arguments: [PluckedString.steel, .nylon, .harp])
    func aPluckedStringRingsForItsDecayAtEveryPitch(string: PluckedString)  throws {
        for midi in [33.0, 45, 57, 69, 81, 93] {
            let seconds = min(5.0, string.decay * 1.1 + 0.2)
            let s = render(Voice(plucked: string, envelope: Self.flat, gain: 1), midi: midi, seconds: seconds)
            let t60 = ringTime(s[...], hz: hertz(midi))
            #expect(abs(t60 / string.decay - 1) < 0.1, "MIDI \(midi) rings for \(t60) s where decay is \(string.decay)")
        }
    }

    /// A bowed string's `decay` is how long it would ring if the bow were
    /// lifted, so once the pressure is taken away the string keeps most of its
    /// sound for the first 60 ms (a 2.2 s decay loses 1.6 dB in that time),
    /// sounds its note, and rings down over its decay, at every pitch.
    ///
    /// Until 2026-10-15 the bow at pressure 0 was parked on the string rather
    /// than lifted: the junction kept its grip and muted the string in about
    /// 60 ms (-25 dB at 40 to 60 ms after the lift at decay 2.2), and the loss
    /// was taken on both sides of the bow, so a lifted string would have rung
    /// half its decay.
    @Test(arguments: [("violin", BowedString.violin), ("cello", BowedString.cello)])
    func aLiftedBowLetsTheStringRingDown(name: String, preset: BowedString) throws {
        let spec = BowedString(position: preset.position, force: preset.force, decay: 2.2, damping: preset.damping)
        for midi in [48.0, 69, 81] {
            let s = renderLifting(Voice(bowed: spec, gain: 1), midi: midi, seconds: 3.6, drive: 0.8, liftAt: 1.0)
            let before = rms(s[Int(0.9 * Self.sampleRate)..<Int(1.0 * Self.sampleRate)])
            let after = rms(s[Int(1.04 * Self.sampleRate)..<Int(1.06 * Self.sampleRate)])
            let fell = 20 * log10(after / before)
            #expect(fell > -6, "\(name) at MIDI \(midi) fell \(fell) dB in the 60 ms after the bow was lifted")
            let ringing = s[Int(1.0 * Self.sampleRate)...]
            let f = peak(ringing.prefix(Int(0.5 * Self.sampleRate)), near: hertz(midi))
            #expect(abs(cents(f, hertz(midi))) < 10, "\(name) at MIDI \(midi) rang at \(f) Hz once lifted")
            let t60 = ringTime(ringing, hz: hertz(midi))
            #expect(abs(t60 / spec.decay - 1) < 0.1, "\(name) at MIDI \(midi) rang for \(t60) s where decay is 2.2")
        }
    }

    /// Every tube starts to sound at the same point of the dial, whatever its
    /// pitch or its reed: silent at 0.25, speaking at 0.5. `pressure` is a dial
    /// from nothing to full, and the sweep the docs show (0.3 to 0.8) is meant
    /// to swell a note, not to gate it.
    ///
    /// Until 2026-10-15 the breath was the dial times a constant, and where a
    /// note starts moves with how much its bore loses, so the clarinet spoke
    /// from about 0.6 at MIDI 57, the hollow tube from 0.7, and every tube
    /// later on a low note than on a high one.
    @Test(arguments: [("clarinet", Voice(blown: .clarinet, gain: 0.6)), ("reedy", Voice(blown: .reedy, gain: 0.6)),
                      ("hollow", Voice(blown: .hollow, gain: 0.6))])
    func aBlownTubeSpeaksFromTheSamePressureAtEveryPitch(name: String, voice: Voice) {
        func fundamental(midi: Double, pressure: Double) -> Double {
            let s = render(voice, midi: midi, seconds: 1.0, velocity: 0.9, drive: pressure)
            let slice = s[Int(0.5 * Self.sampleRate)...]
            return magnitude(slice, hz: hertz(midi)) / (Double(slice.count) / 2)
        }
        for midi in [45.0, 57, 69] {
            let quiet = fundamental(midi: midi, pressure: 0.25)
            #expect(quiet < 0.005, "\(name) at MIDI \(midi) sounds \(quiet) at pressure 0.25")
            let speaking = fundamental(midi: midi, pressure: 0.5)
            #expect(speaking > 0.05, "\(name) at MIDI \(midi) has a fundamental of \(speaking) at pressure 0.5")
        }
    }

    /// Whatever the pressure, a blown tube's output has no standing offset: a
    /// reed pushed shut and held makes no sound, and a speaking one swings
    /// about zero.
    ///
    /// Until 2026-10-15 the tube held a DC offset that shrank with pressure
    /// and never quite went (the clarinet -0.13 at 0.5, -0.05 at 0.8 and -0.01
    /// at 1.0; the hollow tube -0.17 and -0.13), which ate headroom in a mix
    /// and thumped when the pressure stepped.
    @Test(arguments: [("clarinet", Voice(blown: .clarinet, gain: 0.6)), ("reedy", Voice(blown: .reedy, gain: 0.6)),
                      ("hollow", Voice(blown: .hollow, gain: 0.6))])
    func aBlownTubeHoldsNoOffset(name: String, voice: Voice) {
        for pressure in [0.2, 0.5, 0.8, 1.0] {
            let s = render(voice, midi: 57, seconds: 1.0, velocity: 0.9, drive: pressure)
            let slice = s[Int(0.4 * Self.sampleRate)...]
            let mean = slice.reduce(0.0) { $0 + Double($1) } / Double(slice.count)
            #expect(abs(mean) < 0.005, "\(name) at pressure \(pressure) holds an offset of \(mean)")
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

    /// Four rooms are four rooms: the same click through any two of the
    /// built-in rooms cannot be the same samples.
    ///
    /// Until 2026-10-15 the four rendered byte for byte alike (a click through
    /// each had the same 1.41 s decay and the same peak): the room was loaded
    /// with `loadFactoryPreset`, which on macOS 27 names the preset and leaves
    /// every setting at the unit's default room, live and in an export alike.
    @MainActor
    @Test func theBuiltInRoomsAreFourRooms() throws {
        let rooms = Reverb.Space.allCases.map { space in
            (space, exported(effects: [Self.impulse(), .reverb(Reverb(space, mix: 1))], seconds: 2))
        }
        for (a, first) in rooms.enumerated() {
            for second in rooms.dropFirst(a + 1) {
                var differ = 0.0
                for i in 0..<min(first.1.count, second.1.count) {
                    differ = max(differ, Double(abs(first.1[i] - second.1[i])))
                }
                #expect(differ > 0.01, "\(first.0) and \(second.0) rendered the same samples")
            }
        }
    }

    /// A delay waits as long as its `time` says: an echo at 1.5 s arrives at
    /// 1.5 s and one at 2 s at 2 s, and a time past the longest the echo can
    /// wait reads back as that longest, so what it says is what is heard.
    ///
    /// Until 2026-10-15 `Delay.time` kept whatever it was given while the unit
    /// under it held 2 s, so a time of 3 s read back as 3 and echoed at 2.000 s.
    @MainActor
    @Test func aDelayWaitsAsLongAsItsTimeSays() throws {
        func echo(_ delay: Delay) -> Double {
            let out = leftChannel(exported(effects: [Self.impulse(), .delay(delay)], seconds: delay.time + 1))
            var at = 0, best = 0.0
            for i in 200..<out.count where Double(abs(out[i])) > best { best = Double(abs(out[i])); at = i }
            return Double(at) / Self.sampleRate
        }
        for time in [1.5, 2.0, 3.0] {
            let delay = Delay(time: time, feedback: 0, mix: 1, damping: 20000)
            #expect(delay.time == min(time, Delay.maxTime))
            let at = echo(delay)
            #expect(abs(at - delay.time) < 0.002, "an echo at \(delay.time) s arrived at \(at) s")
        }
    }

    /// `x` through a limiter in blocks of 512, the left channel back.
    private func limited(_ x: [Float], _ limiter: Limiter) -> [Float] {
        let effect = DynamicsEffect(.limiter(limiter), sampleRate: Self.sampleRate)
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
        return y
    }

    /// A limiter holds a ceiling without flattening the wave: a 0 dBFS sine
    /// through a -6 dB ceiling comes out a sine 6 dB down, not a flat-topped
    /// one, so its distortion stays under a third of a percent and no stretch
    /// of samples sits exactly on the ceiling.
    ///
    /// Until 2026-10-15 the limiter had no lookahead and applied its gain on
    /// the sample that asked for it, so every crest over the ceiling was
    /// flattened to it: 1.2% THD and 10% of the samples on the ceiling.
    @Test func theLimiterLimitsWithoutClipping() throws {
        let x = (0..<Int(0.5 * Self.sampleRate)).map { Float(sin(2 * .pi * 220 * Double($0) / Self.sampleRate)) }
        let y = limited(x, Limiter(ceiling: -6, release: 0.05))
        let tail = y[Int(0.3 * Self.sampleRate)...]
        let ceiling = Float(pow(10, -6.0 / 20))
        let onTheCeiling = Double(tail.filter { abs(abs($0) - ceiling) < 1e-5 }.count) / Double(tail.count)
        let f = magnitude(tail, hz: 220)
        var harmonics = 0.0
        for h in 2...9 { let m = magnitude(tail, hz: 220 * Double(h)); harmonics += m * m }
        let thd = harmonics.squareRoot() / f
        #expect(thd < 0.003, "THD \(thd * 100)% through the limiter")
        #expect(onTheCeiling < 0.01, "\(onTheCeiling * 100)% of the samples sat exactly on the ceiling")
    }

    /// Nothing leaves a limiter over its ceiling, whatever arrives: bursts of
    /// noise up to 24 dB over it, a lone spike, and a step from silence to
    /// full scale. And below the ceiling the sound passes untouched, later by
    /// `Limiter.lookahead`, which is what the listening ahead costs.
    @Test func aLimitersCeilingHoldsAndItsDelayIsItsLookahead() throws {
        var state: UInt64 = 7
        func noise() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Double(state >> 11) / Double(1 << 53) * 2 - 1)
        }
        let n = Int(1.0 * Self.sampleRate)
        var x = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let burst = (i / 2205) % 3 == 0 ? Float(8) : 0.05
            x[i] = noise() * burst
        }
        x[n / 2] = 16
        for i in (3 * n / 4)..<n { x[i] = 1 }
        for ceiling in [-12.0, -6, -0.5] {
            let y = limited(x, Limiter(ceiling: ceiling, release: 0.02))
            let most = y.map { abs($0) }.max() ?? 0
            #expect(Double(most) <= pow(10, ceiling / 20) * (1 + 1e-6), "ceiling \(ceiling) dB let \(most) through")
        }

        let quiet = (0..<4096).map { Float(0.25 * sin(2 * .pi * 330 * Double($0) / Self.sampleRate)) }
        let passed = limited(quiet, Limiter(ceiling: -6))
        let lag = Int((Limiter.lookahead * Self.sampleRate).rounded())
        var moved: Float = 0
        for i in lag..<quiet.count { moved = max(moved, abs(passed[i] - quiet[i - lag])) }
        #expect(moved < 1e-6, "a sound under the ceiling moved by \(moved) besides its delay of \(lag) samples")
        #expect(passed[0..<lag].allSatisfy { $0 == 0 })
    }

    /// An effect at the setting that asks for none of it passes the sound
    /// unchanged, sample for sample.
    ///
    /// Measured 2026-10-11: the delay, the built-in room, the equalizer, and
    /// the convolution held to the byte, and the distortion at mix 0 moved a
    /// bell by 0.027 of 0.38, until 2026-10-15, when it began to step aside at
    /// mix 0 the way a flat equalizer does.
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
        #expect(moved < 1e-6, "\(name) moved a sample by \(moved)")
    }

    /// A sketch holding its instruments inside a struct, an array, an
    /// optional, a dictionary, or an object of its own still exports them:
    /// the finder reads what the sketch holds, not only what it holds
    /// directly, and an instrument held twice is one instrument.
    ///
    /// Until 2026-10-11 only a direct stored property or an optional was
    /// found; three synths inside structs in an array and one in a bare array
    /// were not, so the Spatial example's three chimes were missing from its
    /// own exported soundtrack.
    final class NestedInstruments: Sketch {
        struct Post { let synth: Synth }
        @MainActor final class Band {
            let drums: Synth
            init() { drums = Synth(.drum) }
        }
        var posts: [Post] = []
        var walker: Synth!
        var inArray: [Synth] = []
        var optional: Synth?
        var byName: [String: Synth] = [:]
        var band: Band!
        var twice: Synth?
        /// A great many plain values beside them, which the finder must not
        /// read one by one.
        var points: [Vector2] = []
        override var canvasSize: CanvasSize { .square(16) }
        override func setup() {
            posts = [Post(synth: Synth(.bell)), Post(synth: Synth(.bell)), Post(synth: Synth(.bell))]
            walker = Synth(.bell)
            inArray = [Synth(.bell)]
            optional = Synth(.bell)
            byName = ["lead": Synth(.pluck)]
            band = Band()
            twice = walker
            points = (0..<1_000_000).map { Vector2(Double($0), 0) }
        }
        override func draw() {}
    }

    @MainActor
    @Test func anInstrumentInsideAnArrayReachesTheExport() throws {
        let sketch = NestedInstruments()
        try sketch.runSetup()
        let started = Date()
        let found = sketch.exportAudioSources()
        let took = Date().timeIntervalSince(started)
        #expect(found.count == 8, "found \(found.count) of the sketch's 8 instruments")
        // The three direct ones come first, in the order the sketch declares
        // them, so a sketch with two instruments mixes exactly as it did.
        #expect(found.first === sketch.walker)
        #expect(took < 2, "reading the sketch took \(took) s beside a million points")
        // And every one is advanced, so a note it plays on a late frame is
        // written down at that frame and not at zero.
        exporting {
            for frame in 0..<30 {
                sketch.advance(time: Double(frame) / 60, deltaTime: 1.0 / 60, frameRate: 60)
                sketch.performDraw()
            }
            sketch.posts[2].synth.play(72, velocity: 0.9, for: 0.2)
        }
        #expect(abs((sketch.posts[2].synth.recorded.first?.at ?? -1) - 29.0 / 60) < 1e-9,
                "the chime inside the array wrote its note at \(sketch.posts[2].synth.recorded.first?.at ?? -1)")
    }

    /// A note asked for on a frame starts on that frame's first sample: the
    /// exporter advances the sketch and then draws it, and the note the draw
    /// asks for belongs to the time the frame is stamped with, on the first
    /// frame and on every one after it.
    ///
    /// Until 2026-10-11 the export clock was only ever stepped, before the
    /// draw, so a note asked for on frame 0 started at sample 736 (one frame
    /// at 60 fps) while the picture was stamped at 0; every note landed one
    /// frame late, 42 ms at 24 fps.
    final class PlaysOnOneFrame: Sketch {
        var synth: Synth!
        var onFrame = 0
        override var canvasSize: CanvasSize { .square(16) }
        override func setup() { synth = Synth(.bell) }
        override func draw() {
            if frameCount == onFrame + 1 { synth.play(72, velocity: 0.9, for: 0.5) }
        }
    }

    @MainActor
    @Test(arguments: [0, 10])
    func aNoteAskedForOnAFrameStartsOnThatFrame(frame: Int) throws {
        var onset = -1
        try exporting {
            let sketch = PlaysOnOneFrame()
            sketch.onFrame = frame
            try sketch.runSetup()
            // The exporter's own order: advance, then draw, every frame.
            for k in 0...frame {
                sketch.advance(time: Double(k) / 60, deltaTime: 1.0 / 60, frameRate: 60)
                sketch.performDraw()
            }
            let s = sketch.synth.renderExportAudio(upTo: 1, sampleRate: Self.sampleRate)
            onset = s.firstIndex { abs($0) > 1e-4 }.map { $0 / 2 } ?? -1
        }
        let expected = Int(Double(frame) / 60 * Self.sampleRate)
        #expect(onset >= expected && onset < expected + 32,
                "the frame-\(frame) note starts at sample \(onset), where the frame starts at \(expected)")
    }

    /// A change of `hearingDistance` while an export runs is heard from the
    /// frame that made it: a note placed 12 units away after the range was
    /// widened to start at 0.2 is five times quieter than one under the default
    /// range starting at 1, and a note before the change is as it was.
    ///
    /// Until 2026-10-11 the offline machine read the range once when it was
    /// built, after the first frame, so a range set later (by a parameter, a
    /// cue, or the Spatial example's own slider) was ignored in the file while
    /// the live window honored it at once.
    @MainActor
    @Test func aHearingDistanceChangedMidExportIsHeard() throws {
        /// Two notes on a placed instrument, the second after frame 30, with
        /// the range `before` to start with and `after` from frame 30 on.
        func notes(before: ClosedRange<Double>, after: ClosedRange<Double>) -> (first: Double, second: Double) {
            let synth = Synth(.bell)
            synth.hearingDistance = before
            var samples: [Float] = []
            exporting {
                var frame = 0
                while frame < 90 {
                    if frame == 30 { synth.hearingDistance = after }
                    synth.place(at: Vector3(0, 0, -12), heardFrom: Self.listener())
                    if frame == 0 { synth.play(72, velocity: 0.9, for: 0.3) }
                    if frame == 45 { synth.play(72, velocity: 0.9, for: 0.5) }
                    synth.advance(by: 1.0 / 60)
                    // The machine is built after the first frame, as an
                    // export builds it.
                    if frame == 0 { _ = synth.renderExportAudio(upTo: 1.0 / 60, sampleRate: Self.sampleRate) }
                    frame += 1
                }
                samples = synth.renderExportAudio(upTo: 1.5, sampleRate: Self.sampleRate)
            }
            func level(from: Double, to: Double) -> Double {
                let start = Int(from * Self.sampleRate), end = Int(to * Self.sampleRate)
                var acc = 0.0
                for f in start..<end { let v = Double(samples[f * 2]); acc += v * v }
                return (acc / Double(end - start)).squareRoot()
            }
            return (level(from: 0.05, to: 0.35), level(from: 0.8, to: 1.4))
        }
        let near = notes(before: 1...50, after: 1...50)
        let wide = notes(before: 0.2...50, after: 0.2...50)
        let changed = notes(before: 1...50, after: 0.2...50)
        #expect(wide.second < near.second * 0.3, "widening the range to 0.2 left the note at \(wide.second / near.second) of its level")
        #expect(abs(changed.second / wide.second - 1) < 0.05,
                "the range changed at frame 30 played the later note at \(changed.second / wide.second) of the range set from the start")
        #expect(abs(changed.first / near.first - 1) < 0.05,
                "the range changed at frame 30 played the earlier note at \(changed.first / near.first) of what it was before the change")
    }

    /// Taking a sound out of space puts it back where it started: as loud as
    /// one that was never placed, in both ears, and placing it again puts it
    /// back in the scene.
    ///
    /// Until 2026-10-11 `unplace()` moved the source to the listener's own
    /// position, where the pan played it at half level in each ear (0.50 of
    /// never placed; a source one unit ahead plays at 0.71), so an instrument
    /// placed once and unplaced was 6 dB down for the rest of the piece.
    @MainActor
    @Test func anUnplacedSoundIsHeardAtFullLevel() throws {
        let never = placed(at: nil)
        let synth = Synth(.bell)
        synth.hearingDistance = 1...50
        var unplaced: [Float] = []
        exporting {
            var frame = 0
            while frame < 150 {
                switch frame {
                case 0: synth.place(at: Vector3(0, 0, -8), heardFrom: Self.listener())
                case 1..<90: synth.unplace()
                default: synth.place(at: Vector3(-6, 0, -2), heardFrom: Self.listener())
                }
                if frame == 0 { synth.play(72, velocity: 0.9, for: 1.0) }
                if frame == 95 { synth.play(72, velocity: 0.9, for: 1.0) }
                synth.advance(by: 1.0 / 60)
                frame += 1
            }
            unplaced = synth.renderExportAudio(upTo: 2.5, sampleRate: Self.sampleRate)
        }
        for channel in 0...1 {
            let ratio = level(unplaced, channel: channel) / level(never, channel: channel)
            #expect(abs(ratio - 1) < 0.02, "unplaced plays at \(ratio) of never placed in ear \(channel)")
        }
        // Placed again, to the left, the second note is louder in the left ear.
        func later(_ channel: Int) -> Double {
            let start = Int(1.65 * Self.sampleRate), end = Int(2.4 * Self.sampleRate)
            var acc = 0.0
            for f in start..<end { let v = Double(unplaced[f * 2 + channel]); acc += v * v }
            return (acc / Double(end - start)).squareRoot()
        }
        #expect(later(0) > later(1) * 1.5, "placed again to the left, the note reads \(later(0)) left and \(later(1)) right")
    }
}
