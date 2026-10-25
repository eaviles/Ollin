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

    @Test func documentStructure() throws {
        let svg = try OllinApp.svg(of: Fixture())
        #expect(svg.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(svg.contains("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\" viewBox=\"0 0 100 100\">"))
        #expect(svg.contains("<rect width=\"100\" height=\"100\" fill=\"rgb(255,255,255)\"/>"))   // background first
        #expect(svg.hasSuffix("</svg>\n"))
    }

    @Test func nativeElementsAndStyle() throws {
        let svg = try OllinApp.svg(of: Fixture())
        #expect(svg.contains("<circle cx=\"50\" cy=\"50\" r=\"20\""))
        #expect(svg.contains("fill=\"rgb(0,0,0)\""))                 // black fill
        #expect(svg.contains("<line "))                             // the line
        #expect(svg.contains("stroke-width=\"2\""))
        #expect(svg.contains("<polygon points="))
    }

    @Test func transformAndAlpha() throws {
        let svg = try OllinApp.svg(of: Fixture())
        #expect(svg.contains("transform=\"matrix(1 0 0 1 10 20)\""))   // the translated rect
        #expect(svg.contains("fill-opacity=\"0.5\""))                  // the alpha fill
    }

    @Test func vectorShapeBecomesPath() throws {
        let svg = try OllinApp.svg(of: Fixture())
        // A `Shape` becomes a closed `<path d="M … Z">`.
        #expect(svg.contains("<path d=\"M "))
        #expect(svg.contains(" Z\""))
    }

    @Test func curvedShapeIsTracedToPolygon() throws {
        let svg = try OllinApp.svg(of: Fixture())
        // The heart has no native element and no closed-form polygon; it traces to
        // a `<polygon>` with many points (far more than the 3-point triangle).
        let polygons = svg.components(separatedBy: "<polygon").dropFirst()
        #expect(polygons.contains { $0.filter { $0 == "," }.count > 20 })
    }

    @Test func multiLoopTraceBecomesEvenOddPath() throws {
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
        let svg = try OllinApp.svg(of: Donut())
        let path = svg.components(separatedBy: "\n").first {
            $0.contains("<path") && $0.contains("fill-rule=\"evenodd\"")
        }
        #expect(path != nil)
        #expect((path ?? "").components(separatedBy: "M ").count - 1 == 2)   // two loops
    }

    @Test func coolSExportsInteriorLineWork() throws {
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
        let stroked = try OllinApp.svg(of: CoolS())
        #expect(stroked.components(separatedBy: "<polyline").count - 1 == 2)
        let fillOnly = CoolS()
        fillOnly.stroked = false
        #expect(try !OllinApp.svg(of: fillOnly).contains("<polyline"))
    }

    @Test func imagesAreSkippedWithNote() throws {
        let svg = try OllinApp.svg(of: Fixture())
        #expect(svg.contains("image draw(s) skipped"))
        #expect(!svg.contains("<image"))
    }

    @Test func isDeterministic() throws {
        // No GPU, fixed timestep: the same frame of the same variation
        // serializes identically. Seeded, because an unseeded sketch rolls a
        // fresh `variation` per instance and the recipe comment records it.
        func fixture() throws -> Fixture {
            let f = Fixture()
            f.seed(1)
            return f
        }
        #expect(try OllinApp.svg(of: fixture(), frame: 3) == OllinApp.svg(of: fixture(), frame: 3))
    }

    /// Two unseeded runs of a randomness-free sketch draw the same picture; only
    /// the recorded variation in the recipe tells them apart.
    @Test func unseededRunsDifferOnlyInTheRecordedVariation() throws {
        func body(_ svg: String) -> String {
            svg.components(separatedBy: "\n").filter { !$0.contains("<!-- {") }.joined(separator: "\n")
        }
        let a = try OllinApp.svg(of: Fixture(), frame: 3)
        let b = try OllinApp.svg(of: Fixture(), frame: 3)
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

    @Test func hatchingTurnsFillsIntoLines() throws {
        let plain = try OllinApp.svg(of: Disk())
        let hatched = try OllinApp.svg(of: Disk(), hatching: Hatching(spacing: 6))
        // The plain export is a filled circle; the hatched one is line work.
        #expect(plain.contains("<circle cx=\"50\" cy=\"50\" r=\"30\" fill=\"rgb(0,0,0)\""))
        #expect(!hatched.contains("fill=\"rgb(0,0,0)\""))   // the fill is gone
        #expect(hatched.contains("<polyline"))              // replaced by hatch lines
    }

    @Test func hatchingKeepsTheOutline() throws {
        let hatched = try OllinApp.svg(of: Disk(), hatching: Hatching(spacing: 6, keepsOutline: true))
        // The circle survives as a stroked, unfilled outline.
        #expect(hatched.contains("<circle cx=\"50\" cy=\"50\" r=\"30\" fill=\"none\" stroke="))
        let dropped = try OllinApp.svg(of: Disk(), hatching: Hatching(spacing: 6, keepsOutline: false))
        #expect(!dropped.contains("<circle"))
    }

    /// Every fill scans the one lattice, so the first line is the lattice line
    /// at or just under a shape's top, never a whole step further in, and two
    /// equal squares anywhere on the canvas hatch within a line of each other.
    @Test func hatchingStartsOnTheFirstLatticeLineInside() {
        let hatch = Hatching(spacing: 7.43, angle: 0)
        func firstAndCount(_ top: Double) -> (first: Double, count: Int) {
            let lines = hatch.lines(filling: Rectangle(x: 10, y: top, width: 52, height: 52))
            return (lines.map { $0[0].y }.min() ?? .infinity, lines.count)
        }
        // The top on a whole step: the lattice line half a step in.
        let onStep = firstAndCount(7.43 * 14)
        #expect(abs(onStep.first - 7.43 * 14.5) < 1e-9 && onStep.count == 7)
        // The top at 100: the lattice line at 13.5 steps (100.3) is inside, so
        // it is the first, not the one at 14.5 steps (7.7 pixels in).
        let at100 = firstAndCount(100)
        #expect(abs(at100.first - 7.43 * 13.5) < 1e-9 && at100.count == 7)
        for top in stride(from: 90.0, to: 110, by: 0.37) {
            let (first, count) = firstAndCount(top)
            #expect(first >= top && first - top < 7.43, "first line \(first - top) in at \(top)")
            #expect(count == 6 || count == 7, "\(count) lines at \(top)")
        }
    }

    /// Centered, a shape is hatched across its own extent: equal squares get
    /// the same count wherever they sit, half a step in at the top and the
    /// bottom, with the step within half a spacing of `spacing` shared over the
    /// count.
    @Test func centeredHatchingFitsEachShapeAlone() {
        let hatch = Hatching(spacing: 7.43, angle: 0, centersLines: true)
        for top in stride(from: 90.0, to: 110, by: 0.37) {
            let lines = hatch.lines(filling: Rectangle(x: 10, y: top, width: 52, height: 52))
            let ys = lines.map { $0[0].y }.sorted()
            // 52 / 7.43 = 7.0: seven lines, 52/7 apart, the first at half that.
            #expect(ys.count == 7, "\(ys.count) lines at \(top)")
            let step = 52.0 / 7
            for (k, y) in ys.enumerated() {
                #expect(abs(y - (top + step * (Double(k) + 0.5))) < 1e-9, "line \(k) at \(top)")
            }
        }
        // The count is the nearest whole number of spacings, never zero: a
        // sliver gets one line through its middle.
        let wide = hatch.lines(filling: Rectangle(x: 0, y: 0, width: 40, height: 40 + 7.43 * 0.6))
        #expect(wide.count == 6)
        let sliver = hatch.lines(filling: Rectangle(x: 0, y: 0, width: 40, height: 2))
        #expect(sliver.count == 1 && abs(sliver[0][0].y - 1) < 1e-9)
    }

    /// Centering holds at any angle and on both passes of a cross-hatch, so a
    /// square turned on the lattice still gets the same lines in each copy.
    @Test func centeredCrossHatchMatchesInEveryCopy() {
        let hatch = Hatching(spacing: 5, angle: .pi / 5, crossHatches: true, centersLines: true)
        let here = hatch.lines(filling: Rectangle(x: 0, y: 0, width: 30, height: 30))
        let there = hatch.lines(filling: Rectangle(x: 73.3, y: 41.9, width: 30, height: 30))
        #expect(here.count == there.count)
        for (a, b) in zip(here, there) {
            #expect((a[0] + Vector2(73.3, 41.9)).distance(to: b[0]) < 1e-9)
            #expect((a[1] + Vector2(73.3, 41.9)).distance(to: b[1]) < 1e-9)
        }
        // Without centering the two copies sit differently on the shared lattice.
        let latticed = Hatching(spacing: 5, angle: .pi / 5, crossHatches: true)
        let a = latticed.lines(filling: Rectangle(x: 0, y: 0, width: 30, height: 30))
        let b = latticed.lines(filling: Rectangle(x: 73.3, y: 41.9, width: 30, height: 30))
        #expect(a.count != b.count || zip(a, b).contains {
            ($0.0[0] + Vector2(73.3, 41.9)).distance(to: $0.1[0]) > 1e-6
        })
    }

    /// The exporter centers each recorded fill when asked.
    @Test func theExporterCentersEachFill() throws {
        final class Cells: Sketch {
            override var canvasSize: CanvasSize { .square(100) }
            override func draw() {
                background(.white); noStroke(); fill(.black)
                drawRect(3, 3, 20, 20)
                drawRect(51.7, 61, 20, 20)
            }
        }
        func lineCount(_ svg: String) -> Int { svg.components(separatedBy: "<polyline").count - 1 }
        let options = Hatching(spacing: 3.3, angle: 0, usesToneDensity: false, keepsOutline: false,
                               centersLines: true)
        // 20 / 3.3 = 6.06: six lines a cell, twelve in all, where the shared
        // lattice puts seven in the second cell (its first line 0.05 in).
        #expect(lineCount(try OllinApp.svg(of: Cells(), hatching: options)) == 12)
    }

    @Test func crossHatchAddsLines() throws {
        func lineCount(_ svg: String) -> Int { svg.components(separatedBy: "<polyline").count - 1 }
        let single = try OllinApp.svg(of: Disk(), hatching: Hatching(spacing: 6, crossHatches: false))
        let cross = try OllinApp.svg(of: Disk(), hatching: Hatching(spacing: 6, crossHatches: true))
        #expect(lineCount(cross) > lineCount(single))
    }

    @Test func usesToneDensitySkipsLightFills() throws {
        // A near-white fill drops out of the hatch entirely.
        final class Faint: Sketch {
            override var canvasSize: CanvasSize { .square(100) }
            override func draw() {
                background(.white); noStroke()
                fill(Color(white: 0.98)); drawCircle(50, 50, 30)
            }
        }
        let hatched = try OllinApp.svg(of: Faint(), hatching: Hatching(spacing: 6, keepsOutline: false))
        #expect(!hatched.contains("<polyline"))   // too light to hatch
    }

    @Test func lineGeometryFillsAShape() throws {
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

    @Test func linearAndRadialBecomeDefs() throws {
        let svg = try OllinApp.svg(of: GradientFixture())
        #expect(svg.contains("<defs>"))
        #expect(svg.contains("<linearGradient id=\"grad0\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"100\">"))
        #expect(svg.contains("fill=\"url(#grad0)\""))
        #expect(svg.contains("<radialGradient id=\"grad1\" gradientUnits=\"userSpaceOnUse\" cx=\"50\" cy=\"50\" r=\"20\">"))
        #expect(svg.contains("fill=\"url(#grad1)\""))
    }

    @Test func nonRGBRampsSubdivideTheirStops() throws {
        // The ramps mix in OKLab, which SVG can't interpolate — each span gains
        // intermediate stops so the SVG curve tracks the ramp.
        let svg = try OllinApp.svg(of: GradientFixture())
        let linearDef = svg.components(separatedBy: "</linearGradient>")[0]
        let stops = linearDef.components(separatedBy: "<stop ").count - 1
        #expect(stops > 2)
    }

    @Test func alongPathStrokeSplitsIntoRuns() throws {
        let svg = try OllinApp.svg(of: GradientFixture())
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

    @Test func alongPathFillFallsBackToMidpoint() throws {
        let svg = try OllinApp.svg(of: GradientFixture())
        // The conic-filled polygon gets a flat midpoint color, not a url ref.
        let polygon = svg.components(separatedBy: "\n").first { $0.contains("<polygon") } ?? ""
        #expect(polygon.contains("fill=\"rgb("))
    }
}
