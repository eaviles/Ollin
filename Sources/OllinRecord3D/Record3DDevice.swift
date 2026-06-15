import Foundation
import CoreGraphics
import os
import Ollin
#if canImport(Darwin)
import Darwin
#endif

/// A live RGBD feed from an iPhone running the **Record3D** app's USB streaming,
/// tethered over the cable — the live sibling of `Record3DRecording`. Each frame's
/// color image and metric depth map arrive full-quality (LZFSE float32 depth, true
/// camera intrinsics, ARKit pose), unproject into a `PointCloud`, and draw through
/// the shipped 3D path. A Mac has no depth camera; this borrows the phone's.
///
/// ```swift
/// let device = Record3DDevice()
/// override func setup() { device.start() }
/// override func draw() {
///     guard let cloud = device.pointCloud() else {
///         return drawStatus(device.waitingMessage, style: .info)
///     }
///     camera(.orbiting(radius: 2.5, azimuth: time * 0.3))
///     drawPointCloud(cloud)
/// }
/// ```
///
/// Enable **USB streaming** in Record3D (Settings) and keep it on the live screen;
/// the device keeps retrying, so plugging in or starting the stream mid-run just
/// works. The transport is the standard `usbmuxd` tunnel (port 1337); the frame
/// format is read clean-room from the wire (the `record3d` library is LGPL-2.1 and
/// never copied — Record3D is credited as the capture app).
///
/// This first slice builds clouds in **camera space** (the per-frame ARKit pose is
/// published as `latestPose` but not yet applied); world placement and multi-frame
/// fusion are a later slice.
@MainActor
public final class Record3DDevice: FrameSource, VideoFeed {

    /// The TCP port Record3D's USB stream listens on (tunnelled via usbmuxd).
    public nonisolated static let streamPort: UInt16 = 1337

    private let reader: Record3DStreamReader

    // Build the drawable `RGBDFrame` lazily and cache it by the box's sequence, so
    // repeated reads in one `draw()` (frame, frameSize, pointCloud) reuse it.
    private var cachedSequence: Int?
    private var cachedFrame: RGBDFrame?

    /// Create a device bound to the Record3D USB stream port.
    public init(port: UInt16 = Record3DDevice.streamPort) {
        reader = Record3DStreamReader(port: port)
    }

    /// The analysis tap (`FrameSource`): the live color frame, delivered on the
    /// reader thread so a vision tracker can run over the phone's camera.
    public var frameTap: FrameTap? {
        didSet { reader.setTap(frameTap) }
    }

    /// Begin connecting and streaming. Safe to call once; the reader retries on its
    /// own until the phone is attached and serving.
    public func start() { reader.start() }

    /// Stop streaming and close the connection. Safe to call when not started.
    public func stop() { reader.stop() }

    /// Whether frames are currently arriving from the phone.
    public var isStreaming: Bool { reader.isConnected }

    /// The latest decoded RGBD frame, or `nil` before the first one arrives. A
    /// fresh frame each time the phone sends one — read it within the current `draw()`.
    public var latestFrame: RGBDFrame? {
        guard let box = reader.latest else { return nil }
        if cachedSequence == box.sequence, let cachedFrame { return cachedFrame }
        let frame = RGBDFrame(color: Image(cgImage: box.color), depth: box.depth,
                              confidence: box.confidence, depthWidth: box.depthWidth,
                              depthHeight: box.depthHeight, intrinsics: box.intrinsics)
        cachedSequence = box.sequence
        cachedFrame = frame
        return frame
    }

    /// The camera pose of the most recent frame (ARKit world space). Published for
    /// the world-placement work to come; this slice draws in camera space.
    public var latestPose: Record3DPose? { reader.latestPose }

    /// Unproject the latest frame into a `PointCloud` (see `RGBDFrame.pointCloud`
    /// for the parameters). `nil` until the first frame arrives.
    public func pointCloud(minimumConfidence: DepthConfidence = .medium,
                           depthRange: ClosedRange<Double>? = nil,
                           step: Int = 1,
                           pointSize: Double = 0.006) -> PointCloud? {
        latestFrame?.pointCloud(minimumConfidence: minimumConfidence, depthRange: depthRange,
                                step: step, pointSize: pointSize)
    }

    // MARK: - VideoFeed

    /// The latest color frame as a drawable `Image` (`VideoFeed`).
    public var frame: Image? { latestFrame?.color }

    /// The pixel size of the latest color frame (`VideoFeed`).
    public var frameSize: Vector2? {
        guard let box = reader.latest else { return nil }
        return Vector2(Double(box.color.width), Double(box.color.height))
    }

    /// The notice to show before frames arrive (`VideoFeed`) — reflects the live
    /// connection state (no device, refused, reconnecting).
    public var waitingMessage: String { reader.statusMessage ?? "Connecting to the phone…" }
}

/// Owns the usbmuxd connection and the background read loop, decoding frames off
/// the main thread and handing the latest one across a lock — the serial-producer /
/// locked-reader model the audio analyzer and `Camera` use. `@unchecked Sendable`:
/// its mutable state lives behind the lock, and the read thread touches nothing
/// main-actor-isolated (the executor-assertion lesson).
final class Record3DStreamReader: @unchecked Sendable {

    private struct State {
        var latest: Record3DFrameBox?
        var connected = false
        var message: String? = "Connecting to the phone…"
        var running = false
        var fd: Int32 = -1
        var sequence = 0
        var tap: FrameTap?
    }

    private let port: UInt16
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    init(port: UInt16) { self.port = port }

    // MARK: Public surface (read from the main actor)

    var latest: Record3DFrameBox? { lock.withLock { $0.latest } }
    var latestPose: Record3DPose? { lock.withLock { $0.latest?.pose } }
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
                switch readFrame(fd) {
                case .frame(let box):
                    let tap = lock.withLock { state -> FrameTap? in
                        state.latest = box
                        return state.tap
                    }
                    tap?(box.color)
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

    private enum ReadOutcome { case frame(Record3DFrameBox), skip, desync }

    private func readFrame(_ fd: Int32) -> ReadOutcome {
        let headerData = USBMux.readFully(fd, Record3DFrameHeader.byteCount)
        guard headerData.count == Record3DFrameHeader.byteCount,
              let header = Record3DFrameHeader.parse(headerData) else { return .desync }

        let total = header.rgbSize + header.depthSize + header.confidenceSize + header.miscSize
        let body = USBMux.readFully(fd, total)
        guard body.count == total else { return .desync }

        let sequence = lock.withLock { state -> Int in state.sequence += 1; return state.sequence }
        guard let box = decodeRecord3DFrame(header: header, body: body, sequence: sequence) else {
            return .skip
        }
        return .frame(box)
    }

    private static func message(for error: Error) -> String {
        guard let muxError = error as? USBMux.USBMuxError else { return "\(error)" }
        switch muxError {
        case .noDevice:
            return "Connect an iPhone over USB."
        case .socketUnavailable:
            return "Can't reach the USB service (usbmuxd)."
        case .connectFailed(3):
            return "Start USB streaming in the Record3D app."
        case .connectFailed, .handshakeFailed:
            return "Waiting for the Record3D USB stream…"
        }
    }
}
