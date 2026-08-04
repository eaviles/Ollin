// figure: frame=96
//
// Guide listing (Chapter 17): the same skinned figure dropped twice from the
// same height, one with its joints powered toward the pose it started in and
// one with them switched off. Caught a moment after landing: the powered one is
// still standing in its own shape, the limp one is a heap. No random anywhere,
// so both falls replay identically.
import Ollin
import OllinPhysics

final class Ragdolls: Sketch {
    let world = World3D()
    /// The pose both figures were built in, held aside as the thing the
    /// powered one is driven toward.
    var rest: Scene!
    /// The two drawn copies, posed from their own ragdolls each frame.
    var limp: Scene!
    var held: Scene!
    var limpDoll: Ragdoll3D!
    var heldDoll: Ragdoll3D!

    override func setup() {
        rest = loadScene("Examples/3D/Physics/Ragdoll/figure.gltf")
        limp = rest
        held = rest
        world.ground = 0
        world.bounce = 0.05
        limpDoll = world.addRagdoll(from: rest, at: Vector3(-0.85, 1.35, 0),
                                    mass: 72, friction: 0.7)
        heldDoll = world.addRagdoll(from: rest, at: Vector3(0.85, 1.35, 0),
                                    mass: 72, friction: 0.7)
    }

    override func draw() {
        background(Color(hex: 0x101620))
        environment(.sky(turbidity: 3.0, sunElevation: 0.75))
        lightingPreset(.standard)
        castShadows()
        camera(.perspective(eye: Vector3(0.4, 1.9, 4.6),
                            target: Vector3(0, 0.7, 0), fieldOfView: .pi / 4))

        // The one difference between the two falls.
        heldDoll.drive(toward: rest, strength: 260)

        world.step(dt: 1.0 / 60)
        limp.apply(limpDoll)
        held.apply(heldDoll)

        material(.dielectric(roughness: 0.95))
        fill(Color(hex: 0x2A3140))
        withState {
            translate(0, -0.15, 0)
            drawBox(width: 12, height: 0.3, depth: 12)
        }

        material(.dielectric(roughness: 0.6))
        fill(.white)
        drawScene(limp)
        drawScene(held)

        // Name them, flat on the canvas, so the pair reads on its own.
        noDepth()
        fill(Color(hex: 0xE8EDF5))
        textSize(30)
        textAlign(.center, .middle)
        drawText("limp", width * 0.44, height * 0.9)
        drawText("powered", width * 0.72, height * 0.9)
    }
}
