import CoreGraphics
import Foundation
import Ollin
import Testing

/// CPU-side tests for `Image` pixel access (`subscript`) and the blank
/// initializer. These touch no GPU — get/set work on the decoded bytes — so they
/// run everywhere, including a GPU-less CI runner.
@Suite
struct ImageTests {

    /// Build a known 2×2 image from raw top-down bytes and read its corners, which
    /// pins the get/set coordinate convention: `(0, 0)` is the top-left, matching
    /// how the image draws.
    @Test func pixelGetMatchesTopLeftOrigin() throws {
        // Row 0 (top): red, green. Row 1 (bottom): blue, white. Opaque, so
        // premultiplied == straight and the bytes are exactly the colors.
        let bytes: [UInt8] = [
            255, 0, 0, 255,   0, 255, 0, 255,
            0, 0, 255, 255,   255, 255, 255, 255,
        ]
        let image = Image(cgImage: try knownCGImage(bytes, width: 2, height: 2))

        expectColor(image[0, 0], red: 1, green: 0, blue: 0)   // top-left
        expectColor(image[1, 0], red: 0, green: 1, blue: 0)   // top-right
        expectColor(image[0, 1], red: 0, green: 0, blue: 1)   // bottom-left
        expectColor(image[1, 1], red: 1, green: 1, blue: 1)   // bottom-right
    }

    /// A write reads back as the same color (translucent round-trips within the
    /// 1/255 premultiplied-storage tolerance).
    @Test func pixelSetRoundTrips() {
        let image = Image(width: 4, height: 4)
        image[2, 1] = Color(red: 0.2, green: 0.6, blue: 0.9)
        expectColor(image[2, 1], red: 0.2, green: 0.6, blue: 0.9)

        image[0, 0] = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        let c = image[0, 0]
        #expect(abs(c.red - 1) < 0.02)
        #expect(abs(c.alpha - 0.5) < 0.01)
    }

    /// A blank image starts filled with its `color` (transparent by default).
    @Test func blankImageStartsFilled() {
        let clear = Image(width: 3, height: 3)
        expectColor(clear[0, 0], red: 0, green: 0, blue: 0)
        #expect(clear[0, 0].alpha == 0)

        let filled = Image(width: 3, height: 3, color: Color(red: 0.5, green: 0.25, blue: 0.75))
        expectColor(filled[2, 2], red: 0.5, green: 0.25, blue: 0.75)
        #expect(filled.width == 3 && filled.height == 3)
    }

    /// Out-of-range access is forgiving: reads return `.clear`, writes are ignored.
    @Test func outOfRangeAccessIsSafe() {
        let image = Image(width: 2, height: 2, color: .red)
        #expect(image[-1, 0].alpha == 0)
        #expect(image[5, 5].alpha == 0)
        image[9, 9] = .green   // no-op, no crash
        expectColor(image[0, 0], red: 1, green: 0, blue: 0)
    }

    /// A bitmap-context-made image must render at face value. The texture loader
    /// only honors its sRGB option for ImageIO-backed sources — a context-made
    /// CGImage (a pixel-authored image, a camera frame) comes back in a linear
    /// pixel format holding sRGB bytes and draws washed-out lighter unless
    /// `texture(for:)` rebuilds it; this pins the rebuild.
    @Test(.enabled(if: Snapshot.hasMetal)) @MainActor
    func contextMadeImageRendersAtFaceValue() throws {
        let sketch = ContextImageSketch()
        let rendered = try #require(OllinApp.image(of: sketch))
        let center = Image(cgImage: rendered)[32, 32]

        // The source color comes back as itself, not its washed-out (linear →
        // sRGB re-encoded) double: 0.07 would wash to ~0.29, so a 0.05
        // tolerance cleanly separates the two.
        #expect(abs(center.red - 0.07) < 0.05, "red \(center.red) ≠ 0.07")
        #expect(abs(center.green - 0.08) < 0.05, "green \(center.green) ≠ 0.08")
        #expect(abs(center.blue - 0.11) < 0.05, "blue \(center.blue) ≠ 0.11")
    }

    // MARK: Helpers

    private func expectColor(_ c: Color, red: Double, green: Double, blue: Double,
                             file: StaticString = #filePath, line: UInt = #line) {
        #expect(abs(c.red - red) < 0.02, "red \(c.red) ≠ \(red)")
        #expect(abs(c.green - green) < 0.02, "green \(c.green) ≠ \(green)")
        #expect(abs(c.blue - blue) < 0.02, "blue \(c.blue) ≠ \(blue)")
    }

    /// A CGImage built directly from top-down premultiplied RGBA8 bytes — its row 0
    /// is the top row by construction, so it's an unambiguous orientation anchor.
    private func knownCGImage(_ bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}

/// Draws a bitmap-context-made image of one known color across the canvas, so
/// the render's center pixel reports whether the texture path kept the color.
private final class ContextImageSketch: Sketch {
    override var canvasSize: CanvasSize { .square(64) }

    private lazy var image: Image = {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return Image(cgImage: ctx.makeImage()!)
    }()

    override func draw() {
        background(.white)
        drawImage(image, 0, 0, width, height)
    }
}
