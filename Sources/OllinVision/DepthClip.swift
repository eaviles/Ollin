import AVFoundation
import CoreGraphics
import CoreML
import Foundation
import Ollin
import VideoToolbox
import Vision
import os

/// A recording's depth, read ahead of time: the whole clip through the video
/// depth model's published inference, its result kept on disk, and every
/// frame's map answered by clip time. `DepthTracker` reads a feed as it plays,
/// one frame at a time, and reads nothing during a headless export, since
/// its frames pump on the live clock. `DepthClip` is the other way round: it
/// reads the file once, in windows of 32 frames the way the model was
/// trained to be read, so the answer is the model at its best, the same on
/// every run, and there for an export.
///
/// ```swift
/// let player = try VideoPlayer(resource: "walk", withExtension: "mp4", in: .module)
/// lazy var depth = DepthClip(player, modelAt: URL(fileURLWithPath:
///     "Models/VideoDepthAnythingSmallClipF16.mlpackage"))
/// override func draw() {
///     guard let rect = drawFrame(player) else { return }
///     if !depth.isReady { return drawStatus("Reading the clip's depth… \(Int(depth.progress * 100))%") }
///     let near = depth.value(at: Vector2(mouseX, mouseY), in: rect)   // 0 far … 1 near
///     if let map = depth.map { drawImage(map, in: rect) }             // tintable
/// }
/// ```
///
/// Bound to a player, `map` and `value(at:in:)` answer for the frame under
/// its playhead; `map(at:)` and `value(at:in:time:)` answer for any clip time.
/// The pass runs in the background the first time a clip meets a model, at a
/// second or two per window on an M2 (`progress` counts it up), and its result
/// is cached under `~/Library/Caches/Ollin/DepthClips`, so the next run of the
/// same clip through the same model opens at once. Under a headless export
/// the pass runs before the first frame renders, so exported frame `k` always
/// carries the map of the clip frame it shows.
///
/// The depth is *relative*: nearer and farther, not meters, on one scale for
/// the whole clip (each window is fitted to the one before it on the frames
/// they share, the published alignment). `map` and `value(at:in:)` read
/// through a fixed `range`, the 1st and 99th percentiles over the whole clip,
/// so nothing re-scales as the clip plays. Frames are read squashed to the
/// model's landscape input, as `DepthTracker` reads them. The model weights
/// aren't in the repo: `Scripts/fetch-models.sh` builds this package beside
/// the streaming one. The model needs Apple silicon.
public final class DepthClip: @unchecked Sendable {

    // The published inference's settings (`infer_video_depth`): windows of 32
    // frames, 22 new frames a window, the first 10 slots refilled from the
    // previous window's keyframes, and of the 10 overlapping frames the first
    // 2 fit the scale and the last 8 blend.
    static let windowLength = 32
    static let overlap = 10
    static let keyframes = [0, 12, 24, 25, 26, 27, 28, 29, 30, 31]
    static let blendLength = 8
    static var step: Int { windowLength - overlap }
    static var fitLength: Int { overlap - blendLength }

