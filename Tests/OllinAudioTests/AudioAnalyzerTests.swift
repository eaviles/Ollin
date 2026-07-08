import Foundation
import Testing
@testable import OllinAudio

/// Pure-DSP checks on the audio analyzer: feed synthesized signals and confirm
/// the amplitude and the spectrum land where they should. No audio hardware and
/// no GPU, so these run everywhere including CI.
@Suite
struct AudioAnalyzerTests {

    static let sampleRate = 44100.0
    static let fftSize = 1024

    /// A pure sine at amplitude `amp` and `frequency` Hz, `count` samples long.
    static func sine(frequency: Double, amplitude amp: Double, count: Int) -> [Float] {
        let inc = 2.0 * Double.pi * frequency / sampleRate
        return (0..<count).map { Float(sin(Double($0) * inc) * amp) }
    }

    /// A full window of a sine whose frequency sits exactly on a bin should peak
    /// in that bin.
    @Test func spectrumPeaksAtTheToneBin() {
        let analyzer = AudioAnalyzer(fftSize: Self.fftSize, sampleRate: Self.sampleRate, smoothing: 0)
        let targetBin = 40
        let freq = Double(targetBin) * Self.sampleRate / Double(Self.fftSize)
        let samples = Self.sine(frequency: freq, amplitude: 0.8, count: Self.fftSize)
        samples.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }

