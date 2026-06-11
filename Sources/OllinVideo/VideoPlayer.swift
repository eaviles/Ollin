import Ollin
import AVFoundation
import CoreImage
import CoreVideo
import Metal

/// Plays a video file into a sketch as a live image — recorded footage the way
/// `Camera` is the live feed. Create one in `setup()`, `play()` it, then draw
/// `frame` in `draw()`; each decoded frame arrives as a GPU texture wrapped in
/// an `Image`, so it composites like any other image, riding the transform
/// stack and `tint`, with no CPU round-trip.
///
/// ```swift
/// let player = try VideoPlayer(path: "/path/to/clip.mp4")
/// override func setup() { player.loops = true; player.play() }
/// override func draw() {
///     if let frame = player.frame, let rect = player.fittedRect(in: bounds) {
///         drawImage(frame, in: rect)
///     }
/// }
/// ```
///
/// Decodes the usual Apple-supported containers and codecs (`.mp4`/`.mov` with
/// H.264/HEVC/ProRes, …) through AVFoundation. For one-off analysis — feeding a
/// frame to a vision tracker's `detect(in:)`, reading pixels — take a
/// `snapshot()`, a CPU-backed copy of the current frame. For *live* analysis,
/// the player is a `FrameSource`: attach a vision tracker to it exactly the way
/// you'd attach one to a camera, and it runs over the footage as it plays.
@MainActor
public final class VideoPlayer: FrameSource {

    /// Whether playback should restart from the top when it reaches the end.
    public var loops = false

    /// Playback speed (`1` is natural speed). Takes effect immediately while
    /// playing, otherwise on the next `play()`.
    public var rate: Double = 1 {
        didSet { if isPlaying { player.rate = Float(rate) } }
    }

    /// Audio volume, `0…1`.
    public var volume: Double {
        get { Double(player.volume) }
        set { player.volume = Float(newValue) }
    }

    /// Whether the audio track is muted.
    public var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    /// Whether the video is currently playing.
    public var isPlaying: Bool { player.timeControlStatus != .paused }

    /// The video's duration in seconds, or `nil` until the file's metadata has
    /// loaded (it loads asynchronously, shortly after init).
    public private(set) var duration: Double?

    /// The video's pixel dimensions, or `nil` until known (from the file's
    /// metadata, or the first decoded frame, whichever lands first).
    public private(set) var size: Vector2?

    /// The current playback position in seconds.
    public var currentTime: Double {
        let t = player.currentTime()
        return t.isValid ? t.seconds : 0
    }

    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    // Written once in init, read again only in deinit (which is nonisolated in
    // Swift 6, hence the unsafe opt-out); NotificationCenter tokens are safe to
    // remove from any thread.
    private nonisolated(unsafe) var endObserver: (any NSObjectProtocol)?

    private var textureCache: CVMetalTextureCache?
    // The wrapped CVMetalTextures keep their pixel buffers alive; the renderer
    // may still be reading an earlier frame's texture (frames in flight), so a
    // short ring holds the last few instead of just the current one.
    private var inFlightTextures: [CVMetalTexture] = []
    private var lastPixelBuffer: CVPixelBuffer?
    private var cachedFrame: Image?
    private lazy var ciContext = CIContext()

    /// The analysis tap (`FrameSource`). Installing one attaches a *second*
    /// video output to the player item and pumps its frames to the tap from a
    /// background queue — its own output, so the tap never steals a decoded
    /// frame from the `frame` display path (each output gets every frame).
    public var frameTap: FrameTap? {
        didSet {
            tapPump?.cancel()
            tapPump = nil
            if let tapOutput {
                player.currentItem?.remove(tapOutput)
                self.tapOutput = nil
            }
            guard let frameTap else { return }
            let output = Self.makeOutput()
            player.currentItem?.add(output)
            tapOutput = output
            tapPump = VideoFrameTapPump(output: output, tap: frameTap)
        }
    }
    private var tapPump: VideoFrameTapPump?
    private var tapOutput: AVPlayerItemVideoOutput?