    private struct State {
        var pass: Pass?
        var progress = 0.0
        var lastMap: (frame: Int, image: Image)?
        var started = false
    }
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())
    private let status = VisionStatus("clip depth")
    private let playback: (any ClipPlayback)?
    private let source: Source
    private let modelURL: URL

    /// Where the frames come from: a file, or (the tests) frames in hand.
    enum Source {
        case file(URL)
        case frames([(image: CGImage, seconds: Double)])
    }

    /// The clip `playback` is playing, read through the window model at
    /// `url` (the fetched `…ClipF16.mlpackage`, or its compiled `.mlmodelc`);
    /// `map` and `value(at:in:)` then answer for the frame under its playhead.
    @MainActor
    public init(_ playback: any ClipPlayback, modelAt url: URL) {
        self.playback = playback
        self.source = .file(playback.url)
        self.modelURL = url
        start()
    }

    /// The clip at `url`, read through the window model at `model`; read it
    /// by clip time with `map(at:)` and `value(at:in:time:)`.
    public init(url: URL, modelAt model: URL) {
        self.playback = nil
        self.source = .file(url)
        self.modelURL = model
        start()
    }

    /// Frames in hand, in order with their times (the tests).
    init(frames: [(image: CGImage, seconds: Double)], modelAt model: URL) {
        self.playback = nil
        self.source = .frames(frames)
        self.modelURL = model
    }

    // MARK: Reading

    /// Whether the pass is finished and every frame's map is there to read.
    public var isReady: Bool { lock.withLockUnchecked { $0.pass != nil } }

    /// How far the pass has come, `0…1`; `1` once `isReady`.
    public var progress: Double { lock.withLockUnchecked { $0.pass != nil ? 1 : $0.progress } }

    /// Whether the pass can run here: the model file exists and loaded, and
    /// the clip could be read. When `false`, `unavailableReason` says why.
    public var isAvailable: Bool { status.isAvailable }
    /// Why the pass couldn't run, or `nil` when it could.
    public var unavailableReason: String? { status.reason }

    /// How many frames the clip has, once `isReady`; `0` before.
    public var frameCount: Int { lock.withLockUnchecked { $0.pass?.times.count ?? 0 } }

    /// The model's own values that `map` and `value(at:in:)` read as `0` (far)
    /// and `1` (near), the 1st and 99th percentiles over the whole clip, or
    /// `nil` before `isReady`.
    public var range: ClosedRange<Double>? { lock.withLockUnchecked { $0.pass?.range } }

    /// The depth map of the frame under the playhead, white with alpha `0`
    /// far … `1` near, sized to the model's output; draw it into the same
    /// rectangle as the frame and it lines up. `nil` before `isReady`, or when
    /// the clip was read by URL rather than bound to a player.
    @MainActor
    public var map: Image? {
        guard let playback else { return nil }
        return map(at: playback.currentTime)
    }

    /// The depth map of the frame showing at `seconds` into the clip (the
    /// frame that starts at or before it, the way a player picks the frame
    /// to show), `nil` before `isReady`.
    public func map(at seconds: Double) -> Image? {
        guard let pass = lock.withLockUnchecked({ $0.pass }),
              let frame = pass.frameIndex(at: seconds) else { return nil }
        if let last = lock.withLockUnchecked({ $0.lastMap }), last.frame == frame {
            return last.image
        }
        let bytes = pass.bytes(of: frame)
        guard let image = SegmentationImages.matteImage(fromGray: bytes, width: pass.width,
                                                        height: pass.height) else { return nil }
        lock.withLockUnchecked { $0.lastMap = (frame, image) }
        return image
    }

    /// The depth under `point` (a canvas point inside `rect`, the rectangle
    /// you drew the frame into) in the frame under the playhead, `0` far … `1`
    /// near; `0` before `isReady`. Set `mirrored` when the frame is drawn
    /// flipped left-to-right.
    @MainActor
    public func value(at point: Vector2, in rect: Rectangle, mirrored: Bool = false) -> Double {
        guard let playback else { return 0 }
        return value(at: point, in: rect, time: playback.currentTime, mirrored: mirrored)
    }

    /// The depth under `point` in the frame showing at `seconds` into the
    /// clip, `0` far … `1` near; `0` before `isReady`.
    public func value(at point: Vector2, in rect: Rectangle, time seconds: Double,
                      mirrored: Bool = false) -> Double {
        valueNormalized(at: VisionSpace.normalizedPoint(point, in: rect, mirrored: mirrored),
                        time: seconds)
    }

    /// The depth at a normalized point (`0…1`, lower-left origin) at `seconds`
    /// into the clip, the raw surface; most sketches want `value(at:in:)`.
    public func valueNormalized(at point: Vector2, time seconds: Double) -> Double {
        guard let pass = lock.withLockUnchecked({ $0.pass }),
              let frame = pass.frameIndex(at: seconds) else { return 0 }
        let col = min(max(Int(point.x * Double(pass.width)), 0), pass.width - 1)
        let row = min(max(Int((1 - point.y) * Double(pass.height)), 0), pass.height - 1)
        return pass.normalized(pass.value(frame: frame, row: row, col: col))
    }

    /// The index of the frame showing at `seconds`, or `nil` before `isReady`.
    func frameIndex(at seconds: Double) -> Int? {
        lock.withLockUnchecked { $0.pass }?.frameIndex(at: seconds)
    }

    /// The model's own value at a pixel of a frame (the tests).
    func modelValue(frame: Int, row: Int, col: Int) -> Float? {
        lock.withLockUnchecked { $0.pass }?.value(frame: frame, row: row, col: col)
    }

    // MARK: The pass

    /// Start the pass: inline under a headless export (the export's first
    /// frame has to find it done), else on its own thread, since it runs for
    /// seconds to minutes and a cooperative worker is not for that.
    private func start() {
        if Thread.isMainThread && OllinApp.isRenderingHeadless {
            run()
            return
        }
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "DepthClip"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Run the pass to completion on the calling thread (the tests call it
    /// directly; `start()` routes here).
    func run() {
        let already = lock.withLockUnchecked { state -> Bool in
            defer { state.started = true }
            return state.started
        }
        if already { return }
        do {
            let pass = try makePass()
            lock.withLockUnchecked { $0.pass = pass }
        } catch {
            status.markUnavailable(String(describing: error))
        }
    }

    private func makePass() throws -> Pass {
        switch source {
        case .file(let clipURL):
            let cached = Self.cacheURL(clip: clipURL, model: modelURL)
            if FileManager.default.fileExists(atPath: cached.path),
               let pass = try? Pass(contentsOf: cached) {
                return pass
            }
            guard FileManager.default.fileExists(atPath: modelURL.path) else {
                throw Error.unavailable(
                    "Model file not found: \(modelURL.path). Run Scripts/fetch-models.sh and relaunch.")
            }
            var frames = try FileFrames(url: clipURL)
            let runner = try ModelWindowRunner(modelAt: modelURL)
            try FileManager.default.createDirectory(at: cached.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let staging = cached.deletingLastPathComponent()
                .appendingPathComponent("staging-\(UUID().uuidString).depthclip")
            try Self.writePass(from: &frames, through: runner, to: staging) { [weak self] progress in
                self?.lock.withLockUnchecked { $0.progress = progress }
            }
            do {
                try FileManager.default.moveItem(at: staging, to: cached)
            } catch CocoaError.fileWriteFileExists {
                try? FileManager.default.removeItem(at: staging)
            }
            return try Pass(contentsOf: cached)
        case .frames(let list):
            guard FileManager.default.fileExists(atPath: modelURL.path) else {
                throw Error.unavailable(
                    "Model file not found: \(modelURL.path). Run Scripts/fetch-models.sh and relaunch.")
            }
            var frames = ArrayFrames(list)
            let runner = try ModelWindowRunner(modelAt: modelURL)
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("DepthClip-\(UUID().uuidString).depthclip")
            try Self.writePass(from: &frames, through: runner, to: file) { [weak self] progress in
                self?.lock.withLockUnchecked { $0.progress = progress }
            }
            return try Pass(contentsOf: file)
        }
    }

    /// The pass over frames in hand through any window runner (the tests
    /// drive the scheduler with a runner of their own); the result lands as a
    /// pass file at `file`.
    static func writePass(from frames: inout some FrameProvider, through runner: any WindowRunner,
                          to file: URL, progress: (Double) -> Void) throws {
        let writer = try PassWriter(file: file, width: runner.width, height: runner.height)
        let total = Double(frames.estimatedCount ?? 0)
        var images: [CGImage] = []
        var times: [Double] = []
        var finished = false
        var windowStart = 0
        var previousInputs: [CGImage]? = nil
        // The 8 provisional maps at the end of the aligned list, blended by
        // the next window before they are final.
        var tail: [[Float]] = []
        var written = 0
        var reference: (first: [Float], second: [Float])? = nil

        /// The scheduler's padding: enough copies of the last frame that the
        /// last window is full, the published rule.
        func padded(to count: Int) {
            while images.count < count, let last = images.last {
                images.append(last)
                times.append(times.last ?? 0)
            }
        }
        var realCount = 0
        /// Maps past the clip's own frames belong to the padding and are dropped.
        func flush(_ plane: [Float]) throws {
            if written < (finished ? realCount : Int.max) {
                try writer.append(plane)
                written += 1
            }
        }

        while true {
            // Pull frames until the window is covered, or the clip ends.
            while !finished && images.count < windowStart + windowLength {
                if let next = try frames.next() {
                    images.append(next.image)
                    times.append(next.seconds)
                    if total > 0 { progress(min(Double(images.count) / total, 0.99)) }
                } else {
                    finished = true
                    realCount = images.count
                }
            }
            if finished {
                if realCount == 0 { throw Error.unavailable("The clip has no frames to read.") }
                let stepCount = step
                let append = (stepCount - (realCount % stepCount)) % stepCount + (windowLength - stepCount)
                padded(to: realCount + append)
            }
            guard windowStart < (finished ? realCount : Int.max),
                  images.count >= windowStart + windowLength else { break }

            var inputs = Array(images[windowStart..<windowStart + windowLength])
            if let previousInputs {
                for i in 0..<overlap { inputs[i] = previousInputs[keyframes[i]] }
            }
            let out = try runner.run(inputs)
            guard out.count == windowLength else {
                throw Error.unavailable("The model answered \(out.count) maps for a window of \(windowLength).")
            }

            if reference == nil {
                // The first window: all 32 maps are its own frames; the last
                // 8 stay provisional.
                for plane in out.prefix(windowLength - blendLength) { try flush(plane) }
                tail = Array(out.suffix(blendLength))
                reference = (out[0], out[keyframes[1]])
            } else {
                // Fit this window's scale to the aligned one on the two frames
                // they share (slot 0 is the clip's first frame, slot 1 the
                // previous window's keyframe 12).
                let (scale, shift) = fit(prediction: out[0] + out[1],
                                         target: reference!.first + reference!.second)
                func aligned(_ plane: [Float]) -> [Float] {
                    plane.map { max($0 * scale + shift, 0) }
                }
                // The 8 overlapping frames: blend the provisional maps into
                // this window's readings of the same frames.
                let post = out[fitLength..<overlap].map(aligned)
                for (i, (before, after)) in zip(tail, post).enumerated() {
                    let weight = Float(i) / Float(blendLength - 1)
                    var blended = before
                    for k in blended.indices {
                        blended[k] = before[k] * (1 - weight) + after[k] * weight
                    }
                    try flush(blended)
                }
                let fresh = out[overlap..<windowLength].map(aligned)
                for plane in fresh.prefix(fresh.count - blendLength) { try flush(plane) }
                tail = Array(fresh.suffix(blendLength))
                reference!.second = aligned(out[keyframes[1]])
            }
            previousInputs = inputs
            windowStart += step
            if finished, windowStart >= realCount { break }
        }
        for plane in tail { try flush(plane) }
        try writer.finish(times: Array(times.prefix(realCount)))
        progress(1)
    }

    /// The least-squares scale and shift that take `prediction` onto
    /// `target` (the published `compute_scale_and_shift`, every pixel
    /// counted), or the identity when the fit is degenerate.
    static func fit(prediction: [Float], target: [Float]) -> (scale: Float, shift: Float) {
        var a00 = 0.0, a01 = 0.0, b0 = 0.0, b1 = 0.0
        for (p, t) in zip(prediction, target) {
            let p = Double(p), t = Double(t)
            a00 += p * p
            a01 += p
            b0 += p * t
            b1 += t
        }
        let a11 = Double(min(prediction.count, target.count))
        let det = a00 * a11 - a01 * a01
        guard det != 0 else { return (1, 0) }
        return (Float((a11 * b0 - a01 * b1) / det), Float((-a01 * b0 + a00 * b1) / det))
    }

    // MARK: The cache

    /// Where a clip's pass lives: keyed on the clip and the model (path,
    /// modification time, size), so a re-encoded clip or a rebuilt model reads
    /// anew.
    static func cacheURL(clip: URL, model: URL) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("Ollin/DepthClips", isDirectory: true)
        let name = clip.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent(
            "\(name)-\(ModelTracker.stamp(for: clip))-\(ModelTracker.stamp(for: model)).depthclip")
    }

    /// Why the pass couldn't run.
    public enum Error: Swift.Error, CustomStringConvertible {
        /// The pass isn't possible here; the text is `unavailableReason`.
        case unavailable(String)

        public var description: String {
            switch self {
            case .unavailable(let reason): return reason
            }
        }
    }
}

// MARK: - The pass file

/// A finished pass, mapped from its file: a header, the maps as half floats
/// frame after frame, and the frame times at the end.
///
///     0   "OLDP"           40  planes offset (u64)
///     4   version (u32)    48  times offset (u64)
///     8   width (u32)      56  reserved
///     12  height (u32)     64  planes: frames x height x width x float16
///     16  frames (u32)     …   times: frames x float64
///     24  range low (f64)
///     32  range high (f64)
struct DepthClipPass {
    let data: Data
    let width: Int
    let height: Int
    let times: [Double]
    let range: ClosedRange<Double>
    private let planesOffset: Int

    static let magic: UInt32 = 0x50444C4F   // "OLDP", little-endian
    static let version: UInt32 = 1
    static let headerSize = 64

    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        guard data.count >= Self.headerSize else { throw DepthClip.Error.unavailable("The pass file is truncated.") }
        func word(_ offset: Int) -> UInt32 { data.load(offset, as: UInt32.self) }
        guard word(0) == Self.magic, word(4) == Self.version else {
            throw DepthClip.Error.unavailable("The pass file is not a depth pass.")
        }
        width = Int(word(8))
        height = Int(word(12))
        let frames = Int(word(16))
        let low = data.load(24, as: Double.self)
        let high = data.load(32, as: Double.self)
        planesOffset = Int(data.load(40, as: UInt64.self))
        let timesOffset = Int(data.load(48, as: UInt64.self))
        guard width > 0, height > 0, frames > 0,
              timesOffset + frames * 8 <= data.count,
              planesOffset + frames * width * height * 2 <= timesOffset else {
            throw DepthClip.Error.unavailable("The pass file is truncated.")
        }
        times = (0..<frames).map { data.load(timesOffset + $0 * 8, as: Double.self) }
        range = low...max(high, low + 1e-6)
        self.data = data
    }

    /// The frame showing at `seconds`: the last one starting at or before it
    /// (the first frame before the clip starts).
    func frameIndex(at seconds: Double) -> Int? {
        guard !times.isEmpty else { return nil }
        var low = 0, high = times.count - 1
        if seconds < times[0] { return 0 }
        while low < high {
            let mid = (low + high + 1) / 2
            if times[mid] <= seconds + 1e-9 { low = mid } else { high = mid - 1 }
        }
        return low
    }

    func value(frame: Int, row: Int, col: Int) -> Float {
        let index = planesOffset + ((frame * height + row) * width + col) * 2
        return Float(data.load(index, as: Float16.self))
    }

    func normalized(_ value: Float) -> Double {
        min(max((Double(value) - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    /// The frame's map as bytes through `range`: `0` far, `255` near.
    func bytes(of frame: Int) -> [UInt8] {
        let low = Float(range.lowerBound)
        let scale = 255 / Float(range.upperBound - range.lowerBound)
        let start = planesOffset + frame * width * height * 2
        return data.withUnsafeBytes { raw -> [UInt8] in
            let halves = raw.baseAddress!.advanced(by: start)
                .assumingMemoryBound(to: Float16.self)
            return (0..<width * height).map { i in
                UInt8(min(max((Float(halves[i]) - low) * scale, 0), 255))
            }
        }
    }
}

private extension Data {
    func load<T>(_ offset: Int, as type: T.Type) -> T {
        withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: type) }
    }
}

typealias Pass = DepthClipPass

/// Writes a pass file: the maps as they become final, the times and the
/// range at the end, the header last.
private final class PassWriter {
    private let handle: FileHandle
    private let width: Int
    private let height: Int
    private var frames = 0
    private var minimum = Float.greatestFiniteMagnitude
    private var maximum = -Float.greatestFiniteMagnitude

    init(file: URL, width: Int, height: Int) throws {
        FileManager.default.createFile(atPath: file.path, contents: nil)
        handle = try FileHandle(forUpdating: file)
        self.width = width
        self.height = height
        try handle.write(contentsOf: Data(count: DepthClipPass.headerSize))
    }

    func append(_ plane: [Float]) throws {
        precondition(plane.count == width * height)
        var halves = [Float16](repeating: 0, count: plane.count)
        for (i, v) in plane.enumerated() {
            halves[i] = Float16(v)
            if v < minimum { minimum = v }
            if v > maximum { maximum = v }
        }
        try halves.withUnsafeBytes { try handle.write(contentsOf: Data($0)) }
        frames += 1
    }

    /// The times, the whole-clip range (the 1st and 99th percentiles, by a
    /// 256-bin histogram over every 7th value), then the header.
    func finish(times: [Double]) throws {
        precondition(times.count <= frames)
        let count = times.count
        let timesOffset = DepthClipPass.headerSize + frames * width * height * 2
        try handle.seek(toOffset: UInt64(timesOffset))
        try times.withUnsafeBytes { try handle.write(contentsOf: Data($0)) }
        try handle.truncate(atOffset: UInt64(timesOffset + count * 8))
        try handle.synchronize()

        var histogram = [Int](repeating: 0, count: 256)
        var counted = 0
        let spread = max(maximum - minimum, 1e-6)
        try handle.seek(toOffset: UInt64(DepthClipPass.headerSize))
        for _ in 0..<count {
            let bytes = try handle.read(upToCount: width * height * 2) ?? Data()
            bytes.withUnsafeBytes { raw in
                let halves = raw.bindMemory(to: Float16.self)
                var i = 0
                while i < halves.count {
                    let bin = Int((Float(halves[i]) - minimum) / spread * 255)
                    histogram[min(max(bin, 0), 255)] += 1
                    counted += 1
                    i += 7
                }
            }
        }
        func level(_ fraction: Double) -> Double {
            let target = Int(Double(counted) * fraction)
            var seen = 0
            for (bin, n) in histogram.enumerated() {
                seen += n
                if seen >= target { return Double(minimum) + Double(bin) / 255 * Double(spread) }
            }
            return Double(maximum)
        }
        let low = level(0.01), high = level(0.99)

        var header = Data(count: DepthClipPass.headerSize)
        header.store(DepthClipPass.magic, at: 0)
        header.store(DepthClipPass.version, at: 4)
        header.store(UInt32(width), at: 8)
        header.store(UInt32(height), at: 12)
        header.store(UInt32(count), at: 16)
        header.store(low, at: 24)
        header.store(high, at: 32)
        header.store(UInt64(DepthClipPass.headerSize), at: 40)
        header.store(UInt64(timesOffset), at: 48)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header)
        try handle.close()
    }
}

private extension Data {
    mutating func store<T>(_ value: T, at offset: Int) {
        withUnsafeMutableBytes { $0.storeBytes(of: value, toByteOffset: offset, as: T.self) }
    }
}

// MARK: - Frames in

/// Frames in order with their times, from wherever they come.
protocol FrameProvider {
    /// How many frames to expect, for progress; `nil` when unknown.
    var estimatedCount: Int? { get }
    mutating func next() throws -> (image: CGImage, seconds: Double)?
}

struct ArrayFrames: FrameProvider {
    private let frames: [(image: CGImage, seconds: Double)]
    private var index = 0
    init(_ frames: [(image: CGImage, seconds: Double)]) { self.frames = frames }
    var estimatedCount: Int? { frames.count }
    mutating func next() -> (image: CGImage, seconds: Double)? {
        guard index < frames.count else { return nil }
        defer { index += 1 }
        return frames[index]
    }
}

/// A sequential decode of a file's video track, every frame in presentation
/// order with its timestamp.
struct FileFrames: FrameProvider {
    let estimatedCount: Int?
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput

    init(url: URL) throws {
        let asset = AVURLAsset(url: url)
        let loaded = Self.loadBlocking(asset)
        guard let track = loaded.track else {
            throw DepthClip.Error.unavailable("No video track could be read at \(url.path).")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw DepthClip.Error.unavailable("The video track at \(url.path) can't be decoded.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw DepthClip.Error.unavailable(
                "The video at \(url.path) couldn't be read: \(reader.error?.localizedDescription ?? "unknown error").")
        }
        self.reader = reader
        self.output = output
        if let duration = loaded.duration, loaded.frameRate > 0 {
            estimatedCount = Int((duration * Double(loaded.frameRate)).rounded())
        } else {
            estimatedCount = nil
        }
    }

    mutating func next() throws -> (image: CGImage, seconds: Double)? {
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            var image: CGImage?
            let status = VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
            guard status == noErr, let image else {
                throw DepthClip.Error.unavailable("A frame couldn't be converted (VideoToolbox error \(status)).")
            }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            return (image, pts.isValid ? pts.seconds : 0)
        }
        if reader.status == .failed {
            throw DepthClip.Error.unavailable(
                "The clip stopped decoding: \(reader.error?.localizedDescription ?? "unknown error").")
        }
        return nil
    }

    /// AVFoundation's metadata loaders are async-only; the pass runs on a
    /// plain thread (or the main thread, headless), never a cooperative
    /// worker, so parking it while a detached task loads is safe.
    private static func loadBlocking(
        _ asset: AVURLAsset
    ) -> (track: AVAssetTrack?, duration: Double?, frameRate: Float) {
        let done = DispatchSemaphore(value: 0)
        let box = OSAllocatedUnfairLock<(AVAssetTrack?, Double?, Float)>(
            uncheckedState: (nil, nil, 0))
        Task.detached {
            let track = try? await asset.loadTracks(withMediaType: .video).first
            let duration = try? await asset.load(.duration)
            let rate: Float = if let track { (try? await track.load(.nominalFrameRate)) ?? 0 } else { 0 }
            let seconds: Double? = (duration?.isValid ?? false) ? duration?.seconds : nil
            box.withLockUnchecked { $0 = (track, seconds, rate) }
            done.signal()
        }
        done.wait()
        return box.withLockUnchecked { $0 }
    }
}

