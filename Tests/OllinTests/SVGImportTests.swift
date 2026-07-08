import Foundation
import Testing
@testable import Ollin

/// SVG import: the path-data grammar, transforms, styles, and document walk.
@Suite struct SVGImportTests {

    // MARK: Helpers

    private func svg(_ body: String, viewBox: String? = "0 0 100 100") -> SVG? {
        let attribute = viewBox.map { " viewBox=\"\($0)\"" } ?? ""
        let text = "<svg xmlns=\"http://www.w3.org/2000/svg\"\(attribute)>\(body)</svg>"
        return SVG(data: Data(text.utf8))
    }

    private func near(_ a: Vector2, _ b: Vector2, tolerance: Double = 1e-6) -> Bool {
        (a - b).length < tolerance
    }

    private func boundsOf(_ points: [Vector2]) -> (min: Vector2, max: Vector2) {
        var lo = Vector2(.infinity, .infinity), hi = Vector2(-.infinity, -.infinity)
        for p in points {
            lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
            hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
        }
        return (lo, hi)
    }

    // MARK: Path grammar

    @Test func absoluteAndRelativeLines() {
        let subpaths = parseSVGPathData("M 10 10 L 20 10 l 0 10")
        #expect(subpaths.count == 1)
        #expect(subpaths[0] == [.move(Vector2(10, 10)), .line(Vector2(20, 10)), .line(Vector2(20, 20))])
    }

    @Test func implicitLinetoAfterMove() {
        // Extra pairs after M are lines; after m they are relative lines.
        let subpaths = parseSVGPathData("m 10 10 10 0 0 10")
        #expect(subpaths[0] == [.move(Vector2(10, 10)), .line(Vector2(20, 10)), .line(Vector2(20, 20))])
    }

