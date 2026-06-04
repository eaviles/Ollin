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
