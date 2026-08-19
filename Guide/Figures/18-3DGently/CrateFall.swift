// figure: frame=92
//
// Guide listing (Chapter 18): the 3D physics world. A crate pyramid takes a
// heavy steel ball, caught mid-topple: crates shoved off the top layers,
// tumbling with real contact response, the ball buried in the wreck. No
// random anywhere, so the collapse replays identically.
import Ollin
import OllinPhysics

final class CrateFall: Sketch {
    let world = World3D()

    let palette: [Color] = [
        Color(hex: 0xE4572E), Color(hex: 0xF2A93B),
        Color(hex: 0x76B39D), Color(hex: 0x8D92E0),
    ]

    override func setup() {
        world.ground = 0
        let size = 0.72
        let gap = 0.05
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
        // The wrecking shot: a dense steel ball lobbed flat into the middle
        // layers, so the whole tower takes the hit rather than just the cap.
        let ball = world.addBody(.sphere(radius: 0.42), at: Vector3(-4.5, 1.3, 0.9),
                                 density: 10, friction: 0.4)
        ball.velocity = Vector3(12.5, 1.2, -2.0)
    }

    override func draw() {
        background(Color(hex: 0x10141B))
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(6.6, 4.0, 9.6), target: Vector3(0.9, 0.9, 0))

        world.step(dt: deltaTime)

        fill(Color(hex: 0x1A1F28))
        material(.dielectric(roughness: 0.85))
        withState {
            translate(0, -0.06, 0)
            drawBox(width: 26, height: 0.12, depth: 26)
        }

        for body in world.bodies {
            withBody(body) {
                switch body.collider {
                case .box(let w, let h, let d):
                    fill(body.userData as? Color ?? .white)
                    material(.dielectric(roughness: 0.55))
                    drawBox(width: w, height: h, depth: d)
                case .sphere(let r):
                    fill(Color(hex: 0xD4DCE6))
                    material(.metal(roughness: 0.22))
                    drawSphere(radius: r)
                default:
                    break
                }
            }
        }
    }
}
