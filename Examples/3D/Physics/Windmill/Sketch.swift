import Ollin
import OllinPhysics

/// A windmill under power: a motored hinge spins the blade cross, balls drop
/// into the sweep and get batted out through spring-shut swing gates. **Drag**
/// a ball to feed the blades; **space** cuts the power and hinge friction
/// coasts the mill to a stop.
///
/// The motor showcase for `World3D`: the blade cross is one `.compound` body
/// (hub plus four blades, posed as parts), `drive(at:)` turns it at a steady
/// rate, each gate is a limited `.revolute` whose `drive(to: 0)` closer pulls
/// it shut, `softenLimits` makes the stops bouncy, and `friction` is what
/// winds the mill down when the power is off.
@main
final class Windmill: Sketch {
    let world = World3D()
    var mill: Joint3D?
    var balls: [Body3D] = []
    var restFrames: [Int] = []
    var powered = true

    @Param(0 ... 5, icon: "wind") var millSpeed = 2.5

    let hubCenter = Vector3(0, 3, 0)
    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B),
        Color(hex: 0xD94F70), Color(hex: 0x8D92E0),
    ]

    override func setup() {
        world.ground = 0
        world.bounce = 0.3

        buildMill()
        buildGate(at: 3.4)
        buildGate(at: -3.4)
        for index in 0 ..< 6 { dropBall(index) }
    }

    /// The tower behind the sweep, and the blade cross as ONE body: a compound
    /// of the hub cylinder and four blades, each a part posed in the cross's
    /// local space, hung on one motored hinge. Mass, balance, and inertia come
    /// from the whole assembly, and a part can never drift off its pose.
    func buildMill() {
        let tower = world.addBody(.box(width: 0.4, height: 2.9, depth: 0.3),
                                  at: Vector3(0, 1.45, -0.5), kind: .static)
        tower.userData = Color(hex: 0x6B5A48)

        // The hub faces the camera: a cylinder is upright, so lay its axis
        // along z with a quarter turn about x. Denser metal than the timber
        // blades, via the part's own density.
        var parts: [Collider3D.Part] = [
            .part(.cylinder(height: 0.2, radius: 0.32),
                  rotated: .pi / 2, axis: .unitX, density: 2),
        ]
        for arm in 0 ..< 4 {
            let angle = Double(arm) * .pi / 2
            let direction = Vector3(cos(angle), sin(angle), 0)
            parts.append(.part(.box(width: 1.5, height: 0.26, depth: 0.08),
                               at: direction * 1.11, rotated: angle, axis: .unitZ))
        }
        let cross = world.addBody(.compound(parts), at: hubCenter)
        cross.userData = Color(hex: 0xE8DCC5)

        let hinge = world.connect(tower, cross,
                                  .revolute(at: hubCenter, axis: .unitZ))
        hinge.friction = 80   // the brake that coasts it down when unpowered
        mill = hinge
    }

    /// A swing gate: a panel on a vertical limited hinge, pulled shut by a
    /// gentle position motor a rolling ball can still barge through.
    func buildGate(at x: Double) {
        let post = world.addBody(.box(width: 0.14, height: 1.15, depth: 0.14),
                                 at: Vector3(x, 0.575, -1.0), kind: .static)
        post.userData = Color(hex: 0x3A4150)
        let panel = world.addBody(.box(width: 0.08, height: 1.0, depth: 1.75),
                                  at: Vector3(x, 0.5, 0), friction: 0.3)
        panel.userData = Color(hex: 0x72BFB2)

        let gate = world.connect(post, panel,
                                 .revolute(at: Vector3(x, 0.5, -0.875),
                                           axis: .unitY, limits: -1.75 ... 1.75))
        gate.softenLimits(frequency: 3, damping: 0.5)   // bouncy end stops
        gate.friction = 0.5
        gate.drive(to: 0, frequency: 1.2, strength: 60)   // the door closer
    }

    /// Feed a ball into the sweep from above, staggered so they don't arrive
    /// as one clump.
    func dropBall(_ index: Int) {
        let ball = world.addBody(.sphere(radius: 0.21),
                                 at: Vector3(random(-1.2, 1.2),
                                             5 + Double(index) * 0.9,
                                             random(-0.04, 0.04)),
                                 density: 1.5, friction: 0.4, restitution: 0.35)
        ball.userData = palette[index % palette.count]
        balls.append(ball)
        restFrames.append(0)
    }

    /// A ball batted past the gates comes back around for another pass.
    func recycle(_ ball: Body3D) {
        ball.position = Vector3(random(-1.2, 1.2), 5 + random(0, 1),
                                random(-0.04, 0.04))
        ball.velocity = .zero
        ball.angularVelocity = .zero
    }

    override func keyPressed() {
        if key == " " {
            powered.toggle()
            if !powered { mill?.stopMotor() }
        }
    }

    override func draw() {
        background(Color(hex: 0x0C0F15))
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(-4.2, 3.8, 8.8), target: Vector3(0, 2.2, 0))

        // Re-asserting the rate each frame keeps the knob live and the mill
        // awake; the strength cap gives it a mechanical spin-up.
        if powered { mill?.drive(at: millSpeed, strength: 500) }
        dragBodies(in: world)
        world.step(dt: deltaTime)
        // Batted past the gates, or parked out of the blades' reach for a
        // couple of seconds: either way, back into the drop.
        for (index, ball) in balls.enumerated() {
            restFrames[index] = ball.velocity.length < 0.08
                ? restFrames[index] + 1 : 0
            if abs(ball.position.x) > 6.2 || abs(ball.position.z) > 4
                || restFrames[index] > 150 {
                recycle(ball)
                restFrames[index] = 0
            }
        }

        fill(Color(hex: 0x1A202A))
        material(.dielectric(roughness: 0.85))
        drawGround(size: 24)

        for body in world.bodies {
            withBody(body) {
                drawCollider(body.collider, tint: body.userData as? Color)
            }
        }
    }

    /// Draw a collider's matching mesh; a compound recurses into its parts at
    /// their local poses, so the drawn cross rides the one simulated body.
    func drawCollider(_ collider: Collider3D, tint: Color?) {
        switch collider {
        case .box(let w, let h, let d):
            fill(tint ?? .white)
            material(.dielectric(roughness: 0.6))
            drawBox(width: w, height: h, depth: d)
        case .cylinder(let h, let r):
            fill(Color(hex: 0xB8C0CC))
            material(.metal(roughness: 0.35))
            drawCylinder(radius: r, height: h)
        case .sphere(let r):
            fill(tint ?? .white)
            material(.dielectric(roughness: 0.3))
            drawSphere(radius: r)
        case .compound(let parts):
            for part in parts {
                withState {
                    translate(part.position)
                    if part.angle != 0 { rotate(part.angle, axis: part.axis) }
                    drawCollider(part.collider, tint: tint)
                }
            }
        default:
            break
        }
    }
}
