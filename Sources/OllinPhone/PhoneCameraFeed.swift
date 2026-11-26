import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import os
import OllinUSBMux
#if canImport(Darwin)
import Darwin
#endif

/// Reads the camera's picture off the cable (`PhoneWire.cameraPort`) and keeps
/// the newest frame decoded, upright, with where the camera stood for it.
///
/// The connection is the asking. The phone compresses its camera only while a
/// client is on this port, so the feed dials only while a sketch reads the
/// picture: a read calls `keepWanted()`, and a feed not asked for two seconds
/// closes and stops dialing. A sketch that reads only where the camera stood
/// never opens it, and the phone never compresses a frame for it.
///
/// Each message carries a compressed picture and the camera record of that same
/// frame, so the two cannot part: what `latest` holds is one frame's picture
/// with that frame's own pose and lens, which is what lets a thing drawn in the
/// room sit on the picture while the phone moves.
///
/// It owns a thread and one socket. Pictures are decoded on the media engine as
/// they arrive (every one, since each is built on the one before) and turned
/// upright on the decoder's thread, so reading the newest costs the frame that
/// draws it nothing but a texture wrapped around the buffer.
///
/// Not main-actor bound: the decoder's output handler is formed inside these
/// nonisolated methods, so it carries no executor assertion into the thread
/// that calls it.
final class PhoneCameraFeed: @unchecked Sendable {

    /// One decoded frame of the camera.
    struct Frame: @unchecked Sendable {
        /// Where the camera stood and what its lens was for this picture.
        let sample: PhoneCameraSample
        /// Counts the frames this feed has decoded, so a reader can tell one
        /// from the next.
        let number: Int
        /// The picture, upright for how the phone was held, as BGRA.
        let buffer: CVPixelBuffer
    }

    /// How long a feed stays connected after the last read that wanted it.
    static let wantedFor: TimeInterval = 2

    /// How long the feed's thread waits to be wanted again before it ends. A
    /// later read starts another, so a sketch that has gone leaves no thread.
    static let idlesFor: TimeInterval = 10

    private struct State {
        /// The thread that is reading, by number, or `nil` when none is. A
        /// thread ends when the number is no longer its own.
        var thread: Int?
        var threadsStarted = 0
        var connected = false
        var fd: Int32 = -1
        var wantedUntil: TimeInterval = 0
        var latest: Frame?
        var decodedCount = 0
        var lastError: String?
        /// Set by the decoder's thread when a picture would not decode, so the
        /// read thread waits for a keyframe.
        var decoderFailed = false
        /// Bumped on every connection, so a picture decoded for one that has
        /// gone is not taken for the newest.
        var connection = 0
    }

    private let port: UInt16
    private let wantedFor: TimeInterval
    private let connect: @Sendable (UInt16) throws -> Int32
    private let lock = OSAllocatedUnfairLock(uncheckedState: State())
    private let wake = DispatchSemaphore(value: 0)
    private let turner = Turner()

    /// Called on the decoder's thread with the capture time of each picture as
    /// it becomes the newest, and with `nil` when the feed lets go of its
    /// connection. Set once, before the first read.
    private let onPictureTime: (@Sendable (Double?) -> Void)?

    /// `connect` opens the socket, the usbmux tunnel unless a test hands it one
    /// end of a socket pair.
    init(port: UInt16 = PhoneWire.cameraPort, wantedFor: TimeInterval = PhoneCameraFeed.wantedFor,
         onPictureTime: (@Sendable (Double?) -> Void)? = nil,
         connect: @escaping @Sendable (UInt16) throws -> Int32 = { try USBMux.connect(toPort: $0) }) {
        self.port = port
        self.wantedFor = wantedFor
        self.connect = connect
        self.onPictureTime = onPictureTime
    }

    deinit { stop() }

    // MARK: Asked from the frame

