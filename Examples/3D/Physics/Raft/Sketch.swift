import Ollin
import OllinPhysics

/// A raft made of cloth, riding a swell with cargo on it. **Drag** the deck to
/// sail her: under the sounding line, or through the harbor gate. **Space**
/// drops another crate.
///
/// The showcase for a soft body being part of the world rather than a thing
/// draped over it, in three ways. It **floats**: `world.water` pushes each of
/// its particles up on its own, so `density` decides how high she rides even
/// though a sheet encloses no volume to work a waterline out of. It **turns up
/// in `world.contacts`**: a crate landing on the deck reports where and how
/// hard, the gate is a sensor that sees her sail in, and `raft.touching` counts
/// what is aboard. And it is **something a query can find**: the sounding line
/// stops at the deck when she is under it, rather than passing through her.
@main
final class Raft: Sketch {
    let world = World3D()
    var raft: SoftBody3D?
    var gate: Body3D?
    var grip: SoftGrip?
    var crateGrip: Joint3D?

    /// How heavy the deck is for its size, against the water's own weight.
    /// Lower rides higher and drier.
    @Param(0.1 ... 0.9, icon: "square.stack.3d.up") var deckDensity = 0.25
    /// How high the swell runs, in world units.
    @Param(0 ... 0.4, icon: "water.waves") var swell = 0.1

    /// One box of cargo, kept so the same numbers build it and draw it.
    struct Crate {
        var body: Body3D
        var size: Double
        var color: Color
    }
    var crates: [Crate] = []

    /// A ring left where something hit the water or the deck, sized by how hard
    /// it landed.
    struct Splash {
        var at: Vector3
        var strength: Double
        var age = 0.0
    }
    var splashes: [Splash] = []

    let deep = -5.0
    let deckSize = 4.0
    let soundingPost = Vector3(-4.4, 0, -0.6)
    let gateX = 4.6
    let palette = [Color(hex: 0xD9A441), Color(hex: 0xC1553F), Color(hex: 0x8FA860)]

    override func setup() {
        world.ground = deep
        world.water = Water(level: 0, linearDrag: 0.4,
                            waves: Water.Waves(amplitude: swell, wavelength: 9,
                                               speed: 1.4))
        buildRaft()
        buildHarbour()
        for index in 0 ..< 2 { dropCrate(at: Double(index) * 0.9 - 0.45) }
    }

    /// The deck: an ordinary plane mesh, stiff enough to carry a crate and
    /// still loose enough to bend over a wave.
    func buildRaft() {
        raft = world.addSoftBody(from: .plane(width: deckSize, depth: deckSize,
                                              segments: 16),
                                 at: Vector3(0, 0.4, 0),
                                 mass: 300, stiffness: 0.998, bend: 1,
                                 damping: 0.1, friction: 0.95, iterations: 14,
                                 vertexRadius: 0.08)
        // A sheet holds no volume, so unlike a crate it cannot work out its own
        // weight for its size: this is the number that decides she floats.
        raft?.density = deckDensity
    }

    /// The two things watching the water: a sounding line that measures what is
    /// under it, and a gate that reports what is inside it.
    func buildHarbour() {
        world.addBody(.box(width: 0.24, height: 3.4, depth: 0.24),
                      at: soundingPost + Vector3(0, 1.7, 0), kind: .static)
        // The arm the line hangs off, so the sounding drops clear of the post.
        world.addBody(.box(width: 1.1, height: 0.16, depth: 0.16),
                      at: soundingPost + Vector3(0.35, 3.3, 0), kind: .static)
        // The gate is a detector, not a wall: the raft sails through it and it
        // reports the passage.
        gate = world.addBody(.box(width: 0.5, height: 2.4, depth: 6.6),
                             at: Vector3(gateX, 0, 0), kind: .static,
                             isSensor: true)
        for side in [-1.0, 1.0] {
            world.addBody(.cylinder(height: 3.0, radius: 0.16),
                          at: Vector3(gateX, 1.0, side * 3.4), kind: .static)
        }
    }

    /// A crate from above. It lands, the deck dips under it, and the landing
    /// comes back as a contact.
    func dropCrate(at x: Double) {
        let size = random(0.44, 0.58)
        let body = world.addBody(.box(width: size, height: size, depth: size),
                                 at: Vector3(x, 1.7, random(-0.5, 0.5)),
                                 rotated: random(-0.4, 0.4),
                                 axis: Vector3(0.3, 1, 0.2),
                                 density: 0.3, friction: 0.9)
        crates.append(Crate(body: body, size: size,
                            color: palette[crates.count % palette.count]))
    }

    override func mousePressed() {
        // The deck and the crates are taken hold of differently: a crate hangs
        // on a joint, a cloth has one of its particles pinned to the cursor.
        crateGrip = grabBody(at: mouse, in: world)
        if crateGrip == nil {
            grip = grabSoftBody(at: mouse, in: world)
        }
    }

    override func mouseReleased() {
        crateGrip?.remove()
        crateGrip = nil
        if let grip { releaseSoftGrab(grip) }
        grip = nil
    }

    override func keyPressed() {
        if key == " " { dropCrate(at: random(-0.7, 0.7)) }
    }

