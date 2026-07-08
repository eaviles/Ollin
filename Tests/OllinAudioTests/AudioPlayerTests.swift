import AVFoundation
import Foundation
import Testing
import Ollin
@testable import OllinAudio

/// The deterministic headless-export path: under `isRenderingHeadless` an
/// `AudioPlayer` follows the export clock (a sample playhead through the
/// decoded file) instead of the live engine, so an audio-reactive sketch
/// exports the same frames on every run. The file under test is synthesized
/// into a temp directory, so no asset ships and no audio hardware plays.
@Suite(.serialized) @MainActor
struct AudioPlayerTests {

    static let sampleRate = 44100.0

    /// Writes a mono wav: a kick-style click every half second (a 55 Hz thump
    /// plus a 2.8 kHz tick, sharp decays) over a held 110 Hz tone.
    static func writeClickTrack(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-clicktrack-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let count = Int(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                      frameCapacity: AVAudioFrameCount(count))!
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let sinceClick = t.truncatingRemainder(dividingBy: 0.5)
            var s = sin(t * 55 * 2 * .pi) * 0.6 * exp(-sinceClick * 9)
            s += sin(t * 2800 * 2 * .pi) * 0.3 * exp(-sinceClick * 70)
            s += sin(t * 110 * 2 * .pi) * 0.2
            buffer.floatChannelData![0][i] = Float(s)
        }
        buffer.frameLength = AVAudioFrameCount(count)
        try file.write(from: buffer)
        return url
    }

    /// Advances a playing headless player frame by frame and returns the frame
    /// index of every beat.
    static func beatFrames(of player: AudioPlayer, frames: Int, fps: Double = 60) -> [Int] {
        var last = 0
        var result: [Int] = []
        for frame in 0..<frames {
            player.advance(by: 1 / fps)
            if player.analyzer.beatCount > last {
                last = player.analyzer.beatCount
                result.append(frame)
            }
        }
        return result
    }

    /// Frame k of a headless run reads the file at k/fps: every half-second
    /// click lands as a beat within a frame or two of its position.
    @Test func headlessExportFollowsTheClock() throws {
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }

        let url = try Self.writeClickTrack(seconds: 2.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let player = try AudioPlayer(url: url, fftSize: 2048)
        player.play()
        #expect(player.isPlaying)

        let beats = Self.beatFrames(of: player, frames: 150)
        #expect(beats.count == 5)
        for frame in beats {
            // Clicks land every 30 frames at 60 fps; allow the analysis chunk.
            let sinceClick = frame % 30
            #expect(sinceClick <= 3)
        }
        #expect(player.analyzer.amplitude > 0)
    }

    /// Two headless runs of the same file produce identical detections: the
    /// whole path is on the sample clock, no wall clock anywhere.
    @Test func headlessRunsAreIdentical() throws {
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }

        let url = try Self.writeClickTrack(seconds: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        var runs: [[Int]] = []
        for _ in 0..<2 {
            let player = try AudioPlayer(url: url, fftSize: 2048)
            player.play()
            runs.append(Self.beatFrames(of: player, frames: 120))
        }
        #expect(runs[0] == runs[1])
        #expect(!runs[0].isEmpty)
    }

    /// A non-looping file stops at its end; a looping one keeps playing and
    /// keeps detecting through the wrap.
    @Test func headlessEndAndLoopSemantics() throws {
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }

        let url = try Self.writeClickTrack(seconds: 1)
        defer { try? FileManager.default.removeItem(at: url) }

        let once = try AudioPlayer(url: url, fftSize: 2048)
        once.play()
        _ = Self.beatFrames(of: once, frames: 90)      // 1.5 s through a 1 s file
        #expect(!once.isPlaying)

        let looped = try AudioPlayer(url: url, fftSize: 2048)
        looped.loops = true
        looped.play()
        let beats = Self.beatFrames(of: looped, frames: 150)   // 2.5 s
        #expect(looped.isPlaying)
        #expect(beats.count >= 4)                       // clicks keep arriving past the wrap
    }
}
