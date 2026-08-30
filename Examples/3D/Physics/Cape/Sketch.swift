import Foundation
import Ollin
import OllinPhysics

/// Cloth that a figure carries. The cape is an ordinary soft body, but its
/// collar is tied to the skeleton under the skin: `carriedBy:` names the joint
/// that carries each part of it, `follow(_:)` hands the simulation this frame's
/// pose, and everything below the collar is left to hang, swing, and catch the
/// air.
///
/// Only the top edge is held. The rest is told how far it may get from where
/// the shoulders would put it (`sway:`), how far behind the figure's back it
/// may be pushed before it is held out (`backStop:`), and how far it may reach
/// from what holds it (`maxStretch:`), so a heavy cape stops stretching like a
/// spring under its own weight.
///
/// **Space** switches the figure between powered and limp: powered it strides
/// and waves and the cape streams behind it, limp the whole thing collapses and
/// the cape comes down with it. **F** cuts the leash, so only the collar stays
/// on the shoulders. **Drag** a limb to swing the figure about.
@main
final class Cape: Sketch {
    let world = World3D()
    /// The figure that is drawn, posed from the solver every frame.
    var figure: Scene!
    /// A second copy, kept as the pose the motors chase.
    var target: Scene!
    var ragdoll: Ragdoll3D!
    var cape: SoftBody3D!
    var wave: SceneAnimation?

    var standing = true

    /// How far the cloth may travel from where the shoulders put it, as a
    /// multiple of what it was built with. Low is a stiff mantle; high is a
    /// loose cloak.
    @Param(0 ... 4, icon: "wind") var looseness = 1.0
    /// How hard the figure strides from side to side, in units.
    @Param(0 ... 1.4, icon: "figure.walk") var stride = 0.7

    /// The cape's rest shape: a sheet lying in the xz plane, stood upright by
    /// the body's own rotation. So in the mesh's own space `z` runs from the
    /// collar (negative) to the hem, and `x` across the shoulders.
    static let length = 1.2
    static let sheet = Mesh.plane(width: 0.8, depth: length, segments: 18)
    static let collar = -length / 2 + 0.02
    let capeColor = Color(hex: 0x9E2B3A)

    override func setup() {
        figure = Scene(resource: "figure", withExtension: "gltf", in: Bundle.module)
        target = figure
        wave = figure.animations.first
        world.ground = 0
        world.restitution = 0.05
        ragdoll = world.addRagdoll(from: figure, at: Vector3(0, 0.95, 0),
                                   mass: 72, friction: 0.7)
        standUp()
        hangTheCape()
    }

    /// Hang the cape on the figure. The pose it is standing in right now is the
    /// bind pose, so the cloth is built where it belongs and the skeleton's
    /// motion from here on is what carries it.
    func hangTheCape() {
        cape = world.addSoftBody(
            from: Cape.sheet,
            // The sheet is centered on its own origin, so standing the collar at
            // the shoulders puts the body half a cape lower.
            at: Vector3(0, 1.45 - Cape.length / 2, -0.13),
            rotated: .pi / 2, axis: Vector3(1, 0, 0),
            mass: 1.2, stiffness: 0.92, bend: 0.01, damping: 0.06,
            friction: 0.4, iterations: 8, vertexRadius: 0.01,
            // Clasped at the neck only. A whole edge pinned is a flag; a cape
            // hangs from a clasp and falls into folds off the shoulders.
            pinned: { $0.z < Cape.collar && abs($0.x) < 0.2 },
            skinnedTo: figure,
            // The whole cape hangs off the chest. The arms would carry it too,
            // and a cape that flies up with a waving hand is not a cape.
            carriedBy: { _ in "chest" },
            // Free of the skin, except that it may not be pushed into the
            // back it hangs on.
            sway: nil,
            backStop: 0.05,
            maxStretch: 1.02)
    }

    override func draw() {
        background(Color(hex: 0x0E141C))
        environment(.sky(turbidity: 3.2, sunElevation: 0.7))
        lightingPreset(.standard)
        castShadows()
        // From behind and a little to the side: a cape is a thing you see the
        // back of.
        camera(.perspective(eye: Vector3(2.6, 1.5, -4.1),
                            target: Vector3(0, 0.9, 0), fieldOfView: .pi / 4))

        cape.swayScale = looseness
        if standing {
            if let wave {
                target.apply(wave, at: time.truncatingRemainder(dividingBy: wave.duration))
            }
            ragdoll.drive(toward: target, strength: 140)
            // The hips are kinematic while the figure is standing, so walking
            // it is a matter of saying where they are. Everything else is the
            // solver's, and the cape only ever sees the skeleton that results.
            ragdoll.limbs[0].body.position = Vector3(sin(time * 1.7) * stride, 0.95, 0)
        }
        dragBodies(in: world)

        // The order is the whole contract: pose the figure, hand the cape the
        // pose, then step. A cape told after the step is a frame behind.
        figure.apply(ragdoll)
        cape.follow(figure)
        world.advance(by: deltaTime)
        figure.apply(ragdoll)

        drawFloor()
        fill(.white)   // white leaves the file's own material untouched
        drawScene(figure)

        material(.dielectric(roughness: 0.7))
        fill(capeColor)
        drawSoftBody(cape)

        drawCaption("\(standing ? "powered" : "limp")"
            + "\(cape.followsSkin ? "" : " · loose")"
            + "      space to switch, F to cut the leash, drag a limb")
    }

    func standUp() {
        if let wave { target.apply(wave, at: 0) }
        ragdoll.pose(from: target)
        standing = true
        // Nothing above the root drives it, so a figure with everything
        // dynamic topples however firmly it holds its shape.
        ragdoll.limbs[0].body.kind = .kinematic
        figure.apply(ragdoll)
        cape?.snap(to: figure)
    }

    func goLimp() {
        standing = false
        ragdoll.limbs[0].body.kind = .dynamic
        ragdoll.goLimp()
    }

    override func keyPressed() {
        switch key {
        case " ": standing ? goLimp() : standUp()
        case "r", "R": standUp()
        case "f", "F": cape.followsSkin.toggle()
        default: break
        }
    }

    func drawFloor() {
        material(.dielectric(roughness: 0.95))
        fill(Color(hex: 0x28303E))
        drawGround(size: 14, thickness: 0.3)
    }
}
