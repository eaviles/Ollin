import Foundation
import Testing
@testable import OllinAudio

/// One note bent, pressed, or slid on its own among others left alone. The
/// renderer is driven directly with the events a `Synth` would send, so every
/// test here is a measurement on samples: where a note's energy sits after a
/// bend, how loud a pressed note is against its twin, what a slide lets
/// through the filter.
@Suite struct SynthExpressionTests {

    static let rate = 44100.0

    /// Something the sketch asks for, and when.
    struct Cue {
        let at: Double
        let event: SynthEvent
    }

    static func on(_ pitch: Double, id: Int, velocity: Double = 0.8, at: Double = 0) -> Cue {
        Cue(at: at, event: SynthEvent(kind: .noteOn, pitch: pitch, velocity: velocity, noteID: id))
    }

    static func off(id: Int, pitch: Double, at: Double) -> Cue {
        Cue(at: at, event: SynthEvent(kind: .noteOff, pitch: pitch, noteID: id))
    }

    static func bend(_ semitones: Double, id: Int, at: Double) -> Cue {
        Cue(at: at, event: SynthEvent(kind: .bend, noteID: id, amount: semitones))
    }

    static func press(_ pressure: Double, id: Int, at: Double) -> Cue {
        Cue(at: at, event: SynthEvent(kind: .press, noteID: id, amount: pressure))
    }

    static func slide(_ position: Double, id: Int, at: Double) -> Cue {
        Cue(at: at, event: SynthEvent(kind: .slide, noteID: id, amount: position))
    }

