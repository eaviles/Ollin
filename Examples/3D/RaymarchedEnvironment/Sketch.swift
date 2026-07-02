import Ollin
import Foundation

/// Raymarched fields lit by an environment: the same image-based lighting the meshes get.
///
/// `environment(_:)` alone lights the scene, and the sphere-traced fields take their
/// ambient from it exactly as the rasterized meshes do. A physically-based field gathers
/// the split-sum ambient (the polished-metal melt reflects the sky) while the stylized
/// materials take the diffuse irradiance. The mesh spheres beside each field carry the
/// same material, so field and mesh read as one consistently lit scene.
@main
final class RaymarchedEnvironment: Sketch {
    override func draw() {
        background(Color(hex: 0x0B0C12))
        toneMap(.aces)

        cameraShowcase(.turntable(period: .tau / 0.22), target: Vector3(0, 0.1, 0), radius: 9.5,
                       elevation: 0.16, fieldOfView: .pi / 4.2)

        // The environment is the only light, drifting so the reflections move across
        // the metal and the irradiance shifts on the matte forms.
        environment(.sunset.rotated(time * 0.08))

        let t = time

        // A polished-metal melt: the split-sum ambient fills it with the sky's reflection.
        withState {
            material(.polishedMetal)
            fill(Color(white: 0.95))
            let melt = SDF3D.torus(radius: 1.15, tube: 0.42)
                .smoothUnion(.sphere(radius: 0.62).at(x: 0, y: sin(t * 0.9) * 0.9, z: 0), k: 0.55)
            drawSDF3D(melt.rotatedX(0.5 * .pi).at(x: -2.4, y: 0.4, z: 0))
        }

        // A matte melt in the standard material: the diffuse irradiance is its ambient,
        // so its two colors stay warm under the sunset instead of going black.
        withState {
            material(.matte)
            let melt = SDF3D.sphere(radius: 0.95).colored(Color(hex: 0x3ad6c5))
                .smoothUnion(.octahedron(radius: 1.05)
                    .at(x: 0.9, y: 0.75 + sin(t * 1.3) * 0.25, z: 0)
                    .colored(Color(hex: 0xffb84d)), k: 0.6)
            drawSDF3D(melt.at(x: 2.2, y: 0.2, z: 0))
        }

        // Mesh parity: the same two materials on rasterized spheres, sharing the frame
        // with the fields under the one environment.
        withState {
            translate(-0.1, -1.4, 1.6)
            material(.polishedMetal)
            fill(Color(white: 0.95))
            drawSphere(radius: 0.55)
        }
        withState {
            translate(1.0, -1.5, 1.9)
            material(.matte)
            fill(Color(hex: 0x3ad6c5))
            drawSphere(radius: 0.45)
        }
    }
}
