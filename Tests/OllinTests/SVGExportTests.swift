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

    @Test func multiLoopTraceBecomesEvenOddPath() {
        // A moon whose cut disk sits fully inside the outer disk has two boundary
        // loops (a ring with an off-center hole); the trace serializes as one
        // even-odd path carrying both, instead of dropping the hole.
        final class Donut: Sketch {
            override var canvasSize: CanvasSize { .square(100) }
            override func draw() {
                background(.white); noStroke(); fill(.black)
                drawMoon(50, 50, 40, 15, 8)
            }
        }
        let svg = OllinApp.svg(of: Donut())
        let path = svg.components(separatedBy: "\n").first {
            $0.contains("<path") && $0.contains("fill-rule=\"evenodd\"")
        }
        #expect(path != nil)
        #expect((path ?? "").components(separatedBy: "M ").count - 1 == 2)   // two loops
    }

    @Test func coolSExportsInteriorLineWork() {
        // The Cool S's interior lines are zero-distance valleys the field never
        // crosses (the raster stroke band shows them); the export emits them as
        // explicit stroke polylines, but only when a stroke is active.
        final class CoolS: Sketch {
            override var canvasSize: CanvasSize { .square(100) }
            var stroked = true
            override func draw() {
                background(.white)
                fill(.black)
                if stroked { stroke(.red); strokeWeight(2) } else { noStroke() }
                drawCoolS(50, 50, 80)
            }
        }
        let stroked = OllinApp.svg(of: CoolS())
        #expect(stroked.components(separatedBy: "<polyline").count - 1 == 2)
        let fillOnly = CoolS()
        fillOnly.stroked = false
        #expect(!OllinApp.svg(of: fillOnly).contains("<polyline"))
    }

    @Test func imagesAreSkippedWithNote() {
        let svg = OllinApp.svg(of: Fixture())
        #expect(svg.contains("image draw(s) skipped"))
        #expect(!svg.contains("<image"))
    }

    @Test func isDeterministic() {
        // No GPU, fixed timestep: the same frame of the same variation
        // serializes identically. Seeded, because an unseeded sketch rolls a
        // fresh `variation` per instance and the recipe comment records it.
        func fixture() -> Fixture {
            let f = Fixture()
            f.seed(1)
            return f
        }
        #expect(OllinApp.svg(of: fixture(), frame: 3) == OllinApp.svg(of: fixture(), frame: 3))
    }

    /// Two unseeded runs of a randomness-free sketch draw the same picture; only
    /// the recorded variation in the recipe tells them apart.
    @Test func unseededRunsDifferOnlyInTheRecordedVariation() {
        func body(_ svg: String) -> String {
            svg.components(separatedBy: "\n").filter { !$0.contains("<!-- {") }.joined(separator: "\n")
        }
        let a = OllinApp.svg(of: Fixture(), frame: 3)
        let b = OllinApp.svg(of: Fixture(), frame: 3)
        #expect(body(a) == body(b))
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
        let plain = OllinApp.svg(of: Disk())
        let hatched = OllinApp.svg(of: Disk(), hatching: Hatching(spacing: 6))
        // The plain export is a filled circle; the hatched one is line work.
        #expect(plain.contains("<circle cx=\"50\" cy=\"50\" r=\"30\" fill=\"rgb(0,0,0)\""))
        #expect(!hatched.contains("fill=\"rgb(0,0,0)\""))   // the fill is gone
        #expect(hatched.contains("<polyline"))              // replaced by hatch lines
    }

    @Test func hatchingKeepsTheOutline() {
        let hatched = OllinApp.svg(of: Disk(), hatching: Hatching(spacing: 6, keepOutline: true))
        // The circle survives as a stroked, unfilled outline.
        #expect(hatched.contains("<circle cx=\"50\" cy=\"50\" r=\"30\" fill=\"none\" stroke="))
        let dropped = OllinApp.svg(of: Disk(), hatching: Hatching(spacing: 6, keepOutline: false))
        #expect(!dropped.contains("<circle"))
    }

    @Test func crossHatchAddsLines() {
        func lineCount(_ svg: String) -> Int { svg.components(separatedBy: "<polyline").count - 1 }
        let single = OllinApp.svg(of: Disk(), hatching: Hatching(spacing: 6, crossHatch: false))
        let cross = OllinApp.svg(of: Disk(), hatching: Hatching(spacing: 6, crossHatch: true))
        #expect(lineCount(cross) > lineCount(single))
    }

    @Test func toneDensitySkipsLightFills() {
        // A near-white fill drops out of the hatch entirely.
        final class Faint: Sketch {
            override var canvasSize: CanvasSize { .square(100) }
            override func draw() {
                background(.white); noStroke()
                fill(Color(white: 0.98)); drawCircle(50, 50, 30)
            }
        }
        let hatched = OllinApp.svg(of: Faint(), hatching: Hatching(spacing: 6, keepOutline: false))
        #expect(!hatched.contains("<polyline"))   // too light to hatch
    }

    @Test func lineGeometryFillsAShape() {
        // The public core: hatch lines for a 50-radius circle at spacing 10.
        let lines = Hatching(spacing: 10, angle: 0).lines(filling: Circle(x: 0, y: 0, radius: 50))
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.count == 2 })                 // each is a segment
        #expect(lines.allSatisfy { $0[0].length <= 50.01 && $0[1].length <= 50.01 })  // inside the disk
    }
}

