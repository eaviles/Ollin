// figure: frame=540
//
// Guide listing (Chapter 24): a soft body as a member of the world. A cloth
// deck floats at the waterline its own `density` sets, carries two crates that
// arrived by landing on it (so the deck is in `world.contacts` too), and stops
// the sounding line hanging beside it, which a ray reports as a hit on cloth.
// Still-ish water and no random anywhere, so it replays identically.
import Ollin
import OllinPhysics

final class Raft: Sketch {
    let world = World3D()
    var raft: SoftBody3D?
    var crates: [(body: Body3D, size: Double, color: Color)] = []

    let deep = -3.5
    let deckSize = 3.4
    let post = Vector3(-2.5, 0, -0.5)

    override func setup() {
        world.ground = deep
        world.water = Water(level: 0, linearDrag: 0.4,
                            waves: Water.Waves(amplitude: 0.08, wavelength: 9,
                                               speed: 1.2))

        raft = world.addSoftBody(from: .plane(width: deckSize, depth: deckSize,
                                              segments: 14),
                                 at: Vector3(0, 0.4, 0), mass: 240,
                                 stiffness: 0.998, bend: 1, damping: 0.1,
                                 friction: 0.95, iterations: 14,
                                 vertexRadius: 0.08)
        // A sheet holds no volume to work its own weight for its size out of,
        // so this is the line that makes it a raft rather than a wet sheet.
        raft?.density = 0.25

        // Cargo, dropped on: it lands, the deck dips, and the landing is a
        // contact like any other.
        for (index, color) in [Color(hex: 0xD9A441), Color(hex: 0x8FA860)].enumerated() {
            let size = 0.46 + Double(index) * 0.06
            crates.append((world.addBody(.box(width: size, height: size, depth: size),
                                         at: Vector3(Double(index) * 0.9 + 0.1,
                                                     1.2, Double(index) * 0.5 + 0.45),
                                         density: 0.3, friction: 0.9),
                           size, color))
        }

        // The sounding line's post and the arm it hangs from.
        world.addBody(.box(width: 0.2, height: 3.0, depth: 0.2),
                      at: post + Vector3(0, 1.5, 0), kind: .static)
        world.addBody(.box(width: 1.75, height: 0.14, depth: 0.14),
                      at: post + Vector3(0.72, 2.9, -0.35), kind: .static)
    }

    override func draw() {
        background(Color(hex: 0x0C1622))
        environment(.sky(turbidity: 3.2, sunElevation: 0.85))
        lightingPreset(.goldenHour)
        castShadows()
        camera(.perspective(eye: Vector3(1.6, 3.6, 7.8),
                            target: Vector3(-0.3, 0.5, 0), fieldOfView: .pi / 4))

        world.step(dt: 1.0 / 60)

        // The deck, in whatever shape it arrived at.
        if let raft {
            fill(Color(hex: 0xC7A87C))
            material(.dielectric(roughness: 0.75))
            drawSoftBody(raft)
        }

        material(.dielectric(roughness: 0.65))
        for crate in crates {
            fill(crate.color)
            withBody(crate.body) {
                drawBox(width: crate.size, height: crate.size, depth: crate.size)
            }
        }

        // The post, and the line, which reaches exactly as far as the ray does.
        fill(Color(hex: 0x6B5138))
        material(.dielectric(roughness: 0.7))
        withState {
            translate(post + Vector3(0, 1.5, 0))
            drawBox(width: 0.2, height: 3.0, depth: 0.2)
        }
        withState {
            translate(post + Vector3(0.72, 2.9, -0.35))
            drawBox(width: 1.75, height: 0.14, depth: 0.14)
        }

        let from = post + Vector3(1.45, 2.75, -0.35)
        let hit = world.raycast(from: from, to: from + Vector3(0, -8, 0))
        let landed = hit?.point ?? from + Vector3(0, -8, 0)
        let onDeck = hit?.body is SoftBody3D
        let drop = max(0.01, from.y - landed.y)
        fill(onDeck ? Color(hex: 0xF5D06A) : Color(hex: 0x8FB4C4))
        material(.dielectric(roughness: 0.4))
        withState {
            translate(from.x, from.y - drop / 2, from.z)
            drawCylinder(radius: 0.03, height: drop)
        }
        withState {
            translate(landed)
            drawSphere(radius: onDeck ? 0.11 : 0.07)
        }

        // The sea, drawn from the very surface the raft is riding.
        if let surface = world.waterMesh(extent: 26, resolution: 60) {
            fill(Color(hex: 0x2C7C96))
            material(.dielectric(roughness: 0.3))
            drawMesh(surface)
        }
        fill(Color(hex: 0x0E1A24))
        material(.dielectric(roughness: 0.95))
        withState {
            translate(0, deep, 0)
            drawBox(width: 60, height: 0.2, depth: 60)
        }
    }
}
