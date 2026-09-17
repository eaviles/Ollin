import Testing
import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Metal
import VideoToolbox
import os
import Ollin
@testable import OllinPhone

/// A sketch that moves and keeps fine detail: hairlines, a gradient, small type,
/// and discs that travel every frame, which is the kind of picture a compressor
/// gets wrong in a way the eye would see.
private final class PictureProbe: Sketch {
    override var canvasSize: CanvasSize { .size(640, 360) }

    override func draw() {
        background(Color(hex: 0x10131A))
        noStroke()
        for band in 0..<32 {
            fill(Color(hue: Double(band) / 32, saturation: 0.6, brightness: 0.9))
            drawRect(Double(band) * 20, 300, 20, 60)
        }
        stroke(Color(hex: 0xF2EBDD))
        strokeWeight(1)
        for line in 0..<24 {
            let x = Double(line) * 13 + 20
            drawLine(x, 20, x + 40, 120)
        }
        noStroke()
        for disc in 0..<6 {
            let phase = Double(frameCount) * 0.08 + Double(disc)
            fill(Color(hue: Double(disc) / 6, saturation: 0.8, brightness: 1))
            drawCircle(360 + cos(phase) * 180, 190 + sin(phase * 1.3) * 80, 26)
        }
    }
}

/// The picture path end to end, on this Mac: a rendered frame goes into the same
/// compressor the live screen uses, over the wire codec in uneven chunks, into
/// the same sample-buffer rebuild the phone runs, through a decoder, and is
/// compared with the frame it started as.
///
/// It uses the media engine's decoder, so it runs in the device phase
/// (`Scripts/test.sh`), beside the other suite that reads video back.
@MainActor
@Suite struct PhonePictureRoundTripTests {

    /// What the probe draws over a run of frames, as BGRA bytes.
    private func renderFrames(_ count: Int) throws -> [Bytes] {
        let sketch = PictureProbe()
        return try (0..<count).map { frame in
            let image = try #require(OllinApp.image(of: sketch, frame: frame))
            return try #require(Bytes(image))
        }
    }

    @Test func renderedFramesSurviveTheCable() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let frames = try renderFrames(24)
        let pictures = try encode(frames, on: device, forcingKeyframesAt: [0, 12])
        #expect(pictures.count == frames.count)

        // The first picture stands alone and carries the three parameter sets a
        // decoder is built from; so does the one the Mac forced midway, which is
        // what the phone gets after a reconnect.
        #expect(pictures.first?.isKeyframe == true)
        #expect(pictures.first?.parameterSets.count == 3)
        #expect(pictures[12].isKeyframe)
        #expect(pictures.filter(\.isKeyframe).count == 2)
        #expect(pictures.allSatisfy { $0.width == 640 && $0.height == 360 })

        let received = try throughTheWire(pictures)
        #expect(received == pictures)

        let decoded = try decode(received)
        #expect(decoded.count == frames.count)
        for (index, picture) in decoded.enumerated() {
            let error = frames[index].meanError(against: picture)
            #expect(error < 2.5, "frame \(index) is \(error) levels off on average")
            #expect(frames[index].psnr(against: picture) > 36, "frame \(index)")
        }