/// Gradient paints in the SVG exporter: linear/radial become native defs
/// referenced by `url(#…)`, an along-path stroke splits into short solid runs,
/// and an along-path fill (the conic sweep, which SVG can't express) falls back
/// to its ramp's midpoint color.
@Suite
@MainActor
struct SVGGradientTests {

    final class GradientFixture: Sketch {
        override var canvasSize: CanvasSize { .square(100) }

        override func draw() {
            background(.white)
            noStroke()
            fill(.linear(from: Vector2(0, 0), to: Vector2(0, 100), [.black, .white]))
            drawRect(0, 0, 100, 100)
            fill(.radial(center: Vector2(50, 50), radius: 20, [.red, .blue]))
            drawCircle(50, 50, 20)
            stroke(.alongPath([.red, .blue]))
            strokeWeight(2)
            drawLine(Vector2(0, 10), Vector2(100, 10))
            noStroke()
            fill(.alongPath([.black, .white]))
            drawPolygon([Vector2(10, 80), Vector2(30, 80), Vector2(20, 95)])
        }
    }

    @Test func linearAndRadialBecomeDefs() {
        let svg = OllinApp.svg(of: GradientFixture())
        #expect(svg.contains("<defs>"))
        #expect(svg.contains("<linearGradient id=\"grad0\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"100\">"))
        #expect(svg.contains("fill=\"url(#grad0)\""))
        #expect(svg.contains("<radialGradient id=\"grad1\" gradientUnits=\"userSpaceOnUse\" cx=\"50\" cy=\"50\" r=\"20\">"))
        #expect(svg.contains("fill=\"url(#grad1)\""))
    }

    @Test func nonRGBRampsSubdivideTheirStops() {
        // The ramps mix in OKLab, which SVG can't interpolate — each span gains
        // intermediate stops so the SVG curve tracks the ramp.
        let svg = OllinApp.svg(of: GradientFixture())
        let linearDef = svg.components(separatedBy: "</linearGradient>")[0]
        let stops = linearDef.components(separatedBy: "<stop ").count - 1
        #expect(stops > 2)
    }

    @Test func alongPathStrokeSplitsIntoRuns() {
        let svg = OllinApp.svg(of: GradientFixture())
        // The 100-point line splits into ~12-point solid runs; their colors walk
        // the ramp, so the first and last differ.
        let lines = svg.components(separatedBy: "\n").filter { $0.contains("<line ") }
        #expect(lines.count >= 4)
        #expect(svg.contains("stroke=\"url") == false)   // no gradient stroke refs remain
        if let first = lines.first, let last = lines.last {
            let firstColor = first.components(separatedBy: "stroke=\"").last?.prefix(16)
            let lastColor = last.components(separatedBy: "stroke=\"").last?.prefix(16)
            #expect(firstColor != lastColor)
        }
    }

    @Test func alongPathFillFallsBackToMidpoint() {
        let svg = OllinApp.svg(of: GradientFixture())
        // The conic-filled polygon gets a flat midpoint color, not a url ref.
        let polygon = svg.components(separatedBy: "\n").first { $0.contains("<polygon") } ?? ""
        #expect(polygon.contains("fill=\"rgb("))
    }
}
