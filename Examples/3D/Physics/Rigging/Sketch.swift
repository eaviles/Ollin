import Foundation
import Ollin
import OllinPhysics

/// Rope, and the thing that makes a rope more than a line of points: every
/// segment carries an orientation of its own.
///
/// Three lines hang from the gantry, all built the same way, from a polyline.
/// The **rope** on the left is limp and drawn as a plain tube. The **chain** in
/// the middle is the same rope with a link drawn on each segment, every other
/// one turned a quarter turn about the rope's own axis so that they interlock;
/// that turn is only possible because each rod knows how it is rolled, which a
/// chain of springs never does. The **vine** on the right resists bending, so
/// it holds a curve of its own, and its leaves are carried and twisted by the
/// stem the same way the links are.
///
/// **Drag** any of them. **Space** stills the wind.
@main
final class Rigging: Sketch {
    let world = World3D()
    var rope: Rope3D!
    var chain: Rope3D!
    var vine: Rope3D!
    var grip: SoftGrip?

    /// How hard the air pushes, in newtons. The gusts are what show a limp rope
    /// and a stiff stem answering the same push differently.
    @Param(0 ... 20, icon: "wind") var wind = 9.0
    var blowing = true

    static let beamHeight = 3.2

    override func setup() {
        world.ground = 0
        world.bounce = 0.05

        // A hanging line is a polyline running straight down from the beam.
        // Anything that makes points makes a rope, so this could as easily be a
        // Contour, a randomWalk, or a ridge off a Heightfield.
        func hangingLine(_ n: Int, spacing: Double) -> [Vector3] {
            (0 ..< n).map { Vector3(0, -Double($0) * spacing, 0) }
        }

        // Long enough that the end of it lies on the floor, which is what
        // reads as rope rather than as a dowel.
        rope = world.addRope(through: hangingLine(56, spacing: 0.09),
                             at: Vector3(-1.25, Rigging.beamHeight, 0),
                             thickness: 0.035, mass: 1.6,
                             bend: 0.02, damping: 0.25, friction: 0.7,
                             pinned: { $0.y > -0.001 })

        chain = world.addRope(through: hangingLine(20, spacing: 0.15),
                              at: Vector3(0, Rigging.beamHeight, 0),
                              thickness: 0.05, mass: 4,
                              bend: 0.06, damping: 0.2, friction: 0.6,
                              pinned: { $0.y > -0.001 },
                              // A chain does not stretch, whatever hangs on it.
                              maxStretch: 1)

        // A stem holds a shape of its own, so it is built already curving.
        let stem = (0 ..< 26).map { i -> Vector3 in
            let t = Double(i) / 25
            return Vector3(sin(t * 2.1) * -0.5 * t, -t * 2.1, cos(t * 1.6) * 0.22 * t)
        }
        vine = world.addRope(through: stem,
                             at: Vector3(1.3, Rigging.beamHeight, 0),
                             thickness: 0.022, mass: 0.5,
                             bend: 0.62, damping: 0.35,
                             iterations: 10,
                             pinned: { $0.y > -0.001 })
    }

    override func draw() {
        background(Color(hex: 0x121820))
        environment(.sky(turbidity: 3.4, sunElevation: 0.62))
        lightingPreset(.standard)
        castShadows()
        camera(.perspective(eye: Vector3(0.7, 2.6, 6.6),
                            target: Vector3(0, 1.6, 0), fieldOfView: .pi / 4.4))

        if blowing {
            // Gusts, not a steady breeze: two rates that never line up, so the
            // three lines are never caught doing the same thing.
            // Across the view rather than into it, so a leaning line reads.
            let gust = wind * (0.55 + 0.45 * sin(time * 0.9) * cos(time * 0.37))
            for line in [rope, chain, vine] {
                line?.applyForce(Vector3(gust, 0, gust * 0.3))
            }
        }
        if let grip { dragSoftGrab(grip, to: mouse) }
        world.step(dt: deltaTime)

        drawSetting()

        // The rope: nothing but its own tube.
        material(.dielectric(roughness: 0.85))
        fill(Color(hex: 0xC8A87A))
        drawSoftBody(rope)

        drawChain()
        drawVine()

        drawCaption("a limp rope, a chain of links, a stem that holds its shape      drag one, space for the wind")
    }

    /// A link on every segment, each one turned a quarter turn from the last
    /// about the rope's own axis. `withSegment(_:)` stands in the middle of a
    /// segment with +y running along it, so a torus laid on its side is a link
    /// the rope passes through, and the alternating roll is what interlocks
    /// them.
    func drawChain() {
        material(.metal(roughness: 0.35))
        fill(Color(hex: 0x8A94A6))
        for segment in chain.segments {
            withSegment(segment) {
                rotate(.pi / 2, axis: Vector3(1, 0, 0))
                if segment.index.isMultiple(of: 2) {
                    rotate(.pi / 2, axis: Vector3(0, 0, 1))
                }
                drawTorus(radius: segment.length * 0.62, tube: 0.026,
                          segments: 20, sides: 8)
            }
        }
    }

    /// Leaves along the stem, each one standing off its own segment. They are
    /// placed by the rod's frame rather than by the line between neighboring
    /// points, so they turn with the stem as it twists rather than only as it
    /// bends.
    func drawVine() {
        material(.dielectric(roughness: 0.7))
        for segment in vine.segments {
            fill(Color(hex: 0x2F6B33))
            withSegment(segment) { drawCylinder(radius: 0.022, height: segment.length * 1.15) }
            guard segment.index % 3 == 1, segment.index > 2 else { continue }
            let side: Double = segment.index.isMultiple(of: 2) ? 1 : -1
            fill(Color(hex: 0x4E9A4A))
            withSegment(segment) {
                rotate(side * 0.9, axis: Vector3(0, 1, 0))
                translate(0.11, 0, 0)
                rotate(.pi / 2.6, axis: Vector3(0, 0, 1))
                scale(1, 0.12, 0.55)
                drawSphere(radius: 0.19, segments: 18, rings: 10)
            }
        }
    }

    func drawSetting() {
        material(.dielectric(roughness: 0.9))
        fill(Color(hex: 0x2A3341))
        drawGround(size: 16, thickness: 0.2)
        fill(Color(hex: 0x4A4137))
        withState {
            translate(0, Rigging.beamHeight + 0.1, 0)
            drawBox(width: 4.1, height: 0.2, depth: 0.2)
        }
        for x in [-1.95, 1.95] {
            withState {
                translate(x, (Rigging.beamHeight + 0.2) / 2, 0)
                drawBox(width: 0.18, height: Rigging.beamHeight + 0.2, depth: 0.18)
            }
        }
    }

    override func mousePressed() {
        grip = grabSoftBody(at: mouse, in: world)
    }

    override func mouseReleased() {
        if let grip { releaseSoftGrab(grip) }
        grip = nil
    }

    override func keyPressed() {
        if key == " " { blowing.toggle() }
    }
}
