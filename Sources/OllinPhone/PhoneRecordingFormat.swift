// PhoneRecordingFormat: a recording of the phone's stream as a folder on disk,
// shared by the Ollin capture app (Apps/OllinPhoneApp), which writes it, and the
// Mac satellite (OllinPhone), which reads it.
//
// LOAD-BEARING: like PhoneWire.swift this file is compiled *verbatim into both
// ends*, so the Mac's tests write a recording with the exact code the phone
// runs. It imports AVFoundation, Compression, and their media types, and nothing
// of Ollin's.
//
// A recording is a folder holding three files:
//
//   stream.bin      the wire's own framed messages, each stamped with its
//                   capture time, in the order the phone made them
//   camera.mov      the camera's picture as HEVC video, one sample for each
//                   frame at the frame's own time, with the microphone's sound
//   recording.json  a short description: the mode, how the phone was held, the
//                   picture's size, how many frames, the format's version
//
// One rule keeps the picture and the data together: a frame goes to both files
// or to neither. The camera record for frame `k` is written only after the
// video took picture `k`, so the two files always count the same frames.

import AVFoundation
import Compression
import CoreMedia
import CoreVideo
import Foundation
import os
import simd

/// The names and the numbers of a recording on disk.
enum PhoneRecordingFile {
    /// What a recording's folder name ends in.
    static let folderExtension = "ollinrecording"
    static let streamName = "stream.bin"
    static let videoName = "camera.mov"
    static let descriptionName = "recording.json"

    /// The format's version, written into the description and the stream. A
    /// reader refuses a recording newer than it knows.
    static let formatVersion = 1

    /// The stream file's marker, "OLNS" as a little-endian `UInt32`.
    static let streamMagic: UInt32 = 0x4F4C_4E53

    /// The stream file opens with: magic(4) + version(1) + reserved(11).
    static let streamHeaderByteCount = 16

    /// Each record opens with: time(8) + flags(1) + kind(1) + reserved(2)
    /// + storedLength(4) + fullLength(4).
    static let recordHeaderByteCount = 20

    /// A wire frame at least this long is stored compressed when that makes it
    /// smaller. A depth map compresses to about half; a pose is not worth the
    /// call.
    static let compressionThreshold = 4096

    /// The longest wire frame there is, which bounds what a record may claim
    /// before anything is set aside for it.
    static let maxFrameBytes = PhoneWire.headerByteCount + PhoneWire.maxPayloadBytes

    /// The video's time scale: ticks to the second.
    static let videoTimeScale: CMTimeScale = 90_000
}

/// The short description that sits beside a recording's two big files.
struct PhoneRecordingDescription: Codable, Equatable, Sendable {
    /// The format's version (`PhoneRecordingFile.formatVersion` when written).
    var format: Int
    /// The mode the phone was in, as `PhoneCaptureMode`'s raw value, and its
    /// name for a person reading the file.
    var mode: Int
    var modeName: String
    /// Quarter turns clockwise that stand the picture upright for how the phone
    /// was held when the recording started. Held for the whole recording.
    var quarterTurnsCW: Int
    /// The picture's size as the sensor delivered it, before any turn.
    var pictureWidth: Int
    var pictureHeight: Int
    /// Whether the video carries the microphone's sound.
    var hasSound: Bool
    /// When the recording started, as an ISO 8601 date.
    var started: String
    /// The device that made it, as the device names itself.
    var device: String
    /// Whether the recording was closed properly. False in a recording whose
    /// app was stopped mid-way: its files hold what was written until then.
    var isFinished: Bool
    /// How many frames both files hold, and how many were dropped whole because
    /// the writer fell behind. Zero until the recording is finished.
    var frameCount: Int
    var droppedFrames: Int
    /// From the first frame to the last, in seconds.
    var duration: Double

