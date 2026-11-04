import AVFoundation
import Foundation
import Metal
import Testing
@testable import Ollin
@testable import OllinAudio

/// The sketch's own sound as a file of its own: beside a frame sequence, and
/// alone from `exportAudio`, which drives the sketch with no renderer. Both are
/// the video track's pump into a lossless file on the sketch's clock, with a
/// skipped stretch dropped before the first frame.
@Suite(.serialized) struct SoundtrackFileTests {
    /// A bell at a tenth of a second and another at one and a tenth.
    final class TwoBells: Sketch {
        let synth = Synth(.bell)
        override var canvasSize: CanvasSize { .square(32) }
        override func draw() {
            background(.white)
            if abs(time - 0.1) < 1e-4 || abs(time - 1.1) < 1e-4 {
                synth.play(72, velocity: 0.9, for: 0.3)
            }
        }
    }

    final class Mute: Sketch {
        override var canvasSize: CanvasSize { .square(32) }
        override func draw() { background(.white) }
    }

    private func scratch(_ name: String) -> String {
        let dir = NSTemporaryDirectory() + "ollin-soundtrack-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/" + name
    }

    /// The left channel of a file, and its rate.
    private func samples(of path: String) throws -> (left: [Float], rate: Double) {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
        let format = file.processingFormat
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format,
                                                   frameCapacity: AVAudioFrameCount(max(file.length, 1))))
        try file.read(into: buffer)
        let data = try #require(buffer.floatChannelData)
        let count = Int(buffer.frameLength)
        var left = [Float]()
        left.reserveCapacity(count)
        if format.isInterleaved {
            let channels = Int(format.channelCount)
            for i in 0 ..< count { left.append(data[0][i * channels]) }
        } else {
            left = Array(UnsafeBufferPointer(start: data[0], count: count))
        }
        return (left, format.sampleRate)
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
    }

    /// The file is as long as the frames and begins where they do: a file
    /// that skipped a second is the second half of the unskipped file, sample
    /// for sample, with the bell at 1.1 s of the sketch's clock at 0.1 s of
    /// the file and the tail of the earlier bell still ringing into it, the
    /// way the picture would show it.
    @MainActor
    @Test func anAudioExportBeginsWhereTheFramesDo() throws {
        let skipped = scratch("skip.wav")
        let whole = scratch("whole.wav")
        try OllinApp.exportAudio(TwoBells(), to: skipped, frames: 60, fps: 60, skipSeconds: 1)
        try OllinApp.exportAudio(TwoBells(), to: whole, frames: 120, fps: 60)
        let (left, rate) = try samples(of: skipped)
        let (all, _) = try samples(of: whole)
        #expect(rate == 44100)
        #expect(left.count == 44100)
        #expect(all.count == 88200)
        let tail = all[44100...]
        let worst = zip(left, tail).map { abs($0 - $1) }.max() ?? 1
        #expect(worst < 1e-3, "the skipped file strays from the whole file's tail by \(worst)")
        let quiet = rms(left[0 ..< Int(0.08 * rate)])
        let loud = rms(left[Int(0.12 * rate) ..< Int(0.3 * rate)])
        #expect(loud > 3 * quiet, "the bell at 1.1 s did not land at 0.1 s of the file")
    }

    /// A sequence writes the soundtrack beside its frames, and it is the
    /// audio-only export's file sample for sample: the same notes on the same
    /// clock through the same renderer, with or without a GPU in the room.
    @MainActor
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func aSequenceWritesTheSameSoundBesideItsFrames() throws {
        let dir = scratch("frames")
        let alone = scratch("alone.wav")
        try OllinApp.exportSequence(TwoBells(), to: dir, frames: 90, fps: 60)
        try OllinApp.exportAudio(TwoBells(), to: alone, frames: 90, fps: 60)
        let beside = try samples(of: dir + "/soundtrack.wav")
        let own = try samples(of: alone)
        #expect(beside.left.count == 90 * 735)   // 44100 / 60 a frame
        #expect(beside.left == own.left)
        #expect(beside.left.contains { abs($0) > 0.02 })
        #expect(FileManager.default.fileExists(atPath: dir + "/frame-00001.png"))
    }

    /// A sketch that holds no instrument writes no soundtrack beside its
    /// frames, and the audio-only export refuses it by name.
    @MainActor
    @Test func aSketchWithNoInstrumentWritesNoSoundtrack() throws {
        let path = scratch("none.wav")
        #expect(throws: ExportError.self) {
            try OllinApp.exportAudio(Mute(), to: path, frames: 10)
        }
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
