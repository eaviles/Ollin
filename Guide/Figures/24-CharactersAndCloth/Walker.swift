// figure: frame=140
//
// Guide listing (Chapter 24): the walking character. A figure steered from
// draw() walks a fixed path east, shoulders a light crate out of the way, and
// climbs a flight of steps its stepHeight allows, caught mid-climb. The walk
// is scripted rather than typed, and there is no random anywhere, so the whole
// sequence replays identically.
import Ollin
import OllinPhysics

final class Walker: Sketch {
    let world = World3D()
    var walker: Character3D!
    var crates: [Body3D] = []
    var stride = 0.0

    let palette: [Color] = [
        Color(hex: 0xE4572E), Color(hex: 0xF2A93B), Color(hex: 0x76B39D),
    ]

    override func setup() {
        world.ground = 0

        // Four steps rising east, each inside the character's 0.4 reach.
        for index in 0 ..< 4 {
            let top = 0.3 * Double(index + 1)
            world.addBody(.box(width: 0.9, height: top, depth: 3.2),
                          at: Vector3(2.2 + Double(index) * 0.9, top / 2, 0),
                          kind: .static, friction: 0.6)
        }
        // The deck the stair arrives on.
        world.addBody(.box(width: 2.4, height: 1.2, depth: 3.2),
                      at: Vector3(6.6, 0.6, 0), kind: .static, friction: 0.6)

        // Two crates light enough for the walk to shoulder aside.
        for (index, offset) in [Vector3(0.9, 0.26, 0.28),
                                Vector3(1.5, 0.26, -0.3)].enumerated() {
            let crate = world.addBody(.box(width: 0.5, height: 0.5, depth: 0.5),
                                      at: offset, density: 0.02, friction: 0.4)
            crate.userData = palette[index]
            crates.append(crate)
        }

        walker = world.addCharacter(radius: 0.28, height: 1.7,
                                    at: Vector3(-1.6, 0.1, 0))
    }

    override func draw() {
        background(Color(hex: 0x0C1119))
        environment(.sky(turbidity: 2.6, sunElevation: 0.8))
        lightingPreset(.standard)
        castShadows()
        perspective(eye: Vector3(-2.2, 3.9, 7.6), target: Vector3(2.4, 0.85, 0),
                    fieldOfView: .pi / 4)

        // The scripted walk: east, at a steady pace, the whole time.
        walker.move(x: 2.2, z: 0)
        world.step(dt: 1.0 / 60)

        let travel = Vector3(walker.actualVelocity.x, 0, walker.actualVelocity.z)
        if travel.length > 0.2 { walker.facing = atan2(travel.x, travel.z) }
        stride += travel.length / 60 * 3.4

        // The floor: `world.ground` is a slab the world keeps out of `bodies`,
        // so the sketch draws its own.
        material(.dielectric(roughness: 0.95))
        fill(Color(hex: 0x6E7A6A))
        withState {
            translate(0, -0.06, 0)
            drawBox(width: 30, height: 0.12, depth: 30)
        }

        material(.dielectric(roughness: 0.8))
        fill(Color(hex: 0xB9AE9C))
        for body in world.bodies where body.kind == .static {
            guard case .box(let w, let h, let d) = body.collider else { continue }
            withBody(body) { drawBox(width: w, height: h, depth: d) }
        }

        material(.dielectric(roughness: 0.5))
        for crate in crates {
            fill(crate.userData as? Color ?? .white)
            withBody(crate) { drawBox(width: 0.5, height: 0.5, depth: 0.5) }
        }

        drawWalker()
    }

    /// Modelled facing its own +z, standing on the origin, so `withCharacter`
    /// turns it by `facing` and stands it on the ground at the feet.
    func drawWalker() {
        let swing = sin(stride) * 0.42
        material(.dielectric(roughness: 0.45))
        withCharacter(walker) {
            fill(Color(hex: 0x1D2430))
            for (side, phase) in [(-1.0, swing), (1.0, -swing)] {
                withState {
                    translate(0.12 * side, 0.72, 0)
                    rotate(phase, axis: .unitX)
                    translate(0, -0.36, 0)
                    drawCapsule(radius: 0.1, height: 0.5)
                }
            }
            fill(Color(hex: 0xE8632F))
            withState {
                translate(0, 1.14, 0)
                drawCapsule(radius: 0.21, height: 0.42)
            }
            fill(Color(hex: 0x1D2430))
            for (side, phase) in [(-1.0, -swing), (1.0, swing)] {
                withState {
                    translate(0.3 * side, 1.3, 0)
                    rotate(phase * 0.7, axis: .unitX)
                    translate(0, -0.24, 0)
                    drawCapsule(radius: 0.07, height: 0.34)
                }
            }
            fill(Color(hex: 0xF2C9A0))
            withState {
                translate(0, 1.56, 0)
                drawSphere(radius: 0.18)
            }
            fill(Color(hex: 0xD94F70))
            withState {
                translate(0, 1.62, 0.12)
                drawBox(width: 0.34, height: 0.05, depth: 0.2)
            }
        }
    }
}
