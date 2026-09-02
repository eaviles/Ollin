import Foundation
import Testing
@testable import OllinAudio

/// A table of cycles read by position. What is checked is that a frame plays
/// the harmonics it was built from, that a position between two frames plays
/// their blend, that a bright frame stays clean at the top of the keyboard,
/// and that the scan's envelope moves the position over the note.
@Suite struct WavetableTests {

    static let rate = 44100.0

    static func render(_ voice: Voice, table: Wavetable?, pitch: Double, seconds: Double,
                       held: Bool = true) -> [Double] {
        let events = EventRing()
        let renderer = SynthRenderer(voice: voice, polyphony: 4, sampleRate: rate, events: events)
        renderer.gain = 1
        renderer.wavetable = table
        events.push(SynthEvent(kind: .noteOn, pitch: pitch, velocity: 1,
                               durationSamples: held ? 0 : Int(seconds * 0.5 * rate)))
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

    static func midi(of hz: Double) -> Double { 69 + 12 * log2(hz / 440) }

    /// A window well into a held note, after every envelope has settled.
    static func settled(_ s: [Double]) -> ArraySlice<Double> {
        s[Int(0.5 * rate) ..< Int(0.9 * rate)]
    }

    // MARK: What a frame plays

    @Test func aFrameOfOneHarmonicPlaysThatHarmonic() {
        let table = Wavetable(name: "third", harmonics: [[0, 0, 1]])
        let f0 = 220.0
        let sound = Self.render(Voice(wavetable: .at(0), envelope: .organ), table: table,
                                pitch: Self.midi(of: f0), seconds: 1)
        let window = Self.settled(sound)
        let third = Self.magnitude(window, at: 3 * f0)
        #expect(third > 0.1, "the frame's one harmonic should be there, not \(third)")
        #expect(Self.magnitude(window, at: f0) < third * 0.01)
        #expect(Self.magnitude(window, at: 2 * f0) < third * 0.01)
    }

    @Test func halfwayBetweenTwoFramesIsTheirBlend() {
        // A sine in the first frame, its third harmonic alone in the second:
        // read halfway, both are there at the same strength.
        let table = Wavetable(name: "pair", harmonics: [[1], [0, 0, 1]])
        let f0 = 220.0
        let sound = Self.render(Voice(wavetable: .at(0.5), envelope: .organ), table: table,
                                pitch: Self.midi(of: f0), seconds: 1)
        let window = Self.settled(sound)
        let first = Self.magnitude(window, at: f0)
        let third = Self.magnitude(window, at: 3 * f0)
        #expect(first > 0.05 && third > 0.05)
        #expect(abs(first - third) < 0.15 * max(first, third),
                "halfway should weigh the frames alike: \(first) against \(third)")

        // At either end only that frame sounds.
        let atStart = Self.settled(Self.render(Voice(wavetable: .at(0), envelope: .organ),
                                               table: table, pitch: Self.midi(of: f0), seconds: 1))
        #expect(Self.magnitude(atStart, at: 3 * f0) < Self.magnitude(atStart, at: f0) * 0.01)
    }

    @Test func aDrawnCycleComesBackAsItself() {
        let count = 512
        let drawn = (0..<count).map { i -> Double in
            let t = Double(i) / Double(count)
            return 0.7 * sin(2 * .pi * t) + 0.3 * sin(2 * .pi * 3 * t + 0.4)
        }
        let table = Wavetable(name: "drawn", frames: [drawn])
        let back = table.frame(0)
        #expect(back.count == Wavetable.length)
        // The same shape at the table's own length, up to the peak scaling.
        let peak = drawn.map(abs).max()!
        var worst = 0.0
        for i in 0..<count {
            let expected = drawn[i] / peak
            let got = back[i * Wavetable.length / count]
            worst = max(worst, abs(expected - got))
        }
        #expect(worst < 1e-3, "the drawn cycle came back off by \(worst)")
        #expect(abs(back.map(abs).max()! - 1) < 1e-6, "a frame is scaled so its loudest point is 1")
    }

