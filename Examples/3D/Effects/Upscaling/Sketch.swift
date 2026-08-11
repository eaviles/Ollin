import Ollin

/// Temporal upscaling: render small, reconstruct full-size, keep the frame rate.
///
/// The scene is deliberately expensive per pixel: a mirror floor with ray-traced
/// reflections, cast shadows, an environment, and thin bright rods that punish
/// fixed-position anti-aliasing. With `temporalUpscaling()` on, the live window
/// renders the whole frame at a fraction of the canvas and the platform's
/// temporal scaler reconstructs the full-size image from the sub-pixel-jittered
/// history, so per-pixel cost drops by the square of the fraction while edges
/// stay temporally anti-aliased. The tier picks how small: `.performance`
/// renders at half size, `.default` at two-thirds, `.detail` at three-quarters.
/// Watch the FPS readout in the inspector while toggling. Exports never
/// upscale: a headless frame renders at full resolution with the deterministic
/// supersample, so what you keep is always full quality; the live window is the
/// fast preview of it.
@main
final class Upscaling: Sketch {

    @Param(icon: "arrow.down.right.and.arrow.up.left.rectangle", group: "Image")
    var upscaling = true

    @Param(style: .segmented, icon: "dial.medium", group: "Image")
    var tier = RenderQuality.default

    override func draw() {
        background(Color(white: 0.03))

        cameraShowcase(.sway(period: 36), target: Vector3(0, 1.0, 0),
                       radius: 12.5, elevation: 0.26, fieldOfView: .pi / 3.4)

        environment(.sky(turbidity: 3, sunElevation: 0.5))
        directionalLight(.white, direction: Vector3(-0.5, -0.85, -0.35), intensity: 0.9)
        castShadows()
        rayTracedReflections()
        if upscaling { temporalUpscaling(tier) }

        // The mirror floor: every pixel of it traces the scene, so its cost
        // falls with the render resolution and the toggle shows in the FPS.
        withState {
            fill(Color(white: 0.85))
            material(.metal(roughness: 0.06))
            translate(0, -0.09, 0)
            drawBox(width: 15, height: 0.18, depth: 15)
        }

        // A ring of glossy columns and spheres for the mirror to work on.
        for i in 0..<10 {
            let a = Double(i) / 10 * .tau
            withState {
                translate(cos(a) * 4.6, 0, sin(a) * 4.6)
                if i % 2 == 0 {
                    fill(Color(hue: Double(i) / 10, saturation: 0.55, brightness: 0.85))
                    material(.dielectric(roughness: 0.25))
                    translate(0, 1.15, 0)
                    drawCylinder(radius: 0.28, height: 2.3)
                } else {
                    fill(Color(white: 0.9))
                    material(.metal(roughness: 0.12))
                    translate(0, 0.62, 0)
                    drawSphere(radius: 0.62)
                }
            }
        }

        // Thin tilted rods: the temporal-AA showcase, kept sharp by the scaler's
        // jittered history even while it renders far fewer pixels than the canvas.
        fill(Color(white: 0.94))
        for i in 0..<7 {
            withState {
                translate(0, 0.5 + Double(i) * 0.35, -2.2)
                rotate(0.035 + Double(i) * 0.012, axis: .unitZ)
                drawBox(width: 6.0, height: 0.03, depth: 0.05)
            }
        }

        // A world-space mover: `withMotion` hands the scaler its exact screen
        // motion, so the bar reconstructs cleanly mid-flight instead of leaning
        // on the depth-reprojection fallback.
        withMotion("orbiter") {
            withState {
                fill(Color(hex: 0xE0B341))
                material(.metal(roughness: 0.2))
                rotate(time * 0.4, axis: .unitY)
                translate(3.1, 1.9, 0)
                rotate(0.1, axis: .unitZ)
                drawBox(width: 1.7, height: 0.05, depth: 0.08)
            }
        }

        drawCaption("temporalUpscaling(\(upscaling ? String(describing: tier) : "off")) - toggle it in the inspector")
    }
}
