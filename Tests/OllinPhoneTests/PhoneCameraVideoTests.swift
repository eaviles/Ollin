import Testing
import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox
import simd
import os
@testable import Ollin
@testable import OllinPhone

/// A frame the way a phone's camera delivers one: landscape, 4:2:0 at full
/// range, tagged BT.709 primaries and transfer with a BT.601 matrix, which is
/// what ARKit's frames carry. The scene is strong flat colors (the ones a wrong
/// matrix moves furthest), a ramp, and a block that travels every frame, so no
/// two frames match and no turn of the picture looks like another.
private struct CameraScene: Sendable {
    let width: Int
    let height: Int

    /// The size the tests run at: small, so comparing every pixel is quick.
    static let small = CameraScene(width: 640, height: 480)
    /// A size past standard definition, where a decoder left to guess takes
    /// the colors for BT.709. A phone's camera is larger still.
    static let large = CameraScene(width: 1280, height: 960)

    static let bars: [(Double, Double, Double)] = [
        (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0),
        (0, 255, 255), (255, 0, 255), (200, 120, 40), (30, 90, 160),
    ]

    /// The color of landscape pixel `(x, y)` on a frame.
    func color(_ x: Int, _ y: Int, frame: Int) -> (Double, Double, Double) {
        // The traveling block, on even pixels so no 2x2 chroma cell straddles it.
        let left = 40 + frame * 24
        if x >= left, x < left + 64, y >= 40, y < 104 { return (250, 250, 250) }
        if y < height * 2 / 3 { return Self.bars[x * 8 / width] }
        // A ramp along the bottom, in steps eight pixels wide.
        let step = Double(x / 8 * 8) / Double(width) * 255
        return (step, 255 - step, 128)
    }

    func buffer(frame: Int) -> CVPixelBuffer {
        var made: CVPixelBuffer?
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any]()]
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                            attributes as CFDictionary, &made)
        let buffer = made!
        CVPixelBufferLockBaseAddress(buffer, [])
        let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let chroma = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt8.self)
        let chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        // BT.601, full range.
        let kr = 0.299, kb = 0.114, kg = 1 - 0.299 - 0.114
        func byte(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = color(x, y, frame: frame)
                let l = kr * r + kg * g + kb * b
                luma[y * lumaRow + x] = byte(l)
                if y % 2 == 0, x % 2 == 0 {
                    chroma[(y / 2) * chromaRow + x] = byte((b - l) / (2 * (1 - kb)) + 128)
                    chroma[(y / 2) * chromaRow + x + 1] = byte((r - l) / (2 * (1 - kr)) + 128)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        CVBufferSetAttachment(buffer, kCVImageBufferColorPrimariesKey,
                              kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferTransferFunctionKey,
                              kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(buffer, kCVImageBufferYCbCrMatrixKey,
                              kCVImageBufferYCbCrMatrix_ITU_R_601_4, .shouldPropagate)
        return buffer
    }

    /// The camera record of a frame: a time, a number, and a place that are
    /// its own, held in portrait.
    func sample(frame: Int, quarterTurnsCW: UInt8 = 1) -> PhoneCameraSample {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(Float(frame) * 0.05, 1.4, -Float(frame) * 0.02, 1)
        return PhoneCameraSample(
            isTracked: true, timestamp: 1000 + Double(frame) / 60, frameIndex: UInt32(frame * 3),
            imageWidth: width, imageHeight: height, fx: 500, fy: 500,
            cx: Float(width) / 2, cy: Float(height) / 2,
            transform: transform, quarterTurnsCW: quarterTurnsCW)
    }

    /// How far a decoded picture is from a frame, on average over the color
    /// channels in eight-bit levels. `upright` reads a picture that was turned
    /// a quarter clockwise, where landscape `(u, v)` lands at `(height - 1 - v, u)`.
    func meanError(of buffer: CVPixelBuffer, against frame: Int, upright: Bool) -> Double {
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              (w, h) == (upright ? (height, width) : (width, height)) else { return .infinity }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self)
        else { return .infinity }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var sum = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let (r, g, b) = upright ? color(y, height - 1 - x, frame: frame) : color(x, y, frame: frame)
                let p = base + y * rowBytes + x * 4
                sum += abs(Double(p[2]) - r) + abs(Double(p[1]) - g) + abs(Double(p[0]) - b)
            }
        }
        return sum / Double(w * h * 3)
    }
}

/// One end of a socket pair standing in for the cable, handed to whoever dials
/// once and refused afterwards.
private final class Cable: Sendable {
    let macEnd: Int32
    let phoneEnd: Int32
    private let dialed = OSAllocatedUnfairLock(initialState: false)

