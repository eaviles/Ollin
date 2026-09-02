import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import Metal
import Ollin
import ScreenCaptureKit
import os

/// Any window or display on the Mac as a live picture a sketch can draw, filter,
/// and analyze. Where the camera hands over what it sees and a video player hands
/// over a file, this hands over the machine's own screen, so anything running on
/// it becomes material: a browser, a map, a terminal, another sketch.
///
/// ```swift
/// import OllinScreen
///
/// final class Mirror: Sketch {
///     let screen = ScreenCapture(.mainDisplay)
///     override func setup() { screen.start() }
///     override func draw() {
///         background(.black)
///         drawFrame(screen)
///     }
/// }
/// ```
///
/// Frames arrive as GPU textures and are drawn with `drawImage`, so they ride the
/// transform stack, `tint`, the effect graph, and every filter, with no trip
/// through the CPU. The capture is also a `FrameSource`, so a vision tracker
/// attaches to it exactly the way it attaches to a camera and runs over whatever
/// is on screen.
///
/// ## Permission
///
/// Capturing the screen needs the user's consent, which is the one thing here a
/// drawing framework cannot arrange for itself. ``isAvailable`` says whether the
/// consent is in place, ``unavailableReason`` says what to do about it when it is
/// not, and ``requestAccess()`` asks. A capture with no permission draws its
/// waiting notice and takes no frames, rather than failing silently. See
/// `Docs/Integration/ScreenCapture.md` for what the prompt actually looks like
/// for a sketch run from the terminal, which is not what you might expect.
///
/// ## Capturing the screen a sketch is drawn on
///
/// By default the sketch's own windows are cut out of a display capture
/// (``excludesOwnWindows``), because otherwise a full-screen capture draws the
/// window it is being drawn in and the picture eats itself. Turning it off is
/// supported and is the point of doing so: the feedback that results is a real
/// effect, and an old one.
@MainActor
public final class ScreenCapture: FrameSource, VideoFeed {

    // MARK: What to capture

    /// What this capture points at. Assigning a new source rebinds a running
    /// capture in place, so a sketch can switch windows from a `@Param` or a key
    /// press without stopping and starting.
    public var source: ScreenSource {
        didSet { if source != oldValue, isRunning { restart() } }
    }

    /// Whether the sketch's own windows are left out of a display capture.
    /// `true` by default, so pointing a sketch at the screen it is drawn on
    /// shows everything except itself.
    ///
    /// Set it to `false` for the feedback: the sketch draws the screen, which
    /// contains the sketch drawing the screen, and the picture tunnels into
    /// itself. It has no effect when capturing a single window or another app,
    /// where the sketch was never in the picture to begin with.
    public var excludesOwnWindows = true {
        didSet { if excludesOwnWindows != oldValue, isRunning { restart() } }
    }

    /// Whether the mouse pointer is drawn into the captured frames. `true` by
    /// default, matching what a screen recording shows.
    public var showsCursor = true {
        didSet { if showsCursor != oldValue, isRunning { applyConfiguration() } }
    }

    /// The most frames per second to take. The system delivers a frame only when
    /// the captured content actually changes, so a still screen costs nothing
    /// whatever this is set to; the cap is what keeps a busy screen from
    /// outrunning the sketch. 60 by default.
    public var frameRate: Double = 60 {
        didSet { if frameRate != oldValue, isRunning { applyConfiguration() } }
    }

    /// A multiplier on the captured pixel size. `1` (the default) captures at the
    /// display's true backing resolution, which on a Retina screen is twice its
    /// size in points. Halving it is the cheap way to feed a heavy effect chain,
    /// or to capture a 5K display without a 5K texture per frame.
    public var scale: Double = 1 {
        didSet {
            let clamped = max(0.05, min(1, scale))
            if clamped != scale { scale = clamped; return }
            if scale != oldValue, isRunning { restart() }
        }
    }

    // MARK: State

    /// Whether the sketch has asked for frames (``start()`` called and not yet
    /// ``stop()``). It stays `true` while the capture waits for a window that is
    /// not open yet, so it means "wanted", not "arriving".
    public private(set) var isRunning = false

    /// Whether the capture is bound to something and frames have started
    /// arriving, as opposed to still looking for the window it was told to find.
    public var isReceiving: Bool { streamIsLive && store.hasDelivered }

    /// Whether screen capture can run at all: whether this Mac has granted the
    /// screen-recording permission to whatever launched the sketch. Reads the
    /// system's answer each time, so it flips to `true` in the same session the
    /// permission is granted.
    public nonisolated static var isAvailable: Bool { CGPreflightScreenCaptureAccess() }

