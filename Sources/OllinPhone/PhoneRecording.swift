import Foundation
import CoreGraphics
import simd
import Ollin

/// What a recording could not do.
public enum PhoneRecordingError: Error, CustomStringConvertible, Sendable {
    /// Nothing is at the path.
    case notFound(String)
    /// The bundle holds no resource of that name.
    case resourceNotFound(String)
    /// The folder is there and one of a recording's three files is not.
    case notARecording(String)
    /// A file is there and does not read as what it should be.
    case unreadable(String)
    /// The recording was made by a newer capture app than this reader knows.
    case newerFormat(Int)
    /// The picture and the camera's record stop being the same instant at this
    /// frame: one of the two files lost a frame the other kept.
    case framesDisagree(frame: Int)
    /// A frame number outside the recording.
    case frameOutOfRange(Int, count: Int)
    /// The video would not give up this frame's picture.
    case pictureUnavailable(Int)

    public var description: String {
        switch self {
        case .notFound(let path):
            return "There is no recording at \(path)."
        case .resourceNotFound(let name):
            return "The bundle holds no recording named \(name)."
        case .notARecording(let why):
            return "That folder is not a recording: \(why)"
        case .unreadable(let why):
            return "The recording does not read: \(why)"
        case .newerFormat(let version):
            return "The recording is format \(version), newer than this reader. Update Ollin on the Mac."
        case .framesDisagree(let frame):
            return "The recording's picture and its camera records disagree from frame \(frame) on."
        case .frameOutOfRange(let frame, let count):
            return "Frame \(frame) is outside the recording, which holds \(count)."
        case .pictureUnavailable(let frame):
            return "The recording's video would not give the picture of frame \(frame)."
        }
    }
}

/// A recording the Ollin capture app made: the camera's video with everything
/// the phone sensed beside it, frame for frame, opened for playing.
///
/// Press **Record** in the capture app, with no cable, in any mode that runs the
/// camera. The recording is a folder in the app's own documents (the Files app
/// and Finder both show it); bring it to the Mac and hand it to a device:
///
/// ```swift
/// final class Pins: Sketch {
///     let device = PhoneDevice(playing: try! PhoneRecording(path: "~/Movies/Walk.ollinrecording"))
///
///     override func setup() { device.start() }
///
///     override func draw() {
///         guard let view = device.latestCamera else {
///             return drawStatus(device.waitingMessage, style: .info)
///         }
///         drawPhonePicture(view)
///         camera(view)
///         // ...draw in the room, in meters
///     }
/// }
/// ```
///
/// The device is the same object the cable feeds, so everything else it
/// reports (planes, a body, hands, the room's light) arrives from the
/// recording too, at the frame it was sensed on.
///
/// The recording plays on the sketch's clock: it advances by what the sketch's
/// `time` advances by, so it holds while the sketch is paused, and under an
/// export frame `n` of the output is always the same frame of the recording.
/// `pause()`, `seek(to:)`, and `seek(toFrame:)` move it by hand, and
/// `camera(at:)` reads any frame without moving it.
@MainActor
public final class PhoneRecording {

    /// Where the recording is on disk.
    public let path: String
    /// The folder's name without its extension.
    public let name: String
    /// The mode the phone was in while it recorded.
    public let mode: PhoneCaptureMode
    /// How many frames the recording holds.
    public let frameCount: Int
    /// From the first frame to the last, in seconds.
    public let duration: Double
    /// Frames to the second, measured over the whole recording.
    public let frameRate: Double
    /// The picture's size in pixels, upright for how the phone was held.
    public let pictureSize: Vector2
    /// Whether the recording's video carries the microphone's sound.
    public let hasSound: Bool
    /// Whether the recording was closed properly. False for one whose app was
    /// stopped mid-way, which plays up to the last frame both files hold.
    public let isComplete: Bool

    /// Whether the recording starts over when it reaches its end. On by
    /// default; off, it holds its last frame.
    public var loops = true

    /// Whether the recording is advancing with the sketch's clock.
    public private(set) var isPlaying = true

    /// The last thing that went wrong while playing, as a sentence, or `nil`.
    /// Set when a frame's picture would not decode, and cleared when one
    /// decodes again.
    public private(set) var lastError: String?

    // MARK: What is on disk

    struct Entry: Sendable {
        var offset: Int
        var header: PhoneRecordingRecordHeader
    }

    private let stream: Data
    private let entries: [Entry]
    /// Each frame's camera record, and where in `entries` it sits.
    private let frames: [PhoneCameraSample]
    private let frameEntry: [Int]
    /// Each frame's time, in seconds from the first.
    private let frameTimes: [Double]
    private let video: PhoneRecordingVideo
    private let quarterTurnsCW: Int

    // MARK: The playhead

    private var position = 0.0
    private var anchorClock: Double?
    private var anchorPosition = 0.0

