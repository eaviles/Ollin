// PhonePictureCompressor: pixel buffers in, pictures for the wire out, shared by
// the Ollin capture app (Apps/OllinPhoneApp) and the Mac satellite (OllinPhone).
//
// LOAD-BEARING: like PhoneWire.swift this file is compiled *verbatim into both
// ends*. The Mac compresses a sketch's frames for the phone's screen with it,
// and the phone compresses its camera for the Mac with it, so one set of
// compressor settings serves both directions and the Mac's tests run the code
// the phone runs. It imports the media frameworks and nothing of Ollin's.

import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import os

/// Compresses pixel buffers of one size into `PhonePicture`s: HEVC in real time
/// with no reordering, so a picture goes out the moment it is made instead of
/// waiting on a later one.
///
/// A picture that is not a keyframe is built on the one before it. So a caller
/// decides whether to compress a frame *before* handing it over, never after: a
/// picture already made cannot be thrown away without spoiling every picture
/// after it until the next keyframe.
///
/// The compression runs asynchronously, and each frame's handler is called on a
/// thread of the compressor's own. Not main-actor bound: the handler is formed
/// inside these nonisolated methods, so it carries no executor assertion into
/// the thread that calls it.
final class PhonePictureCompressor: @unchecked Sendable {

    /// How the compressed stream says its colors are to be read.
    enum ColorTags {
        /// Say nothing and let the buffers' own tags stand: a camera's frames,
        /// whose colors the caller reads off each buffer and sends beside it.
        case fromTheBuffers
        /// An sRGB canvas: BT.709 primaries and matrix, an sRGB transfer.
        case sRGBCanvas
    }

    let width: Int
    let height: Int
    let framesPerSecond: Double

    private let session: VTCompressionSession
    private let pending = OSAllocatedUnfairLock(initialState: 0)

    /// A compressor for buffers of `width` by `height`, or `nil` when this
    /// machine cannot make one at that size.
    ///
    /// `sourceAttributes` describes the buffers that will be handed over, when
    /// the caller wants a pool of them from the compressor (`pixelBufferPool`);
    /// a caller with buffers of its own (a camera's) passes `nil`.
    init?(width: Int, height: Int, framesPerSecond: Double, colors: ColorTags,
          sourceAttributes: [CFString: Any]? = nil) {
        guard width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
        self.framesPerSecond = max(1, framesPerSecond)

        // Low-latency rate control where the machine has it, the plain real-time
        // compressor where it does not.
        let specifications: [[CFString: Any]] = [
            [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true],
            [:],
        ]
        var found: VTCompressionSession?
        for specification in specifications {
            var made: VTCompressionSession?
            let status = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height),
                codecType: kCMVideoCodecType_HEVC,
                encoderSpecification: specification.isEmpty ? nil : specification as CFDictionary,
                imageBufferAttributes: sourceAttributes.map { $0 as CFDictionary },
                compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                compressionSessionOut: &made)
            if status == noErr, let made {
                found = made
                break
            }
        }
        guard let found else { return nil }
        session = found
        configure(colors: colors)
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    deinit { VTCompressionSessionInvalidate(session) }

    /// The pool the compressor keeps for buffers matching `sourceAttributes`,
    /// which it reads where they lie.
    var pixelBufferPool: CVPixelBufferPool? { VTCompressionSessionGetPixelBufferPool(session) }

    /// How many buffers have been handed over and not come back.
    var inFlight: Int { pending.withLock { $0 } }

    /// The bit rate a picture size runs at: about an eighth of a bit for every
    /// pixel of every frame, which keeps a hairline and a grain of noise intact
    /// on a screen held a hand away, and inside what the cable carries.
    static func bitRate(width: Int, height: Int, framesPerSecond: Double) -> Int {
        let rate = Double(width * height) * framesPerSecond * 0.125
        return Int(min(max(rate, 4_000_000), 40_000_000))
    }

    /// Hand one buffer to the compressor.
    ///
    /// `time` places it for the rate control, in seconds on any clock that only
    /// moves forward. `onPicture` is called once, on the compressor's thread,
    /// with the picture, or with `nil` when the compressor dropped the frame or
    /// its output cannot be carried. Returns `false` when the buffer was not
    /// taken, in which case `onPicture` is never called.
    @discardableResult
    func encode(_ pixelBuffer: CVPixelBuffer, at time: Double, forceKeyframe: Bool,
                onPicture: @escaping @Sendable (PhonePicture?) -> Void) -> Bool {
        pending.withLock { $0 += 1 }
        let stamp = CMTime(seconds: time, preferredTimescale: 1_000_000)
        let duration = CMTime(seconds: 1 / framesPerSecond, preferredTimescale: 1_000_000)
        let properties: CFDictionary? = forceKeyframe
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary : nil
        let pending = pending
        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer, presentationTimeStamp: stamp, duration: duration,
            frameProperties: properties, infoFlagsOut: nil
        ) { status, _, sampleBuffer in
            // Read the picture before the count drops, so a caller that waits for
            // nothing in flight has the picture in hand by then.
            let picture = status == noErr ? sampleBuffer.flatMap(PhonePicture.init(sampleBuffer:)) : nil
            onPicture(picture)
            pending.withLock { $0 = max(0, $0 - 1) }
        }
        if status != noErr {
            pending.withLock { $0 = max(0, $0 - 1) }
            return false
        }
        return true
    }

    /// Wait for every buffer handed over to come back. The tests use it, and a
    /// caller about to let a compressor go; the live path never waits on one.
    func finish() {
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    }

    private func configure(colors: ColorTags) {
        func set(_ key: CFString, _ value: Any) {
            VTSessionSetProperty(session, key: key, value: value as CFTypeRef)
        }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue!)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse!)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, framesPerSecond as NSNumber)
        // A keyframe at least every second, which is how long a reader that lost
        // its place waits at the longest.
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 1.0 as NSNumber)
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval,
            Int(framesPerSecond.rounded()) as NSNumber)
        set(kVTCompressionPropertyKey_AverageBitRate,
            Self.bitRate(width: width, height: height, framesPerSecond: framesPerSecond) as NSNumber)
        if case .sRGBCanvas = colors {
            // The canvas is sRGB, and saying so is what lets the phone show it as drawn.
            set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
            set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_sRGB)
            set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        }
    }
}