    /// Why screen capture cannot run, in a sentence fit to draw on the canvas, or
    /// `nil` when it can.
    public nonisolated static var unavailableReason: String? {
        isAvailable
            ? nil
            : "Screen recording permission is off. Allow it in System Settings › Privacy & Security › Screen & System Audio Recording, then run the sketch again."
    }

    /// Ask for the screen-recording permission. The system shows its prompt the
    /// first time anything asks; afterwards it does nothing, and the permission
    /// has to be changed in System Settings.
    ///
    /// Granting it does not reach a process that is already running: the sketch
    /// has to be started again. ``start()`` calls this for you, so a sketch
    /// usually never needs it.
    @discardableResult
    public nonisolated static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Why this capture has nothing to show, or `nil` when frames are arriving.
    /// Covers the permission being off, the named window not being open, and a
    /// stream the system stopped.
    public private(set) var unavailableReason: String?

    // MARK: Frames

    /// The latest captured frame as a drawable `Image`, or `nil` before the first
    /// one arrives. A fresh image each new frame: hold it for the current
    /// `draw()` only.
    public var frame: Image? {
        guard let buffer = store.take() else { return cachedFrame }
        guard let texture = makeTexture(from: buffer) else { return cachedFrame }
        let image = Image(texture: texture)
        cachedFrame = image
        return image
    }

    /// The pixel dimensions of the captured frames, or `nil` before the first one
    /// arrives.
    public private(set) var frameSize: Vector2?

    /// The notice `drawFrame(screen)` shows before the first frame, which names
    /// what is being waited for or what is wrong.
    public var waitingMessage: String {
        unavailableReason ?? "Waiting for \(source.label)…"
    }

    /// The analysis tap (`FrameSource`). Installing one turns each captured frame
    /// into a `CGImage` on the capture queue and hands it over, so a vision
    /// tracker can read the screen. Nothing is converted while no tap is
    /// installed, so a capture that is only drawn never pays for it.
    public var frameTap: FrameTap? {
        didSet {
            let tap = frameTap
            tapStore.withLock { $0 = tap }
        }
    }

    // MARK: Private state

    private let store = ScreenFrameStore()
    private let tapStore = OSAllocatedUnfairLock<FrameTap?>(initialState: nil)
    private let queue = DispatchQueue(label: "co.eavl.ollin.screen.capture")

    // The stream and its output have to be held: a stream nobody references is
    // torn down and simply stops delivering, with no error and no callback. They
    // live in a holder rather than in stored properties so the nonisolated
    // `deinit` can end the capture, which it cannot do by reading a non-Sendable
    // property of a main-actor class.
    private let held = StreamHolder()
    private var streamIsLive = false

    // Resolving a source is asynchronous and may find nothing yet, so it runs as
    // a task that retries until the window appears or the sketch stops.
    private var binder: Task<Void, Never>?

    private var textureCache: CVMetalTextureCache?
    // Each frame's texture wraps a pixel buffer the renderer may still be reading
    // a frame or two later, so a short ring holds them alive past the swap.
    private var inFlightTextures: [CVMetalTexture] = []
    private var cachedFrame: Image?

    // MARK: Lifecycle

    /// Create a capture pointed at `source`. Nothing happens until ``start()``.
    public init(_ source: ScreenSource = .mainDisplay) {
        self.source = source
    }

    deinit {
        binder?.cancel()
        // `stopCapture` is documented safe from any thread, and dropping the
        // references is what actually ends the capture.
        held.stop()
    }

