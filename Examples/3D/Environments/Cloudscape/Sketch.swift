import Ollin

/// A raymarched cloudscape over the procedural sky.
///
/// `.sky(...).clouds(...)` bakes real volumetric clouds into the environment
/// itself, so everything agrees about the weather: the sky behind the scene,
/// the light falling on every surface, and the reflections in the chrome ball
/// all show the same formations. Slide `coverage` from a few fair-weather
/// puffs to a gray lid and watch the whole scene's light dim and diffuse with
/// it; `tallness` trades flat sheets for building towers, `bigness` sets how
/// broad the weather systems run, and the wind drifts the formations on the
/// sketch's clock, deterministically, so an export plays the same sky. A
/// still sky bakes once and costs nothing per frame; the drifting one
/// re-bakes as it moves.
@main
final class Cloudscape: Sketch {

    @Param(0 ... 1, icon: "cloud", group: "Weather") var coverage = 0.45
    @Param(0.2 ... 2.5, icon: "cloud.fill", group: "Weather") var density = 1.0
    @Param(0.25 ... 3, icon: "arrow.up.left.and.arrow.down.right", group: "Weather") var bigness = 1.0
    @Param(0 ... 1, icon: "arrow.up.to.line", group: "Weather") var tallness = 0.6
    @Param(icon: "wind", group: "Weather") var drifting = true
    @Param(0.06 ... 1.35, icon: "sun.max", group: "Sun") var sunHeight = 0.5
    @Param(0 ... 6.28, icon: "location.north.line", group: "Sun") var sunAround = 0.7

    private var wind = 0.0

    override func draw() {
        background(.black)
        toneMap(.aces)
        if drifting { wind += deltaTime * 0.6 }

        cameraShowcase(.sway(amplitude: 0.35, period: .tau / 0.05),
                       target: Vector3(0, 1.6, 0), radius: 9,
                       elevation: 0.14, fieldOfView: .pi / 3.1)

        environment(.sky(turbidity: 2.4, sunElevation: sunHeight)
            .rotated(sunAround)
            .clouds(coverage: coverage, density: density, scale: bigness,
                    tallness: tallness, phase: wind))

        // A chrome ball and a matte plain: one shows the weather as a picture,
        // the other as light.
        fill(.white)
        material(.polishedMetal)
        drawSphere(radius: 1.3)
        material(.matte)
        fill(Color(white: 0.55))
        withState { translate(0, -1.7, 0); drawBox(width: 40, height: 0.4, depth: 40) }
    }
}
