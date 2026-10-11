import Testing
import CoreGraphics
import simd
@testable import Ollin

/// The vector outline each distance-field shape writes to an SVG traces the
/// shape the GPU draws. The exporter has no shader to ask, so it builds the
/// polygonal shapes' corners and traces the curved ones over a CPU copy of
/// each distance function; if that copy drifts from the shader, a plotter
/// draws a different shape from the screen. Checked away from the edge,
/// where antialiasing has no say: a pixel whose center lies more than
/// 0.75 px inside the outline is fully covered in the render, and one more
/// than 1.5 px outside is empty.
@Suite
@MainActor
struct SDFOutlineTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let draw: @MainActor @Sendable (Sketch) -> Void
        var testDescription: String { name }
    }

    nonisolated static let c = Vector2(48, 50)

    nonisolated static let shapes: [Case] = [
        Case(name: "triangle", draw: { $0.drawTriangle(center: c, radius: 34) }),
        Case(name: "isosceles triangle", draw: { $0.drawTriangle(apex: Vector2(48, 14), base: 60, height: 70) }),
        Case(name: "ngon", draw: { $0.drawNgon(center: c, radius: 36, sides: 7) }),
        Case(name: "star", draw: { $0.drawStar(center: c, outerRadius: 40, innerRadius: 17, points: 5) }),
        Case(name: "hexagon", draw: { $0.drawHexagon(center: c, radius: 36) }),
        Case(name: "rhombus", draw: { $0.drawRhombus(center: c, width: 70, height: 44) }),
        Case(name: "rounded rhombus", draw: { $0.drawRhombus(center: c, width: 70, height: 44, cornerRadius: 6) }),
        Case(name: "vesica", draw: { $0.drawVesica(center: c, width: 70, height: 44) }),
        Case(name: "rounded vesica", draw: { $0.drawVesica(center: c, width: 70, height: 44, cornerRadius: 4) }),
        Case(name: "moon", draw: { $0.drawMoon(center: c, outerRadius: 36, innerRadius: 26, offset: 14) }),
        Case(name: "cross", draw: { $0.drawCross(center: c, length: 70, thickness: 20) }),
        Case(name: "rounded cross", draw: { $0.drawCross(center: c, length: 70, thickness: 20, cornerRadius: 5) }),
        Case(name: "ring", draw: { $0.drawRing(center: c, innerRadius: 18, outerRadius: 38) }),
        Case(name: "trapezoid", draw: { $0.drawTrapezoid(center: c, topWidth: 36, bottomWidth: 76, height: 50) }),
        Case(name: "parallelogram", draw: { $0.drawParallelogram(center: c, width: 56, height: 40, skew: 14) }),
        Case(name: "egg", draw: { $0.drawEgg(center: c, bottomRadius: 30, topRadius: 16) }),
        Case(name: "heart", draw: { $0.drawHeart(center: c, size: 70) }),
        Case(name: "cut disk", draw: { $0.drawCutDisk(center: c, radius: 36, cut: 14) }),
        Case(name: "uneven capsule", draw: { $0.drawUnevenCapsule(Vector2(28, 66), Vector2(66, 30), 18, 9) }),
        Case(name: "horseshoe", draw: { $0.drawHorseshoe(center: c, radius: 30, thickness: 8, gap: 0.8) }),
        Case(name: "parabola", draw: { $0.drawParabola(center: c, width: 70, height: 50) }),
        Case(name: "rounded x", draw: { $0.drawRoundedX(center: c, length: 76, thickness: 12) }),
        Case(name: "blobby cross", draw: { $0.drawBlobbyCross(center: c, radius: 38, blobbiness: 0.4) }),
        Case(name: "tunnel", draw: { $0.drawTunnel(center: c, width: 56, height: 70) }),
        Case(name: "stairs", draw: { $0.drawStairs(center: c, stepWidth: 14, stepHeight: 12, steps: 5) }),
        Case(name: "cool s", draw: { $0.drawCoolS(center: c, size: 76) }),
        Case(name: "oriented box", draw: { $0.drawOrientedBox(Vector2(16, 20), Vector2(80, 78), thickness: 22) }),
        Case(name: "oriented vesica", draw: { $0.drawOrientedVesica(Vector2(16, 20), Vector2(80, 78), width: 30) }),
        Case(name: "pie", draw: { $0.drawArc(center: c, radiusX: 38, radiusY: 38, start: 0.4, stop: 4.4, mode: .pie) }),
        Case(name: "chord", draw: { $0.drawArc(center: c, radiusX: 38, radiusY: 38, start: 0.4, stop: 4.4, mode: .chord) }),
        Case(name: "square marker", draw: { $0.pointMarker(.square); $0.drawPoint(at: c, size: 60) }),
        Case(name: "diamond marker", draw: { $0.pointMarker(.diamond); $0.drawPoint(at: c, size: 60) }),
        Case(name: "cross marker", draw: { $0.pointMarker(.cross); $0.drawPoint(at: c, size: 60) }),
        Case(name: "x marker", draw: { $0.pointMarker(.x); $0.drawPoint(at: c, size: 60) }),
    ]

    @Test(arguments: shapes)
    func theExportedOutlineTracesTheRender(_ shape: Case) throws {
        let render = Pixels(try OllinApp.image(of: OneShape(shape.draw), frame: 1))
        let recording = OllinApp.recordVectorFrame(of: OneShape(shape.draw), frame: 1, fps: 60, hatching: nil)
        var rings: [[Vector2]] = []
        for command in recording.commands {
            guard case let .draw(recorded) = command else { continue }
            #expect(recorded.transform == matrix_identity_float3x3)
            switch recorded.geometry {
            case let .polygon(points): rings.append(points)
            case let .path(outline): rings += outline.contours.map(\.points)
            default: Issue.record("\(shape.name) wrote \(recorded.geometry), not an outline")
            }
        }
        try #require(!rings.isEmpty, "\(shape.name) wrote no outline")
        var wrongInside = 0, wrongOutside = 0, first: (Int, Int)?
        for y in 0 ..< render.height {
            for x in 0 ..< render.width {
                let p = Vector2(Double(x) + 0.5, Double(y) + 0.5)
                let edge = distanceToEdges(p, rings)
                let gray = render.gray(x, y)
                if edge > 0.75, isInside(p, rings), gray < 250 {
                    wrongInside += 1; first = first ?? (x, y)
                } else if edge > 1.5, !isInside(p, rings), gray > 5 {
                    wrongOutside += 1; first = first ?? (x, y)
                }
            }
        }
        let check = {
            #expect(wrongInside == 0 && wrongOutside == 0,
                    "\(shape.name): \(wrongInside) pixels inside the outline not covered, \(wrongOutside) outside it inked, first at \(String(describing: first))")
        }
        if let gap = Self.knownGaps[shape.name] {
            withKnownIssue(Comment(rawValue: gap)) { check() }
        } else {
            check()
        }
    }

    /// The gaps this test measured on its first run (2026-10-10), filed in
    /// DESIGN-NOTES (the blobby cross under *Rendering and color frontier*,
    /// the traced corners under *New output surfaces*). A fix takes its
    /// entry off.
    nonisolated static let knownGaps: [String: String] = [
        "blobby cross": "the formula is a bound that reports a fraction of the distance past each tip (0.68 px where the true distance is 4.5 px), so the render draws a faint spike past every tip out to the quad's edge; the outline ends at the tip",
        "cut disk": "the tracer's 1.5-unit grid chamfers the sharp corners where the chord meets the circle, so the outline cuts each by about 2.4 px",
        "horseshoe": "the tracer's 1.5-unit grid chamfers the square ends of the arms by about 1.7 px",
    ]

    /// Even-odd containment over every loop, the rule a traced outline with a
    /// hole is written with.
    private func isInside(_ p: Vector2, _ rings: [[Vector2]]) -> Bool {
        var inside = false
        for ring in rings where ring.count > 2 {
            var j = ring.count - 1
            for i in ring.indices {
                let a = ring[i], b = ring[j]
                if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                    inside.toggle()
                }
                j = i
            }
        }
        return inside
    }

    private func distanceToEdges(_ p: Vector2, _ rings: [[Vector2]]) -> Double {
        var best = Double.infinity
        for ring in rings where ring.count > 1 {
            for i in ring.indices {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let ab = b - a, ap = p - a
                let t = max(0, min(1, (ap.x * ab.x + ap.y * ab.y) / max(ab.x * ab.x + ab.y * ab.y, 1e-12)))
                let q = a + ab * t
                best = min(best, ((p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)).squareRoot())
            }
        }
        return best
    }
}

/// White on black, filled, no stroke, one shape.
@MainActor
private final class OneShape: Sketch {
    var paint: (Sketch) -> Void = { _ in }

    convenience init(_ paint: @escaping (Sketch) -> Void) {
        self.init()
        self.paint = paint
    }

    override var canvasSize: CanvasSize { .square(96) }

    override func draw() {
        background(.black)
        noStroke()
        fill(.white)
        paint(self)
    }
}
