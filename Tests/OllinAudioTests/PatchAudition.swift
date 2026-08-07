import AVFoundation
import Foundation
import Testing
@testable import OllinAudio

/// The numbers say a modulated sine has harmonics in it. Whether the result is
/// an instrument is a different question, and this is how it gets asked.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/patch.wav swift test --filter PatchAudition
/// ```
@Suite struct PatchAudition {

    static let rate = 44100.0

    static func play(_ voice: Voice, _ notes: [(Double, Double, Double)],
                     tail: Double = 1.4, gain: Double = 0.6) -> [Float] {
        let events = EventRing(capacity: 2048)
        let renderer = SynthRenderer(voice: voice, polyphony: 16,
                                     sampleRate: rate, events: events)
        renderer.gain = gain
        var pending = notes.sorted { $0.0 < $1.0 }
        let span = (notes.map { $0.0 + $0.2 }.max() ?? 1) + tail
        var out = [Float]()
        var elapsed = 0.0
        let block = 512
        while elapsed < span {
            while let next = pending.first, next.0 <= elapsed {
                events.push(SynthEvent(kind: .noteOn, pitch: next.1, velocity: 0.85,
                                       durationSamples: Int(next.2 * rate)))
                pending.removeFirst()
            }
            var chunk = [Float](repeating: 0, count: block)
            chunk.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: block) }
            out += chunk
            elapsed += Double(block) / rate
        }
        return out
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        var samples = [Float]()

        /// The same short phrase every time, so only the patch differs.
        let phrase: [(Double, Double, Double)] = [
            (0, 60, 0.5), (0.55, 67, 0.5), (1.1, 64, 0.5), (1.65, 72, 1.1),
        ]

        let takes: [(String, Patch, Envelope)] = [
            ("one sine, nothing pushing it", .tone(.sine), .organ),
            ("pushed at the same frequency, gently", Patch.tone(.sine)
                .modulated(by: .tone(.sine, ratio: 1), index: 1), .organ),
            ("pushed harder, same patch", Patch.tone(.sine)
                .modulated(by: .tone(.sine, ratio: 1), index: 5), .organ),
            ("pushed an octave up: brass", .brass, .standard),
            ("pushed at three and a half: a bell", .bell, .percussive),
            ("pushed at five and a bit, so it drifts", .glass, .swell),
            ("one operator pushing itself", .buzz, .organ),
            ("a body and a strike, heard together", .struck, .percussive),
            ("three deep: pushed by something itself pushed", Patch.tone(.sine)
                .modulated(by: Patch.tone(.sine, ratio: 2)
                    .modulated(by: .tone(.sine, ratio: 7), index: 2), index: 3), .percussive),
        ]

        for (name, patch, envelope) in takes {
            samples += Self.play(Voice(patch: patch, envelope: envelope, gain: 0.7), phrase)
            samples += [Float](repeating: 0, count: Int(0.3 * Self.rate))
            print("  take: \(name) (\(patch.count) operators)")
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 1)!
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path),
                                   settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                      frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)

        print("audition: \(Double(samples.count) / Self.rate) s to \(path)")
        #expect(samples.count > Int(Self.rate))
        #expect(samples.contains { abs($0) > 0.02 })
    }
}