    // One decoded picture of each kind, kept by frame so several reads in one
    // `draw()` share a texture.
    private var uprightImage: (frame: Int, image: Image)?
    private var sensorImage: (frame: Int, image: Image)?

    // MARK: Opening

    /// Open the recording at `path` (a leading `~` is the home folder).
    ///
    /// Throws when nothing is there, when the folder is not a recording, when
    /// one of its files does not read, and when the picture and the camera's
    /// records are not the same frames.
    public convenience init(path: String) throws {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            throw PhoneRecordingError.notFound(path)
        }
        try self.init(folder: URL(fileURLWithPath: expanded))
    }

    /// Open a recording bundled with the sketch.
    public convenience init(resource: String, withExtension ext: String, in bundle: Bundle) throws {
        guard let url = bundle.url(forResource: resource, withExtension: ext) else {
            throw PhoneRecordingError.resourceNotFound("\(resource).\(ext)")
        }
        try self.init(folder: url)
    }

    init(folder: URL) throws {
        let descriptionURL = folder.appendingPathComponent(PhoneRecordingFile.descriptionName)
        let streamURL = folder.appendingPathComponent(PhoneRecordingFile.streamName)
        let videoURL = folder.appendingPathComponent(PhoneRecordingFile.videoName)
        let manager = FileManager.default
        for url in [descriptionURL, streamURL, videoURL] where !manager.fileExists(atPath: url.path) {
            throw PhoneRecordingError.notARecording("it holds no \(url.lastPathComponent).")
        }

        let description: PhoneRecordingDescription
        do {
            description = try PhoneRecordingDescription.read(from: descriptionURL)
        } catch {
            throw PhoneRecordingError.unreadable("\(PhoneRecordingFile.descriptionName) is not a description.")
        }
        guard description.format <= PhoneRecordingFile.formatVersion else {
            throw PhoneRecordingError.newerFormat(description.format)
        }

        guard let stream = try? Data(contentsOf: streamURL, options: .mappedIfSafe),
              let version = PhoneRecordingStream.version(ofFileHeader: stream) else {
            throw PhoneRecordingError.unreadable("\(PhoneRecordingFile.streamName) is not a stream file.")
        }
        guard version <= PhoneRecordingFile.formatVersion else {
            throw PhoneRecordingError.newerFormat(version)
        }

        let index = try Self.index(stream, isFinished: description.isFinished)
        let entries = index.entries, frames = index.frames, frameEntry = index.frameEntry

        guard let video = PhoneRecordingVideo(url: videoURL, quarterTurnsCW: description.quarterTurnsCW) else {
            throw PhoneRecordingError.unreadable("\(PhoneRecordingFile.videoName) holds no video.")
        }

        // The rule the format rests on: picture `k` and record `k` are one
        // instant. A recording closed properly holds the same count of each;
        // one stopped mid-way plays as far as both go.
        var count = frames.count
        if video.times.count != frames.count {
            guard !description.isFinished else {
                throw PhoneRecordingError.framesDisagree(frame: min(video.times.count, frames.count))
            }
            count = min(video.times.count, frames.count)
        }
        guard count > 0 else {
            throw PhoneRecordingError.unreadable("it holds no frames.")
        }
        let firstRecord = frames[0].timestamp, firstPicture = video.times[0]
        for k in 0..<count {
            let record = frames[k].timestamp - firstRecord
            let picture = video.times[k] - firstPicture
            guard abs(record - picture) <= Self.instantTolerance else {
                throw PhoneRecordingError.framesDisagree(frame: k)
            }
        }

        let turns = ((description.quarterTurnsCW % 4) + 4) % 4
        self.path = folder.path
        self.name = folder.deletingPathExtension().lastPathComponent
        self.mode = PhoneCaptureMode(rawValue: UInt8(clamping: description.mode)) ?? .world
        self.frameCount = count
        self.frameTimes = (0..<count).map { frames[$0].timestamp - firstRecord }
        let length = frames[count - 1].timestamp - firstRecord
        self.duration = length
        self.frameRate = length > 0 ? Double(count - 1) / length : 0
        self.pictureSize = turns % 2 == 1
            ? Vector2(Double(video.height), Double(video.width))
            : Vector2(Double(video.width), Double(video.height))
        self.hasSound = description.hasSound
        self.isComplete = description.isFinished
        self.stream = stream
        self.entries = entries
        self.frames = Array(frames.prefix(count))
        self.frameEntry = Array(frameEntry.prefix(count))
        self.video = video
        self.quarterTurnsCW = turns
    }

    /// Walk a stream file's records once: where each sits, and the camera's
    /// record for every frame. Only the camera records are opened here; they
    /// are small and never stored compressed.
    ///
    /// Throws when a camera record is damaged or out of its place in the
    /// count, and when a stream that says it was closed properly ends inside
    /// a record. One that was stopped part way through may end inside its
    /// last record, and is read without it.
    nonisolated static func index(_ stream: Data, isFinished: Bool) throws
        -> (entries: [Entry], frames: [PhoneCameraSample], frameEntry: [Int]) {
        var entries: [Entry] = []
        var frames: [PhoneCameraSample] = []
        var frameEntry: [Int] = []
        var offset = PhoneRecordingFile.streamHeaderByteCount
        var endsCleanly = true
        while offset < stream.count {
            guard let header = PhoneRecordingStream.recordHeader(in: stream, at: offset),
                  stream.count - offset - PhoneRecordingFile.recordHeaderByteCount >= header.storedLength
            else {
                endsCleanly = false
                break
            }
            if header.kind == PhoneMessageKind.camera.rawValue {
                guard case .camera(let sample)? = PhoneRecordingStream.message(of: header, in: stream, at: offset)
                else {
                    throw PhoneRecordingError.unreadable("the camera record of frame \(frames.count) is damaged.")
                }
                guard Int(sample.frameIndex) == frames.count else {
                    throw PhoneRecordingError.framesDisagree(frame: frames.count)
                }
                frameEntry.append(entries.count)
                frames.append(sample)
            }
            entries.append(Entry(offset: offset, header: header))
            offset += PhoneRecordingFile.recordHeaderByteCount + header.storedLength
        }
        guard endsCleanly || !isFinished else {
            throw PhoneRecordingError.unreadable("\(PhoneRecordingFile.streamName) ends inside a record.")
        }
        return (entries, frames, frameEntry)
    }

    /// How far apart a picture's time and its record's time may be and still be
    /// one instant. A frame lost from one file moves every later frame by a
    /// whole frame's time, many times this.
    static let instantTolerance = 0.004

    /// The recordings in a folder, newest first, as paths. Empty when the
    /// folder holds none or cannot be read. A leading `~` is the home folder.
    public static func availableRecordings(in folder: String) -> [String] {
        let root = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let found = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        return found
            .filter { $0.pathExtension == PhoneRecordingFile.folderExtension }
            .map { url -> (String, Date) in
                let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate
                return (url.path, date ?? .distantPast)
            }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
            .map(\.0)
    }

    // MARK: Playing

    /// Carry on from where the recording stands.
    public func play() {
        guard !isPlaying else { return }
        isPlaying = true
        anchorClock = nil
    }

    /// Hold the frame the recording is on.
    public func pause() {
        isPlaying = false
        anchorClock = nil
    }

    /// Move to `seconds` from the start, held inside the recording.
    public func seek(to seconds: Double) {
        position = min(max(0, seconds.isFinite ? seconds : 0), duration)
        anchorClock = nil
    }

    /// Move to a frame by its number, held inside the recording.
    public func seek(toFrame index: Int) {
        position = frameTimes[min(max(0, index), frameCount - 1)]
        anchorClock = nil
    }

    /// Where the recording stands, in seconds from its first frame.
    public var currentTime: Double { position }

    /// The frame the recording stands on.
    ///
    /// A frame is shown from a quarter of a frame's time before its own moment
    /// until the same margin before the next. Read on the frame's exact moment
    /// instead, a sketch running at the recording's own rate would sit on the
    /// boundary between two frames at every draw, and the smallest rounding
    /// would repeat one frame and skip the next. The margin keeps a sketch at
    /// the recording's rate, at half of it, and at twice it clear of every
    /// boundary, the loop's own included.
    public var frameIndex: Int {
        var moment = position + (frameRate > 0 ? 0.25 / frameRate : 0)
        if loops, moment >= loopLength { moment -= loopLength }
        var low = 0, high = frameCount - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if frameTimes[mid] <= moment { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// Follow the sketch's clock: stand where the recording should be when the
    /// sketch's `time` is `clock`.
    ///
    /// The place is worked out afresh from where the recording stood when it
    /// last started to follow, never added up frame by frame, so frame `n` of
    /// an export lands on the same frame of the recording in every run.
    func follow(clock: Double) {
        guard isPlaying else { return }
        guard let anchor = anchorClock, clock >= anchor else {
            // The first look after `play()` or a seek anchors here. A clock
            // that ran backward is a sketch that started over, and the
            // recording starts over with it.
            if let anchor = anchorClock, clock < anchor { position = 0 }
            anchorClock = clock
            anchorPosition = position
            return
        }
        let raw = anchorPosition + (clock - anchor)
        if loops {
            let length = loopLength
            // Left unclamped past the last frame's moment: the last frame has
            // its own share of the loop, and `frameIndex` reads it there.
            position = length > 0 ? raw.truncatingRemainder(dividingBy: length) : 0
        } else {
            position = min(raw, duration)
        }
    }

    /// A loop's length: the recording, and the last frame's own share of time.
    private var loopLength: Double {
        duration + (frameRate > 0 ? 1 / frameRate : 0)
    }

    // MARK: By frame

    /// The time of a frame, in seconds from the first.
    public func time(at index: Int) throws -> Double {
        try check(index)
        return frameTimes[index]
    }

    /// Where the camera stood on a frame and what its lens was, upright, with
    /// the frame's picture read when it is asked for. Reading the place and the
    /// lens of every frame costs no decode.
    public func camera(at index: Int) throws -> PhoneCamera {
        try check(index)
        return camera(for: frames[index], frame: index)
    }

    /// The picture of a frame, upright for how the phone was held.
    public func picture(at index: Int) throws -> Image {
        try check(index)
        guard let image = uprightPicture(at: index) else {
            throw PhoneRecordingError.pictureUnavailable(index)
        }
        return image
    }

    private func check(_ index: Int) throws {
        guard index >= 0, index < frameCount else {
            throw PhoneRecordingError.frameOutOfRange(index, count: frameCount)
        }
    }

    // MARK: For the device

    /// The camera a record describes, with its picture waiting to be read. The
    /// lens is brought to the video's own size, should the two ever differ.
    func camera(for sample: PhoneCameraSample, frame: Int) -> PhoneCamera {
        var camera = PhoneCamera(sample)
        camera.frameIndex = frame
        let size = pictureSize
        if camera.intrinsics.width != Int(size.x) || camera.intrinsics.height != Int(size.y) {
            camera.intrinsics = camera.intrinsics.scaled(toWidth: Int(size.x), height: Int(size.y))
        }
        camera.pictureSource = { [weak self] in self?.uprightPicture(at: frame) }
        return camera
    }

    /// The frame a capture time belongs to, or `nil` when no frame was taken at
    /// that time (its picture was dropped).
    func frame(atCaptureTime timestamp: Double) -> Int? {
        let relative = timestamp - frames[0].timestamp
        let index = PhoneRecordingVideo.nearestIndex(to: relative, in: frameTimes)
        return abs(frameTimes[index] - relative) <= Self.instantTolerance ? index : nil
    }

    /// One past the last record that had been handed over by the time frame
    /// `index` was the newest: everything before the next frame's own record.
    func entryEnd(forFrame index: Int) -> Int {
        index + 1 < frameEntry.count ? frameEntry[index + 1] : entries.count
    }

    /// The records of `range` worth opening, in order. A kind whose newest
    /// value replaces the one before it is opened once, at its last record in
    /// the range; a kind that adds up (a block of the room, a surface, a sound,
    /// a touch) keeps every record.
    func entriesToFeed(_ range: Range<Int>) -> [Int] {
        var newest: [UInt8: Int] = [:]
        for index in range where !Self.addsUp(entries[index].header.kind) {
            newest[entries[index].header.kind] = index
        }
        return range.filter { index in
            let kind = entries[index].header.kind
            return Self.addsUp(kind) || newest[kind] == index
        }
    }

    private static func addsUp(_ kind: UInt8) -> Bool {
        switch PhoneMessageKind(rawValue: kind) {
        case .sceneMesh, .plane, .sound, .touch: return true
        default: return false
        }
    }

    /// The message a record holds, or `nil` when it does not decode.
    func message(atEntry index: Int) -> PhoneMessage? {
        let entry = entries[index]
        return PhoneRecordingStream.message(of: entry.header, in: stream, at: entry.offset)
    }

    /// The upright picture of a frame as a drawable image.
    func uprightPicture(at index: Int) -> Image? {
        if let uprightImage, uprightImage.frame == index { return uprightImage.image }
        guard let buffer = video.uprightBuffer(at: index), let image = video.image(from: buffer) else {
            lastError = PhoneRecordingError.pictureUnavailable(index).description
            return nil
        }
        lastError = nil
        uprightImage = (index, image)
        return image
    }

    /// The picture of a frame as the sensor delivered it, which is the frame a
    /// depth map lines up with.
    func sensorPicture(at index: Int) -> Image? {
        if quarterTurnsCW == 0 { return uprightPicture(at: index) }
        if let sensorImage, sensorImage.frame == index { return sensorImage.image }
        guard let buffer = video.buffer(at: index), let image = video.image(from: buffer) else {
            lastError = PhoneRecordingError.pictureUnavailable(index).description
            return nil
        }
        lastError = nil
        sensorImage = (index, image)
        return image
    }

    /// The sensor picture's size in pixels.
    var sensorPictureSize: Vector2 { Vector2(Double(video.width), Double(video.height)) }

    /// The upright picture of a frame as a `CGImage`, for a vision tracker.
    func uprightCGImage(at index: Int) -> CGImage? {
        guard let buffer = video.uprightBuffer(at: index) else { return nil }
        return video.cgImage(from: buffer)
    }
}
