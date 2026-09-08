import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The tests say a room of your own is the convolution it stands for.
/// Whether it sounds like a room is something only listening settles, and
/// this is how it gets asked.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/rooms.wav swift test --filter ConvolutionAudition
/// ```
///
/// Rendered through the export path, which builds the chain the same way the
/// output does. A short phrase, then the same phrase through each room in
/// turn, with the built-in hall first for comparison.
@Suite(.serialized) struct ConvolutionAudition {

    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let rate = 48000.0

        /// One short phrase through a chain, rendered as an export would.
        func take(_ effects: [Effect], voice: Voice = .pluck, seconds: Double = 4.5) -> [Float] {
            let synth = Synth(voice, polyphony: 12)
            synth.gain = 0.55
            synth.effects = effects
            OllinApp.isRenderingHeadless = true
            let notes: [(Double, Double)] = [(0, 60), (0.35, 67), (0.7, 63), (1.05, 70), (1.4, 72)]
            var pending = notes
            var elapsed = 0.0
            while elapsed < seconds {
                while let next = pending.first, next.0 <= elapsed {
                    synth.play(Pitch(next.1), velocity: 0.9, for: 0.25)
                    pending.removeFirst()
                }
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            OllinApp.isRenderingHeadless = false
            return synth.renderExportAudio(upTo: seconds, sampleRate: rate)
        }

        let takes: [(String, [Effect])] = [
            ("nothing at all", []),
            ("the built-in hall", [.reverb(Reverb(.hall, mix: 0.4))]),
            ("a small room of noise", [.reverb(Reverb(.decay(seconds: 0.6, damping: 0.6, sampleRate: rate), mix: 0.4))]),
            ("a hall of noise, three seconds", [.reverb(Reverb(.decay(seconds: 3, damping: 0.6, sampleRate: rate), mix: 0.4))]),
            ("the same hall, bright", [.reverb(Reverb(.decay(seconds: 3, damping: 0, sampleRate: rate), mix: 0.4))]),
            ("the same hall, with a pre-delay", [.reverb(Reverb(.decay(seconds: 3, damping: 0.6, sampleRate: rate), mix: 0.4, preDelay: 0.06))]),
            ("the hall run backward", [.reverb(Reverb(.decay(seconds: 1.5, damping: 0.6, sampleRate: rate).reversed(), mix: 0.6))]),
            ("a room that hums at A", [.reverb(Reverb(ImpulseResponse(seconds: 2, sampleRate: rate) { t, _ in
                exp(-3 * t) * sin(2 * .pi * 220 * t)
            }, mix: 0.5))]),
            ("a dropped ball: echoes closing in", [.reverb(Reverb(ImpulseResponse(seconds: 1.6, sampleRate: rate) { t, noise in
                var sum = 0.0
                var at = 0.0, gap = 0.4
                for bounce in 0..<12 {
                    if t >= at { sum += exp(-(t - at) / 0.02) * pow(0.75, Double(bounce)) }
                    at += gap
                    gap *= 0.75
                }
                return sum * (0.6 + 0.4 * noise)
            }, mix: 0.6))]),
        ]

        var samples = [Float]()
        for (name, effects) in takes {
            let stereo = take(effects)
            samples += stereo
            samples += [Float](repeating: 0, count: Int(0.5 * rate) * 2)
            print("  take: \(name)")
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: format.settings)
        let frames = samples.count / 2
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            buffer.floatChannelData![0][frame] = samples[frame * 2]
            buffer.floatChannelData![1][frame] = samples[frame * 2 + 1]
        }
        try file.write(from: buffer)

        print("audition: \(Double(frames) / rate) s to \(path)")
        #expect(frames > Int(rate))
        #expect(samples.contains { abs($0) > 0.02 })
    }
}
