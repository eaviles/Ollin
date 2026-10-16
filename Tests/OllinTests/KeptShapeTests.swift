import Testing
@testable import Ollin

/// A shape drawn again unchanged copies the triangles and stroke it kept from
/// an earlier draw instead of working them out again. Each test compares what
/// a kept shape lays into the frame with what a fresh value of the same shape
/// (one with no memory) lays down under the same settings, byte for byte, and
/// the memory's own closures say whether anything was worked out again.
@Suite
@MainActor
struct KeptShapeTests {

    /// A concave outline with a hole, the case a fill has to triangulate.
    private let shape: Shape = {
        let outer = (0..<90).map { i -> Vector2 in
            let a = Double.tau * Double(i) / 90
            let r = 120 + 35 * sin(a * 5)
            return Vector2(200 + cos(a) * r, 200 + sin(a) * r)
        }
        let hole = (0..<24).map { i -> Vector2 in
            let a = -Double.tau * Double(i) / 24
            return Vector2(200 + cos(a) * 30, 200 + sin(a) * 30)
        }
        return Shape(outer: outer, holes: [hole])
    }()

    /// A shape with the same contours and no memory of its own.
    private func fresh(_ shape: Shape) -> Shape {
        Shape(contours: shape.contours, winding: shape.winding)
    }

    private func drawer() -> Drawer {
        let d = Drawer()
        d.beginFrame()
        d.fill(Color(red: 0.2, green: 0.5, blue: 0.9, alpha: 0.4))
        d.stroke(Color(red: 1, green: 0.8, blue: 0.1, alpha: 0.7))
        d.strokeWeight(3)
        return d
    }

    /// The bytes and batch layout `shape` lays down on a fresh frame with
    /// `setup` applied first.
    private func laid(_ shape: Shape, color hue: Double = 0, _ setup: (Drawer) -> Void = { _ in }) -> [UInt8] {
        let d = drawer()
        d.fill(Color(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 0.5))
        d.stroke(Color(hue: hue + 0.4, saturation: 0.5, brightness: 1, alpha: 0.8))
        setup(d)
        d.drawShape(shape)
        var bytes = d.vertices.withUnsafeBytes { Array($0) }
        for batch in d.batches {
            bytes += withUnsafeBytes(of: batch.vertexStart) { Array($0) } + [batch.kind == .fringe ? 1 : 0]
        }
        return bytes
    }

    @Test func aShapeDrawnAgainLaysDownWhatAFreshOneDoes() {
        let kept = shape
        for (draw, hue) in [0.0, 0.3, 0.55, 0.8, 0.1].enumerated() {
            let transform: (Drawer) -> Void = { d in
                d.translate(Vector2(30 + Double(draw) * 7, -12))
                d.rotate(0.2 * Double(draw))
            }
            #expect(laid(kept, color: hue, transform) == laid(fresh(kept), color: hue, transform),
                    "draw \(draw + 1)")
        }
    }

    @Test func fromTheThirdDrawNothingIsWorkedOutAgain() {
        let kept = shape
        _ = laid(kept)
        _ = laid(kept)
        let d = drawer()
        let fill = kept.memory.fill(of: kept) {
            Issue.record("the fill was triangulated again")
            return []
        }
        #expect(!fill.isEmpty)
        for index in kept.contours.indices {
            let stroke = kept.memory.stroke(of: kept, contour: index, key: d.plainStrokeKey) {
                Issue.record("contour \(index) was expanded again")
                return []
            }
            #expect(!stroke.isEmpty)
        }
        // A copy of the value shares what it kept.
        let copy = kept
        _ = copy.memory.fill(of: copy) {
            Issue.record("a copy triangulated again")
            return []
        }
    }

    @Test func aShapeDrawnOnceKeepsNothing() {
        let once = shape
        _ = laid(once)
        var worked = 0
        _ = once.memory.fill(of: once) { worked += 1; return once.triangulatedFill() }
        #expect(worked == 1)
    }

    @Test func anEditedCopyIsDrawnAsItsOwnShape() {
        let kept = shape
        for _ in 0..<3 { _ = laid(kept) }
        var moved = kept
        moved.contours[0].points[10] = moved.contours[0].points[10] + Vector2(60, 0)
        #expect(laid(moved) == laid(fresh(moved)))
        var rewound = kept
        rewound.winding = .nonZero
        #expect(laid(rewound) == laid(fresh(rewound)))
        // The original, drawn after its copies, is still itself.
        #expect(laid(kept) == laid(fresh(kept)))
    }

    @Test func aNewWidthJoinCapOrScaleExpandsAgain() {
        var open = shape
        open.contours[0].isClosed = false
        let settings: [(String, (Drawer) -> Void)] = [
            ("width", { $0.strokeWeight(9) }),
            ("join", { $0.strokeJoinStyle = .round }),
            ("cap", { $0.strokeCapStyle = .round }),
            ("scale", { $0.scale(2.5, 2.5) }),
        ]
        for (name, setting) in settings {
            // Kept at the plain settings first, then drawn at the new one.
            let kept = fresh(open)
            for _ in 0..<3 { _ = laid(kept) }
            #expect(laid(kept, setting) == laid(fresh(kept), setting), "\(name)")
        }
    }

    @Test func aStrokeWithMoreThanOneColorOrWidthIsNotKept() {
        let settings: [(String, (Drawer) -> Void)] = [
            ("dash", { $0.strokeDashPattern = StrokeDash([12, 6]) }),
            ("profile", { $0.strokeProfileShape = .taper(start: 0.2, end: 0.2) }),
            ("gradient", { $0.stroke(Gradient.linear(from: Vector2(0, 0), to: Vector2(400, 400),
                                                     [.red, .blue])) }),
        ]
        for (name, setting) in settings {
            let kept = fresh(shape)
            for _ in 0..<3 {
                #expect(laid(kept, setting) == laid(fresh(kept), setting), "\(name)")
            }
            // Nothing was kept for the stroke: asking for it works it out.
            let d = drawer()
            setting(d)
            var expanded = false
            _ = kept.memory.stroke(of: kept, contour: 0, key: d.plainStrokeKey) { expanded = true; return [] }
            #expect(expanded, "\(name)")
        }
    }
}