    @Test func theBuiltInTablesHaveTheirFrames() {
        #expect(Wavetable.basic.frameCount == 4)
        #expect(Wavetable.pulse.frameCount == 5)
        #expect(Wavetable.vowels.frameCount == 5)
        // The first frame of the plain table is a sine, and the last a square:
        // the square's third harmonic is a third of its first, the sine has none.
        let sine = Wavetable.basic.frame(0)
        let square = Wavetable.basic.frame(3)
        func harmonic(_ cycle: [Double], _ h: Int) -> Double {
            var s = 0.0, c = 0.0
            for (i, v) in cycle.enumerated() {
                let a = 2 * Double.pi * Double(h * i) / Double(cycle.count)
                s += v * sin(a); c += v * cos(a)
            }
            return (s * s + c * c).squareRoot() * 2 / Double(cycle.count)
        }
        #expect(harmonic(sine, 3) < 1e-6)
        #expect(abs(harmonic(square, 3) / harmonic(square, 1) - 1.0 / 3) < 1e-3)
        // The blend the sketch draws is the blend the note reads.
        let midway = Wavetable.basic.cycle(at: 1.0 / 6)
        #expect(midway.count == Wavetable.length)
        #expect(abs(midway[Wavetable.length / 4] - 0.5 * (sine[Wavetable.length / 4] + Wavetable.basic.frame(1)[Wavetable.length / 4])) < 1e-6)
    }

    // MARK: Staying clean at the top