// MARK: - Windows through

/// One window of frames in, one map per frame out, in the model's own units.
protocol WindowRunner {
    var width: Int { get }
    var height: Int { get }
    func run(_ window: [CGImage]) throws -> [[Float]]
}

/// The window model: 32 image inputs, resized by Core ML onto the model's
/// shape, one prediction. A frame's converted input is kept while it can
/// still be asked for (the next window's keyframes), so a keyframe is
/// converted once.
final class ModelWindowRunner: WindowRunner {
    let width: Int
    let height: Int
    private let model: MLModel
    private let constraint: MLImageConstraint
    private var features: [ObjectIdentifier: MLFeatureValue] = [:]

    init(modelAt url: URL) throws {
        let model = try Self.loadBlocking(url)
        let description = model.modelDescription
        guard let constraint = description.inputDescriptionsByName["frame_0"]?.imageConstraint,
              description.inputDescriptionsByName["frame_\(DepthClip.windowLength - 1)"] != nil,
              description.outputDescriptionsByName["depth"] != nil else {
            throw DepthClip.Error.unavailable(
                "The model at \(url.path) isn't the clip window model (it wants frame_0 … frame_31 and answers depth).")
        }
        self.model = model
        self.constraint = constraint
        width = constraint.pixelsWide
        height = constraint.pixelsHigh
    }