    /// Say that a sketch is reading the picture and wants the connection. The
    /// first call starts the feed's thread, and so does the first after `stop()`.
    func keepWanted() {
        let now = ProcessInfo.processInfo.systemUptime
        let (starts, wasIdle) = lock.withLockUnchecked { state -> (Int?, Bool) in
            let wasIdle = state.wantedUntil < now
            state.wantedUntil = now + wantedFor
            guard state.thread == nil else { return (nil, wasIdle) }
            state.threadsStarted += 1
            state.thread = state.threadsStarted
            return (state.threadsStarted, wasIdle)
        }
        if let starts {
            Thread.detachNewThread { [self] in self.run(thread: starts) }
        } else if wasIdle {
            wake.signal()
        }
    }

    /// The newest decoded frame on the connection that is open now, or `nil`
    /// when there is none: no connection, or no picture yet.
    var latest: Frame? { lock.withLockUnchecked { $0.connected ? $0.latest : nil } }

    /// Whether a phone is on the other end of the camera connection.
    var isConnected: Bool { lock.withLockUnchecked { $0.connected } }

    /// How many pictures have been decoded since the feed began.
    var decodedCount: Int { lock.withLockUnchecked { $0.decodedCount } }

    /// How many pictures were refused because one before them was lost.
    var refusedCount: Int { refused.withLock { $0 } }
    private let refused = OSAllocatedUnfairLock(initialState: 0)

    /// The last thing that went wrong, as a sentence, or `nil` once a picture
    /// has decoded again.
    var lastError: String? { lock.withLockUnchecked { $0.lastError } }

    /// Close the connection and end the thread. The next `keepWanted()` starts
    /// another.
    func stop() {
        let fd = lock.withLockUnchecked { state -> Int32 in
            state.thread = nil
            state.wantedUntil = 0
            state.connected = false
            state.latest = nil
            return state.fd
        }
        // Wakes a blocked read; the thread closes the descriptor it owns.
        if fd >= 0 { shutdown(fd, SHUT_RDWR) }
        wake.signal()
    }

    // MARK: The thread

    private func isRunning(_ thread: Int) -> Bool { lock.withLockUnchecked { $0.thread == thread } }

