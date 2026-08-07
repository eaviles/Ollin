import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The tests say two orders of the same chain export to different samples.
/// Whether the difference is the one claimed is something only listening
/// settles, and this is how it gets asked.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/effects.wav swift test --filter EffectChainAudition
/// ```
///
/// Rendered through the export path, which builds the chain the same way the
/// output does.
@Suite(.serialized) struct EffectChainAudition {

    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let rate = 44100.0

        /// One short phrase through a chain, rendered as an export would.
        func take(_ effects: [Effect], voice: Voice = .stab) -> [Float] {
            let synth = Synth(voice, polyphony: 12)
            synth.gain = 0.55
            synth.effects = effects
            OllinApp.isRenderingHeadless = true
            let notes: [(Double, Double)] = [(0, 60), (0.4, 67), (0.8, 63), (1.2, 70)]
            var pending = notes
            var elapsed = 0.0
            while elapsed < 4.0 {
                while let next = pending.first, next.0 <= elapsed {
                    synth.play(Pitch(next.1), velocity: 0.9, for: 0.3)
                    pending.removeFirst()
                }
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            OllinApp.isRenderingHeadless = false
            return synth.renderExportAudio(upTo: 4.0, sampleRate: rate)
        }

        let dirt = Effect.distortion(Distortion(.overdrive, drive: 0, mix: 0.7))
        let echo = Effect.delay(Delay(time: 0.24, feedback: 0.55, mix: 0.5))

        let takes: [(String, [Effect])] = [
            ("nothing at all", []),
            ("a room", [.reverb(Reverb(.hall, mix: 0.4))]),
            ("an echo", [echo]),
            ("warm, then a room", [.equalizer(.warm), .reverb(Reverb(.hall, mix: 0.35))]),
            ("bright, then the same room", [.equalizer(.bright), .reverb(Reverb(.hall, mix: 0.35))]),
            ("an echo OF a dirty sound", [dirt, echo]),
            ("a dirty echo (same two, other way round)", [echo, dirt]),
            ("all four, in order", [dirt, .equalizer(.scooped), echo,
                                    .reverb(Reverb(.cathedral, mix: 0.35))]),
        ]

        var samples = [Float]()
        for (name, effects) in takes {
            // The export path is stereo interleaved; fold to mono for the file.
            let stereo = take(effects)
            for frame in 0..<(stereo.count / 2) {
                samples.append((stereo[frame * 2] + stereo[frame * 2 + 1]) * 0.5)
            }
            samples += [Float](repeating: 0, count: Int(0.4 * rate))
            print("  take: \(name)")
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path),
                                   settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                      frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)

        print("audition: \(Double(samples.count) / rate) s to \(path)")
        #expect(samples.count > Int(rate))
        #expect(samples.contains { abs($0) > 0.02 })
    }
}
