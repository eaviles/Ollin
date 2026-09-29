// figure: frame=45
//
// Guide listing (Chapter 11): a strand to hang. Fifteen beads, each linked to
// the one before by a stiff spring, the first pinned. The strand starts laid
// out on a diagonal, and three quarters of a second in it is swinging down
// through its arc.
import Ollin
import OllinPhysics

final class Strand: Sketch {
    let world = World()
    var beads: [Particle] = []

    override func setup() {
        world.gravity = Vector2(0, 1600)
        for i in 0 ..< 15 {
            let bead = world.addParticle(at: Vector2(width / 2 + Double(i) * 16,
                                                     140 + Double(i) * 42))
            beads.append(bead)
        }
        beads[0].pin()
        for i in 1 ..< beads.count {
            world.connect(beads[i - 1], beads[i], stiffness: 0.9)
        }
    }

    override func draw() {
        background(Color(hex: 0x101318))

        if mouseIsPressed {
            beads.last?.place(at: Vector2(mouseX, mouseY))
        }
        world.advance(by: deltaTime)

        stroke(Color(hex: 0x8E99A8))
        strokeWeight(5)
        drawPolyline(beads.map(\.position))
        noStroke()
        fill(Color(hex: 0xF2CC8F))
        for bead in beads {
            drawCircle(center: bead.position, radius: 9)
        }
    }
}
