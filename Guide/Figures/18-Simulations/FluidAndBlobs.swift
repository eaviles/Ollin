// figure: frame=260 unstable
//
// Guide diagram (Chapter 18): the two particle-dynamics systems, mid-motion.
// Left, an SPH fluid released as a dam break, sloshing up the far wall.
// Right, shape-matched soft bodies piled and squashing against each other.
import Ollin

final class FluidAndBlobs: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0xF7F5F1)
    let soft = Color(hex: 0xF7F5F1, alpha: 0.22)

    let left = Rectangle(x: 44, y: 70, width: 384, height: 340)
    let right = Rectangle(x: 452, y: 70, width: 384, height: 340)

    var fluid: ParticleFluid!
    var blobs: SoftBodies!

    override func setup() {
        fluid = particleFluid(count: 4200, radius: 11, bounds: left, seed: 3)
        blobs = softBodies(count: 9, radius: 44, bounds: right, seed: 5)
    }

    override func draw() {
        background(Color(hex: 0x0B0D12))

        // Stir the pool so the figure catches a real free surface, not a
        // settled block.
        let a = Double(frameCount) * 0.05
        fluid.push(at: Vector2(left.x + left.width * (0.5 + cos(a) * 0.34),
                               left.y + left.height * 0.78),
                   strength: 5200, radius: 120)

        blendMode(.add)
        updateParticleFluid(fluid)
        drawParticles(fluid)
        blendMode(.normal)

        updateSoftBodies(blobs)
        drawParticles(blobs)

        frame(left, title: "particle fluid (SPH)")
        frame(right, title: "soft bodies (shape matching)")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("thousands of particles, negotiating", width / 2, 462)
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
