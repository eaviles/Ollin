import Ollin
import OllinPhysics

/// A slow rain of solids (crates, balls, capsules, drums) piling up on the
/// floor, and a hand that can reach in: **drag** any shape to fling it around,
/// and the pile makes room; **space** clears it. The mixed-collider showcase
/// for `World3D`: every form is one `addBody` with a different `Collider3D`,
/// drawn by matching a mesh to `body.collider` inside `withBody`.
///
/// Grabbing is the two sketch calls: `grabBody(at:in:)` ray-picks the body
/// under the cursor through the camera and hangs it on a soft drag spring,
/// `dragGrab(_:to:)` pulls it along the cursor at the depth it was picked.
/// The camera stays hand-set here so the mouse belongs to the pile.
@main
final class Tumble3D: Sketch {
    let world = World3D()
    let maxBodies = 90
    var grabbed: Joint3D?

    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B), Color(hex: 0x72BFB2),
        Color(hex: 0x8D92E0), Color(hex: 0xDE87B2), Color(hex: 0x9CCB6B),
    ]

    override func setup() {
        world.ground = 0
        world.bounce = 0.15
    }

    /// Drop one random solid from above the pile with a little spin.
    func spawn() {
        guard world.bodies.count < maxBodies else { return }
        let collider: Collider3D
        switch Int(random(4)) {
        case 0: collider = .box(width: random(0.5, 0.9), height: random(0.4, 0.8),
                                depth: random(0.5, 0.9))
        case 1: collider = .sphere(radius: random(0.25, 0.45))
        case 2: collider = .capsule(height: random(0.4, 0.8), radius: random(0.16, 0.26))
        default: collider = .cylinder(height: random(0.4, 0.8), radius: random(0.22, 0.38))
        }
        let body = world.addBody(collider,
                                 at: Vector3(random(-1.6, 1.6), random(6, 8), random(-1.6, 1.6)),
                                 rotated: random(.tau),
                                 axis: Vector3(random(-1, 1), random(-1, 1), random(-1, 1)),
                                 friction: 0.5, restitution: random(0.05, 0.3))
        body.angularVelocity = Vector3(random(-3, 3), random(-3, 3), random(-3, 3))
        body.userData = randomChoice(palette)
    }

    override func mousePressed() {
        grabbed = grabBody(at: mouse, in: world)
    }

    override func mouseReleased() {
        grabbed?.remove()
        grabbed = nil
    }

    override func keyPressed() {
        if key == " " { world.removeAll() }
    }

    override func draw() {
        background(Color(hex: 0x10131A))
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(5.2, 4.6, 7.8), target: Vector3(0, 1.2, 0))

        if frameCount % 18 == 0 { spawn() }
        if let grabbed { dragGrab(grabbed, to: mouse) }
        world.step(dt: deltaTime)

        fill(Color(hex: 0x1C222C))
        material(.dielectric(roughness: 0.85))
        drawGround(size: 24)

        material(.dielectric(roughness: 0.5))
        for body in world.bodies {
            fill(body.userData as? Color ?? .white)
            drawBody(body)
        }
    }
}
