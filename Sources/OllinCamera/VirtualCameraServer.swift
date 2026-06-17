import CoreFoundation
import Metal
import Ollin
import os

/// Publishes a sketch's rendered frames to the **Ollin Camera virtual camera**,
/// so every app that takes a webcam — video chat, recording, and streaming apps,
/// and browser tools through `getUserMedia` — reads the sketch as a
/// live camera. It's a `Sketch` extension: register one in `setup()` and every
/// frame is published automatically.
///
/// ```swift
/// final class Visuals: Sketch {
///     override func setup() {
///         publishVirtualCamera()      // or: extend(VirtualCameraServer())
///     }
///     override func draw() { /* draw as usual */ }
/// }
/// ```
///
/// The camera device itself is installed once by the Ollin Camera app (a system
/// extension); after that, any Ollin process — including a plain `swift run`
/// sketch — connects to it and feeds it. While nothing is feeding it, the
/// camera shows its built-in "no signal" test card, so a viewer can always
/// tell the camera works. If the device isn't installed, `isAvailable` stays
/// `false` and `unavailableReason` says what to do; the server keeps retrying
/// quietly, so installing the camera mid-run starts publishing without a
/// restart.
///
/// The frame is taken from the GPU (the same rendered-texture seam Syphon
/// publishes through), letterboxed into the camera's fixed 1280×720 frame, and
/// handed across to the camera extension as a shared-memory surface.
public final class VirtualCameraServer: SketchExtension {

    /// The camera device to publish to — the name Ollin Camera registers.
    public let deviceName: String

    /// `true` once at least one frame has been handed to the camera.
    public private(set) var isPublishing = false

    /// Whether the virtual camera is reachable (installed and connected).
    public var isAvailable: Bool { connection != nil }

    /// Why the camera isn't reachable, in user-actionable terms — most
    /// commonly that the Ollin Camera app hasn't been installed. `nil` while
    /// connected.
    public private(set) var unavailableReason: String?

    private var connection: SinkConnection?
    private var converter: FrameConverter?
    private var lastPublishAt: CFAbsoluteTime = 0
    private var lastConnectAttemptAt: CFAbsoluteTime = 0
    private var loggedUnavailable = false
    private let logger = Logger(subsystem: "dev.ollin", category: "VirtualCamera")

    /// Create a server that will publish to `deviceName` (default
    /// `"Ollin Camera"`).
    public init(deviceName: String = "Ollin Camera") {
        self.deviceName = deviceName
    }

    /// Stop feeding the camera and disconnect. Optional — dropping all
    /// references to this extension has the same effect. The camera falls back
    /// to its "no signal" test card within a second.
    public func stop() {
        connection = nil
        isPublishing = false
    }

    // MARK: SketchExtension

    /// Always wants the rendered frame as a texture — that's what gets published.
    public var wantsRenderedTexture: Bool { true }

    /// Publish each rendered frame, paced to the camera's frame rate. Runs on
    /// the main actor (the render loop), right after the frame is drawn.
    public func frameRendered(_ sketch: Sketch, texture: MTLTexture) {
        let now = CFAbsoluteTimeGetCurrent()
        // The camera runs at a fixed rate; a sketch usually draws faster.
        // A small tolerance keeps a 60 fps sketch from publishing at 20.
        guard now - lastPublishAt >= 1.0 / Double(FrameConverter.frameRate) - 0.002 else { return }

        if connection == nil {
            guard now - lastConnectAttemptAt >= 2 else { return }
            lastConnectAttemptAt = now
            switch SinkConnection.connect(toDeviceNamed: deviceName) {
            case .success(let sink):
                connection = sink
                unavailableReason = nil
                loggedUnavailable = false
                logger.info("Connected to \(self.deviceName, privacy: .public).")
            case .failure(let error):
                unavailableReason = error.description
                if !loggedUnavailable {
                    logger.warning("\(error.description, privacy: .public)")
                    loggedUnavailable = true
                }
                return
            }
        }
        guard let connection else { return }

        if converter == nil {
            converter = FrameConverter(device: texture.device)
        }
        guard let converter,
              let sampleBuffer = converter.makeSampleBuffer(from: texture)
        else { return }

        if connection.enqueue(sampleBuffer) {
            isPublishing = true
            lastPublishAt = now
        }
    }
}

extension Sketch {
    /// Start publishing this sketch's frames to the Ollin Camera virtual
    /// camera, so any app that takes a webcam can read them. Sugar for building
    /// a ``VirtualCameraServer`` and registering it; returns it so you can
    /// query `isAvailable` / `unavailableReason`. Call in `setup()`.
    @discardableResult
    public func publishVirtualCamera(deviceName: String = "Ollin Camera") -> VirtualCameraServer {
        let server = VirtualCameraServer(deviceName: deviceName)
        extend(server)
        return server
    }
}
