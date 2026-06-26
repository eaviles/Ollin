import Ollin

/// Screen-space reflections turning a 3D scene's own surfaces into mirrors.
///
/// Image-based lighting lets a metal reflect its *environment*; screen-space
/// reflections let surfaces reflect the *scene around them*: bright objects above a
/// glossy floor appear inverted on it, a polished tabletop catches what sits on it,
/// wet asphalt doubles the lights. It reads only what's already on screen, so it
/// costs nothing extra to author: draw a 3D scene into a render target, which
/// captures depth, and feed `scene.depth` to `.screenSpaceReflections` as the aux.
/// View-space position and surface normal come from the depth (a true mesh normal
/// here), the reflection ray is marched through the depth buffer, and the scene
/// colour at the hit is composited back over the surface:
///
/// ```swift
/// let scene = renderTarget()
/// withTarget(scene) { camera(...); drawBox(...) }      // 3D -> depth captured
/// let ssr = scene.combined(with: scene.depth, .screenSpaceReflections())
/// drawImage(ssr.image, 0, 0)
/// ```
///
/// A glossy dark floor is where screen-space reflection shines: a broad flat surface
/// reflects the well-separated objects standing on it as clean mirror images. The
/// camera orbits at a low angle so the floor catches them. **Hold the mouse** to drop
/// the reflections and compare. Only on-screen geometry can reflect, so reflections
/// fade as their rays reach the frame edge; `fresnel` concentrates them at grazing
/// angles (where a wet floor reflects most), and a little `roughness` keeps them
/// glossy rather than a hard mirror.
@main
final class ScreenSpaceReflections: Sketch {

    override func draw() {
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x06080d))
            camera(.orbiting(target: Vector3(0, 0.7, 0), radius: 10,
                             azimuth: time * 0.1, elevation: 0.55,
                             fieldOfView: .pi / 4, near: 2, far: 24))
            ambientLight(Color(white: 0.3))
            directionalLight(.white, direction: Vector3(-0.35, -1, -0.2), intensity: 0.95)

            // The glossy floor: dark, so the reflections stand out against it.
            withState {
                fill(Color(white: 0.05))
                translate(0, -0.05, 0)
                drawBox(width: 40, height: 0.1, depth: 40)
            }

            // A loose scatter of spheres standing on the floor, spaced well apart so each
            // reads its own clean mirror image (curved surfaces reflecting a close neighbour
            // is where screen-space reflection frays, so they're kept separated). Each tuple
            // is (x, z, hue).
            let spheres: [(x: Double, z: Double, hue: Double)] = [
                (-3.8, 1.5, 0.02), (3.6, 2.0, 0.33), (-1.0, -3.5, 0.58), (5.2, -2.5, 0.85),
            ]
            for s in spheres {
                withState {
                    translate(s.x, 1.0, s.z)
                    fill(Color(hue: s.hue, saturation: 0.75, brightness: 1.0))
                    drawSphere(radius: 1.0)
                }
            }
            // One reflective cube, off to the side: a broad flat face reflects cleanly.
            withState {
                fill(Color(hex: 0xeef0fa))
                translate(-4.5, 0.7, -3.0)
                rotateY(0.6)
                drawBox(width: 1.4, height: 1.4, depth: 1.4)
            }
        }

        // Hold the mouse to see the raw scene; release for the reflected one.
        if mouseIsPressed {
            drawImage(scene.image, 0, 0)
            drawCaption("Screen-space reflections: OFF (release the mouse to compare)")
        } else {
            let ssr = scene.combined(with: scene.depth,
                                     .screenSpaceReflections(intensity: 0.9, roughness: 0.15, fresnel: 0.8))
            drawImage(ssr.image, 0, 0)
            drawCaption("Screen-space reflections: ON (hold the mouse to compare)")
        }
    }
}
