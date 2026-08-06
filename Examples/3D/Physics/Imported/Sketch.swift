import Foundation
import Ollin
import OllinPhysics

/// A scene whose physics was written down somewhere else.
///
/// Nothing in this sketch says what falls. `yard.usda` does: which of its prims
/// are rigid bodies, which are scenery, what shape each collides as, how heavy
/// they are, and where the two hinges go. `world.addBodies(from: scene)` reads
/// all of it and makes the ordinary bodies and joints, so the sketch is a
/// camera, a lighting preset, and a loop that draws whatever came across.
///
/// That is what a shared format is good at, and it is a one-way trade on
/// purpose. Reading is lossy and that is fine: anything the file does not say
/// has a sensible answer here. Writing would not be, which is why a world you
/// want back exactly goes into Ollin's own snapshot instead.
///
/// Worth looking at in the file, since each one is a rule rather than a
/// coincidence:
///
/// - **Ground** and **Fulcrum** are colliders with no rigid body on them, so
///   they are scenery and never move.
/// - **Hammer** is one body with a cylinder and a box under it, because a rigid
///   body owns everything in its subtree: several colliders make one compound.
/// - **Sign** hangs from a hinge that names only one body, which means the
///   world itself. The post beside it is scenery: the joint does not name it,
///   and taking the post away would change nothing.
/// - **Roller** is a capsule authored the USD default way, standing on **z**,
///   where Ollin's stand on y. It comes in lying down because that is what the
///   file says.
/// - **Ball** is bound to a physics material, so it keeps its bounce.
///
/// Press **space** to drop the weight on the seesaw again, **R** to put the
/// yard back the way the file describes it.
@main
final class Imported: Sketch {
    let world = World3D()
    var scene: Scene!

    /// A colour per prim name, so the drawing loop can tell the parts apart
    /// without a parallel array: every body knows the name it came in under.
    let colors: [String: Color] = [
        "Ground": Color(hex: 0x6E6A55), "Fulcrum": Color(hex: 0x53503F),
        "Plank": Color(hex: 0xC08B4E), "Weight": Color(hex: 0x8C4A3F),
        "CrateA": Color(hex: 0xB08A57), "CrateB": Color(hex: 0xC79A63),
        "CrateC": Color(hex: 0x9B7847), "Ball": Color(hex: 0x3E7A86),
        "Hammer": Color(hex: 0x6C6F79), "Sign": Color(hex: 0xB5533F),
        "Roller": Color(hex: 0x77804C), "Post": Color(hex: 0x4E4A3C),
        "Arm": Color(hex: 0x4E4A3C),
    ]

    override func setup() {
        scene = Scene(resource: "yard", extension: "usda", in: Bundle.module)
        rebuild()
    }

    /// The whole world, in one call. The file's own gravity comes with it.
    func rebuild() {
        world.removeAll()
        world.bounce = 0.2
        world.addBodies(from: scene, applyGravity: true)
    }

    override func keyPressed() {
        switch key?.lowercased() ?? "" {
        case "r": rebuild()
        case " ": drop()
        default: break
        }
    }

    /// Put the weight back over the seesaw's near end and let it go again.
    func drop() {
        guard let weight = world.bodies.first(where: { $0.assetName == "Weight" })
        else { return }
        weight.position = Vector3(-4.1, 1.5, -2)
        weight.velocity = .zero
        weight.angularVelocity = .zero
        weight.setRotation(0, axis: .unitY)
        weight.wake()
    }

    override func draw() {
        background(Color(hex: 0x14181E))
        environment(.sky(turbidity: 3.4, sunElevation: 0.42))
        lightingPreset(.goldenHour)
        castShadows()
        perspective(eye: Vector3(5.4, 3.9, 8.2), target: Vector3(-0.5, 1.1, -0.6))

        world.step(dt: deltaTime)

        for body in world.bodies {
            fill(colors[body.assetName ?? ""] ?? .white)
            material(body.assetName == "Ball" ? .glossy
                                              : .dielectric(roughness: 0.9))
            withBody(body) { draw(body.collider) }
        }

        drawCaption("physics read from yard.usda"
                    + "      space drop the weight      R reset")
    }

    /// Every body draws itself out of the collider the file described, the
    /// compound ones part by part.
    func draw(_ collider: Collider3D) {
        switch collider {
        case .box(let width, let height, let depth):
            drawBox(width: width, height: height, depth: depth)
        case .sphere(let radius):
            drawSphere(radius: radius)
        case .capsule(let height, let radius):
            drawCapsule(radius: radius, height: height)
        case .cylinder(let height, let radius):
            drawCylinder(radius: radius, height: height)
        case .cone(let height, let radius):
            drawCone(radius: radius, height: height)
        case .compound(let parts):
            for part in parts {
                withState {
                    translate(part.position)
                    if part.angle != 0 { rotate(part.angle, axis: part.axis) }
                    draw(part.collider)
                }
            }
        default:
            break
        }
    }
}