    @Test func horizontalAndVertical() {
        let subpaths = parseSVGPathData("M0 0 H10 v5 h-4 V0")
        #expect(subpaths[0] == [.move(Vector2(0, 0)), .line(Vector2(10, 0)), .line(Vector2(10, 5)),
                                .line(Vector2(6, 5)), .line(Vector2(6, 0))])
    }

    @Test func packedNumbers() {
        // Signs and second decimal points separate numbers with no whitespace.
        let subpaths = parseSVGPathData("M1-2L.5.5")
        #expect(subpaths[0] == [.move(Vector2(1, -2)), .line(Vector2(0.5, 0.5))])
        let exponent = parseSVGPathData("M1e1 2E0")
        #expect(exponent[0] == [.move(Vector2(10, 2))])
    }

    @Test func smoothCubicReflectsControl() {
        let subpaths = parseSVGPathData("M0 0 C 0 10, 10 10, 10 0 S 20 -10, 20 0")
        guard case .cubic(let c1, let c2, let end) = subpaths[0][2] else {
            Issue.record("expected a cubic from S")
            return
        }
        // The reflected control mirrors (10, 10) about the pen (10, 0).
        #expect(near(c1, Vector2(10, -10)))
        #expect(near(c2, Vector2(20, -10)))
        #expect(near(end, Vector2(20, 0)))
    }

    @Test func smoothQuadWithoutPredecessorUsesPen() {
        let subpaths = parseSVGPathData("M5 5 T 15 5")
        guard case .quad(let control, let end) = subpaths[0][1] else {
            Issue.record("expected a quad from T")
            return
        }
        #expect(near(control, Vector2(5, 5)))
        #expect(near(end, Vector2(15, 5)))
    }

    @Test func closeSplitsSubpaths() {
        let subpaths = parseSVGPathData("M0 0 L10 0 L10 10 Z M20 20 L30 20")
        #expect(subpaths.count == 2)
        #expect(subpaths[0].last == .close)
        #expect(subpaths[1] == [.move(Vector2(20, 20)), .line(Vector2(30, 20))])
    }

    @Test func arcQuarterCircleEndsWhereItShould() {
        // A quarter arc from (10, 0) to (0, 10), radius 10, sweeping through
        // (≈7.07, ≈7.07): converted to cubics whose endpoint is exact.
        let subpaths = parseSVGPathData("M10 0 A 10 10 0 0 1 0 10")
        guard case .cubic(_, _, let end) = subpaths[0].last else {
            Issue.record("expected a cubic from A")
            return
        }
        #expect(near(end, Vector2(0, 10), tolerance: 1e-9))
    }

    @Test func arcFlagsParseUnseparated() {
        // The two flags and the x coordinate packed together: "0110" reads as
        // flag 0, flag 1, number 10.
        let subpaths = parseSVGPathData("M0 0 a10 10 0 0110 10")
        guard case .cubic(_, _, let end) = subpaths[0].last else {
            Issue.record("expected a cubic from a")
            return
        }
        #expect(near(end, Vector2(10, 10), tolerance: 1e-9))
    }

    @Test func zeroRadiusArcIsALine() {
        let subpaths = parseSVGPathData("M0 0 A 0 10 0 0 1 10 10")
        #expect(subpaths[0] == [.move(Vector2(0, 0)), .line(Vector2(10, 10))])
    }

    @Test func malformedDataStopsWithoutSpinning() {
        // A number after Z has no command to belong to: parsing stops there.
        let subpaths = parseSVGPathData("M0 0 L10 0 Z 5 5")
        #expect(subpaths.count == 1)
        // Garbage mid-stream keeps the well-formed prefix.
        let partial = parseSVGPathData("M0 0 L10 0 L nope")
        #expect(partial[0] == [.move(Vector2(0, 0)), .line(Vector2(10, 0))])
    }

    // MARK: Transforms

    @Test func transformListComposesInOrder() {
        let t = parseSVGTransformList("translate(10 5) scale(2)")
        // Scale first in local terms: p' = translate(scale(p)).
        #expect(near(t.apply(Vector2(1, 1)), Vector2(12, 7)))
    }

    @Test func rotateAboutAPoint() {
        let t = parseSVGTransformList("rotate(90 10 10)")
        #expect(near(t.apply(Vector2(20, 10)), Vector2(10, 20), tolerance: 1e-9))
    }

    @Test func matrixForm() {
        let t = parseSVGTransformList("matrix(0 1 -1 0 10 0)")
        #expect(near(t.apply(Vector2(1, 0)), Vector2(10, 1)))
    }

    @Test func nestedGroupsCompose() {
        let art = svg("""
        <g transform="translate(10 0)"><g transform="scale(2)">
        <rect x="0" y="0" width="5" height="5"/>
        </g></g>
        """)
        let points = art?.elements.first?.shape.contours.first?.points ?? []
        let box = boundsOf(points)
        #expect(near(box.min, Vector2(10, 0)))
        #expect(near(box.max, Vector2(20, 10)))
    }

    @Test func strokeWidthScalesWithTransform() {
        let art = svg("""
        <g transform="scale(3)"><rect x="0" y="0" width="5" height="5" stroke="black" stroke-width="2"/></g>
        """)
        #expect(art?.elements.first?.strokeWidth == 6)
    }

    // MARK: Shapes

    @Test func rectCornersAndWinding() {
        let art = svg("<rect x=\"10\" y=\"20\" width=\"30\" height=\"40\"/>")
        guard let contour = art?.elements.first?.shape.contours.first else {
            Issue.record("no rect contour")
            return
        }
        #expect(contour.isClosed)
        let box = boundsOf(contour.points)
        #expect(near(box.min, Vector2(10, 20)))
        #expect(near(box.max, Vector2(40, 60)))
    }

    @Test func circleBoundsMatchRadius() {
        let art = svg("<circle cx=\"50\" cy=\"50\" r=\"20\"/>")
        guard let contour = art?.elements.first?.shape.contours.first else {
            Issue.record("no circle contour")
            return
        }
        let box = boundsOf(contour.points)
        // The cubic approximation stays within a fraction of a unit.
        #expect(near(box.min, Vector2(30, 30), tolerance: 0.1))
        #expect(near(box.max, Vector2(70, 70), tolerance: 0.1))
    }

    @Test func lineIsOpenAndStrokeOnly() {
        let art = svg("<line x1=\"0\" y1=\"0\" x2=\"10\" y2=\"10\" stroke=\"red\"/>")
        guard let element = art?.elements.first else {
            Issue.record("no line element")
            return
        }
        #expect(element.shape.contours.first?.isClosed == false)
        #expect(element.fill == nil)         // an open element never fills
        #expect(element.stroke == Color(hex: 0xFF0000))
    }

    @Test func polygonClosesPolylineDoesNot() {
        let closed = svg("<polygon points=\"0,0 10,0 5,10\"/>")
        #expect(closed?.elements.first?.shape.contours.first?.isClosed == true)
        let open = svg("<polyline points=\"0,0 10,0 5,10\" stroke=\"black\"/>")
        #expect(open?.elements.first?.shape.contours.first?.isClosed == false)
    }

    @Test func multiSubpathPathBecomesOneShape() {
        // A ring: outer square, inner square, even-odd.
        let art = svg("""
        <path fill-rule="evenodd" d="M0 0 H40 V40 H0 Z M10 10 H30 V30 H10 Z"/>
        """)
        guard let shape = art?.elements.first?.shape else {
            Issue.record("no shape")
            return
        }
        #expect(shape.contours.count == 2)
        #expect(shape.winding == .evenOdd)
    }

    @Test func defaultWindingIsNonZero() {
        let art = svg("<path d=\"M0 0 H10 V10 H0 Z\"/>")
        #expect(art?.elements.first?.shape.winding == .nonZero)
    }

    // MARK: Styles

    @Test func paintParsing() {
        #expect(parseSVGPaint("none") == SVGPaintValue.none)
        #expect(parseSVGPaint("#f00") == .color(Color(hex: 0xFF0000)))
        #expect(parseSVGPaint("#00ff00") == .color(Color(hex: 0x00FF00)))
        #expect(parseSVGPaint("rgb(255, 0, 0)") == .color(Color(red: 1, green: 0, blue: 0)))
        #expect(parseSVGPaint("rgb(100%, 0%, 0%)") == .color(Color(red: 1, green: 0, blue: 0)))
        #expect(parseSVGPaint("rebeccapurple") == .color(Color(hex: 0x663399)))
        #expect(parseSVGPaint("url(#gradient)") == .unresolved)
        #expect(parseSVGPaint("mystery-paint") == nil)
    }

    @Test func fillNoneIsHonored() {
        let art = svg("<rect x=\"0\" y=\"0\" width=\"10\" height=\"10\" fill=\"none\" stroke=\"black\"/>")
        guard let element = art?.elements.first else {
            Issue.record("no element")
            return
        }
        #expect(element.fill == nil)
        #expect(element.stroke == Color(hex: 0x000000))
    }

    @Test func defaultFillIsBlack() {
        let art = svg("<rect x=\"0\" y=\"0\" width=\"10\" height=\"10\"/>")
        #expect(art?.elements.first?.fill == Color(hex: 0x000000))
        #expect(art?.elements.first?.stroke == nil)
    }

    @Test func inlineStyleWinsOverPresentation() {
        let art = svg("<rect x=\"0\" y=\"0\" width=\"10\" height=\"10\" fill=\"red\" style=\"fill: blue\"/>")
        #expect(art?.elements.first?.fill == Color(hex: 0x0000FF))
    }

    @Test func opacityFoldsIntoAlpha() {
        let art = svg("""
        <g opacity="0.5"><rect x="0" y="0" width="10" height="10" fill="black" fill-opacity="0.5"/></g>
        """)
        let alpha = art?.elements.first?.fill?.alpha ?? 0
        #expect(abs(alpha - 0.25) < 1e-9)
    }

    @Test func strokeJoinAndCapParse() {
        let art = svg("""
        <polyline points="0,0 10,0 10,10" stroke="black" stroke-linejoin="round" stroke-linecap="square"/>
        """)
        #expect(art?.elements.first?.join == .round)
        #expect(art?.elements.first?.cap == .square)
    }

    @Test func displayNoneAndDefsAreSkipped() {
        let art = svg("""
        <defs><rect x="0" y="0" width="10" height="10"/></defs>
        <rect x="0" y="0" width="5" height="5" display="none"/>
        <rect id="visible" x="0" y="0" width="5" height="5"/>
        """)
        #expect(art?.elements.count == 1)
        #expect(art?.elements.first?.name == "visible")
    }

    @Test func gradientPaintFallsBackVisible() {
        let art = svg("<rect x=\"0\" y=\"0\" width=\"10\" height=\"10\" fill=\"url(#g)\"/>")
        #expect(art?.elements.first?.fill != nil)
    }

    // MARK: Document

    @Test func viewBoxBecomesBounds() {
        let art = svg("<rect x=\"0\" y=\"0\" width=\"10\" height=\"10\"/>", viewBox: "0 0 200 100")
        #expect(art?.bounds == Rectangle(x: 0, y: 0, width: 200, height: 100))
    }

    @Test func missingViewBoxFallsBackToGeometry() {
        let art = svg("<rect x=\"10\" y=\"20\" width=\"30\" height=\"40\"/>", viewBox: nil)
        #expect(art?.bounds == Rectangle(x: 10, y: 20, width: 30, height: 40))
    }

    @Test func elementNamedFindsById() {
        let art = svg("""
        <rect id="a" x="0" y="0" width="5" height="5"/>
        <circle id="b" cx="50" cy="50" r="10"/>
        """)
        #expect(art?.element(named: "b") != nil)
        #expect(art?.element(named: "missing") == nil)
    }

    @Test func fittedScalesIntoContainer() {
        let art = svg("<rect x=\"0\" y=\"0\" width=\"100\" height=\"100\" stroke=\"black\" stroke-width=\"2\"/>",
                      viewBox: "0 0 100 100")
        guard let fitted = art?.fitted(in: Rectangle(x: 0, y: 0, width: 400, height: 200)) else {
            Issue.record("no fitted document")
            return
        }
        // Uniform scale (2×), centered in the wide container.
        #expect(fitted.bounds == Rectangle(x: 100, y: 0, width: 200, height: 200))
        #expect(fitted.elements.first?.strokeWidth == 4)
        let box = boundsOf(fitted.elements.first?.shape.contours.first?.points ?? [])
        #expect(near(box.min, Vector2(100, 0)))
        #expect(near(box.max, Vector2(300, 200)))
    }

    @Test func garbageDataReturnsNil() {
        #expect(SVG(data: Data("not xml at all".utf8)) == nil)
        #expect(SVG(data: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)) == nil)
    }

    @Test func documentOrderIsPreserved() {
        let art = svg("""
        <rect id="first" x="0" y="0" width="5" height="5"/>
        <g><rect id="second" x="10" y="0" width="5" height="5"/></g>
        <rect id="third" x="20" y="0" width="5" height="5"/>
        """)
        #expect(art?.elements.map(\.name) == ["first", "second", "third"])
    }
}