    static func read(from url: URL) throws -> PhoneRecordingDescription {
        try JSONDecoder().decode(PhoneRecordingDescription.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// What opens each record of the stream file.
struct PhoneRecordingRecordHeader: Equatable, Sendable {
    /// The message's capture time, in seconds on the phone's own clock.
    var time: Double
    /// Whether the bytes that follow are compressed.
    var isCompressed: Bool
    /// The wire kind of the message, repeated here so a reader can index a
    /// recording without opening a compressed record.
    var kind: UInt8
    /// How many bytes follow in the file, and how long the wire frame is once
    /// it is opened.
    var storedLength: Int
    var fullLength: Int
}

/// The stream file's own framing: a short header, then one record per message.
enum PhoneRecordingStream {

    /// The bytes a stream file opens with.
    static func fileHeader() -> Data {
        var d = Data()
        LittleEndian.append(&d, PhoneRecordingFile.streamMagic)
        d.append(UInt8(PhoneRecordingFile.formatVersion))
        d.append(contentsOf: [UInt8](repeating: 0, count: PhoneRecordingFile.streamHeaderByteCount - 5))
        return d
    }

    /// The version a stream file says it is, or `nil` when the bytes are not a
    /// stream file's opening at all.
    static func version(ofFileHeader data: Data) -> Int? {
        guard data.count >= PhoneRecordingFile.streamHeaderByteCount,
              LittleEndian.u32(data, data.startIndex) == PhoneRecordingFile.streamMagic
        else { return nil }
        return Int(data[data.startIndex + 4])
    }

    /// One record: when the message was captured, then its wire frame, stored
    /// compressed when the frame is big and compressing it makes it smaller.
    static func record(time: Double, frame: Data) -> Data {
        var body = frame
        var compressed = false
        if frame.count >= PhoneRecordingFile.compressionThreshold,
           let smaller = compress(frame), smaller.count < frame.count {
            body = smaller
            compressed = true
        }
        var d = Data(capacity: PhoneRecordingFile.recordHeaderByteCount + body.count)
        LittleEndian.append(&d, time)
        d.append(compressed ? 1 : 0)
        // The kind sits at the same place in every wire header.
        d.append(frame.count > 5 ? frame[frame.startIndex + 5] : 0)
        d.append(0); d.append(0)
        LittleEndian.append(&d, UInt32(body.count))
        LittleEndian.append(&d, UInt32(frame.count))
        d.append(body)
        return d
    }

    /// Read the record header at `offset`, or `nil` when the file ends before a
    /// whole header, or the header claims more than a wire frame can be.
    ///
    /// Both lengths are bounded here, before anything adds to them or sets
    /// memory aside for them.
    static func recordHeader(in data: Data, at offset: Int) -> PhoneRecordingRecordHeader? {
        let count = PhoneRecordingFile.recordHeaderByteCount
        guard offset >= 0, data.count - offset >= count else { return nil }
        let s = data.startIndex + offset
        let time = LittleEndian.f64(data, s)
        let flags = data[s + 8]
        let kind = data[s + 9]
        let stored = Int(LittleEndian.u32(data, s + 12))
        let full = Int(LittleEndian.u32(data, s + 16))
        guard time.isFinite,
              stored >= 0, stored <= PhoneRecordingFile.maxFrameBytes,
              full >= PhoneWire.headerByteCount, full <= PhoneRecordingFile.maxFrameBytes
        else { return nil }
        let isCompressed = flags & 1 != 0
        guard isCompressed || stored == full else { return nil }
        return PhoneRecordingRecordHeader(time: time, isCompressed: isCompressed, kind: kind,
                                          storedLength: stored, fullLength: full)
    }

    /// The wire frame a record holds, opened if it was stored compressed, or
    /// `nil` when the file ends inside it or the bytes do not open to the
    /// length the header promised.
    static func frame(of header: PhoneRecordingRecordHeader, in data: Data, at offset: Int) -> Data? {
        let start = offset + PhoneRecordingFile.recordHeaderByteCount
        guard start >= 0, data.count - start >= header.storedLength else { return nil }
        let s = data.startIndex + start
        let stored = data.subdata(in: s ..< s + header.storedLength)
        guard header.isCompressed else { return stored }
        return decompress(stored, to: header.fullLength)
    }

    /// The message a record holds, decoded through the path the cable uses.
    static func message(of header: PhoneRecordingRecordHeader, in data: Data, at offset: Int) -> PhoneMessage? {
        guard let frame = frame(of: header, in: data, at: offset),
              let wire = PhoneHeader.parse(frame),
              frame.count - PhoneWire.headerByteCount >= wire.payloadLength else { return nil }
        let s = frame.startIndex + PhoneWire.headerByteCount
        return PhoneWire.decode(header: wire, payload: frame.subdata(in: s ..< s + wire.payloadLength))
    }

    private static func compress(_ data: Data) -> Data? {
        let capacity = data.count
        guard capacity > 0 else { return nil }
        var out = Data(count: capacity)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            data.withUnsafeBytes { src -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(d, capacity, s, data.count, nil, COMPRESSION_LZFSE)
            }
        }
        guard written > 0, written < capacity else { return nil }
        out.removeSubrange(written ..< out.count)
        return out
    }

    private static func decompress(_ data: Data, to length: Int) -> Data? {
        guard length > 0, length <= PhoneRecordingFile.maxFrameBytes, !data.isEmpty else { return nil }
        var out = Data(count: length)
        let written = out.withUnsafeMutableBytes { dst -> Int in
            data.withUnsafeBytes { src -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, length, s, data.count, nil, COMPRESSION_LZFSE)
            }
        }
        return written == length ? out : nil
    }
}

/// What a recording could not do while it was being written.
enum PhoneRecordingWriteError: Error, CustomStringConvertible {
    case folderExists(String)
    case cannotCreate(String)
    case video(String)

