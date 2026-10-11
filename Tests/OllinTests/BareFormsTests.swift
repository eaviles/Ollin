import Testing
import CoreGraphics
@testable import Ollin

/// Every bare drawing call with scalar arguments draws what its value-type
/// twin draws, pixel for pixel: the positional form and the labeled one are
/// two spellings of one primitive. The numbers are uneven on purpose (a
/// center off the middle, a width unlike its height, two radii that differ),
/// so a form that handed two of them over in the wrong order would draw
/// something else.
@Suite
@MainActor
struct BareFormsTests {

    /// One primitive's two spellings.
    struct Pair: Sendable, CustomTestStringConvertible {
        let name: String
        let bare: @MainActor @Sendable (Sketch) -> Void
        let twin: @MainActor @Sendable (Sketch) -> Void
        var testDescription: String { name }
    }

    nonisolated static let c = Vector2(30, 34)

    nonisolated static let pairs: [Pair] = [
        Pair(name: "circle", bare: { $0.drawCircle(30, 34, 17) }, twin: { $0.drawCircle(center: c, radius: 17) }),
        Pair(name: "circle value", bare: { $0.drawCircle(30, 34, 17) }, twin: { $0.drawCircle(Circle(center: c, radius: 17)) }),
        Pair(name: "ellipse", bare: { $0.drawEllipse(30, 34, 20, 11) },
             twin: { $0.drawEllipse(center: c, radiusX: 20, radiusY: 11) }),
        Pair(name: "triangle by radius", bare: { $0.drawTriangle(30, 34, 18) },
             twin: { $0.drawTriangle(center: c, radius: 18) }),
        Pair(name: "triangle by apex", bare: { $0.drawTriangle(30, 12, 34, 40) },
             twin: { $0.drawTriangle(apex: Vector2(30, 12), base: 34, height: 40) }),
        Pair(name: "triangle by corners", bare: { $0.drawTriangle(6, 50, 52, 44, 24, 8) },
             twin: { $0.drawTriangle(Vector2(6, 50), Vector2(52, 44), Vector2(24, 8)) }),
        Pair(name: "ngon", bare: { $0.drawNgon(30, 34, 20, sides: 7) },
             twin: { $0.drawNgon(center: c, radius: 20, sides: 7) }),
        Pair(name: "star", bare: { $0.drawStar(30, 34, 22, 9, points: 5) },
             twin: { $0.drawStar(center: c, outerRadius: 22, innerRadius: 9, points: 5) }),
        Pair(name: "pentagon", bare: { $0.drawPentagon(30, 34, 19) }, twin: { $0.drawPentagon(center: c, radius: 19) }),
        Pair(name: "hexagon", bare: { $0.drawHexagon(30, 34, 19) }, twin: { $0.drawHexagon(center: c, radius: 19) }),
        Pair(name: "heptagon", bare: { $0.drawHeptagon(30, 34, 19) }, twin: { $0.drawHeptagon(center: c, radius: 19) }),
        Pair(name: "octagon", bare: { $0.drawOctagon(30, 34, 19) }, twin: { $0.drawOctagon(center: c, radius: 19) }),
        Pair(name: "rhombus", bare: { $0.drawRhombus(30, 34, 40, 22, cornerRadius: 3) },
             twin: { $0.drawRhombus(center: c, width: 40, height: 22, cornerRadius: 3) }),
        Pair(name: "vesica", bare: { $0.drawVesica(30, 34, 40, 26, cornerRadius: 2) },
             twin: { $0.drawVesica(center: c, width: 40, height: 26, cornerRadius: 2) }),
        Pair(name: "moon", bare: { $0.drawMoon(30, 34, 20, 14, 7, cornerRadius: 1) },
             twin: { $0.drawMoon(center: c, outerRadius: 20, innerRadius: 14, offset: 7, cornerRadius: 1) }),
        Pair(name: "cross", bare: { $0.drawCross(30, 34, 36, 10, cornerRadius: 2) },
             twin: { $0.drawCross(center: c, length: 36, thickness: 10, cornerRadius: 2) }),
        Pair(name: "ring", bare: { $0.drawRing(30, 34, 9, 20) },
             twin: { $0.drawRing(center: c, innerRadius: 9, outerRadius: 20) }),
        Pair(name: "trapezoid", bare: { $0.drawTrapezoid(30, 34, 20, 40, 26) },
             twin: { $0.drawTrapezoid(center: c, topWidth: 20, bottomWidth: 40, height: 26) }),
        Pair(name: "parallelogram", bare: { $0.drawParallelogram(30, 34, 34, 20, 8) },
             twin: { $0.drawParallelogram(center: c, width: 34, height: 20, skew: 8) }),
        Pair(name: "egg", bare: { $0.drawEgg(30, 34, 16, 9) },
             twin: { $0.drawEgg(center: c, bottomRadius: 16, topRadius: 9) }),
        Pair(name: "heart", bare: { $0.drawHeart(30, 34, 30) }, twin: { $0.drawHeart(center: c, size: 30) }),
        Pair(name: "cut disk", bare: { $0.drawCutDisk(30, 34, 18, 6) },
             twin: { $0.drawCutDisk(center: c, radius: 18, cut: 6) }),
        Pair(name: "uneven capsule", bare: { $0.drawUnevenCapsule(14, 40, 44, 24, 10, 5) },
             twin: { $0.drawUnevenCapsule(Vector2(14, 40), Vector2(44, 24), 10, 5) }),
        Pair(name: "horseshoe", bare: { $0.drawHorseshoe(30, 34, 18, 5, gap: 0.8) },
             twin: { $0.drawHorseshoe(center: c, radius: 18, thickness: 5, gap: 0.8) }),
        Pair(name: "parabola", bare: { $0.drawParabola(30, 34, 40, 20) },
             twin: { $0.drawParabola(center: c, width: 40, height: 20) }),
        Pair(name: "rounded x", bare: { $0.drawRoundedX(30, 34, 40, 6) },
             twin: { $0.drawRoundedX(center: c, length: 40, thickness: 6) }),
        Pair(name: "blobby cross", bare: { $0.drawBlobbyCross(30, 34, 20, blobbiness: 0.3) },
             twin: { $0.drawBlobbyCross(center: c, radius: 20, blobbiness: 0.3) }),
        Pair(name: "tunnel", bare: { $0.drawTunnel(30, 34, 30, 40) },
             twin: { $0.drawTunnel(center: c, width: 30, height: 40) }),
        Pair(name: "stairs", bare: { $0.drawStairs(30, 34, 8, 6, steps: 4) },
             twin: { $0.drawStairs(center: c, stepWidth: 8, stepHeight: 6, steps: 4) }),
        Pair(name: "cool s", bare: { $0.drawCoolS(30, 34, 40) }, twin: { $0.drawCoolS(center: c, size: 40) }),
        Pair(name: "arc", bare: { $0.drawArc(30, 34, 20, 12, start: 0.3, stop: 2.5, mode: .pie) },
             twin: { $0.drawArc(center: c, radiusX: 20, radiusY: 12, start: 0.3, stop: 2.5, mode: .pie) }),
        Pair(name: "arrow", bare: { $0.drawArrow(8, 10, 50, 52, headLength: 9, headWidth: 7) },
             twin: { $0.drawArrow(from: Vector2(8, 10), to: Vector2(50, 52), headLength: 9, headWidth: 7) }),
        Pair(name: "bezier", bare: { $0.drawBezier(6, 50, 20, 4, 56, 40) },
             twin: { $0.drawBezier(Vector2(6, 50), Vector2(20, 4), Vector2(56, 40)) }),
        Pair(name: "line", bare: { $0.drawLine(6, 50, 56, 12) }, twin: { $0.drawLine(Vector2(6, 50), Vector2(56, 12)) }),
        Pair(name: "oriented box", bare: { $0.drawOrientedBox(8, 10, 50, 40, thickness: 7) },
             twin: { $0.drawOrientedBox(Vector2(8, 10), Vector2(50, 40), thickness: 7) }),
        Pair(name: "oriented vesica", bare: { $0.drawOrientedVesica(8, 10, 50, 40, width: 12) },
             twin: { $0.drawOrientedVesica(Vector2(8, 10), Vector2(50, 40), width: 12) }),
        Pair(name: "point", bare: { $0.pointSize(7); $0.drawPoint(30, 34) },
             twin: { $0.pointSize(7); $0.drawPoint(at: c) }),
        Pair(name: "sized point", bare: { $0.drawPoint(30, 34, 9) }, twin: { $0.drawPoint(at: c, size: 9) }),
        Pair(name: "rect by corner", bare: { $0.drawRect(8, 10, 40, 30, cornerRadius: 4) },
             twin: { $0.drawRect(corner: Vector2(8, 10), width: 40, height: 30, cornerRadius: 4) }),
        Pair(name: "rect value", bare: { $0.drawRect(8, 10, 40, 30, cornerRadius: 4) },
             twin: { $0.drawRect(Rectangle(x: 8, y: 10, width: 40, height: 30), cornerRadius: 4) }),
        Pair(name: "rect by center", bare: { $0.drawRect(10, 19, 40, 30, cornerRadius: 4) },
             twin: { $0.drawRect(center: c, width: 40, height: 30, cornerRadius: 4) }),
        Pair(name: "rect corner radii", bare: { $0.drawRect(8, 10, 40, 30, cornerRadii: radii) },
             twin: { $0.drawRect(corner: Vector2(8, 10), width: 40, height: 30, cornerRadii: radii) }),
        Pair(name: "rect corner radii by center", bare: { $0.drawRect(10, 19, 40, 30, cornerRadii: radii) },
             twin: { $0.drawRect(center: c, width: 40, height: 30, cornerRadii: radii) }),
        Pair(name: "rect corner radii value", bare: { $0.drawRect(8, 10, 40, 30, cornerRadii: radii) },
             twin: { $0.drawRect(Rectangle(x: 8, y: 10, width: 40, height: 30), cornerRadii: radii) }),
    ]

    nonisolated static let radii = CornerRadii(topLeft: 2, topRight: 9, bottomRight: 0, bottomLeft: 5)

    @Test(arguments: pairs)
    func theBareFormDrawsItsTwin(_ pair: Pair) throws {
        let bare = pixels(of: try OllinApp.image(of: OneMark(pair.bare), frame: 1))
        let twin = pixels(of: try OllinApp.image(of: OneMark(pair.twin), frame: 1))
        let blank = pixels(of: try OllinApp.image(of: OneMark { _ in }, frame: 1))
        #expect(bare != blank, "the bare form drew nothing")
        #expect(bare == twin)
    }
}

/// A 64-point canvas with one mark on it, filled and stroked so a form that
/// dropped either would show.
@MainActor
private final class OneMark: Sketch {
    var paint: (Sketch) -> Void = { _ in }

    convenience init(_ paint: @escaping (Sketch) -> Void) {
        self.init()
        self.paint = paint
    }

    override var canvasSize: CanvasSize { .square(64) }

    override func draw() {
        background(.black)
        fill(Color(red: 0.95, green: 0.8, blue: 0.3))
        stroke(Color(red: 0.2, green: 0.6, blue: 1))
        strokeWeight(2)
        paint(self)
    }
}
