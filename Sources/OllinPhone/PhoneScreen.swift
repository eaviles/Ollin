import CoreFoundation
import Metal
import Ollin

/// A sketch shown on the phone's screen while it runs on the Mac.
///
/// The Mac draws, compresses each frame as video, and sends it down the cable;
/// the capture app shows it full screen and sends every finger on it back. So
/// the sketch keeps the Mac's live reload, its inspector, and its console, and
/// the question "does it look and feel right on the phone" is answered in the
/// hand, with nothing built or installed.
///
/// With no mode asked for, the phone goes to **Sketch** mode, which runs no
/// camera: the screen is the sketch and nothing else. With a camera mode asked
/// for (`device.use(.room)` beside `device.show(self)`), the phone keeps that
/// mode running under the picture, so a sketch that draws over the camera's
/// own picture makes the phone in the hand its viewfinder.
///
/// ```swift
/// let device = PhoneDevice()
/// override func setup() {
///     device.show(self)
/// }
/// override func draw() {
///     background(.black)
///     if mouseIsPressed { drawCircle(mouseX, mouseY, 40 + pressure * 60) }
/// }
/// ```
///
/// The phone's first finger is the sketch's pointer, the way a finger is when the
/// sketch is installed on the phone: `mouseX`, `mouseY`, `mouseIsPressed`, the
/// press and release hooks, and `pressure` where the glass measures force. A
/// second finger never moves it. Every finger still arrives on
/// `device.touches`, and the phone's motion on `device.latestMotion`, as they do
/// in any mode.
///
/// What it shows is the Mac's picture, so it answers how a piece looks and plays
/// in the hand, not whether the phone's own GPU keeps up with it; installing the
/// sketch answers that.
///
/// It is an extension of the sketch it shows, so a reloaded sketch makes its own
/// in `setup()`, and the phone moves over to it.
@MainActor
public final class PhoneScreen: SketchExtension {

    /// The phone this screen belongs to.
    public let device: PhoneDevice

    /// The most pictures a second it sends. A sketch drawing faster than this
    /// is sampled, and a cable slower than this skips frames rather than
    /// falling behind.
    public let frameRate: FrameRate

    /// Whether the phone's first finger drives the sketch's pointer. On by
    /// default; turn it off for a sketch that reads `device.touches` itself and
    /// wants the Mac's mouse left alone.
    public var drivesPointer = true {
        didSet {
            guard drivesPointer != oldValue, !isStopped else { return }
            if drivesPointer { device.touches.armPointer() } else { pendingRelease = true }
        }
    }

    /// Whether the phone is showing this sketch: its screen is given over to
    /// the sketch (in **Sketch** mode, or as the viewfinder of a camera mode)
    /// and a picture has reached it on the current connection.
    public var isShowing: Bool {
        !isStopped && phoneShowsSketch() && sender.hasSent
    }

    /// Where the screen is, in the words the other publishers of the sketch's
    /// frames use: `.stopped` after `stop()` (no later frame starts the
    /// pictures again; showing the sketch again means a new screen),
    /// `.publishing` while the phone is showing the sketch, and `.waiting`
    /// otherwise (for the phone, or for its screen, which the person holding
    /// it can take back).
    public var phase: PublisherPhase {
        if isStopped { return .stopped }
        return isShowing ? .publishing : .waiting
    }
    private var isStopped = false

    let sender: PhonePictureSender
    /// Whether the phone says its screen is the sketch's. The device's answer,
    /// unless a test says it.
    private let phoneShowsSketch: @MainActor () -> Bool
    private var encoder: PhonePictureEncoder?
    private var wasShowing = false
    private var lastSent: CFAbsoluteTime = 0
    private var pendingRelease = false
    /// Whether a finger on the phone holds the sketch's pointer down.
    private var holdsPress = false

    init(device: PhoneDevice, frameRate: FrameRate, sender: PhonePictureSender = PhonePictureSender(),
         phoneShowsSketch: (@MainActor () -> Bool)? = nil) {
        self.device = device
        self.frameRate = frameRate
        self.sender = sender
        self.phoneShowsSketch = phoneShowsSketch
            ?? { [device] in device.latestState?.isShowingSketch ?? false }
        device.touches.armPointer()
    }

    deinit { sender.stop() }

    /// Stop sending pictures. The phone keeps its last one until something else
    /// arrives; tap another mode on it to leave.
    public func stop() {
        guard !isStopped else { return }
        isStopped = true
        sender.stop()
        pendingRelease = true
    }

    // MARK: SketchExtension

    public func beforeDraw(_ sketch: Sketch) {
        if pendingRelease {
            pendingRelease = false
            apply(device.touches.disarmPointer(), to: sketch, showing: false)
        }
        guard !isStopped else { return }
        sender.keepWanted()

        // A screen that has just been given to the sketch has nothing to build on.
        let showing = phoneShowsSketch()
        if showing, !wasShowing { sender.requestKeyframe() }
        wasShowing = showing

        guard drivesPointer else { return }
        apply(device.touches.takePointerEvents(), to: sketch, showing: showing)
    }

    public var wantsRenderedTexture: Bool { canSend }

