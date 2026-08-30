import Ollin
import Foundation

// A raymarched 3D SDF field. Spheres melt together by smooth-union (their colors
// blending through the seam), one orbits, and a sphere is carved out of the top; the
// whole thing sphere-traced as a single surface, lit by the scene's light. A glossy
// bar skewers the blob to show that the marched surface and the rasterized mesh share
// one depth buffer: the bar's near half occludes the blob, its far half is occluded
// by it. It orbits on its own.
@main
final class RaymarchedSDF: Sketch {
    override func draw() {
        raymarchResolution(0.35)   // a heavier metaball field, so traced below the default half-res
        background(Color(hex: 0x0e1116))
        let t = time

        cameraShowcase(.turntable(period: .tau / 0.35), target: .zero, radius: 5.5,
                    elevation: 0.45, fieldOfView: .pi / 4, near: 0.1, far: 40)

        // A key light from the upper left plus a soft ambient, so the blob reads as form.
        directionalLight(.white, direction: Vector3(-0.6, 0.7, 0.5),
                         intensity: 1.1, softness: 0.3)
        ambientLight(Color(white: 0.16))

        // A glossy bar that interpenetrates the blob: the depth-compositing proof.
        withState {
            material(.glossy)
            fill(Color(hex: 0xf2c14e))
            rotateY(t * 0.5)
            rotateZ(0.3)
            drawBox(width: 4.4, height: 0.45, depth: 0.45)
        }

        // The marched field: a metaball of three spheres melting together (one orbiting),
        // with a sphere carved out of the top. Each leaf carries its own color, so the
        // smooth-union seams blend cyan → magenta → lime.
        material(.jade)
        let orbit = Vector3(cos(t) * 1.3, sin(t * 1.3) * 0.5, sin(t) * 1.3)
        let blob = SDF3D.sphere(radius: 1.05).colored(Color(hex: 0x39d0ff))
            .smoothUnion(SDF3D.sphere(radius: 0.85).at(orbit).colored(Color(hex: 0xff4f97)), k: 0.7)
            .smoothUnion(SDF3D.sphere(radius: 0.6).at(-1.1, 0.7, 0.4)
                .colored(Color(hex: 0xb6ff5a)), k: 0.5)
            .smoothSubtract(SDF3D.sphere(radius: 0.7).at(0.2, 1.15, 0), k: 0.25)
        drawSDF3D(blob)
    }
}
