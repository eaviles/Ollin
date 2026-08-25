import Ollin
import OllinPhysics

/// A crate pyramid on a floor, and a cannon in your cursor: **click** to fire
/// a heavy ball from the camera at wherever you point, and the tower takes
/// the hit; crates shove, topple, and rebound with real 3D contact response.
/// **Space** rebuilds the pyramid.
///
/// This is the 3D rigid-body world at its simplest: one `World3D` with a
/// `ground`, one `addBody` per crate, `step(dt:)` each frame, and every crate
/// drawn by `withBody`, which moves the transform stack to the body's pose so
/// the mesh and the physics can't drift apart. The cannonball is the same
/// `addBody` with a `.sphere` collider, `density: 6`, and an opening
/// `velocity` down the camera ray.
@main
final class Stack3D: Sketch {
    let world = World3D()

    /// Crate colors, one per level, hung off `userData`.
    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B),
        Color(hex: 0x72BFB2), Color(hex: 0x8D92E0),
    ]

    override func setup() {
        world.ground = 0
        world.bounce = 0.1
        buildTower()
    }

    /// A square pyramid of crates: 4×4 at the base up to a single cap.
    func buildTower() {
        world.removeAll()
        let size = 0.72
        let gap = 0.045
        for level in 0 ..< 4 {
            let count = 4 - level
            let span = Double(count - 1) * (size + gap)
            for row in 0 ..< count {
                for column in 0 ..< count {
                    let crate = world.addBody(
                        .box(width: size, height: size, depth: size),
                        at: Vector3(Double(column) * (size + gap) - span / 2,
                                    size / 2 + Double(level) * (size + gap),
                                    Double(row) * (size + gap) - span / 2),
                        friction: 0.6)
                    crate.userData = palette[level]
                }
            }
        }
    }

    override func mousePressed() {
        // Fire from just inside the camera, down the ray under the cursor.
        guard let camera = activeCamera,
              let ray = cameraRay(through: mouse) else { return }
        let aim = ray.direction
        let ball = world.addBody(.sphere(radius: 0.3),
                                 at: camera.eye + aim * 1.2,
                                 density: 6, friction: 0.4)
        ball.velocity = aim * 24
        ball.userData = Color(hex: 0xD4DCE6)
    }

    override func keyPressed() {
        if key == " " { buildTower() }
    }

    override func draw() {
        background(Color(hex: 0x0B0E13))
        lightingPreset(.studio)
        castShadows()
        cameraShowcase(.autoOrbit(period: 34), radius: 9.5, elevation: 0.24)

        world.step(dt: deltaTime)

        // Cannonballs that rolled off the slab are gone for good.
        for body in world.bodies where body.position.y < -8 {
            world.remove(body)
        }

        // The floor the physics `ground` stands in for.
        fill(Color(hex: 0x1A1F28))
        material(.dielectric(roughness: 0.85))
        drawGround(size: 26)

        material(.dielectric(roughness: 0.55))
        for body in world.bodies {
            fill(body.userData as? Color ?? .white)
            withBody(body) {
                switch body.collider {
                case .box(let w, let h, let d):
                    drawBox(width: w, height: h, depth: d)
                case .sphere(let r):
                    material(.metal(roughness: 0.25))
                    drawSphere(radius: r)
                    material(.dielectric(roughness: 0.55))
                default:
                    break
                }
            }
        }
    }
}