    func run(_ window: [CGImage]) throws -> [[Float]] {
        var dictionary: [String: Any] = [:]
        var keep: [ObjectIdentifier: MLFeatureValue] = [:]
        for (i, image) in window.enumerated() {
            let id = ObjectIdentifier(image)
            let feature: MLFeatureValue
            if let cached = features[id] ?? keep[id] {
                feature = cached
            } else {
                feature = try MLFeatureValue(
                    cgImage: image, constraint: constraint,
                    options: [.cropAndScale: VNImageCropAndScaleOption.scaleFill.rawValue])
            }
            keep[id] = feature
            dictionary["frame_\(i)"] = feature
        }
        features = keep
        let output = try model.prediction(from: try MLDictionaryFeatureProvider(dictionary: dictionary))
        guard let depth = output.featureValue(for: "depth")?.multiArrayValue else {
            throw DepthClip.Error.unavailable("The model produced no depth maps.")
        }
        let shape = depth.shape.map(\.intValue)
        let count = DepthClip.windowLength
        guard shape.reduce(1, *) == count * width * height else {
            throw DepthClip.Error.unavailable("The model answered maps of shape \(shape).")
        }
        let plane = width * height
        let values: [Float] = depth.withUnsafeBufferPointer(ofType: Float.self) { Array($0) }
        return (0..<count).map { Array(values[$0 * plane..<($0 + 1) * plane]) }
    }

    /// The load, awaited from the pass's own thread (or the main thread,
    /// headless): the compile-and-cache step and the serialized loader are
    /// async, and neither needs the calling thread.
    private static func loadBlocking(_ url: URL) throws -> MLModel {
        final class Box: @unchecked Sendable {
            var result: Result<MLModel, Swift.Error>?
            let done = DispatchSemaphore(value: 0)
        }
        let box = Box()
        Task.detached(priority: .userInitiated) {
            do {
                let compiled = try await ModelTracker.compiledModelURL(for: url)
                let model = try await ModelLoader.shared.load(contentsOf: compiled, computeUnits: .cpuAndGPU)
                box.result = .success(model)
            } catch {
                box.result = .failure(error)
            }
            box.done.signal()
        }
        box.done.wait()
        do {
            return try box.result!.get()
        } catch {
            throw DepthClip.Error.unavailable(
                "The model at \(url.path) couldn't load: \(error.localizedDescription)")
        }
    }
}