    init() {
        var pair: [Int32] = [0, 0]
        precondition(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        macEnd = pair[0]
        phoneEnd = pair[1]
    }

    var hasBeenDialed: Bool { dialed.withLock { $0 } }

    /// What a feed is given to dial with.
    var connect: @Sendable (UInt16) throws -> Int32 {
        { [self] _ in
            let first = dialed.withLock { was -> Bool in defer { was = true }; return !was }
            guard first else { throw CancellationError() }
            return macEnd
        }
    }

    /// Write one framed message from the phone's end, in chunks that cut
    /// through its header and its payload alike.
    func write(_ frame: Data) {
        var offset = 0
        var step = 11
        frame.withUnsafeBytes { raw in
            while offset < frame.count {
                let count = min(step, frame.count - offset)
                var sent = 0
                while sent < count {
                    let wrote = Darwin.write(phoneEnd, raw.baseAddress! + offset + sent, count - sent)
                    guard wrote > 0 else { return }
                    sent += wrote
                }
                offset += count
                step = step * 7 % 8191 + 1
            }
        }
    }

    func hangUp() { close(phoneEnd) }
}

/// Probe first, then read the clock, so a test resumed late still looks once.
@MainActor
private func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(30)
    while true {
        if condition() { return }
        guard Date() < deadline else {
            Issue.record("never held: \(what)")
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(5))
    }
}

/// The camera's picture on the cable, end to end on this Mac: frames shaped
/// like a phone camera's go into the sender the phone runs (the gate, the
/// compressor, the colors read off the buffer, the message), across a socket
/// pair in uneven chunks, into the feed the Mac runs (the framing, the decoder,
/// the turn upright), and each comes out as the picture it started as, holding
/// the camera record it was sent with.
///
/// It uses the media engine's coder and decoder, so it runs in the device phase
/// (`Scripts/test.sh`), inside `PhoneMediaTests`, which keeps the suites that
/// work the media engine from running at once.
extension PhoneMediaTests {
@MainActor
@Suite struct PhoneCameraVideoTests {

