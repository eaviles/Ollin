import Ollin
import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import os

/// The Mac's camera as a frame source for a sketch — the built-in FaceTime
/// camera, a Continuity Camera iPhone, or an external webcam. Create one in
/// `setup()`, `start()` it, then draw `frame` in `draw()`. Attach a tracker
/// (`FaceTracker`, and the ones to come) to the same camera to get recognition
/// over the live feed.
///
/// ```swift
/// let camera = Camera()
/// override func setup() { try? camera.start() }
/// override func draw() {
///     if let frame = camera.frame { drawImage(frame, in: bounds) }
/// }
/// ```
///
/// Using the camera needs the user's permission; `start()` requests it the first
/// time. Until it's granted, `frame` stays `nil`.
@MainActor
public final class Camera: FrameSource {

    /// Which camera to use. `.default` is the system's default video device (the
    /// built-in camera on most Macs); the rest pick the first device of a kind.
    public enum Device: Sendable {
        case `default`
        case builtIn
        /// A nearby iPhone acting as a Continuity Camera.
        case continuity
        /// An external USB/Thunderbolt webcam.
        case external
        /// The Desk View camera (the downward-angled view a Continuity Camera offers).
        case deskView
    }

    /// Whether capture is currently running.
    public private(set) var isRunning = false

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "co.eavl.ollin.vision.camera")
    private let store = FrameStore()
    private let device: Device

    /// The analysis tap (`FrameSource`). The capture delegate reads it on the
    /// capture queue, so the live value crosses through a locked box.
    public var frameTap: FrameTap? {
        didSet {
            let tap = frameTap
            tapStore.withLock { $0 = tap }
        }
    }
    private let tapStore = OSAllocatedUnfairLock<FrameTap?>(initialState: nil)

    private var delegate: CameraCaptureDelegate?
    private var configured = false

    // Cache the wrapped `Image` so repeated `frame` reads in one draw don't
    // rebuild it; a new capture (new `CGImage`) invalidates the cache.
    private var cachedImage: Image?
    private var cachedFrameID: ObjectIdentifier?

    /// Create a camera bound to `device` (the default video device by default).
    public init(_ device: Device = .default) {
        self.device = device
    }

    /// Begin capturing. Gates on camera permission the same way the microphone
    /// does: if it's already granted, capture starts now; if it hasn't been asked,
    /// the system prompts and capture starts once the user allows it; if it's
    /// denied, nothing starts (`frame` stays `nil`).
    public func start() throws {
        guard !isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            try configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                guard granted else { return }
                Task { @MainActor in try? self.configureAndRun() }
            }
        default:
            break   // denied or restricted — no frames
        }
    }

    /// Stop capturing. Safe to call when not running.
    public func stop() {
        guard isRunning else { return }
        session.stopRunning()
        isRunning = false
    }

    /// The latest captured frame as a drawable `Image`, or `nil` before the first
    /// frame arrives (or while permission is pending). A fresh image each new
    /// frame — hold it only for the current `draw()`, don't cache it across frames.
    public var frame: Image? {
        guard let box = store.latest else { return nil }
        let id = ObjectIdentifier(box.cgImage)
        if cachedFrameID == id, let cachedImage { return cachedImage }
        let image = Image(cgImage: box.cgImage)
        cachedImage = image
        cachedFrameID = id
        return image
    }

    /// The pixel dimensions of the latest frame, or `nil` before one arrives.
    public var frameSize: Vector2? {
        guard let box = store.latest else { return nil }
        return Vector2(Double(box.width), Double(box.height))
    }

    /// The letterboxed rectangle that fits the camera frame inside `container`
    /// without stretching — draw the frame into it and map results into the same
    /// rectangle so overlays line up. `nil` before the first frame.
    public func fittedRect(in container: Rectangle) -> Rectangle? {
        guard let size = frameSize else { return nil }
        return VisionSpace.fittedRect(imageSize: size, in: container)
    }

    private func configureAndRun() throws {
        if !configured {
            try configure()
            configured = true
        }
        // `startRunning()` is synchronous and can take a moment on first launch;
        // a one-time hitch at setup, acceptable for a sketch.
        session.startRunning()
        isRunning = true
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }

        guard let captureDevice = Camera.resolveDevice(device) else {
            throw CameraError.noDevice
        }
        let input = try AVCaptureDeviceInput(device: captureDevice)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        let delegate = CameraCaptureDelegate(store: store, tapStore: tapStore)
        output.setSampleBufferDelegate(delegate, queue: queue)
        self.delegate = delegate
        guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        session.addOutput(output)
    }

    private static func resolveDevice(_ device: Device) -> AVCaptureDevice? {
        let type: AVCaptureDevice.DeviceType
        switch device {
        case .default:    return AVCaptureDevice.default(for: .video)
        case .builtIn:    type = .builtInWideAngleCamera
        case .continuity: type = .continuityCamera
        case .external:   type = .external
        case .deskView:   type = .deskViewCamera
        }
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [type], mediaType: .video, position: .unspecified)
        return discovery.devices.first ?? AVCaptureDevice.default(for: .video)
    }
}

/// Why the camera couldn't start.
public enum CameraError: Error, Sendable {
    case noDevice
    case cannotAddInput
    case cannotAddOutput
}

/// Receives frames on the capture queue and fans them out: the display frame to
/// the `FrameStore`, and a copy to the installed frame tap for recognition.
///
/// Defined at file scope (not nested in the `@MainActor` `Camera`) on purpose, so
/// its delegate method stays **non-isolated** — the capture queue calls it off
/// the main thread, and a main-actor-isolated method would trip an executor
/// assertion the instant that happens. It captures only `Sendable` collaborators,
/// and its `CIContext` is touched only here on the serial capture queue.
private final class CameraCaptureDelegate: NSObject,
    AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    private let store: FrameStore
    private let tapStore: OSAllocatedUnfairLock<FrameTap?>
    private let context = CIContext()

    init(store: FrameStore, tapStore: OSAllocatedUnfairLock<FrameTap?>) {
        self.store = store
        self.tapStore = tapStore
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        store.store(FrameBox(cgImage))
        if let tap = tapStore.withLock({ $0 }) { tap(cgImage) }
    }
}
