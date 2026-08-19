// figure: frame=170
//
// Guide listing (Chapter 19): two figures striding the same path with the same
// cape hung on each, one carried by the skeleton under the skin and one only
// pinned to the world. Caught mid-stride: the carried cape has gone with its
// figure and swung out behind it, the pinned one is still hanging where it was
// hung while its figure walks out from under it. No random anywhere, so both
// replay identically.
import Ollin
import OllinPhysics

final class Cape: Sketch {
    let world = World3D()
    /// The two drawn figures, posed from their own ragdolls each frame.
    var carriedFigure: Scene!
    var pinnedFigure: Scene!
    /// The pose both are driven toward, so they stride rather than collapse.
    var rest: Scene!
    var carriedDoll: Ragdoll3D!
    var pinnedDoll: Ragdoll3D!
    var carried: SoftBody3D!
    var pinned: SoftBody3D!

    static let length = 1.15
    static let sheet = Mesh.plane(width: 0.8, depth: length, segments: 16)
    static let collar = -length / 2 + 0.02

    override func setup() {
        rest = loadScene("Examples/3D/Physics/Ragdoll/figure.gltf")
        carriedFigure = rest
        pinnedFigure = rest
        world.ground = 0
        world.bounce = 0.05

        carriedDoll = stand(at: -1.0)
        pinnedDoll = stand(at: 1.0)
        carriedFigure.apply(carriedDoll)
        pinnedFigure.apply(pinnedDoll)

        // The only difference between the two: one names a joint to be carried
        // by, the other names none, so its collar is pinned to the world.
        carried = hang(at: -1.0, on: carriedFigure)
        pinned = hang(at: 1.0, on: nil)
    }

    /// A figure standing at `x`, held up by a kinematic root so it can be
    /// walked rather than left to topple.
    func stand(at x: Double) -> Ragdoll3D {
        let doll = world.addRagdoll(from: rest, at: Vector3(x, 0.95, 0),
                                    mass: 72, friction: 0.7)!
        doll.limbs[0].body.kind = .kinematic
        return doll
    }

    func hang(at x: Double, on figure: Scene?) -> SoftBody3D {
        world.addSoftBody(
            from: Cape.sheet, at: Vector3(x, 1.45 - Cape.length / 2, -0.13),
            rotation: .pi / 2, axis: Vector3(1, 0, 0),
            mass: 1.0, stiffness: 0.92, bend: 0.01, damping: 0.06,
            iterations: 8, vertexRadius: 0.01,
            pinned: { $0.z < Cape.collar && abs($0.x) < 0.2 },
            skinnedTo: figure,
            carriedBy: figure == nil ? nil : { _ in "chest" },
            backStop: 0.05, maxStretch: 1.02)!
    }

    override func draw() {
        background(Color(hex: 0x101620))
        environment(.sky(turbidity: 3.0, sunElevation: 0.75))
        lightingPreset(.standard)
        castShadows()
        // From behind: a cape is a thing you see the back of.
        camera(.perspective(eye: Vector3(0.5, 1.6, -4.6),
                            target: Vector3(0, 0.95, 0), fieldOfView: .pi / 3.2))

        let step = sin(Double(frameCount) / 60 * 1.7) * 0.65
        carriedDoll.drive(toward: rest, strength: 160)
        pinnedDoll.drive(toward: rest, strength: 160)
        carriedDoll.limbs[0].body.position = Vector3(-1.0 + step, 0.95, 0)
        pinnedDoll.limbs[0].body.position = Vector3(1.0 + step, 0.95, 0)

        carriedFigure.apply(carriedDoll)
        pinnedFigure.apply(pinnedDoll)
        carried.follow(carriedFigure)
        world.step(dt: 1.0 / 60)
        carriedFigure.apply(carriedDoll)
        pinnedFigure.apply(pinnedDoll)

        material(.dielectric(roughness: 0.95))
        fill(Color(hex: 0x2A3140))
        withState {
            translate(0, -0.15, 0)
            drawBox(width: 14, height: 0.3, depth: 14)
        }

        material(.dielectric(roughness: 0.6))
        fill(.white)
        drawScene(carriedFigure)
        drawScene(pinnedFigure)

        material(.dielectric(roughness: 0.7))
        fill(Color(hex: 0x9E2B3A))
        drawSoftBody(carried)
        fill(Color(hex: 0x3F6E8C))
        drawSoftBody(pinned)
    }
}
