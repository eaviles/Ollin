import Ollin
import OllinPhysics

/// A yard under watch, built from three questions the solver can already
/// answer. A lamp circles overhead and lights only the crates it can actually
/// see, so a pillar between them leaves one dark. A drone patrols at a fixed
/// clearance above whatever passes below, feeling its way with a ball rather
/// than a point, so it climbs over a crate the way it climbs over a pillar.
/// And every few seconds it pulses, shoving everything inside a sphere that
/// exists for exactly one frame. **Drag** a crate to move it into cover or out
/// of it; **space** fires the pulse by hand.
///
/// The query showcase for `World3D`. Three calls, all made between steps:
/// `raycast(from:to:)` for the line of sight, `sweep(_:from:to:)` for the
/// clearance under the drone, and `bodiesOverlapping(_:at:)` for the pulse.
/// None of them needs a body built to ask with.
@main
final class Sightlines: Sketch {
    let world = World3D()
    var crates: [Body3D] = []
    var pillars: [Body3D] = []
    var seen: [Bool] = []

    /// Where the drone is now, and where the sweep says the ground under it is.
    var drone = Vector3(0, 3, 0)
    var groundUnderDrone = Vector3(0, 0, 0)

    var pulses: [Pulse] = []
    var nextPulse = 3.0

    @Param(0.8 ... 4, icon: "arrow.up.and.down") var clearance = 1.7
    @Param(1.5 ... 6, icon: "circle.dashed") var pulseRadius = 3.2

    let lampHeight = 5.2, lampOrbit = 5.6, crateSize = 0.7
    let lit = Color(hex: 0xF2B347), shadowed = Color(hex: 0x2A3550)

    /// A shove that has already happened, kept only to draw its edge spreading.
    struct Pulse {
        var at: Vector3
        var radius: Double
        var age = 0.0
    }

    override func setup() {
        world.ground = 0
        world.bounce = 0.15

        // Five pillars in a ring: the things that get in the way.
        for index in 0 ..< 5 {
            let angle = Double(index) / 5 * .tau + 0.3
            pillars.append(world.addBody(.box(width: 0.8, height: 4.4, depth: 0.8),
                                         at: Vector3(cos(angle), 0, sin(angle)) * 3.1
                                             + Vector3(0, 2.2, 0),
                                         kind: .static, friction: 0.6))
        }

        // Crates scattered around them: the things being looked for.
        for _ in 0 ..< 14 {
            let angle = random(0, .tau)
            let reach = random(1.2, 5.6)
            let crate = world.addBody(.box(width: crateSize, height: crateSize,
                                           depth: crateSize),
                                      at: Vector3(cos(angle) * reach,
                                                  crateSize / 2 + random(0, 1.5),
                                                  sin(angle) * reach),
                                      rotated: random(0, .tau), density: 0.6,
                                      friction: 0.7)
            crates.append(crate)
            seen.append(false)
        }
    }

    /// The lamp's own position, circling the yard.
    var lamp: Vector3 {
        let angle = time * 0.42
        return Vector3(cos(angle) * lampOrbit, lampHeight, sin(angle) * lampOrbit)
    }

    override func keyPressed() {
        if key == " " { firePulse() }
    }

