import CoreGraphics
import Foundation
import Ollin
import Testing

/// Checks on the PDF exporter. Like the SVG exporter it replays the CPU vector
/// recording and never touches Metal, so these run everywhere (including CI).
/// PDF is a binary container whose bytes carry a creation date, so instead of
/// asserting on the document text the tests open it with `CGPDFDocument` for
/// structure and rasterize the page to probe pixels: that pins the orientation
/// flip, colors, alpha, transforms, gradients, clipping, and hatching against
/// what a viewer will actually show.
@Suite
@MainActor
struct PDFExportTests {

    /// A 100x100 fixture with known pixel geography: white background, a black
    /// square covering the top-left quadrant (the orientation probe), a
    /// half-alpha red square at bottom-right placed through a transform, and a
    /// skipped raster image at bottom-left.
    final class Fixture: Sketch {
        override var canvasSize: CanvasSize { .square(100) }

        override func draw() {
            background(.white)
            noStroke()
            fill(.black)
            drawRect(0, 0, 50, 50)                    // top-left quadrant

            withState {
                translate(50, 50)                     // bottom-right quadrant
                fill(Color(red: 1, green: 0, blue: 0, alpha: 0.5))
                drawRect(0, 0, 50, 50)
            }

            let blank = Image(width: 4, height: 4, color: .blue)
            drawImage(blank, 10, 80, 8, 8)            // skipped: raster is omitted
        }
    }

