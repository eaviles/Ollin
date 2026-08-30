// figure: frame=340
//
// Guide listing (Chapter 24): collision groups. Two identical tubes, each with
// a grating across the middle, and the same handful of beads poured into each.
// The left beads pile up on the grating; the right ones are in a group the
// grating is told to ignore, so they fall past it and pile on the floor. One
// sentence is the whole difference. No random anywhere, so it replays
// identically.
import Ollin
import OllinPhysics

final class Sorted: Sketch {
    let world = World3D()

    let beadRadius = 0.17
    let gratingY = 0.5
    let floorY = -1.3
    let tube = 1.5
    var beads: [(body: Body3D, color: Color)] = []
    var walls: [Body3D] = []
    var gratings: [Body3D] = []

    let held = Color(hex: 0xE8A33D)
    let passing = Color(hex: 0x4FC1AE)

    override func setup() {
        world.ground = floorY
        world.restitution = 0.05

        // One rule, and it is the only difference between the two halves.
        world.ignoreCollisions(between: "passing", and: "grating")

        for side in [-1.0, 1.0] {
            buildTube(at: side * 1.35)
        }

        // The same pour into each tube: the left beads are in no group at all,
        // the right ones are in the group the grating ignores.
        for layer in 0 ..< 2 {
            for i in 0 ..< 3 {
                for j in 0 ..< 3 {
                    // Staggered rather than a perfect lattice, so the beads
                    // settle into a pile instead of stacking into a tower.
                    let offset = Vector3(Double(i) * 0.42 - 0.42,
                                         2.0 + Double(layer) * 0.5
                                             + Double((i + j) % 2) * 0.13,
                                         Double(j) * 0.42 - 0.42)
                    add(at: Vector3(-1.35, 0, 0) + offset, group: .default, color: held)
                    add(at: Vector3(1.35, 0, 0) + offset, group: "passing", color: passing)
                }
            }
        }
    }

    /// An open tube with a grating across the middle: four walls running from
    /// the floor up past the grating, so a bead either stops on it or does not.
    func buildTube(at x: Double) {
        gratings.append(world.addBody(.box(width: tube, height: 0.14, depth: tube),
                                      at: Vector3(x, gratingY, 0), kind: .static,
                                      friction: 0.7, group: "grating"))
        let height = 2.9
        let mid = floorY + height / 2
        for edge in [-1.0, 1.0] {
            walls.append(world.addBody(.box(width: 0.1, height: height, depth: tube),
                                       at: Vector3(x + edge * tube / 2, mid, 0),
                                       kind: .static, friction: 0.3))
            walls.append(world.addBody(.box(width: tube, height: height, depth: 0.1),
                                       at: Vector3(x, mid, edge * tube / 2),
                                       kind: .static, friction: 0.3))
        }
    }

    func add(at position: Vector3, group: CollisionGroup, color: Color) {
        let bead = world.addBody(.sphere(radius: beadRadius), at: position,
                                 density: 0.9, friction: 0.45, group: group)
        beads.append((bead, color))
    }

    override func draw() {
        background(Color(hex: 0x0D111A))
        environment(.night.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        camera(.perspective(eye: Vector3(0, 2.6, 7.2),
                            target: Vector3(0, 0.15, 0), fieldOfView: .pi / 4.4))

        world.advance(by: 1.0 / 60)

        fill(Color(hex: 0x11151F))
        material(.dielectric(roughness: 0.94))
        withState {
            translate(0, floorY - 0.07, 0)
            drawBox(width: 22, height: 0.14, depth: 22)
        }

        // The gratings solid, the tube walls see-through, so both piles read.
        material(.dielectric(roughness: 0.6))
        fill(Color(hex: 0x46587A))
        for grating in gratings {
            withBody(grating) { drawBox(width: tube, height: 0.14, depth: tube) }
        }

        material(.dielectric(roughness: 0.34))
        for (bead, color) in beads {
            fill(color)
            withBody(bead) {
                drawSphere(radius: beadRadius, segments: 14, rings: 8)
            }
        }

        material(.dielectric(roughness: 0.5))
        fill(Color(hex: 0x8FA4C6).withAlpha(0.16))
        for wall in walls {
            guard case .box(let w, let h, let d) = wall.collider else { continue }
            withBody(wall) { drawBox(width: w, height: h, depth: d) }
        }
    }
}
