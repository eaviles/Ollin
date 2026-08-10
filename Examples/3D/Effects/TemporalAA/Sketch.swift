import Ollin

/// Temporal anti-aliasing: edges refined past MSAA by accumulating jittered frames.
///
/// The scene is deliberately hostile to fixed-position anti-aliasing: thin
/// bright rods at shallow tilts, a wire trellis, a glinting sphere. MSAA
/// samples each pixel at the same eight positions every frame, so a
/// near-horizontal edge quantizes into visible steps that crawl as the camera
/// drifts. With `temporalAntialiasing()` on, the renderer nudges the camera's
/// projection by a different sub-pixel offset each frame and folds the frames
/// into a running average, so the same edges settle into clean gradients and
/// the crawling stops; the toggle makes the comparison one keypress. Exports
/// stay deterministic: a headless frame renders the scene several times at
/// fixed offsets and averages them, so a video of this sketch cannot flicker.
@main
final class TemporalAA: Sketch {

    @Param(icon: "sparkles", group: "Image")
    var temporalAA = true

    override func draw() {
        background(Color(white: 0.045))

        cameraShowcase(.sway(period: 40), target: Vector3(0, 1.2, 0),
                       radius: 7, elevation: 0.18, fieldOfView: .pi / 3.6)

        ambientLight(Color(white: 0.10))
        directionalLight(.white, direction: Vector3(-0.4, -0.9, -0.5), intensity: 0.95)
        if temporalAA { temporalAntialiasing() }

        // The trellis: thin bright rods at shallow angles, the worst case for
        // fixed sample positions and the best showcase for the jitter average.
        fill(Color(white: 0.92))
        for i in 0..<9 {
            withState {
                translate(0, 0.25 + Double(i) * 0.28, 0)
                rotate(0.03 + Double(i) * 0.011, axis: .unitZ)
                drawBox(width: 5.4, height: 0.030, depth: 0.045)
            }
        }
        for i in 0..<11 {
            withState {
                translate(-2.5 + Double(i) * 0.5, 1.35, -0.02)
                rotate(0.06, axis: .unitX)
                drawBox(width: 0.030, height: 2.7, depth: 0.045)
            }
        }

        // A glinting sphere: its specular highlight shimmers under motion
        // without the accumulation, and holds steady with it.
        withState {
            fill(Color(hex: 0xC05A3E))
            material(.dielectric(roughness: 0.3))
            translate(1.7, 0.85, 1.0)
            drawSphere(radius: 0.62)
        }

        withState {
            fill(Color(white: 0.30))
            translate(0, -0.06, 0)
            drawBox(width: 13, height: 0.12, depth: 13)
        }

        drawCaption("temporalAntialiasing() \(temporalAA ? "on" : "off") - toggle it in the inspector")
    }
}