/// How a picture's numbers are to be read: its primaries, its transfer function,
/// and the matrix between its color and its brightness, as the code points video
/// standards share (ITU-T H.273).
///
/// A camera tags every buffer it delivers, and those tags do not cross the wire
/// inside the compressed stream's parameter sets. So the phone reads them off
/// the buffer and sends the three numbers beside the picture, and the Mac hands
/// them to its decoder; without the matrix a decoder guesses, and a guess of
/// BT.709 for a phone camera's BT.601 is tens of levels off in a strong color.
struct PhonePictureColors: Sendable, Equatable {
    var primaries: UInt8
    var transfer: UInt8
    var matrix: UInt8

    /// The code point that says a value was not given.
    static let unspecified: UInt8 = 2

    init(primaries: UInt8 = PhonePictureColors.unspecified,
         transfer: UInt8 = PhonePictureColors.unspecified,
         matrix: UInt8 = PhonePictureColors.unspecified) {
        self.primaries = primaries
        self.transfer = transfer
        self.matrix = matrix
    }

    /// The tags a buffer carries, with "unspecified" for each one it does not.
    init(of pixelBuffer: CVPixelBuffer) {
        func point(_ key: CFString, _ convert: (CFString?) -> Int32) -> UInt8 {
            guard let name = CVBufferCopyAttachment(pixelBuffer, key, nil) as? String
            else { return Self.unspecified }
            let code = convert(name as CFString)
            return code > 0 && code <= Int32(UInt8.max) ? UInt8(code) : Self.unspecified
        }
        primaries = point(kCVImageBufferColorPrimariesKey, CVColorPrimariesGetIntegerCodePointForString)
        transfer = point(kCVImageBufferTransferFunctionKey, CVTransferFunctionGetIntegerCodePointForString)
        matrix = point(kCVImageBufferYCbCrMatrixKey, CVYCbCrMatrixGetIntegerCodePointForString)
    }

    /// The tags as the extensions of a decoder's format, leaving out each value
    /// that was not given, so the decoder is told only what the camera said.
    var formatExtensions: [CFString: Any] {
        var extensions: [CFString: Any] = [:]
        if primaries != Self.unspecified,
           let name = CVColorPrimariesGetStringForIntegerCodePoint(Int32(primaries))?.takeUnretainedValue() {
            extensions[kCMFormatDescriptionExtension_ColorPrimaries] = name
        }
        if transfer != Self.unspecified,
           let name = CVTransferFunctionGetStringForIntegerCodePoint(Int32(transfer))?.takeUnretainedValue() {
            extensions[kCMFormatDescriptionExtension_TransferFunction] = name
        }
        if matrix != Self.unspecified,
           let name = CVYCbCrMatrixGetStringForIntegerCodePoint(Int32(matrix))?.takeUnretainedValue() {
            extensions[kCMFormatDescriptionExtension_YCbCrMatrix] = name
        }
        return extensions
    }
}

