import CoreGraphics
import Testing
@testable import Ollin

/// The dash pattern and the cut it makes. The pixel snapshot pins the look;
/// these pin the rules a mean-difference comparison would average away: how a
/// pattern is read, where the dashes land and how a phase moves them, that a
/// corner inside a dash keeps its vertex and a dash across a closed path's seam
/// comes back whole, that a profile keeps reading the whole path across the
/// gaps, that the analytic shapes hand their outline over, and that the vector
/// file and the web page carry each dash on its own.
@Suite
@MainActor
struct StrokeDashTests {

    // MARK: Reading a pattern

    @Test
    func anOddCountRepeatsAndNegativesReadAsZero() {
        #expect(StrokeDash([8, 4, 2]).resolvedLengths == [8, 4, 2, 8, 4, 2])
        #expect(abs(StrokeDash([8, 4, 2]).period - 28) < 1e-12)
        #expect(StrokeDash([-3, 5]).resolvedLengths == [0, 5])
        #expect(StrokeDash([10, .nan]).resolvedLengths == [10, 0])
    }

    @Test
    func solidWhenNoGapHasLength() {
        #expect(StrokeDash([]).isSolid)
        #expect(StrokeDash([10, 0]).isSolid)
        #expect(StrokeDash([10, -4]).isSolid)
        // A single length is a dash and a gap of that length, so it does cut.
        #expect(!StrokeDash([10]).isSolid)
        #expect(!StrokeDash.dashes(6).isSolid)
        #expect(!StrokeDash.dots(spacing: 4).isSolid)
    }

    // MARK: Where the dashes land

    private let line = [Vector2(0, 0), Vector2(100, 0)]

    @Test
    func aStraightLineCutsIntoEvenDashes() throws {
        let pieces = try #require(StrokeDash.dashes(10).cut(line, closed: false))
        #expect(pieces.count == 5)
        for (k, piece) in pieces.enumerated() {
            #expect(piece.points.count == 2)
            #expect(abs(piece.points[0].x - Double(k) * 20) < 1e-9)
            #expect(abs(piece.points[1].x - Double(k) * 20 - 10) < 1e-9)
            #expect(abs(piece.fractions[0] - Double(k) * 0.2) < 1e-12)
            #expect(abs(piece.fractions[1] - Double(k) * 0.2 - 0.1) < 1e-12)
        }
    }

    @Test
    func aPositivePhaseCarriesTheDashesForward() throws {
        let forward = try #require(StrokeDash.dashes(10, phase: 5).cut(line, closed: false))
        #expect(forward.count == 5)
        #expect(abs(forward[0].points[0].x - 5) < 1e-9)
        #expect(abs(forward[0].points[1].x - 15) < 1e-9)
        #expect(abs(forward[4].points[1].x - 95) < 1e-9)
        // Slid back by 5 the path starts inside a dash, so the first is cut short.
        let back = try #require(StrokeDash.dashes(10, phase: -5).cut(line, closed: false))
        #expect(back.count == 6)
        #expect(abs(back[0].points[0].x) < 1e-9)
        #expect(abs(back[0].points[1].x - 5) < 1e-9)
        #expect(abs(back[1].points[0].x - 15) < 1e-9)
        // A whole period of phase changes nothing.
        let wrapped = try #require(StrokeDash.dashes(10, phase: 40).cut(line, closed: false))
        #expect(wrapped.count == 5)
        #expect(abs(wrapped[0].points[0].x) < 1e-9)
    }

    @Test
    func aCornerInsideADashKeepsItsVertex() throws {
        let corner = [Vector2(0, 0), Vector2(50, 0), Vector2(50, 50)]
        let pieces = try #require(StrokeDash.dashes(30, gap: 10).cut(corner, closed: false))
        #expect(pieces.count == 3)
        // The second dash runs from 40 to 70 along the path, through the corner.
        #expect(pieces[1].points == [Vector2(40, 0), Vector2(50, 0), Vector2(50, 20)])
        #expect(pieces[1].fractions.map { ($0 * 100).rounded() / 100 } == [0.4, 0.5, 0.7])
        // The last one ends on the last point.
        #expect(pieces[2].points == [Vector2(50, 30), Vector2(50, 50)])
    }

