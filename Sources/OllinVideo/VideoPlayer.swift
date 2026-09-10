import Ollin
import AVFoundation
import CoreImage
import CoreVideo
import Metal
import os

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
///     if let frame = player.frame, let rect = player.fittedRectangle(in: bounds) {
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
public final class VideoPlayer: FrameSource, VideoFeed, ClipPlayback {

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
    public var isPlaying: Bool {
        if OllinApp.isRenderingHeadless { return virtualPlaying }
        return player.timeControlStatus != .paused
    }

    /// The video's duration in seconds, or `nil` until the file's metadata has
    /// loaded (it loads asynchronously, shortly after init).
    public private(set) var duration: Double?

    /// The video's pixel dimensions, or `nil` until known (from the file's
    /// metadata, or the first decoded frame, whichever lands first).
    public private(set) var size: Vector2?

    /// `size`, under the name the `VideoFeed` seam reads (`drawFrame` and
    /// `fittedRectangle(in:)` letterbox by it).
    public var frameSize: Vector2? { size }

    /// The current playback position in seconds.
    public var currentTime: Double {
        if OllinApp.isRenderingHeadless { return virtualTime }
        let t = player.currentTime()
        return t.isValid ? t.seconds : 0
    }

    /// The file being played (the `ClipPlayback` seam an analysis over the
    /// whole file, like the vision satellite's `DepthClip`, reads).
    public let url: URL
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    // Written once in init, read again only in deinit (which is nonisolated in
    // Swift 6, hence the unsafe opt-out); NotificationCenter tokens are safe to
    // remove from any thread.
    private nonisolated(unsafe) var endObserver: (any NSObjectProtocol)?

    // Headless (export) playback: the offline drivers run a fixed-timestep
    // loop with no runloop servicing, so the AVPlayer above never advances.
    // Under `OllinApp.isRenderingHeadless` the player instead keeps a virtual
    // playhead, advanced by the sketch's per-frame pass (`advance(by:)`), and
    // `frame` decodes by timestamp through a `HeadlessVideoReader`, making
    // exported video deterministic against the sketch clock.
    private var headlessReader: HeadlessVideoReader?
    private var headlessReaderFailed = false
    private var virtualTime: Double = 0
    private var virtualPlaying = false
    // `play()` arms the playhead instead of moving it: the first advance after
    // it covers time that passed *before* playback began, so it isn't counted.
    private var virtualArmed = false

    // The audio tap's shared state; created with the tap on first install and
    // owned by the tap from then on (see `VideoAudioTapStorage`).
    private var audioTapStorage: VideoAudioTapStorage?
    private var audioTapInstallStarted = false

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

    /// The soundtrack tap (`AudioTapSource`). Installing one attaches a
    /// processing tap to the player item's audio mix and delivers mono PCM
    /// from the audio thread as the video plays; the usual consumer is
    /// OllinAudio's `Soundtrack`, which runs the full analyzer surface
    /// (`amplitude` / `spectrum` / `beat`, …) over it. The tap reads the
    /// soundtrack before volume shaping, so a sketch can react to a video it
    /// keeps *quiet*: turn `volume` all the way down and the consumer still
    /// hears the full signal. `isMuted = true` is the one exception; a hard
    /// mute stops audio processing altogether and the tap goes silent with
    /// it, so prefer `volume = 0` when the visuals should keep reacting.
    public var audioTap: AudioTap? {
        didSet {
            if let audioTapStorage {
                audioTapStorage.handler.withLock { [audioTap] in $0 = audioTap }
            } else if audioTap != nil {
                installAudioTap()
            }
        }
    }

    /// Builds the processing tap and hangs it on the item's audio mix. Done
    /// once; afterwards installing/replacing/removing a consumer is just the
    /// handler swap in `audioTap`'s observer. The track load is asynchronous,
    /// so the first samples arrive shortly after; a clip with no audio track
    /// simply never delivers.
    private func installAudioTap() {
        guard !audioTapInstallStarted else { return }
        audioTapInstallStarted = true
        let storage = VideoAudioTapStorage()
        storage.handler.withLock { [audioTap] in $0 = audioTap }
        audioTapStorage = storage
        guard let item = player.currentItem else { return }
        Task {
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first,
                  let tap = makeVideoAudioTap(storage: storage) else { return }
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [parameters]
            item.audioMix = mix
        }
    }

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
        self.url = url
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
        if OllinApp.isRenderingHeadless {
            if let duration = headlessDuration, duration > 0, virtualTime >= duration {
                virtualTime = 0
            }
            if !virtualPlaying { virtualArmed = true }
            virtualPlaying = true
            return
        }
        if let duration, duration > 0, currentTime >= duration {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.playImmediately(atRate: Float(rate))
    }

    /// Pauses playback, keeping the position.
    public func pause() {
        if OllinApp.isRenderingHeadless {
            virtualPlaying = false
            return
        }
        player.pause()
    }