    /// Begin capturing. Asks for the screen-recording permission the first time
    /// anything on the Mac does.
    ///
    /// The named source does not have to exist yet: if the window is not open,
    /// the capture waits and starts by itself when it appears, so a sketch can
    /// name a window and then go open it. Safe to call when already running.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        guard Self.isAvailable else {
            // Asking is what shows the prompt; the answer cannot arrive in this
            // process, so say what happens next rather than waiting for it.
            _ = Self.requestAccess()
            unavailableReason = Self.unavailableReason
            isRunning = false
            return
        }
        unavailableReason = nil
        bind()
    }

    /// Stop capturing and release the stream. Safe to call when not running.
    public func stop() {
        isRunning = false
        binder?.cancel()
        binder = nil
        teardownStream()
        store.clear()
        unavailableReason = nil
    }

    // MARK: Binding

    /// Look for the source and start a stream on it, retrying while it is not
    /// found. One task at a time; a rebind cancels the one in flight.
    private func bind() {
        binder?.cancel()
        binder = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let attached = await self.attemptBind()
                if attached || Task.isCancelled { return }
                // Nothing matched. Wait before looking again, so a sketch naming a
                // window that never opens costs almost nothing.
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// One attempt at resolving the source and standing a stream up on it.
    /// Returns whether the stream started.
    private func attemptBind() async -> Bool {
        let excluded = excludesOwnWindows ? ProcessInfo.processInfo.processIdentifier : nil
        let wanted = source
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard !Task.isCancelled else { return true }
            guard let filter = resolveFilter(wanted, in: content, excludingPID: excluded) else {
                unavailableReason = "Waiting for \(wanted.label)…"
                return false
            }
            try await startStream(on: filter)
            return true
        } catch {
            unavailableReason = Self.reason(for: error)
            return false
        }
    }

    private func startStream(on filter: SCContentFilter) async throws {
        teardownStream()

        let config = SCStreamConfiguration()
        apply(config, for: filter)

        let output = ScreenStreamOutput(store: store, tapStore: tapStore) { [weak self] error in
            // The stream ended on its own: the window closed, the display went
            // away, or the system stopped it. Report it and start looking again.
            Task { @MainActor in self?.streamEnded(error) }
        }
        let stream = SCStream(filter: filter, configuration: config, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()

        held.stream = stream
        held.output = output
        self.currentFilter = filter
        self.streamIsLive = true
        self.unavailableReason = nil
    }

    /// Fill in a stream configuration for `filter`. The captured size is the
    /// filter's own content rectangle at the display's backing scale, so a
    /// Retina screen is captured at its true pixel size rather than its size in
    /// points, then scaled by ``scale``.
    private func apply(_ config: SCStreamConfiguration, for filter: SCContentFilter) {
        let points = filter.contentRect.size
        let pixelScale = Double(filter.pointPixelScale) * scale
        config.width = max(2, Int((points.width * pixelScale).rounded()))
        config.height = max(2, Int((points.height * pixelScale).rounded()))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        // The captured bytes are display-ready sRGB, and the texture is read back
        // through an sRGB format to match, so the renderer's linear pipeline
        // decodes them once and the screen's colors survive the round trip.
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = showsCursor
        config.scalesToFit = false
        config.preservesAspectRatio = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
        // A few buffers of slack, so a frame the renderer still holds does not
        // starve the pool that produces the next one.
        config.queueDepth = 6
    }

    /// Push changed settings onto a running stream, for the parameters that do not
    /// need a new filter.
    private func applyConfiguration() {
        guard let stream = held.stream, let filter = currentFilter else { return }
        let config = SCStreamConfiguration()
        apply(config, for: filter)
        stream.updateConfiguration(config, completionHandler: { _ in })
    }

    private var currentFilter: SCContentFilter?

    private func restart() {
        teardownStream()
        store.clear()
        guard isRunning else { return }
        bind()
    }

    private func teardownStream() {
        streamIsLive = false
        held.stop()
        currentFilter = nil
        inFlightTextures.removeAll()
        cachedFrame = nil
    }

    private func streamEnded(_ error: any Error) {
        guard isRunning else { return }
        streamIsLive = false
        unavailableReason = Self.reason(for: error)
        // Whatever ended it, the source may come back (a window reopens, a
        // display is plugged in again), so keep looking.
        restart()
    }

    /// Turn a capture failure into a sentence worth drawing on a canvas.
    private nonisolated static func reason(for error: any Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else { return error.localizedDescription }
        switch nsError.code {
        case -3801:  // the user declined, or was never asked
            return unavailableReason
                ?? "Screen recording permission was declined for this sketch."
        case -3817:  // the user pressed stop in the menu bar
            return "Screen capture was stopped."
        case -3821:
            return "The system stopped the screen capture."
        case -3815, -3813, -3814:
            return "Nothing left to capture."
        default:
            return "Screen capture stopped (error \(nsError.code))."
        }
    }

    // MARK: Texture

    /// Wrap a captured pixel buffer as a Metal texture, without copying: the
    /// buffer is IOSurface-backed, so the texture cache maps the same memory the
    /// window server wrote.
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
        var wrapped: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            nil, cache, buffer, nil, .bgra8Unorm_srgb, width, height, 0, &wrapped)
        guard result == kCVReturnSuccess,
              let wrapped, let texture = CVMetalTextureGetTexture(wrapped) else { return nil }
        frameSize = Vector2(Double(width), Double(height))
        // A fresh texture every frame, never a write into the one already handed
        // to the renderer, which may still be reading it for a frame in flight.
        inFlightTextures.append(wrapped)
        if inFlightTextures.count > 4 { inFlightTextures.removeFirst() }
        return texture
    }

    // MARK: What is on screen

    /// Every display that can be captured. Needs the screen-recording permission;
    /// returns an empty array without it.
    public nonisolated static func availableDisplays() async -> [ScreenDisplay] {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return [] }
        let main = CGMainDisplayID()
        return content.displays
            .map {
                ScreenDisplay(id: $0.displayID,
                              size: CGSize(width: $0.width, height: $0.height),
                              isMain: $0.displayID == main)
            }
            .sorted { $0.id < $1.id }
    }

    /// Every on-screen window that can be captured, ordered by window id so a
    /// listing reads the same way twice. Needs the screen-recording permission;
    /// returns an empty array without it.
    public nonisolated static func availableWindows() async -> [ScreenWindow] {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }
        return content.windows
            .map {
                ScreenWindow(id: $0.windowID,
                             title: $0.title,
                             appName: $0.owningApplication?.applicationName,
                             bundleIdentifier: $0.owningApplication?.bundleIdentifier,
                             frame: $0.frame)
            }
            .sorted { $0.id < $1.id }
    }

    /// Every application with a capturable window, ordered by name. Needs the
    /// screen-recording permission; returns an empty array without it.
    public nonisolated static func apps() async -> [ScreenApp] {
        guard let content = try? await SCShareableContent
            .excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return [] }
        return content.applications
            .map { ScreenApp(id: $0.processID, name: $0.applicationName,
                             bundleIdentifier: $0.bundleIdentifier) }
            .sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }
    }
}

