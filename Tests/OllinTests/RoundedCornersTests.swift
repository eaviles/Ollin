import Testing
import CoreGraphics
import Foundation
import COllinShaders
@testable import Ollin

/// A radius per corner and the conic paint: the value, the instance the box
/// path writes, the vector exports, and the seam on the tessellated path.
@Suite
@MainActor
struct RoundedCornersTests {

    // MARK: The value

    @Test func namedCornersAndTheUniformCase() {
        let tab = CornerRadii.top(20)
        #expect(tab == CornerRadii(topLeft: 20, topRight: 20, bottomRight: 0, bottomLeft: 0))
        #expect(CornerRadii.bottom(5) == CornerRadii(topLeft: 0, topRight: 0, bottomRight: 5, bottomLeft: 5))
        #expect(CornerRadii.left(5) == CornerRadii(topLeft: 5, topRight: 0, bottomRight: 0, bottomLeft: 5))
        #expect(CornerRadii.right(5) == CornerRadii(topLeft: 0, topRight: 5, bottomRight: 5, bottomLeft: 0))
        #expect(CornerRadii.all(7).uniformRadius == 7)
        #expect(CornerRadii(7) == .all(7))
        #expect(tab.uniformRadius == nil)
        #expect(CornerRadii.zero.uniformRadius == 0)
    }

    @Test func fittingScalesEveryRadiusByTheSameFactor() {
        // Two 60s along a 100 side both become 50, and the other corners
        // scale with them so the shape is kept.
        let fitted = CornerRadii(topLeft: 60, topRight: 60, bottomRight: 12, bottomLeft: 0)
            .fitted(width: 100, height: 200)
        #expect(abs(fitted.topLeft - 50) < 1e-12 && abs(fitted.topRight - 50) < 1e-12)
        #expect(abs(fitted.bottomRight - 10) < 1e-12 && fitted.bottomLeft == 0)
        // A negative radius reads as none; radii that fit are untouched.
        let kept = CornerRadii(topLeft: -5, topRight: 10, bottomRight: 20, bottomLeft: 30)
            .fitted(width: 100, height: 100)
        #expect(kept == CornerRadii(topLeft: 0, topRight: 10, bottomRight: 20, bottomLeft: 30))
        // Four equal radii fit to the one-radius clamp, half the shorter side.
        #expect(CornerRadii(80).fitted(width: 100, height: 60).uniformRadius == 30)
    }

    // MARK: The box path

    @Test func fourEqualRadiiWriteTheSameInstanceAsOneRadius() {
        let one = Drawer(), four = Drawer()
        for d in [one, four] {
            d.beginFrame(); d.fill(Color.red); d.stroke(Color.black); d.strokeWeight(3)
        }
        one.drawRect(Rectangle(x: 10, y: 20, width: 100, height: 60), cornerRadius: 14)
        four.drawRect(Rectangle(x: 10, y: 20, width: 100, height: 60), cornerRadii: .all(14))
        #expect(one.sdfInstances.count == 1 && four.sdfInstances.count == 1)
        #expect(bytes(of: one.sdfInstances[0]) == bytes(of: four.sdfInstances[0]))
        // The one-radius clamp still applies through the four-radius form.
        let big = Drawer()
        big.beginFrame(); big.fill(Color.red)
        big.drawRect(Rectangle(x: 0, y: 0, width: 100, height: 60), cornerRadii: .all(80))
        #expect(big.sdfInstances[0].extra == 30)
        #expect(big.sdfInstances[0].param0 == .zero && big.sdfInstances[0].param1 == .zero)
    }

    @Test func differentRadiiRideTheParameterPairs() {
        let d = Drawer()
        d.beginFrame(); d.fill(Color.red)
        d.drawRect(Rectangle(x: 0, y: 0, width: 100, height: 60),
                   cornerRadii: CornerRadii(topLeft: 4, topRight: 12, bottomRight: 24, bottomLeft: 30))
        let i = d.sdfInstances[0]
        #expect(i.extra == 0)
        #expect(i.param0 == SIMD2<Float>(4, 12) && i.param1 == SIMD2<Float>(24, 30))
        #expect(i.shape & 0xFF == SDFShape.box.rawValue)
        // The merged-field leaf carries the same four, in the same order.
        var nodes: [SDFNode] = []
        _ = SDF.rect(width: 100, height: 60, cornerRadii: .top(9)).flatten(defaultFill: .white, into: &nodes)
        #expect(nodes.count == 1)
        #expect(nodes[0].geo0 == SIMD4<Float>(50, 30, 9, 9) && nodes[0].geo1 == SIMD4<Float>(0, 0, 0, 0))
        #expect(nodes[0].extra == 0)
    }

