import AVFoundation
import Foundation
import Ollin
import Testing
@testable import OllinAudio

/// A sound cannot be snapshotted, so the way to check one is to listen to it.
///
/// This walks through what a plucked string model does, one control at a time,
/// and finishes with a short piece. Rendered offline through the same renderer
/// that feeds the speakers, with no audio engine anywhere in it.
///
/// ```sh
/// OLLIN_AUDITION=/tmp/audition.wav swift test --filter PhysicalModelAudition
/// ```
@Suite struct PhysicalModelAudition {

    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let given = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!)
        let path = given
            .deletingLastPathComponent()
            .appendingPathComponent(given.deletingPathExtension().lastPathComponent + "-physical")
            .appendingPathExtension(given.pathExtension.isEmpty ? "wav" : given.pathExtension)

        let sampleRate = 44100.0
        var samples = [Float]()

        // A run across the whole range. Every note is tuned by the loop rather
        // than rounded to a whole number of samples, which is what an octave at
        // the top is a test of: rounding puts it most of a semitone out.
        // Named and annotated, rather than inferred through a map inside a
        // trailing closure, which Swift 6.3 will not finish working out.
        let sweep: [(at: Double, pitch: Double, velocity: Double, hold: Double)] =
            (0..<25).map { (step: Int) in
                (at: Double(step) * 0.13, pitch: 36 + Double(step) * 3,
                 velocity: 0.85, hold: 0.5)
            }
        samples += render(sampleRate: sampleRate, voice: Voice(plucked: .steel, gain: 0.8)) { sweep }

        // The same note plucked in different places. Halfway along is hollow,
        // because every harmonic with a node in the middle is missing; near the
        // end keeps them all and comes out thin.
        for pick in [0.5, 0.38, 0.26, 0.16, 0.08, 0.04] {
            let string = PluckedString(position: pick, hardness: 0.75, decay: 2.4, damping: 0.35)
            samples += render(sampleRate: sampleRate, voice: Voice(plucked: string, gain: 0.85)) {
                [(at: 0, pitch: 52, velocity: 0.9, hold: 1.0)]
            }
        }

        // How hard the pluck is: what part of the string it sets moving.
        for hardness in [0.0, 0.3, 0.6, 1.0] {
            let string = PluckedString(position: 0.2, hardness: hardness, decay: 2.2, damping: 0.4)
            samples += render(sampleRate: sampleRate, voice: Voice(plucked: string, gain: 0.85)) {
                [(at: 0, pitch: 45, velocity: 0.9, hold: 1.0)]
            }
        }

        // How fast the top goes compared with the bottom, which is what makes a
        // held note darken as it rings.
        for damping in [0.0, 0.35, 0.7, 1.0] {
            let string = PluckedString(position: 0.22, hardness: 0.9, decay: 3.5, damping: damping)
            samples += render(sampleRate: sampleRate, voice: Voice(plucked: string, gain: 0.85)) {
                [(at: 0, pitch: 40, velocity: 0.95, hold: 1.6)]
            }
        }

        // Each preset, played as a chord.
        for string in [PluckedString.nylon, .steel, .harp, .muted] {
            samples += render(sampleRate: sampleRate, voice: Voice(plucked: string, gain: 0.7)) {
                let chord = Chord("A3", .minorSeventh).pitches
                return chord.enumerated().map { index, pitch in
                    (at: Double(index) * 0.07, pitch: pitch.midi, velocity: 0.85, hold: 2.4)
                }
            }
        }

        // And a figure, so it is heard as an instrument rather than as a sweep.
        samples += render(sampleRate: sampleRate, voice: Voice(plucked: .nylon, gain: 0.7)) {
            let key = Scale(.minorPentatonic, root: "A3")
            let rhythm = Rhythm(7, in: 16)
            let arp = Arpeggio(Chord(key[0], .minorSeventh), .upDown, octaves: 2)
            return (0..<48).compactMap { step in
                guard rhythm[step] else { return nil }
                return (at: Double(step) * 0.14, pitch: key.snap(arp[step]).midi,
                        velocity: 0.8, hold: 1.6)
            }
        }

        // The struck bodies. Each preset first, so the family is audible.
        for body in [ModalBody.drum, .plate, .bar, .bell, .wood, .glass] {
            samples += render(sampleRate: sampleRate, voice: Voice(struck: body, gain: 0.8)) {
                [(at: 0, pitch: 60, velocity: 0.9, hold: max(1.0, body.decay))]
            }
        }

        // Then shapes, which is the point: nothing below picks a sound. The
        // ratios come out of the outline, and the same note is played on each.
        let outlines: [(String, Shape)] = [
            ("circle", Self.polygon(sides: 96, radius: 100)),
            ("square", Self.polygon(sides: 4, radius: 100, turn: .pi / 4)),
            ("triangle", Self.polygon(sides: 3, radius: 110)),
            ("oblong", Self.oblong(width: 220, height: 90)),
            ("blob", Self.blob(radius: 100)),
        ]
        for (name, outline) in outlines {
            guard let measured = StruckShape(outline, modes: 12) else { continue }
            print("audition: \(name) rings at "
                  + measured.ratios.map { String(format: "%.2f", $0) }.joined(separator: " "))
            let body = measured.body(decay: 2.6, damping: 0.9, hardness: 0.75)
            samples += render(sampleRate: sampleRate, voice: Voice(struck: body, gain: 0.8)) {
                [(at: 0, pitch: 55, velocity: 0.9, hold: 2.6)]
            }
        }

        // One shape struck in different places. Same body, same note: only
        // where it was hit changes, and half its tones go quiet in the middle.
        if let measured = StruckShape(Self.polygon(sides: 96, radius: 100), modes: 12) {
            for away in [0.0, 0.25, 0.5, 0.75, 0.95] {
                let body = measured.body(struckAt: Vector2(away * 100, 0),
                                         decay: 2.4, damping: 0.9, hardness: 0.8)
                samples += render(sampleRate: sampleRate, voice: Voice(struck: body, gain: 0.8)) {
                    [(at: 0, pitch: 57, velocity: 0.9, hold: 2.0)]
                }
            }
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(forWriting: path, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)

        print("audition: \(samples.count) samples, \(Double(samples.count) / sampleRate) s to \(path.path)")
        #expect(samples.count > Int(sampleRate * 20))
        #expect(samples.contains { abs($0) > 0.05 }, "it came out silent")
    }

    private static func polygon(sides: Int, radius: Double, turn: Double = 0) -> Shape {
        Shape((0..<sides).map { step in
            let angle = Double(step) / Double(sides) * .tau - .pi / 2 + turn
            return Vector2(cos(angle), sin(angle)) * radius
        })
    }

    private static func oblong(width: Double, height: Double) -> Shape {
        Shape([Vector2(-width / 2, -height / 2), Vector2(width / 2, -height / 2),
               Vector2(width / 2, height / 2), Vector2(-width / 2, height / 2)])
    }

    private static func blob(radius: Double) -> Shape {
        Shape((0..<120).map { step in
            let angle = Double(step) / 120 * .tau
            let wobble = 1 + 0.26 * sin(angle * 3 + 0.7) + 0.13 * sin(angle * 5 - 1.9)
            return Vector2(cos(angle), sin(angle)) * radius * wobble
        })
    }

    /// Plays a set of notes on one voice and returns the samples, with enough
    /// room after the last one for it to finish.
    private func render(
        sampleRate: Double, voice: Voice,
        notes: () -> [(at: Double, pitch: Double, velocity: Double, hold: Double)]
    ) -> [Float] {
        let events = EventRing()
        let renderer = SynthRenderer(
            voice: voice, polyphony: 16, sampleRate: sampleRate, events: events, seed: 0x51F
        )
        renderer.gain = 0.7

        var pending = notes().sorted { $0.at < $1.at }
        let span = (pending.map { $0.at + $0.hold }.max() ?? 1) + 0.6
        var elapsed = 0.0
        let block = 512
        var samples = [Float]()

        while elapsed < span {
            while let next = pending.first, next.at <= elapsed {
                events.push(SynthEvent(
                    kind: .noteOn, pitch: next.pitch, velocity: next.velocity,
                    durationSamples: Int(next.hold * sampleRate)
                ))
                pending.removeFirst()
            }
            var chunk = [Float](repeating: 0, count: block)
            chunk.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: block) }
            samples += chunk
            elapsed += Double(block) / sampleRate
        }
        return samples
    }
}
