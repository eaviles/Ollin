// figure: frame=0
//
// Guide figure (Chapter 32): a field rebuilt as blocks. The same melt of a sphere,
// a ring, and a cap three times: as the smooth surface it is, then voxelized at two
// block sizes, each block taking the color the field has at its center.
import Ollin

final class Blocks: Sketch {
    override var canvasSize: CanvasSize { .size(1200, 480) }

    override func draw() {
        background(Color(hex: 0x9CC3E0))
        camera(.perspective(eye: Vector3(0, 2.7, 6.6), target: Vector3(0, 0.05, 0),
                            fieldOfView: .pi / 4.2))
        directionalLight(Color(hex: 0xFFF4E0), direction: Vector3(-0.45, -0.8, -0.35), intensity: 1.15)
        ambientLight(Color(hex: 0x6E8AA8))
        material(.matte)

        let melt = SDF3D.sphere(radius: 0.95).colored(Color(hex: 0xE8A24A))
            .smoothUnion(SDF3D.torus(radius: 1.3, tube: 0.28).rotatedX(0.35).colored(Color(hex: 0x3E8FB0)), k: 0.35)
            .smoothUnion(SDF3D.sphere(radius: 0.35).at(0, 1.1, 0).colored(Color(hex: 0xD9534F)), k: 0.25)
        drawSDF3D(melt.rotatedY(0.5).at(-3.6, 0, 0))
        drawSDF3D(melt.voxelized(size: 0.32, seed: 1).rotatedY(0.5).at(0, 0, 0))
        drawSDF3D(melt.voxelized(size: 0.14, seed: 1).rotatedY(0.5).at(3.6, 0, 0))
    }
}
