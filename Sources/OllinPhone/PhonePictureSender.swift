import Foundation
import os
import OllinUSBMux
#if canImport(Darwin)
import Darwin
#endif

/// Carries pictures down the cable on their own connection (`PhoneWire.picturePort`).
///
/// It owns a thread and one socket, and it holds at most one picture waiting to
/// go. The screen asks `isReady` before it compresses a frame, so a slow cable
/// makes the Mac skip frames before they are compressed rather than after: a
/// picture that is not a keyframe is built on the one before it, and dropping one
/// that was already made would spoil every picture after it until the next
/// keyframe.
///
/// The connection is held only while it is wanted. A screen calls `keepWanted()`
/// every frame it draws, and a sender not asked for two seconds closes and stops
/// dialing. That is what lets a live reload hand the phone over: the old sketch
/// stops drawing, its sender lets go, and the phone, which keeps only its newest
/// picture connection, is left with the new sketch's.
final class PhonePictureSender: @unchecked Sendable {

    /// How long a sender stays connected after the last frame that wanted it.
    static let wantedFor: TimeInterval = 2

    private struct State: Sendable {
        var running = true
        var connected = false
        var fd: Int32 = -1
        var queued: Data?
        var sentOnConnection = 0
        var needsKeyframe = true
        var wantedUntil: TimeInterval = 0
        var dropped = 0
    }

    private let port: UInt16
    private let connect: @Sendable (UInt16) throws -> Int32
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let wake = DispatchSemaphore(value: 0)

    /// `dials: false` makes a sender that never opens a connection, for a test
    /// that drives the screen with no phone and must not find one on the desk.
    /// `connect` opens the socket, the usbmux tunnel unless a test hands it one
    /// end of a socket pair.
    init(port: UInt16 = PhoneWire.picturePort, dials: Bool = true,
         connect: @escaping @Sendable (UInt16) throws -> Int32 = { try USBMux.connect(toPort: $0) }) {
        self.port = port
        self.connect = connect
        guard dials else {
            lock.withLock { $0.running = false }
            return
        }
        Thread.detachNewThread { [self] in self.run() }
    }

    /// Whether one framed picture fits a single frame of the wire, which the
    /// phone's reader refuses past `PhoneWire.maxPayloadBytes`.
    static func fits(_ frame: Data) -> Bool {
        frame.count - PhoneWire.headerByteCount <= PhoneWire.maxPayloadBytes
    }

    deinit { stop() }

    // MARK: Asked from the frame

    /// Whether a phone is on the other end of the picture connection.
    var isConnected: Bool { lock.withLock { $0.connected } }

    /// Whether a picture compressed now would go straight out: connected, and
    /// nothing already waiting.
    var isReady: Bool { lock.withLock { $0.connected && $0.queued == nil } }

    /// Whether a picture has reached this connection since it opened.
    var hasSent: Bool { lock.withLock { $0.connected && $0.sentOnConnection > 0 } }

    /// How many pictures were too big for the wire and were not sent.
    var droppedCount: Int { lock.withLock { $0.dropped } }

    /// Say that a sketch is still drawing and wants the connection.
    func keepWanted() {
        let now = ProcessInfo.processInfo.systemUptime
        let wasIdle = lock.withLock { state -> Bool in
            defer { state.wantedUntil = now + Self.wantedFor }
            return state.wantedUntil < now
        }
        if wasIdle { wake.signal() }
    }

    /// Ask for the next picture to stand alone.
    func requestKeyframe() { lock.withLock { $0.needsKeyframe = true } }

    /// Whether the next picture must stand alone, clearing the request.
    func takeKeyframeRequest() -> Bool {
        lock.withLock { state in
            defer { state.needsKeyframe = false }
            return state.needsKeyframe
        }
    }

    /// Queue one picture to go out. A picture too big for one frame of the wire is
    /// dropped, and the next one is asked to stand alone, since the phone can no
    /// longer decode what was built on it.
    func send(_ picture: PhonePicture) {
        let frame = PhoneWire.encode(.picture(picture))
        lock.withLock { state in
            guard state.connected else { return }
            guard Self.fits(frame) else {
                state.dropped += 1
                state.needsKeyframe = true
                return
            }
            state.queued = frame
        }
        wake.signal()
    }

    /// Close the connection and end the thread.
    func stop() {
        let fd = lock.withLock { state -> Int32 in
            state.running = false
            return state.fd
        }
        // Wakes a blocked write; the thread closes the descriptor it owns.
        if fd >= 0 { shutdown(fd, SHUT_RDWR) }
        wake.signal()
    }

    // MARK: The thread

    private var isRunning: Bool { lock.withLock { $0.running } }

    private var isWanted: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return lock.withLock { $0.wantedUntil >= now }
    }

    private func run() {
        while isRunning {
            guard isWanted else {
                _ = wake.wait(timeout: .now() + 0.5)
                continue
            }
            let fd: Int32
            do {
                fd = try connect(port)
            } catch {
                _ = wake.wait(timeout: .now() + 1)
                continue
            }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let proceed = lock.withLock { state -> Bool in
                guard state.running else { return false }
                state.fd = fd
                state.connected = true
                state.sentOnConnection = 0
                state.queued = nil
                // A phone that has just connected has no picture to build on.
                state.needsKeyframe = true
                return true
            }
            if proceed { carry(fd) }

            lock.withLock { state in
                state.connected = false
                state.queued = nil
                state.fd = -1
            }
            close(fd)
            if isRunning { _ = wake.wait(timeout: .now() + 0.5) }
        }
    }

    /// Write pictures as they arrive until the connection goes, the sketch stops
    /// wanting it, or the sender stops.
    private func carry(_ fd: Int32) {
        while isRunning, isWanted {
            let frame = lock.withLock { state -> Data? in
                defer { state.queued = nil }
                return state.queued
            }
            if let frame {
                guard USBMux.writeFully(fd, frame) else { return }
                lock.withLock { $0.sentOnConnection += 1 }
                continue
            }
            _ = wake.wait(timeout: .now() + 0.25)
            // The phone sends nothing on this connection, so a read that finds the
            // end of the stream is the phone closing it (the app left Sketch mode's
            // newest connection to another sketch, or the cable came out).
            var byte: UInt8 = 0
            let peeked = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
            if peeked == 0 { return }
            if peeked < 0, errno != EAGAIN, errno != EWOULDBLOCK { return }
        }
    }
}
