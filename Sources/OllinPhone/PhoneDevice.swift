import Foundation
import CoreGraphics
import simd
import os
import Ollin
import OllinUSBMux
#if canImport(Darwin)
import Darwin
#endif

/// A live sensor stream from a tethered iPhone running the **Ollin** capture app
/// (Apps/OllinPhoneApp) — the phone runs ARKit on its own Neural Engine and streams
/// typed results the Mac reads in `draw()`: a 3D **body skeleton**, a **face** (the
/// deforming mesh + the 52 expression blendshapes), a world-facing **RGBD depth
/// frame** from the rear LiDAR, and **device motion**.
///
/// ```swift
/// let device = PhoneDevice()
/// override func setup() { device.start() }
/// override func draw() {
///     guard let body = device.latestBody else {
///         return drawStatus(device.waitingMessage, style: .info)
///     }
///     camera(.orbiting(target: body.center, radius: 2.5, azimuth: time * 0.3))
///     drawPointCloud(body.cloud())
/// }
/// ```
///
/// In **World** mode the capture app streams a world-facing RGBD frame from the
/// rear LiDAR instead — `latestDepthFrame` / `pointCloud(...)` unproject it into a
/// colored cloud, and each frame's `latestPose` carries the 6DoF camera transform
/// for world fusion. The device is also a `FrameSource` + `VideoFeed`, so a vision
/// tracker can analyze the depth-mode color feed and `drawFrame` can letterbox it.
///
/// Launch the Ollin capture app on the iPhone and connect the cable; the device
/// keeps retrying, so plugging in or starting the app mid-run just works. The
/// transport is the standard `usbmuxd` tunnel (port 1338); the wire format is
/// Ollin's own (`PhoneWire`).
@MainActor
public final class PhoneDevice: FrameSource, VideoFeed {

    /// The TCP port the Ollin capture app listens on (tunnelled via usbmuxd) —
    /// defined once in `PhoneWire` so both ends agree.
    public nonisolated static let streamPort: UInt16 = PhoneWire.streamPort

    private let reader: PhoneStreamReader

    // Build the drawable `RGBDFrame` lazily and cache it by the box's sequence, so
    // repeated reads in one `draw()` (frame, frameSize, pointCloud) reuse it.
    private var cachedSequence: Int?
    private var cachedFrame: RGBDFrame?

    /// Create a device bound to the capture app's stream port.
    public init(port: UInt16 = PhoneDevice.streamPort) {
        reader = PhoneStreamReader(port: port)
    }

    /// Begin connecting and streaming. Safe to call once; the reader retries on its
    /// own until the phone is attached and the app is serving.
    public func start() { reader.start() }

    /// Stop streaming and close the connection. Safe to call when not started.
    public func stop() { reader.stop() }

    /// Whether sensor frames are currently arriving from the phone.
    public var isStreaming: Bool { reader.isConnected }

    /// The latest body skeleton, or `nil` before one arrives. A fresh value each
    /// time the phone sends a pose — read it within the current `draw()`.
    public var latestBody: PhoneBody? { reader.latestPose.map(PhoneBody.init) }

    /// The latest face — mesh, blendshapes, and head pose — or `nil` before one
    /// arrives. Populated when the capture app is in **Face** mode (front camera);
    /// body and face are mutually exclusive, so only one of `latestBody`/`latestFace`
    /// updates at a time.
    public var latestFace: PhoneFace? { reader.latestFace.map(PhoneFace.init) }

    /// The latest CoreMotion sample, or `nil` before one arrives — the cheap
    /// transport smoke-test (it moves the moment the wire is alive, before ARKit
    /// has found a body).
    public var latestMotion: PhoneMotion? { reader.latestMotion.map(PhoneMotion.init) }

    // MARK: - World mode (rear LiDAR RGBD)

