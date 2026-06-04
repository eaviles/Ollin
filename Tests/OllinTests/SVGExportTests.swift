import Ollin
import Testing

/// Structure checks on the SVG exporter. SVG export records draw calls on the CPU
/// and never touches Metal, so these run everywhere (including CI) — and exercise
/// the no-GPU path directly. They render a fixture covering each element kind and
/// assert the document shape, not exact coordinates (those are pinned visually
/// against the raster render in the VectorExport example).
@Suite
@MainActor
struct SVGExportTests {

    /// A 100×100 fixture touching one of each: native element, polygon, curved
    /// (traced) path, vector shape, transform, alpha, and a skipped image.
    final class Fixture: Sketch {
        override var canvasSize: CanvasSize { .square(100) }

        override func draw() {
            background(.white)
            noStroke()
            fill(.black)
            drawCircle(50, 50, 20)                       // <circle>

            withState {
                translate(10, 20)                        // -> transform matrix
                fill(Color(red: 1, green: 0, blue: 0, alpha: 0.5))   // -> fill-opacity
                drawRect(0, 0, 30, 12)                   // <rect>
            }

            stroke(.black)
            strokeWeight(2)
            drawLine(Vector2(0, 0), Vector2(100, 100))   // <line>

            fill(Color(white: 0.5))
            drawHeart(50, 70, 30)                         // curved -> traced <polygon>
            drawPolygon([Vector2(0, 0), Vector2(10, 0), Vector2(5, 10)])   // <polygon>

            fill(.black)
            drawShape(Shape([Vector2(80, 80), Vector2(95, 80), Vector2(95, 95), Vector2(80, 95)]))   // <path … Z>

            let blank = Image(width: 4, height: 4, color: .blue)
            drawImage(blank, 0, 0, 8, 8)                  // skipped -> comment
        }
    }

    @Test func documentStructure() {
        let svg = OllinApp.svg(of: Fixture())
        #expect(svg.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(svg.contains("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\" viewBox=\"0 0 100 100\">"))
        #expect(svg.contains("<rect width=\"100\" height=\"100\" fill=\"rgb(255,255,255)\"/>"))   // background first
        #expect(svg.hasSuffix("</svg>\n"))
    }

    @Test func nativeElementsAndStyle() {
        let svg = OllinApp.svg(of: Fixture())
        #expect(svg.contains("<circle cx=\"50\" cy=\"50\" r=\"20\""))
        #expect(svg.contains("fill=\"rgb(0,0,0)\""))                 // black fill
        #expect(svg.contains("<line "))                             // the line
        #expect(svg.contains("stroke-width=\"2\""))
        #expect(svg.contains("<polygon points="))
    }

    @Test func transformAndAlpha() {
        let svg = OllinApp.svg(of: Fixture())
        #expect(svg.contains("transform=\"matrix(1 0 0 1 10 20)\""))   // the translated rect
        #expect(svg.contains("fill-opacity=\"0.5\""))                  // the alpha fill
    }

    @Test func vectorShapeBecomesPath() {
        let svg = OllinApp.svg(of: Fixture())
        // A `Shape` becomes a closed `<path d="M … Z">`.
        #expect(svg.contains("<path d=\"M "))
        #expect(svg.contains(" Z\""))
    }

    @Test func curvedShapeIsTracedToPolygon() {
        let svg = OllinApp.svg(of: Fixture())
        // The heart has no native element and no closed-form polygon; it traces to
        // a `<polygon>` with many points (far more than the 3-point triangle).
        let polygons = svg.components(separatedBy: "<polygon").dropFirst()
        #expect(polygons.contains { $0.filter { $0 == "," }.count > 20 })
    }

    @Test func imagesAreSkippedWithNote() {
        let svg = OllinApp.svg(of: Fixture())
        #expect(svg.contains("image draw(s) skipped"))
        #expect(!svg.contains("<image"))
    }

    @Test func isDeterministic() {
        // No GPU, fixed timestep — the same frame serializes identically.
        #expect(OllinApp.svg(of: Fixture(), frame: 3) == OllinApp.svg(of: Fixture(), frame: 3))
    }
}
