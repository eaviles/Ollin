// figure: frame=0 themed
//
// Guide diagram (Chapter 31): the embroidery plan. A leaf composed as contours
// (an outline, its veins, and a fill laid as rows), and the same leaf as the
// stitches a machine sews: a dot at every penetration, the thread between them,
// and the jumps where the thread is carried over.
import Ollin
import OllinDiagram

final class StitchPlan: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    override func draw() {
        background(paper)

        let left = Rectangle(x: 90, y: 92, width: 330, height: 180)
        let right = Rectangle(x: 460, y: 92, width: 330, height: 180)

        let (outline, veins) = leaf(in: left)
        let rows = Hatching(spacing: 6, angle: 0.35).lines(filling: Shape(outline))

        // The design as drawn.
        noStroke()
        fill(Color(hex: 0x2E7D4F))
        drawPolygon(outline)
        stroke(Color(hex: 0xF3E6B3))
        strokeWeight(3)
        strokeCap(.round)
        for v in veins { drawPolyline(v) }

        // The same contours planned as stitches, drawn in the right panel.
        var contours = rows.map { Contour($0, closed: false) }
        contours.append(Contour(outline, closed: true))
        contours.append(contentsOf: veins.map { Contour($0, closed: false) })
        let plan = Embroidery(width: 100, stitchLength: 2.2).stitches(contours, in: left)
        let shift = Vector2(right.x - left.x, 0)
        noFill()
        var previous: Vector2?
        for stitch in plan.stitches {
            defer { previous = stitch.position }
            guard let p = previous else { continue }
            switch stitch.kind {
            case .stitch:
                stroke(ink.withAlpha(0.6))
                strokeWeight(1)
            case .jump:
                stroke(theme.ink(0.3))
                strokeWeight(0.6)
            case .colorChange:
                continue
            }
            drawLine(p + shift, stitch.position + shift)
        }
        noStroke()
        fill(ink)
        for stitch in plan.stitches where stitch.kind == .stitch {
            drawCircle(center: stitch.position + shift, radius: 1.3)
        }

        frame(left, title: "the design, as contours")
        frame(right, title: "Embroidery(width: 100).stitches(contours, in:)")

        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("\(plan.stitchCount) stitches, every corner a penetration, fills as rows",
                 width / 2, 312)
    }

    /// A leaf laid out inside `r`: a pointed oval, a midrib, and side veins.
    func leaf(in r: Rectangle) -> ([Vector2], [[Vector2]]) {
        let center = r.center
        let long = r.width * 0.42, wide = r.height * 0.36
        let outline = (0 ..< 96).map { k -> Vector2 in
            let t = Double(k) / 96 * .tau
            let taper = pow(abs(sin(t)), 0.75)
            return center + Vector2(cos(t) * long * (0.9 + 0.1 * taper), sin(t) * wide * taper)
        }
        let tip = center + Vector2(long, 0), base = center - Vector2(long, 0)
        var veins: [[Vector2]] = [[base, tip]]
        for k in 1 ... 5 {
            let along = Double(k) / 6
            let root = base.lerp(to: tip, along)
            for side in [-1.0, 1.0] {
                let reach = wide * 0.8 * sin(along * .pi)
                veins.append([root, root + Vector2(long * 0.16, side * reach * 0.6),
                              root + Vector2(long * 0.3, side * reach)])
            }
        }
        return (outline, veins)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