    override func draw() {
        background(Color(hex: 0x0A1521))
        environment(.sky(turbidity: 3.4, sunElevation: 0.8))
        lightingPreset(.goldenHour)
        castShadows()
        cameraShowcase(.autoOrbit(period: 44), from: Camera3D
            .perspective(eye: Vector3(1.2, 5.4, 9.2), target: Vector3(0, 0.2, 0)))

        // Both parameters reach the water between steps, so the raft answers them
        // while she is riding.
        world.water?.waves?.amplitude = swell
        raft?.density = deckDensity

        if let grip { dragSoftGrab(grip, to: mouse) }
        if let crateGrip { dragGrab(crateGrip, to: mouse) }
        world.advance(by: deltaTime)
        markLandings()

        drawSea()
        drawHarbour()
        drawRaft()
        drawCargo()
        drawSplashes()
        report()
    }

    /// Every landing in the scene, the deck's included. A soft body reaches the
    /// same list as everything else, so this one loop rings a crate hitting the
    /// water and a crate hitting the cloth alike.
    func markLandings() {
        for contact in world.contacts where contact.phase == .began {
            guard contact.speed > 0.8 else { continue }
            splashes.append(Splash(at: contact.point, strength: contact.speed))
        }
        for index in splashes.indices { splashes[index].age += deltaTime }
        splashes.removeAll { $0.age > 1.1 }
    }

    /// The sea, drawn from the very surface the raft is riding.
    func drawSea() {
        guard let surface = world.waterMesh(extent: 34, resolution: 108) else { return }
        fill(Color(hex: 0x2A7188))
        material(.dielectric(roughness: 0.3))
        drawMesh(surface)

        fill(Color(hex: 0x0D1A22))
        material(.dielectric(roughness: 0.95))
        withState {
            translate(0, deep, 0)
            drawBox(width: 70, height: 0.2, depth: 70)
        }
    }

    /// The sounding line and the gate. The line is a ray straight down: what it
    /// stops at is what is there, and the deck is now one of the answers.
    func drawHarbour() {
        material(.dielectric(roughness: 0.7))
        fill(Color(hex: 0x6B5138))
        withState {
            translate(soundingPost + Vector3(0, 1.7, 0))
            drawBox(width: 0.24, height: 3.4, depth: 0.24)
        }
        withState {
            translate(soundingPost + Vector3(0.35, 3.3, 0))
            drawBox(width: 1.1, height: 0.16, depth: 0.16)
        }

        let from = soundingPost + Vector3(0.65, 3.1, 0)
        let sounded = world.raycast(from: from, to: from + Vector3(0, -9, 0))
        let onDeck = sounded?.body is SoftBody3D
        let landed = sounded?.point ?? from + Vector3(0, -9, 0)
        // The line is the ray, drawn: it reaches exactly as far as the query
        // says, so it shortens onto the deck when she is under it.
        let drop = max(0.01, from.y - landed.y)
        fill(onDeck ? Color(hex: 0xF5D06A) : Color(hex: 0x8FB4C4))
        material(.dielectric(roughness: 0.4))
        withState {
            translate(from.x, from.y - drop / 2, from.z)
            drawCylinder(radius: 0.035, height: drop)
        }
        withState {
            translate(landed)
            drawSphere(radius: onDeck ? 0.13 : 0.08)
        }

        // The gate lights while the raft is inside it, which is a sensor
        // answering for a body that has no pose to ask about.
        let passing = gate.map { !$0.touching.isEmpty } ?? false
        fill(passing ? Color(hex: 0xF0E2A8) : Color(hex: 0x54606B))
        material(.dielectric(roughness: passing ? 0.3 : 0.8))
        for side in [-1.0, 1.0] {
            withState {
                translate(gateX, 1.0, side * 3.4)
                drawCylinder(radius: 0.16, height: 3.0)
            }
        }
    }

    /// One call: the simulation hands back the shape the deck arrived at.
    func drawRaft() {
        guard let raft else { return }
        fill(Color(hex: 0xC7A87C))
        material(.dielectric(roughness: 0.75))
        drawSoftBody(raft)
    }

    func drawCargo() {
        material(.dielectric(roughness: 0.65))
        for crate in crates {
            fill(crate.color)
            withBody(crate.body) {
                drawBox(width: crate.size, height: crate.size, depth: crate.size)
            }
        }
    }

    /// A ring at each landing, spreading and fading with age.
    func drawSplashes() {
        noFill()
        strokeWeight(2)
        for splash in splashes {
            let life = splash.age / 1.1
            let radius = 6 + 34 * life * min(1.4, splash.strength / 3)
            stroke(Color(hex: 0xEAF4F7).withAlpha(0.7 * (1 - life)))
            withBillboard(at: splash.at) { drawCircle(0, 0, radius) }
        }
        noStroke()
    }

    /// What is aboard, read off the deck itself: a soft body keeps a touch list
    /// like any other body, and holds it even once it has settled.
    func report() {
        let aboard = raft.map { deck in
            crates.filter { $0.body.isTouching(deck) }.count
        } ?? 0
        drawCaption("aboard: \(aboard)      drag the deck      space drops a crate")
    }
}
