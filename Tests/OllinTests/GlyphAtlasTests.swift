import CoreGraphics
import Foundation
import Metal
import Testing
@testable import Ollin

/// Tests for the SDF glyph atlas behind `textMode(.atlas)`.
///
/// The signed-distance generation is pure CPU and deterministic, so it's checked
/// directly (no GPU). The end-to-end render is checked for *parity* with the
/// outline path rather than against a committed reference — both paths use
/// whatever system font is present, so comparing them stays robust across
/// machines and macOS versions (the system font's exact outlines aren't fixed).
@Suite
struct GlyphAtlasTests {

    // MARK: Signed distance field (deterministic, no GPU)

    /// A vertical edge: the left half outside, the right half inside. Across the
    /// boundary the field must rise through `0.5` (128) — below it just outside,
    /// above it just inside — and saturate to 0 / 1 far from the edge.
    @Test
    func signedDistanceFieldCrossesHalfAtTheEdge() {
        let w = 32, h = 8, mid = w / 2, spread = 4
        var coverage = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { for x in mid..<w { coverage[y * w + x] = 255 } }

        let sdf = GlyphAtlas.signedDistanceField(coverage: coverage, width: w, height: h, spread: spread)
        let row = 4
        func v(_ x: Int) -> Int { Int(sdf[row * w + x]) }

        #expect(v(mid) > 128)        // first inside texel
        #expect(v(mid - 1) < 128)    // last outside texel
        #expect(v(w - 1) == 255)     // deep inside saturates
        #expect(v(0) == 0)           // deep outside saturates
        // Monotonic non-decreasing left → right across the boundary band.
        for x in (mid - spread)..<(mid + spread) { #expect(v(x) <= v(x + 1)) }
    }

    /// Degenerate masks don't crash and saturate the whole field the right way.
    @Test
    func signedDistanceFieldHandlesAllInsideOrOutside() {
        let w = 16, h = 16
        let allIn = GlyphAtlas.signedDistanceField(
            coverage: [UInt8](repeating: 255, count: w * h), width: w, height: h, spread: 4)
        let allOut = GlyphAtlas.signedDistanceField(
            coverage: [UInt8](repeating: 0, count: w * h), width: w, height: h, spread: 4)
        #expect(allIn.allSatisfy { $0 == 255 })
        #expect(allOut.allSatisfy { $0 == 0 })
    }

    // MARK: Render parity with the outline path

    /// The atlas path should reproduce outline text closely. Render the same text
    /// once with `textMode(.outline)` and once with `.atlas` and require a small
    /// mean per-channel difference — the two only diverge on anti-aliased edges
    /// (SDF coverage vs MSAA), which are a small fraction of a mostly-white frame.
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    @MainActor
    func atlasTextMatchesOutlineText() throws {
        let outline = ParityText(); outline.useAtlas = false
        let atlas = ParityText(); atlas.useAtlas = true
        guard let o = OllinApp.image(of: outline), let a = OllinApp.image(of: atlas) else {
            Issue.record("off-screen render failed"); return
        }
        let diff = try #require(GlyphAtlasTests.meanDifference(o, a))
        #expect(diff < 6.0, "atlas vs outline mean per-channel difference \(diff)")
    }

    /// Mean per-channel absolute difference (0…255) between two same-size images.
    private static func meanDifference(_ x: CGImage, _ y: CGImage) -> Double? {
        guard let bx = rgba(x), let by = rgba(y), bx.count == by.count, !bx.isEmpty else { return nil }
        var total = 0
        for i in bx.indices { total += abs(Int(bx[i]) - Int(by[i])) }
        return Double(total) / Double(bx.count)
    }

    /// An image's pixels in a tightly-packed RGBA8 buffer.
    private static func rgba(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let ptr = ctx.data else { return nil }
        return Array(UnsafeRawBufferPointer(start: ptr, count: w * h * 4))
    }
}

/// Black text on white, drawn through whichever path `useAtlas` selects, so the
/// two renders can be diffed for parity.
private final class ParityText: Sketch {
    var useAtlas = false
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        fill(.black)
        textFont(.system)
        textMode(useAtlas ? .atlas : .outline)
        textAlign(.left, .top)
        textSize(22)
        drawText("Atlas vs", 16, 24)
        drawText("outline 0123", 16, 58)
        textSize(40)
        drawText("Aa Bb", 16, 104)
    }
}