    /// A sawtooth frame at 5 kHz: its fifth harmonic and up would land above
    /// half the sample rate and fold back down as tones that are not
    /// harmonics of the note. The band-limited read has none of those, and the
    /// same frame read with every harmonic in (the counterfactual) has them
    /// plainly.
    @Test func aBrightFrameDoesNotFoldAtTheTopOfTheKeyboard() {
        let f0 = 5000.0
        let sound = Self.render(Voice(wavetable: .at(2.0 / 3), envelope: .organ),
                                table: .basic, pitch: Self.midi(of: f0), seconds: 1)
        let window = Self.settled(sound)
        let fundamental = Self.magnitude(window, at: f0)
        #expect(fundamental > 0.05)
        // Harmonic 7 (35 kHz) folds to 9.1 kHz and harmonic 6 (30 kHz) to 14.1 kHz.
        let folded7 = Self.magnitude(window, at: 2 * 22050 - 7 * f0)
        let folded6 = Self.magnitude(window, at: 2 * 22050 - 6 * f0)
        #expect(folded7 < fundamental * 0.005, "harmonic 7 folded back at \(folded7 / fundamental)")
        #expect(folded6 < fundamental * 0.005, "harmonic 6 folded back at \(folded6 / fundamental)")
        // What the note does keep: the harmonics that fit.
        #expect(Self.magnitude(window, at: 2 * f0) > fundamental * 0.3)

        // The counterfactual: the full-band frame read at the same rate.
        let full = Wavetable.basic.frame(2)
        let increment = f0 / Self.rate
        var phase = 0.0
        var naive = [Double]()
        for _ in 0 ..< Int(Self.rate) {
            let at = phase * Double(Wavetable.length)
            let i = Int(at) & (Wavetable.length - 1)
            naive.append(full[i])
            phase -= floor(phase)
            phase += increment
            phase -= floor(phase)
        }
        let naiveWindow = Self.settled(naive)
        let naiveFundamental = Self.magnitude(naiveWindow, at: f0)
        let naiveFolded = Self.magnitude(naiveWindow, at: 2 * 22050 - 7 * f0)
        #expect(naiveFolded > naiveFundamental * 0.05,
                "the unlimited frame should fold audibly (\(naiveFolded / naiveFundamental)), or the check proves nothing")
    }

    @Test func theLevelFollowsThePitch() {
        // Every harmonic at the very bottom; only the fundamental at the top.
        // At 55 Hz four hundred harmonics fit under half the rate, so the
        // level with 256 is the strongest that does.
        #expect(Wavetable.level(forIncrement: 20 / Self.rate) == 0)
        #expect(Wavetable.harmonicLimit(atLevel: Wavetable.level(forIncrement: 55 / Self.rate)) == 256)
        #expect(Wavetable.level(forIncrement: 20000 / Self.rate) == Wavetable.levelCount - 1)
        // 5 kHz fits four harmonics under 22.05 kHz.
        let level = Wavetable.level(forIncrement: 5000 / Self.rate)
        #expect(Wavetable.harmonicLimit(atLevel: level) == 4)
        #expect(Wavetable.basic.frame(2, harmonicsUpTo: 4).count == Wavetable.length)
    }

    // MARK: The scan moving

    @Test func theSweepMovesThePositionOverTheNote() {
        // From the sine end, struck to the square end, and settling back most
        // of the way: the third harmonic is strong early and nearly gone late.
        let f0 = 220.0
        let sound = Self.render(.morph, table: .basic, pitch: Self.midi(of: f0), seconds: 1.6)
        let early = sound[Int(0.02 * Self.rate) ..< Int(0.12 * Self.rate)]
        let late = sound[Int(1.2 * Self.rate) ..< Int(1.55 * Self.rate)]
        let earlyRatio = Self.magnitude(early, at: 3 * f0) / Self.magnitude(early, at: f0)
        let lateRatio = Self.magnitude(late, at: 3 * f0) / Self.magnitude(late, at: f0)
        #expect(earlyRatio > 0.2, "early on the note should be near the square: \(earlyRatio)")
        #expect(lateRatio < earlyRatio * 0.3, "late it should have settled toward the sine: \(lateRatio)")

        // Held still, it stays where it was put.
        let still = Self.render(Voice(wavetable: .at(1), envelope: .organ), table: .basic,
                                pitch: Self.midi(of: f0), seconds: 1.6)
        let stillEarly = still[Int(0.02 * Self.rate) ..< Int(0.12 * Self.rate)]
        let stillLate = still[Int(1.2 * Self.rate) ..< Int(1.55 * Self.rate)]
        let a = Self.magnitude(stillEarly, at: 3 * f0) / Self.magnitude(stillEarly, at: f0)
        let b = Self.magnitude(stillLate, at: 3 * f0) / Self.magnitude(stillLate, at: f0)
        #expect(abs(a - b) < 0.05 * max(a, b))
    }

    @Test func detuneReadsTheTableTwice() {
        let f0 = 220.0
        let sound = Self.render(Voice(wavetable: .at(0), envelope: .organ, detune: 0.3),
                                table: .basic, pitch: Self.midi(of: f0), seconds: 1)
        let window = Self.settled(sound)
        let apart = f0 * pow(2, 0.3 / 12)
        #expect(Self.magnitude(window, at: f0) > 0.05)
        #expect(Self.magnitude(window, at: apart) > 0.05)
    }

    // MARK: The rules

    @Test func noTableMeansSilenceAndNothingElse() {
        let sound = Self.render(Voice(wavetable: .at(0.5)), table: nil, pitch: 60, seconds: 0.3)
        #expect(!sound.contains { abs($0) > 1e-9 })
    }

    @Test func theScanIsSmallAndTheVoiceStaysCopyable() {
        #expect(_isPOD(WavetableScan.self))
        #expect(_isPOD(VoiceSource.self))
        #expect(_isPOD(Voice.self))
        #expect(_isPOD(SynthEvent.self))
    }

    @Test func theVoiceSaysWhereItReads() throws {
        var voice = Voice(wavetable: WavetableScan(position: 0.3, sweep: 0.5))
        #expect(voice.wavetable?.position == 0.3)
        #expect(voice.plucked == nil && voice.patch == nil)
        #expect(Voice.morph.wavetable != nil)
        #expect(Voice.pluck.wavetable == nil)
        voice.wavetable?.position = 0.9
        #expect(voice.wavetable?.position == 0.9)
        #expect(!voice.source.isDriven)

        let data = try JSONEncoder().encode(voice)
        let back = try JSONDecoder().decode(Voice.self, from: data)
        #expect(back == voice)

        // The numbers are kept in range.
        let clamped = WavetableScan(position: 3, sweep: -4)
        #expect(clamped.position == 1 && clamped.sweep == -1)
    }

    @Test func everyOlderPresetStillHasNoTable() {
        for voice in [Voice.pluck, .bass, .pad, .bell, .stab, .breath, .sine,
                      .nylon, .steel, .harp, .muted, .drum, .violin, .clarinet,
                      .fmBell, .fmBrass, .fmBuzz] {
            #expect(voice.wavetable == nil, "\(voice.source) became a wavetable")
        }
    }
}