    /// Rasterize page 1 of a PDF into straight sRGB bytes (RGBA, rows top-down)
    /// over a white base, so probes read what a viewer shows on paper.
    private func rasterize(_ document: Data, width: Int, height: Int) -> [UInt8] {
        let provider = CGDataProvider(data: document as CFData)!
        let page = CGPDFDocument(provider)!.page(at: 1)!
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let box = page.getBoxRect(.mediaBox)   // scale the page to fill the bitmap
        ctx.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
        ctx.drawPDFPage(page)
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: bytes, count: width * height * 4))
    }

    /// The RGB at a pixel, addressed like the canvas: x right, y down from the
    /// top-left corner.
    private func pixel(_ rgba: [UInt8], _ width: Int, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2]))
    }

    @Test func documentStructure() {
        let data = OllinApp.pdf(of: Fixture())
        #expect(data.starts(with: Array("%PDF".utf8)))
        let doc = CGPDFDocument(CGDataProvider(data: data as CFData)!)
        #expect(doc?.numberOfPages == 1)
        // One canvas pixel is one PDF point.
        #expect(doc?.page(at: 1)?.getBoxRect(.mediaBox) == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    /// A blank sketch on the A4 paper preset.
    final class A4Page: Sketch {
        override var canvasSize: CanvasSize { .a4 }
        override func draw() { background(.white) }
    }

    @Test func paperPresetExportsTrueToSize() {
        // The paper presets are sized in PDF points, so `.a4` comes out as an
        // actual A4 page (595×842 pt at 72 per inch).
        let doc = CGPDFDocument(CGDataProvider(data: OllinApp.pdf(of: A4Page()) as CFData)!)
        #expect(doc?.page(at: 1)?.getBoxRect(.mediaBox) == CGRect(x: 0, y: 0, width: 595, height: 842))
    }

    /// A US Letter page at print resolution: the canvas is 2550×3300 pixels,
    /// with a black square over the top-left quadrant.
    final class PrintResolutionPage: Sketch {
        override var canvasSize: CanvasSize { .usLetter.dpi(300) }
        override func draw() {
            background(.white)
            noStroke()
            fill(.black)
            drawRect(0, 0, width / 2, height / 2)
        }
    }

    @Test func dpiScaledCanvasKeepsItsPageSize() {
        // `.dpi(300)` raises the pixel resolution but the PDF page stays the
        // physical sheet, with the geometry scaled back onto it.
        let sketch = PrintResolutionPage()
        #expect(sketch.canvasSize.width == 2550 && sketch.canvasSize.height == 3300)
        let data = OllinApp.pdf(of: sketch)
        let doc = CGPDFDocument(CGDataProvider(data: data as CFData)!)
        #expect(doc?.page(at: 1)?.getBoxRect(.mediaBox) == CGRect(x: 0, y: 0, width: 612, height: 792))
        // The pixel-space square still covers the page's top-left quadrant.
        let rgba = rasterize(data, width: 102, height: 132)
        #expect(pixel(rgba, 102, 25, 33).r < 30)      // top-left quadrant: black
        #expect(pixel(rgba, 102, 75, 33).r > 225)     // top-right: white
        #expect(pixel(rgba, 102, 25, 99).r > 225)     // bottom-left: white
    }

    @Test func dpiAndOrientationCompose() {
        #expect(CanvasSize.a4.dpi(300).width == 2479)         // 595 × 300 / 72
        #expect(CanvasSize.a4.dpi(300).height == 3508)        // 842 × 300 / 72
        let landscape = CanvasSize.a4.dpi(300).landscape
        #expect(landscape.width == 3508 && landscape.height == 2479)
        #expect(CanvasSize.a4.dpi(300).dpi(72) == .size(595, 842))   // back to one pixel per point
        #expect(CanvasSize.square1080.dpi(72) == .square1080)        // a no-op stays itself
    }

    @Test func orientationIsTopLeft() {
        // The black square was drawn at the canvas top-left; if the page flip
        // were missing it would land bottom-left instead.
        let rgba = rasterize(OllinApp.pdf(of: Fixture()), width: 100, height: 100)
        #expect(pixel(rgba, 100, 25, 25).r < 30)     // top-left: black square
        #expect(pixel(rgba, 100, 25, 75).r > 225)    // bottom-left: white background
    }

    @Test func transformAndAlpha() {
        let rgba = rasterize(OllinApp.pdf(of: Fixture()), width: 100, height: 100)
        // The translated half-alpha red square over white reads pink.
        let p = pixel(rgba, 100, 75, 75)
        #expect(p.r > 225)
        #expect(p.g > 95 && p.g < 160)
        #expect(p.b > 95 && p.b < 160)
    }

    @Test func imagesAreSkipped() {
        // The blue raster image never lands on the page.
        let rgba = rasterize(OllinApp.pdf(of: Fixture()), width: 100, height: 100)
        #expect(pixel(rgba, 100, 14, 84).b > 225)
        #expect(pixel(rgba, 100, 14, 84).r > 225)
    }

    @Test func renderedPixelsAreDeterministic() {
        // The container bytes carry a creation date, so determinism is pinned
        // on what the page draws, not on the file bytes.
        let a = rasterize(OllinApp.pdf(of: Fixture(), frame: 3), width: 100, height: 100)
        let b = rasterize(OllinApp.pdf(of: Fixture(), frame: 3), width: 100, height: 100)
        #expect(a == b)
    }

    // MARK: - Gradients

    /// A full-canvas left-to-right red-to-blue linear gradient fill.
    final class GradientFill: Sketch {
        override var canvasSize: CanvasSize { .square(100) }
        override func draw() {
            background(.white)
            noStroke()
            fill(.linear(from: Vector2(0, 0), to: Vector2(100, 0), [.red, .blue]))
            drawRect(0, 0, 100, 100)
        }
    }

    @Test func linearGradientFillDrawsNatively() {
        let rgba = rasterize(OllinApp.pdf(of: GradientFill()), width: 100, height: 100)
        let left = pixel(rgba, 100, 5, 50)
        let right = pixel(rgba, 100, 95, 50)
        #expect(left.r > 200 && left.b < 80)         // red end
        #expect(right.b > 200 && right.r < 80)       // blue end
    }

    // MARK: - Clipping

    /// A full-canvas black fill confined to the right half by `withClip`.
    final class Clipped: Sketch {
        override var canvasSize: CanvasSize { .square(100) }
        override func draw() {
            background(.white)
            noStroke()
            withClip(Rectangle(x: 50, y: 0, width: 50, height: 100)) {
                fill(.black)
                drawRect(0, 0, 100, 100)
            }
        }
    }

    @Test func clipConfinesDrawing() {
        let rgba = rasterize(OllinApp.pdf(of: Clipped()), width: 100, height: 100)
        #expect(pixel(rgba, 100, 25, 50).r > 225)    // outside the clip: white
        #expect(pixel(rgba, 100, 75, 50).r < 30)     // inside the clip: black
    }

    // MARK: - Hatching

    /// A single black circle on white, for the hatching transform.
    final class Disk: Sketch {
        override var canvasSize: CanvasSize { .square(100) }
        override func draw() {
            background(.white)
            noStroke()
            fill(.black)
            drawCircle(50, 50, 30)
        }
    }

    @Test func hatchingTurnsFillsIntoLines() {
        let plain = rasterize(OllinApp.pdf(of: Disk()), width: 100, height: 100)
        let hatched = rasterize(OllinApp.pdf(of: Disk(), hatching: Hatching(spacing: 8, keepsOutline: false)),
                                width: 100, height: 100)
        // Down the disk's vertical diameter: the plain fill is solid ink, the
        // hatched one alternates pen lines with paper gaps.
        let plainSamples = (30...70).map { pixel(plain, 100, 50, $0).r }
        let hatchedSamples = (30...70).map { pixel(hatched, 100, 50, $0).r }
        #expect(plainSamples.allSatisfy { $0 < 30 })
        #expect(hatchedSamples.contains { $0 < 100 })    // pen lines
        #expect(hatchedSamples.contains { $0 > 200 })    // gaps between them
    }
}
