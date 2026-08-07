import AVFoundation
import Foundation
import Testing
@testable import OllinAudio

/// The numbers say the ratios are whole and the degrees are the right degrees.
/// Whether any of it is music is a different question.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/composition.wav swift test --filter ProgressionAudition
/// ```
///
/// Rendered through the engine-free renderer, so nothing here starts an engine.
@Suite struct ProgressionAudition {

    static let rate = 44100.0

    /// Plays a sequence of (time, pitch, length, velocity) through one voice.
    static func play(_ voice: Voice, _ notes: [(Double, Double, Double, Double)],
                     tail: Double = 1.6, gain: Double = 0.55) -> [Float] {
        let events = EventRing(capacity: 2048)
        let renderer = SynthRenderer(voice: voice, polyphony: 16,
                                     sampleRate: rate, events: events)
        renderer.gain = gain
        var pending = notes.sorted { $0.0 < $1.0 }
        let span = (notes.map { $0.0 + $0.2 }.max() ?? 1) + tail
        var out = [Float]()
        var elapsed = 0.0
        let block = 512
        while elapsed < span {
            while let next = pending.first, next.0 <= elapsed {
                events.push(SynthEvent(kind: .noteOn, pitch: next.1, velocity: next.3,
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

    static func mix(_ takes: [[Float]]) -> [Float] {
        var out = [Float](repeating: 0, count: takes.map(\.count).max() ?? 0)
        for take in takes {
            for index in take.indices { out[index] += take[index] }
        }
        return out.map { max(-1, min(1, $0)) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        var samples = [Float]()

        /// A progression played as chords with a root underneath it.
        func changes(_ progression: Progression, bars: Int, beat: Double = 0.55,
                     voice: Voice = .pad, bass: Voice = .bass) -> [Float] {
            var chords: [(Double, Double, Double, Double)] = []
            var roots: [(Double, Double, Double, Double)] = []
            for bar in 0..<bars {
                let at = Double(bar) * beat * 2
                for pitch in progression.pitches(at: bar) {
                    chords.append((at, pitch.midi, beat * 1.9, 0.5))
                }
                roots.append((at, progression.root(at: bar).midi - 12, beat * 1.7, 0.8))
            }
            return Self.mix([Self.play(voice, chords), Self.play(bass, roots, gain: 0.5)])
        }

        let key = Scale(.major, root: "C4")
        let minorKey = Scale(.minor, root: "A3")

        print("  take: I vi IV V in C major")
        samples += changes(Progression("I vi IV V", in: key), bars: 8)
        print("  take: the same degrees in A minor, unchanged")
        samples += changes(Progression("I vi IV V", in: minorKey), bars: 8)
        print("  take: ii V I with sevenths")
        samples += changes(Progression.twoFiveOne(in: key), bars: 6)
        print("  take: the andalusian descent")
        samples += changes(Progression.andalusian(in: minorKey), bars: 8)
        print("  take: a wander learned from I vi IV V ii V")
        samples += changes(Progression("I vi IV V ii V", in: key).wandering(16, seed: 5),
                           bars: 16)
        print("  take: written as chord symbols instead")
        samples += changes(Progression(symbols: "Dm7 G7 Cmaj7 Cmaj7"), bars: 8)

        // A scale in each tuning, so the differences are audible one after the
        // other rather than described.
        func run(_ tuning: Tuning, steps: Int, voice: Voice = .bowed) -> [Float] {
            let notes = (0...steps).map { step in
                (Double(step) * 0.32, tuning[step].midi, 0.34, 0.75)
            }
            return Self.play(voice, notes, tail: 1.0)
        }
        /// A held chord, which is where a tuning is really heard: whole number
        /// ratios stop beating and equal ones do not.
        func chord(_ tuning: Tuning, _ degrees: [Int]) -> [Float] {
            Self.play(.bowed, degrees.map { (0.0, tuning[$0].midi, 2.4, 0.6) }, tail: 1.2)
        }

        print("  take: twelve equal steps, then just intonation")
        samples += chord(.equalTemperament.rooted(at: "C3"), [0, 4, 7])
        samples += chord(Tuning.just.rooted(at: "C3"), [0, 2, 4])
        print("  take: nineteen and thirty one equal steps")
        samples += run(.nineteen.rooted(at: "C3"), steps: 19)
        samples += run(.thirtyOne.rooted(at: "C3"), steps: 31)
        print("  take: a tuning with no octave in it")
        samples += run(Tuning.bohlenPierce.rooted(at: "C3"), steps: 13, voice: .clarinet)

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
