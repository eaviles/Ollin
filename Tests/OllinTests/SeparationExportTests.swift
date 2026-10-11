import Testing
import CoreGraphics
import ImageIO
import Foundation
@testable import Ollin

/// The print-separation export as a file writer (`PrintSeparationTests`
/// covers the separation itself): one master per ink, named by the ink in print order, plus the overprint
/// preview; the margin band with registration targets in black when asked
/// for and the bare picture when not; and the sentence it throws when no
/// inks are named.
@Suite
@MainActor
struct SeparationExportTests {

    private func png(_ path: String) throws -> Pixels {
        let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
        return Pixels(try #require(CGImageSourceCreateImageAtIndex(source, 0, nil)))
    }

    @Test func oneMasterPerInkAndAPreview() throws {
        let stem = ollinTempPath("separations-\(UUID().uuidString)")
        try OllinApp.exportSeparations(TwoInks(), to: stem + ".png", drawsRegistrationMarks: false)
        let blue = try png(stem + "-1-blue.png")
        let yellow = try png(stem + "-2-yellow.png")
        let preview = try png(stem + "-preview.png")
        for sheet in [blue, yellow, preview] {
            #expect(sheet.width == 64 && sheet.height == 64)
        }
        // The left half is the blue ink, the right half the yellow, the band
        // across the bottom bare paper: black is full ink in a master.
        #expect(blue.gray(10, 20) < 20 && yellow.gray(10, 20) > 235)
        #expect(yellow.gray(50, 20) < 20 && blue.gray(50, 20) > 235)
        #expect(blue.gray(30, 58) > 235 && yellow.gray(30, 58) > 235)
        // The preview is the inks laid over the paper: blue reads blue.
        #expect(preview.channel(2, 10, 20) > preview.channel(0, 10, 20) + 80)
        for path in [stem + "-1-blue.png", stem + "-2-yellow.png", stem + "-preview.png"] {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    @Test func theMarksBandFramesEveryFileTheSame() throws {
        let stem = ollinTempPath("separations-marked-\(UUID().uuidString)")
        try OllinApp.exportSeparations(TwoInks(), to: stem + ".png")
        let paths = [stem + "-1-blue.png", stem + "-2-yellow.png", stem + "-preview.png"]
        let sheets = try paths.map(png)
        // A 64-pixel picture takes the 24-pixel minimum band on every side.
        for sheet in sheets {
            #expect(sheet.width == 112 && sheet.height == 112)
        }
        // The targets in the corners print in black on every file, and the
        // band between them is white.
        func inked(_ sheet: Pixels, _ x0: Int, _ y0: Int) -> Int {
            var count = 0
            for y in y0 ..< y0 + 24 { for x in x0 ..< x0 + 24 where sheet.gray(x, y) < 64 { count += 1 } }
            return count
        }
        for sheet in sheets {
            for (x, y) in [(0, 0), (88, 0), (0, 88)] {
                #expect(inked(sheet, x, y) > 10, "a corner at (\(x), \(y)) has no target")
            }
            #expect(sheet.gray(56, 4) > 235, "the band between the targets is inked")
        }
        // The picture sits inside the band, unmoved: blue's left half is ink.
        #expect(sheets[0].gray(24 + 10, 24 + 20) < 20)
        for path in paths { try? FileManager.default.removeItem(atPath: path) }
    }

    @Test func noInksIsSaidAndWritesNothing() throws {
        let stem = ollinTempPath("separations-none-\(UUID().uuidString)")
        let sketch = TwoInks()
        sketch.declaresInks = false
        #expect(throws: ExportError.self) {
            try OllinApp.exportSeparations(sketch, to: stem + ".png")
        }
        do {
            try OllinApp.exportSeparations(sketch, to: stem + ".png")
        } catch let error as ExportError {
            #expect(error.description.contains("printInks"), Comment(rawValue: error.description))
        }
        #expect(!FileManager.default.fileExists(atPath: stem + "-preview.png"))
    }

    @Test func aLayerFileIsNamedByItsInk() {
        #expect(OllinApp.layerPath(stem: "art", index: 1, ink: .fluorescentPink) == "art-2-fluorescent-pink.png")
        #expect(OllinApp.layerPath(stem: "a/b", index: 0, ink: Ink(name: "Marine Red", color: .red)) == "a/b-1-marine-red.png")
    }
}

/// The blue ink's color on the left, the yellow's on the right, paper along
/// the bottom.
@MainActor
private final class TwoInks: Sketch {
    var declaresInks = true
    override var printInks: [Ink]? { declaresInks ? [.blue, .yellow] : nil }
    override var canvasSize: CanvasSize { .square(64) }
    override func draw() {
        background(.white)
        noStroke()
        fill(Ink.blue.color)
        drawRect(0, 0, 32, 50)
        fill(Ink.yellow.color)
        drawRect(32, 0, 32, 50)
    }
}
