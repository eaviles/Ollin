// figure: frame=200
//
// Guide listing (Chapter 21): joints that make a machine. A motor turns the
// small wheel; a gear link ties its hinge to the big wheel's, so the big one
// turns half as fast the other way; and a rack-and-pinion link ties that same
// hinge to the bar's slider, so turning becomes sliding and the bar shoves the
// blocks to the end of their shelf. Each wheel carries one pale spoke so where
// it has got to is visible. No random anywhere, so it replays identically.
import Ollin
import OllinPhysics

final class Machines: Sketch {
    let world = World3D()

    var crank: Joint3D?
    var blocks: [Body3D] = []

    let smallHub = Vector3(-1.95, 2.0, 0)
    let bigHub = Vector3(0.15, 2.0, 0)
    let smallRadius = 0.7
    let bigRadius = 1.4
    let pinionRadius = 0.8
    var rackY: Double { bigHub.y - pinionRadius - 0.11 }

    let timber = Color(hex: 0x7C6142)
    let brass = Color(hex: 0xD9A441)
    let steel = Color(hex: 0xB9C2CE)
    let teal = Color(hex: 0x4FC1AE)

    override func setup() {
        world.ground = -0.8
        // Meshed teeth: plain cylinders would jam against each other.
        world.ignoreCollisions(between: "frame", and: "frame")

        let wall = world.addBody(.box(width: 6.0, height: 3.8, depth: 0.25),
                                 at: Vector3(-0.6, 1.3, -0.7), kind: .static,
                                 group: "frame")
        wall.userData = timber

        // A cylinder stands upright, so each wheel takes a quarter turn about x
        // to lay its axle along z, facing the camera.
        let small = world.addBody(.compound([
            .part(.cylinder(height: 0.3, radius: smallRadius),
                  rotated: .pi / 2, axis: .unitX, density: 3),
        ]), at: smallHub, group: "frame")
        small.userData = brass

        // One body wearing two wheels: the gear that meshes with the small one,
        // and the pinion in front of it that drives the bar.
        let big = world.addBody(.compound([
            .part(.cylinder(height: 0.3, radius: bigRadius),
                  rotated: .pi / 2, axis: .unitX, density: 3),
            .part(.cylinder(height: 0.3, radius: pinionRadius),
                  at: Vector3(0, 0, 0.45), rotated: .pi / 2, axis: .unitX,
                  density: 3),
        ]), at: bigHub, group: "frame")
        big.userData = brass

        let crankHinge = world.connect(wall, small,
                                       .revolute(at: smallHub, axis: .unitZ))
        let bigHinge = world.connect(wall, big, .revolute(at: bigHub, axis: .unitZ))
        world.connect(crankHinge, bigHinge, .gear(teeth: 20, and: 40))
        crank = crankHinge

        let barCenter = Vector3(bigHub.x, rackY, 0.45)
        let bar = world.addBody(.compound([
            .part(.box(width: 3.6, height: 0.22, depth: 0.22)),
            .part(.box(width: 0.2, height: 0.5, depth: 0.9),
                  at: Vector3(-1.5, -0.24, 0)),
        ]), at: barCenter, density: 2, group: "frame")
        bar.userData = steel

        let slide = world.connect(wall, bar,
                                  .prismatic(at: barCenter, axis: .unitX,
                                             limits: -0.02 ... 1.5))
        slide.softenLimits(frequency: 4, damping: 0.7)
        world.connect(bigHinge, slide,
                      .rackAndPinion(travelPerTurn: 2 * .pi * pinionRadius))

        let shelfTop = rackY - 0.49
        let shelf = world.addBody(.box(width: 4.4, height: 0.3, depth: 1.2),
                                  at: Vector3(bigHub.x, shelfTop - 0.15, 0.45),
                                  kind: .static, group: "frame")
        shelf.userData = timber

        for i in 0 ..< 4 {
            let block = world.addBody(.box(width: 0.3, height: 0.3, depth: 0.3),
                                      at: Vector3(bigHub.x - 1.0 + Double(i) * 0.42,
                                                  shelfTop + 0.16, 0.45),
                                      density: 0.6, friction: 0.5)
            block.userData = teal
            blocks.append(block)
        }
    }

    override func draw() {
        background(Color(hex: 0x0D111A))
        environment(.night.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        camera(.perspective(eye: Vector3(-0.4, 2.2, 8.9),
                            target: Vector3(-0.5, 1.35, 0.2),
                            fieldOfView: .pi / 4.6))

        crank?.drive(at: -1.1, strength: 600)
        world.step(dt: 1.0 / 60)

        fill(Color(hex: 0x11151F))
        material(.dielectric(roughness: 0.94))
        withState {
            translate(0, -0.87, 0)
            drawBox(width: 26, height: 0.14, depth: 26)
        }

        for body in world.bodies {
            withBody(body) { draw(body.collider, tint: body.userData as? Color) }
        }
    }

    func draw(_ collider: Collider3D, tint: Color?) {
        switch collider {
        case .box(let w, let h, let d):
            fill(tint ?? .white)
            material(.dielectric(roughness: 0.65))
            drawBox(width: w, height: h, depth: d)
        case .cylinder(let h, let r):
            fill(tint ?? steel)
            material(.metal(roughness: 0.38))
            drawCylinder(radius: r, height: h, segments: 28)
            drawSpokes(radius: r, height: h)
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

    /// Spokes across a wheel's face, one of them pale, so where the wheel has
    /// got to is readable in a still.
    func drawSpokes(radius r: Double, height: Double) {
        guard r > 0.3 else { return }
        material(.metal(roughness: 0.5))
        fill(Color(hex: 0x6E5426))
        for i in 0 ..< 6 {
            withState {
                rotate(Double(i) / 6 * .pi, axis: .unitY)
                drawBox(width: r * 1.85, height: height * 1.06, depth: r * 0.14)
            }
        }
        // One arm only, so the wheel's angle reads without a half-turn's doubt.
        fill(Color(hex: 0xF7EBCC))
        withState {
            translate(r * 0.47, 0, 0)
            drawBox(width: r * 0.9, height: height * 1.12, depth: r * 0.2)
        }
    }
}
