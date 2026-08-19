// figure: frame=0
//
// Guide diagram (Chapter 18): three more fractals that come out of playing a
// small set of transformations. A fractal flame developed from its density
// histogram, the limit set of a ring of tangent mirrors, and the limit curve
// of a two-generator Möbius group.
import Ollin

final class FractalFamily: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let night = Color(hex: 0x0C0F16)
    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)

    var flame: Image?

    override func setup() {
        var source = SplitMix64(seed: 6)
        let recipe = FractalFlame.random(using: &source)
        var draws = SplitMix64(seed: 6)
        flame = recipe.render(width: 262, height: 262, quality: 90, using: &draws)
    }

    override func draw() {
        background(paper)
        seed(3)

        let panels = (0 ..< 3).map {
            Rectangle(x: 25 + Double($0) * 284, y: 66, width: 262, height: 262)
        }

        noStroke()
        fill(night)
        drawRect(panels[0])
        if let flame { drawImage(flame, in: panels[0]) }

        // A ring of mutually tangent mirrors, plus one filling their hole.
        fill(night)
        drawRect(panels[1])
        let center = Vector2(panels[1].x + panels[1].width / 2,
                             panels[1].y + panels[1].height / 2)
        let ringRadius = 78.0
        let count = 5
        let r = ringRadius * sin(.pi / Double(count))
        var mirrors: [Circle] = (0 ..< count).map { i in
            let angle = Double(i) / Double(count) * .tau
            return Circle(center: center + Vector2(cos(angle), sin(angle)) * ringRadius,
                          radius: r)
        }
        mirrors.append(Circle(center: center, radius: ringRadius - r))
        noFill()
        stroke(Color(hex: 0x2A3242))
        strokeWeight(1)
        drawCircles(mirrors)
        noStroke()
        fill(Color(hex: 0xE8C97D, alpha: 0.55))
        drawPoints(inversionLimitSet(of: mirrors, count: 26_000), size: 1.4)

        // One ordered closed curve, no randomness at all.
        fill(night)
        drawRect(panels[2])
        let curve = kleinianLimitSet(.lace)
        noFill()
        stroke(Color(hex: 0x9BD1E5))
        strokeWeight(0.9)
        drawPolygon(fitted(curve.points, in: panels[2].inset(by: .all(16))))

        frame(panels[0], title: "a fractal flame")
        frame(panels[1], title: "mirrors inverting mirrors")
        frame(panels[2], title: "a Kleinian limit curve")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("same idea, three vocabularies of transformation",
                 width / 2, 364)
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
