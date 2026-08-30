import Ollin
import OllinPhysics

/// A workshop of machines, each one a joint that ties two things together in a
/// way a hinge cannot. Nothing here is scripted: every part is a rigid body,
/// and the machine is what the joints between them make.
///
/// **Drag** anything to play with it. **Space** drops a crate into the tray on
/// the left of the hoist. **power** stops the drive train; **speed** sets how
/// fast it runs.
///
/// Left to right:
///
/// - The **drive train** is two links composing. A motor turns the small gear;
///   a `.gear` link ties its hinge to the big gear's, so the big one turns
///   slower and the other way, at the ratio of their teeth; and a
///   `.rackAndPinion` link ties that same hinge to the toothed bar's slider, so
///   the bar shuttles and shoves the blocks along their shelf. Both links name
///   two *joints*, not two bodies, because what they tie together is the motion
///   those joints allow.
/// - The **hoist** is a `.pulley`: one rope from the tray, up over two hooks,
///   and down to the counterweight. The length is fixed, so loading the tray
///   sends the weight up and vice versa.
/// - The **turntable** is a `.allowing` joint, the general one written as the
///   freedoms it keeps: this platter may rise along its post and spin about
///   it, and may do nothing else, however hard it is shoved.
/// - The **cart** rides a `.path`, a smooth track through a ring of points,
///   with `alignment: .followsPath` so it turns into every bend.
@main
final class Contraption: Sketch {
    let world = World3D()

    @Param(icon: "bolt") var power = true
    @Param(0.4 ... 4, icon: "speedometer") var speed = 1.6

    var crank: Joint3D?
    var ride: Joint3D?
    var grabbed: Joint3D?
    var blocks: [Body3D] = []
    var loaded: [Body3D] = []

    // The hoist's two ends and the hooks its rope runs over, kept so the rope
    // can be drawn where the joint is actually pulling.
    var tray: Body3D?
    var counterweight: Body3D?
    let leftHook = Vector3(0.6, 5.2, 0)
    let rightHook = Vector3(2.9, 5.2, 0)

    // The drive train, in one place because every part is measured off it.
    let smallHub = Vector3(-5.4, 2.4, 0)
    let bigHub = Vector3(-3.3, 2.4, 0)
    let smallRadius = 0.75
    let bigRadius = 1.35
    let pinionRadius = 0.85
    var rackY: Double { bigHub.y - pinionRadius - 0.11 }

    var track: [Vector3] = []

    let timber = Color(hex: 0x8A6A46)
    let brass = Color(hex: 0xD9A441)
    let steel = Color(hex: 0xB9C2CE)
    let teal = Color(hex: 0x4FA89B)
    let clay = Color(hex: 0xD2603F)

    override func setup() {
        world.ground = 0
        world.restitution = 0.15
        // Gear teeth mesh; plain cylinders would jam. Nothing in the frame
        // needs to collide with anything else in it.
        world.ignoreCollisions(between: "frame", and: "frame")

        buildDriveTrain()
        buildHoist()
        buildTurntable()
        buildTrack()
    }

    // MARK: The drive train

    func buildDriveTrain() {
        let wall = world.addBody(.box(width: 5.8, height: 3.6, depth: 0.25),
                                 at: Vector3(-4.2, 1.8, -0.75), kind: .static,
                                 group: "frame")
        wall.userData = timber

        // A cylinder stands upright, so every wheel here takes a quarter turn
        // about x to lay its axle along z, facing the camera.
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

        let crankHinge = world.connect(wall, small, .revolute(at: smallHub, axis: .unitZ))
        let bigHinge = world.connect(wall, big, .revolute(at: bigHub, axis: .unitZ))
        // 20 teeth against 36, which is the ratio of the two wheels drawn.
        world.connect(crankHinge, bigHinge, .gear(teeth: 20, and: 36))
        crank = crankHinge

        // The bar carries a fork, so the blocks between its two arms are
        // shuttled back and forth rather than shoved off one end.
        let barCenter = Vector3(bigHub.x, rackY, 0.45)
        let bar = world.addBody(.compound([
            .part(.box(width: 3.8, height: 0.22, depth: 0.22)),
            .part(.box(width: 0.2, height: 0.5, depth: 0.9),
                  at: Vector3(-0.8, -0.24, 0)),
            .part(.box(width: 0.2, height: 0.5, depth: 0.9),
                  at: Vector3(0.8, -0.24, 0)),
        ]), at: barCenter, density: 2, group: "frame")
        bar.userData = steel

        let slide = world.connect(wall, bar,
                                  .prismatic(at: barCenter, axis: .unitX,
                                             limits: -1.3 ... 1.3))
        slide.softenLimits(frequency: 4, damping: 0.6)
        // The pinion rolls along the bar, so one turn of it runs the bar the
        // pinion's own circumference.
        world.connect(bigHinge, slide,
                      .rackAndPinion(travelPerTurn: 2 * .pi * pinionRadius))

        let shelfTop = rackY - 0.49
        let shelf = world.addBody(.box(width: 4.4, height: 0.3, depth: 1.3),
                                  at: Vector3(bigHub.x, shelfTop - 0.15, 0.45),
                                  kind: .static, group: "frame")
        shelf.userData = timber

        for i in 0 ..< 3 {
            let block = world.addBody(.box(width: 0.34, height: 0.34, depth: 0.34),
                                      at: Vector3(bigHub.x - 0.5 + Double(i) * 0.5,
                                                  shelfTop + 0.18, 0.45),
                                      density: 0.6, friction: 0.5)
            block.userData = i == 1 ? clay : teal
            blocks.append(block)
        }
    }