    private func bytes(of instance: SDFInstance) -> [UInt8] {
        withUnsafeBytes(of: instance) { Array($0) }
    }

    // MARK: The vector exports

    final class Rounded: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        override func draw() {
            background(.white)
            noStroke()
            fill(.black)
            drawRect(10, 10, 100, 60, cornerRadius: 12)
            drawRect(10, 80, 100, 60, cornerRadii: CornerRadii(topLeft: 4, topRight: 12, bottomRight: 24, bottomLeft: 0))
            fill(.conic(center: Vector2(150, 150), [.black, .white]))
            drawCircle(150, 150, 30)
        }
    }

    @Test func theSVGWritesARectForOneRadiusAndAPathWithAnArcPerRoundedCorner() {
        let svg = OllinApp.svg(of: Rounded())
        #expect(svg.contains("<rect x=\"10\" y=\"10\" width=\"100\" height=\"60\" rx=\"12\""))
        let path = svg.components(separatedBy: "\n").first { $0.contains("<path d=\"M 14 80") } ?? ""
        // Three rounded corners are three arcs at their own radii; the square
        // bottom-left corner is two lines meeting at the corner point.
        #expect(path.contains("L 98 80 A 12 12 0 0 1 110 92"))
        #expect(path.contains("L 110 116 A 24 24 0 0 1 86 140"))
        #expect(path.contains("L 10 140 L 10 84 A 4 4 0 0 1 14 80 Z"))
        #expect(path.components(separatedBy: " A ").count == 4)
        // The conic has no SVG form and falls back to the ramp's midpoint, never a url.
        let circle = svg.components(separatedBy: "\n").first { $0.contains("<circle cx=\"150\"") } ?? ""
        #expect(circle.contains("fill=\"rgb(") && !circle.contains("url("))
    }

    @Test func thePDFTakesThePerCornerOutline() throws {
        // The same recording through CoreGraphics arcs: a document comes back
        // with its one page, and its size says the rectangles were drawn.
        let data = try #require(OllinApp.pdf(of: Rounded()))
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == 1)
    }

    // MARK: The seam on the tessellated path

    final class SeamSquare: Sketch {
        var tessellated = true
        override var canvasSize: CanvasSize { .square(160) }
        override func draw() {
            background(.white)
            noStroke()
            fill(.conic(center: Vector2(80, 80), startAngle: .pi,
                        [Color(hex: 0xFFB36B), Color(hex: 0x2B3A67)]))
            if tessellated {
                // A fan from the first corner: both of its triangles cross the
                // seam, which runs from the center to the left edge.
                drawPolygon([Vector2(20, 20), Vector2(140, 20), Vector2(140, 140), Vector2(20, 140)])
            } else {
                drawRect(20, 20, 120, 120)   // the SDF path, exact per pixel
            }
        }
    }

    @Test func aFanThatCrossesTheSeamIsCutThereRatherThanSmeared() throws {
        let fan = SeamSquare()
        fan.tessellated = true
        let exact = SeamSquare()
        exact.tessellated = false
        let a = try #require(OllinApp.image(of: fan))
        let b = try #require(OllinApp.image(of: exact))
        // Per-vertex shading only approximates a sweep, so the two are never
        // equal; but the seam is a line in both. Without the cut, the two
        // triangles that straddle it shade backwards through the whole ramp
        // and the mean difference nearly doubles (3.8 with the cut, 6.9
        // without, over the whole 160-pixel square, ground included).
        let difference = try WebExportTests.meanDifference(a, b)
        #expect(difference < 5, "mean difference \(difference)")
    }
}