    /// The frames of the scene compressed in order, as the messages the phone
    /// would send, with a keyframe forced at each index of `keys`.
    private func messages(_ count: Int, of scene: CameraScene = .small,
                          forcingKeyframesAt keys: Set<Int> = []) throws -> [PhoneCameraPicture] {
        let compressor = try #require(PhonePictureCompressor(
            width: scene.width, height: scene.height, framesPerSecond: 30,
            colors: .fromTheBuffers))
        let made = OSAllocatedUnfairLock(initialState: [Int: PhoneCameraPicture]())
        for frame in 0..<count {
            let buffer = scene.buffer(frame: frame)
            let colors = PhonePictureColors(of: buffer)
            let camera = scene.sample(frame: frame)
            #expect(compressor.encode(buffer, at: camera.timestamp, forceKeyframe: keys.contains(frame)) { picture in
                guard let picture else { return }
                made.withLock {
                    $0[frame] = PhoneCameraPicture(
                        camera: camera, sequence: UInt32(frame), colorPrimaries: colors.primaries,
                        transferFunction: colors.transfer, yCbCrMatrix: colors.matrix, picture: picture)
                }
            })
        }
        compressor.finish()
        let all = made.withLock { $0 }
        #expect(all.count == count)
        return try (0..<count).map { try #require(all[$0]) }
    }

    /// Decode pictures straight through a decoder, as the sensor delivered
    /// them, telling it the colors or leaving it to guess.
    private func decode(_ messages: [PhoneCameraPicture], tellingColors: Bool) throws -> [CVPixelBuffer] {
        var format: PhonePictureFormat?
        var session: VTDecompressionSession?
        let decoded = OSAllocatedUnfairLock(uncheckedState: [CVPixelBuffer]())
        defer { if let session { VTDecompressionSessionInvalidate(session) } }
        for message in messages {
            let sample = try #require(message.picture.sampleBuffer(
                reusing: &format, colors: tellingColors ? message.colors : nil))
            if session == nil {
                let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA]
                var made: VTDecompressionSession?
                #expect(VTDecompressionSessionCreate(
                    allocator: kCFAllocatorDefault, formatDescription: try #require(format).description,
                    decoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary,
                    outputCallback: nil, decompressionSessionOut: &made) == noErr)
                session = made
            }
            #expect(VTDecompressionSessionDecodeFrame(
                try #require(session), sampleBuffer: sample, flags: [], infoFlagsOut: nil
            ) { status, _, image, _, _ in
                guard status == noErr, let image else { return }
                decoded.withLockUnchecked { $0.append(image) }
            } == noErr)
        }
        if let session { VTDecompressionSessionWaitForAsynchronousFrames(session) }
        return decoded.withLockUnchecked { $0 }
    }

    @Test func theCameraPictureCrossesWithItsColors() throws {
        let scene = CameraScene.small
        let sent = try messages(6)
        #expect(sent[0].picture.isKeyframe)
        #expect(sent[0].picture.parameterSets.count == 3)
        #expect(sent.dropFirst().allSatisfy { !$0.picture.isKeyframe })
        // The camera said how its colors are to be read, in the standards' own
        // numbers: BT.709 primaries and transfer, the BT.601 matrix.
        #expect(sent.allSatisfy { $0.colorPrimaries == 1 && $0.transferFunction == 1 && $0.yCbCrMatrix == 6 })

        // Every message through the wire's own coder, whole.
        for message in sent {
            #expect(roundTrip(.cameraPicture(message)) == .cameraPicture(message))
        }

        let told = try decode(sent, tellingColors: true)
        #expect(told.count == sent.count)
        for (frame, picture) in told.enumerated() {
            let error = scene.meanError(of: picture, against: frame, upright: false)
            #expect(error < 2.5, "frame \(frame) is \(error) levels off on average")
        }

        // The tolerance has to be able to fail: a picture against a frame the
        // block had moved on from is not the same picture.
        #expect(scene.meanError(of: told[5], against: 1, upright: false) > 2.5)
    }

    @Test func aDecoderLeftToGuessReadsTheCameraWrong() throws {
        // Why the colors are sent. The compressed stream's parameter sets say
        // nothing of them, and a decoder left to guess takes anything past
        // standard definition for BT.709; a phone's camera is far past it and
        // uses the BT.601 matrix, so its strong colors come back tens of levels
        // off. Told, the same pictures are right.
        let scene = CameraScene.large
        let sent = try messages(2, of: scene)
        #expect(sent.allSatisfy { $0.yCbCrMatrix == 6 })
        let told = try decode(sent, tellingColors: true)
        let guessed = try decode(sent, tellingColors: false)
        let right = scene.meanError(of: try #require(told.last), against: 1, upright: false)
        let wrong = scene.meanError(of: try #require(guessed.last), against: 1, upright: false)
        #expect(right < 2.5, "told its colors, the picture is \(right) levels off")
        #expect(wrong > 2.5 * 2, "left to guess, the picture is only \(wrong) levels off")
    }

    @Test func eachPictureArrivesUprightWithItsOwnCameraRecord() async throws {
        let scene = CameraScene.small
        let cable = Cable()
        let sender = PhoneCameraSender(framesPerSecond: 30) { frame, whenTaken in
            cable.write(frame)
            whenTaken()
        }
        let times = OSAllocatedUnfairLock(initialState: [Double]())
        let feed = PhoneCameraFeed(wantedFor: 60, onPictureTime: { time in
            if let time { times.withLock { $0.append(time) } }
        }, connect: cable.connect)

        // Nothing dials until a sketch reads the picture, and nothing is
        // compressed until a sketch is on the camera port.
        sender.frame(scene.buffer(frame: 0), camera: scene.sample(frame: 0))
        sender.finish()
        #expect(sender.sentCount == 0 && !cable.hasBeenDialed)

        feed.keepWanted()
        try await waitUntil("the feed connects") { feed.isConnected }
        sender.clientArrived()

        let count = 8
        for frame in 0..<count {
            let camera = scene.sample(frame: frame)
            sender.frame(scene.buffer(frame: frame), camera: camera)
            try await waitUntil("frame \(frame) is the newest decoded") { feed.latest?.sample == camera }
            let newest = try #require(feed.latest)
            // The record that came with the picture is the one it was sent
            // with, to the bit: its time, its number, where the camera stood.
            #expect(newest.sample == camera)
            #expect(newest.number == frame + 1)
            let error = scene.meanError(of: newest.buffer, against: frame, upright: true)
            #expect(error < 2.5, "frame \(frame) is \(error) levels off on average")
        }
        #expect(sender.sentCount == count && sender.skippedCount == 0 && sender.lostCount == 0)
        #expect(feed.decodedCount == count && feed.refusedCount == 0)
        #expect(feed.lastError == nil)
        // Each picture told the device's clock its capture time, in order.
        #expect(times.withLock { $0 } == (0..<count).map { scene.sample(frame: $0).timestamp })

        // The turn has to be able to fail: read as if it had gone the other
        // way round, the newest picture is nothing like its frame.
        let newest = try #require(feed.latest)
        #expect(scene.meanError(of: newest.buffer, against: count - 1, upright: true) < 2.5)
        #expect(scene.meanError(of: newest.buffer, against: 0, upright: true) > 2.5)

        // A phone that hangs up leaves nothing to read.
        cable.hangUp()
        try await waitUntil("the feed sees the hang-up") { !feed.isConnected }
        #expect(feed.latest == nil)
        #expect(times.withLock { $0.count } == count)
        feed.stop()
    }

    @Test func aPictureLostOnTheWayIsCaughtAndTheNextKeyframeRecovers() async throws {
        // Twelve pictures with a keyframe forced at the ninth, and the fourth
        // never written: everything built on it is refused, and the keyframe
        // starts the picture again.
        let scene = CameraScene.small
        let sent = try messages(12, forcingKeyframesAt: [8])
        #expect(sent[8].picture.isKeyframe)
        let cable = Cable()
        let feed = PhoneCameraFeed(wantedFor: 60, connect: cable.connect)
        feed.keepWanted()
        try await waitUntil("the feed connects") { feed.isConnected }
        for (index, message) in sent.enumerated() where index != 3 {
            cable.write(PhoneWire.encode(.cameraPicture(message)))
        }
        try await waitUntil("every picture is decoded or refused") {
            feed.decodedCount + feed.refusedCount == 11
        }
        #expect(feed.refusedCount == 4, "pictures 4 to 7 are built on the one that was lost")
        #expect(feed.decodedCount == 7)
        let newest = try #require(feed.latest)
        #expect(newest.sample == scene.sample(frame: 11))
        #expect(scene.meanError(of: newest.buffer, against: 11, upright: true) < 2.5)

        // A frame that is not this wire's ends the connection, as on the
        // sensor's own.
        cable.write(Data([0x4F, 0x4C, 0x4E, 0x52]) + Data(repeating: 0, count: 8))
        try await waitUntil("the feed drops a stream out of step") { !feed.isConnected }
        cable.hangUp()
        feed.stop()
    }

    @Test func aCableThatStallsSkipsWholeFramesBeforeTheyAreCompressed() throws {
        // A connection that takes nothing: the phone holds two pictures (one
        // with the compressor, one with the connection) and skips every frame
        // after them whole, so nothing it made is ever thrown away.
        let scene = CameraScene.small
        typealias Waiting = (frame: Data, whenTaken: @Sendable () -> Void)
        let waiting = OSAllocatedUnfairLock(uncheckedState: [Waiting]())
        let sender = PhoneCameraSender(framesPerSecond: 30) { frame, whenTaken in
            waiting.withLockUnchecked { $0.append((frame, whenTaken)) }
        }
        func picture(_ index: Int) throws -> PhoneCameraPicture {
            let frame = waiting.withLockUnchecked { $0[index].frame }
            let header = try #require(PhoneHeader.parse(frame))
            #expect(header.kind == .cameraPicture)
            let payload = frame.subdata(in: (frame.startIndex + PhoneWire.headerByteCount) ..< frame.endIndex)
            guard case .cameraPicture(let message)? = PhoneWire.decode(header: header, payload: payload) else {
                throw CancellationError()
            }
            return message
        }

        sender.clientArrived()
        for frame in 0..<10 {
            sender.frame(scene.buffer(frame: frame), camera: scene.sample(frame: frame))
        }
        sender.finish()
        #expect(waiting.withLockUnchecked { $0.count } == PhoneCameraGate.maxWaiting)
        #expect(sender.skippedCount == 10 - PhoneCameraGate.maxWaiting)
        #expect(sender.sentCount == 0)
        // What was made is numbered without a gap, the first standing alone,
        // each with the record of the frame it is a picture of.
        #expect(try picture(0).sequence == 0 && picture(0).picture.isKeyframe)
        #expect(try picture(1).sequence == 1 && !picture(1).picture.isKeyframe)
        #expect(try picture(1).camera == scene.sample(frame: 1))

        // The connection takes them, and the next frames go.
        for entry in waiting.withLockUnchecked({ $0 }) { entry.whenTaken() }
        #expect(sender.sentCount == 2)
        sender.frame(scene.buffer(frame: 10), camera: scene.sample(frame: 10))
        sender.finish()
        #expect(waiting.withLockUnchecked { $0.count } == 3)
        // A skipped frame leaves no gap in the numbers: it was never numbered.
        #expect(try picture(2).sequence == 2 && picture(2).camera == scene.sample(frame: 10))

        // A new sketch on the port has nothing to build on: the count starts
        // again and its first picture stands alone.
        sender.clientArrived()
        sender.frame(scene.buffer(frame: 11), camera: scene.sample(frame: 11))
        sender.finish()
        #expect(try picture(3).sequence == 0 && picture(3).picture.isKeyframe)

        // With nobody on the port nothing is compressed at all.
        sender.clientLeft()
        sender.frame(scene.buffer(frame: 12), camera: scene.sample(frame: 12))
        sender.finish()
        #expect(waiting.withLockUnchecked { $0.count } == 4)
    }

    @Test func aSketchReadingThePictureGetsThePictureAndThePoseOfOneFrame() async throws {
        let scene = CameraScene.small
        let cable = Cable()
        let device = PhoneDevice(cameraConnect: cable.connect, pictureWantedFor: 0.5)
        let sender = PhoneCameraSender(framesPerSecond: 30) { frame, whenTaken in
            cable.write(frame)
            whenTaken()
        }
        device.start()

        // The sensor connection says where the camera is now, eight frames on
        // from anything the picture has shown.
        let sensed = scene.sample(frame: 8)
        device.reader.arrive(.camera(sensed))

        // Reading where the camera stood asks for no video.
        let first = try #require(device.latestCamera)
        #expect(first.timestamp == sensed.timestamp)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!cable.hasBeenDialed)

        // Reading the picture does, and until one arrives there is none.
        #expect(first.picture == nil)
        try await waitUntil("the picture connection opens") { device.cameraFeed?.isConnected == true }
        sender.clientArrived()

        var shown: PhoneCamera?
        for frame in 0..<3 {
            let camera = scene.sample(frame: frame)
            sender.frame(scene.buffer(frame: frame), camera: camera)
            try await waitUntil("frame \(frame) reaches the device") {
                device.latestCamera?.timestamp == camera.timestamp
            }
            let view = try #require(device.latestCamera)
            _ = view.picture
            shown = view
        }

        // While the picture arrives, the camera a sketch reads is the
        // picture's own frame, not the newer one the sensor connection holds:
        // a thing drawn through it lands on its place in that picture.
        let view = try #require(shown)
        let own = PhoneCamera(scene.sample(frame: 2))
        #expect(view.timestamp == own.timestamp && view.frameIndex == own.frameIndex)
        #expect(view.pose == own.pose)
        #expect(view.timestamp != sensed.timestamp)
        // Upright for the hold: the picture and the lens turned together.
        let picture = try #require(view.picture)
        #expect(picture.width == scene.height && picture.height == scene.width)
        #expect(view.intrinsics.width == scene.height && view.intrinsics.height == scene.width)
        // Two reads in one frame are one texture.
        #expect(try #require(device.latestCamera?.picture) === picture)

        // A sketch that stops reading the picture lets the connection go, and
        // the camera is the newest one sensed again, with no picture.
        try await waitUntil("the picture connection closes") { device.cameraFeed?.isConnected == false }
        let after = try #require(device.latestCamera)
        #expect(after.timestamp == sensed.timestamp)
        cable.hangUp()
        device.stop()
    }
}
}

