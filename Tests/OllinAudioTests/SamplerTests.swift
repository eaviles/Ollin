import Foundation
import Testing
@testable import OllinAudio

/// An instrument made of recordings. Most of what is checked here is the map:
/// which recording answers a note, and whether it comes out at the pitch asked
/// for, since a sampler that picks the wrong file or moves it the wrong
/// distance is the whole way a sampler goes wrong.
@Suite struct SamplerTests {

    static let rate = 44100.0

    static func render(_ instrument: SampledInstrument, pitch: Double,
                       spec: Sampler = Sampler(), seconds: Double = 1.2,
                       velocity: Double = 0.9) -> [Double] {
        let events = EventRing()
        let renderer = SynthRenderer(voice: Voice(sampled: spec, envelope: .plucked),
                                     polyphony: 4, sampleRate: rate, events: events)
        renderer.gain = 1
        renderer.instrument = instrument
        events.push(SynthEvent(kind: .noteOn, pitch: pitch, velocity: velocity,
                               durationSamples: Int(seconds * rate)))
        var out = [Double]()
        while out.count < Int(seconds * rate) {
            var chunk = [Float](repeating: 0, count: 512)
            chunk.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: 512) }
            out += chunk.map(Double.init)
        }
        return out
    }

    static func magnitude(_ s: ArraySlice<Double>, at hz: Double) -> Double {
        let w = 2 * Double.pi * hz / rate, c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for v in s { let s0 = v + c * s1 - s2; s2 = s1; s1 = s0 }
        return (s1 * s1 + s2 * s2 - c * s1 * s2).squareRoot() / Double(s.count)
    }

    static func frequency(of midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    // MARK: - Reading the map

    @Test func sfzRegionsRead() {
        let file = SFZFile(text: """
        // a comment, and a blank line follow

        <region> sample=a.wav lokey=48 hikey=52 pitch_keycenter=50
        <region> sample=b.wav key=60 volume=-6 tune=25
        """)
        #expect(file.regions.count == 2)
        #expect(file.regions[0].sample == "a.wav")
        #expect(file.regions[0].lowKey == 48)
        #expect(file.regions[0].highKey == 52)
        #expect(file.regions[0].rootKey == 50)
        // `key` sets all three at once, which is what a one-file-per-note
        // library writes.
        #expect(file.regions[1].lowKey == 60)
        #expect(file.regions[1].highKey == 60)
        #expect(file.regions[1].rootKey == 60)
        #expect(file.regions[1].volume == -6)
        #expect(file.regions[1].tune == 25)
    }

    /// A group's settings are inherited by the regions under it, which is how
    /// libraries avoid repeating themselves on every line.
    @Test func groupsAndGlobalsAreInherited() {
        let file = SFZFile(text: """
        <global> volume=-3
        <group> loop_mode=loop_continuous
        <region> sample=a.wav key=60
        <region> sample=b.wav key=62 volume=0
        <group>
        <region> sample=c.wav key=64
        """)
        #expect(file.regions.count == 3)
        #expect(file.regions[0].volume == -3)
        #expect(file.regions[0].loops)
        // A region's own opcode wins over the group's.
        #expect(file.regions[1].volume == 0)
        // A new group clears the old group's settings but not the global's.
        #expect(!file.regions[2].loops)
        #expect(file.regions[2].volume == -3)
    }

    /// Libraries write notes both ways, and a reader that took only numbers
    /// would fail on half of them for no reason a user could see.
    @Test func noteNamesAreReadAsWellAsNumbers() {
        #expect(SFZRegion.note("60") == 60)
        #expect(SFZRegion.note("c4") == 60)
        #expect(SFZRegion.note("C4") == 60)
        #expect(SFZRegion.note("a4") == 69)
        #expect(SFZRegion.note("f#3") == 54)
        #expect(SFZRegion.note("db4") == 61)
        #expect(SFZRegion.note("c-1") == 0)
        #expect(SFZRegion.note("wobble") == nil)
    }

    /// SFZ is a Windows format by birth, so paths arrive with backslashes.
    @Test func windowsPathsAreTurnedRound() {
        let file = SFZFile(text: #"<region> sample=samples\piano\c4.wav key=60"#)
        #expect(file.regions.first?.sample == "samples/piano/c4.wav")
    }

    /// An unknown opcode is passed over rather than refused, so a library using
    /// the hundreds of opcodes this does not model still loads and plays.
    @Test func unknownOpcodesAreSkippedRatherThanRefused() {
        let file = SFZFile(text: """
        <region> sample=a.wav key=60 ampeg_attack=0.1 fil_type=lpf_2p cutoff=800 seq_position=2
        """)
        #expect(file.regions.count == 1)
        #expect(file.regions[0].rootKey == 60)
    }

    @Test func anEmptyOrBrokenFileGivesNoRegions() {
        #expect(SFZFile(text: "").regions.isEmpty)
        #expect(SFZFile(text: "// only a comment").regions.isEmpty)
        // A region with no sample names nothing to play.
        #expect(SFZFile(text: "<region> key=60").regions.isEmpty)
    }

    // MARK: - The bundled instrument

    @Test func thebundledInstrumentLoads() throws {
        let instrument = try #require(SampledInstrument.builtIn)
        #expect(!instrument.isEmpty)
        #expect(instrument.recordingCount == 5)
        #expect(instrument.name == "Struck")
    }

    /// Where several recordings cover a note, the nearest wins, because moving
    /// a recording a long way is what makes a sampler sound wrong and it is the
    /// one thing choosing well can avoid.
    @Test func thenearestRecordingIsChosen() throws {
        let instrument = try #require(SampledInstrument.builtIn)
        for key in 40...80 {
            let index = try #require(instrument.zone(for: key, velocity: 0.8))
            let chosen = instrument.zones[index].rootKey
            // No other recording is nearer than the one picked.
            for zone in instrument.zones where zone.lowKey <= key && key <= zone.highKey {
                #expect(abs(key - chosen) <= abs(key - zone.rootKey))
            }
        }
    }

    /// A note outside every recording's range is stretched from the nearest one
    /// rather than played as silence, which is what a small instrument should
    /// do rather than simply stopping.
    @Test func anoteOutsideTheRangeIsStretchedRatherThanSilent() throws {
        let instrument = try #require(SampledInstrument.builtIn)
        let sound = Self.render(instrument, pitch: 96, seconds: 0.6)
        #expect(sound.contains { abs($0) > 0.005 })
    }

    // MARK: - What comes out

    /// The check that says the read head moves at the right rate: a note played
    /// from a recording made at a different pitch has to come out at the pitch
    /// asked for, and the recording's own partials have to move with it.
    @Test func anoteComesOutAtThePitchAskedFor() throws {
        let instrument = try #require(SampledInstrument.builtIn)
        for note in [48.0, 55.0, 60.0, 67.0, 72.0] {
            let sound = Self.render(instrument, pitch: note)
            let window = sound[Int(0.05 * Self.rate)..<Int(0.45 * Self.rate)]
            let f0 = Self.frequency(of: note)

            // Strongest at the note itself, and far stronger there than a
            // semitone either side, which is what being in tune means.
            let atPitch = Self.magnitude(window, at: f0)
            #expect(atPitch > 3 * Self.magnitude(window, at: f0 * pow(2, 1.0 / 12)),
                    "note \(note) is sharp")
            #expect(atPitch > 3 * Self.magnitude(window, at: f0 * pow(2, -1.0 / 12)),
                    "note \(note) is flat")

            // And the recording's own second partial moved with it, which is
            // what says the whole recording was moved rather than merely the
            // note being right by luck.
            #expect(Self.magnitude(window, at: f0 * 2.756)
                    > 3 * Self.magnitude(window, at: f0 * 2),
                    "note \(note) lost the bar's own partials")
        }
    }

    /// Transposing moves every note, which is how an instrument recorded at the
    /// wrong pitch is corrected.
    @Test func transposingMovesTheWholeInstrument() throws {
        let instrument = try #require(SampledInstrument.builtIn)
        let plain = Self.render(instrument, pitch: 60)
        let octaveDown = Self.render(instrument, pitch: 60,
                                     spec: Sampler(transposition: -12))
        func peakFrequency(_ s: [Double]) -> Double {
            let window = s[Int(0.05 * Self.rate)..<Int(0.45 * Self.rate)]
            var best = 0.0, bestHz = 0.0
            for semitone in stride(from: 36.0, through: 84.0, by: 1) {
                let hz = Self.frequency(of: semitone)
                let m = Self.magnitude(window, at: hz)
                if m > best { best = m; bestHz = hz }
            }
            return bestHz
        }
        let ratio = peakFrequency(plain) / peakFrequency(octaveDown)
        #expect(abs(ratio - 2) < 0.06, "an octave down should halve it, got \(ratio)")
    }

    /// Velocity sensitivity is a setting because some instruments record their
    /// own dynamics and should not be scaled again.
    @Test func velocitySensitivityDecidesWhetherVelocityIsHeard() throws {
        let instrument = try #require(SampledInstrument.builtIn)
        func peak(_ velocity: Double, sensitivity: Double) -> Double {
            Self.render(instrument, pitch: 60,
                        spec: Sampler(velocitySensitivity: sensitivity),
                        seconds: 0.5, velocity: velocity).map(abs).max() ?? 0
        }
        // Sensitive: a soft note is much quieter than a hard one.
        #expect(peak(0.2, sensitivity: 1) < 0.4 * peak(1.0, sensitivity: 1))
        // Insensitive: the recording's own level is what is heard.
        #expect(abs(peak(0.2, sensitivity: 0) - peak(1.0, sensitivity: 0)) < 1e-9)
    }

    /// A sampled voice is silent with no instrument set, rather than falling
    /// back to something else and quietly not being a sampler.
    @Test func asampledVoiceWithNoInstrumentIsSilent() {
        let events = EventRing()
        let renderer = SynthRenderer(voice: Voice(sampled: Sampler(), envelope: .plucked),
                                     polyphony: 4, sampleRate: Self.rate, events: events)
        renderer.gain = 1
        events.push(SynthEvent(kind: .noteOn, pitch: 60, velocity: 0.9,
                               durationSamples: Int(0.3 * Self.rate)))
        var out = [Float](repeating: 0, count: 4096)
        out.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: 4096) }
        #expect(out.allSatisfy { abs($0) < 1e-9 })
    }

    /// The constraint the whole design is shaped by: recordings are far too
    /// large to travel inside a note, so what travels is only the settings.
    @Test func onlyTheSettingsRideTheRing() {
        #expect(_isPOD(Sampler.self))
        #expect(_isPOD(VoiceSource.self))
        #expect(_isPOD(Voice.self))
        #expect(_isPOD(SynthEvent.self))
    }

    /// An instrument can be built from sound a sketch made itself, which is the
    /// way in for anything Ollin does not know how to read.
    @Test func aninstrumentCanBeBuiltFromRecordingsInHand() {
        let tone = (0..<4410).map { Float(sin(Double($0) * 2 * .pi * 440 / 44100)) * 0.5 }
        let instrument = SampledInstrument(name: "mine", recordings: [
            .init(frames: tone, sampleRate: 44100, rootKey: 69, lowKey: 0, highKey: 127),
        ])
        #expect(instrument.recordingCount == 1)
        #expect(!instrument.isEmpty)
        let sound = Self.render(instrument, pitch: 69, seconds: 0.09)
        #expect(sound.contains { abs($0) > 0.05 })
    }

    @Test func thesameNotePlaysTheSameWayTwice() throws {
        let instrument = try #require(SampledInstrument.builtIn)
        #expect(Self.render(instrument, pitch: 62, seconds: 0.5)
                == Self.render(instrument, pitch: 62, seconds: 0.5))
    }
}