    private var isWanted: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return lock.withLockUnchecked { $0.wantedUntil >= now }
    }

    private func run(thread: Int) {
        // The decoder belongs to this thread alone, so a thread started after a
        // stop never meets the one that is still on its way out.
        let decoder = Decoder(feed: self)
        while isRunning(thread) {
            guard isWanted else {
                let ended = lock.withLockUnchecked { state -> Bool in
                    let now = ProcessInfo.processInfo.systemUptime
                    guard state.thread == thread, state.wantedUntil + Self.idlesFor < now else { return false }
                    state.thread = nil
                    return true
                }
                if ended { return }
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
            // A read timeout, so the loop looks again at whether it is still
            // wanted while the phone has no picture to send (a mode with no
            // camera sends none).
            var timeout = timeval(tv_sec: 0, tv_usec: 250_000)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            let connection = lock.withLockUnchecked { state -> Int? in
                guard state.thread == thread else { return nil }
                state.fd = fd
                state.connected = true
                state.latest = nil
                state.decoderFailed = false
                state.connection += 1
                return state.connection
            }
            if let connection { carry(fd, connection: connection, thread: thread, into: decoder) }

            // What the decoder still holds comes back before the connection's
            // frames are let go, so none of them lands after this.
            decoder.close()
            lock.withLockUnchecked { state in
                // A thread that was stopped leaves what a newer one has set.
                guard state.fd == fd else { return }
                state.connected = false
                state.latest = nil
                state.fd = -1
                state.connection += 1
            }
            onPictureTime?(nil)
            close(fd)
            if isRunning(thread) { _ = wake.wait(timeout: .now() + 0.5) }
        }
    }

    private enum Read { case data(Data), idle, closed }

    /// Read exactly `count` bytes. `.idle` when the wait ran out before the
    /// first byte and `mayIdle` allows it, which is a phone with nothing to
    /// send; `.closed` when the connection ended or stalled mid-message.
    private func read(_ fd: Int32, _ count: Int, mayIdle: Bool, thread: Int) -> Read {
        var out = Data()
        out.reserveCapacity(count)
        var buffer = [UInt8](repeating: 0, count: min(max(count, 1), 1 << 16))
        var stalls = 0
        while out.count < count {
            let want = min(buffer.count, count - out.count)
            let got = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, want) }
            if got > 0 {
                out.append(contentsOf: buffer[0..<got])
                stalls = 0
                continue
            }
            if got == 0 { return .closed }
            guard errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR else { return .closed }
            if out.isEmpty, mayIdle { return .idle }
            // Mid-message: the rest is on its way. Two seconds of nothing is a
            // connection that has gone without saying so.
            stalls += 1
            guard stalls < 8, isRunning(thread) else { return .closed }
        }
        return .data(out)
    }

    /// Read pictures until the connection goes, the sketch stops wanting it, or
    /// the feed stops.
    private func carry(_ fd: Int32, connection: Int, thread: Int, into decoder: Decoder) {
        decoder.begin(connection: connection)
        while isRunning(thread), isWanted {
            let headerData: Data
            switch read(fd, PhoneWire.headerByteCount, mayIdle: true, thread: thread) {
            case .idle: continue
            case .closed: return
            case .data(let data): headerData = data
            }
            // A header that does not parse is a stream out of step: drop the
            // connection instead of hunting for a magic word further along.
            guard let header = PhoneHeader.parse(headerData) else { return }
            var payload = Data()
            if header.payloadLength > 0 {
                guard case .data(let data) = read(fd, header.payloadLength, mayIdle: false, thread: thread)
                else { return }
                payload = data
            }
            // A frame that is framed correctly but will not decode is skipped;
            // the stream is still in step.
            guard case .cameraPicture(let message)? = PhoneWire.decode(header: header, payload: payload)
            else { continue }
            decoder.take(message)
        }
    }

    // MARK: Decoding

    /// One read thread's decoder and what it is following. Touched only by the
    /// thread that made it; what it decodes crosses to the feed behind the
    /// feed's lock.
    private final class Decoder {
        private let feed: PhoneCameraFeed
        private var format: PhonePictureFormat?
        private var session: VTDecompressionSession?
        private var sequence = PhoneCameraSequence()
        private var connection = 0
        private var refusedBefore = 0

        init(feed: PhoneCameraFeed) { self.feed = feed }

        /// Start on a new connection, which begins with a keyframe.
        func begin(connection: Int) {
            self.connection = connection
            sequence.reset()
        }

        /// Hand one picture to the decoder, if it can be decoded: a keyframe always,
        /// anything else only when it follows the last one decoded.
        func take(_ message: PhoneCameraPicture) {
            let lock = feed.lock
            let failed = lock.withLockUnchecked { state -> Bool in
                defer { state.decoderFailed = false }
                return state.decoderFailed
            }
            if failed { sequence.reset() }
            guard sequence.accepts(sequence: message.sequence, isKeyframe: message.picture.isKeyframe) else {
                let newly = sequence.refused - refusedBefore
                refusedBefore = sequence.refused
                feed.refused.withLock { $0 += newly }
                return
            }
            guard let sample = message.picture.sampleBuffer(reusing: &format, colors: message.colors),
                  let format, let session = decoder(for: format) else {
                sequence.reset()
                lock.withLockUnchecked { $0.lastError = "The camera's picture could not be decoded." }
                return
            }

            let camera = message.camera
            let connection = connection
            let turner = feed.turner
            let onPictureTime = feed.onPictureTime
            let status = VTDecompressionSessionDecodeFrame(
                session, sampleBuffer: sample,
                flags: [._EnableAsynchronousDecompression, ._1xRealTimePlayback], infoFlagsOut: nil
            ) { status, _, image, _, _ in
                guard status == noErr, let image,
                      let upright = turner.upright(image, quarterTurnsCW: Int(camera.quarterTurnsCW)) else {
                    lock.withLockUnchecked { state in
                        state.decoderFailed = true
                        state.lastError = "The camera's picture could not be decoded."
                    }
                    return
                }
                let isNewest = lock.withLockUnchecked { state -> Bool in
                    guard state.connected, state.connection == connection else { return false }
                    state.decodedCount += 1
                    state.latest = Frame(sample: camera, number: state.decodedCount, buffer: upright)
                    state.lastError = nil
                    return true
                }
                if isNewest { onPictureTime?(camera.timestamp) }
            }
            if status != noErr {
                sequence.reset()
                lock.withLockUnchecked { $0.lastError = "The camera's picture could not be decoded." }
            }
        }

        /// The decoder for this format, made on first use and made again when the
        /// picture's size or colors change.
        private func decoder(for format: PhonePictureFormat) -> VTDecompressionSession? {
            if let session, VTDecompressionSessionCanAcceptFormatDescription(session, formatDescription: format.description) {
                return session
            }
            close()
            // BGRA on an IOSurface, which is what a Metal texture wraps with no copy.
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey: true,
                kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
            ]
            var made: VTDecompressionSession?
            guard VTDecompressionSessionCreate(
                    allocator: kCFAllocatorDefault, formatDescription: format.description,
                    decoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary,
                    outputCallback: nil, decompressionSessionOut: &made) == noErr, let made
            else { return nil }
            VTSessionSetProperty(made, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
            session = made
            return made
        }

        /// Wait for what the decoder still holds, and let it go.
        func close() {
            guard let session else { return }
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
            self.session = nil
            format = nil
        }

        deinit { close() }
    }
}