    var description: String {
        switch self {
        case .folderExists(let path): return "There is already a recording at \(path)."
        case .cannotCreate(let why): return "The recording could not be created: \(why)"
        case .video(let why): return "The recording's video could not be written: \(why)"
        }
    }
}

/// Writes a recording: the stream file, the video beside it, and the description.
///
/// Everything it is handed goes onto one serial queue, so the two files are
/// written by one thread in the order the calls were made, whichever threads
/// made them (the camera's frames arrive on one, the microphone's sound on
/// another). `@unchecked Sendable` asserts exactly that: the mutable state below
/// is touched only on `queue`, and the two counters read from outside sit behind
/// a lock.
///
/// The picture's size is known only when the first frame arrives, so the video
/// is opened then rather than at `init`.
final class PhoneRecordingWriter: @unchecked Sendable {

    /// The folder being written.
    let folder: URL

    /// How many pictures may wait to be written before a live writer drops the
    /// next frame whole. A waiting picture holds one of the camera's own
    /// buffers, and the camera has only a few to lend.
    static let maxPicturesWaiting = 3

    private let queue = DispatchQueue(label: "dev.ollin.recording.writer", qos: .userInitiated)
    private let isRealTime: Bool
    private let framesPerSecond: Double
    private let wantsSound: Bool
    private let bitRate: Int?
    private let streamHandle: FileHandle

    // Touched only on `queue`.
    private var description: PhoneRecordingDescription
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var soundInput: AVAssetWriterInput?
    private var firstTime: Double?
    private var lastTime: Double?
    private var failure: String?
    private var isClosed = false

    private struct Counts {
        var frames = 0
        var dropped = 0
        var waiting = 0
    }
    private let counts = OSAllocatedUnfairLock(initialState: Counts())

    /// How many frames both files hold so far.
    var frameCount: Int { counts.withLock { $0.frames } }
    /// How many frames were dropped whole so far.
    var droppedFrames: Int { counts.withLock { $0.dropped } }