    public func frameRendered(_ sketch: Sketch, texture: MTLTexture) {
        // Asked a frame ago; ask again now that the frame is here.
        guard canSend else { return }
        if encoder == nil {
            encoder = PhonePictureEncoder(device: texture.device,
                                          framesPerSecond: frameRate.framesPerSecond,
                                          onPicture: Self.delivery(to: sender))
        }
        guard let encoder else { return }
        let keyframe = sender.takeKeyframeRequest()
        if encoder.encode(texture, forceKeyframe: keyframe) {
            lastSent = CFAbsoluteTimeGetCurrent()
        } else if keyframe {
            sender.requestKeyframe()
        }
    }

    // MARK: Inside

    /// Whether a frame should be compressed now: the phone's screen is the
    /// sketch's and it is connected, nothing is waiting to go or being
    /// compressed, and the rate allows it (a little early is allowed, so 60 on
    /// a 60 Hz display is 60).
    private var canSend: Bool {
        guard !isStopped, wasShowing, sender.isReady,
              (encoder?.inFlight ?? 0) == 0 else { return false }
        let interval = frameRate.frameDuration
        return CFAbsoluteTimeGetCurrent() - lastSent >= interval - 0.004
    }

    /// The compressor's output handler, built outside the main actor so the
    /// thread that calls it carries no executor assertion.
    nonisolated private static func delivery(to sender: PhonePictureSender)
        -> @Sendable (PhonePicture) -> Void {
        { picture in sender.send(picture) }
    }

    /// Hand the pointer's events to the sketch. A finger presses only while the
    /// phone shows the sketch, since on any other screen the glass is not the
    /// canvas; a press already held is always let go, whatever the phone is
    /// showing by then, so the sketch is never left pressed.
    private func apply(_ events: [PhonePointer.Event], to sketch: Sketch, showing: Bool) {
        let canvas = Rectangle(x: 0, y: 0, width: sketch.width, height: sketch.height)
        for event in events {
            switch event {
            case .press(let position, let force):
                guard showing else { continue }
                let point = PhoneTouch.mapped(position, in: canvas)
                sketch.setMouse(x: point.x, y: point.y)
                Self.press(force, on: sketch)
                sketch.handleMouseButton(pressed: true)
                holdsPress = true
            case .move(let position, let force):
                guard showing, holdsPress else { continue }
                let point = PhoneTouch.mapped(position, in: canvas)
                sketch.setMouse(x: point.x, y: point.y)
                Self.press(force, on: sketch)
            case .release(let position):
                guard holdsPress else { continue }
                if showing {
                    let point = PhoneTouch.mapped(position, in: canvas)
                    sketch.setMouse(x: point.x, y: point.y)
                }
                sketch.setPressure(0, canVary: false)
                sketch.handleMouseButton(pressed: false)
                holdsPress = false
            case .pair(let from, let to):
                // Two fingers pinch and turn the way they do on a trackpad.
                guard showing, let change = from.change(to: to, in: canvas) else { continue }
                if change.scale != 1 { sketch.handlePinch(by: change.scale) }
                if change.turn != 0 { sketch.handleTurn(by: change.turn) }
            }
        }
    }

    /// A screen that weighs a press reports it; one that cannot reports a plain
    /// full press, which is what the phone's own canvas does.
    private static func press(_ force: Double?, on sketch: Sketch) {
        if let force {
            sketch.setPressure(force, canVary: true)
        } else {
            sketch.setPressure(1, canVary: false)
        }
    }
}

public extension PhoneDevice {

    /// Show this sketch on the phone's screen while it runs here, and take the
    /// phone's fingers back as its pointer.
    ///
    /// Call it in `setup()`. It starts the device if it has not started, and
    /// with no mode asked for it asks the phone for **Sketch** mode, which runs
    /// no camera, so it is the whole setup:
    ///
    /// ```swift
    /// let device = PhoneDevice()
    /// override func setup() { device.show(self) }
    /// ```
    ///
    /// `show` keeps a mode the sketch asked for. With a camera mode running
    /// under it the phone is a viewfinder: the camera's picture comes up the
    /// cable, the sketch draws over it, and what it drew goes back to the
    /// screen in the hand.
    ///
    /// ```swift
    /// override func setup() {
    ///     device.use(.room)       // the phone tracks the room
    ///     device.show(self)       // and its screen shows this sketch
    /// }
    /// override func draw() {
    ///     guard let view = device.latestCamera else { return }
    ///     drawPhonePicture(view)
    ///     camera(view)
    ///     // whatever is drawn here stands in the room on the phone's screen
    /// }
    /// ```
    ///
    /// The order of the two calls does not matter, and a later `use(_:)`
    /// changes the mode under the picture.
    ///
    /// The pictures are HEVC at the canvas size, fitted under 1920 pixels on the
    /// long side, on a connection of their own beside the sensor stream. Returns
    /// the screen, for `isShowing` and `drivesPointer`.
    @discardableResult
    func show(_ sketch: Sketch, frameRate: FrameRate = 60) -> PhoneScreen {
        let screen = PhoneScreen(device: self, frameRate: frameRate)
        sketch.extend(screen)
        if !hasAskedForMode { use(.sketch) }
        start()
        return screen
    }
}
