import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The numbers say a reading rises and falls in the right places. Whether it is
/// worth listening to is a separate question, and this is how it gets asked.
///
/// Four readings of the same landscape row, so the differences are the settings
/// and not the data: chromatic, snapped to a scale, turned upside down, and
/// with a reference note underneath. Rendered through the engine-free renderer,
/// so nothing here starts an audio engine.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/sonification.wav swift test --filter SonificationAudition
/// ```
@Suite struct SonificationAudition {

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let sampleRate = 44100.0
        let tempo = 96.0

        // One row of a landscape. Built from a few sines rather than from noise
        // so the file is the same every time and two takes can be compared.
        let land = Heightfield(columns: 48, rows: 16) { u, v in
            sin(u * 7.1) * 0.5 + sin(u * 2.3 + v) * 0.3 + sin(u * 17) * 0.12
        }.normalized()
        let row = (0 ..< land.columns).map { land[$0, 8] }

        let scale = Scale(.minorPentatonic, root: "A2")
        let takes: [(String, Sonification, Bool)] = [
            ("every semitone", Sonification(row, pitches: "A2"..."A5", length: 0.5), false),
            ("snapped to a scale",
             Sonification(row, in: scale, pitches: "A2"..."A5", length: 0.5), false),
            ("turned over",
             Sonification(row, in: scale, pitches: "A2"..."A5", length: 0.5).inverted(), false),
            ("with a reference",
             Sonification(row, in: scale, pitches: "A2"..."A5", length: 0.5), true),
        ]

        var samples = [Float]()
        for (name, reading, withReference) in takes {
            let events = EventRing()
            let renderer = SynthRenderer(voice: .pluck, polyphony: 16,
                                         sampleRate: sampleRate, events: events)
            renderer.gain = 0.6

            let reference = reading.reference(
                at: (reading.domain.lowerBound + reading.domain.upperBound) / 2,
                velocity: 0.35)
            let stepSeconds = reading[0]?.seconds(at: tempo) ?? 0.3
            let span = Double(reading.count) * stepSeconds + 1.5

            var elapsed = 0.0, next = 0
            let block = 512
            while elapsed < span {
                while next < reading.count, Double(next) * stepSeconds <= elapsed {
                    if let note = reading.note(at: next) {
                        events.push(SynthEvent(
                            kind: .noteOn, pitch: note.pitch.midi, velocity: note.velocity,
                            durationSamples: Int(note.seconds(at: tempo) * sampleRate)))
                    }
                    // The reference sounds every eighth step, under the reading.
                    if withReference, next % 8 == 0 {
                        events.push(SynthEvent(
                            kind: .noteOn, pitch: reference.pitch.midi,
                            velocity: reference.velocity,
                            durationSamples: Int(reference.seconds(at: tempo) * sampleRate)))
                    }
                    next += 1
                }
                var chunk = [Float](repeating: 0, count: block)
                chunk.withUnsafeMutableBufferPointer {
                    renderer.render(into: $0, frameCount: block)
                }
                samples += chunk
                elapsed += Double(block) / sampleRate
            }
            print("  take: \(name), \(reading.count) notes")
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path),
                                   settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                      frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)

        print("audition: \(Double(samples.count) / sampleRate) s to \(path)")
        #expect(samples.count > Int(sampleRate))
        #expect(samples.contains { abs($0) > 0.02 })
    }
}
