import AVFoundation
import Foundation
import Testing
@testable import OllinAudio

/// A sound cannot be snapshotted, so the way to check one is to listen to it.
///
/// This composes a short piece out of the composition types and renders it
/// through the offline path, on a clock the test owns. Nothing here starts an
/// audio engine, which is the other thing it checks: the composition tier is
/// pure values and the renderer takes events and gives back samples, so a whole
/// piece can be made with no hardware in the room.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/audition.wav swift test --filter CompositionAudition
/// ```
///
/// It writes beside the path it is given, so it never overwrites the synthesis
/// audition, and it is off unless asked for.
@Suite struct CompositionAudition {

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let given = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!)
        let path = given
            .deletingLastPathComponent()
            .appendingPathComponent(given.deletingPathExtension().lastPathComponent + "-composition")
            .appendingPathExtension(given.pathExtension.isEmpty ? "wav" : given.pathExtension)

        let sampleRate = 44100.0
        let tempo = 104.0
        let steps = 16
        let bars = 16

        // Three parts, each its own renderer, exactly as the example runs three
        // instruments. They are summed at the end rather than shared, so each
        // one's polyphony and voice are its own.
        let parts = [
            Part(voice: .bass, gain: 0.55, sampleRate: sampleRate),
            Part(voice: .pluck, gain: 0.3, sampleRate: sampleRate),
            Part(voice: .breath, gain: 0.14, sampleRate: sampleRate),
        ]

        var melody = MarkovChain<Int>(seed: 4)
        melody.learn([0, 2, 4, 2, 0, -3, 0, 4], loops: true)
        melody.start(at: 0)

        var counter = StepCounter(perBeat: 4)
        let block = 512
        let secondsPerBeat = 60 / tempo
        let span = Double(bars * steps) / 4 * secondsPerBeat + 2.5
        var elapsed = 0.0
        var samples = [[Float]](repeating: [], count: parts.count)

        while elapsed < span {
            for step in counter.steps(upTo: elapsed / secondsPerBeat) {
                let bar = step / steps

                // The piece is arranged so each piece of the tier can be heard
                // arriving: bass alone, then the figure over it, then air, then
                // the rhythms and the key change under all three.
                let key = Scale(bar < 8 ? .minorPentatonic : .dorian, root: "A2")
                let counts = bar < 12 ? [3, 5, 11] : [5, 7, 9]
                let rings = counts.map { Rhythm($0, in: steps) }

                if rings[0][step] {
                    let degree = melody.next() ?? 0
                    parts[0].play(key[degree], velocity: 0.9, seconds: 0.34)
                }
                if bar >= 4, rings[1][step] {
                    let chord = Chord(key[0].transposed(by: 12), .minorSeventh)
                    let arp = Arpeggio(chord, .upDown, octaves: 2)
                    parts[1].play(key.snap(arp[step]), velocity: 0.55, seconds: 0.24)
                }
                if bar >= 8, rings[2][step] {
                    parts[2].play(Pitch(78 + Double(step % 3) * 5), velocity: 0.4, seconds: 0.1)
                }
            }

            for (index, part) in parts.enumerated() {
                samples[index] += part.render(block)
            }
            elapsed += Double(block) / sampleRate
        }

        let mixed = mix(samples)
        try write(mixed, to: path, sampleRate: sampleRate)
        print("audition: \(mixed.count) samples, \(Double(mixed.count) / sampleRate) s to \(path.path)")
        #expect(mixed.count > Int(sampleRate * 20))
        #expect(mixed.contains { abs($0) > 0.05 }, "the piece came out silent")
    }

    /// One instrument: a renderer, its event ring, and the rate they run at.
    private final class Part {
        let events = EventRing()
        let renderer: SynthRenderer
        let sampleRate: Double

        init(voice: Voice, gain: Double, sampleRate: Double) {
            self.sampleRate = sampleRate
            renderer = SynthRenderer(
                voice: voice, polyphony: 12, sampleRate: sampleRate, events: events
            )
            renderer.gain = gain
        }

        func play(_ pitch: Pitch, velocity: Double, seconds: Double) {
            events.push(SynthEvent(
                kind: .noteOn, pitch: pitch.midi, velocity: velocity,
                durationSamples: Int(seconds * sampleRate)
            ))
        }

        func render(_ frames: Int) -> [Float] {
            var chunk = [Float](repeating: 0, count: frames)
            chunk.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: frames) }
            return chunk
        }
    }

    private func mix(_ parts: [[Float]]) -> [Float] {
        let length = parts.map(\.count).max() ?? 0
        var out = [Float](repeating: 0, count: length)
        for part in parts {
            for index in part.indices { out[index] += part[index] }
        }
        return out.map { Float(softClip(Double($0))) }
    }

    private func write(_ samples: [Float], to url: URL, sampleRate: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
    }
}