extension PhoneCameraFeed {

    /// Turns decoded pictures upright, on the decoder's thread.
    ///
    /// One turn at a time behind its own lock, since a rotation session is not
    /// to be shared between two calls at once. Each turned picture is a buffer
    /// from a pool that nobody else holds: a frame still on its way to the
    /// screen may be reading the last one, so a buffer is never written twice
    /// while anything keeps it.
    final class Turner: @unchecked Sendable {
        private struct Tools {
            var turns = 0
            var session: PictureTurner?
            var pool: CVPixelBufferPool?
            var poolSize = (width: 0, height: 0)
        }
        private let tools = OSAllocatedUnfairLock(uncheckedState: Tools())

        func upright(_ source: CVPixelBuffer, quarterTurnsCW: Int) -> CVPixelBuffer? {
            let turns = ((quarterTurnsCW % 4) + 4) % 4
            guard turns != 0 else { return source }
            return tools.withLockUnchecked { tools -> CVPixelBuffer? in
                if tools.session == nil || tools.turns != turns {
                    tools.session = PictureTurner(quarterTurnsCW: turns)
                    tools.turns = turns
                }
                let sideways = turns % 2 == 1
                let w = CVPixelBufferGetWidth(source), h = CVPixelBufferGetHeight(source)
                let size = (width: sideways ? h : w, height: sideways ? w : h)
                if tools.pool == nil || tools.poolSize != size {
                    let attributes: [CFString: Any] = [
                        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                        kCVPixelBufferWidthKey: size.width,
                        kCVPixelBufferHeightKey: size.height,
                        kCVPixelBufferMetalCompatibilityKey: true,
                        kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
                    ]
                    var pool: CVPixelBufferPool?
                    CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
                    tools.pool = pool
                    tools.poolSize = size
                }
                guard let turner = tools.session, let pool = tools.pool else { return nil }
                var destination: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess,
                      let destination,
                      VTPixelRotationSessionRotateImage(turner.session, source, destination) == noErr
                else { return nil }
                return destination
            }
        }
    }
}
