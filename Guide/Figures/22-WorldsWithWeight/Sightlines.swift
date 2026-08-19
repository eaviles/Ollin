// figure: frame=150
//
// Guide listing (Chapter 22): the three world queries in one yard. A lamp
// raycasts to every crate and draws a beam to the ones it can actually see, so
// the crates behind a pillar stay dark; a drone sweeps a ball straight down to
// find its clearance, marked by the disc where the sweep stopped; and a pulse
// overlaps a sphere at the drone and shoves what was inside it, drawn as that
// sphere's equator. Hand-placed crates, no random anywhere, so it replays
// identically.
import Ollin
import OllinPhysics

final class Sightlines: Sketch {
    let world = World3D()
    var crates: [Body3D] = []
    var seen: [Bool] = []
    var drone = Vector3(0, 3, 0)
    var groundUnderDrone = Vector3.zero
    var pulse: (at: Vector3, radius: Double, age: Double)?

    let crateSize = 0.7, clearance = 1.7, pulseRadius = 3.2
    let lit = Color(hex: 0xF2B347), shadowed = Color(hex: 0x2A3550)

    /// Where the pillars stand: two of them between the lamp and the crates
    /// behind, which is what puts anything in shadow at all.
    let pillars: [Vector3] = [
        Vector3(-2.6, 0, 1.4), Vector3(0.4, 0, 2.9), Vector3(3.0, 0, 0.2),
        Vector3(-1.4, 0, -2.4),
    ]

    /// Crates placed by hand, resting on the floor from the first frame, so
    /// nothing has to settle before the figure is taken.
    let placed: [Vector3] = [
        Vector3(-4.6, 0, 0.2), Vector3(-2.5, 0, -0.6), Vector3(-0.8, 0, 0.9),
        Vector3(1.4, 0, 1.1), Vector3(2.2, 0, -1.6), Vector3(4.3, 0, 0.9),
        Vector3(-3.4, 0, 3.1), Vector3(0.2, 0, 4.4), Vector3(3.4, 0, 3.4),
        Vector3(-0.4, 0, -3.4), Vector3(1.9, 0, -4.1),
    ]

    override func setup() {
        world.ground = 0
        for base in pillars {
            world.addBody(.box(width: 0.8, height: 4.4, depth: 0.8),
                          at: base + Vector3(0, 2.2, 0), kind: .static)
        }
        for base in placed {
            crates.append(world.addBody(.box(width: crateSize, height: crateSize,
                                             depth: crateSize),
                                        at: base + Vector3(0, crateSize / 2, 0),
                                        density: 0.6, friction: 0.7))
            seen.append(false)
        }
    }

    /// The lamp, parked where its beams rake across the yard.
    let lamp = Vector3(-4.2, 5.2, 4.6)

    override func draw() {
        background(Color(hex: 0x080B12))
        environment(.night.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(1.0, 6.6, 12.4), target: Vector3(-0.7, 2.1, 0.2))

        world.step(dt: deltaTime)

        // A ray per crate: it is visible when the crate itself is what the ray
        // found first.
        for (index, crate) in crates.enumerated() {
            seen[index] = world.raycast(from: lamp, to: crate.position)?.body === crate
        }

        // A sweep straight down for the clearance under the drone.
        let patrol = Vector3(1.1, 0, -0.7)
        let above = patrol + Vector3(0, 9, 0)
        let below = world.sweep(.sphere(radius: 0.55), from: above,
                                to: patrol - Vector3(0, 1, 0))
        groundUnderDrone = below?.point ?? patrol
        drone = Vector3(patrol.x, (below.map { above.y - $0.distance } ?? 0) + clearance,
                        patrol.z)

        // One pulse, fired on a known frame so the ring is in the picture.
        if frameCount == 130 {
            for caught in world.bodiesOverlapping(.sphere(radius: pulseRadius), at: drone) {
                // Only a solid body takes an impulse.
                guard let body = caught as? Body3D else { continue }
                let away = body.position - drone
                let falloff = 1 - min(1, away.length / pulseRadius)
                body.applyImpulse((away.normalized + Vector3(0, 0.6, 0))
                    * (2.4 + 5 * falloff))
            }
            pulse = (drone, pulseRadius, 0)
        }
        if pulse != nil { pulse?.age += deltaTime }

        fill(Color(hex: 0x121824))
        material(.dielectric(roughness: 0.92))
        withState {
            translate(0, -0.06, 0)
            drawBox(width: 30, height: 0.12, depth: 30)
        }
        fill(Color(hex: 0x1B2434))
        material(.dielectric(roughness: 0.7))
        for body in world.bodies where body.kind == .static {
            withBody(body) { drawBox(width: 0.8, height: 4.4, depth: 0.8) }
        }

        for (index, crate) in crates.enumerated() {
            fill(seen[index] ? lit : shadowed)
            material(.dielectric(roughness: seen[index] ? 0.35 : 0.8))
            withBody(crate) {
                drawBox(width: crateSize, height: crateSize, depth: crateSize)
            }
        }
        fill(lit.withAlpha(0.22))
        material(.dielectric(roughness: 0.4))
        for (index, crate) in crates.enumerated() where seen[index] {
            drawTube([lamp, crate.position], radius: 0.012, sides: 6)
        }

        fill(Color(hex: 0xFFE7B0))
        material(.dielectric(roughness: 0.2))
        withState {
            translate(lamp)
            drawSphere(radius: 0.22)
        }

        fill(Color(hex: 0x74D6C4))
        material(.metal(roughness: 0.3))
        withState {
            translate(drone)
            drawCylinder(radius: 0.34, height: 0.16)
        }
        fill(Color(hex: 0x74D6C4).withAlpha(0.25))
        material(.dielectric(roughness: 0.5))
        drawTube([drone, groundUnderDrone], radius: 0.01, sides: 6)
        withState {
            translate(groundUnderDrone + Vector3(0, 0.02, 0))
            drawCylinder(radius: 0.3, height: 0.02)
        }

        if let pulse {
            let t = min(1, pulse.age / 0.7)
            fill(Color(hex: 0x74D6C4).withAlpha(1 - t))
            material(.dielectric(roughness: 0.4))
            withState {
                translate(pulse.at)
                drawTorus(radius: pulse.radius * (1 + 0.05 * t), tube: 0.035,
                          segments: 64, sides: 6)
            }
        }
    }
}