    /// Create the folder and open the stream file.
    ///
    /// `isRealTime` is how the phone writes: a frame that finds the video busy is
    /// dropped from both files. A writer that is not live (the Mac making a
    /// recording of a known scene) waits for the video instead, so it keeps
    /// every frame. `bitRate` names the video's bit rate in place of the one
    /// worked out from the picture's size.
    init(folder: URL, mode: PhoneCaptureMode, quarterTurnsCW: UInt8, device: String,
         started: Date = Date(), framesPerSecond: Double = 60, wantsSound: Bool = false,
         isRealTime: Bool = true, bitRate: Int? = nil) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: folder.path) else {
            throw PhoneRecordingWriteError.folderExists(folder.path)
        }
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw PhoneRecordingWriteError.cannotCreate(error.localizedDescription)
        }
        let streamURL = folder.appendingPathComponent(PhoneRecordingFile.streamName)
        guard manager.createFile(atPath: streamURL.path, contents: PhoneRecordingStream.fileHeader()),
              let handle = try? FileHandle(forWritingTo: streamURL) else {
            throw PhoneRecordingWriteError.cannotCreate("the stream file would not open")
        }
        _ = try? handle.seekToEnd()
        self.folder = folder
        self.streamHandle = handle
        self.isRealTime = isRealTime
        self.framesPerSecond = max(1, framesPerSecond)
        self.wantsSound = wantsSound
        self.bitRate = bitRate
        let formatter = ISO8601DateFormatter()
        description = PhoneRecordingDescription(
            format: PhoneRecordingFile.formatVersion, mode: Int(mode.rawValue), modeName: mode.title,
            quarterTurnsCW: Int(quarterTurnsCW % 4), pictureWidth: 0, pictureHeight: 0,
            hasSound: false, started: formatter.string(from: started), device: device,
            isFinished: false, frameCount: 0, droppedFrames: 0, duration: 0)
        // The description is on disk from the start, marked unfinished, so a
        // recording whose app was stopped mid-way still says what it is.
        try? description.write(to: folder.appendingPathComponent(PhoneRecordingFile.descriptionName))
    }

    // MARK: Appending

    /// One frame of the camera: its picture into the video and its record into
    /// the stream, or neither.
    ///
    /// The record's `frameIndex` is written by the writer, as the count of
    /// frames the video has taken, and its turn count is the recording's own.
    /// A live writer that is already behind drops the frame here, before it
    /// holds the camera's buffer.
    func append(picture: CVPixelBuffer, camera: PhoneCameraSample) {
        if isRealTime {
            let behind = counts.withLock { state -> Bool in
                if state.waiting >= Self.maxPicturesWaiting {
                    state.dropped += 1
                    return true
                }
                state.waiting += 1
                return false
            }
            if behind { return }
        }
        let box = Unchecked(picture)
        queue.async { [self] in
            if isRealTime { counts.withLock { $0.waiting -= 1 } }
            write(picture: box.value, camera: camera)
        }
    }

    /// Any other message, stamped with the time it was captured. A depth frame
    /// is written without its small JPEG, since the video holds the picture.
    func append(_ message: PhoneMessage, at time: Double) {
        queue.async { [self] in
            guard !isClosed else { return }
            var stored = message
            if case .depth(var depth) = message {
                depth.colorJPEG = Data()
                stored = .depth(depth)
            }
            writeRecord(time: time, PhoneWire.encode(stored))
        }
    }

    /// A stretch of the microphone's sound, on the same clock as the frames.
    /// Ignored until the first frame has opened the video.
    func append(sound sampleBuffer: CMSampleBuffer) {
        let box = Unchecked(sampleBuffer)
        queue.async { [self] in
            guard !isClosed, failure == nil, let soundInput, writer?.status == .writing,
                  soundInput.isReadyForMoreMediaData else { return }
            if soundInput.append(box.value) {
                description.hasSound = true
            }
        }
    }

    /// Close both files and write the finished description. Returns it, or
    /// throws what went wrong with the video.
    func finish() async throws -> PhoneRecordingDescription {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                close { result in continuation.resume(with: result) }
            }
        }
    }

    /// Wait until everything handed over so far has been written. A test uses
    /// it to look at a recording that was never finished, the way a recording
    /// is left when its app is stopped mid-way.
    func drain() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { continuation.resume() }
        }
    }

    // MARK: On the queue

    private func write(picture: CVPixelBuffer, camera: PhoneCameraSample) {
        guard !isClosed, failure == nil else { return }
        if writer == nil { openVideo(for: picture, at: camera.timestamp) }
        guard failure == nil, let videoInput, let adaptor else { return }

        // A frame must be later than the one before it, or the video refuses it.
        if let lastTime, camera.timestamp <= lastTime {
            counts.withLock { $0.dropped += 1 }
            return
        }
        if !isRealTime {
            // Not live: wait for the video rather than lose the frame.
            var waited = 0
            while !videoInput.isReadyForMoreMediaData, writer?.status == .writing, waited < 20_000 {
                usleep(500)
                waited += 1
            }
        }
        let time = CMTime(seconds: camera.timestamp,
                          preferredTimescale: PhoneRecordingFile.videoTimeScale)
        guard videoInput.isReadyForMoreMediaData,
              adaptor.append(picture, withPresentationTime: time) else {
            counts.withLock { $0.dropped += 1 }
            if writer?.status == .failed {
                failure = writer?.error?.localizedDescription ?? "the video writer stopped"
            }
            return
        }
        // The video took the picture, so the record follows it.
        var record = camera
        record.frameIndex = UInt32(clamping: counts.withLock { $0.frames })
        record.quarterTurnsCW = UInt8(description.quarterTurnsCW)
        writeRecord(time: camera.timestamp, PhoneWire.encode(.camera(record)))
        counts.withLock { $0.frames += 1 }
        lastTime = camera.timestamp
    }

    private func writeRecord(time: Double, _ frame: Data) {
        try? streamHandle.write(contentsOf: PhoneRecordingStream.record(time: time, frame: frame))
    }

    private func openVideo(for picture: CVPixelBuffer, at time: Double) {
        let width = CVPixelBufferGetWidth(picture), height = CVPixelBufferGetHeight(picture)
        description.pictureWidth = width
        description.pictureHeight = height
        let url = folder.appendingPathComponent(PhoneRecordingFile.videoName)
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            // A second of pictures at most is lost if the app is stopped mid-way.
            writer.movieFragmentInterval = CMTime(seconds: 1, preferredTimescale: 600)

            let compression: [String: Any] = [
                AVVideoAverageBitRateKey: bitRate ?? Self.bitRate(
                    width: width, height: height, framesPerSecond: framesPerSecond),
                AVVideoExpectedSourceFrameRateKey: framesPerSecond,
                // A picture that stands alone every half second, so a reader
                // asked for any frame decodes few to reach it, and no picture
                // that waits on a later one, so the file's order is time's order.
                AVVideoMaxKeyFrameIntervalKey: max(1, Int((framesPerSecond / 2).rounded())),
                AVVideoAllowFrameReorderingKey: false,
            ]
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compression,
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = isRealTime
            input.mediaTimeScale = PhoneRecordingFile.videoTimeScale
            // So a player shows it upright; the Mac turns the frames itself.
            input.transform = CGAffineTransform(
                rotationAngle: CGFloat(description.quarterTurnsCW) * .pi / 2)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input, sourcePixelBufferAttributes: nil)
            guard writer.canAdd(input) else {
                failure = "the video track was refused"
                return
            }
            writer.add(input)

            if wantsSound {
                let sound = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 96_000,
                ])
                sound.expectsMediaDataInRealTime = isRealTime
                if writer.canAdd(sound) {
                    writer.add(sound)
                    soundInput = sound
                }
            }

            guard writer.startWriting() else {
                failure = writer.error?.localizedDescription ?? "the video would not start"
                return
            }
            // The session starts at the first frame's own time, so the video
            // opens on that frame and every later sample, picture or sound,
            // is placed by the clock the frames are stamped on.
            writer.startSession(atSourceTime: CMTime(
                seconds: time, preferredTimescale: PhoneRecordingFile.videoTimeScale))
            self.writer = writer
            self.videoInput = input
            self.adaptor = adaptor
            self.firstTime = time
        } catch {
            failure = error.localizedDescription
        }
    }

    private func close(_ completion: @escaping @Sendable (Result<PhoneRecordingDescription, Error>) -> Void) {
        guard !isClosed else {
            completion(.success(description))
            return
        }
        isClosed = true
        try? streamHandle.close()

        let frames = counts.withLock { $0.frames }
        description.frameCount = frames
        description.droppedFrames = counts.withLock { $0.dropped }
        if let firstTime, let lastTime { description.duration = lastTime - firstTime }
        let descriptionURL = folder.appendingPathComponent(PhoneRecordingFile.descriptionName)

        guard let writer, failure == nil else {
            // No frame ever arrived, or the video failed: say so, and leave the
            // description marked unfinished.
            try? description.write(to: descriptionURL)
            completion(.failure(PhoneRecordingWriteError.video(failure ?? "no frame was recorded")))
            return
        }
        videoInput?.markAsFinished()
        soundInput?.markAsFinished()
        let finished = Unchecked(writer)
        let unfinished = description
        writer.finishWriting {
            let writer = finished.value
            guard writer.status == .completed else {
                try? unfinished.write(to: descriptionURL)
                completion(.failure(PhoneRecordingWriteError.video(
                    writer.error?.localizedDescription ?? "the video would not close")))
                return
            }
            var closed = unfinished
            closed.isFinished = true
            do {
                try closed.write(to: descriptionURL)
                completion(.success(closed))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// A copy of a sound buffer with its times moved from one clock to
    /// another, or `nil` when the buffer carries no timing to move.
    ///
    /// A microphone stamps its buffers on its own clock and a camera frame is
    /// stamped on the system's, so the phone converts each buffer before it is
    /// written, and the sound lands where the frames say it happened.
    static func restamped(_ sampleBuffer: CMSampleBuffer, from source: CMClock,
                          to destination: CMClock) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr,
              count > 0 else { return nil }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(
                sampleBuffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count) == noErr
        else { return nil }
        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = CMSyncConvertTime(
                    timing[index].presentationTimeStamp, from: source, to: destination)
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMSyncConvertTime(
                    timing[index].decodeTimeStamp, from: source, to: destination)
            }
        }
        var copy: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: count, sampleTimingArray: &timing,
                sampleBufferOut: &copy) == noErr else { return nil }
        return copy
    }

    /// The bit rate a picture size is written at: about a tenth of a bit for
    /// every pixel of every frame, which keeps the grain of a wall, held to a
    /// range a phone's storage and its encoder both take.
    static func bitRate(width: Int, height: Int, framesPerSecond: Double) -> Int {
        let rate = Double(width * height) * framesPerSecond * 0.1
        return Int(min(max(rate, 2_000_000), 60_000_000))
    }
}

/// The stream file's numbers, little-endian like the wire's own.
private enum LittleEndian {
    static func append(_ d: inout Data, _ v: UInt32) {
        var le = v.littleEndian
        withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }

    static func append(_ d: inout Data, _ v: Double) {
        var le = v.bitPattern.littleEndian
        withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }

    static func u32(_ d: Data, _ i: Data.Index) -> UInt32 {
        UInt32(d[i]) | (UInt32(d[i + 1]) << 8) | (UInt32(d[i + 2]) << 16) | (UInt32(d[i + 3]) << 24)
    }

    static func f64(_ d: Data, _ i: Data.Index) -> Double {
        var bits: UInt64 = 0
        for byte in 0..<8 { bits |= UInt64(d[i + byte]) << UInt64(8 * byte) }
        return Double(bitPattern: bits)
    }
}

/// Carries a media object the compiler cannot vouch for across to the writer's
/// queue. The promise is the writer's: the object is handed over once and only
/// the queue touches it afterwards.
private struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
