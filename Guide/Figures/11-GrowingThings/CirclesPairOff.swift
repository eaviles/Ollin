// figure: frame=0
//
// Guide diagram (Chapter 11): how a Schottky group's lace builds up. The four
// pairing circles on their own, the first generation of images nesting inside
// them, and the whole orbit. No randomness anywhere.
import Ollin

final class CirclesPairOff: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let night = Color(hex: 0x0C0F16)
    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let gold = Color(hex: 0xE8C97D)
    let blue = Color(hex: 0x9BD1E5)

    override func draw() {
        background(paper)

        let panels = (0 ..< 3).map {
            Rectangle(x: 25 + Double($0) * 284, y: 66, width: 262, height: 262)
        }

        for panel in panels {
            noStroke()
            fill(night)
            drawRect(panel)
        }

        let pairings = schottkyCuspedPairs(in: panels[0].inset(by: .all(18)))

        // The four circles on their own, one color per pair, with the two
        // points where a pair touches.
        noFill()
        strokeWeight(1.6)
        for (index, pairing) in pairings.enumerated() {
            stroke(index == 0 ? gold : blue)
            drawCircle(pairing.from)
            drawCircle(pairing.to)
        }
        noStroke()
        for (index, pairing) in pairings.enumerated() {
            fill(index == 0 ? gold : blue)
            drawCircle(center: Vector2((pairing.from.x + pairing.to.x) / 2,
                                       (pairing.from.y + pairing.to.y) / 2),
                       radius: 4)
        }

        // One generation of images, then the whole orbit. Both arrangements are
        // the panel-0 one slid across, so the three panels line up.
        drawOrbit(into: panels[1], from: panels[0], maxDepth: 1, weight: 1.2, alpha: 0.85)
        drawOrbit(into: panels[2], from: panels[0], maxDepth: 60, weight: 0.5, alpha: 0.4)

        frame(panels[0], title: "four circles, paired")
        frame(panels[1], title: "each pairing, applied once")
        frame(panels[2], title: "applied in every order")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("every circle lands inside its partner, smaller", width / 2, 364)
    }

    /// The orbit of the panel-0 arrangement, shifted into `panel` and clipped
    /// to it, since the early images swing well outside the four circles.
    func drawOrbit(into panel: Rectangle, from source: Rectangle,
                   maxDepth: Int, weight: Double, alpha: Double) {
        let pairings = schottkyCuspedPairs(in: source.inset(by: .all(18)))
        let shift = Vector2(panel.x - source.x, 0)
        withClip(panel) {
            noFill()
            strokeWeight(weight)
            stroke(Color(white: 0.92, alpha: alpha))
            for circle in schottkyCircles(pairing: pairings, minRadius: 0.4,
                                          maxDepth: maxDepth) {
                drawCircle(Circle(center: circle.center + shift, radius: circle.radius))
            }
            strokeWeight(1.6)
            for (index, pairing) in pairings.enumerated() {
                stroke(index == 0 ? gold : blue)
                drawCircle(Circle(center: pairing.from.center + shift,
                                  radius: pairing.from.radius))
                drawCircle(Circle(center: pairing.to.center + shift,
                                  radius: pairing.to.radius))
            }
        }
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
