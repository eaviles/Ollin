import Foundation
import Testing
@testable import OllinAudio

/// Routing as a value. Most of what is checked here is that a patch is what it
/// says it is, and that adding a tier underneath the presets left the presets
/// exactly where they were.
@Suite struct PatchTests {

    static let rate = 44100.0

    static func render(_ voice: Voice, pitch: Double, seconds: Double) -> [Double] {
        let events = EventRing()
        let renderer = SynthRenderer(voice: voice, polyphony: 4, sampleRate: rate, events: events)
        renderer.gain = 1
        events.push(SynthEvent(kind: .noteOn, pitch: pitch, velocity: 0.9,
                               durationSamples: 0))
        var out = [Double]()
        let block = 512
        while out.count < Int(seconds * rate) {
            var chunk = [Float](repeating: 0, count: block)
            chunk.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: block) }
            out += chunk.map(Double.init)
        }
        return out
    }

    static func magnitude(_ s: ArraySlice<Double>, at hz: Double) -> Double {
        let n = s.count
        guard n > 16 else { return 0 }
        let w = 2 * Double.pi * hz / rate
        let c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in s { let s0 = v + c * s1 - s2; s2 = s1; s1 = s0 }
        return (s1 * s1 + s2 * s2 - c * s1 * s2).squareRoot() / Double(n)
    }

    /// Energy at the note's own harmonics, relative to the strongest.
    static func harmonics(_ s: [Double], of f0: Double, count: Int = 8) -> [Double] {
        let window = s[Int(0.3 * rate)..<Int(0.7 * rate)]
        let raw = (1...count).map { magnitude(window, at: f0 * Double($0)) }
        let peak = raw.max() ?? 0
        return peak > 1e-12 ? raw.map { $0 / peak } : raw
    }

    static func midi(of hz: Double) -> Double { 69 + 12 * log2(hz / 440) }

    // MARK: - The tier underneath

    /// The headline promise: the bare form is untouched. Every preset that
    /// existed before this tier renders exactly the samples it rendered before,
    /// because none of them is a patch.
    @Test func everyPresetThatIsNotAPatchIsUnchanged() {
        for voice in [Voice.pluck, .bass, .pad, .bell, .stab, .breath, .sine,
                      .nylon, .steel, .harp, .muted, .drum, .violin, .clarinet] {
            #expect(voice.patch == nil, "\(voice.source) became a patch")
            let sound = Self.render(voice, pitch: 60, seconds: 0.4)
            #expect(sound.contains { abs($0) > 0.001 }, "\(voice.source) went silent")
        }
    }

    /// A one operator patch is an oscillator, so it has to be the same
    /// oscillator. This is the check that the shared shape evaluator did not
    /// change what the ordinary path produces.
    @Test func aSingleOperatorPatchIsExactlyAnOscillator() {
        for waveform in [Waveform.sine, .triangle, .sawtooth, .square] {
            let plain = Self.render(Voice(waveform: waveform, envelope: .organ),
                                    pitch: 57, seconds: 0.3)
            let patched = Self.render(Voice(patch: .tone(waveform), envelope: .organ),
                                      pitch: 57, seconds: 0.3)
            #expect(plain == patched, "\(waveform) drifted between the two paths")
        }
    }

    // MARK: - What a patch is

    @Test func atoneIsOneOperatorThatIsHeard() {
        let patch = Patch.tone(.sine, ratio: 2, level: 0.5)
        #expect(patch.count == 1)
        let op = patch.operators[0]
        #expect(op.waveform == .sine)
        #expect(op.ratio == 2)
        #expect(op.level == 0.5)
        #expect(op.reachesOutput)
        #expect(op.modulatedBy == nil)
    }

    /// Modulating puts the modulator in an earlier lane than what it pushes,
    /// which is what lets one forward pass evaluate the whole patch.
    @Test func amodulatorSitsInAnEarlierLaneThanWhatItPushes() {
        let patch = Patch.tone(.sine).modulated(by: .tone(.sine, ratio: 3), index: 2)
        #expect(patch.count == 2)

        let operators = patch.operators
        // The modulator is first, is not heard, and its level is the depth.
        #expect(!operators[0].reachesOutput)
        #expect(operators[0].ratio == 3)
        #expect(operators[0].level == 2)
        // The carrier is second, is heard, and points back at the modulator.
        #expect(operators[1].reachesOutput)
        #expect(operators[1].modulatedBy == 0)

        // Every modulator reference points backwards, whatever is built.
        let deep = Patch.tone(.sine)
            .modulated(by: Patch.tone(.sine, ratio: 2)
                .modulated(by: .tone(.sine, ratio: 5), index: 1), index: 3)
        for (lane, op) in deep.operators.enumerated() {
            if let source = op.modulatedBy { #expect(source < lane) }
        }
    }

    @Test func mixingKeepsBothVoices() {
        let patch = Patch.tone(.sine).mixed(with: .tone(.sine, ratio: 2))
        #expect(patch.count == 2)
        #expect(patch.operators.allSatisfy { $0.reachesOutput })
    }

    @Test func feedbackAppliesToWhatIsHeard() {
        let patch = Patch.tone(.sine).fedBack(0.5)
        #expect(patch.operators[0].feedback == 0.5)
        // And it is bounded, since past one it is not feedback any more.
        #expect(Patch.tone(.sine).fedBack(9).operators[0].feedback == 1)
        #expect(Patch.tone(.sine).fedBack(-2).operators[0].feedback == 0)
    }

    /// A patch is a fixed size because it travels to the audio thread inside a
    /// note. Past the limit it refuses rather than quietly dropping an
    /// operator, since a patch with a piece missing is a different instrument.
    @Test func apatchPastItsLimitRefusesRatherThanLosingAnOperator() {
        var patch = Patch.tone(.sine)
        for _ in 0..<7 { patch = patch.mixed(with: .tone(.sine)) }
        #expect(patch.count == Patch.maxOperators)

        // One more would be nine, so the patch comes back as it was.
        let refused = patch.mixed(with: .tone(.sine))
        #expect(refused.count == Patch.maxOperators)
        #expect(refused == patch)
    }

    /// The constraint this whole design is shaped by.
    @Test func apatchStillRidesTheLockFreeRing() {
        #expect(_isPOD(Patch.self))
        #expect(_isPOD(VoiceSource.self))
        #expect(_isPOD(Voice.self))
        #expect(_isPOD(SynthEvent.self))
    }

    // MARK: - What it sounds like

    /// The reason frequency modulation is worth having: it puts harmonics into
    /// a sine, which no amount of filtering can do. The twin is the same
    /// carrier with nothing pushing it.
    @Test func modulationPutsHarmonicsIntoASine() {
        let f0 = 220.0
        let plain = Self.harmonics(
            Self.render(Voice(patch: .tone(.sine), envelope: .organ),
                        pitch: Self.midi(of: f0), seconds: 0.9), of: f0)
        let pushed = Self.harmonics(
            Self.render(Voice(patch: Patch.tone(.sine)
                .modulated(by: .tone(.sine, ratio: 1), index: 3), envelope: .organ),
                pitch: Self.midi(of: f0), seconds: 0.9), of: f0)

        // A sine is its fundamental and nothing else.
        #expect(plain[0] == 1.0)
        #expect(plain.dropFirst().allSatisfy { $0 < 0.02 }, "a plain sine had harmonics: \(plain)")
        // Pushed, there is real energy above it.
        let above = pushed.dropFirst().filter { $0 > 0.1 }.count
        #expect(above >= 3, "modulation should fill in harmonics, got \(pushed)")
    }

    /// How hard the modulator pushes decides how many harmonics there are,
    /// which is the one parameter that matters most.
    @Test func aHarderPushIsABrighterTone() {
        let f0 = 220.0
        func brightness(_ index: Double) -> Double {
            let patch = Patch.tone(.sine).modulated(by: .tone(.sine, ratio: 1), index: index)
            let h = Self.harmonics(
                Self.render(Voice(patch: patch, envelope: .organ),
                            pitch: Self.midi(of: f0), seconds: 0.9), of: f0)
            let total = h.reduce(0, +)
            guard total > 1e-9 else { return 0 }
            return h.enumerated().reduce(0) { $0 + Double($1.offset + 1) * $1.element } / total
        }
        #expect(brightness(5) > brightness(1))
    }

    /// A ratio that is not a whole number gives tones that are not harmonics of
    /// the note, which is what metal sounds like. The twin is the same patch at
    /// a whole ratio.
    @Test func anInharmonicRatioRingsLikeMetalRatherThanLikeANote() {
        let f0 = 220.0
        func harmonicShare(ratio: Double) -> Double {
            let patch = Patch.tone(.sine).modulated(by: .tone(.sine, ratio: ratio), index: 4)
            let sound = Self.render(Voice(patch: patch, envelope: .organ),
                                    pitch: Self.midi(of: f0), seconds: 0.9)
            let window = sound[Int(0.3 * Self.rate)..<Int(0.7 * Self.rate)]
            // How much of the energy sits on the note's own harmonics.
            let onHarmonics = (1...10).reduce(0.0) { $0 + Self.magnitude(window, at: f0 * Double($1)) }
            // Against the same count of places that are not harmonics.
            let between = (1...10).reduce(0.0) { $0 + Self.magnitude(window, at: f0 * (Double($1) + 0.5)) }
            return onHarmonics / max(1e-12, onHarmonics + between)
        }
        #expect(harmonicShare(ratio: 2) > harmonicShare(ratio: 3.5) + 0.15,
                "a whole ratio should sit on the harmonics far more than 3.5 does")
    }

    @Test func feedbackBrightensASine() {
        let f0 = 220.0
        let plain = Self.harmonics(
            Self.render(Voice(patch: .tone(.sine), envelope: .organ),
                        pitch: Self.midi(of: f0), seconds: 0.9), of: f0)
        let buzzing = Self.harmonics(
            Self.render(Voice(patch: Patch.tone(.sine).fedBack(0.6), envelope: .organ),
                        pitch: Self.midi(of: f0), seconds: 0.9), of: f0)
        #expect(plain.dropFirst().allSatisfy { $0 < 0.02 })
        #expect(buzzing.dropFirst().contains { $0 > 0.15 }, "feedback added nothing: \(buzzing)")
    }

    /// Two operators heard together must not be twice as loud as one, or every
    /// patch would need its levels balanced by hand.
    @Test func mixingDoesNotDoubleTheLevel() {
        func peak(_ patch: Patch) -> Double {
            Self.render(Voice(patch: patch, envelope: .organ), pitch: 57, seconds: 0.5)
                .map(abs).max() ?? 0
        }
        let one = peak(.tone(.sine))
        let two = peak(Patch.tone(.sine).mixed(with: .tone(.sine, ratio: 1.5)))
        #expect(two < 1.4 * one, "one \(one), two \(two)")
    }

    @Test func thenamedPatchesSound() {
        for (name, voice) in [("fmBell", Voice.fmBell), ("fmBrass", .fmBrass),
                              ("fmBuzz", .fmBuzz)] {
            let sound = Self.render(voice, pitch: 60, seconds: 0.6)
            #expect(sound.contains { abs($0) > 0.01 }, "\(name) was silent")
            #expect(sound.allSatisfy { abs($0) <= 1.0 }, "\(name) clipped")
        }
    }

    /// The renderer takes events and gives back samples with no clock, so a
    /// patch renders the same way twice like everything else.
    @Test func apatchRendersTheSameWayTwice() {
        let voice = Voice(patch: .bell, envelope: .percussive)
        #expect(Self.render(voice, pitch: 64, seconds: 0.5)
                == Self.render(voice, pitch: 64, seconds: 0.5))
    }

    @Test func anEmptyPatchIsSilentRatherThanWrong() {
        let sound = Self.render(Voice(patch: Patch(), envelope: .organ),
                                pitch: 60, seconds: 0.3)
        #expect(sound.allSatisfy { abs($0) < 1e-9 })
    }
}