/// The rules of the camera connection that need no media engine: the gate that
/// decides what the phone compresses, the count a reader follows, the readings
/// held until their picture is here, and the wire.
@MainActor
@Suite struct PhoneCameraLinkTests {

    @Test func theGateLetsInOnlyWhatTheConnectionCanTake() {
        var gate = PhoneCameraGate()
        // Nobody on the port: nothing is compressed, and nothing counts as skipped.
        let nobody = gate.admit()
        #expect(nobody == nil)
        #expect(gate.skipped == 0)

        gate.clientArrived()
        let first = gate.admit(), second = gate.admit()
        #expect(first?.sequence == 0 && first?.forcesKeyframe == true)
        #expect(second?.sequence == 1 && second?.forcesKeyframe == false)
        // Two are on their way; the third frame is skipped whole.
        let skipped = gate.admit()
        #expect(skipped == nil)
        #expect(gate.skipped == 1 && gate.waiting == 2)

        // Compressed is not yet gone: the connection still holds it.
        let sendsFirst = gate.compressed(first!, fits: true)
        let stillFull = gate.admit()
        #expect(sendsFirst && stillFull == nil)
        gate.sent(first!)
        let third = gate.admit()
        #expect(third?.sequence == 2 && third?.forcesKeyframe == false)

        // A picture that cannot be carried frees its place, leaves a gap in
        // the numbers for the reader to see, and the next stands alone.
        let sendsSecond = gate.compressed(second!, fits: false)
        let fourth = gate.admit()
        #expect(!sendsSecond)
        #expect(fourth?.sequence == 3 && fourth?.forcesKeyframe == true)
    }

