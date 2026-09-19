import Foundation
import Testing
@testable import OllinAudio

/// The listening side's pitch reads, proven on rendered signals: a tone reads
/// its own frequency to within a few cents with the confidence of a pure
/// tone, a note with harmonics reads its fundamental rather than any one of
/// them (a fundamental that is not even there included), the tuner's two
/// numbers come out right, a sweep across five octaves of sines and sawtooths
/// never lands an octave off, silence and noise read as no note at all, the
/// reading follows the window as chunks arrive, a chord's twelve classes peak
/// on its notes and nowhere else with every octave folded onto one wheel, and
/// the longer ring the pitch window needs leaves the older reads untouched.
/// No hardware and no GPU.
@Suite
struct PitchTests {

    static let sampleRate = 44100.0
    /// Enough samples to fill the ring, so a single call is a whole window.
    static let count = 4096

    static func sine(_ frequency: Double, amplitude: Double = 0.5, count: Int = count) -> [Float] {
        (0..<count).map { Float(sin(Double($0) / sampleRate * frequency * 2 * .pi) * amplitude) }
    }

    /// A sawtooth built from its harmonics, so it is exactly periodic and
    /// stops short of the Nyquist frequency.
    static func sawtooth(_ frequency: Double, amplitude: Double = 0.5, count: Int = count) -> [Float] {
        let harmonics = max(1, min(40, Int(20000 / frequency)))
        return (0..<count).map { index in
            let t = Double(index) / sampleRate
            var sum = 0.0
            for k in 1...harmonics {
                sum += sin(t * frequency * Double(k) * 2 * .pi) / Double(k)
            }
            return Float(sum * amplitude * 2 / .pi)
        }
    }

