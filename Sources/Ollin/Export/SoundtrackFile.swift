import AVFoundation
import Foundation

/// The sketch's own sound written to a file of its own: beside a frame
/// sequence, or alone from `OllinApp.exportAudio`. Interleaved stereo 32-bit
/// float at the soundtrack rate, lossless, for a muxer to encode once. Pumped
/// a frame at a time the way the video track is, so the notes are rendered
/// forward as they are asked for and nothing waits for the end.
@MainActor
final class SoundtrackFile {
    /// The file a sequence writes beside its frames.
    static let sequenceName = "soundtrack.wav"

    let path: String
    private let file: AVAudioFile
    private let sources: [ExportAudioSource]
    private let skipSeconds: Double
    private var droppedSkip = false
    /// Sample frames written so far, one left and one right each.
    private(set) var framesWritten = 0

    /// Opens the file for a sketch that holds a sound source, after its
    /// `setup()` has run so the source can be found; `nil` for a sketch that
    /// holds none, which writes no file. `skipSeconds` of the sketch's own clock
    /// run before the first written frame, and the sound of that stretch is
    /// rendered and dropped at the first pump, so the file starts where the
    /// frames do.
    init?(for sketch: Sketch, at path: String, skipSeconds: Double) throws {
        let sources = sketch.exportAudioSources()
        guard !sources.isEmpty else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: OllinApp.soundtrackSampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        do {
            file = try AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: true)
        } catch {
            throw ExportError(.unwritable, path: path,
                              problem: "the soundtrack could not be opened for writing: \(error.localizedDescription)")
        }
        self.path = path
        self.sources = sources
        self.skipSeconds = max(0, skipSeconds)
    }

    /// Write the sound up to `seconds` of the sketch's clock, from wherever the
    /// last pump stopped. The skipped stretch goes first and is dropped.
    func pump(_ sketch: Sketch, upTo seconds: Double) throws {
        if !droppedSkip {
            droppedSkip = true
            if skipSeconds > 0 {
                _ = sketch.renderSoundtrack(upTo: skipSeconds, sampleRate: OllinApp.soundtrackSampleRate,
                                            sources: sources)
            }
        }
        let samples = sketch.renderSoundtrack(upTo: seconds, sampleRate: OllinApp.soundtrackSampleRate,
                                              sources: sources)
        guard !samples.isEmpty else { return }
        let frames = samples.count / 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else {
            throw ExportError(.unwritable, path: path, problem: "no buffer could be made for the soundtrack")
        }
        // Interleaved, so the one channel pointer holds left and right in turn,
        // which is the order the mixer left them in.
        samples.withUnsafeBufferPointer { source in
            channels[0].update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        do {
            try file.write(from: buffer)
        } catch {
            throw ExportError(.unwritable, path: path,
                              problem: "the soundtrack could not be written: \(error.localizedDescription)")
        }
        framesWritten += frames
    }

    /// Write what is left up to `seconds` and close the file.
    func finish(_ sketch: Sketch, upTo seconds: Double) throws {
        try pump(sketch, upTo: seconds)
        file.close()
    }
}
