import Ollin
import OllinPhysics

/// A wrecking rig: a chain of capsule links hangs from a beam on ball joints,
/// ending in a heavy sphere, with a crate tower minding its own business
/// nearby. **Drag** the ball back and let it swing; the chain whips, the
/// tower scatters. **Space** restacks the crates.
///
/// The joint showcase for `World3D`: every link is one `connect` with a
/// `.ball` at the meeting point, which is all a hanging chain is. The same
/// call with `.revolute`, `.distance`, `.weld`, or `.prismatic` builds doors,
/// rods, rigid assemblies, and sliders.
@main
final class Chain3D: Sketch {
    let world = World3D()
    var ball: Body3D?

    let linkCount = 7
    let linkHeight = 0.42
    let linkRadius = 0.09
    let anchorHeight = 5.4

    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B),
        Color(hex: 0x72BFB2), Color(hex: 0x8D92E0),
    ]

    override func setup() {
        world.ground = 0
        world.bounce = 0.1

        // The beam, the chain, and the ball, joined top to bottom. Each link
        // meets the next where cap touches cap, and a ball joint there lets
        // the chain fold every way a real one does.
        let beam = world.addBody(.box(width: 1.4, height: 0.22, depth: 0.22),
                                 at: Vector3(0, anchorHeight, 0), kind: .static)
        var previous = beam
        let step = linkHeight + 2 * linkRadius
        for index in 0 ..< linkCount {
            let top = anchorHeight - 0.11 - Double(index) * step
            let link = world.addBody(.capsule(height: linkHeight, radius: linkRadius),
                                     at: Vector3(0, top - step / 2, 0),
                                     density: 2, friction: 0.4)
            world.connect(previous, link, .ball(at: Vector3(0, top, 0)))
            previous = link
        }
        let chainEnd = anchorHeight - 0.11 - Double(linkCount) * step
        let sphere = world.addBody(.sphere(radius: 0.5),
                                   at: Vector3(0, chainEnd - 0.5, 0),
                                   density: 8, friction: 0.4)
        world.connect(previous, sphere, .ball(at: Vector3(0, chainEnd, 0)))
        ball = sphere

        buildTower()
    }

    /// The crates waiting to be scattered, off to the side of the ball's rest.
    func buildTower() {
        for body in world.bodies where body.userData is Color {
            world.remove(body)
        }
        let size = 0.62
        for level in 0 ..< 5 {
            for row in 0 ..< 2 {
                let crate = world.addBody(
                    .box(width: size, height: size, depth: size),
                    at: Vector3(2.4, size / 2 + Double(level) * (size + 0.03),
                                Double(row) * (size + 0.04) - (size + 0.04) / 2),
                    friction: 0.55)
                crate.userData = palette[level % palette.count]
            }
        }
    }

    override func keyPressed() {
        if key == " " { buildTower() }
    }

    override func draw() {
        background(Color(hex: 0x0C0F15))
        // The chain and ball are metal, and metal is only as bright as what it
        // reflects; the environment lights them without painting the backdrop.
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(-5.6, 4.2, 8.6), target: Vector3(0.8, 2.0, 0))

        dragBodies(in: world)
        world.step(dt: deltaTime)

        fill(Color(hex: 0x1A202A))
        material(.dielectric(roughness: 0.85))
        drawGround(size: 24)

        for body in world.bodies {
            withBody(body) {
                switch body.collider {
                case .box(let w, let h, let d):
                    if let color = body.userData as? Color {
                        fill(color)
                        material(.dielectric(roughness: 0.55))
                    } else {
                        fill(Color(hex: 0x3A4150))   // the static beam
                        material(.metal(roughness: 0.5))
                    }
                    drawBox(width: w, height: h, depth: d)
                case .capsule(let h, let r):
                    fill(Color(hex: 0xB8C0CC))
                    material(.metal(roughness: 0.35))
                    drawCapsule(radius: r, height: h)
                case .sphere(let r):
                    fill(Color(hex: 0xD4DCE6))
                    material(.metal(roughness: 0.2))
                    drawSphere(radius: r)
                default:
                    break
                }
            }
        }
    }
}