    static func chord(_ frequencies: [Double], count: Int = count) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        for f in frequencies {
            for (i, s) in sine(f, amplitude: 0.3, count: count).enumerated() { out[i] += s }
        }
        return out
    }

    /// Deterministic white noise, hashed from the sample index.
    static func noise(count: Int = count) -> [Float] {
        (0..<count).map { i in
            var x = UInt64(truncatingIfNeeded: i) &* 0x9E3779B97F4A7C15
            x ^= x >> 29
            x &*= 0xBF58476D1CE4E5B9
            x ^= x >> 32
            return Float(Double(x >> 40) / Double(1 << 23) - 1) * 0.5
        }
    }

    static func analyzer() -> AudioAnalyzer {
        AudioAnalyzer(fftSize: 1024, sampleRate: sampleRate, smoothing: 0)
    }

    static func feed(_ samples: [Float], to analyzer: AudioAnalyzer) {
        samples.withUnsafeBufferPointer { analyzer.analyze(samples: $0.baseAddress!, count: $0.count) }
    }

    static func cents(_ read: Double, from truth: Double) -> Double {
        1200 * log2(read / truth)
    }

    // MARK: - One note

    /// A pure tone reads its own frequency to within a few cents across the
    /// range a voice or an instrument uses, and with the confidence of a pure
    /// tone.
    @Test func aSineReadsItsOwnFrequency() throws {
        for frequency in [82.41, 110.0, 220.0, 440.0, 880.0, 1760.0] {
            let analyzer = Self.analyzer()
            Self.feed(Self.sine(frequency), to: analyzer)
            let heard = try #require(analyzer.pitch)
            #expect(abs(Self.cents(heard.frequency, from: frequency)) < 3)
            #expect(heard.confidence > 0.95)
        }
    }

    /// A note with harmonics reads its fundamental, not its loudest partial.
    @Test func aSawtoothReadsItsFundamental() throws {
        let analyzer = Self.analyzer()
        Self.feed(Self.sawtooth(196), to: analyzer)
        let heard = try #require(analyzer.pitch)
        #expect(abs(Self.cents(heard.frequency, from: 196)) < 3)
        #expect(heard.confidence > 0.9)
        #expect(heard.nearestPitch == Pitch(name: "G3"))
    }

    /// The period of a note is there even when the fundamental is not: a sound
    /// made of the second, third, and fourth harmonics alone still reads at
    /// the fundamental, which is what the ear hears too.
    @Test func aNoteWithItsFundamentalMissingStillReadsAtIt() throws {
        let analyzer = Self.analyzer()
        Self.feed(Self.chord([300, 450, 600]), to: analyzer)
        let heard = try #require(analyzer.pitch)
        #expect(abs(Self.cents(heard.frequency, from: 150)) < 5)
        #expect(heard.confidence > 0.9)
    }

    /// The tuner's two numbers: the nearest note and the cents away from it,
    /// signed, with `midi` putting them back together and `note` the short
    /// form of the note alone.
    @Test func theNoteAndTheCents() throws {
        let sharp = Self.analyzer()
        Self.feed(Self.sine(445), to: sharp)
        let heardSharp = try #require(sharp.pitch)
        #expect(heardSharp.nearestPitch == Pitch(name: "A4"))
        #expect(abs(heardSharp.cents - 19.56) < 1)
        #expect(abs(heardSharp.midi - (69 + 0.1956)) < 0.01)
        #expect(sharp.nearestPitch == heardSharp.nearestPitch)

        let flat = Self.analyzer()
        Self.feed(Self.sine(430), to: flat)
        let heardFlat = try #require(flat.pitch)
        #expect(heardFlat.nearestPitch == Pitch(name: "A4"))
        #expect(abs(heardFlat.cents - -39.80) < 1)

        let middle = Self.analyzer()
        Self.feed(Self.sine(261.63), to: middle)
        let heardMiddle = try #require(middle.pitch)
        #expect(heardMiddle.nearestPitch == Pitch(name: "C4"))
        #expect(abs(heardMiddle.cents) < 1)
        #expect("\(heardMiddle.nearestPitch)" == "C4")
    }

    /// Across five octaves in quarter-tone steps, sines and sawtooths alike,
    /// no reading lands more than half a semitone off, and every one is heard.
    /// The threshold step is what keeps an octave below the note from
    /// winning; this sweep is the proof that it does.
    @Test func octaveErrorsStayUnderABound() {
        var readings = 0
        var gross = 0
        var missed = 0
        var step = 0
        while true {
            let frequency = 60 * pow(2, Double(step) / 24)
            if frequency > 2000 { break }
            step += 1
            for signal in [Self.sine(frequency), Self.sawtooth(frequency)] {
                let analyzer = Self.analyzer()
                Self.feed(signal, to: analyzer)
                readings += 1
                guard let heard = analyzer.pitch else { missed += 1; continue }
                if abs(Self.cents(heard.frequency, from: frequency)) > 50 { gross += 1 }
            }
        }
        #expect(readings > 200)
        #expect(missed == 0)
        #expect(gross == 0)
    }

    /// Silence and noise read as no note at all, in both reads.
    @Test func silenceAndNoiseHearNoNote() {
        let quiet = Self.analyzer()
        Self.feed([Float](repeating: 0, count: Self.count), to: quiet)
        #expect(quiet.pitch == nil)
        #expect(quiet.nearestPitch == nil)
        #expect(quiet.chroma == [Float](repeating: 0, count: 12))

        let hiss = Self.analyzer()
        Self.feed(Self.noise(), to: hiss)
        #expect(hiss.pitch == nil)
        #expect(hiss.nearestPitch == nil)

        // Nothing has arrived at all: the same answer, from an empty window.
        let untouched = Self.analyzer()
        #expect(untouched.pitch == nil)
        #expect(untouched.chroma.count == 12)
    }

    /// The reading follows the window as chunks arrive the way a live tap
    /// delivers them: a new note is heard once the window has slid onto it,
    /// and the reading between chunks is the same value, not a fresh guess.
    @Test func theReadingFollowsTheWindow() throws {
        let analyzer = Self.analyzer()
        Self.feed(Self.sine(220), to: analyzer)
        #expect(analyzer.nearestPitch == Pitch(name: "A3"))
        let held = analyzer.pitch
        #expect(analyzer.pitch == held)

        let chunk = 735
        let next = Self.sine(330, count: chunk * 6)
        var heardE4At = -1
        for k in 0..<6 {
            let slice = Array(next[(k * chunk)..<((k + 1) * chunk)])
            Self.feed(slice, to: analyzer)
            if heardE4At < 0, analyzer.nearestPitch == Pitch(name: "E4") { heardE4At = k + 1 }
        }
        // The window is 2,204 samples, three chunks; the fourth is fully E4.
        #expect(heardE4At > 0)
        #expect(heardE4At <= 4)
        let heard = try #require(analyzer.pitch)
        #expect(abs(Self.cents(heard.frequency, from: 330)) < 3)
    }

    // MARK: - Twelve classes

    /// A chord's classes peak on its notes and nowhere else.
    @Test func chromaOfAChordPeaksOnItsNotes() {
        let analyzer = Self.analyzer()
        Self.feed(Self.chord([261.63, 329.63, 392.00]), to: analyzer)   // C4 E4 G4
        let chroma = analyzer.chroma
        #expect(chroma.count == 12)
        for index in [0, 4, 7] { #expect(chroma[index] >= 0.5) }
        for index in 0..<12 where ![0, 4, 7].contains(index) { #expect(chroma[index] <= 0.15) }
        #expect(chroma.max() == 1)
    }

    /// Every octave lands on the same twelve: three As two octaves apart are
    /// one class, at 1.
    @Test func chromaFoldsOctaves() {
        let analyzer = Self.analyzer()
        Self.feed(Self.chord([110, 440, 880]), to: analyzer)
        let chroma = analyzer.chroma
        #expect(chroma[9] == 1)
        for index in 0..<12 where index != 9 { #expect(chroma[index] <= 0.05) }
    }

    /// A single note is one class, whatever its octave, and a note between
    /// two names goes to the nearer.
    @Test func chromaOfASingleNoteIsOneClass() {
        let sharp = Self.analyzer()
        Self.feed(Self.sine(554.37), to: sharp)                           // C#5
        let chroma = sharp.chroma
        #expect(chroma[1] == 1)
        for index in 0..<12 where index != 1 { #expect(chroma[index] <= 0.05) }

        let leaning = Self.analyzer()
        Self.feed(Self.sine(445), to: leaning)                             // A4, 20 cents sharp
        #expect(leaning.chroma[9] == 1)
    }

    // MARK: - The ring under the older reads

    /// A chunk longer than the FFT window but shorter than the ring still
    /// reads its last windowful: the waveform is those samples and the
    /// amplitude their level, exactly as before the ring grew.
    @Test func aLongChunkStillReadsItsLastWindow() {
        let analyzer = Self.analyzer()
        let long = (0..<3000).map { Float($0 % 7) / 7 - 0.5 }
        Self.feed(long, to: analyzer)
        let wave = analyzer.waveform
        #expect(wave.count == 1024)
        #expect(wave == Array(long.suffix(1024)))
        let tail = long.suffix(1024)
        let rms = (tail.map { Double($0 * $0) }.reduce(0, +) / 1024).squareRoot()
        #expect(abs(Double(analyzer.amplitude) - rms) < 1e-5)
    }
}