    /// The latest world-facing RGBD frame, or `nil` before one arrives. Populated
    /// when the capture app is in **World** mode (rear LiDAR); body/face modes don't
    /// produce depth. A fresh frame each time the phone sends one — read it within
    /// the current `draw()`.
    public var latestDepthFrame: RGBDFrame? {
        guard let box = reader.latestDepth else { return nil }
        if cachedSequence == box.sequence, let cachedFrame { return cachedFrame }
        let frame = RGBDFrame(color: Image(cgImage: box.color), depth: box.depth,
                              confidence: box.confidence, depthWidth: box.depthWidth,
                              depthHeight: box.depthHeight, intrinsics: box.intrinsics)
        cachedSequence = box.sequence
        cachedFrame = frame
        return frame
    }

    /// Unproject the latest depth frame into a `PointCloud` (see `RGBDFrame.pointCloud`
    /// for the parameters). `nil` until the first World-mode frame arrives. The rear
    /// LiDAR reaches across a room, so the defaults open the depth range up.
    public func pointCloud(minimumConfidence: DepthConfidence = .medium,
                           depthRange: ClosedRange<Double>? = nil,
                           step: Int = 1,
                           pointSize: Double = 0.009) -> PointCloud? {
        latestDepthFrame?.pointCloud(minimumConfidence: minimumConfidence, depthRange: depthRange,
                                     step: step, pointSize: pointSize)
    }

    /// The 6DoF camera pose of the latest World-mode frame (ARKit's camera→world
    /// `simd_float4x4`), or `nil` before one arrives. ARKit's world is fixed and
    /// gravity-aligned, so transforming a frame's camera-space cloud by this pose
    /// places it where it really is in the room — feed both to a `WorldCloud` to
    /// fuse a sweep of frames into one scene (see `PointCloud.transformed(by:)`).
    public var latestPose: simd_float4x4? { reader.latestPose3D }

    /// An identifier that changes whenever a new World-mode depth frame arrives —
    /// the frame's stream sequence number. `draw()` runs faster than depth frames
    /// stream in, so a fusion sketch compares this against the last value it fused
    /// to add each frame exactly once. `nil` before the first frame.
    public var latestDepthFrameID: Int? { reader.latestDepth?.sequence }

    // MARK: - FrameSource / VideoFeed (the World-mode color feed)

    /// The analysis tap (`FrameSource`): the live color frame, delivered on the
    /// reader thread so a vision tracker can run over the phone's World-mode camera.
    public var frameTap: FrameTap? {
        didSet { reader.setTap(frameTap) }
    }

    /// The latest World-mode color frame as a drawable `Image` (`VideoFeed`).
    public var frame: Image? { latestDepthFrame?.color }

    /// The pixel size of the latest World-mode color frame (`VideoFeed`).
    public var frameSize: Vector2? {
        guard let box = reader.latestDepth else { return nil }
        return Vector2(Double(box.color.width), Double(box.color.height))
    }

    /// The notice to show before frames arrive — reflects the live connection state
    /// (no device, refused, reconnecting).
    public var waitingMessage: String { reader.statusMessage ?? "Connecting to the phone…" }
}

/// Owns the usbmuxd connection and the background read loop, decoding framed
/// messages off the main thread and handing the latest of each kind across a lock —
/// a serial-producer / locked-reader model.
/// `@unchecked Sendable`: its mutable state lives behind the lock, and the read
/// thread touches nothing main-actor-isolated (the executor-assertion lesson).
final class PhoneStreamReader: @unchecked Sendable {

    private struct State {
        var latestPose: PhonePoseSample?
        var latestFace: PhoneFaceSample?
        var latestMotion: PhoneMotionSample?
        var latestDepth: PhoneDepthFrameBox?
        var depthSequence = 0
        var tap: FrameTap?
        var connected = false
        var message: String? = "Connecting to the phone…"
        var running = false
        var fd: Int32 = -1
    }

    private let port: UInt16
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    init(port: UInt16) { self.port = port }

    // MARK: Public surface (read from the main actor)