extension PhoneCameraPicture {
    /// The picture's three color values as one.
    var colors: PhonePictureColors {
        PhonePictureColors(primaries: colorPrimaries, transfer: transferFunction, matrix: yCbCrMatrix)
    }
}

/// Decides, frame by frame, whether the phone compresses its camera for the
/// cable, and numbers the pictures it does.
///
/// The rule is the whole of the camera connection's flow control, so it lives
/// here in the file both ends share and a Mac test pins it. Two things can
/// each stop a frame from being compressed, and both are decided *before* the
/// compressor sees it:
///
/// - nobody is on the camera connection, which is how a sketch that reads no
///   picture costs the phone nothing;
/// - the pictures already made have not left (`maxWaiting` of them are still
///   being compressed or waiting on the connection), which is a cable or a Mac
///   that is not keeping up, and the frame is skipped whole.
///
/// A picture is numbered when it is let in, not when it leaves, so a picture
/// lost after that point (too big for one frame of the wire, or dropped by the
/// compressor) leaves a gap the reader sees, and the next one let in is asked
/// to stand alone.
struct PhoneCameraGate: Sendable, Equatable {

    /// How many pictures may be on their way at once. Two, so the compressor
    /// and the connection each hold one and the camera's rate is kept on a
    /// cable that is keeping up.
    static let maxWaiting = 2

    /// A frame that was let in: its number on the connection, whether it must
    /// stand alone, and the connection it was let in for.
    struct Ticket: Sendable, Equatable {
        var sequence: UInt32
        var forcesKeyframe: Bool
        var connection: Int
    }

    private(set) var hasClient = false
    private(set) var waiting = 0
    private(set) var needsKeyframe = true
    private(set) var nextSequence: UInt32 = 0
    private(set) var connection = 0
    /// How many frames were skipped because the pictures before them had not left.
    private(set) var skipped = 0
    /// How many pictures were let in on this connection.
    private(set) var admitted = 0

    init() {}

    /// A client connected (or a newer one replaced it): it has nothing to build
    /// on, so the count starts again and the first picture stands alone.
    mutating func clientArrived() {
        hasClient = true
        connection += 1
        waiting = 0
        needsKeyframe = true
        nextSequence = 0
        skipped = 0
        admitted = 0
    }

    /// The client left. Pictures still on their way belong to nobody.
    mutating func clientLeft() {
        hasClient = false
        connection += 1
        waiting = 0
        needsKeyframe = true
    }

    /// Ask to compress one frame. `nil` means skip it.
    mutating func admit() -> Ticket? {
        guard hasClient else { return nil }
        guard waiting < Self.maxWaiting else {
            skipped += 1
            return nil
        }
        waiting += 1
        admitted += 1
        defer {
            nextSequence &+= 1
            needsKeyframe = false
        }
        return Ticket(sequence: nextSequence, forcesKeyframe: needsKeyframe, connection: connection)
    }

    /// The compressor handed a ticket's picture back. Returns whether to send
    /// it: not when its connection has gone, and not when it cannot be carried
    /// (`fits` false: no picture came back, or one too big for a frame of the
    /// wire), in which case the next frame let in stands alone.
    mutating func compressed(_ ticket: Ticket, fits: Bool) -> Bool {
        guard ticket.connection == connection else { return false }
        guard fits else {
            waiting = max(0, waiting - 1)
            needsKeyframe = true
            return false
        }
        return true
    }

    /// The connection took a ticket's picture.
    mutating func sent(_ ticket: Ticket) {
        guard ticket.connection == connection else { return }
        waiting = max(0, waiting - 1)
    }
}

/// Follows the numbers on the pictures a reader receives, and says which ones it
/// can decode.
///
/// A keyframe is always usable and is where the count starts again. A picture
/// that is not a keyframe is usable only when it is the one right after the
/// last usable picture; anything else means a picture in between was lost, and
/// everything is refused until the next keyframe.
struct PhoneCameraSequence: Sendable, Equatable {
    private(set) var expected: UInt32?
    /// How many pictures were refused because one before them was lost.
    private(set) var refused = 0

    init() {}

    /// Whether the picture with this number can be decoded.
    mutating func accepts(sequence: UInt32, isKeyframe: Bool) -> Bool {
        if isKeyframe || sequence == expected {
            expected = sequence &+ 1
            return true
        }
        expected = nil
        refused += 1
        return false
    }

