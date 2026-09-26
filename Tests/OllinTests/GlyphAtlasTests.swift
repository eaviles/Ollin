import CoreGraphics
import CoreText
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

    // MARK: A full page

    /// A page that fills while its face is already on it is rebuilt, and the
    /// glyph that filled it is kept on the new page. The lookup used to hold an
    /// index into the faces from before the rebuild, which the rebuild had
    /// emptied: a crash the first time a long run of text filled a page, which
    /// `SoakTests` found.
    @Test func aPageThatFillsIsRebuiltUnderTheFaceThatFilledIt() throws {
        let atlas = GlyphAtlas()
        let font = CTFontCreateUIFontForLanguage(.system, 1, nil)!
        let glyphs = CTFontGetGlyphCount(font)
        var glyph: CGGlyph = 1
        while atlas.generation == 0, Int(glyph) < glyphs {
            _ = atlas.slot(for: glyph, font: font)
            glyph += 1
        }
        try #require(atlas.generation == 1, "the system face holds more glyphs than one page")
        let filler = glyph - 1
        #expect(atlas.glyphCount == 1, "the rebuilt page holds the glyph that filled the old one")
        #expect(atlas.slot(for: filler, font: font) != nil)
        #expect(atlas.glyphCount == 1 && atlas.generation == 1, "and a second ask finds it rather than making it again")
    }

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

    // MARK: Runs

    /// Text set one character at a time is one run, so one draw call: the quads
    /// carry their own color and size, and only the atlas and the pass state split
    /// the run. Without it, a sketch that places every character in a cell of its
    /// own makes a draw call per character, and four sheets of 16,000 cells take
    /// 125 ms a frame to encode.
    @Test @MainActor
    func characterAtATimeTextIsOneRun() {
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.textFont(OutlineFont.systemMono)
        drawer.textSize(12)
        drawer.textRenderMode = .atlas
        for (i, mark) in "HOX#=-".enumerated() {
            drawer.fill(Color(white: Double(i) / 8))      // a color per character
            drawer.textSize(10 + Double(i))               // and a size per character
            drawer.drawText(String(mark), 10 + 12 * Double(i), 20)
        }
        #expect(drawer.batches.map(\.kind) == [.glyphAtlas])
        #expect(drawer.glyphVertices.count == 6 * 6)

        // Anything drawn between two calls, a new blend, or another font's
        // atlas splits the run, and draw order is kept.
        drawer.drawCircle(50, 50, 4)
        drawer.drawText("A", 60, 20)
        drawer.blendMode(.add)
        drawer.drawText("B", 70, 20)
        drawer.textFont(OutlineFont.system)
        drawer.drawText("C", 80, 20)
        #expect(drawer.batches.map(\.kind) == [.glyphAtlas, .sdf, .glyphAtlas, .glyphAtlas, .glyphAtlas])
    }

    /// Merging runs changes nothing on the canvas: the same characters drawn one
    /// call each and as one string at the same pen positions render identically.
    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    @MainActor
    func mergedRunsRenderAsTheyDidOneByOne() throws {
        let apart = CellText(); apart.oneCallPerCharacter = true
        let whole = CellText(); whole.oneCallPerCharacter = false
        guard let a = OllinApp.image(of: apart), let w = OllinApp.image(of: whole) else {
            Issue.record("off-screen render failed"); return
        }
        let diff = try #require(GlyphAtlasTests.meanDifference(a, w))
        #expect(diff < 0.05, "one call per character vs one string, mean difference \(diff)")
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

/// A line of monospaced characters, drawn either one call per character at its
/// own pen position or as one string, for the run-merging parity test.
private final class CellText: Sketch {
    var oneCallPerCharacter = false
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        fill(.black)
        textFont(OutlineFont.systemMono)
        textMode(.atlas)
        textAlign(.left, .baseline)
        textSize(18)
        let line = "HOX#=-HOX#=-"
        if oneCallPerCharacter {
            let advance = textWidth("H")
            for (i, mark) in line.enumerated() {
                drawText(String(mark), 16 + Double(i) * advance, 100)
            }
        } else {
            drawText(line, 16, 100)
        }
    }
}
