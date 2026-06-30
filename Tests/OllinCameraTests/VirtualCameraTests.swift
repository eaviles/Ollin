import Testing
import CoreMedia
import CoreVideo
import Foundation
import Metal
@testable import OllinCamera

/// The publish client's testable surface: the connection failure path (always
/// on — no camera required), the GPU letterbox pass (gated on a Metal device),
/// and a real end-to-end push when the Ollin Camera extension is installed
/// (soft-skips where it isn't, e.g. CI).
@Suite(.timeLimit(.minutes(1))) struct VirtualCameraTests {

    static var hasMetal: Bool { MTLCreateSystemDefaultDevice() != nil }

    /// Always-on: connecting to a camera that doesn't exist must fail cleanly,
    /// with the user-actionable install hint.
    @Test func missingDeviceFailsCleanly() {
        switch SinkConnection.connect(toDeviceNamed: "No Such Ollin Camera \(UUID().uuidString.prefix(8))") {
        case .success:
            Issue.record("Connected to a camera that shouldn't exist.")
        case .failure(let error):
            guard case .deviceNotFound = error else {
                Issue.record("Expected .deviceNotFound, got \(error).")
                return
            }
            #expect(error.description.contains("OllinCamera.app"))
        }
    }

    /// GPU-gated: the converter letterboxes a portrait canvas into the fixed
    /// camera frame — source bytes pass through unchanged in the picture area,
    /// pillarbox bars are opaque black.
    @Test(.enabled(if: VirtualCameraTests.hasMetal))
    func converterLetterboxesAndPassesBytesThrough() throws {
        let device = MTLCreateSystemDefaultDevice()!
        let converter = try #require(FrameConverter(device: device))

        // A portrait source in a known sRGB byte color (BGRA in memory).
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: 100, height: 200, mipmapped: false)
        descriptor.usage = [.shaderRead, .pixelFormatView]
        let source = try #require(device.makeTexture(descriptor: descriptor))
        let pixel: [UInt8] = [0, 128, 255, 255]   // orange: B 0, G 128, R 255
        var fill = [UInt8](repeating: 0, count: 100 * 200 * 4)
        for i in stride(from: 0, to: fill.count, by: 4) { fill.replaceSubrange(i..<i + 4, with: pixel) }
        source.replace(region: MTLRegionMake2D(0, 0, 100, 200), mipmapLevel: 0,
                       withBytes: fill, bytesPerRow: 100 * 4)

        let sampleBuffer = try #require(converter.makeSampleBuffer(from: source))
        let imageBuffer = try #require(CMSampleBufferGetImageBuffer(sampleBuffer))
        #expect(CVPixelBufferGetWidth(imageBuffer) == FrameConverter.width)
        #expect(CVPixelBufferGetHeight(imageBuffer) == FrameConverter.height)

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
        let base = try #require(CVPixelBufferGetBaseAddress(imageBuffer))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        func bgra(_ x: Int, _ y: Int) -> [UInt8] {
            let p = base.advanced(by: y * bytesPerRow + x * 4).assumingMemoryBound(to: UInt8.self)
            return [p[0], p[1], p[2], p[3]]
        }
        // Center: the source color, byte-for-byte (constant color, so the
        // bilinear sample can't blend anything else in).
        #expect(bgra(FrameConverter.width / 2, FrameConverter.height / 2) == pixel)
        // Corner: pillarbox bar, opaque black (a 1:2 portrait can't reach the
        // 16:9 frame's left edge).
        #expect(bgra(2, FrameConverter.height / 2) == [0, 0, 0, 255])
    }

    /// Soft-gated end-to-end: when the Ollin Camera extension is installed (a
    /// dev Mac with the device half set up), connect to its sink stream and
    /// hand it one real frame. Where the device doesn't exist (CI), the
    /// connect fails with `.deviceNotFound` and the test records a skip-style
    /// pass instead.
    @Test func publishesToInstalledCamera() throws {
        switch SinkConnection.connect(toDeviceNamed: "Ollin Camera") {
        case .failure(.deviceNotFound):
            // Not installed here — nothing to assert against.
            return
        case .failure(let error):
            Issue.record("The camera exists but connecting failed: \(error).")
        case .success(let connection):
            var pixelBufferOut: CVPixelBuffer?
            let attributes: [String: Any] = [
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
            ]
            CVPixelBufferCreate(kCFAllocatorDefault, FrameConverter.width, FrameConverter.height,
                                kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBufferOut)
            let pixelBuffer = try #require(pixelBufferOut)
            var formatDescription: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDescription)
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 30),
                presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                decodeTimeStamp: .invalid)
            var sampleBufferOut: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                formatDescription: try #require(formatDescription), sampleTiming: &timing,
                sampleBufferOut: &sampleBufferOut)
            #expect(connection.enqueue(try #require(sampleBufferOut)))
        }
    }
}
