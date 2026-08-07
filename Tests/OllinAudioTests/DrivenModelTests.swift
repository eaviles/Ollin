import Foundation
import Testing
@testable import OllinAudio

/// A bow and a breath are different from a pluck and a strike in one way that
/// matters: they keep happening. So most of what is checked here is that a note
/// is still being made in its middle, and that what the player is doing reaches
/// it while it sounds.
///
/// A sound cannot be snapshotted, so every check is a measurement or a twin
/// differing in one setting.
@Suite struct DrivenModelTests {

    static let rate = 44100.0

    /// Renders one note, optionally changing the drive part way through.
    static func render(
        _ voice: Voice, pitch: Double, seconds: Double,
        drive: Double = 0.8, changeTo: (at: Double, drive: Double)? = nil,
        hold: Bool = true
    ) -> [Double] {
        let events = EventRing()
        let renderer = SynthRenderer(voice: voice, polyphony: 4, sampleRate: rate, events: events)
        renderer.gain = 1
        renderer.drive = drive
        events.push(SynthEvent(kind: .noteOn, pitch: pitch, velocity: 0.9,
                               durationSamples: hold ? 0 : Int(seconds * rate)))
        var out = [Double]()
        out.reserveCapacity(Int(seconds * rate) + 512)
        let block = 512
        while out.count < Int(seconds * rate) {
            if let changeTo, Double(out.count) / rate >= changeTo.at,
               renderer.drive != changeTo.drive {
                renderer.drive = changeTo.drive
            }
            var chunk = [Float](repeating: 0, count: block)
            chunk.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: block) }
            out += chunk.map(Double.init)
        }
        return out
    }

    static func rms(_ s: ArraySlice<Double>) -> Double {
        guard !s.isEmpty else { return 0 }
        return (s.reduce(0) { $0 + $1 * $1 } / Double(s.count)).squareRoot()
    }

    static func loudness(_ s: [Double], from: Double, to: Double) -> Double {
        let a = min(max(0, Int(from * rate)), s.count)
        let b = min(max(a, Int(to * rate)), s.count)
        return rms(s[a..<b])
    }

    /// How much energy sits at one frequency, by the single-bin transform.
    static func magnitude(_ s: ArraySlice<Double>, at hz: Double) -> Double {
        let n = s.count
        guard n > 16 else { return 0 }
        let w = 2 * Double.pi * hz / rate
        let c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in s { let s0 = v + c * s1 - s2; s2 = s1; s1 = s0 }
        return (s1 * s1 + s2 * s2 - c * s1 * s2).squareRoot() / Double(n)
    }

    static func harmonics(_ s: [Double], of f0: Double, count: Int = 6,
                          from: Double = 1.0, to: Double = 1.5) -> [Double] {
        let a = min(max(0, Int(from * rate)), s.count)
        let b = min(max(a, Int(to * rate)), s.count)
        let window = s[a..<b]
        let raw = (1...count).map { magnitude(window, at: f0 * Double($0)) }
        let peak = raw.max() ?? 0
        return peak > 1e-12 ? raw.map { $0 / peak } : raw
    }

    static func midi(of hz: Double) -> Double { 69 + 12 * log2(hz / 440) }

    // MARK: - The whole point: a note with a middle

    /// The headline. A plucked string is set going once and is fading by the
    /// time it is a second old; a bowed one is still being made.
    @Test func aDrivenNoteIsStillBeingMadeInTheMiddle() {
        let bowed = Self.render(.cello, pitch: 48, seconds: 2.0)
        let plucked = Self.render(.steel, pitch: 48, seconds: 2.0)

        let bowedEarly = Self.loudness(bowed, from: 0.25, to: 0.45)
        let bowedLate = Self.loudness(bowed, from: 1.5, to: 1.9)
        let pluckedEarly = Self.loudness(plucked, from: 0.25, to: 0.45)
        let pluckedLate = Self.loudness(plucked, from: 1.5, to: 1.9)

        // The bow holds its level; the pluck is well down from where it was.
        #expect(bowedLate > 0.7 * bowedEarly,
                "a bowed note should hold: \(bowedEarly) then \(bowedLate)")
        #expect(pluckedLate < 0.5 * pluckedEarly,
                "a plucked note should fade: \(pluckedEarly) then \(pluckedLate)")
    }

    @Test func aBlownNoteIsStillBeingMadeInTheMiddle() {
        let blown = Self.render(.clarinet, pitch: 62, seconds: 2.0)
        #expect(Self.loudness(blown, from: 1.5, to: 1.9)
                > 0.7 * Self.loudness(blown, from: 0.25, to: 0.45))
    }

    /// Nothing is driving it, so there is nothing to hear. This is the
    /// counterfactual that says the sound really is coming from the drive.
    @Test func nothingSoundsWithoutDriving() {
        for voice in [Voice.cello, Voice.clarinet] {
            let silent = Self.render(voice, pitch: 55, seconds: 1.0, drive: 0)
            #expect(silent.allSatisfy { abs($0) < 1e-9 }, "\(voice.source) made sound unbowed")
        }
    }

    /// A note that can change while it sounds is the thing an envelope cannot
    /// give you. Two takes of the same note, differing only in what the player
    /// did half way through.
    @Test func theDriveReachesANoteWhileItIsSounding() {
        let steady = Self.render(.cello, pitch: 48, seconds: 2.0, drive: 0.8)
        let lifted = Self.render(.cello, pitch: 48, seconds: 2.0, drive: 0.8,
                                 changeTo: (at: 1.0, drive: 0))

        // Identical up to the moment the bow was lifted.
        #expect(abs(Self.loudness(steady, from: 0.4, to: 0.9)
                    - Self.loudness(lifted, from: 0.4, to: 0.9)) < 1e-9)
        // And ringing out afterwards rather than still being played.
        #expect(Self.loudness(lifted, from: 1.5, to: 1.9)
                < 0.5 * Self.loudness(steady, from: 1.5, to: 1.9))

        // Bowing faster is louder, which is the other half of the control.
        // Measured at about 1.8 times across that range rather than the ratio
        // of the speeds: a bowed string's loudness comes from the bow's force
        // as much as its speed, and force is the stronger of the two here.
        #expect(Self.loudness(Self.render(.cello, pitch: 48, seconds: 1.6, drive: 0.9),
                              from: 1.0, to: 1.5)
                > 1.5 * Self.loudness(Self.render(.cello, pitch: 48, seconds: 1.6, drive: 0.25),
                                      from: 1.0, to: 1.5))
    }

    /// The sources that are set going once must not hear the drive at all, so
    /// adding this control cannot have changed any voice that existed before.
    @Test func aSourceThatIsSetGoingOnceIgnoresTheDrive() {
        for voice in [Voice.pluck, Voice.steel, Voice.bell, Voice.drum] {
            let full = Self.render(voice, pitch: 60, seconds: 0.8, drive: 1)
            let none = Self.render(voice, pitch: 60, seconds: 0.8, drive: 0)
            #expect(full == none, "\(voice.source) changed with the drive")
            #expect(full.contains { abs($0) > 0.001 })
        }
    }

    // MARK: - The bowed string

    /// A bowed string is caught and released once per cycle, which makes its
    /// motion a sawtooth. A sawtooth's harmonics fall off as one over their
    /// number, so that is what the spectrum has to look like.
    @Test func aBowedStringMovesLikeASawtooth() {
        let f0 = 130.81
        let s = Self.render(.cello, pitch: Self.midi(of: f0), seconds: 1.8)
        let h = Self.harmonics(s, of: f0)

        // The fundamental is the strongest, and each harmonic is weaker than
        // the one below it, which is what one-over-n means.
        #expect(h[0] == 1.0, "the fundamental should dominate, got \(h)")
        for index in 1..<h.count {
            #expect(h[index] <= h[index - 1] + 0.02,
                    "harmonic \(index + 1) rose above \(index): \(h)")
        }
        // And it is genuinely a rich tone rather than a sine.
        #expect(h[1] > 0.2 && h[2] > 0.1, "too few harmonics for a bow: \(h)")
    }

    /// Bow force decides whether the string can be driven at all without
    /// breaking. The twin is the same bow speed on a lighter bow, which tears
    /// loose twice a cycle and jumps to the octave, exactly as over-bowing does.
    @Test func tooLittleForceForTheSpeedBreaksIntoTheOctave() {
        let f0 = 196.0
        func spectrum(force: Double) -> [Double] {
            var spec = BowedString.violin
            spec.force = force
            let voice = Voice(bowed: spec, gain: 0.7)
            let s = Self.render(voice, pitch: Self.midi(of: f0), seconds: 1.8, drive: 1.0)
            return Self.harmonics(s, of: f0)
        }
        let solid = spectrum(force: 0.75)
        let overBowed = spectrum(force: 0.06)

        #expect(solid[0] == 1.0, "a firm bow should hold the fundamental: \(solid)")
        #expect(overBowed[1] > overBowed[0],
                "a bow too light for the speed should break to the octave: \(overBowed)")
    }

    /// Bowing right next to the bridge is a different sound, not a louder one:
    /// the fundamental thins out and the upper partials take over, which is
    /// what sul ponticello is.
    @Test func bowingNearTheBridgeThinsTheFundamental() {
        let f0 = 196.0
        func fundamentalShare(_ spec: BowedString) -> Double {
            let s = Self.render(Voice(bowed: spec, gain: 0.7),
                                pitch: Self.midi(of: f0), seconds: 1.8)
            return Self.harmonics(s, of: f0)[0]
        }
        #expect(fundamentalShare(.ponticello) < 0.6 * fundamentalShare(.cello))
    }

    /// The two sides of the bow have to add up to one period, so the string
    /// sounds the note it was asked for whatever the bow is doing.
    @Test func aBowedStringIsInTuneWhereverTheBowIs() {
        let capacity = 4096
        let memory = UnsafeMutablePointer<Double>.allocate(
            capacity: BowVoice.memoryNeeded(capacity: capacity))
        defer { memory.deallocate() }

        for note in stride(from: 33.0, through: 93.0, by: 6) {
            let wanted = 440 * pow(2, (note - 69) / 12)
            for position in [0.05, 0.13, 0.25, 0.4] {
                for damping in [0.0, 0.5, 1.0] {
                    var bow = BowVoice(buffer: memory, capacity: capacity)
                    bow.start(frequency: wanted,
                              spec: BowedString(position: position, damping: damping),
                              sampleRate: Self.rate)
                    let sounded = bow.soundingFrequency(sampleRate: Self.rate)
                    let cents = abs(1200 * log2(sounded / wanted))
                    #expect(cents < 1,
                            "\(wanted) Hz at \(position)/\(damping) sounded \(sounded) (\(cents)c)")
                }
            }
        }
    }

    /// How bright the string is must not be able to move its pitch, the same
    /// promise the plucked string makes.
    @Test func dampingCannotMoveTheBowedPitch() {
        let capacity = 4096
        let memory = UnsafeMutablePointer<Double>.allocate(
            capacity: BowVoice.memoryNeeded(capacity: capacity))
        defer { memory.deallocate() }

        var dark = BowVoice(buffer: memory, capacity: capacity)
        dark.start(frequency: 220, spec: BowedString(damping: 1), sampleRate: Self.rate)
        var bright = BowVoice(buffer: memory, capacity: capacity)
        bright.start(frequency: 220, spec: BowedString(damping: 0), sampleRate: Self.rate)

        let apart = abs(1200 * log2(dark.soundingFrequency(sampleRate: Self.rate)
                                    / bright.soundingFrequency(sampleRate: Self.rate)))
        #expect(apart < 1, "damping moved the pitch by \(apart) cents")
    }

    // MARK: - The blown tube

    /// The one that says the model is a stopped tube and not just a filter. A
    /// tube closed at one end fits a quarter of a wave, so it supports the odd
    /// harmonics and not the even ones. The twin is the bowed string, which
    /// has all of them.
    @Test func aStoppedTubeSoundsOnlyItsOddHarmonics() {
        let f0 = 146.83
        let tube = Self.harmonics(
            Self.render(.clarinet, pitch: Self.midi(of: f0), seconds: 1.8), of: f0)
        let string = Self.harmonics(
            Self.render(.cello, pitch: Self.midi(of: f0), seconds: 1.8), of: f0)

        // Odd harmonics carry the tone; even ones are barely there at all.
        #expect(tube[0] == 1.0, "the fundamental should lead: \(tube)")
        #expect(tube[2] > 0.05, "the third harmonic should be present: \(tube)")
        #expect(tube[1] < 0.1, "the second harmonic should be all but absent: \(tube)")
        #expect(tube[3] < 0.1, "the fourth harmonic should be all but absent: \(tube)")

        // The string, on the same note, has the even ones the tube does not.
        #expect(string[1] > 3 * tube[1],
                "a string should keep its even harmonics: \(string) vs \(tube)")
    }

    /// Biting harder shuts the reed at a lower pressure, which changes the tone
    /// rather than the loudness. The twin is the same tube with a looser lip.
    @Test func biteChangesTheReedsTone() {
        let f0 = 220.0
        func brightness(_ embouchure: Double) -> Double {
            var spec = BlownTube.clarinet
            spec.embouchure = embouchure
            let s = Self.render(Voice(blown: spec, gain: 0.6),
                                pitch: Self.midi(of: f0), seconds: 1.6)
            // Measured at the tube's own harmonics rather than on a fixed grid,
            // so this reads the tone and not the tuning.
            let h = Self.harmonics(s, of: f0, count: 8)
            let total = h.reduce(0, +)
            guard total > 1e-9 else { return 0 }
            return h.enumerated().reduce(0) { $0 + Double($1.offset + 1) * $1.element } / total
        }
        // Measured, not assumed: a tighter bite shuts the reed at a lower
        // pressure, so it gets less far open and lets less through, and the
        // tone comes out simpler. A loose lip is the rich one.
        #expect(brightness(0.2) > brightness(0.85),
                "a looser lip should be the richer of the two")
    }

    /// The round trip is half a period, not a whole one, so the tube sounds the
    /// note it was asked for rather than an octave and a fifth above it.
    @Test func aBlownTubeIsInTune() {
        let capacity = 4096
        let memory = UnsafeMutablePointer<Double>.allocate(
            capacity: TubeVoice.memoryNeeded(capacity: capacity))
        defer { memory.deallocate() }

        for note in stride(from: 45.0, through: 93.0, by: 6) {
            let wanted = 440 * pow(2, (note - 69) / 12)
            var tube = TubeVoice(buffer: memory, capacity: capacity, seed: 1)
            tube.start(frequency: wanted, spec: .clarinet, sampleRate: Self.rate)
            let cents = abs(1200 * log2(tube.soundingFrequency(sampleRate: Self.rate) / wanted))
            #expect(cents < 12, "\(wanted) Hz sounded \(cents) cents out")
        }
    }

    /// And it really does come out where it was asked for, measured off the
    /// sound rather than off the model's own arithmetic.
    @Test func theTubeSoundsThePitchItWasAskedFor() {
        let f0 = 220.0
        let s = Self.render(.clarinet, pitch: Self.midi(of: f0), seconds: 1.6)
        let window = s[Int(1.0 * Self.rate)..<Int(1.4 * Self.rate)]
        let atPitch = Self.magnitude(window, at: f0)
        // Not an octave up, and not the fifth above that, which are the two
        // places a mistuned stopped tube would land.
        #expect(atPitch > 3 * Self.magnitude(window, at: f0 * 2))
        #expect(atPitch > 2 * Self.magnitude(window, at: f0 * 3))
    }

    // MARK: - The tier's rules

    /// The renderer has no clock and takes its randomness from its own seed, so
    /// the same note renders the same samples every time.
    @Test func adrivenNoteRendersTheSameWayTwice() {
        for voice in [Voice.violin, Voice.clarinet] {
            let once = Self.render(voice, pitch: 57, seconds: 0.8)
            let again = Self.render(voice, pitch: 57, seconds: 0.8)
            #expect(once == again)
            #expect(once.contains { abs($0) > 0.001 })
        }
    }

    /// A driven voice still rides the event ring, so it must stay something
    /// that can be copied a word at a time.
    @Test func adrivenVoiceIsStillTriviallyCopyable() {
        #expect(_isPOD(BowedString.self))
        #expect(_isPOD(BlownTube.self))
        #expect(_isPOD(SynthEvent.self))
    }
}
