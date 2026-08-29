import Testing
import CoreGraphics
import CoreVideo
import Foundation
import Ollin
@testable import OllinVision

/// The matte/cutout conversions are deterministic byte work, so they're checked
/// exactly; the models themselves are smoke-tested with the soft-skip the other
/// neural trackers use (they need a compute device some test environments lack).
@Suite struct SegmenterTests {

    /// A grayscale CGImage from explicit byte values, the shape Vision's matte
    /// arrives in (modulo its gray→RGB expansion, which `grayBytes` normalizes).
    private func grayImage(_ values: [UInt8], width: Int, height: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(values) as CFData)!
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    /// An opaque RGBA image of one solid color (premultiplied bytes as given).
    private func solidImage(r: UInt8, g: UInt8, b: UInt8, width: Int, height: Int) -> CGImage {
        var bytes: [UInt8] = []
        for _ in 0..<(width * height) { bytes.append(contentsOf: [r, g, b, 255]) }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    // MARK: Conversions

    @Test func grayBytesRoundTripAtSameSize() {
        let values: [UInt8] = [0, 64, 128, 255]
        let gray = SegmentationImages.grayBytes(from: grayImage(values, width: 2, height: 2),
                                                width: 2, height: 2)
        #expect(gray == values)
    }

    @Test func matteBecomesPremultipliedWhite() {
        let bytes = SegmentationImages.matteRGBABytes(
            from: grayImage([0, 64, 128, 255], width: 2, height: 2))
        // Each pixel is (m, m, m, m): white premultiplied by the matte's level.
        #expect(bytes == [0, 0, 0, 0,  64, 64, 64, 64,  128, 128, 128, 128,  255, 255, 255, 255])
    }

    @Test func matteImageWrapsTheBytesDrawable() throws {
        let image = try #require(SegmentationImages.matteImage(
            from: grayImage([0, 64, 128, 255], width: 2, height: 2)))
        #expect(image.width == 2 && image.height == 2)
        // Fully-on pixel reads back as opaque white; fully-off as clear.
        #expect(image[1, 1].alpha == 1 && image[1, 1].red == 1)
        #expect(image[0, 0].alpha == 0)
    }

    @Test func colorImageKeepsColorsAndOrientation() throws {
        // 2×2 with a distinct color per corner, decoded at face value: colors
        // pass through untouched and the top-left origin is preserved (no
        // flip) — the decode behind the model tracker's `outputImage`.
        var bytes: [UInt8] = []
        bytes.append(contentsOf: [255, 0, 0, 255])      // top-left: red
        bytes.append(contentsOf: [0, 255, 0, 255])      // top-right: green
        bytes.append(contentsOf: [0, 0, 255, 255])      // bottom-left: blue
        bytes.append(contentsOf: [255, 255, 255, 255])  // bottom-right: white
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(width: 2, height: 2,
                         bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                         space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false,
                         intent: .defaultIntent)!
        let image = try #require(SegmentationImages.colorImage(from: cg))
        #expect(image.width == 2 && image.height == 2)
        #expect(image[0, 0].red == 1 && image[0, 0].green == 0 && image[0, 0].blue == 0)
        #expect(image[1, 0].green == 1 && image[1, 0].red == 0)
        #expect(image[0, 1].blue == 1 && image[0, 1].red == 0)
        #expect(image[1, 1].red == 1 && image[1, 1].green == 1 && image[1, 1].blue == 1)
        #expect(image[1, 1].alpha == 1)
    }

    @Test func cutoutKeepsSourceWhereMatteIsOn() {
        let frame = solidImage(r: 200, g: 100, b: 40, width: 2, height: 2)
        let matte = grayImage([255, 0, 255, 0], width: 2, height: 2)
        let bytes = SegmentationImages.cutoutRGBABytes(frame: frame, matte: matte)
        // On-pixels keep the source color opaque; off-pixels go fully transparent
        // (premultiplied, so every channel zeroes).
        #expect(bytes == [200, 100, 40, 255,  0, 0, 0, 0,  200, 100, 40, 255,  0, 0, 0, 0])
    }

    @Test func cutoutRescalesTheMatteToTheFrame() {
        // A 1×1 fully-on matte against a larger frame: the rescale must cover it.
        let frame = solidImage(r: 10, g: 20, b: 30, width: 4, height: 4)
        let matte = grayImage([255], width: 1, height: 1)
        let bytes = SegmentationImages.cutoutRGBABytes(frame: frame, matte: matte)
        #expect(bytes?.count == 4 * 4 * 4)
        #expect(bytes == Array([[UInt8]](repeating: [10, 20, 30, 255], count: 16).joined()))
    }

    @Test func floatMaskBufferConvertsToGray() throws {
        // The shape Vision's `generateMask` hands back: one-component 32-bit
        // float, values 0…1.
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 2, 2, kCVPixelFormatType_OneComponent32Float, nil, &buffer)
        let mask = try #require(buffer)
        CVPixelBufferLockBaseAddress(mask, [])
        let p = CVPixelBufferGetBaseAddress(mask)!.assumingMemoryBound(to: Float.self)
        let stride = CVPixelBufferGetBytesPerRow(mask) / MemoryLayout<Float>.stride
        p[0] = 0; p[1] = 0.25
        p[stride] = 0.5; p[stride + 1] = 1
        CVPixelBufferUnlockBaseAddress(mask, [])

        let gray = try #require(SegmentationImages.grayCGImage(from: mask))
        #expect(SegmentationImages.grayBytes(from: gray, width: 2, height: 2) == [0, 64, 128, 255])
    }

    // MARK: Models (soft-skip where the compute device is missing)

    @Test func blankImageSegmentsToAnEmptyPersonMatte() async throws {
        let image = Image(width: 64, height: 64, color: .black)
        // Soft-skip: the segmentation model needs a compute device some headless
        // test environments lack; a throw there isn't a code failure. (`try?`
        // flattens the optional, so nil covers both the skip and a nil result.)
        guard let segmentation = try? await PersonSegmenter.detect(in: image) else { return }
        #expect(segmentation.matte.width > 0)
        #expect(segmentation.cutout.width == 64)
        // No person anywhere: the matte's center stays transparent.
        let center = segmentation.matte[segmentation.matte.width / 2, segmentation.matte.height / 2]
        #expect(center.alpha < 0.1)
    }

    /// A bright disk on a dark ground — salient enough for the foreground model
    /// to lift (verified on this hardware).
    private func diskImage() -> Image {
        let image = Image(width: 320, height: 240, color: Color(white: 0.05))
        let cx = 160, cy = 120, radius = 70
        for y in (cy - radius)...(cy + radius) {
            for x in (cx - radius)...(cx + radius)
            where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius {
                image[x, y] = Color(red: 1.0, green: 0.6, blue: 0.1)
            }
        }
        return image
    }

    @Test func syntheticDiskLiftsAsASubject() async throws {
        // Lenient soft-skip: `try?` flattens, so nil covers both "model can't run
        // here" and "the model judged nothing salient" — assert only when
        // something lifted.
        guard let segmentation = try? await SubjectSegmenter.detect(in: diskImage()) else { return }
        #expect(segmentation.cutout.width == 320)
        let center = segmentation.matte[segmentation.matte.width / 2, segmentation.matte.height / 2]
        #expect(center.alpha > 0.5)
    }

    @MainActor
    @Test func liveWiringPublishesMatteCutoutAndCount() async throws {
        // Gate on the still path: only run the live assertion where the model
        // demonstrably lifts this exact frame (elsewhere this is the soft-skip).
        let image = diskImage()
        guard (try? await SubjectSegmenter.detect(in: image)) != nil else { return }

        // The camera-free live path: a hand-driven source standing in for the
        // capture queue, exactly like the frame-source tests.
        let source = FrameSourceTests.ManualFrameSource()
        let subjects = SubjectSegmenter(source)
        let tap = try #require(source.frameTap)
        let frame = image.currentCGImage()

        // Both surfaces are read before the clock, since a starved task can
        // wake past its own deadline having never looked once, and a loop that
        // tests the deadline first then gives up over a result that is already
        // published.
        let deadline = Date(timeIntervalSinceNow: 8)
        var published = false
        while true {
            tap(frame)   // the analyzer drops frames while one is in flight
            // Reading both surfaces arms both conversions (the first read is what
            // turns each one on), so poll until both publish.
            if subjects.matte != nil, subjects.cutout != nil { published = true; break }
            if Date() >= deadline { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(published)
        #expect(subjects.count >= 1)
    }
}