    // MARK: The hoist

    func buildHoist() {
        let beam = world.addBody(.box(width: 4.6, height: 0.25, depth: 0.35),
                                 at: Vector3(1.75, 5.5, 0), kind: .static,
                                 group: "frame")
        beam.userData = timber
        for x in [-0.4, 3.9] {
            let leg = world.addBody(.box(width: 0.25, height: 5.4, depth: 0.3),
                                    at: Vector3(x, 2.7, 0), kind: .static,
                                    group: "frame")
            leg.userData = timber
        }

        // A tray, so a crate dropped in stays in: a floor and four low walls,
        // fused into one body by a compound collider.
        var walls: [Collider3D.Part] = [.part(.box(width: 1.1, height: 0.12, depth: 1.1))]
        for (dx, dz) in [(0.55, 0.0), (-0.55, 0.0), (0.0, 0.55), (0.0, -0.55)] {
            walls.append(.part(.box(width: dx == 0 ? 1.1 : 0.12, height: 0.5,
                                    depth: dz == 0 ? 1.1 : 0.12),
                               at: Vector3(dx, 0.25, dz)))
        }
        let basket = world.addBody(.compound(walls), at: Vector3(0.6, 3.2, 0),
                                   density: 0.5, friction: 0.6)
        basket.userData = steel
        tray = basket

        // The counterweight starts on the ground with the rope at its full
        // length, so the hoist opens at rest: it is the load in the tray that
        // starts it moving, and the weight that comes up in exchange.
        let weight = world.addBody(.box(width: 0.7, height: 0.7, depth: 0.7),
                                   at: Vector3(2.9, 0.35, 0), density: 3)
        weight.userData = clay
        counterweight = weight

        // The rope hangs the tray from its rim, above where its own weight
        // sits, which is what keeps an empty tray level instead of tumbling.
        world.connect(basket, weight,
                      .pulley(from: Vector3(0.6, 3.45, 0), over: leftHook,
                              and: rightHook, to: Vector3(2.9, 0.7, 0)))
    }

    // MARK: The turntable

    func buildTurntable() {
        let base = world.addBody(.box(width: 1.0, height: 1.0, depth: 1.0),
                                 at: Vector3(5.6, 0.5, 0), kind: .static,
                                 group: "frame")
        base.userData = timber

        let top = Vector3(5.6, 3.6, 0)
        let platter = world.addBody(.cylinder(height: 0.22, radius: 1.1),
                                    at: top, density: 1.2, friction: 0.8)
        platter.userData = steel
        platter.angularVelocity = Vector3(0, 2.6, 0)

        world.connect(base, platter,
                      .allowing([.moveY, .turnY], at: top, travel: -1.6 ... 0.01))

        for i in 0 ..< 3 {
            let angle = Double(i) / 3 * 2 * .pi
            let crate = world.addBody(.box(width: 0.4, height: 0.4, depth: 0.4),
                                      at: top + Vector3(cos(angle) * 0.72, 0.32,
                                                        sin(angle) * 0.72),
                                      density: 0.8, friction: 0.6)
            crate.userData = i == 0 ? clay : teal
        }
    }

    // MARK: The track

    func buildTrack() {
        // A little railway across the front, clear of everything behind it.
        track = (0 ..< 48).map { i in
            let a = Double(i) / 48 * 2 * .pi
            return Vector3(cos(a) * 5.0, 0.3, 3.9 + sin(a) * 1.7)
        }
        // The track belongs to its first body, so the rails need one; this one
        // sits under the floor because it is bookkeeping, not scenery.
        let rails = world.addBody(.box(width: 0.2, height: 0.2, depth: 0.2),
                                  at: Vector3(0, -2, 0), kind: .static,
                                  group: "frame")
        let cart = world.addBody(.box(width: 0.8, height: 0.45, depth: 0.5),
                                 at: track[0], density: 1.5)
        cart.userData = clay
        let joint = world.connect(rails, cart,
                                  .path(through: track, looping: true,
                                        alignment: .followsPath))
        joint.drive(at: 5, strength: 400)
        ride = joint
    }