    @Test func aNewerSketchOwesNothingToTheOldOnesPictures() {
        var gate = PhoneCameraGate()
        gate.clientArrived()
        let old = gate.admit()!
        gate.clientArrived()
        // The old connection's picture is not sent to the new one, and its
        // leaving does not free a place it never held there.
        let sendsOld = gate.compressed(old, fits: true)
        #expect(!sendsOld)
        let a = gate.admit()!, b = gate.admit()!
        #expect(a.sequence == 0 && a.forcesKeyframe && b.sequence == 1)
        gate.sent(old)
        let full = gate.admit()
        #expect(full == nil)
        gate.sent(a)
        let next = gate.admit()
        #expect(next?.sequence == 2)

        gate.clientLeft()
        let gone = gate.admit()
        let sendsAfter = gate.compressed(b, fits: true)
        #expect(gone == nil && !sendsAfter)
    }

    @Test func aReaderRefusesWhatIsBuiltOnALostPicture() {
        var sequence = PhoneCameraSequence()
        func take(_ number: UInt32, key: Bool = false) -> Bool {
            sequence.accepts(sequence: number, isKeyframe: key)
        }
        // Nothing is usable before a keyframe.
        let early = take(0)
        let key = take(4, key: true), built = take(5)
        #expect(!early && key && built)
        // Six never came: seven and eight are built on it.
        let seven = take(7), eight = take(8)
        #expect(!seven && !eight)
        #expect(sequence.refused == 3)
        let again = take(9, key: true), after = take(10)
        #expect(again && after)
        // The count wraps like any other.
        var late = PhoneCameraSequence()
        let last = late.accepts(sequence: .max, isKeyframe: true)
        let wrapped = late.accepts(sequence: 0, isKeyframe: false)
        #expect(last && wrapped)
    }

