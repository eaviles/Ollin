// figure: frame=260
//
// Guide payoff (Chapter 24): the contraption. Nothing here is animated. A
// motor turns one hinge, a gear link ties it to a second, and a paddle on the
// second wheel sweeps a shelf of crates off the end. Everything else is
// contact.
import Foundation
import Ollin
import OllinPhysics

final class Contraption: Sketch {
    @Param("Speed", 0.5...6.0) var speed = 2.6
    @Param("Teeth", 10...40) var bigTeeth = 34

    let world = World3D()
    var crank: Joint3D?
    var crates: [Body3D] = []

    let timber = Color(hex: 0x8A6A4A)
    let brass = Color(hex: 0xD9A441)
    let steel = Color(hex: 0xB9C2CE)
    let clay = Color(hex: 0xD2603F)

    // The hubs sit exactly the two radii apart, so the wheels look like they
    // mesh. The gear link does not care, but the reader does.
    let smallHub = Vector3(-1.5, 2.4, 0)
    let bigHub = Vector3(0.4, 2.4, 0)

    override func setup() {
        world.ground = 0
        world.bounce = 0.15

        // Gear teeth have to mesh, and two cylinders that touch would jam
        // instead. Nothing in the frame needs to collide with the rest of it.
        world.ignoreCollisions(between: "frame", and: "frame")

        let wall = world.addBody(.box(width: 6.0, height: 4.4, depth: 0.25),
                                 at: Vector3(-0.4, 2.2, -0.75), kind: .static,
                                 group: "frame")
        wall.userData = timber

        // A cylinder stands upright, so each wheel takes a quarter turn about
        // x to lay its axle along z, facing the camera.
        let small = world.addBody(.compound([
            .part(.cylinder(height: 0.3, radius: 0.7), rotated: .pi / 2, axis: .unitX, density: 3),
        ]), at: smallHub, group: "frame")
        small.userData = brass

        let big = world.addBody(.compound([
            .part(.cylinder(height: 0.3, radius: 1.2), rotated: .pi / 2, axis: .unitX, density: 3),
            .part(.box(width: 3.8, height: 0.16, depth: 0.5), density: 3),
        ]), at: bigHub, group: "frame")
        big.userData = steel

        let smallHinge = world.connect(wall, small, .revolute(at: smallHub, axis: .unitZ))
        let bigHinge = world.connect(wall, big, .revolute(at: bigHub, axis: .unitZ))
        world.connect(smallHinge, bigHinge, .gear(teeth: 20, and: bigTeeth))
        crank = smallHinge

        let shelf = world.addBody(.box(width: 3.2, height: 0.3, depth: 1.2),
                                  at: Vector3(2.9, 1.05, 0), kind: .static, group: "frame")
        shelf.userData = timber

        for i in 0 ..< 6 {
            let crate = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                                      at: Vector3(1.9 + Double(i) * 0.5, 1.45, 0))
            crate.userData = clay
            crates.append(crate)
        }
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(0.9, 4.2, 9.4), target: Vector3(0.9, 2.3, 0),
                    fieldOfView: 0.85)

        crank?.drive(at: speed, strength: 900)
        world.step(dt: deltaTime)

        // A crate swept off the shelf goes back on it, so the machine never
        // runs out of work to do.
        for (i, crate) in crates.enumerated() where crate.position.y < 0.6 {
            crate.position = Vector3(1.9 + Double(i) * 0.5, 1.7, 0)
            crate.velocity = .zero
            crate.angularVelocity = .zero
        }

        // A floor for the shadows to land on. It is drawn rather than added
        // to the world, because `world.ground` is already the plane bodies
        // rest on and a second one would only fight it.
        noStroke()
        fill(Color(hex: 0x2A2F3A))
        material(.dielectric(roughness: 0.9))
        withState {
            translate(0, -0.1, 0)
            drawBox(width: 26, height: 0.2, depth: 20)
        }

        for body in world.bodies {
            withBody(body) { draw(body.collider, tint: body.userData as? Color) }
        }
    }

    // Bodies come back as colliders, so one recursive helper draws every kind
    // and a compound just draws its parts in their own local frames.
    func draw(_ collider: Collider3D, tint: Color?) {
        switch collider {
        case .box(let w, let h, let d):
            fill(tint ?? .white)
            material(.dielectric(roughness: 0.65))
            drawBox(width: w, height: h, depth: d)
        case .cylinder(let h, let r):
            fill(tint ?? steel)
            material(.metal(roughness: 0.38))
            drawCylinder(radius: r, height: h)
        case .compound(let parts):
            for part in parts {
                withState {
                    translate(part.position)
                    if part.angle != 0 { rotate(part.angle, axis: part.axis) }
                    draw(part.collider, tint: tint)
                }
            }
        default:
            break
        }
    }
}
