// figure: frame=0
//
// Guide listing (Chapter 21): the first 3D field. Two spheres melt into one
// body, a third is carved away, and the merged surface is traced through the
// camera and lit like any solid.
import Ollin

final class FirstMarch: Sketch {
    override func draw() {
        background(Color(hex: 0x0D1017))
        camera(.orbiting(target: .zero, radius: 5.2, azimuth: 0.5,
                         elevation: 0.3, fieldOfView: .pi / 4))
        material(.jade)

        let blob = SDF3D.sphere(radius: 1).colored(Color(hex: 0x39D0C8))
            .smoothUnion(SDF3D.sphere(radius: 0.72)
                .at(x: 1.0, y: 0.42, z: 0.1)
                .colored(Color(hex: 0xFF4F97)), k: 0.5)
            .smoothSubtract(SDF3D.sphere(radius: 0.55).at(x: -0.45, y: 0.75, z: 0.5), k: 0.25)

        drawSDF3D(blob)
    }
}
