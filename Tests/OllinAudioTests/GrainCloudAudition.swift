import AVFoundation
import Foundation
import Testing
@testable import OllinAudio

/// The numbers say a frozen position holds its spectrum and that spread grains
/// land on both sides. Whether a cloud is an instrument is a different
/// question, and this is how it gets asked.
///
/// Written in two channels, because half of what a cloud is doing is where the
/// grains land.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/grains.wav swift test --filter GrainCloudAudition
/// ```
@Suite struct GrainCloudAudition {

    static let rate = 44100.0

    /// A sound with something to find in it: a struck bar, a rising tone, and
    /// a rattle, so scrubbing through it is audibly moving somewhere.
    static func material() -> GrainSource {
        guard let bar = GrainSource.builtIn else {
            return GrainSource(waveform: .sawtooth, frequency: 220, seconds: 2)
        }
        var frames = bar.frames
        let rate = bar.sampleRate
        var phase = 0.0
        for index in 0..<Int(1.5 * rate) {
            let along = Double(index) / (1.5 * rate)
            phase += 2 * Double.pi * (180 + 900 * along) / rate
            frames.append(Float(0.35 * sin(phase) * (1 - along * 0.5)))
        }
        var noise = UInt64(0x5EED)
        for index in 0..<Int(0.8 * rate) {
            noise &+= 0x9E37_79B9_7F4A_7C15
            var z = noise
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z ^= z >> 31
            let value = Double(z >> 11) * (1.0 / 9_007_199_254_740_992.0) * 2 - 1
            let along = Double(index) / (0.8 * rate)
            frames.append(Float(0.3 * value * sin(along * 40)))
        }
        return GrainSource(name: "material", frames: frames, sampleRate: rate,
                           rootKey: bar.rootKey)
    }

    static func play(_ voice: Voice, source: GrainSource,
                     _ notes: [(Double, Double, Double)],
                     scrub: ((Double) -> Double)? = nil,
                     tail: Double = 1.0, gain: Double = 0.5) -> (left: [Float], right: [Float]) {
        let events = EventRing(capacity: 2048)
        let renderer = SynthRenderer(voice: voice, polyphony: 16,
                                     sampleRate: rate, events: events)
        renderer.gain = gain
        renderer.grainSource = source
        var pending = notes.sorted { $0.0 < $1.0 }
        let span = (notes.map { $0.0 + $0.2 }.max() ?? 1) + tail
        var left = [Float](), right = [Float]()
        var elapsed = 0.0
        let block = 512
        while elapsed < span {
            while let next = pending.first, next.0 <= elapsed {
                events.push(SynthEvent(kind: .noteOn, pitch: next.1, velocity: 0.85,
                                       durationSamples: Int(next.2 * rate)))
                pending.removeFirst()
            }
            if let scrub { renderer.grainScrub = scrub(elapsed / span) }
            var a = [Float](repeating: 0, count: block)
            var b = [Float](repeating: 0, count: block)
            a.withUnsafeMutableBufferPointer { one in
                b.withUnsafeMutableBufferPointer { two in
                    renderer.render(into: one, right: two, frameCount: block)
                }
            }
            left += a
            right += b
            elapsed += Double(block) / rate
        }
        return (left, right)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let source = Self.material()
        var left = [Float](), right = [Float]()

        /// The same short phrase every time, so only the cloud differs.
        let phrase: [(Double, Double, Double)] = [
            (0, 48, 2.2), (2.4, 55, 2.2), (4.8, 51, 3.4),
        ]
        let one: [(Double, Double, Double)] = [(0, 60, 6)]

        let takes: [(String, Voice, ((Double) -> Double)?)] = [
            ("the sound crawling past at a sixth of its speed: smear", .smear, nil),
            ("held still, spread wide: cloud", .cloud, nil),
            ("one grain at a time, thrown about: rain", .rain, nil),
            ("held, and dragged through by hand",
             Voice(granular: GrainCloud(size: 0.07, density: 55, positionJitter: 0.006,
                                        speed: 0, panSpread: 0.6),
                   envelope: .sustained, gain: 0.8),
             { along in along }),
            ("grains on a strict clock, which is a pitch of its own",
             Voice(granular: GrainCloud(size: 0.008, density: 220, position: 0.55,
                                        positionJitter: 0, speed: 0, timingJitter: 0),
                   envelope: .sustained, gain: 0.8),
             nil),
            ("a chord of itself: five semitones of spread",
             Voice(granular: GrainCloud(size: 0.09, density: 40, position: 0.3,
                                        positionJitter: 0.02, speed: 0,
                                        pitchSpread: 7, panSpread: 0.9),
                   envelope: .sustained, gain: 0.8),
             nil),
        ]

        for (index, take) in takes.enumerated() {
            let notes = index == 3 || index == 4 ? one : phrase
            let played = Self.play(take.1, source: source, notes, scrub: take.2)
            left += played.left
            right += played.right
            let gap = [Float](repeating: 0, count: Int(0.4 * Self.rate))
            left += gap
            right += gap
            print("  take: \(take.0)")
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 2)!
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

        print("audition: \(Double(left.count) / Self.rate) s to \(path)")
        #expect(left.count > Int(Self.rate))
        #expect(left.contains { abs($0) > 0.02 })
        #expect(zip(left, right).contains { abs($0 - $1) > 0.01 })
    }
}