    // MARK: Readings held until their picture is here

    private func reader() -> PhoneStreamReader {
        PhoneStreamReader(port: PhoneDevice.streamPort, sounds: PhoneSounds(), touches: PhoneTouches())
    }

    private func wand(_ time: Double) -> PhoneMessage {
        .wand(PhoneWandSample(isTracked: true, timestamp: time, transform: matrix_identity_float4x4))
    }

    private func hand(_ time: Double) -> PhoneMessage {
        .hands([PhoneHandSample(isTracked: true, timestamp: time, joints: [:])])
    }

    @Test func withNoPictureArrivingNothingWaits() {
        let reader = reader()
        reader.arrive(wand(10), now: 100)
        #expect(reader.latestWand?.timestamp == 10)
        #expect(reader.heldCount == 0)
    }

    @Test func aReadingWaitsForThePictureOfItsFrame() {
        let reader = reader()
        reader.pictureArrived(at: 10.000, now: 100.00)
        // Read from the frame the picture already shows: straight in.
        reader.arrive(wand(10.000), now: 100.00)
        #expect(reader.latestWand?.timestamp == 10.000)
        // Read from the two frames after it: held, in order.
        reader.arrive(wand(10.016), now: 100.01)
        reader.arrive(wand(10.033), now: 100.02)
        #expect(reader.latestWand?.timestamp == 10.000)
        #expect(reader.heldCount == 2)
        // Each picture lets through what was read from its frame and no more.
        reader.pictureArrived(at: 10.016, now: 100.03)
        #expect(reader.latestWand?.timestamp == 10.016)
        #expect(reader.heldCount == 1)
        reader.pictureArrived(at: 10.033, now: 100.05)
        #expect(reader.latestWand?.timestamp == 10.033)
        #expect(reader.heldCount == 0)
    }

    @Test func aPictureThatSkipsAheadLetsEverythingBeforeItThrough() {
        // The phone skipped two frames' pictures (a slow cable); the readings
        // from those frames go when a later picture arrives, in order, so the
        // latest is the one nearest the picture.
        let reader = reader()
        reader.pictureArrived(at: 10.000, now: 100)
        for step in 1...4 { reader.arrive(wand(10 + Double(step) * 0.016), now: 100.01) }
        reader.pictureArrived(at: 10.048, now: 100.06)
        #expect(reader.latestWand?.timestamp == 10.048)
        #expect(reader.heldCount == 1)
    }

    @Test func whatIsNotReadFromACameraFrameNeverWaits() {
        let reader = reader()
        reader.pictureArrived(at: 10, now: 100)
        reader.arrive(wand(10.5), now: 100.01)
        #expect(reader.heldCount == 1)
        // The phone's own motion, the room's light, and where the camera is
        // now go straight through, past what is waiting.
        reader.arrive(.motion(PhoneMotionSample(attitude: SIMD4<Float>(0, 0, 0, 1), gravity: SIMD3<Float>(0, -1, 0),
                                                rotationRate: .zero, userAcceleration: .zero, timestamp: 10.5)),
                      now: 100.01)
        reader.arrive(.light(PhoneLightSample(timestamp: 10.5, ambientIntensity: 900, colorTemperature: 5000)),
                      now: 100.01)
        reader.arrive(.camera(PhoneCameraSample(isTracked: true, timestamp: 10.5, frameIndex: 7, imageWidth: 4,
                                                imageHeight: 2, fx: 1, fy: 1, cx: 2, cy: 1,
                                                transform: matrix_identity_float4x4)), now: 100.01)
        #expect(reader.latestMotion?.timestamp == 10.5)
        #expect(reader.latestLight?.timestamp == 10.5)
        #expect(reader.latestCamera?.timestamp == 10.5)
        #expect(reader.heldCount == 1 && reader.latestWand == nil)
    }

    @Test func anEmptyListGoesWithWhatWasReadBeforeIt() {
        // "No hand in view" names no frame. It follows the hand that was read
        // before it, so the hand is seen and then seen to leave, in that order.
        let reader = reader()
        reader.pictureArrived(at: 10, now: 100)
        reader.arrive(hand(10.016), now: 100.01)
        reader.arrive(.hands([]), now: 100.02)
        #expect(reader.heldCount == 2 && reader.latestHands.isEmpty)
        reader.pictureArrived(at: 10.016, now: 100.03)
        #expect(reader.heldCount == 0 && reader.latestHands.isEmpty)
        // With nothing waiting it goes straight in.
        reader.arrive(hand(10.016), now: 100.04)
        #expect(reader.latestHands.count == 1)
        reader.arrive(.hands([]), now: 100.05)
        #expect(reader.latestHands.isEmpty && reader.heldCount == 0)
    }