    @Test
    func aDashAcrossAClosedPathsSeamComesBackWhole() throws {
        let square = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
        // On is 0...125, 175...325, and 375...400, so the last dash runs on into the first.
        let pieces = try #require(StrokeDash([150, 50], phase: -25).cut(square, closed: true))
        #expect(pieces.count == 2)
        #expect(pieces[0].points == [Vector2(100, 75), Vector2(100, 100), Vector2(0, 100), Vector2(0, 75)])
        let seam = pieces[1]
        #expect(seam.points == [Vector2(0, 25), Vector2(0, 0), Vector2(100, 0), Vector2(100, 25)])
        #expect(seam.fractions.map { ($0 * 10000).rounded() / 10000 } == [0.9375, 1, 0.25, 0.3125])
    }

    @Test
    func oneDashCoveringTheWholeLoopLeavesItWhole() {
        let square = Contour([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)], closed: true)
        let cut = square.dashed(.dashes(1000, gap: 10))
        #expect(cut.count == 1)
        #expect(cut[0].isClosed)
        #expect(cut[0] == square)
        // And the solid pattern is the identity on an open contour too.
        let open = Contour(line, closed: false)
        #expect(open.dashed(StrokeDash([])) == [open])
    }

    @Test
    func dotsAreZeroLengthDashesWithADirection() throws {
        let pieces = try #require(StrokeDash.dots(spacing: 20).cut(line, closed: false))
        // One on every 20 points, the two ends included.
        #expect(pieces.count == 6)
        for (k, piece) in pieces.enumerated() {
            #expect(piece.points.count == 2)
            #expect(abs(piece.points[0].x - Double(k) * 20) < 1e-9)
            // Nudged along the path so its caps know which way to face, by
            // less than any stroke could show.
            #expect(piece.points[1].x > piece.points[0].x)
            #expect(piece.points[1].x - piece.points[0].x < 0.01)
            #expect(piece.points[1].y == 0)
        }
    }

    @Test
    func aShapeCutsEveryContour() {
        let shape = Shape(contours: [Contour(line, closed: false),
                                     Contour(line.map { $0 + Vector2(0, 10) }, closed: false)],
                          winding: .nonZero)
        let cut = shape.dashed(.dashes(10))
        #expect(cut.contours.count == 10)
        #expect(cut.winding == .nonZero)
        #expect(cut.contours.allSatisfy { !$0.isClosed })
    }

    // MARK: The drawer

    @Test
    func aPatternTooFineForItsPathDrawsWhole() {
        let dash = StrokeDash([0.001, 0.001])
        #expect(dash.dashCount(along: 1000) > Drawer.maxDashesPerPath)
        let drawer = Drawer()
        drawer.strokeDash(dash)
        let runs = drawer.strokeRuns([Vector2(0, 0), Vector2(1000, 0)], closed: false)
        #expect(runs.count == 1)
        #expect(runs[0].fractions == nil)
    }

    @Test
    func noDashIsTheWholePathAsOneRun() {
        let drawer = Drawer()
        let runs = drawer.strokeRuns(line, closed: true)
        #expect(runs.count == 1)
        #expect(runs[0].closed)
        #expect(runs[0].points == line)
        #expect(runs[0].fractions == nil)
    }

    /// A width profile keeps reading the whole path: the last dash of a ramp is
    /// nearly full width, not a fresh ramp from nothing.
    @Test
    func aProfileReadsTheWholePathAcrossTheGaps() throws {
        let drawer = Drawer()
        drawer.strokeWeight(10)
        drawer.strokeProfile(.ramp(from: 0, to: 1))
        drawer.strokeDash(.dashes(10))
        let runs = drawer.strokeRuns(line, closed: false)
        #expect(runs.count == 5)
        let last = runs[4]
        let hws = try #require(drawer.strokeHalfWidths(for: last.points, closed: false,
                                                        fractions: last.fractions))
        #expect(abs(hws[0] - 4.0) < 1e-9)
        #expect(abs(hws[1] - 4.5) < 1e-9)
        // Subdividing a run keeps the fractions in step with the points.
        let (pts, ts) = Drawer.subdivided(last.points, fractions: last.fractions, closed: false, maxLength: 2.5)
        let fractions = try #require(ts)
        #expect(pts.count == fractions.count)
        #expect(pts.count == 5)
        #expect(abs(fractions[2] - 0.85) < 1e-9)
    }

    /// The map a brush reads its place through: a run's own fraction onto the whole path's.
    @Test
    func aBrushReadsItsPlaceOnTheWholePath() {
        let run = Drawer.StrokeRun(points: [Vector2(80, 0), Vector2(90, 0)], closed: false,
                                   fractions: [0.8, 0.9])
        let place = Drawer.fractionMap(run)
        #expect(abs(place(0) - 0.8) < 1e-12)
        #expect(abs(place(0.5) - 0.85) < 1e-12)
        #expect(abs(place(1) - 0.9) < 1e-12)
        let whole = Drawer.StrokeRun(points: [Vector2(0, 0), Vector2(10, 0)], closed: false, fractions: nil)
        #expect(Drawer.fractionMap(whole)(0.3) == 0.3)
    }

    @Test
    func withStateRestoresTheDash() {
        let drawer = Drawer()
        drawer.strokeDash(.dashes(4))
        drawer.pushState()
        drawer.noStrokeDash()
        #expect(drawer.strokeDashPattern == nil)
        drawer.popState()
        #expect(drawer.strokeDashPattern == .dashes(4))
    }

    /// A circle under a dash draws its fill as the instance it always was and
    /// its outline as a stroked path; with no fill there is no instance at all.
    @Test
    func analyticShapesHandTheirOutlineOver() {
        let drawer = Drawer()
        drawer.stroke(.black)
        drawer.strokeWeight(2)
        drawer.noFill()
        drawer.strokeDash(.dashes(10))
        drawer.drawCircle(50, 50, 20)
        #expect(drawer.sdfInstances.isEmpty)
        #expect(!drawer.vertices.isEmpty)

        let filled = Drawer()
        filled.stroke(.black)
        filled.strokeWeight(2)
        filled.fill(.red)
        filled.strokeDash(.dashes(10))
        filled.drawRect(Rectangle(x: 10, y: 10, width: 40, height: 30), cornerRadius: 6)
        #expect(filled.sdfInstances.count == 1)
        #expect(filled.sdfInstances[0].strokeWidth == 0)
        #expect(!filled.vertices.isEmpty)

        // The same shapes without a dash are the one instance they always were.
        let plain = Drawer()
        plain.stroke(.black)
        plain.strokeWeight(2)
        plain.drawCircle(50, 50, 20)
        #expect(plain.sdfInstances.count == 1)
        #expect(plain.vertices.isEmpty)
    }

    /// Each dash crosses to the web page as a source of its own.
    @Test
    func eachDashCrossesAsItsOwnSource() {
        let drawer = Drawer()
        drawer.recordsWebSources = true
        drawer.stroke(.black)
        drawer.strokeWeight(3)
        drawer.strokeDash(.dashes(10))
        drawer.drawPolyline(line)
        #expect(drawer.webSources.count == 5)
        for source in drawer.webSources {
            guard case .stroke(let closed, _, _, _, _, _, _, _, _) = source.kind else {
                Issue.record("a dash crossed as something other than a stroke")
                continue
            }
            #expect(!closed)
            #expect(source.points.count == 2)
        }
    }

    // MARK: The vector file

    /// The file carries every dash as a subpath of its own, so a plotter lifts
    /// the pen at each gap, and the fill under a dashed outline stays whole.
    @Test
    func dashesExportAsSubpaths() {
        let svg = OllinApp.svg(of: DashedLineFixture())
        #expect(svg.contains("<path d=\"M 0 50 L 10 50 M 20 50 L 30 50 M 40 50 L 50 50 M 60 50 L 70 50 M 80 50 L 90 50\""))
        // The rectangle's fill is the element it always was, and its dashed
        // outline is a path with no closing command.
        #expect(svg.contains("<rect x=\"10\" y=\"10\" width=\"40\" height=\"20\""))
        let outline = svg.components(separatedBy: "\n").first { $0.contains("<path d=\"M 10 10") }
        #expect(outline != nil)
        #expect(outline?.contains(" Z") == false)
        #expect(outline?.contains("stroke=\"rgb(0,0,0)\"") == true)
    }

    private final class DashedLineFixture: Sketch {
        override var canvasSize: CanvasSize { .square(100) }
        override func draw() {
            background(.white)
            stroke(.black)
            strokeWeight(2)
            strokeDash([10, 10])
            drawLine(Vector2(0, 50), Vector2(100, 50))
            fill(.red)
            drawRect(10, 10, 40, 20)
        }
    }

    // MARK: Rendered

    /// The gaps are paper and the dashes are ink, exactly where the pattern
    /// says, with butt caps ending each dash on its own point.
    @Test(.enabled(if: Snapshot.hasMetal))
    func gapsStayBlankAndDashesInk() throws {
        let image = try #require(OllinApp.image(of: DashedLineProbe()))
        let px = pixels(of: image)
        // Dashes of 40 with gaps of 20 from x = 20: ink on 20...60, 80...120, 140...180, 200...220.
        for x in [30, 50, 90, 110, 150, 170, 210] { #expect(px.gray(x, 64) <= 12, "ink at \(x)") }
        for x in [66, 74, 126, 134, 186, 194, 230] { #expect(px.gray(x, 64) >= 250, "paper at \(x)") }
    }

    /// A dashed circle is a ring with gaps: some of it ink, some of it paper,
    /// rather than the continuous band the instance draws.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDashedCircleIsARingWithGaps() throws {
        let image = try #require(OllinApp.image(of: DashedCircleProbe()))
        let px = pixels(of: image)
        var ink = 0, paper = 0
        for k in 0..<360 {
            let a = Double(k) / 360 * 2 * .pi
            let x = Int((128 + cos(a) * 40).rounded()), y = Int((64 + sin(a) * 40).rounded())
            if px.gray(x, y) <= 60 { ink += 1 } else if px.gray(x, y) >= 200 { paper += 1 }
        }
        #expect(ink > 100)
        #expect(paper > 100)
    }

    /// A taper tapers across the gaps: the first dash of a ramp is fat and the
    /// last is thin, rather than every dash starting the ramp over.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aProfileTapersAcrossTheGaps() throws {
        let image = try #require(OllinApp.image(of: TaperedDashesProbe()))
        let px = pixels(of: image)
        func ink(_ x: Int) -> Int { (30..<98).reduce(0) { $0 + 255 - px.gray(x, $1) } }
        #expect(ink(40) > ink(100))
        #expect(ink(100) > ink(160))
        #expect(ink(160) > ink(212))
        #expect(ink(212) > 0)
    }
}

