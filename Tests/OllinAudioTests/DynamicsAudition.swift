import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The tests say a compressor lands a tone where its ratio says and a gate
/// shuts under its threshold. Whether the holding reads as a phrase that keeps
/// its accents rather than one that pumps, and whether the gate closes on the
/// room without swallowing a tail, is something only listening settles, and
/// this is how it gets asked.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/levels.wav swift test --filter DynamicsAudition
/// ```
///
/// A phrase with accents in it, rendered through the export path, since a
/// compressor with nothing loud to hold says nothing at all.
@Suite(.serialized) struct DynamicsAudition {

    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let rate = 44100.0

        /// A phrase whose every fourth note is an accent, through one chain.
        func take(_ effects: [Effect]) -> [Float] {
            let synth = Synth(.pluck, polyphony: 8)
            synth.gain = 0.5
            synth.effects = effects
            OllinApp.isRenderingHeadless = true
            let steps: [Double] = [45, 52, 48, 55, 50, 57, 48, 52, 45, 52, 48, 55, 50, 57, 48, 52]
            var pending: [(Double, Double, Double, Double)] = steps.enumerated().map { index, note in
                let accent = index % 4 == 0
                return (Double(index) * 0.3, note, accent ? 1.0 : 0.25, accent ? 0.9 : 0.3)
            }
            var elapsed = 0.0
            while elapsed < 5.4 {
                while let next = pending.first, next.0 <= elapsed {
                    synth.play(Pitch(next.1), velocity: next.2, for: next.3)
                    pending.removeFirst()
                }
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            OllinApp.isRenderingHeadless = false
            return synth.renderExportAudio(upTo: 5.4, sampleRate: rate)
        }

        /// A hiss under everything, for the gate to have a room to take out.
        let hiss = Effect.custom("room", state: UInt32(22)) { sound, seed in
            for index in 0..<sound.frameCount {
                seed = seed &* 1_664_525 &+ 1_013_904_223
                let noise = (Float(seed >> 9) / Float(1 << 23) - 0.5) * 0.012
                sound.left[index] += noise
                sound.right[index] += noise
            }
        }

        let takes: [(String, [Effect])] = [
            ("nothing at all, the accents towering over the rest", []),
            ("a compressor, gently", [.compressor(Compressor(threshold: -18, ratio: 3, makeup: 5))]),
            ("the same, squeezed hard and fast", [.compressor(Compressor(threshold: -28, ratio: 12,
                                                                        attack: 0.001, release: 0.08,
                                                                        makeup: 12))]),
            ("a slow release, breathing", [.compressor(Compressor(threshold: -26, ratio: 8,
                                                                  attack: 0.02, release: 0.6,
                                                                  makeup: 10))]),
            ("a limiter alone, ceiling low", [.limiter(Limiter(ceiling: -14, release: 0.06))]),
            ("hiss, and nothing done about it", [hiss]),
            ("the same hiss, gated", [hiss, .gate(Gate(threshold: -34, hold: 0.08, release: 0.1))]),
            ("gated with no hold, which chops the tails", [hiss, .gate(Gate(threshold: -34, hold: 0,
                                                                           release: 0.02))]),
        ]

        var left = [Float](), right = [Float]()
        for (name, effects) in takes {
            let stereo = take(effects)
            for frame in 0..<(stereo.count / 2) {
                left.append(stereo[frame * 2])
                right.append(stereo[frame * 2 + 1])
            }
            let gap = [Float](repeating: 0, count: Int(0.6 * rate))
            left += gap
            right += gap
            print("  take: \(name)")
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path),
                                   settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                      frameCapacity: AVAudioFrameCount(left.count))!
        buffer.frameLength = AVAudioFrameCount(left.count)
        left.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: left.count)
        }
        right.withUnsafeBufferPointer {
            buffer.floatChannelData![1].update(from: $0.baseAddress!, count: right.count)
        }
        try file.write(from: buffer)

        print("audition: \(Double(left.count) / rate) s to \(path)")
        #expect(left.count > Int(rate))
        #expect(left.contains { abs($0) > 0.02 })
    }
}
