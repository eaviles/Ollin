import AVFoundation
import Foundation
import Testing
@testable import OllinAudio

/// A sound cannot be snapshotted, so the way to check one is to listen to it.
///
/// This renders a short phrase through the offline path (the same renderer that
/// feeds the speakers, driven by a clock the test owns) and writes it to a file.
/// It is off unless asked for, so it never writes anything in a normal run:
///
/// ```sh
/// OLLIN_AUDITION=/tmp/audition.wav swift test --filter audition
/// ```
///
/// It doubles as a check that the renderer really is independent of the audio
/// engine: nothing below starts one.
@Suite struct SynthAudition {

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let sampleRate = 44100.0

        // Each preset gets a phrase that suits it, so the file is a tour rather
        // than one sound repeated.
        let phrases: [(Voice, [(beat: Double, pitch: Double, length: Double, velocity: Double)])] = [
            (.pluck, (0..<8).map { index in
                let scale = [0.0, 4, 7, 11, 12, 11, 7, 4]
                return (beat: Double(index) * 0.25, pitch: 60 + scale[index], length: 0.22, velocity: 0.85)
            }),
            (.bass, [
                (0, 36, 0.4, 1.0), (0.5, 36, 0.2, 0.7), (0.75, 43, 0.2, 0.8),
                (1.0, 41, 0.4, 1.0), (1.5, 36, 0.4, 0.8),
            ]),
            (.pad, [
                (0, 48, 2.2, 0.8), (0, 55, 2.2, 0.7), (0, 60, 2.2, 0.6), (0, 64, 2.2, 0.5),
            ]),
            (.bell, [(0, 72, 1.4, 0.9), (0.6, 79, 1.4, 0.7), (1.1, 76, 1.6, 0.8)]),
            (.breath, [(0, 60, 1.6, 0.9), (0.4, 67, 1.4, 0.7)]),
        ]

        var samples = [Float]()
        for (voice, notes) in phrases {
            let events = EventRing()
            let renderer = SynthRenderer(
                voice: voice, polyphony: 16, sampleRate: sampleRate, events: events
            )
            renderer.gain = 0.6

            let span = (notes.map { $0.beat + $0.length }.max() ?? 1) + 1.2
            var pending = notes.sorted { $0.beat < $1.beat }
            var elapsed = 0.0
            let block = 512

            while elapsed < span {
                while let next = pending.first, next.beat <= elapsed {
                    events.push(SynthEvent(
                        kind: .noteOn, pitch: next.pitch, velocity: next.velocity,
                        durationSamples: Int(next.length * sampleRate)
                    ))
                    pending.removeFirst()
                }
                var chunk = [Float](repeating: 0, count: block)
                chunk.withUnsafeMutableBufferPointer {
                    renderer.render(into: $0, frameCount: block)
                }
                samples += chunk
                elapsed += Double(block) / sampleRate
            }
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)

        print("audition: \(samples.count) samples, \(Double(samples.count) / sampleRate) s to \(path)")
        #expect(samples.count > Int(sampleRate))
    }
}