    /// Opens the video at a filesystem `path`. Throws if no file exists there.
    public convenience init(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw VideoError.fileNotFound(path)
        }
        self.init(url: URL(fileURLWithPath: path))
    }

    /// Opens a video bundled as a resource. Pass the caller's bundle as `bundle`
    /// (a default would resolve to Ollin's own bundle, not yours).
    public convenience init(resource name: String, withExtension ext: String, in bundle: Bundle) throws {
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            throw VideoError.resourceNotFound("\(name).\(ext)")
        }
        self.init(url: url)
    }

    /// Opens the video at `url`. The file's metadata (`duration`, `size`) loads
    /// asynchronously; a file that can't be read simply never produces frames.
    public init(url: URL) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let output = Self.makeOutput()
        item.add(output)
        self.output = output
        self.player = AVPlayer(playerItem: item)
        // End-of-item is handled here (loop or hold), not by the player.
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reachedEnd() }
        }
        Task { [weak self] in
            guard let duration = try? await asset.load(.duration) else { return }
            var natural: CGSize?
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                natural = try? await track.load(.naturalSize)
            }
            guard let self else { return }
            self.duration = duration.isValid ? duration.seconds : nil
            if self.size == nil, let natural, natural.width > 0 {
                self.size = Vector2(natural.width, natural.height)
            }
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    /// Starts (or resumes) playback at `rate`.
    public func play() {
        if let duration, duration > 0, currentTime >= duration {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.playImmediately(atRate: Float(rate))
    }

    /// Pauses playback, keeping the position.
    public func pause() { player.pause() }

    /// Stops playback and rewinds to the beginning.
    public func stop() {
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Jumps to `seconds` from the start (clamped to the video by the player).
    public func seek(to seconds: Double) {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// The current video frame as a drawable `Image`, or `nil` before the first
    /// frame decodes. The image wraps the decoded frame's GPU texture directly;
    /// while no new frame is due (paused, or drawing faster than the video's
    /// frame rate) the previous frame is returned, so it always draws something
    /// once playback has begun.
    public var frame: Image? {
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard itemTime.isValid,
              output.hasNewPixelBuffer(forItemTime: itemTime),
              let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil),
              let texture = makeTexture(from: buffer)
        else { return cachedFrame }
        lastPixelBuffer = buffer
        let image = Image(texture: texture)
        cachedFrame = image
        if size == nil {
            size = Vector2(Double(CVPixelBufferGetWidth(buffer)), Double(CVPixelBufferGetHeight(buffer)))
        }
        return image
    }

    /// A CPU-backed copy of the current frame, or `nil` before one decodes.
    /// Unlike `frame` (a live GPU texture), the result supports the CPU paths —
    /// pixel reads via `image[x, y]`, `cgImage`, and a vision tracker's
    /// `detect(in:)` — at the cost of a GPU→CPU copy, so take one when needed
    /// rather than every frame.
    public func snapshot() -> Image? {
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        var buffer: CVPixelBuffer?
        if itemTime.isValid {
            buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        }
        guard let buffer = buffer ?? lastPixelBuffer else { return nil }
        if lastPixelBuffer == nil { lastPixelBuffer = buffer }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return Image(cgImage: cgImage)
    }

    /// The letterboxed rectangle that fits the video inside `container` without
    /// stretching — draw `frame` into it, and map any analysis results into the
    /// same rectangle so overlays line up. `nil` until `size` is known.
    public func fittedRect(in container: Rectangle) -> Rectangle? {
        guard let size, size.x > 0, size.y > 0 else { return nil }
        let scale = min(container.width / size.x, container.height / size.y)
        let width = size.x * scale
        let height = size.y * scale
        return Rectangle(
            x: container.x + (container.width - width) / 2,
            y: container.y + (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// BGRA (the texture cache's native layout), Metal-compatible buffers.
    private nonisolated static func makeOutput() -> AVPlayerItemVideoOutput {
        let attributes: [String: any Sendable] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        return AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
    }

    private func reachedEnd() {
        if loops {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            player.rate = Float(rate)
        } else {
            player.pause()
        }
    }

    /// Wraps a decoded pixel buffer as a Metal texture through the texture
    /// cache (zero-copy on Apple platforms). The view is created with an sRGB
    /// pixel format so sampling decodes to linear, matching how the image
    /// pipeline composites (gamma-correct, linear-light).
    private func makeTexture(from buffer: CVPixelBuffer) -> MTLTexture? {
        if textureCache == nil {
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
            textureCache = cache
        }
        guard let cache = textureCache else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, buffer, nil, .bgra8Unorm_srgb, width, height, 0, &cvTexture)
        guard let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        inFlightTextures.append(cvTexture)
        if inFlightTextures.count > 4 { inFlightTextures.removeFirst() }
        return texture
    }
}

/// Pulls decoded frames from a dedicated video output and hands each new one
/// to the frame tap as a `CGImage`, from its own background queue — the pump
/// behind `VideoPlayer`'s `FrameSource` conformance.
///
/// Defined at file scope (not nested in the `@MainActor` `VideoPlayer`) so its
/// timer handler stays **non-isolated**; a main-actor-isolated closure would
/// trip an executor assertion the instant the background queue ran it. The
/// timer ticks faster than any common video's frame rate and
/// `hasNewPixelBuffer` gates the work, so frames are delivered at the
/// footage's own cadence and a paused video delivers nothing.
///
/// `@unchecked Sendable`: the output and `CIContext` are touched only on the
/// serial pump queue after init; the tap is `@Sendable`; `cancel()` on the
/// timer is thread-safe.
private final class VideoFrameTapPump: @unchecked Sendable {

    private let output: AVPlayerItemVideoOutput
    private let tap: FrameTap
    private let queue = DispatchQueue(label: "co.eavl.ollin.video.frametap")
    private let timer: any DispatchSourceTimer
    private let context = CIContext()

    init(output: AVPlayerItemVideoOutput, tap: @escaping FrameTap) {
        self.output = output
        self.tap = tap
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        self.timer = timer
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
    }

    /// A resumed GCD timer is kept alive by the system until cancelled, so the
    /// pump must cancel it explicitly (the handler's `weak self` keeps the
    /// timer from retaining the pump, which is what lets `deinit` run at all).
    func cancel() { timer.cancel() }

    deinit { timer.cancel() }

    private func tick() {
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard itemTime.isValid,
              output.hasNewPixelBuffer(forItemTime: itemTime),
              let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        tap(cgImage)
    }
}

/// Errors thrown while opening a video.
public enum VideoError: Error, CustomStringConvertible {
    case fileNotFound(String)
    case resourceNotFound(String)

    public var description: String {
        switch self {
        case .fileNotFound(let path): return "Video file not found: \(path)"
        case .resourceNotFound(let name): return "Video resource not found: \(name)"
        }
    }
}
