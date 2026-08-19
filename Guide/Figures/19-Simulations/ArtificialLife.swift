// figure: frame=420 unstable
//
// Guide diagram (Chapter 19): three emergent-behavior systems side by side.
// Left, Particle Life sorts a few kinds into membranes and cells. Middle, the
// Primordial Particle System grows dividing cells from one turning rule.
// Right, Physarum agents lay a trail and steer toward it into a network.
import Ollin

final class ArtificialLife: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0xF7F5F1)
    let soft = Color(hex: 0xF7F5F1, alpha: 0.22)

    let left = Rectangle(x: 30, y: 70, width: 253, height: 340)
    let middle = Rectangle(x: 303, y: 70, width: 253, height: 340)
    let right = Rectangle(x: 576, y: 70, width: 253, height: 340)

    var life: ParticleLife!
    var pps: PPS!
    var slime: Physarum!

    override func setup() {
        life = particleLife(count: 9000, kinds: 5, radius: 34, bounds: left, seed: 3)
        life.forceFactor = 8
        pps = primordialParticles(count: PPS.suggestedCount(for: 16, in: middle),
                                  radius: 16, bounds: middle, seed: 5)
        slime = physarum(agents: 90_000, width: 384, height: 516, seed: 7)
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))

        updatePhysarum(slime)
        drawImage(slime.image, in: right)

        blendMode(.add)
        updateParticleLife(life)
        drawParticles(life)
        updatePPS(pps)
        drawParticles(pps)
        blendMode(.normal)

        frame(left, title: "particle life")
        frame(middle, title: "primordial particles")
        frame(right, title: "physarum")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("three ways a crowd organizes itself", width / 2, 462)
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
