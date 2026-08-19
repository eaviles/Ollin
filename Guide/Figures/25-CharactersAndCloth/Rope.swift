// figure: frame=600
//
// Guide listing (Chapter 25): ropes. Three lines stick out from the same post,
// built as the same straight polyline and differing only in `bend`: the limp
// one has folded straight down, the middle one droops in an arc, and the stiff
// one still holds itself out. On the right the limp one again, drawn as a link
// on every segment with every other one rolled a quarter turn about the rope's
// own axis, which is a turn only a rod that knows how it is rolled can be asked
// for. No random anywhere, so it settles identically every time.
import Ollin
import OllinPhysics

final class Rope: Sketch {
    let world = World3D()
    var arms: [Rope3D] = []
    var chain: Rope3D!

    static let postHeight = 3.0

    /// A straight line sticking out to the right: the cantilever every bend is
    /// measured by, since gravity pulls across it rather than along it.
    static func arm(_ n: Int, spacing: Double) -> [Vector3] {
        (0 ..< n).map { Vector3(Double($0) * spacing, 0, 0) }
    }

    override func setup() {
        world.ground = 0
        for (index, bend) in [0.0, 0.5, 1.0].enumerated() {
            let line = world.addRope(through: Rope.arm(22, spacing: 0.061),
                                     // A little in front of the posts, so a
                                     // line that folds down hangs clear of one.
                                     at: Vector3(-2.45 + Double(index) * 1.5, 2.52, 0.14),
                                     thickness: 0.03, mass: 0.5,
                                     bend: bend, damping: 0.55, iterations: 12,
                                     pinned: { $0.x < 0.04 })
            if let line { arms.append(line) }
        }
        // The same limp rope again, with something to carry.
        chain = world.addRope(through: (0 ..< 13).map { Vector3(0, -Double($0) * 0.155, 0) },
                              at: Vector3(2.22, 2.52, 0.5),
                              thickness: 0.055, mass: 2.5,
                              bend: 0.06, damping: 0.4, iterations: 10,
                              pinned: { $0.y > -0.001 },
                              maxStretch: 1)
    }

    override func draw() {
        background(Color(hex: 0x101620))
        environment(.sky(turbidity: 3.2, sunElevation: 0.66))
        lightingPreset(.standard)
        castShadows()
        camera(.perspective(eye: Vector3(-0.1, 2.0, 9.9),
                            target: Vector3(-0.1, 1.55, 0), fieldOfView: .pi / 5.4))
        world.step(dt: 1.0 / 60)

        material(.dielectric(roughness: 0.9))
        fill(Color(hex: 0x2B3442))
        withState {
            translate(0, -0.08, 0)
            drawBox(width: 18, height: 0.16, depth: 18)
        }
        // One post per line, so each hangs clear of the next.
        fill(Color(hex: 0x4A4137))
        for x in [-2.53, -1.03, 0.47, 2.22] {
            withState {
                translate(x, Rope.postHeight / 2, 0)
                drawBox(width: 0.18, height: Rope.postHeight, depth: 0.18)
            }
        }
        withState {
            translate(2.22, 2.6, 0.28)
            drawBox(width: 0.14, height: 0.12, depth: 0.62)
        }

        // The three that differ only in how hard they resist bending.
        material(.dielectric(roughness: 0.85))
        for (index, line) in arms.enumerated() {
            fill([Color(hex: 0xC8A87A), Color(hex: 0xCF8F5A), Color(hex: 0x6FA96B)][index])
            drawSoftBody(line)
        }

        // And the one that carries something. `withSegment` stands in the
        // middle of a rod with +y along it, so a ring laid on its side is a
        // link the rope runs through, and rolling every other one interlocks
        // them.
        material(.metal(roughness: 0.32))
        fill(Color(hex: 0x8E98AA))
        for segment in chain.segments {
            withSegment(segment) {
                rotate(.pi / 2, axis: Vector3(1, 0, 0))
                if segment.index.isMultiple(of: 2) {
                    rotate(.pi / 2, axis: Vector3(0, 0, 1))
                }
                drawTorus(radius: segment.length * 0.6, tube: 0.028,
                          segments: 20, sides: 8)
            }
        }
    }
}