    var latestPose: PhonePoseSample? { lock.withLock { $0.latestPose } }
    var latestFace: PhoneFaceSample? { lock.withLock { $0.latestFace } }
    var latestMotion: PhoneMotionSample? { lock.withLock { $0.latestMotion } }
    var latestDepth: PhoneDepthFrameBox? { lock.withLock { $0.latestDepth } }
    var latestPose3D: simd_float4x4? { lock.withLock { $0.latestDepth?.transform } }
    var isConnected: Bool { lock.withLock { $0.connected } }
    var statusMessage: String? { lock.withLock { $0.message } }

    func setTap(_ tap: FrameTap?) { lock.withLock { $0.tap = tap } }

    func start() {
        let alreadyRunning = lock.withLock { state -> Bool in
            if state.running { return true }
            state.running = true
            return false
        }
        guard !alreadyRunning else { return }
        Thread.detachNewThread { [weak self] in self?.run() }
    }

    func stop() {
        let fd = lock.withLock { state -> Int32 in
            state.running = false
            let fd = state.fd
            state.fd = -1
            state.connected = false
            return fd
        }
        if fd >= 0 { close(fd) }   // breaks a blocking read
    }

    // MARK: Background loop

    private var isRunning: Bool { lock.withLock { $0.running } }

    private func run() {
        while isRunning {
            let fd: Int32
            do {
                fd = try USBMux.connect(toPort: port)
            } catch {
                lock.withLock { $0.connected = false; $0.message = Self.message(for: error) }
                Thread.sleep(forTimeInterval: 1.0)
                continue
            }
            // A read timeout so the loop re-checks `running` even when frames stall.
            var tv = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            lock.withLock { $0.fd = fd; $0.connected = true; $0.message = nil }

            readLoop: while isRunning {
                switch readMessage(fd) {
                case .message(.depth(let sample)):
                    // Decode the RGBD frame (JPEG + intrinsics) on this thread, off
                    // the main actor (the executor-assertion lesson), then fire the
                    // FrameSource tap with the color image.
                    let seq = lock.withLock { state -> Int in state.depthSequence += 1; return state.depthSequence }
                    if let box = decodePhoneDepth(sample, sequence: seq) {
                        let tap = lock.withLock { state -> FrameTap? in
                            state.latestDepth = box
                            return state.tap
                        }
                        tap?(box.color)
                    }
                case .message(let message):
                    lock.withLock { state in
                        switch message {
                        case .motion(let m): state.latestMotion = m
                        case .pose(let p): state.latestPose = p
                        case .face(let f): state.latestFace = f
                        case .depth: break   // handled above
                        }
                    }
                case .skip:
                    continue            // a bad frame, but the stream is still in sync
                case .desync:
                    break readLoop      // framing lost — drop and reconnect
                }
            }

            lock.withLock {
                if $0.fd == fd { $0.fd = -1 }
                $0.connected = false
                if $0.running { $0.message = "Reconnecting to the phone…" }
            }
            close(fd)
            if isRunning { Thread.sleep(forTimeInterval: 0.5) }
        }
    }

    private enum ReadOutcome { case message(PhoneMessage), skip, desync }

    private func readMessage(_ fd: Int32) -> ReadOutcome {
        let headerData = USBMux.readFully(fd, PhoneWire.headerByteCount)
        guard headerData.count == PhoneWire.headerByteCount,
              let header = PhoneHeader.parse(headerData) else { return .desync }

        let payload = header.payloadLength > 0
            ? USBMux.readFully(fd, header.payloadLength) : Data()
        guard payload.count == header.payloadLength else { return .desync }

        guard let message = PhoneWire.decode(header: header, payload: payload) else { return .skip }
        return .message(message)
    }

    private static func message(for error: Error) -> String {
        guard let muxError = error as? USBMux.USBMuxError else { return "\(error)" }
        switch muxError {
        case .noDevice:
            return "Connect an iPhone over USB."
        case .socketUnavailable:
            return "Can't reach the USB service (usbmuxd)."
        case .connectFailed(3):
            return "Launch the Ollin capture app on the iPhone."
        case .connectFailed, .handshakeFailed:
            return "Waiting for the Ollin capture stream…"
        }
    }
}