        // The tolerance has to be able to fail: a decoded frame compared against a
        // frame the discs had moved on from is far outside it.
        #expect(frames[20].meanError(against: decoded[4]) > 2.5 * 2)
    }

    @Test func aPhoneJoiningMidStreamWaitsForAKeyframe() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let frames = try renderFrames(16)
        let pictures = try encode(frames, on: device, forcingKeyframesAt: [0, 8])

        // Nothing before a keyframe can be built: there is no format to build on.
        var format: PhonePictureFormat?
        #expect(pictures[3].sampleBuffer(reusing: &format) == nil)
        #expect(format == nil)

        // From the forced keyframe on, the stream decodes and matches.
        let decoded = try decode(Array(pictures[8...]))
        #expect(decoded.count == 8)
        for (offset, picture) in decoded.enumerated() {
            #expect(frames[8 + offset].meanError(against: picture) < 2.5)
        }
    }

    @Test func theFormatIsBuiltOnceWhileTheParameterSetsHold() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let pictures = try encode(try renderFrames(10), on: device, forcingKeyframesAt: [0, 5])
        var format: PhonePictureFormat?
        _ = pictures[0].sampleBuffer(reusing: &format)
        let first = try #require(format?.description)
        _ = pictures[5].sampleBuffer(reusing: &format)
        #expect(format?.description === first)
        let size = CMVideoFormatDescriptionGetDimensions(first)
        #expect(size.width == 640 && size.height == 360)
    }

    @Test func theScreenCarriesWhatItDrawsDownTheCable() async throws {
        let gpu = try #require(MTLCreateSystemDefaultDevice())
        let frames = try renderFrames(12)

        // One end of a socket pair stands in for the tunnel, so the sender's own
        // thread, framing, and keyframe rule run with no phone and no network.
        var pair: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        let macEnd = pair[0], phoneEnd = pair[1]
        let dialed = OSAllocatedUnfairLock(initialState: false)
        let sender = PhonePictureSender(connect: { _ in
            let first = dialed.withLock { was -> Bool in defer { was = true }; return !was }
            guard first else { throw CancellationError() }
            return macEnd
        })
        let screen = PhoneScreen(device: PhoneDevice(), frameRate: 1000, sender: sender,
                                 phoneMode: { .sketch })
        let sketch = PictureProbe()

        // The phone's end, read on a thread of its own the way the app's server
        // reads: chunks into a buffer, whole requests out of it.
        let received = OSAllocatedUnfairLock(initialState: [PhonePicture]())
        Thread.detachNewThread {
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 1 << 16)
            while true {
                let count = read(phoneEnd, &chunk, chunk.count)
                guard count > 0 else { break }
                buffer.append(contentsOf: chunk[0..<count])
                guard let requests = PhoneWire.takeRequests(from: &buffer) else { break }
                let pictures = requests.compactMap { request -> PhonePicture? in
                    if case .picture(let picture) = request { return picture } else { return nil }
                }
                received.withLock { $0 += pictures }
            }
            close(phoneEnd)
        }

        // The sender dials only once a drawn frame wants it; one that dialed on
        // its own would have done so the moment its thread started.
        try await Task.sleep(for: .milliseconds(150))
        #expect(!dialed.withLock { $0 })
        screen.beforeDraw(sketch)
        try await waitUntil { sender.isConnected }

        for frame in frames {
            screen.beforeDraw(sketch)
            try await waitUntil { screen.wantsRenderedTexture }
            screen.frameRendered(sketch, texture: try #require(frame.texture(on: gpu)))
            // While that picture is being made or waits to go, the next is not asked for.
            #expect(!screen.wantsRenderedTexture)
        }
        try await waitUntil { received.withLock { $0.count } == frames.count }
        #expect(screen.isShowing)

        let pictures = received.withLock { $0 }
        #expect(pictures.first?.isKeyframe == true)
        #expect(pictures.dropFirst().allSatisfy { !$0.isKeyframe })
        let decoded = try decode(pictures)
        #expect(decoded.count == frames.count)
        for (index, picture) in decoded.enumerated() {
            #expect(frames[index].meanError(against: picture) < 2.5, "frame \(index)")
        }

        screen.stop()
        try await waitUntil { !sender.isConnected }
        #expect(!screen.isShowing)
    }

    /// Probe first, then read the clock, so a test resumed late still looks once.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while true {
            if condition() { return }
            guard Date() < deadline else {
                Issue.record("the condition never held")
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: The path

    private func encode(_ frames: [Bytes], on device: MTLDevice,
                        forcingKeyframesAt keys: Set<Int>) throws -> [PhonePicture] {
        let collected = OSAllocatedUnfairLock(initialState: [PhonePicture]())
        let encoder = try #require(PhonePictureEncoder(device: device, framesPerSecond: 30) { picture in
            collected.withLock { $0.append(picture) }
        })
        for (index, frame) in frames.enumerated() {
            let texture = try #require(frame.texture(on: device))
            #expect(encoder.encode(texture, forceKeyframe: keys.contains(index)))
        }
        encoder.finish()
        #expect(encoder.inFlight == 0)
        return collected.withLock { $0 }
    }

    /// Every picture framed as a request, the frames joined, and the bytes fed
    /// back in chunks that cut through headers and payloads alike.
    private func throughTheWire(_ pictures: [PhonePicture]) throws -> [PhonePicture] {
        let stream = pictures.map { PhoneWire.encode(.picture($0)) }.reduce(Data(), +)
        var buffer = Data()
        var received: [PhonePicture] = []
        var offset = 0
        var step = 7
        while offset < stream.count {
            let end = min(stream.count, offset + step)
            buffer.append(stream[offset..<end])
            offset = end
            step = step * 3 % 4093 + 1
            let requests = try #require(PhoneWire.takeRequests(from: &buffer))
            for case .picture(let picture) in requests { received.append(picture) }
        }
        #expect(buffer.isEmpty)
        return received
    }

    private func decode(_ pictures: [PhonePicture]) throws -> [CVPixelBuffer] {
        var format: PhonePictureFormat?
        var session: VTDecompressionSession?
        let decoded = OSAllocatedUnfairLock(uncheckedState: [CVPixelBuffer]())
        defer { if let session { VTDecompressionSessionInvalidate(session) } }
        for picture in pictures {
            let sample = try #require(picture.sampleBuffer(reusing: &format))
            if session == nil {
                let attributes: [CFString: Any] = [
                    kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                ]
                var made: VTDecompressionSession?
                let status = VTDecompressionSessionCreate(
                    allocator: kCFAllocatorDefault, formatDescription: try #require(format).description,
                    decoderSpecification: nil, imageBufferAttributes: attributes as CFDictionary,
                    outputCallback: nil, decompressionSessionOut: &made)
                #expect(status == noErr)
                session = made
            }
            let status = VTDecompressionSessionDecodeFrame(
                try #require(session), sampleBuffer: sample, flags: [], infoFlagsOut: nil
            ) { status, _, image, _, _ in
                guard status == noErr, let image else { return }
                decoded.withLockUnchecked { $0.append(image) }
            }
            #expect(status == noErr)
        }
        if let session { VTDecompressionSessionWaitForAsynchronousFrames(session) }
        return decoded.withLockUnchecked { $0 }
    }
}

