import AVFoundation
import Foundation
import Testing
@testable import OllinAudio

/// The numbers say a note comes out at the pitch asked for and keeps the
/// recording's own partials. Whether five recordings are enough, and what one
/// stretched over everything actually sounds like, is a listening question.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/sampler.wav swift test --filter SamplerAudition
/// ```
@Suite struct SamplerAudition {

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let rate = 44100.0
        let full = try #require(SampledInstrument.builtin)

        /// A climbing run through one instrument.
        func run(_ instrument: SampledInstrument, from: Int, to: Int,
                 spec: Sampled = Sampled()) -> [Float] {
            let events = EventRing(capacity: 1024)
            let renderer = SynthRenderer(voice: Voice(sampled: spec, envelope: .plucked, gain: 0.8),
                                         polyphony: 12, sampleRate: rate, events: events)
            renderer.gain = 0.7
            renderer.instrument = instrument

            var out = [Float]()
            var elapsed = 0.0
            var next = from
            let step = 0.34
            let span = Double(to - from + 1) * step + 1.8
            while elapsed < span {
                if next <= to, elapsed >= Double(next - from) * step {
                    events.push(SynthEvent(kind: .noteOn, pitch: Double(next),
                                           velocity: 0.85,
                                           durationSamples: Int(0.3 * rate)))
                    next += 1
                }
                var chunk = [Float](repeating: 0, count: 512)
                chunk.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: 512) }
                out += chunk
                elapsed += 512 / rate
            }
            return out
        }

        // The same run three ways, so the difference is the instrument.
        let middle = full.recordingCount / 2
        let one = SampledInstrument(name: "one",
                                    recordings: [full.recording(at: middle, over: 0...127)])

        var samples = [Float]()
        print("  take: five recordings, chromatic run")
        samples += run(full, from: 45, to: 76)
        samples += [Float](repeating: 0, count: Int(0.5 * rate))

        print("  take: one recording stretched over the same run")
        samples += run(one, from: 45, to: 76)
        samples += [Float](repeating: 0, count: Int(0.5 * rate))

        print("  take: five recordings, an octave down")
        samples += run(full, from: 45, to: 60, spec: Sampled(transpose: -12))

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
        #expect(samples.contains { abs($0) > 0.02 })
    }
}
