import AVFoundation
import Compression
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import OllinMutation
@testable import OllinAudio
@testable import OllinRecord3D

/// The recordings a sketch is handed: an `.r3d` depth recording (a zip of a
/// metadata file and per-frame pictures, depth, and confidence), sound files
/// in the three containers people record into, and an SFZ instrument that
/// names them. Each is read the way a sketch reads it: a recording's frames
/// decoded and unprojected, a sound turned into the reverb that convolves
/// with it and the grains that scatter it, an instrument played across its
/// range.
@Suite(.enabled(if: !underThreadSanitizer, fileRunReason))
struct RecordingAndSoundFileMutationTests {

    // MARK: Depth recordings

    @Test func depthRecordings() throws {
        let seed = Self.recording()
        let report = MutationRun.run("r3d-recording", seeds: [seed], count: 400, allocations: fileBound) { bytes in
            let recording = try Record3DRecording(data: Data(bytes))
            _ = recording.intrinsics
            for index in 0..<min(recording.frameCount, 3) {
                _ = try? recording.pose(at: index)
                if let frame = try? recording.frame(at: index) {
                    _ = frame.pointCloud(minConfidence: .low, step: 1)
                    _ = frame.depth(atNormalizedX: 0.5, y: 0.5)
                    _ = frame.unproject(normalizedX: 0.25, y: 0.75)
                }
            }
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    /// A one-frame recording: a 16 by 12 picture, an 8 by 6 depth map, and its
    /// confidence, with the metadata deflated the way a capture app writes it.
    static func recording() -> [UInt8] {
        let metadata: [String: Any] = ["K": [16.0, 0, 0, 0, 16.0, 0, 8.0, 6.0, 1.0], "w": 16, "h": 12, "fps": 30.0,
                                       "poses": [[0, 0, 0, 1, 0.1, 0.2, 0.3]]]
        // Sorted, or the seed's bytes (and so every case number) change with
        // the process's hash seed.
        let meta = (try? JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])) ?? Data()
        let depth = [Float](repeating: 1.5, count: 48).withUnsafeBytes { Data($0) }
        let confidence = Data([UInt8](repeating: 2, count: 48))
        return ZipSeed.make([("metadata", [UInt8](meta), true),
                             ("rgbd/0.jpg", jpeg(width: 16, height: 12), false),
                             ("rgbd/0.depth", lzfse([UInt8](depth)), false),
                             ("rgbd/0.conf", lzfse([UInt8](confidence)), false)])
    }

    static func jpeg(width: Int, height: Int) -> [UInt8] {
        let data = NSMutableData()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.setFillColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return [] }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return [UInt8](data as Data)
    }

    static func lzfse(_ bytes: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: bytes.count + 4096)
        let written = compression_encode_buffer(&out, out.count, bytes, bytes.count, nil, COMPRESSION_LZFSE)
        return Array(out.prefix(written))
    }

    // MARK: Sound files

    @Test(arguments: ["wav", "aif", "caf"])
    func soundFiles(_ ext: String) throws {
        let folder = ScratchFolder("sound-\(ext)")
        let seed = try #require(try Self.soundSeeds(in: folder).first { $0.0 == ext }?.1)
        // The field sweep goes where the headers keep 32-bit sizes (a WAV's
        // chunks, a CAF's packet description); an AIFF's are read by the
        // random edits alone.
        let report = MutationRun.run("sound-\(ext)", seeds: [seed], count: 150, sweeps: ext != "aif",
                                     allocations: fileBound) { bytes in
            let url = folder.write(bytes, named: "case.\(ext)")
            guard let frames = try AudioFileFrames.read(url) else { return false }
            _ = frames.buffer()
            _ = frames.mono
            // The player, the grain source, the instrument, and the
            // classifier all read through `AudioFileFrames`; the impulse
            // response adds its own limit and the reverb's preparation.
            if let impulse = try? ImpulseResponse(contentsOf: url) {
                _ = impulse.prepared(at: 48000, preDelay: 0.05)
                _ = impulse.reversed()
            }
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    /// A short tone written in the three containers and sample layouts a
    /// recording arrives in: 16-bit WAV, 24-bit AIFF, float CAF in stereo.
    static func soundSeeds(in folder: ScratchFolder) throws -> [(String, [UInt8])] {
        let layouts: [(String, [String: Any])] = [
            ("wav", [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 8000, AVNumberOfChannelsKey: 1,
                     AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]),
            ("aif", [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 11025, AVNumberOfChannelsKey: 1,
                     AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true]),
            ("caf", [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 22050, AVNumberOfChannelsKey: 2,
                     AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false]),
        ]
        return try layouts.map { ext, settings in
            let url = folder.url.appendingPathComponent("seed.\(ext)")
            do {
                let file = try AVAudioFile(forWriting: url, settings: settings)
                let format = file.processingFormat
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96))
                buffer.frameLength = 96
                for channel in 0..<Int(format.channelCount) {
                    for i in 0..<96 { buffer.floatChannelData![channel][i] = Float(sin(Double(i) * 0.3)) * 0.5 }
                }
                try file.write(from: buffer)
            }
            return (ext, [UInt8](try Data(contentsOf: url)))
        }
    }

    // MARK: Instruments

    @Test func sfzInstruments() throws {
        let folder = ScratchFolder("sfz")
        let sounds = try Self.soundSeeds(in: folder)
        for (ext, bytes) in sounds { folder.write(bytes, named: "tone.\(ext)") }
        let instrument = """
        // a small instrument
        <global> volume=-3
        <group> lovel=1 hivel=127 loop_mode=loop_continuous loop_start=4 loop_end=80
        <region> sample=tone.wav lokey=c3 hikey=b3 pitch_keycenter=f#3 tune=-12
        <region> sample=tone.aif key=60 transpose=1 volume=2.5
        <region> sample=sub\\tone.caf lokey=61 hikey=127 pitch_keycenter=72 lovel=64
        """
        try FileManager.default.createDirectory(at: folder.url.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        folder.write(sounds[2].1, named: "sub/tone.caf")
        let spec = Sampler(loops: true)
        let report = MutationRun.run("sfz-instrument", seeds: [instrument.bytes], count: 300, sweeps: false,
                                     numberSweep: true, allocations: fileBound) { bytes in
            let url = folder.write(bytes, named: "case.sfz")
            let played = try SampledInstrument(contentsOf: url)
            for key in [0.0, 48, 60, 61, 72, 127, 140] {
                var voice = SamplerVoice()
                voice.start(instrument: played, pitch: key, velocity: 0.7, spec: spec, sampleRate: 48000)
                for _ in 0..<400 { _ = voice.next() }
            }
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }
}
