import AVFoundation
import Foundation
import Testing
@testable import OllinAudio

/// The numbers say a position between two frames plays their blend. Whether
/// a note sliding along a table is an instrument is a different question, and
/// this is how it gets asked.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/wavetable.wav swift test --filter WavetableAudition
/// ```
@Suite struct WavetableAudition {

    static let rate = 44100.0

    static func play(_ voice: Voice, table: Wavetable, _ notes: [(Double, Double, Double)],
                     tail: Double = 1.2, gain: Double = 0.6) -> [Float] {
        let events = EventRing(capacity: 2048)
        let renderer = SynthRenderer(voice: voice, polyphony: 16,
                                     sampleRate: rate, events: events)
        renderer.gain = gain
        renderer.wavetable = table
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

        /// The same short phrase every time, so only the table and scan differ.
        let phrase: [(Double, Double, Double)] = [
            (0, 48, 0.9), (1.0, 55, 0.9), (2.0, 52, 0.9), (3.0, 60, 1.8),
        ]

        let takes: [(String, Wavetable, Voice)] = [
            ("the plain table, held at the sine end", .basic,
             Voice(wavetable: .at(0), envelope: .organ)),
            ("the same, held between the sawtooth and the square", .basic,
             Voice(wavetable: .at(0.85), envelope: .organ)),
            ("struck to the square and settling back: morph", .basic, .morph),
            ("the pulse narrowing over each note", .pulse,
             Voice(wavetable: WavetableScan(position: 0, sweep: 1,
                                            envelope: Envelope(attack: 0.6, decay: 0.01, sustain: 1, release: 0.3)),
                   envelope: .swell)),
            ("the vowels, a to u over each note", .vowels,
             Voice(wavetable: WavetableScan(position: 0, sweep: 1,
                                            envelope: Envelope(attack: 1.2, decay: 0.01, sustain: 1, release: 0.4)),
                   envelope: .swell)),
        ]

        for (name, table, voice) in takes {
            samples += Self.play(voice, table: table, phrase)
            samples += [Float](repeating: 0, count: Int(0.3 * Self.rate))
            print("  take: \(name) (\(table.name), \(table.frameCount) frames)")
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