    /// Renders a scene: each cue lands at its time, in the blocks a live
    /// engine renders.
    static func render(_ voice: Voice, seconds: Double, drive: Double = 0.8,
                       wavetable: Wavetable? = nil, cues: [Cue]) -> [Double] {
        let events = EventRing()
        let renderer = SynthRenderer(voice: voice, polyphony: 4, sampleRate: rate, events: events)
        renderer.gain = 1
        renderer.pressure = drive
        renderer.wavetable = wavetable
        var pending = cues.sorted { $0.at < $1.at }
        var out = [Double]()
        out.reserveCapacity(Int(seconds * rate) + 512)
        let block = 512
        while out.count < Int(seconds * rate) {
            let now = Double(out.count) / rate
            while let next = pending.first, next.at <= now {
                events.push(next.event)
                pending.removeFirst()
            }
            var chunk = [Float](repeating: 0, count: block)
            chunk.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: block) }
            out += chunk.map(Double.init)
        }
        return out
    }

    static func hz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

    static func window(_ s: [Double], from: Double, to: Double) -> ArraySlice<Double> {
        let a = min(max(0, Int(from * rate)), s.count)
        let b = min(max(a, Int(to * rate)), s.count)
        return s[a..<b]
    }

    static func rms(_ s: ArraySlice<Double>) -> Double {
        guard !s.isEmpty else { return 0 }
        return (s.reduce(0) { $0 + $1 * $1 } / Double(s.count)).squareRoot()
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

    /// A plain wave that holds its level, so a spectrum reads clean.
    static let held = Voice(waveform: .sine,
                            envelope: Envelope(attack: 0.005, decay: 0, sustain: 1, release: 0.05))

    /// Two notes sound; one is bent an octave. Afterwards its energy sits an
    /// octave up and the other's has not moved, and before the bend both sat
    /// where they were struck.
    @Test func aBendReachesOneVoiceOnly() {
        let out = Self.render(Self.held, seconds: 1.2, cues: [
            Self.on(60, id: 1), Self.on(67, id: 2), Self.bend(12, id: 1, at: 0.3),
        ])
        let early = Self.window(out, from: 0.1, to: 0.28)
        #expect(Self.magnitude(early, at: Self.hz(60)) > 20 * Self.magnitude(early, at: Self.hz(72)))

        let late = Self.window(out, from: 0.7, to: 1.2)
        let bent = Self.magnitude(late, at: Self.hz(72))
        let still = Self.magnitude(late, at: Self.hz(67))
        let gone = Self.magnitude(late, at: Self.hz(60))
        #expect(bent > 20 * gone)
        #expect(still > 20 * gone)
        #expect(abs(bent - still) < 0.2 * still)
    }

    /// A bent note is still let go, by the value the sketch holds and by the
    /// pitch it started on alike, and the other note keeps sounding.
    @Test func aBentNoteIsStillLetGo() {
        for byHandle in [true, false] {
            let release = byHandle ? Self.off(id: 1, pitch: 60, at: 0.6) : Self.off(id: 0, pitch: 60, at: 0.6)
            let out = Self.render(Self.held, seconds: 1.5, cues: [
                Self.on(60, id: 1), Self.on(67, id: 2), Self.bend(12, id: 1, at: 0.2), release,
            ])
            let late = Self.window(out, from: 1.0, to: 1.5)
            let bent = Self.magnitude(late, at: Self.hz(72))
            let still = Self.magnitude(late, at: Self.hz(67))
            #expect(still > 20 * bent, "released \(byHandle ? "by handle" : "by pitch")")
        }
    }

    /// A bend sent for no note in particular moves every note.
    @Test func theWholeInstrumentBends() {
        let all = Cue(at: 0.3, event: SynthEvent(kind: .bend, noteID: 0, amount: 2))
        let out = Self.render(Self.held, seconds: 1.2, cues: [Self.on(60, id: 1), Self.on(67, id: 2), all])
        let late = Self.window(out, from: 0.7, to: 1.2)
        #expect(Self.magnitude(late, at: Self.hz(62)) > 20 * Self.magnitude(late, at: Self.hz(60)))
        #expect(Self.magnitude(late, at: Self.hz(69)) > 20 * Self.magnitude(late, at: Self.hz(67)))
    }

    /// Every source that is cut to length when a note starts follows a bend
    /// while it sounds: the plucked string, the bowed string, the blown tube,
    /// a wavetable, and a patch each move their energy an octave up.
    @Test func everyModelFollowsABend() {
        let cases: [(name: String, voice: Voice, table: Wavetable?)] = [
            ("plucked", .nylon, nil),
            ("bowed", .cello, nil),
            ("blown", .clarinet, nil),
            ("wavetable", Voice(wavetable: WavetableScan()), .basic),
            ("patch", Voice(patch: .brass), nil),
        ]
        for scene in cases {
            let out = Self.render(scene.voice, seconds: 1.3, wavetable: scene.table, cues: [
                Self.on(60, id: 1, velocity: 0.9), Self.bend(12, id: 1, at: 0.4),
            ])
            let late = Self.window(out, from: 0.8, to: 1.3)
            let up = Self.magnitude(late, at: Self.hz(72))
            let down = Self.magnitude(late, at: Self.hz(60))
            #expect(up > 3 * down, "\(scene.name): \(up) at the octave against \(down) where it started")
        }
    }

    /// A struck body holds its pitch: its tones were decided by the strike.
    @Test func aStruckBodyHoldsItsPitch() {
        let out = Self.render(.chime, seconds: 1.0, cues: [
            Self.on(72, id: 1, velocity: 0.9), Self.bend(12, id: 1, at: 0.2),
        ])
        let late = Self.window(out, from: 0.5, to: 1.0)
        #expect(Self.magnitude(late, at: Self.hz(72)) > 3 * Self.magnitude(late, at: Self.hz(84)))
    }

    /// A press on a bowed note is that note's bow. Pressed to nothing it goes
    /// silent while its neighbor, still on the instrument's bow, sounds; and
    /// a press equal to the instrument's bow is the same sound exactly.
    @Test func aPressDrivesOneBowedNote() {
        let both = Self.render(.cello, seconds: 1.2, cues: [Self.on(48, id: 1), Self.on(55, id: 2)])
        let oneLifted = Self.render(.cello, seconds: 1.2, cues: [
            Self.on(48, id: 1), Self.on(55, id: 2), Self.press(0, id: 2, at: 0),
        ])
        let late = 0.7...1.2
        let lowBefore = Self.magnitude(Self.window(both, from: late.lowerBound, to: late.upperBound), at: Self.hz(48))
        let highBefore = Self.magnitude(Self.window(both, from: late.lowerBound, to: late.upperBound), at: Self.hz(55))
        let lowAfter = Self.magnitude(Self.window(oneLifted, from: late.lowerBound, to: late.upperBound), at: Self.hz(48))
        let highAfter = Self.magnitude(Self.window(oneLifted, from: late.lowerBound, to: late.upperBound), at: Self.hz(55))
        #expect(highAfter < 0.05 * highBefore)
        #expect(lowAfter > 0.5 * lowBefore)

        let same = Self.render(.cello, seconds: 0.6, cues: [Self.on(48, id: 1), Self.press(0.8, id: 1, at: 0)])
        let plain = Self.render(.cello, seconds: 0.6, cues: [Self.on(48, id: 1)])
        #expect(same == plain)
    }

    /// On a voice that is set going once, a press raises the note from the
    /// level it was struck at toward full, by the voice's pressure amount;
    /// at zero amount, or unpressed, the note is exactly what it was.
    @Test func aPressRaisesAStruckLevel() {
        var voice = Self.held
        voice.pressureAmount = 1
        let soft = Self.render(voice, seconds: 0.6, cues: [Self.on(60, id: 1, velocity: 0.4)])
        let pressed = Self.render(voice, seconds: 0.6, cues: [
            Self.on(60, id: 1, velocity: 0.4), Self.press(1, id: 1, at: 0),
        ])
        let quiet = Self.rms(Self.window(soft, from: 0.2, to: 0.6))
        let loud = Self.rms(Self.window(pressed, from: 0.2, to: 0.6))
        #expect(abs(loud / quiet - 2.5) < 0.1)

        let halfway = Self.render(voice, seconds: 0.6, cues: [
            Self.on(60, id: 1, velocity: 0.4), Self.press(0.5, id: 1, at: 0),
        ])
        #expect(abs(Self.rms(Self.window(halfway, from: 0.2, to: 0.6)) / quiet - 1.75) < 0.1)

        voice.pressureAmount = 0
        let ignored = Self.render(voice, seconds: 0.6, cues: [
            Self.on(60, id: 1, velocity: 0.4), Self.press(1, id: 1, at: 0),
        ])
        let untouched = Self.render(voice, seconds: 0.6, cues: [Self.on(60, id: 1, velocity: 0.4)])
        #expect(ignored == untouched)
    }

    /// A slide opens the filter above the middle of the key and closes it
    /// below; at rest it is exactly the filter the note started with.
    @Test func aSlideMovesTheFilter() {
        let filter = Voice.Filter(mode: .lowpass, cutoff: 300, resonance: 0.1, slideAmount: 2)
        let voice = Voice(waveform: .sawtooth,
                          envelope: Envelope(attack: 0.005, decay: 0, sustain: 1, release: 0.05),
                          filter: filter)
        let eighth = Self.hz(45) * 8      // 880 Hz, well above a 300 Hz cutoff
        let plain = Self.render(voice, seconds: 0.8, cues: [Self.on(45, id: 1)])
        let opened = Self.render(voice, seconds: 0.8, cues: [Self.on(45, id: 1), Self.slide(1, id: 1, at: 0)])
        let closed = Self.render(voice, seconds: 0.8, cues: [Self.on(45, id: 1), Self.slide(0, id: 1, at: 0)])
        let rest = Self.render(voice, seconds: 0.8, cues: [Self.on(45, id: 1), Self.slide(0.5, id: 1, at: 0)])
        let through = Self.magnitude(Self.window(plain, from: 0.3, to: 0.8), at: eighth)
        let more = Self.magnitude(Self.window(opened, from: 0.3, to: 0.8), at: eighth)
        let less = Self.magnitude(Self.window(closed, from: 0.3, to: 0.8), at: eighth)
        #expect(more > 4 * through)
        #expect(less < 0.5 * through)
        #expect(rest == plain)
    }

    /// A note that is never bent, pressed, or slid sounds exactly as it did
    /// before notes had numbers: the identity costs nothing.
    @Test func anUnexpressedChordIsUnchanged() {
        let numbered = Self.render(.pluck, seconds: 0.8, cues: [
            Self.on(60, id: 1), Self.on(64, id: 2, at: 0.1), Self.on(67, id: 3, at: 0.2),
            Self.off(id: 2, pitch: 64, at: 0.5),
        ])
        let unnumbered = Self.render(.pluck, seconds: 0.8, cues: [
            Self.on(60, id: 0), Self.on(64, id: 0, at: 0.1), Self.on(67, id: 0, at: 0.2),
            Self.off(id: 0, pitch: 64, at: 0.5),
        ])
        #expect(numbered == unnumbered)
        #expect(Self.rms(Self.window(numbered, from: 0.3, to: 0.5)) > 0.01)
    }

    /// An expression sent with a note's first block lands whole rather than
    /// gliding from nothing: a controller says where the finger is before it
    /// says the finger is down.
    @Test func anExpressionSentWithTheNoteLandsWhole() {
        let out = Self.render(Self.held, seconds: 0.3, cues: [Self.on(60, id: 1), Self.bend(12, id: 1, at: 0)])
        let first = Self.window(out, from: 0.02, to: 0.1)
        #expect(Self.magnitude(first, at: Self.hz(72)) > 20 * Self.magnitude(first, at: Self.hz(60)))
    }
}
