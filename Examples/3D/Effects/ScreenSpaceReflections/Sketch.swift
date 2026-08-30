import Ollin

/// Screen-space reflections turning a 3D scene's own surfaces into mirrors.
///
/// Image-based lighting lets a metal reflect its *environment*; screen-space
/// reflections let surfaces reflect the *scene around them*. Here both run at once:
/// a ring of reflective-metal spheres (each a different finish: polished, brushed,
/// gold, copper) reflect a studio `environment`, and the dark glossy floor reflects
/// *them* by screen-space reflection. Draw a 3D scene into a render target, which
/// captures depth, and feed `scene.depth` to `.screenSpaceReflections`:
///
/// ```swift
/// let scene = makeRenderTarget()
/// withTarget(scene) { camera(...); material(.polishedMetal); drawSphere(...) }   // depth captured
/// let ssr = scene.combined(with: scene.depth, .screenSpaceReflections())
/// drawImage(ssr.image, 0, 0)
/// ```
///
/// A metal needs an environment to reflect (without one it reads dark), so a studio
/// `environment` lights them; `.lightingOnly()` keeps the background dark so the floor's
/// reflections stand out. The camera orbits on its own, and the mouse takes it over
/// (drag to orbit, scroll to dolly). **Hold the space bar** to drop the screen-space
/// reflections and compare: the metals keep their environment reflections, but their
/// mirror images on the floor vanish. `fresnel` concentrates the floor reflection at
/// grazing angles; `roughness` blurs it for a glossy (rather than mirror) floor.
@main
final class ScreenSpaceReflections: Sketch {

    override func draw() {
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(Color(hex: 0x20242c))
            cameraShowcase(.autoOrbit(period: .tau / 0.12),
                           target: Vector3(0, 0.9, 0), radius: 9, elevation: 0.5,
                           fieldOfView: .pi / 4, near: 2, far: 20)
            // A bright studio environment: it lights and reflects in the metals, and its softly
            // blurred backdrop fills the scene with light (a bright scene reveals the reflections
            // a dark one would hide).
            environment(.studio.intensified(to: 1.15).backgroundBlurred(0.6))
            directionalLight(.white, direction: Vector3(-0.3, -1, -0.2), intensity: 0.85)

            // A light glossy showroom floor: bright, and its reflection comes from SSR.
            withState {
                fill(Color(white: 0.45))
                translate(0, -0.05, 0)
                drawBox(width: 28, height: 0.1, depth: 28)
            }

            // A polished-metal monolith in the middle.
            withState {
                material(.polishedMetal)
                fill(Color(hex: 0xe2e6f0))
                translate(0, 1.2, 0)
                drawBox(width: 1.0, height: 2.4, depth: 1.0)
            }

            // A ring of spheres, each a different reflective metal finish.
            let spheres: [(color: Color, finish: Material)] = [
                (Color(hex: 0xf2f3f7), .polishedMetal),           // chrome
                (Color(hex: 0xffcc4a), .metal(roughness: 0.12)),  // gold
                (Color(hex: 0x5a86d8), .brushedMetal),            // brushed steel-blue
                (Color(hex: 0xd07a3a), .metal(roughness: 0.1)),   // copper
                (Color(hex: 0x37c879), .polishedMetal),           // emerald
                (Color(hex: 0xc54baa), .metal(roughness: 0.22)),  // satin magenta
            ]
            for (i, s) in spheres.enumerated() {
                let a = Double(i) / Double(spheres.count) * .tau
                withState {
                    material(s.finish)
                    fill(s.color)
                    translate(cos(a) * 4.2, 1.0, sin(a) * 4.2)
                    drawSphere(radius: 1.0)
                }
            }
        }

        // Hold the space bar to see the raw scene; release for the reflected one.
        if isKeyDown(" ") {
            drawImage(scene.image, 0, 0)
            drawCaption("Screen-space reflections: OFF (release space to compare)")
        } else {
            let ssr = scene.combined(with: scene.depth,
                                     .screenSpaceReflections(amount: 0.9, roughness: 0.2, fresnel: 0.5))
            drawImage(ssr.image, 0, 0)
            drawCaption("Screen-space reflections: ON (hold space to compare)")
        }
    }
}
