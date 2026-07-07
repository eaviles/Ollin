import Foundation
import Testing
import Ollin
@testable import OllinAudio

/// `Soundtrack` over a stand-in tap source: no real player, just the seam.
/// Confirms the tap slot is claimed and released, samples reach the analyzer,
/// and the analyzer is rebuilt to the stream's real sample rate.
@MainActor
@Suite struct SoundtrackTests {

    /// The smallest possible `AudioTapSource`: a slot and nothing else.
    final class StubTapSource: AudioTapSource {
        var audioTap: AudioTap?
    }

    @Test func claimsAnalyzesAndDetaches() async throws {
        let source = StubTapSource()
        let sound = Soundtrack(of: source, fftSize: 512, smoothing: 0)
        let tap = try #require(source.audioTap)

        // Feed a loud 440 Hz sine at 44.1 kHz from off the main thread, the
        // way a real source's audio thread would.
        let samples = (0..<512).map { Float(sin(Double($0) / 44100 * 440 * 2 * .pi)) }
        await Task.detached {
            samples.withUnsafeBufferPointer { tap($0, 44100) }
        }.value

        // The placeholder analyzer guessed 48 kHz; the tap's first delivery
        // rebuilds it at the real rate, and the samples land.
        #expect(sound.analyzer.sampleRate == 44100)
        #expect(sound.amplitude > 0.5)

        sound.detach()
        #expect(source.audioTap == nil)
    }

    @Test func tuningSurvivesTheSampleRateRebuild() async throws {
        let source = StubTapSource()
        let sound = Soundtrack(of: source, fftSize: 512)
        sound.smoothing = 0.25
        sound.beatSensitivity = 2.5
        let tap = try #require(source.audioTap)

        let silence = [Float](repeating: 0, count: 512)
        await Task.detached {
            silence.withUnsafeBufferPointer { tap($0, 44100) }
        }.value

        #expect(sound.analyzer.sampleRate == 44100)
        #expect(sound.smoothing == 0.25)
        #expect(sound.beatSensitivity == 2.5)
    }
}
