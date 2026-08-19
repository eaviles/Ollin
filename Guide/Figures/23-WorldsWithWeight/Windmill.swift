// figure: frame=260
//
// Guide listing (Chapter 23): joint motors and compound bodies. The blade
// cross is ONE compound body (hub plus four blades, posed as parts) on a
// hinge driven at a constant rate; staged balls drop into the sweep and get
// batted at the swing gates, each a limited hinge held shut by a weak
// position motor. No random anywhere, so the moment replays identically.
import Ollin
import OllinPhysics

final class Windmill: Sketch {
    let world = World3D()

    let hubCenter = Vector3(0, 3, 0)
    let palette: [Color] = [
        Color(hex: 0xE8632F), Color(hex: 0xF2A93B),
        Color(hex: 0xD94F70), Color(hex: 0x8D92E0),
    ]

    override func setup() {
        world.ground = 0
        world.bounce = 0.3

        let tower = world.addBody(.box(width: 0.4, height: 2.9, depth: 0.3),
                                  at: Vector3(0, 1.45, -0.5), kind: .static)
        tower.userData = Color(hex: 0x6B5A48)
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
        let mill = world.connect(tower, cross, .revolute(at: hubCenter, axis: .unitZ))
        mill.drive(at: 2.5, strength: 500)

        for x in [3.4, -3.4] {
            let post = world.addBody(.box(width: 0.14, height: 1.15, depth: 0.14),
                                     at: Vector3(x, 0.575, -1.0), kind: .static)
            post.userData = Color(hex: 0x3A4150)
            let panel = world.addBody(.box(width: 0.08, height: 1.0, depth: 1.75),
                                      at: Vector3(x, 0.5, 0), friction: 0.3)
            panel.userData = Color(hex: 0x72BFB2)
            let gate = world.connect(post, panel,
                                     .revolute(at: Vector3(x, 0.5, -0.875),
                                               axis: .unitY, limits: -1.75 ... 1.75))
            gate.softenLimits(frequency: 3, damping: 0.5)
            gate.drive(to: 0, frequency: 1.2, strength: 15)
        }

        // Staged drops, no random: a steady feed into the sweep.
        let drops: [(Double, Double)] = [(-1.1, 4.8), (0.7, 5.6), (-0.4, 6.5),
                                         (1.1, 7.4), (-0.8, 8.4), (0.3, 9.2)]
        for (index, drop) in drops.enumerated() {
            let ball = world.addBody(.sphere(radius: 0.21),
                                     at: Vector3(drop.0, drop.1, 0),
                                     density: 1.5, friction: 0.4,
                                     restitution: 0.55)
            ball.userData = palette[index % palette.count]
        }
    }

    override func draw() {
        background(Color(hex: 0x0C0F15))
        environment(.courtyard.lightingOnly())
        lightingPreset(.studio)
        castShadows()
        perspective(eye: Vector3(-4.2, 3.8, 8.8), target: Vector3(0, 2.2, 0))

        world.step(dt: deltaTime)

        fill(Color(hex: 0x1A202A))
        material(.dielectric(roughness: 0.85))
        withState {
            translate(0, -0.06, 0)
            drawBox(width: 24, height: 0.12, depth: 24)
        }

        for body in world.bodies {
            withBody(body) {
                drawCollider(body.collider, tint: body.userData as? Color)
            }
        }
    }

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
