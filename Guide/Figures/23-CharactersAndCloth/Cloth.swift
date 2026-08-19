// figure: frame=420
//
// Guide listing (Chapter 23): soft bodies. A sheet dropped on a sphere has
// draped over it and hangs to the floor around it, and beside it two balls
// built from the same mesh differ only in the air inside them: the left one is
// empty and has slumped, the right one is firm and still round. No random
// anywhere, so the settle replays identically.
import Ollin
import OllinPhysics

final class Cloth: Sketch {
    let world = World3D()
    var sheet: SoftBody3D!
    var limp: SoftBody3D!
    var firm: SoftBody3D!

    let ballRadius = 0.42

    override func setup() {
        world.ground = 0

        // What the sheet has to find the shape of.
        world.addBody(.sphere(radius: 0.62), at: Vector3(-1.05, 0.62, 0),
                      kind: .static, friction: 0.8)

        sheet = world.addSoftBody(from: .plane(width: 2.2, depth: 2.2, segments: 22),
                                  at: Vector3(-1.05, 2.1, 0),
                                  mass: 0.5, stiffness: 0.95, bend: 0.2,
                                  friction: 0.9, vertexRadius: 0.012)

        // The same mesh twice; the only difference is the air in it.
        let shell = Mesh.icosphere(radius: ballRadius, subdivisions: 4)
        limp = world.addSoftBody(from: shell, at: Vector3(0.75, 1.6, 0.25),
                                 mass: 0.5, bend: 0.12, pressure: 0, friction: 0.6)
        firm = world.addSoftBody(from: shell, at: Vector3(2.0, 1.6, -0.15),
                                 mass: 0.5, bend: 0.12, pressure: 3, friction: 0.6)
    }

    override func draw() {
        background(Color(hex: 0x101620))
        environment(.sky(turbidity: 3.0, sunElevation: 0.75))
        lightingPreset(.standard)
        castShadows()
        camera(.perspective(eye: Vector3(0.05, 1.35, 5.4),
                            target: Vector3(0.05, 0.5, 0), fieldOfView: .pi / 4))

        world.step(dt: 1.0 / 60)

        fill(Color(hex: 0x2A3242))
        material(.dielectric(roughness: 0.92))
        withState {
            translate(0, -0.05, 0)
            drawBox(width: 30, height: 0.1, depth: 30)
        }

        // The sphere under the sheet, drawn from the collider it was built with.
        fill(Color(hex: 0x7A6A55))
        material(.dielectric(roughness: 0.6))
        for body in world.bodies {
            withBody(body) { drawSphere(radius: 0.62) }
        }

        fill(Color(hex: 0xEDE6D8))
        material(.dielectric(roughness: 0.55))
        drawSoftBody(sheet)

        material(.dielectric(roughness: 0.35))
        fill(Color(hex: 0x4E8F8A))
        drawSoftBody(limp)
        fill(Color(hex: 0x3FC0B4))
        drawSoftBody(firm)
    }
}