// MARK: - Helpers

private struct Pixels {
    var bytes: [UInt8]
    var width: Int
    func gray(_ x: Int, _ y: Int) -> Int { Int(bytes[(y * width + x) * 4]) }
}

private func pixels(of image: CGImage) -> Pixels {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return Pixels(bytes: bytes, width: w)
}

private final class DashedLineProbe: Sketch {
    override var canvasSize: CanvasSize { .size(256, 128) }

    override func draw() {
        background(.white)
        stroke(.black)
        strokeWeight(8)
        strokeCap(.butt)
        strokeDash([40, 20])
        drawLine(Vector2(20, 64), Vector2(220, 64))
    }
}

private final class DashedCircleProbe: Sketch {
    override var canvasSize: CanvasSize { .size(256, 128) }

    override func draw() {
        background(.white)
        noFill()
        stroke(.black)
        strokeWeight(6)
        strokeDash([20, 20])
        drawCircle(128, 64, 40)
    }
}

private final class TaperedDashesProbe: Sketch {
    override var canvasSize: CanvasSize { .size(256, 128) }

    override func draw() {
        background(.white)
        stroke(.black)
        strokeWeight(18)
        strokeCap(.butt)
        strokeProfile(.ramp(from: 1, to: 0.15))
        strokeDash([40, 20])
        drawLine(Vector2(20, 64), Vector2(220, 64))
    }
}
