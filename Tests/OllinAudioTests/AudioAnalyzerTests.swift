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