    override func draw() {
        background(Color(hex: 0x080B12))
        environment(.night.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        cameraShowcase(.autoOrbit(period: 46), from: Camera3D
            .perspective(eye: Vector3(2.4, 6.2, 11.5), target: Vector3(0, 1.6, 0)))

        dragBodies(in: world)
        world.step(dt: deltaTime)

        lookAround()
        flyTheDrone()
        agePulses()

        drawYard()
        drawCrates()
        drawLamp()
        drawDrone()
        drawPulses()
        drawCaption("space: pulse      drag a crate into cover")
    }

    // MARK: The three questions

    /// Line of sight, one ray per crate. The lamp reaches a crate only when the
    /// crate itself is the first thing the ray runs into; anything else in the
    /// way (a pillar, another crate) means this one is in shadow.
    func lookAround() {
        let eye = lamp
        for (index, crate) in crates.enumerated() {
            seen[index] = world.raycast(from: eye, to: crate.position)?.body === crate
        }
    }

    /// Clearance, one sweep straight down. A ray would find the floor between
    /// two crates and drop the drone onto them; a ball the drone's own width
    /// finds whatever it would actually brush past, which is why it rides over
    /// the pillars instead of into them.
    func flyTheDrone() {
        let patrol = Vector3(sin(time * 0.31) * 4.6, 0, cos(time * 0.23) * 4.6)
        let above = patrol + Vector3(0, 9, 0)
        let below = world.sweep(.sphere(radius: 0.55), from: above,
                                to: patrol - Vector3(0, 1, 0))
        groundUnderDrone = below?.point ?? patrol
        let target = (below.map { above.y - $0.distance } ?? 0) + clearance
        // Eased rather than snapped, so passing over a crate reads as a climb.
        drone = Vector3(patrol.x, drone.y + (target - drone.y) * min(1, deltaTime * 3),
                        patrol.z)
    }

    /// The pulse: everything inside a sphere at the drone, shoved away from it.
    /// The sphere is not a body and never was, which is the point.
    func firePulse() {
        for caught in world.bodiesOverlapping(.sphere(radius: pulseRadius), at: drone) {
            // An impulse only reaches a solid body: a soft one has no single
            // mass to push, which is what the cast says.
            guard let body = caught as? Body3D, body.kind == .dynamic else { continue }
            let away = body.position - drone
            let falloff = 1 - min(1, away.length / pulseRadius)
            body.applyImpulse((away.normalized + Vector3(0, 0.6, 0))
                * (2.4 + 5 * falloff))
        }
        pulses.append(Pulse(at: drone, radius: pulseRadius))
    }

    func agePulses() {
        nextPulse -= deltaTime
        if nextPulse <= 0 {
            nextPulse = 6
            firePulse()
        }
        for index in pulses.indices { pulses[index].age += deltaTime }
        pulses.removeAll { $0.age > 0.7 }
    }

    // MARK: Drawing it

    func drawYard() {
        fill(Color(hex: 0x121824))
        material(.dielectric(roughness: 0.92))
        drawGround(size: 30)
        fill(Color(hex: 0x1B2434))
        material(.dielectric(roughness: 0.7))
        for pillar in pillars {
            withBody(pillar) { drawBox(width: 0.8, height: 4.4, depth: 0.8) }
        }
    }

    /// Crates in the lamp's color or the shadow's, with a thin beam drawn to
    /// each one it reaches.
    func drawCrates() {
        for (index, crate) in crates.enumerated() {
            fill(seen[index] ? lit : shadowed)
            material(seen[index] ? .dielectric(roughness: 0.35)
                                 : .dielectric(roughness: 0.8))
            withBody(crate) { drawBox(width: crateSize, height: crateSize,
                                      depth: crateSize) }
        }

        fill(lit.withAlpha(0.22))
        material(.dielectric(roughness: 0.4))
        let eye = lamp
        for (index, crate) in crates.enumerated() where seen[index] {
            drawTube([eye, crate.position], radius: 0.012, sides: 6)
        }
    }

    func drawLamp() {
        fill(Color(hex: 0xFFE7B0))
        material(.dielectric(roughness: 0.2))
        withState {
            translate(lamp)
            drawSphere(radius: 0.22)
        }
    }

    /// The drone, the line it is feeling down, and a disc where the sweep
    /// stopped: the answer drawn where it was found.
    func drawDrone() {
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
    }

    /// Each pulse as the equator of the sphere it asked with, fading rather
    /// than spreading: the sphere had one radius, and everything inside it was
    /// caught at once.
    func drawPulses() {
        material(.dielectric(roughness: 0.4))
        for pulse in pulses {
            let t = pulse.age / 0.7
            fill(Color(hex: 0x74D6C4).withAlpha(1 - t))
            withState {
                translate(pulse.at)
                drawTorus(radius: pulse.radius * (1 + 0.05 * t), tube: 0.035,
                          segments: 64, sides: 6)
            }
        }
    }
}
