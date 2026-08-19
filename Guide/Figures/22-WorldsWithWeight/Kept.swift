// figure: frame=1
//
// Guide listing (Chapter 22): why a settled arrangement is saved rather than
// made again. Three heaps built by the same code. The first is simulated and
// then captured; the second is that capture restored, which is exact; the
// third is simulated again with one stone released a ten-millionth of a unit
// higher, which is enough to make a different heap. No random anywhere, so it
// replays identically.
import Ollin
import OllinPhysics

final class Kept: Sketch {
    override var canvasSize: CanvasSize { .size(1240, 560) }

    var heaps: [World3D] = []

    let spacing = 2.7
    let stones: [Color] = [Color(hex: 0x9C9282), Color(hex: 0x847A6C),
                           Color(hex: 0xAAA292), Color(hex: 0x6F6A61)]

    override func setup() {
        let saved = build(nudge: 0)

        let restored = World3D()
        restored.restore(saved.snapshot())

        heaps = [saved, restored, build(nudge: 1e-7)]
    }

    /// A heap laid one stone at a time, each one settling before the next
    /// arrives. `nudge` lifts the fourth stone's release point, and nothing
    /// else, by an amount no eye could find in the setup.
    func build(nudge: Double) -> World3D {
        let world = World3D()
        world.ground = 0
        world.bounce = 0
        var top = 0.0
        for i in 0 ..< 12 {
            let turn = Double(i) * 2.399           // the golden angle: no lanes
            let shape: Collider3D = i % 3 == 0
                ? .cylinder(height: 0.14, radius: 0.32)
                : .box(width: 0.42, height: 0.16, depth: 0.42)
            world.addBody(shape,
                          at: Vector3(cos(turn) * 0.16,
                                      top + 0.4 + (i == 3 ? nudge : 0),
                                      sin(turn) * 0.16),
                          rotated: Double(i) * 0.53, axis: .unitY,
                          density: 2.4, friction: 1, restitution: 0)
            for _ in 0 ..< 75 { world.step(dt: 1.0 / 60) }
            top = world.bodies.map(\.position.y).max() ?? 0
        }
        for _ in 0 ..< 400 { world.step(dt: 1.0 / 60) }
        return world
    }

    override func draw() {
        background(Color(hex: 0x11131A))
        environment(.night.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        camera(.perspective(eye: Vector3(0, 1.75, 7.9),
                            target: Vector3(0, 0.78, 0),
                            fieldOfView: .pi / 5.2))

        fill(Color(hex: 0x1A1E27))
        material(.dielectric(roughness: 0.95))
        withState {
            translate(0, -0.07, 0)
            drawBox(width: 30, height: 0.14, depth: 30)
        }

        let names = ["saved", "restored", "simulated again"]
        for (h, heap) in heaps.enumerated() {
            withState {
                translate(spacing * (Double(h) - 1), 0, 0)
                for (i, body) in heap.bodies.enumerated() {
                    fill(stones[i % stones.count])
                    material(.dielectric(roughness: 0.85))
                    withBody(body) { draw(body.collider) }
                }
                withBillboard(at: Vector3(0, 1.45, 0)) {
                    fill(h == 2 ? Color(hex: 0xE8A05A) : Color(hex: 0xCFD6E2))
                    textSize(26)
                    textAlign(.center, .middle)
                    drawText(names[h], 0, 0)
                }
            }
        }
    }

    func draw(_ collider: Collider3D) {
        switch collider {
        case .box(let width, let height, let depth):
            drawBox(width: width, height: height, depth: depth)
        case .cylinder(let height, let radius):
            drawCylinder(radius: radius, height: height, segments: 28)
        default:
            break
        }
    }
}