    /// Forget where the count stood: the decoder failed, or the connection is new.
    mutating func reset() { expected = nil }
}

/// The phone's half of the camera connection: takes every frame of the camera
/// with its record, and compresses, frames, and sends the ones the connection
/// can take.
///
/// It lives in the file both ends share so the Mac's tests run the path the
/// phone runs: the gate, the compressor, the colors read off the buffer, the
/// message, and the count of what has left. The connection itself is the
/// caller's: `send` writes one framed message and calls back when the
/// connection has taken it, which is what tells the gate the cable is keeping
/// up.
///
/// `frame` is called from one thread (the camera's frames arrive on the main
/// thread), and the compressor is made, used, and replaced there. Everything
/// the compressor's thread and the connection's queue touch is behind the lock.
final class PhoneCameraSender: @unchecked Sendable {

    /// Writes one framed message, and calls back when the connection took it.
    typealias Send = @Sendable (Data, @escaping @Sendable () -> Void) -> Void

    private struct State: Sendable {
        var gate = PhoneCameraGate()
        var sent = 0
        var lost = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let send: Send
    private let framesPerSecond: Double
    private var compressor: PhonePictureCompressor?
    private var failedSize: (width: Int, height: Int)?

    init(framesPerSecond: Double = 60, send: @escaping Send) {
        self.framesPerSecond = framesPerSecond
        self.send = send
    }

    /// A sketch connected to the camera port, or a newer one replaced it.
    func clientArrived() {
        state.withLock { state in
            state.gate.clientArrived()
            state.sent = 0
            state.lost = 0
        }
    }

    /// The sketch on the camera port left.
    func clientLeft() { state.withLock { $0.gate.clientLeft() } }

    /// Whether a sketch is on the camera port.
    var hasClient: Bool { state.withLock { $0.gate.hasClient } }
    /// How many pictures the connection has taken since the client arrived.
    var sentCount: Int { state.withLock { $0.sent } }
    /// How many frames were skipped because the pictures before them had not left.
    var skippedCount: Int { state.withLock { $0.gate.skipped } }
    /// How many pictures were made and could not be sent.
    var lostCount: Int { state.withLock { $0.lost } }

    /// One frame of the camera: its picture as the sensor delivered it, and its
    /// record. Compressed and sent when a sketch is on the camera port and the
    /// pictures before it have left; skipped whole otherwise.
    func frame(_ pixelBuffer: CVPixelBuffer, camera: PhoneCameraSample) {
        guard let ticket = state.withLock({ $0.gate.admit() }) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        let colors = PhonePictureColors(of: pixelBuffer)
        let state = state
        let send = send
        let taken = compressorFitting(width: width, height: height)?.encode(
            pixelBuffer, at: camera.timestamp, forceKeyframe: ticket.forcesKeyframe
        ) { picture in
            let framed = picture.flatMap { picture -> Data? in
                let message = PhoneCameraPicture(
                    camera: camera, sequence: ticket.sequence, colorPrimaries: colors.primaries,
                    transferFunction: colors.transfer, yCbCrMatrix: colors.matrix, picture: picture)
                let frame = PhoneWire.encode(.cameraPicture(message))
                // A picture too big for one frame of the wire cannot be carried.
                return frame.count - PhoneWire.headerByteCount <= PhoneWire.maxPayloadBytes ? frame : nil
            }
            let sends = state.withLock { state -> Bool in
                let sends = state.gate.compressed(ticket, fits: framed != nil)
                if framed == nil { state.lost += 1 }
                return sends
            }
            guard sends, let framed else { return }
            send(framed) {
                state.withLock { state in
                    state.gate.sent(ticket)
                    state.sent += 1
                }
            }
        } ?? false
        if !taken {
            state.withLock { state in
                _ = state.gate.compressed(ticket, fits: false)
                state.lost += 1
            }
        }
    }

    /// Wait for every frame handed to the compressor to come back. For the tests.
    func finish() { compressor?.finish() }

    /// The compressor for this picture size, made on first use and made again
    /// when the camera's size changes (another mode, another camera).
    private func compressorFitting(width: Int, height: Int) -> PhonePictureCompressor? {
        if let compressor, compressor.width == width, compressor.height == height { return compressor }
        // A size the device could not compress once is not asked for every frame.
        if let failedSize, failedSize == (width, height) { return nil }
        compressor?.finish()
        compressor = PhonePictureCompressor(width: width, height: height,
                                            framesPerSecond: framesPerSecond, colors: .fromTheBuffers)
        failedSize = compressor == nil ? (width, height) : nil
        return compressor
    }
}
