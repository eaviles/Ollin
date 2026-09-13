import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The tests say a shifted tone lands where the ratio says and a frozen
/// instant is still there a second later. Whether a phrase an octave up
/// keeps its attacks, whether a harmonizer reads as two voices or one
/// smeared one, whether a held chord reads as a pad or as a stuck machine,
/// and whether a recording slowed four times is a drone or a warble, is
/// something only listening settles, and this is how it gets asked.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/spectral.wav swift test --filter SpectralAudition
/// ```
@Suite(.serialized) struct SpectralAudition {

    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let rate = 44100.0

        /// A short phrase and a chord, through one chain, with the chain's
        /// settings free to move as the phrase goes.
        func take(_ voice: Voice, seconds: Double, effects: [Effect],
                  instrument: SampledInstrument? = nil,
                  notes: [(at: Double, pitch: Double, velocity: Double, length: Double)],
                  move: (Double) -> [Effect]? = { _ in nil }) -> [Float] {
            let synth = Synth(voice, polyphony: 8)
            synth.gain = 0.5
            synth.instrument = instrument
            synth.effects = effects
            OllinApp.isRenderingHeadless = true
            var pending = notes
            var elapsed = 0.0
            while elapsed < seconds {
                while let next = pending.first, next.at <= elapsed {
                    synth.play(Pitch(next.pitch), velocity: next.velocity, for: next.length)
                    pending.removeFirst()
                }
                if let changed = move(elapsed) { synth.effects = changed }
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            OllinApp.isRenderingHeadless = false
            return synth.renderExportAudio(upTo: seconds, sampleRate: rate)
        }

        let phrase: [(at: Double, pitch: Double, velocity: Double, length: Double)] =
            [57, 60, 64, 67, 64, 60, 57, 55].enumerated().map { index, note in
                (Double(index) * 0.35, Double(note), index % 4 == 0 ? 0.9 : 0.6, 0.6)
            }
        let chord: [(at: Double, pitch: Double, velocity: Double, length: Double)] =
            [(0.2, 52, 0.8, 1.2), (0.2, 59, 0.7, 1.2), (0.2, 64, 0.7, 1.2), (0.2, 67, 0.6, 1.2)]

        /// The bundled instrument's first recording, slowed four times: the
        /// same bar, rung in slow motion.
        let slowed: SampledInstrument? = {
            guard let bar = SampledInstrument.builtIn else { return nil }
            let recording = bar.recording(at: 0, over: 0...127).stretched(by: 4)
            return SampledInstrument(name: "slowed", recordings: [recording])
        }()

        var takes: [(String, [Float])] = [
            ("the phrase plain", take(.pluck, seconds: 3.4, effects: [], notes: phrase)),
            ("the same, an octave up", take(.pluck, seconds: 3.4,
                                            effects: [.pitchShift(PitchShift(semitones: 12))], notes: phrase)),
            ("an octave down", take(.pluck, seconds: 3.4,
                                    effects: [.pitchShift(PitchShift(semitones: -12))], notes: phrase)),
            ("a fifth over it, half mixed: a harmonizer", take(.pluck, seconds: 3.4,
                                    effects: [.pitchShift(PitchShift(semitones: 7, mix: 0.5))], notes: phrase)),
            ("the pitch sliding up two octaves over the phrase", take(.pluck, seconds: 3.4,
                                    effects: [.pitchShift(PitchShift(semitones: 0))], notes: phrase) { t in
                                        [.pitchShift(PitchShift(semitones: min(24, t / 3.4 * 24)))]
                                    }),
            ("a chord, plain, ringing out", take(.bell, seconds: 4.5, effects: [], notes: chord)),
            ("the same chord frozen a second in, and held", take(.bell, seconds: 4.5,
                                    effects: [.freeze(Freeze(amount: 0))], notes: chord) { t in
                                        [.freeze(Freeze(amount: t >= 1.0 ? 1 : 0))]
                                    }),
            ("frozen, then let go over two seconds", take(.bell, seconds: 4.5,
                                    effects: [.freeze(Freeze(amount: 0))], notes: chord) { t in
                                        let amount = t < 1.0 ? 0 : max(0, 1 - (t - 1.8) / 2)
                                        return [.freeze(Freeze(amount: amount))]
                                    }),
        ]
        if let bar = SampledInstrument.builtIn, let slowed {
            let root = Double(bar.recordingRoots[0])
            takes.append(("the bundled bar, as recorded",
                          take(Voice(sampled: Sampler(), envelope: .plucked), seconds: 2.5,
                               effects: [], instrument: bar,
                               notes: [(0.1, root, 0.9, 2.0)])))
            takes.append(("the same recording stretched four times, at the same pitch",
                          take(Voice(sampled: Sampler(), envelope: .plucked), seconds: 7,
                               effects: [], instrument: slowed,
                               notes: [(0.1, root, 0.9, 6.5)])))
        }

        var left = [Float](), right = [Float]()
        for (name, stereo) in takes {
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