    @Test func aPictureThatStopsStrandsNothing() {
        let reader = reader()
        reader.pictureArrived(at: 10, now: 100)
        reader.arrive(wand(10.016), now: 100.01)
        #expect(reader.heldCount == 1)
        // A quarter second with no picture: the next arrival lets everything
        // through and is not held itself.
        reader.arrive(wand(10.4), now: 100 + PhoneStreamReader.pictureArrivesFor + 0.02)
        #expect(reader.heldCount == 0)
        #expect(reader.latestWand?.timestamp == 10.4)

        // The feed letting go of its connection does the same at once.
        reader.pictureArrived(at: 11, now: 200)
        reader.arrive(wand(11.2), now: 200.01)
        #expect(reader.heldCount == 1)
        reader.pictureArrived(at: nil, now: 200.02)
        #expect(reader.heldCount == 0 && reader.latestWand?.timestamp == 11.2)
    }

    @Test func theWaitIsBounded() {
        let reader = reader()
        reader.pictureArrived(at: 10, now: 100)
        for step in 1...(PhoneStreamReader.maxHeld + 5) {
            reader.arrive(wand(10 + Double(step)), now: 100.01)
        }
        #expect(reader.heldCount == PhoneStreamReader.maxHeld)
        // The oldest went through to make room, in order.
        #expect(reader.latestWand?.timestamp == 15)
    }

    // MARK: The wire

