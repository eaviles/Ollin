// figure: frame=420
//
// Guide listing (Chapter 23): taking a direction away. Two identical pin
// boards over two identical bins, the same beads poured down each with the
// same careless sideways nudge. The left beads are held to the board's plane,
// so the nudge has nowhere to go and they land in one flat sheet down the
// middle of their bin; the right ones are free, so the same nudge spreads them
// through the bin's whole depth. One word is the difference. No random
// anywhere, so it replays identically.
import Ollin
import OllinPhysics

final class Flattened: Sketch {
    let world = World3D()

    let beadRadius = 0.17
    let floorY = -2.1
    let binWidth = 3.1
    let binDepth = 2.6
    var beads: [(body: Body3D, color: Color)] = []
    var pins: [Vector3] = []
    var slabs: [(position: Vector3, size: Vector3)] = []

    let flat = Color(hex: 0x4FC1AE)
    let free = Color(hex: 0xE8A33D)
    let boardX = 2.4

    override func setup() {
        world.ground = floorY
        world.bounce = 0.1

        for side in [-1.0, 1.0] { buildBoard(at: side * boardX) }

    }

    /// One bead into each bin, dropped just above the pins so it arrives with
    /// no more energy than the pins give it, and nudged toward or away from the
    /// camera on the way down. Released one at a time from `draw`, which is
    /// what keeps the two pours identical without them landing on each other.
    func release(_ i: Int) {
        let across = Double(i % 3) * 0.82 - 0.82 + Double(i / 3) * 0.26
        let offset = Vector3(across, 2.35, 0)
        let nudge = Vector3(0, 0, Double(i % 3 - 1) * 1.15)
        add(at: Vector3(-boardX, 0, 0) + offset, nudge: nudge,
            freedom: .plane(), color: flat)
        add(at: Vector3(boardX, 0, 0) + offset, nudge: nudge,
            freedom: .all, color: free)
    }

    @discardableResult
    func slab(_ size: Vector3, at position: Vector3) -> Body3D {
        slabs.append((position, size))
        return world.addBody(.box(width: size.x, height: size.y, depth: size.z),
                             at: position, kind: .static, friction: 0.4)
    }

    /// A back plate with three staggered rows of pins, standing in a bin deep
    /// enough that a bead is free to land anywhere across it.
    func buildBoard(at x: Double) {
        slab(Vector3(binWidth, 4.4, 0.3), at: Vector3(x, 0.7, -binDepth / 2))
        // The bin has no front at all, and it does not need one for the beads
        // on the left: travel toward the camera is the very thing they have
        // been refused. It is the only way out for the ones on the right.
        // The sides run the whole height of the board, so nothing can leave a
        // bin sideways and the front lip is the only way out of it.
        for edge in [-1.0, 1.0] {
            slab(Vector3(0.16, 4.9, binDepth),
                 at: Vector3(x + edge * binWidth / 2, floorY + 2.45, 0))
        }
        for row in 0 ..< 3 {
            let y = 1.7 - Double(row) * 1.05
            let stagger = row.isMultiple(of: 2) ? 0.0 : 0.48
            for column in -1 ... 1 {
                let pin = Vector3(x + Double(column) * 0.96 + stagger, y, -0.35)
                pins.append(pin)
                world.addBody(.cylinder(height: 0.9, radius: 0.13), at: pin,
                              kind: .static, rotated: .pi / 2, axis: .unitX,
                              friction: 0.1, restitution: 0.2)
            }
        }
    }

    func add(at position: Vector3, nudge: Vector3, freedom: Freedom3D,
             color: Color) {
        let bead = world.addBody(.sphere(radius: beadRadius),
                                 at: position + Vector3(0, 0, -0.35),
                                 density: 0.9, friction: 0.5, freedom: freedom)
        bead.velocity = nudge
        beads.append((bead, color))
    }

    override func draw() {
        background(Color(hex: 0x0D111A))
        environment(.night.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        camera(.perspective(eye: Vector3(1.6, 4.6, 13.6),
                            target: Vector3(0, -0.7, 0), fieldOfView: .pi / 4.6))

        let poured = beads.count / 2
        if poured < 9 && frameCount % 16 == 1 { release(poured) }
        world.step(dt: 1.0 / 60)

        fill(Color(hex: 0x11151F))
        material(.dielectric(roughness: 0.94))
        withState {
            translate(0, floorY - 0.07, 0)
            drawBox(width: 26, height: 0.14, depth: 26)
        }

        material(.dielectric(roughness: 0.75))
        fill(Color(hex: 0x1B2231))
        for slab in slabs {
            withState {
                translate(slab.position.x, slab.position.y, slab.position.z)
                drawBox(width: slab.size.x, height: slab.size.y, depth: slab.size.z)
            }
        }

        material(.metal(roughness: 0.35))
        fill(Color(hex: 0x8B93A8))
        for pin in pins {
            withState {
                translate(pin.x, pin.y, pin.z)
                rotateX(.pi / 2)
                drawCylinder(radius: 0.13, height: 0.9, segments: 16)
            }
        }

        material(.dielectric(roughness: 0.34))
        for (bead, color) in beads {
            fill(color)
            withBody(bead) {
                drawSphere(radius: beadRadius, segments: 14, rings: 8)
            }
        }
    }
}
