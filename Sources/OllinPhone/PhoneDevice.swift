import Foundation
import os
import Ollin
import OllinUSBMux
#if canImport(Darwin)
import Darwin
#endif

/// A live sensor stream from a tethered iPhone running the **Ollin** capture app
/// (Apps/OllinPhoneApp) — the phone runs ARKit on its own Neural Engine and streams
/// typed results the Mac reads in `draw()`. Where `Record3DDevice` borrows the
/// Record3D app's RGBD feed, this is Ollin's own app, so the stream carries what
/// ARKit perceives: a 3D **body skeleton** and **device motion**, not just depth.
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
/// Launch the Ollin capture app on the iPhone and connect the cable; the device
/// keeps retrying, so plugging in or starting the app mid-run just works. The
/// transport is the standard `usbmuxd` tunnel (port 1338, distinct from Record3D's
/// 1337); the wire format is Ollin's own (`PhoneWire`).
@MainActor
public final class PhoneDevice {

    /// The TCP port the Ollin capture app listens on (tunnelled via usbmuxd) —
    /// defined once in `PhoneWire` so both ends agree.
    public nonisolated static let streamPort: UInt16 = PhoneWire.streamPort

    private let reader: PhoneStreamReader

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

    /// The latest CoreMotion sample, or `nil` before one arrives — the cheap
    /// transport smoke-test (it moves the moment the wire is alive, before ARKit
    /// has found a body).
    public var latestMotion: PhoneMotion? { reader.latestMotion.map(PhoneMotion.init) }

    /// The notice to show before frames arrive — reflects the live connection state
    /// (no device, refused, reconnecting).
    public var waitingMessage: String { reader.statusMessage ?? "Connecting to the phone…" }
}

/// Owns the usbmuxd connection and the background read loop, decoding framed
/// messages off the main thread and handing the latest of each kind across a lock —
/// the serial-producer / locked-reader model `Record3DStreamReader` uses.
/// `@unchecked Sendable`: its mutable state lives behind the lock, and the read
/// thread touches nothing main-actor-isolated (the executor-assertion lesson).
final class PhoneStreamReader: @unchecked Sendable {

    private struct State {
        var latestPose: PhonePoseSample?
        var latestMotion: PhoneMotionSample?
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
    var latestMotion: PhoneMotionSample? { lock.withLock { $0.latestMotion } }
    var isConnected: Bool { lock.withLock { $0.connected } }
    var statusMessage: String? { lock.withLock { $0.message } }

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
                case .message(let message):
                    lock.withLock { state in
                        switch message {
                        case .motion(let m): state.latestMotion = m
                        case .pose(let p): state.latestPose = p
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
