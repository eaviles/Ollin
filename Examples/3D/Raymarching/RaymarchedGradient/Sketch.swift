import Ollin
import Foundation

// Gradient paint on a merged raymarched 3D SDF field. A solid `fill` colors each leaf (melting
// at smooth seams); a gradient `fill` paints the whole sphere-traced surface instead, sampled
// by each hit's projected screen position. It's the same canvas-space Gradient every 2D shape
// uses, so it stays fixed to the frame as the blob turns beneath it.
@main
final class RaymarchedGradient: Sketch {
    override func draw() {
        raymarchResolution(0.35)   // a heavier gradient field, so traced below the default half-res
        background(Color(hex: 0x0b1020))
        let t = time

        cameraShowcase(.turntable(period: .tau / 0.3), target: .zero, radius: 6,
                    elevation: 0.25, fieldOfView: .pi / 4, near: 0.1, far: 40)

        directionalLight(.white, direction: Vector3(-0.3, -0.85, -0.45),
                         intensity: 1.2, softness: 0.35)
        ambientLight(Color(white: 0.22))
        material(.glossy)

        // A vertical screen-space gradient across the whole merged blob (warm top, cool bottom).
        fill(.linear(from: Vector2(0, height * 0.18), to: Vector2(0, height * 0.82),
                     [Color(hex: 0xfb923c), Color(hex: 0xec4899), Color(hex: 0x6366f1)]))
        let blob = SDF3D.sphere(radius: 1.05)
            .smoothUnion(SDF3D.sphere(radius: 0.7).at(1.3, 0.4, 0), k: 0.55)
            .smoothUnion(SDF3D.sphere(radius: 0.7).at(-1.1, 0.55, 0.3), k: 0.55)
            .smoothUnion(SDF3D.sphere(radius: 0.6).at(0.1, -1.15, 0), k: 0.55)
        withState { rotateY(t * 0.4); drawSDF3D(blob) }
    }
}
