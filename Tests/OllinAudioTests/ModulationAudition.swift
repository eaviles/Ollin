import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The tests say a chorus slides its copy by the wave and a flanger held
/// still is a comb. Whether the slide reads as several voices and the comb
/// as the whoosh it is meant to be is something only listening settles, and
/// this is how it gets asked.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/movement.wav swift test --filter ModulationAudition
/// ```
///
/// Rendered through the export path, in stereo, since a chorus's width and
/// a tremolo's swing are half the point.
@Suite(.serialized) struct ModulationAudition {

    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let rate = 44100.0

        /// A held chord and a short phrase over it, through one chain.
        func take(_ effects: [Effect]) -> [Float] {
            let synth = Synth(.pad, polyphony: 12)
            synth.gain = 0.5
            synth.effects = effects
            OllinApp.isRenderingHeadless = true
            let notes: [(Double, Double, Double)] = [
                (0, 50, 4.6), (0, 57, 4.6), (0.4, 62, 0.5), (0.8, 66, 0.5), (1.2, 69, 0.5),
                (1.6, 74, 0.5), (2.4, 69, 0.5), (2.8, 66, 0.5), (3.2, 62, 1.2),
            ]
            var pending = notes
            var elapsed = 0.0
            while elapsed < 5.0 {
                while let next = pending.first, next.0 <= elapsed {
                    synth.play(Pitch(next.1), velocity: 0.85, for: next.2)
                    pending.removeFirst()
                }
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            OllinApp.isRenderingHeadless = false
            return synth.renderExportAudio(upTo: 5.0, sampleRate: rate)
        }

        let takes: [(String, [Effect])] = [
            ("nothing at all", []),
            ("a chorus", [.chorus(Chorus(rate: 0.8, depth: 0.6, mix: 0.5))]),
            ("a flanger, feedback up", [.flanger(Flanger(rate: 0.2, depth: 0.8, feedback: 0.6, mix: 0.5))]),
            ("the same flanger, feedback negative", [.flanger(Flanger(rate: 0.2, depth: 0.8, feedback: -0.6, mix: 0.5))]),
            ("a phaser, four stages", [.phaser(Phaser(rate: 0.35, depth: 1, stages: 4, feedback: 0.4, mix: 0.5))]),
            ("a tremolo", [.tremolo(Tremolo(rate: 5, depth: 0.7))]),
            ("the tremolo spread wide, swinging side to side", [.tremolo(Tremolo(rate: 1.5, depth: 0.9, spread: 1))]),
            ("a chorus into a room", [.chorus(Chorus()), .reverb(Reverb(.hall, mix: 0.3))]),
        ]

        var left = [Float](), right = [Float]()
        for (name, effects) in takes {
            let stereo = take(effects)
            for frame in 0..<(stereo.count / 2) {
                left.append(stereo[frame * 2])
                right.append(stereo[frame * 2 + 1])
            }
            let gap = [Float](repeating: 0, count: Int(0.5 * rate))
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
