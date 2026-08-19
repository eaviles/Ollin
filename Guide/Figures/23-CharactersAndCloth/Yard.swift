// figure: frame=320
//
// Guide payoff (Chapter 23): the yard. A truck on four sprung wheels, a figure
// on its feet, and a banner strung between two posts, all in the same world as
// the crates they knock about. None of the three is a rigid body, and each is
// held up by a different solver.
import Foundation
import Ollin
import OllinPhysics

final class Yard: Sketch {
    @Param("Throttle", 0.0...1.0) var throttle = 0.55
    @Param("Steering", -1.0...1.0) var steering = -0.35
    @Param("Wind", 0.0...14.0) var wind = 7.0

    let world = World3D()
    let bannerMesh = Mesh.plane(width: 5, depth: 2.4, segments: 16)

    var truck: Vehicle3D?
    var pacer: Character3D?
    var banner: SoftBody3D?

    let clay = Color(hex: 0xD2603F)
    let timber = Color(hex: 0x8A6A4A)
    let teal = Color(hex: 0x3E8E86)

    override func setup() {
        world.ground = 0

        // A real floor body, not just `world.ground`. A character walks on
        // geometry rather than on the implicit plane, so without this one it
        // falls forever and never appears.
        let floor = world.addBody(.box(width: 34, height: 0.4, depth: 34),
                                  at: Vector3(0, -0.2, 0), kind: .static)
        floor.userData = Color(hex: 0x2C3340)

        // Four wheels: the front pair steers, the back pair is driven. The
        // spring is shorter than the default so the body sits down on its
        // wheels rather than up on stilts.
        let wheels = [Vector3(0.85, -0.28, 1.2), Vector3(-0.85, -0.28, 1.2),
                      Vector3(0.85, -0.28, -1.2), Vector3(-0.85, -0.28, -1.2)]
            .enumerated().map { index, mount -> Wheel3D in
                let wheel = Wheel3D.wheel(at: mount, radius: 0.38, width: 0.28,
                                          steers: index < 2, driven: index >= 2)
                wheel.suspensionLength = 0.26
                wheel.suspensionTravel = 0.2
                return wheel
            }
        truck = world.addVehicle(.box(width: 1.7, height: 0.7, depth: 3.4),
                                 at: Vector3(2.6, 1.3, 3.0), wheels: wheels,
                                 mass: 1400, engineTorque: 520, topSpeed: 16,
                                 rotated: .pi, axis: .unitY)

        pacer = world.addCharacter(radius: 0.3, height: 1.75, at: Vector3(-4.4, 1.0, 0.4))

        // A soft body is its mesh. Pinning the two top corners is what turns a
        // sheet into a banner rather than a dropped cloth.
        banner = world.addSoftBody(from: bannerMesh, at: Vector3(-1.2, 3.1, -4.2),
                                   mass: 1.2, stiffness: 0.7, damping: 0.2,
                                   pinned: { $0.z < -1.0 && abs($0.x) > 2.2 })

        for post in [-3.7, 1.3] {
            let p = world.addBody(.box(width: 0.22, height: 3.4, depth: 0.22),
                                  at: Vector3(post, 1.7, -4.2), kind: .static)
            p.userData = timber
        }

        for i in 0 ..< 9 {
            let crate = world.addBody(.box(width: 0.7, height: 0.7, depth: 0.7),
                                      at: Vector3(-0.6 + Double(i % 3) * 0.75,
                                                  0.4 + Double(i / 3) * 0.72, -1.0))
            crate.userData = clay
        }

        // Let the yard settle before anybody looks at it.
        for _ in 0 ..< 180 { world.step(dt: 1.0 / 60) }
    }

    override func draw() {
        background(Color(hex: 0x0C1018))
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(7.4, 5.2, 10.4), target: Vector3(-1.1, 1.3, -0.8),
                    fieldOfView: 0.86)

        truck?.throttle = throttle
        truck?.steering = steering

        // `move` takes a velocity and the character keeps it, so a figure told
        // to walk one way walks that way until something stops it. Steering it
        // back toward a home point is what keeps this one in the yard.
        if let pacer {
            let home = Vector3(-4.4, pacer.position.y, 0.4)
            let back = home - pacer.position
            pacer.move(Vector3(back.x * 0.9, 0, back.z * 0.9 + sin(time * 0.8) * 0.9))
        }
        banner?.applyForce(Vector3(sin(time * 1.3) * wind, 0, wind * 0.4))
        world.step(dt: deltaTime)

        noStroke()
        for body in world.bodies where body !== truck?.body {
            fill((body.userData as? Color) ?? .white)
            material(.dielectric(roughness: 0.7))
            withBody(body) {
                if case .box(let w, let h, let d) = body.collider {
                    drawBox(width: w, height: h, depth: d)
                }
            }
        }

        if let truck {
            fill(Color(hex: 0xC7CDD6))
            material(.metal(roughness: 0.35))
            withBody(truck.body) { drawBox(width: 1.7, height: 0.7, depth: 3.4) }
            fill(Color(hex: 0x22262E))
            material(.dielectric(roughness: 0.8))
            for wheel in truck.wheels {
                withWheel(wheel) { drawCylinder(radius: 0.38, height: 0.28) }
            }
        }

        // A character is a swept capsule with no mesh of its own, so something
        // has to stand in for the body it is carrying.
        if let pacer {
            fill(Color(hex: 0xE0C089))
            material(.dielectric(roughness: 0.6))
            // `withCharacter` puts the origin at the character's feet, so
            // the capsule has to be lifted by half its own height.
            withCharacter(pacer) {
                translate(0, 0.875, 0)
                drawCapsule(radius: 0.3, height: 1.15)
            }
        }

        if let banner {
            fill(teal)
            material(.dielectric(roughness: 0.55))
            drawSoftBody(banner)
        }
    }
}
