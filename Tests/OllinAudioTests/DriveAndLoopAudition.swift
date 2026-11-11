import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The tests say what each distortion character does to a tone, where a long
/// echo's repeats land, and that a blown tube holds its pitch at the top of
/// its range. Whether a soft clip is warm, a loop is a loop, and a high
/// clarinet blown hard still sounds like one is something only listening
/// settles, and this is how it gets asked.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/drive-and-loop.wav swift test --filter DriveAndLoopAudition
/// ```
///
/// Rendered through the export path, which builds the chain the same way the
/// output does.
@Suite(.serialized) struct DriveAndLoopAudition {

    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let rate = 44100.0

        /// Notes at their times through a chain, rendered as an export would.
        /// With a `breath`, each note is pressed by it from its own start, the
        /// way a finger on the note would.
        func take(_ effects: [Effect], voice: Voice = .stab, seconds: Double,
                  notes: [(at: Double, midi: Double, length: Double)],
                  breath: ((Double) -> Double)? = nil) -> [Float] {
            let synth = Synth(voice, polyphony: 12)
            synth.gain = 0.5
            synth.effects = effects
            OllinApp.isRenderingHeadless = true
            var pending = notes
            var sounding: (note: PlayingNote, since: Double)?
            var elapsed = 0.0
            while elapsed < seconds {
                while let next = pending.first, next.at <= elapsed {
                    let note = synth.play(Pitch(next.midi), velocity: 0.9, for: next.length)
                    sounding = (note, elapsed)
                    pending.removeFirst()
                }
                if let breath, let sounding { synth.press(sounding.note, breath(elapsed - sounding.since)) }
                synth.advance(by: 1.0 / 60)
                elapsed += 1.0 / 60
            }
            OllinApp.isRenderingHeadless = false
            return synth.renderExportAudio(upTo: seconds, sampleRate: rate)
        }

        let phrase: [(at: Double, midi: Double, length: Double)] =
            [(0, 48, 0.35), (0.4, 55, 0.35), (0.8, 51, 0.35), (1.2, 58, 0.35), (1.6, 60, 0.6)]
        var takes: [(String, [Float])] = []

        takes.append(("the phrase, clean", take([], seconds: 3, notes: phrase)))
        for character in Distortion.Character.allCases {
            for drive in [-6.0, 8] {
                takes.append(("\(character) at \(Int(drive)) dB",
                              take([.distortion(Distortion(character, drive: drive, mix: 1)), .limiter(Limiter())],
                                   seconds: 3, notes: phrase)))
            }
        }

        // Five notes into a four-second loop, then twelve seconds of what the
        // loop does with them.
        takes.append(("a four-second loop, feedback 0.85",
                      take([.delay(Delay(time: 4, feedback: 0.85, mix: 0.5, damping: 5000)), .limiter(Limiter())],
                           voice: .pluck, seconds: 16, notes: phrase)))

        // A scale to the top of the tube's range, each note swelled from just
        // speaking to full breath: the pitch should hold through the swell.
        let climb: [(at: Double, midi: Double, length: Double)] =
            [69, 76, 81, 84, 88, 91, 93, 95].enumerated().map { (Double($0.offset) * 1.5, Double($0.element), 1.3) }
        for (name, tube) in [("clarinet", Voice.clarinet), ("reedy tube", Voice(blown: .reedy))] {
            takes.append(("\(name), A4 to B6, each note swelled",
                          take([], voice: tube, seconds: 12.5, notes: climb) { held in
                              0.35 + 0.65 * min(1, held / 1.1)
                          }))
        }

        var samples = [Float]()
        for (name, stereo) in takes {
            // The export path is stereo interleaved; fold to mono for the file.
            for frame in 0..<(stereo.count / 2) {
                samples.append((stereo[frame * 2] + stereo[frame * 2 + 1]) * 0.5)
            }
            samples += [Float](repeating: 0, count: Int(0.5 * rate))
            print("  take: \(name)")
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
        print("  wrote \(path): \(takes.count) takes, \(String(format: "%.0f", Double(samples.count) / rate)) s")
    }
}