// MARK: Frame delivery

/// Keeps the running stream and its output alive, and ends them. It exists so
/// the capture's nonisolated `deinit` can stop a stream it would otherwise not
/// be allowed to touch, and because a stream nobody holds is deallocated and
/// stops delivering with no error and no callback to say so.
private final class StreamHolder: @unchecked Sendable {
    var stream: SCStream?
    var output: AnyObject?

    func stop() {
        stream?.stopCapture(completionHandler: { _ in })
        stream = nil
        output = nil
    }
}

/// Holds the newest captured frame for the main actor to pick up. The window
/// server delivers on a background queue and the sketch reads on the main one, so
/// the buffer crosses through a lock, and only the newest is kept: a sketch draws
/// the current screen, and an older frame it never got to has nothing to say.
/// A plain lock rather than `OSAllocatedUnfairLock`'s generic form, because a
/// `CVPixelBuffer` is explicitly not `Sendable` and so cannot be that lock's
/// state. It is safe to hand across all the same: the buffer is a Core
/// Foundation object, and the lock is what keeps the two threads from touching
/// the reference at once.
private final class ScreenFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: CVPixelBuffer?
    private var delivered = false

    func store(_ buffer: CVPixelBuffer) {
        lock.lock()
        pending = buffer
        delivered = true
        lock.unlock()
    }

    /// The newest frame if one arrived since the last read, else `nil` (the
    /// caller keeps drawing the frame it already has).
    func take() -> CVPixelBuffer? {
        lock.lock()
        defer { pending = nil; lock.unlock() }
        return pending
    }

    /// Whether any frame has arrived since the last ``clear()``. Read rather than
    /// derived from `pending`, which a draw empties every frame.
    var hasDelivered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return delivered
    }

    func clear() {
        lock.lock()
        pending = nil
        delivered = false
        lock.unlock()
    }
}

/// Receives captured frames and the stream's own end-of-life notice.
///
/// Defined at file scope, outside the `@MainActor` capture, on purpose: the
/// window server calls it on a background queue, and a main-actor-isolated
/// method would trip an executor assertion the moment that happens. It holds only
/// `Sendable` collaborators, and its `CIContext` is touched only here, on the one
/// serial capture queue.
private final class ScreenStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate,
                                        @unchecked Sendable {

    private let store: ScreenFrameStore
    private let tapStore: OSAllocatedUnfairLock<FrameTap?>
    private let onStop: @Sendable (any Error) -> Void
    private lazy var context = CIContext()

    init(store: ScreenFrameStore,
         tapStore: OSAllocatedUnfairLock<FrameTap?>,
         onStop: @escaping @Sendable (any Error) -> Void) {
        self.store = store
        self.tapStore = tapStore
        self.onStop = onStop
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen else { return }
        // A delivered frame is not always a new picture: the system also sends
        // idle and blank frames, flagged in the sample's status. Only a complete
        // one carries pixels worth showing.
        guard isComplete(sampleBuffer),
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        store.store(buffer)
        // The CPU copy is made only when something is analyzing the feed.
        guard let tap = tapStore.withLock({ $0 }) else { return }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        tap(cgImage)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStop(error)
    }

    private func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