        let spectrum = analyzer.spectrum
        #expect(spectrum.count == Self.fftSize / 2)
        let peak = spectrum.firstIndex(of: spectrum.max()!)!
        #expect(abs(peak - targetBin) <= 1)
    }

    /// With no smoothing, the reported amplitude is the RMS of the input — about
    /// `amp / √2` for a sine.
    @Test func amplitudeTracksRMS() {
        let analyzer = AudioAnalyzer(fftSize: Self.fftSize, sampleRate: Self.sampleRate, smoothing: 0)
        let amp = 0.5
        let samples = Self.sine(frequency: 1000, amplitude: amp, count: Self.fftSize)
        samples.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }

        let expected = Float(amp / 2.0.squareRoot())
        #expect(abs(analyzer.amplitude - expected) < 0.01)
    }

    /// Silence reads as zero amplitude and (near-)zero everywhere in the spectrum.
    @Test func silenceIsQuiet() {
        let analyzer = AudioAnalyzer(fftSize: Self.fftSize, sampleRate: Self.sampleRate, smoothing: 0)
        let samples = [Float](repeating: 0, count: Self.fftSize)
        samples.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }

        #expect(analyzer.amplitude == 0)
        #expect((analyzer.spectrum.max() ?? 0) < 1e-6)
    }

    /// A band query covering the tone reads louder than a band well away from it.
    @Test func bandQueryIsolatesEnergy() {
        let analyzer = AudioAnalyzer(fftSize: Self.fftSize, sampleRate: Self.sampleRate, smoothing: 0)
        let samples = Self.sine(frequency: 5000, amplitude: 0.8, count: Self.fftSize)
        samples.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }

        let onTone = analyzer.magnitude(in: 4500...5500)
        let offTone = analyzer.magnitude(in: 200...400)
        #expect(onTone > offTone * 5)
    }

    /// `bands(_:)` returns normalized values, with the band covering the tone the
    /// loudest.
    @Test func bandsNormalizeAndPeakAtTheTone() {
        let analyzer = AudioAnalyzer(fftSize: Self.fftSize, sampleRate: Self.sampleRate, smoothing: 0)
        let freq = 2000.0
        let samples = Self.sine(frequency: freq, amplitude: 0.8, count: Self.fftSize)
        samples.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }

        // Let the attack/release envelope settle on the steady spectrum.
        let count = 32
        var bands = analyzer.bands(count)
        for _ in 0..<20 { bands = analyzer.bands(count) }

        #expect(bands.count == count)
        #expect(bands.allSatisfy { $0 >= 0 && $0 <= 1.0001 })

        // The loudest band should be the one whose log-spaced range holds 2 kHz.
        let loHz = 40.0, hiHz = min(16000.0, Self.sampleRate * 0.5 * 0.98)
        let expected = Int(Double(count) * log(freq / loHz) / log(hiHz / loHz))
        let peak = bands.firstIndex(of: bands.max()!)!
        #expect(abs(peak - expected) <= 1)
        #expect(bands.max()! > 0.5)
    }

    /// Silence yields (near-)zero bands.
    @Test func bandsAreZeroOnSilence() {
        let analyzer = AudioAnalyzer(fftSize: Self.fftSize, sampleRate: Self.sampleRate, smoothing: 0)
        let silence = [Float](repeating: 0, count: Self.fftSize)
        for _ in 0..<10 {
            silence.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }
        }
        var bands = analyzer.bands(24)
        for _ in 0..<20 { bands = analyzer.bands(24) }
        #expect((bands.max() ?? 0) < 0.01)
    }

    /// A loud hit after silence registers a beat; repeated, spaced hits register
    /// repeated beats; pure silence registers none.
    @Test func beatDetectsOnsets() {
        let analyzer = AudioAnalyzer(fftSize: Self.fftSize, sampleRate: Self.sampleRate, smoothing: 0)
        let loud = Self.sine(frequency: 1000, amplitude: 0.8, count: Self.fftSize)
        let quiet = [Float](repeating: 0, count: Self.fftSize)

        // Five loud buffers, each followed by silence well past the refractory.
        for _ in 0..<5 {
            loud.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }
            for _ in 0..<7 {
                quiet.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }
            }
        }
        #expect(analyzer.beatCount >= 3)
    }

    @Test func silenceHasNoBeats() {
        let analyzer = AudioAnalyzer(fftSize: Self.fftSize, sampleRate: Self.sampleRate, smoothing: 0)
        let quiet = [Float](repeating: 0, count: Self.fftSize)
        for _ in 0..<40 {
            quiet.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }
        }
        #expect(analyzer.beatCount == 0)
    }

    // MARK: Beat clock, threshold, and waveform semantics

    /// A tiny synthesized band, the deterministic stand-in for a microphone:
    /// optionally a kick drum every half second (a 55 Hz thump plus a 2.8 kHz
    /// click, both with sharp decays) over a held bass note, a steady mid tone,
    /// and a whisper of hiss.
    static func band(seconds: Double, gain: Double = 1, kick: Bool = true) -> [Float] {
        let count = Int(sampleRate * seconds)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            var s = 0.0
            if kick {
                let sinceKick = t.truncatingRemainder(dividingBy: 0.5)
                s += sin(t * 55 * 2 * .pi) * 0.6 * exp(-sinceKick * 9)
                s += sin(t * 2800 * 2 * .pi) * 0.3 * exp(-sinceKick * 70)
            }
            s += sin(t * 110 * 2 * .pi) * 0.2
            s += sin(t * 330 * 2 * .pi) * 0.16
            s += white(i) * 0.02
            out[i] = Float(s * gain)
        }
        return out
    }

    /// Deterministic white noise, hashed from the sample index.
    static func white(_ i: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: i) &* 0x9E3779B97F4A7C15
        x ^= x >> 29
        x &*= 0xBF58476D1CE4E5B9
        x ^= x >> 32
        return Double(x >> 40) / Double(1 << 23) - 1
    }

    /// Feeds a signal in 60 fps-sized chunks (the way a live tap delivers it)
    /// and returns the sample position of each detected beat.
    static func beatPositions(of signal: [Float], analyzer: AudioAnalyzer) -> [Int] {
        let chunk = Int(sampleRate / 60)
        var positions: [Int] = []
        var last = 0
        var offset = 0
        while offset < signal.count {
            let take = min(chunk, signal.count - offset)
            signal.withUnsafeBufferPointer {
                analyzer.process(samples: $0.baseAddress! + offset, count: take)
            }
            offset += take
            if analyzer.beatCount > last {
                last = analyzer.beatCount
                positions.append(offset)
            }
        }
        return positions
    }

    /// Every half-second kick lands as a beat at default sensitivity, each
    /// detection within a chunk or two of the kick itself, and nothing fires
    /// between kicks. This is the scenario that used to false-fire: steady
    /// tones between the kicks let the old relative-only threshold collapse.
    @Test func kicksOverSteadyTonesDetectCleanly() {
        let analyzer = AudioAnalyzer(fftSize: 2048, sampleRate: Self.sampleRate, smoothing: 0)
        let beats = Self.beatPositions(of: Self.band(seconds: 6), analyzer: analyzer)

        #expect(beats.count == 12)
        for position in beats {
            let sinceKick = (Double(position) / Self.sampleRate)
                .truncatingRemainder(dividingBy: 0.5)
            #expect(sinceKick < 0.06)
        }
    }

    /// Steady material (held tones, no transients) must not accumulate beats.
    /// The one allowed detection is the very start, where the tones switching
    /// on is a genuine onset.
    @Test func steadyMaterialDoesNotFalseFire() {
        let analyzer = AudioAnalyzer(fftSize: 2048, sampleRate: Self.sampleRate, smoothing: 0)
        let beats = Self.beatPositions(of: Self.band(seconds: 6, kick: false), analyzer: analyzer)

        #expect(beats.count <= 1)
        if let first = beats.first {
            #expect(Double(first) / Self.sampleRate < 0.1)
        }
    }

    /// The same band ten times quieter yields the same beats at the same
    /// positions: the log-compressed flux makes the threshold gain-invariant.
    @Test func beatsAreVolumeInvariant() {
        let loud = AudioAnalyzer(fftSize: 2048, sampleRate: Self.sampleRate, smoothing: 0)
        let quiet = AudioAnalyzer(fftSize: 2048, sampleRate: Self.sampleRate, smoothing: 0)
        let loudBeats = Self.beatPositions(of: Self.band(seconds: 6), analyzer: loud)
        let quietBeats = Self.beatPositions(of: Self.band(seconds: 6, gain: 0.1), analyzer: quiet)

        #expect(loudBeats == quietBeats)
    }

    /// `timeSinceBeat` runs on the sample clock: after a beat, feeding k more
    /// buffers reads exactly k · fftSize / sampleRate seconds, no wall clock
    /// involved.
    @Test func beatClockIsSampleAccurate() {
        let analyzer = AudioAnalyzer(fftSize: Self.fftSize, sampleRate: Self.sampleRate, smoothing: 0)
        let loud = Self.sine(frequency: 1000, amplitude: 0.8, count: Self.fftSize)
        let quiet = [Float](repeating: 0, count: Self.fftSize)

        #expect(analyzer.timeSinceBeat == .greatestFiniteMagnitude)
        #expect(analyzer.beat == 0)

        for _ in 0..<5 {
            quiet.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }
        }
        loud.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }
        #expect(analyzer.beatCount == 1)
        #expect(analyzer.timeSinceBeat == 0)
        #expect(analyzer.beat == 1)

        let k = 8
        for _ in 0..<k {
            quiet.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }
        }
        #expect(analyzer.timeSinceBeat == Double(k * Self.fftSize) / Self.sampleRate)
    }

    /// `waveform` is a rolling window of the last `fftSize` samples, oldest
    /// first, sliding across chunk boundaries.
    @Test func waveformIsARollingWindow() {
        let analyzer = AudioAnalyzer(fftSize: Self.fftSize, sampleRate: Self.sampleRate, smoothing: 0)
        let half = Self.fftSize / 2
        let a = [Float](repeating: 0.25, count: half)
        let b = [Float](repeating: 0.5, count: half)
        let c = [Float](repeating: 0.75, count: half)

        a.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }
        b.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }
        var wave = analyzer.waveform
        #expect(wave.count == Self.fftSize)
        #expect(wave[0..<half].allSatisfy { $0 == 0.25 })
        #expect(wave[half...].allSatisfy { $0 == 0.5 })

        c.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }
        wave = analyzer.waveform
        #expect(wave[0..<half].allSatisfy { $0 == 0.5 })
        #expect(wave[half...].allSatisfy { $0 == 0.75 })
    }

    /// Smoothing damps the response: one frame of loud input lands only partway
    /// toward the true level.
    @Test func smoothingDampsResponse() {
        let analyzer = AudioAnalyzer(fftSize: Self.fftSize, sampleRate: Self.sampleRate, smoothing: 0.8)
        let samples = Self.sine(frequency: 1000, amplitude: 0.9, count: Self.fftSize)
        samples.withUnsafeBufferPointer { analyzer.process(samples: $0.baseAddress!, count: $0.count) }

        let rms = Float(0.9 / 2.0.squareRoot())
        // After one frame from zero with a=0.8, amplitude ≈ 0.2 * rms.
        #expect(analyzer.amplitude < rms * 0.5)
        #expect(analyzer.amplitude > 0)
    }
}
