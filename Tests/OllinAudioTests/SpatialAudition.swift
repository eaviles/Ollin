import AVFoundation
import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// A placing cannot be snapshotted and it cannot really be measured either: the
/// numbers say a sound is louder in one ear, but whether it goes *round* you is
/// something only listening settles.
///
/// This drives the export path exactly as an exported sketch does, writing the
/// frames down first and rendering the soundtrack afterwards, and puts the
/// result in a file. Off unless asked for:
///
/// ```sh
/// OLLIN_AUDITION=/tmp/spatial.wav swift test --filter SpatialAudition
/// ```
///
/// Wear headphones.
@Suite(.serialized) struct SpatialAudition {

    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OLLIN_AUDITION"] != nil))
    func audition() throws {
        let path = ProcessInfo.processInfo.environment["OLLIN_AUDITION"]!
        let sampleRate = 44100.0
        let fps = 60.0
        let seconds = 18.0

        // Three chimes standing still and one walking a circle past them, which
        // is the shape of the example sketch.
        let walker = Synth(.nylon, polyphony: 6)
        walker.gain = 0.5
        let posts = (0..<3).map { _ -> Synth in
            let synth = Synth(.chime, polyphony: 6)
            synth.gain = 0.4
            return synth
        }
        let postAt = (0..<3).map { index -> Vector3 in
            let angle = Double(index) * 2.094
            return Vector3(cos(angle) * 5, 0, sin(angle) * 5)
        }
        let tuning = Scale(.minorPentatonic, root: "A3")

        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }

        var elapsed = 0.0
        var lastStep = -10.0
        var lastRang = [Double](repeating: -10, count: 3)
        var walkerPitch = 0

        while elapsed < seconds {
            // The listener orbits, so the whole scene turns around the head as
            // well as the walker moving through it.
            let angle = elapsed * 0.24
            let eye = Vector3(cos(angle) * 13, 3, sin(angle) * 13)
            let camera = Camera3D(eye: eye, target: Vector3(0, 0.8, 0))

            let walkerAt = Vector3(cos(elapsed * 0.55) * 3.2, 0, sin(elapsed * 0.55) * 3.2)
            walker.place(at: walkerAt, heardFrom: camera)

            if elapsed - lastStep > 0.42 {
                lastStep = elapsed
                walkerPitch = (walkerPitch + 3) % 10
                walker.play(tuning[walkerPitch + 5], velocity: 0.75, for: 0.9)
            }

            for index in posts.indices {
                posts[index].place(at: postAt[index], heardFrom: camera)
                let apart = (walkerAt - postAt[index]).length
                if apart < 2.4, elapsed - lastRang[index] > 1.6 {
                    lastRang[index] = elapsed
                    posts[index].play(tuning[index * 2], velocity: 0.9, for: 3)
                }
            }

            for synth in [walker] + posts { synth.advance(by: 1 / fps) }
            elapsed += 1 / fps
        }

        // Mixed the way the exporters mix a sketch's instruments.
        let sketch = Sketch()
        let sources: [ExportAudioSource] = ([walker] + posts).map { $0 }
        let samples = sketch.renderSoundtrack(upTo: seconds, sampleRate: sampleRate,
                                              sources: sources)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path),
                                   settings: format.settings)
        let frames = samples.count / 2
        let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                      frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let channels = buffer.floatChannelData!
        for frame in 0..<frames {
            channels[0][frame] = samples[frame * 2]
            channels[1][frame] = samples[frame * 2 + 1]
        }
        try file.write(from: buffer)

        // What the numbers can say: both ears carry sound, and the balance
        // between them moves as the scene turns.
        var minRatio = Double.infinity, maxRatio = 0.0
        let window = Int(sampleRate)
        for start in stride(from: 0, to: frames - window, by: window) {
            var l = 0.0, r = 0.0
            for frame in start..<(start + window) {
                l += Double(samples[frame * 2]) * Double(samples[frame * 2])
                r += Double(samples[frame * 2 + 1]) * Double(samples[frame * 2 + 1])
            }
            guard r > 1e-12, l > 1e-12 else { continue }
            let ratio = (l / r).squareRoot()
            minRatio = min(minRatio, ratio)
            maxRatio = max(maxRatio, ratio)
        }
        print("audition: \(frames) frames, \(Double(frames) / sampleRate) s to \(path)")
        print(String(format: "  balance swing %.3f ... %.3f", minRatio, maxRatio))
        #expect(frames > Int(sampleRate))
        #expect(maxRatio > 1.3 && minRatio < 0.77, "the scene should move around the listener")
    }
}
