// figure: frame=0
//
// Guide figure (Chapter 21): the EnvironmentSky scene with `.sky(...)` swapped
// for a bundled photographic HDRI of a sunset. Same camera, same field, same
// material; only the surroundings differ, which is the whole point of the pair.
import Ollin

final class EnvironmentSunset: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        camera(.perspective(eye: Vector3(2.2, 1.9, 5.2), target: Vector3(0, 1.0, 0),
                            fieldOfView: .pi / 4.4))
        environment(.sunset.backgroundBlur(0.2))
        toneMap(.aces, exposure: 1.0)

        material(.matte)
        fill(Color(hex: 0x7A8290))
        drawPlane(width: 40, depth: 40)

        material(.metal(roughness: 0.12))
        drawSDF3D(Self.body)
    }

    static let body = SDF3D.sphere(radius: 0.72).at(x: 0, y: 0.8, z: 0)
        .smoothUnion(SDF3D.ellipsoid(rx: 0.5, ry: 0.34, rz: 0.5)
            .at(x: 0.66, y: 0.46, z: 0.2), k: 0.42)
        .smoothUnion(SDF3D.sphere(radius: 0.38).at(x: -0.34, y: 1.42, z: 0.16), k: 0.44)
        .colored(Color(hex: 0xD8DCE2))
}
