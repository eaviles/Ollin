import Ollin

/// Ambient occlusion grounding a 3D scene by its **own** depth buffer.
///
/// Where direct lights cast the hard shadows, ambient occlusion is the soft
/// self-shadowing in between: the darkening in crevices, in the gaps between
/// objects, and where they meet the ground. It's what stops a brightly lit scene
/// from looking like it floats.
///
/// Like the depth-of-field example, the depth comes for free: draw a 3D scene into a
/// render target and it captures depth, exposed as `scene.depth`. Feed that to
/// `.ambientOcclusion` as the aux and the occlusion is computed entirely from the
/// depth: view-space position and surface normal are reconstructed from it, with no
/// separate normal buffer:
///
/// ```swift
/// let scene = renderTarget()
/// withTarget(scene) { camera(...); drawBox(...) }      // 3D → depth captured
/// let ao = scene.combined(with: scene.depth, .ambientOcclusion(radius: 0.6))
/// drawImage(ao.image, 0, 0)
/// ```
///
/// `scene.depth` carries the camera's near/far and field of view, so set them to
/// bracket the scene and `radius` reads in world units. Here a packed grid of blocks
/// of varying heights sits on a ground plane; the camera orbits slowly. **Hold the
/// mouse** to drop the occlusion and compare: the gaps between blocks and the contact
/// with the ground flatten out without it.
@main
final class AmbientOcclusion: Sketch {

    override func draw() {
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x121318))
            // near/far bracket the block field so the reconstruction has depth precision.
            camera(.orbiting(target: Vector3(0, 0.4, 0), radius: 9,
                             azimuth: time * 0.15, elevation: 0.5,
                             fieldOfView: .pi / 4, near: 3, far: 18))
            // Bright ambient so the soft occlusion reads against an evenly lit scene,
            // plus a key light for form.
            ambientLight(Color(white: 0.55))
            directionalLight(.white, direction: Vector3(-0.4, -1, -0.3), intensity: 0.7)

            // The ground.
            withState {
                fill(Color(white: 0.8))
                translate(0, -0.2, 0)
                drawBox(width: 16, height: 0.4, depth: 16)
            }

            // A packed grid of blocks of varying heights, with gaps and contacts everywhere
            // for the occlusion to settle into.
            let n = 6
            let cell = 1.1, box = 0.86
            for ix in 0 ..< n {
                for iz in 0 ..< n {
                    let fx = Double(ix) - Double(n - 1) / 2
                    let fz = Double(iz) - Double(n - 1) / 2
                    let h = 0.5 + 1.6 * noise(Double(ix) * 0.6, Double(iz) * 0.6)
                    withState {
                        translate(fx * cell, h / 2, fz * cell)
                        fill(Color(hue: 0.07 + 0.5 * noise(fx, fz), saturation: 0.4, brightness: 0.95))
                        drawBox(width: box, height: h, depth: box)
                    }
                }
            }
        }

        // Hold the mouse to see the raw scene; release for the occluded one.
        if mouseIsPressed {
            drawImage(scene.image, 0, 0)
            drawCaption("Ambient occlusion: OFF (release the mouse to compare)")
        } else {
            let ao = scene.combined(with: scene.depth,
                                    .ambientOcclusion(radius: 0.5, intensity: 1.0))
            drawImage(ao.image, 0, 0)
            drawCaption("Ambient occlusion: ON (hold the mouse to compare)")
        }
    }
}