    // MARK: Play

    override func keyPressed() {
        if key == " " {
            let crate = world.addBody(.box(width: 0.45, height: 0.45, depth: 0.45),
                                      at: Vector3(0.6 + random(-0.1, 0.1), 6.8, 0),
                                      density: 4, friction: 0.6)
            crate.userData = brass
            loaded.append(crate)
            // Keep the pile finite; the oldest crate is retired.
            if loaded.count > 4 { world.remove(loaded.removeFirst()) }
        }
    }

    override func mousePressed() {
        grabbed = grabBody(at: mouse, in: world)
    }

    override func mouseReleased() {
        grabbed?.remove()
        grabbed = nil
    }

    override func draw() {
        background(Color(hex: 0x0B0E14))
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(-0.6, 5.4, 14.2), target: Vector3(-0.5, 2.3, 1.6),
                    fieldOfView: 0.92)

        // A velocity motor whose rate swings slowly is what makes the whole
        // train reciprocate: the gears rock, and the bar runs out and back.
        if power {
            crank?.drive(at: sin(time * 0.55) * speed * 2.2, strength: 900)
        } else {
            crank?.stopMotor()
        }
        ride?.drive(at: power ? 5 : 0, strength: 400)

        if let grabbed { dragGrab(grabbed, to: mouse) }
        world.advance(by: deltaTime)

        // A block shoved off the end of its shelf goes back on it.
        for block in blocks where block.position.y < 0.6 {
            block.position = Vector3(bigHub.x, rackY + 0.4, 0.45)
            block.velocity = .zero
            block.angularVelocity = .zero
        }

        drawFloor()
        drawRail()
        drawRope()
        drawShaft()
        for body in world.bodies {
            withBody(body) { draw(body.collider, tint: body.userData as? Color) }
        }
    }

    func drawFloor() {
        fill(Color(hex: 0x161B24))
        material(.dielectric(roughness: 0.9))
        withState {
            translate(0, -0.08, 0)
            drawBox(width: 40, height: 0.16, depth: 26)
        }
    }

    /// The rail the cart is threaded on, drawn through the same points the
    /// track was built from.
    func drawRail() {
        fill(Color(hex: 0x5A6472))
        material(.metal(roughness: 0.5))
        drawTube(track, radius: 0.06, sides: 8, closed: true)
    }

    /// The hoist's rope, drawn where the joint is pulling: up from the tray,
    /// over both hooks, and down to the counterweight.
    func drawRope() {
        guard let tray, let counterweight else { return }
        fill(Color(hex: 0xE4D9C0))
        material(.dielectric(roughness: 0.8))
        drawTube([tray.position + Vector3(0, 0.25, 0), leftHook, rightHook,
                  counterweight.position + Vector3(0, 0.35, 0)],
                 radius: 0.035, sides: 6)
    }

    /// The turntable's post is drawing only: a body there would hold the
    /// platter up before its joint ever stopped it.
    func drawShaft() {
        fill(steel)
        material(.metal(roughness: 0.4))
        withState {
            translate(5.6, 2.5, 0)
            drawCylinder(radius: 0.13, height: 3)
        }
    }

    /// A collider's matching mesh; a compound recurses into its parts at their
    /// local poses, so a fused assembly rides the one simulated body.
    func draw(_ collider: Collider3D, tint: Color?) {
        switch collider {
        case .box(let w, let h, let d):
            fill(tint ?? .white)
            material(.dielectric(roughness: 0.65))
            drawBox(width: w, height: h, depth: d)
        case .cylinder(let h, let r):
            fill(tint ?? steel)
            material(.metal(roughness: 0.38))
            drawCylinder(radius: r, height: h)
            drawSpokes(radius: r, height: h)
        case .sphere(let r):
            fill(tint ?? .white)
            material(.dielectric(roughness: 0.35))
            drawSphere(radius: r)
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

    /// Spokes across a wheel's face, so which way it is turning is visible.
    func drawSpokes(radius r: Double, height: Double) {
        guard r > 0.3 else { return }
        fill(Color(hex: 0x6E5426))
        material(.metal(roughness: 0.5))
        for i in 0 ..< 6 {
            withState {
                rotate(Double(i) / 6 * .pi, axis: .unitY)
                drawBox(width: r * 1.85, height: height * 1.06, depth: r * 0.13)
            }
        }
    }
}