    /// Stops playback and rewinds to the beginning.
    public func stop() {
        if OllinApp.isRenderingHeadless {
            virtualPlaying = false
            virtualTime = 0
            return
        }
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Jumps to `seconds` from the start (clamped to the video by the player).
    public func seek(to seconds: Double) {
        if OllinApp.isRenderingHeadless {
            virtualTime = max(0, seconds)
            if let duration = headlessDuration, duration > 0 {
                virtualTime = min(virtualTime, duration)
            }
            return
        }
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// The current video frame as a drawable `Image`, or `nil` before the first
    /// frame decodes. The image wraps the decoded frame's GPU texture directly;
    /// while no new frame is due (paused, or drawing faster than the video's
    /// frame rate) the previous frame is returned, so it always draws something
    /// once playback has begun.
    public var frame: Image? {
        if OllinApp.isRenderingHeadless { return headlessFrame() }
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

    /// `frame` under a headless driver: decode by the virtual playhead. The
    /// same texture wrap as the live path, so what an export composites is
    /// pixel-identical to what a live window would have shown at that moment.
    private func headlessFrame() -> Image? {
        guard let reader = ensureHeadlessReader(),
              let buffer = reader.pixelBuffer(at: virtualTime)
        else { return cachedFrame }
        if buffer === lastPixelBuffer, let cachedFrame { return cachedFrame }
        guard let texture = makeTexture(from: buffer) else { return cachedFrame }
        lastPixelBuffer = buffer
        let image = Image(texture: texture)
        cachedFrame = image
        return image
    }

    /// The clip duration as the headless reader knows it (its synchronous
    /// load fills `duration` in even when the async metadata task never got a
    /// turn on the busy export loop).
    private var headlessDuration: Double? { headlessReader?.duration ?? duration }

    private func ensureHeadlessReader() -> HeadlessVideoReader? {
        if let headlessReader { return headlessReader }
        guard !headlessReaderFailed else { return nil }
        guard let reader = HeadlessVideoReader(url: url) else {
            headlessReaderFailed = true
            return nil
        }
        headlessReader = reader
        if duration == nil { reader.duration.map { duration = $0 } }
        if size == nil, let natural = reader.naturalSize, natural.width > 0 {
            size = Vector2(natural.width, natural.height)
        }
        return reader
    }

    /// A CPU-backed copy of the current frame, or `nil` before one decodes.
    /// Unlike `frame` (a live GPU texture), the result supports the CPU paths —
    /// pixel reads via `image[x, y]`, `cgImage`, and a vision tracker's
    /// `detect(in:)` — at the cost of a GPU→CPU copy, so take one when needed
    /// rather than every frame. Under a headless export it reads the same
    /// virtual playhead `frame` does, so `seek(to:)` then `snapshot()` hands
    /// back exactly the moment asked for.
    public func snapshot() -> Image? {
        // Under a headless driver there is no runloop decoding into the output,
        // so the copy below has nothing to take. Pull the playhead's own frame
        // first: that is what fills the buffer, and it costs a decode only when
        // the sketch has not already drawn this moment.
        if OllinApp.isRenderingHeadless { _ = headlessFrame() }
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

/// The tap side of the soundtrack seam lives on the class (`audioTap` and its
/// installer); the marker keeps the conformance greppable beside its sibling
/// `FrameSource`.
extension VideoPlayer: AudioTapSource {}

// MARK: Export clock

/// The per-frame advance pass (the one that steps `@Eased` and `Timeline`)
/// also steps the virtual playhead while a headless driver runs, so an
/// exported video follows the sketch clock exactly: frame `k` of an export
/// always shows the clip at `k / fps` seconds after `play()` (times `rate`,
/// wrapped by `loops`). The conformance is main-actor isolated, matching the
/// pass that calls it.
extension VideoPlayer: @MainActor FrameAdvancing {
    package func advance(by dt: Double) {
        guard OllinApp.isRenderingHeadless, virtualPlaying else { return }
        if virtualArmed {
            // The dt that elapsed before `play()` isn't playback time.
            virtualArmed = false
        } else {
            virtualTime += dt * rate
        }
        // Created here as well as on the first `frame` read, so `duration` and
        // `size` are filled in before the sketch first draws.
        _ = ensureHeadlessReader()
        guard let duration = headlessDuration, duration > 0, virtualTime >= duration else { return }
        if loops {
            virtualTime.formTruncatingRemainder(dividingBy: duration)
        } else {
            virtualTime = duration
            virtualPlaying = false
        }
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
        queue.setSpecific(key: Self.onPumpQueue, value: true)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(16))
        self.timer = timer
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
    }

    /// Cleared by `cancel()`, and read once more immediately before the tap is
    /// called. Canceling a timer stops the *next* tick, and says nothing about
    /// the one already running: a tick that has passed its guards is holding a
    /// pixel buffer and is about to spend a millisecond or two turning it into
    /// an image, so without this it delivers a frame after the caller cleared
    /// the tap and believes nothing more can arrive.
    private let live = OSAllocatedUnfairLock(initialState: true)

    /// Set on the pump's own queue, so `cancel()` can tell whether it is being
    /// called from inside a delivery and skip the drain that would deadlock.
    private static let onPumpQueue = DispatchSpecificKey<Bool>()

    /// A resumed GCD timer is kept alive by the system until canceled, so the
    /// pump must cancel it explicitly (the handler's `weak self` keeps the
    /// timer from retaining the pump, which is what lets `deinit` run at all).
    ///
    /// The empty `sync` is the drain: the queue is serial, so it runs after any
    /// tick already under way, and the caller therefore holds no live delivery
    /// once this returns. A tap that clears itself from inside its own callback
    /// is running *on* that queue, where a `sync` would deadlock, so that case
    /// takes the flag alone (it is the delivery, and there is no other).
    func cancel() {
        live.withLock { $0 = false }
        timer.cancel()
        if DispatchQueue.getSpecific(key: Self.onPumpQueue) != true { queue.sync {} }
    }

    deinit { cancel() }

    private func tick() {
        guard live.withLock({ $0 }) else { return }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        guard itemTime.isValid,
              output.hasNewPixelBuffer(forItemTime: itemTime),
              let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        guard live.withLock({ $0 }) else { return }
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