/// A frame as tightly packed BGRA bytes, eight bits a channel, alpha ignored.
private struct Bytes {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: info)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = buffer
    }

    /// The frame as the renderer hands it to an extension: display-ready sRGB bytes.
    func texture(on device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .pixelFormatView]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        pixels.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: width * 4)
        }
        return texture
    }

    /// Mean absolute difference over the color channels, in eight-bit levels.
    func meanError(against buffer: CVPixelBuffer) -> Double {
        let (sum, count) = differences(against: buffer) { abs($0) }
        return count == 0 ? .infinity : sum / Double(count)
    }

    /// Peak signal to noise, in decibels, over the color channels.
    func psnr(against buffer: CVPixelBuffer) -> Double {
        let (sum, count) = differences(against: buffer) { $0 * $0 }
        guard count > 0 else { return 0 }
        let mse = sum / Double(count)
        return mse == 0 ? .infinity : 10 * log10(255 * 255 / mse)
    }

    private func differences(against buffer: CVPixelBuffer,
                             _ measure: (Double) -> Double) -> (Double, Int) {
        guard CVPixelBufferGetWidth(buffer) == width, CVPixelBufferGetHeight(buffer) == height,
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return (0, 0) }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self)
        else { return (0, 0) }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var sum = 0.0, count = 0
        for y in 0..<height {
            for x in 0..<width {
                for channel in 0..<3 {
                    let decoded = Double(base[y * rowBytes + x * 4 + channel])
                    let source = Double(pixels[(y * width + x) * 4 + channel])
                    sum += measure(decoded - source)
                    count += 1
                }
            }
        }
        return (sum, count)
    }
}
