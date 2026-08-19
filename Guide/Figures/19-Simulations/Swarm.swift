// figure: frame=260 unstable
//
// Guide diagram (Chapter 19): the same steering agents under three sets of
// weights. Left, the three flocking rules. Middle, a flow field carrying
// everyone. Right, each one wandering on its own. Trails come from a
// translucent sheet over an accumulating canvas, so the picture shows how the
// agents moved rather than only where they ended up.
import Ollin

final class SwarmFigure: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0xF7F5F1)
    let soft = Color(hex: 0xF7F5F1, alpha: 0.22)

    let left = Rectangle(x: 30, y: 70, width: 253, height: 340)
    let middle = Rectangle(x: 303, y: 70, width: 253, height: 340)
    let right = Rectangle(x: 576, y: 70, width: 253, height: 340)

    var flocking: Swarm!
    var flowing: Swarm!
    var roaming: Swarm!

    let palette = [Color(hue: 0.55, saturation: 0.7, brightness: 0.55),
                   Color(hue: 0.62, saturation: 0.6, brightness: 0.5),
                   Color(hue: 0.47, saturation: 0.6, brightness: 0.46)]

    override func setup() {
        background(Color(hex: 0x0B0D12))
        noClear()

        flocking = swarm(count: 4200, perceptionRadius: 15, colors: palette,
                         size: 1.4, bounds: left, seed: 3)
        flocking.separation = 1.5
        flocking.alignment = 1.5
        flocking.cohesion = 0.8
        flocking.separationRadius = 5

        flowing = swarm(count: 4200, perceptionRadius: 15, colors: palette,
                        size: 1.4, bounds: middle, seed: 5)
        flowing.flow = 1.4
        flowing.flowScale = 0.016

        roaming = swarm(count: 900, perceptionRadius: 15, colors: palette,
                        size: 1.4, bounds: right, seed: 7)
        roaming.wander = 1.2

        for s in [flocking, flowing, roaming] {
            s?.maxSpeed = 150
            s?.maxForce = 600
            s?.minSpeed = 40
        }
    }

    override func draw() {
        // Fade what is already on the canvas rather than wiping it, so each agent
        // leaves the path it took. `background` would clear the whole thing.
        blendMode(.normal)
        noStroke()
        fill(Color(hex: 0x0B0D12, alpha: 0.10))
        drawRect(0, 0, width, height)

        blendMode(.add)
        for s in [flocking, flowing, roaming] {
            updateSwarm(s!)
            drawParticles(s!)
        }
        blendMode(.normal)

        // The panels sit on a shared canvas, so mask everything outside them.
        fill(Color(hex: 0x0B0D12))
        drawRect(0, 0, width, left.y)
        drawRect(0, left.y + left.height, width, height - left.y - left.height)
        drawRect(0, left.y, left.x, left.height)
        drawRect(left.x + left.width, left.y, middle.x - left.x - left.width, left.height)
        drawRect(middle.x + middle.width, left.y, right.x - middle.x - middle.width, left.height)
        drawRect(right.x + right.width, left.y, width - right.x - right.width, left.height)

        frame(left, title: "flocking")
        frame(middle, title: "a current")
        frame(right, title: "roaming")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one set of urges, three sets of weights", width / 2, 462)
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
        drawText(title, r.x + 2, r.y - 20)
    }
}
