import Foundation
import Ollin
import OllinPhysics

/// A skinned figure given weight. `addRagdoll(from:)` reads the scene's
/// skeleton and builds one rigid body per joint, sizing each from the part of
/// the mesh that joint moves, and `figure.apply(ragdoll)` writes the solver's
/// answer back onto those joints, which is `apply(_:at:)` run backwards.
///
/// The two states are the point. Powered, every joint has a motor pulling
/// toward the pose the "wave" animation is asking for, so the figure stands and
/// waves, and an arm you drag springs back the moment you let go. Limp, the
/// motors are off and only the joint limits are left, so the same figure falls
/// in a heap and stays there. Space switches between them, `R` stands it back
/// up, and `B` shows the capsules the fit found under the skin.
///
/// Drag any limb with the mouse: a ragdoll's limbs are ordinary bodies, so
/// picking, contacts, and the drag spring all work on them.
@main
final class Ragdoll: Sketch {
    let world = World3D()
    /// The figure that is drawn: posed from the solver every frame.
    var figure: Scene!
    /// A second copy of the same scene, kept as the *target*: the animation
    /// poses this one, and the motors chase it. Keeping them apart is what
    /// stops the figure from chasing where it already is.
    var target: Scene!
    var ragdoll: Ragdoll3D!
    var wave: SceneAnimation?

    var standing = true
    var showBones = false

    /// How hard a joint may pull toward the pose, in newton-meters. Low is a
    /// figure too tired to hold itself up; high is one that will not be moved.
    @Param(2 ... 400, icon: "figure.strengthtraining.traditional") var effort = 120.0
    /// How far a joint may bend away from where it started. Loose is rubbery;
    /// tight is a mannequin.
    @Param(5 ... 90, icon: "angle") var looseness = 45.0

    var appliedLooseness = 0.0

    override func setup() {
        figure = Scene(resource: "figure", withExtension: "gltf", in: Bundle.module)
        target = figure
        wave = figure.animations.first
        world.ground = 0
        world.restitution = 0.05
        ragdoll = world.addRagdoll(from: figure, at: Vector3(0, 0.95, 0),
                                   mass: 72, friction: 0.7)
        standUp()
    }

    override func draw() {
        background(Color(hex: 0x101620))
        environment(.sky(turbidity: 3.2, sunElevation: 0.7))
        lightingPreset(.standard)
        castShadows()
        camera(.perspective(eye: Vector3(2.6, 2.0, 4.4),
                            target: Vector3(0, 0.9, 0), fieldOfView: .pi / 4))

        retune()
        if standing {
            // The animation says where the limbs should be; the motors decide
            // how hard they try to get there. The target scene is posed fresh
            // every frame, so the figure always has somewhere to pull toward.
            if let wave {
                target.apply(wave, at: time.truncatingRemainder(dividingBy: wave.duration))
            }
            ragdoll.drive(toward: target, strength: effort)
        }
        dragBodies(in: world)

        world.advance(by: deltaTime)
        figure.apply(ragdoll)

        drawFloor()
        // The capsules live inside the skin, so the two views swap rather than
        // stack: `B` is a look at what the solver is actually holding.
        if showBones {
            drawBones()
        } else {
            fill(.white)   // white shows the file's own material untouched
            drawScene(figure)
        }

        drawCaption("\(standing ? "powered" : "limp")\(showBones ? " · bones" : "")"
            + "      space to switch, R to stand up, B for the bones, drag a limb")
    }

    /// Stand the figure back up: put every limb where the animation's opening
    /// pose has it, and pin the hips so the powered figure has something to
    /// hold itself up against (nothing above the root drives it, so a figure
    /// with everything dynamic topples however firmly it holds its shape).
    func standUp() {
        if let wave { target.apply(wave, at: 0) }
        ragdoll.pose(from: target)
        standing = true
        ragdoll.limbs[0].body.kind = .kinematic
    }

    /// Let go: the hips fall with the rest, and the motors stop pulling.
    func goLimp() {
        standing = false
        ragdoll.limbs[0].body.kind = .dynamic
        ragdoll.goLimp()
    }

    /// The looseness parameter, applied to every joint the moment it moves.
    func retune() {
        guard abs(looseness - appliedLooseness) > 0.01 else { return }
        appliedLooseness = looseness
        let swing = looseness * .pi / 180
        for limb in ragdoll.limbs {
            ragdoll.limit(limb.name, swing: swing, twist: -swing / 3 ... swing / 3)
        }
    }

    override func keyPressed() {
        switch key {
        case " ": standing ? goLimp() : standUp()
        case "r", "R": standUp()
        case "b", "B": showBones.toggle()
        default: break
        }
    }

    /// The capsules the fit found: each limb's shape, in the place the solver
    /// actually keeps it. `withLimb` poses the body *and* the offset that puts
    /// the shape on the bone.
    func drawBones() {
        noStroke()
        material(.dielectric(roughness: 0.35))
        fill(Color(hex: 0x72BFB2))
        for limb in ragdoll.limbs {
            withLimb(limb) {
                switch limb.collider {
                case .capsule(let height, let radius):
                    drawCapsule(radius: radius, height: height)
                case .sphere(let radius):
                    drawSphere(radius: radius)
                default:
                    break
                }
            }
        }
    }

    func drawFloor() {
        material(.dielectric(roughness: 0.95))
        fill(Color(hex: 0x2A3140))
        drawGround(size: 14, thickness: 0.3)
    }
}
