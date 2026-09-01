import AVFoundation
import Foundation
import Testing
@testable import OllinAudio

/// The numbers say the spectrum falls off the way a bowed string's does and
/// that the tube has no even harmonics. Whether either is worth playing is a
/// different question, and this is how it gets asked.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/driven.wav swift test --filter DrivenModelAudition
/// ```
///
/// Nothing here starts an audio engine: it is the same clock-free renderer the
/// speakers get, driven by a loop this test owns.
@Suite struct DrivenModelAudition {

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let rate = 44100.0

        /// One take: a note held while the drive follows a shape, which is the
        /// thing these voices can do and the others cannot.
        func take(_ voice: Voice, pitch: Double, seconds: Double,
                  shape: (Double) -> Double) -> [Float] {
            let events = EventRing()
            let renderer = SynthRenderer(voice: voice, polyphony: 8,
                                         sampleRate: rate, events: events)
            renderer.gain = 0.7
            events.push(SynthEvent(kind: .noteOn, pitch: pitch, velocity: 0.9))
            var out = [Float]()
            let block = 256
            var elapsed = 0.0
            var released = false
            while elapsed < seconds {
                renderer.pressure = shape(elapsed / seconds)
                if !released, elapsed > seconds - 0.5 {
                    events.push(SynthEvent(kind: .noteOff, pitch: pitch))
                    released = true
                }
                var chunk = [Float](repeating: 0, count: block)
                chunk.withUnsafeMutableBufferPointer {
                    renderer.render(into: $0, frameCount: block)
                }
                out += chunk
                elapsed += Double(block) / rate
            }
            return out
        }

        func steady(_ t: Double) -> Double { 0.75 }
        /// In from nothing, hold, and away again, which is a bow stroke.
        func stroke(_ t: Double) -> Double {
            let shaped = sin(min(max(t, 0), 1) * .pi)
            return 0.15 + 0.75 * shaped * shaped
        }
        /// A held note leaned on twice, so the middle is audibly being played.
        func leaning(_ t: Double) -> Double { 0.45 + 0.4 * sin(t * .pi * 4) }

        var samples = [Float]()
        let takes: [(String, Voice, Double, Double, (Double) -> Double)] = [
            ("cello, steady bow", .cello, 45, 3.0, steady),
            ("cello, a bow stroke", .cello, 50, 3.0, stroke),
            ("violin, leaning on it", .violin, 67, 3.5, leaning),
            ("bowed, light and slow", .bowed, 62, 3.0, stroke),
            ("ponticello, next to the bridge", Voice(bowed: .ponticello, gain: 0.6), 55, 3.0, steady),
            ("clarinet, steady breath", .clarinet, 62, 3.0, steady),
            ("clarinet, a breath shaped", .clarinet, 69, 3.0, stroke),
            ("reed, bitten tight", .reed, 57, 3.0, steady),
            ("hollow, loose lip", .hollow, 50, 3.0, stroke),
        ]
        for (name, voice, pitch, seconds, shape) in takes {
            samples += take(voice, pitch: pitch, seconds: seconds, shape: shape)
            samples += [Float](repeating: 0, count: Int(0.35 * rate))
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