    @Test func aCameraPictureRoundTripsAndBoundsItsLengths() throws {
        let camera = PhoneCameraSample(
            isTracked: true, timestamp: 123.456, frameIndex: 99, imageWidth: 1920, imageHeight: 1440,
            fx: 1450.5, fy: 1451.25, cx: 960.5, cy: 719.75,
            transform: simd_float4x4(SIMD4(0, 1, 0, 0), SIMD4(-1, 0, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0.5, 1.5, -2, 1)),
            quarterTurnsCW: 3)
        let keyframe = PhoneCameraPicture(
            camera: camera, sequence: 7, colorPrimaries: 1, transferFunction: 1, yCbCrMatrix: 6,
            picture: PhonePicture(width: 1920, height: 1440, isKeyframe: true,
                                  parameterSets: [Data([1, 2, 3]), Data([4, 5]), Data([6])],
                                  data: Data((0..<200).map { UInt8($0) })))
        #expect(roundTrip(.cameraPicture(keyframe)) == .cameraPicture(keyframe))
        #expect(PhoneMessage.cameraPicture(keyframe).kind == .cameraPicture)
        #expect(PhoneMessageKind.cameraPicture.rawValue == 20)

        var built = keyframe
        built.sequence = 8
        built.picture = PhonePicture(width: 1920, height: 1440, isKeyframe: false, data: Data([9, 9, 9]))
        #expect(roundTrip(.cameraPicture(built)) == .cameraPicture(built))

        // Left out, the colors say "unspecified", the standards' own number for it.
        let untold = PhoneCameraPicture(camera: camera, sequence: 0, picture: built.picture)
        #expect(untold.colorPrimaries == 2 && untold.transferFunction == 2 && untold.yCbCrMatrix == 2)
        #expect(untold.colors.formatExtensions.isEmpty)
        #expect(keyframe.colors.formatExtensions.count == 3)

        // Cut anywhere, the payload is refused whole, never read past its end.
        let frame = PhoneWire.encode(.cameraPicture(keyframe))
        let payload = frame.subdata(in: (frame.startIndex + PhoneWire.headerByteCount) ..< frame.endIndex)
        let header = PhoneHeader(kind: .cameraPicture, payloadLength: payload.count)
        #expect(PhoneWire.decode(header: header, payload: payload) != nil)
        for length in 0..<payload.count {
            #expect(PhoneWire.decode(header: header, payload: payload.prefix(length)) == nil,
                    "a payload cut to \(length) bytes decoded")
        }
        // A keyframe with nothing to build a decoder from is refused.
        var bare = keyframe
        bare.picture.parameterSets = []
        #expect(roundTrip(.cameraPicture(bare)) == nil)
    }

    @Test func aPictureIsTheSameBytesInBothDirections() {
        // The sketch's frames going down and the camera's coming up are one
        // picture codec: the bytes after a camera picture's own fields are the
        // bytes of a picture request.
        let picture = PhonePicture(width: 640, height: 360, isKeyframe: true,
                                   parameterSets: [Data([1]), Data([2, 3])], data: Data([7, 8, 9, 10]))
        #expect(roundTrip(.picture(picture)) == .picture(picture))
        let request = PhoneWire.encode(.picture(picture)).dropFirst(PhoneWire.headerByteCount)
        let camera = PhoneCameraSample(isTracked: false, timestamp: 0, frameIndex: 0, imageWidth: 640,
                                       imageHeight: 360, fx: 1, fy: 1, cx: 0, cy: 0,
                                       transform: matrix_identity_float4x4)
        let message = PhoneWire.encode(.cameraPicture(PhoneCameraPicture(camera: camera, sequence: 0, picture: picture)))
            .dropFirst(PhoneWire.headerByteCount)
        #expect(Data(message.suffix(request.count)) == Data(request))
        let record = PhoneWire.encode(.camera(camera)).count - PhoneWire.headerByteCount
        #expect(message.count == record + 4 + 3 + request.count)
    }

    @Test func thePhoneSaysWhetherItsScreenIsTheSketchs() throws {
        // In a camera mode with the sketch's picture up: the viewfinder.
        let viewfinder = PhoneStateSample(timestamp: 5, mode: .room, status: "Streaming the room",
                                          notes: ["a note"], showsSketch: true)
        #expect(roundTrip(.state(viewfinder)) == .state(viewfinder))
        #expect(PhoneState(viewfinder).isShowingSketch)
        // Left out, the flag follows the mode.
        #expect(PhoneStateSample(timestamp: 0, mode: .sketch).showsSketch)
        #expect(!PhoneStateSample(timestamp: 0, mode: .room).showsSketch)
        #expect(PhoneState(timestamp: 0, mode: .sketch).isShowingSketch)
        #expect(!PhoneState(timestamp: 0, mode: .world).isShowingSketch)
        // Put away by the person holding the phone, it is carried as said.
        let away = PhoneStateSample(timestamp: 1, mode: .room, showsSketch: false)
        #expect(roundTrip(.state(away)) == .state(away))

        // A state written before the flag existed (a recording keeps its
        // state messages) still reads, and follows its mode.
        for mode in [PhoneCaptureMode.sketch, .room] {
            let frame = PhoneWire.encode(.state(PhoneStateSample(timestamp: 2, mode: mode, notes: ["n"])))
            let payload = frame.subdata(in: (frame.startIndex + PhoneWire.headerByteCount) ..< (frame.endIndex - 1))
            let header = PhoneHeader(kind: .state, payloadLength: payload.count)
            guard case .state(let old)? = PhoneWire.decode(header: header, payload: payload) else {
                Issue.record("a state without the flag did not decode")
                continue
            }
            #expect(old.showsSketch == (mode == .sketch))
            #expect(old.notes == ["n"])
        }
    }

    // MARK: Asking for the viewfinder

    @Test func showKeepsTheModeTheSketchAskedFor() {
        final class Plain: Sketch {}
        func device() -> PhoneDevice {
            PhoneDevice(cameraConnect: { _ in throw CancellationError() })
        }

        // Alone, show asks for Sketch mode, which runs no camera.
        let alone = device()
        alone.show(Plain()).stop()
        #expect(alone.reader.declaredMode == .sketch)

        // With a camera mode asked for, show leaves it: the phone as a viewfinder.
        let viewfinder = device()
        viewfinder.use(.room)
        viewfinder.show(Plain()).stop()
        #expect(viewfinder.reader.declaredMode == .room)

        // The order does not matter, and a later ask changes the mode under the picture.
        let reversed = device()
        reversed.show(Plain()).stop()
        reversed.use(.face)
        #expect(reversed.reader.declaredMode == .face)
    }

    @Test func theScreenSendsOnlyWhileThePhoneGivesItTheScreen() {
        // A camera mode with the sketch's picture up counts as showing, and a
        // finger on it presses; put away by the person holding the phone, it
        // does not, in whatever mode.
        final class Pointed: Sketch {
            var presses = 0
            override func mousePressed() { presses += 1 }
        }
        let device = PhoneDevice(cameraConnect: { _ in throw CancellationError() })
        let sketch = Pointed()
        sketch.setCanvasSize(width: 800, height: 400)
        let screen = PhoneScreen(device: device, frameRate: 60, sender: PhonePictureSender(dials: false))

        device.reader.arrive(.state(PhoneStateSample(timestamp: 1, mode: .room, showsSketch: true)))
        device.touches.feel([PhoneTouch(id: 1, position: Vector2(0, 0))], at: 1)
        screen.beforeDraw(sketch)
        #expect(sketch.presses == 1 && sketch.mouseIsPressed)
        device.touches.feel([], at: 2)
        screen.beforeDraw(sketch)

        device.reader.arrive(.state(PhoneStateSample(timestamp: 3, mode: .room, showsSketch: false)))
        device.touches.feel([PhoneTouch(id: 2, position: Vector2(0, 0))], at: 3)
        screen.beforeDraw(sketch)
        #expect(sketch.presses == 1 && !sketch.mouseIsPressed)
        // No picture has reached a phone, so nothing is showing either way.
        #expect(!screen.isShowing)
        screen.stop()
    }
}
