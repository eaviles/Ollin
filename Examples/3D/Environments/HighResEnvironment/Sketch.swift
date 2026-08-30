import Ollin

/// A high-resolution environment, downloaded on demand.
///
/// The built-in environments ship at 1K, for instant, offline use. `highResolution(_:)` fetches a
/// sharper 2K / 4K / 8K version from Poly Haven on the first run and caches it (the bundled
/// 1K shows meanwhile, then it swaps in once the download lands). Only the *backdrop* gets
/// sharper (the lighting and the reflections are the same), so it's purely for a crisp
/// background behind the subjects, without bloating the framework with large assets.
///
/// The cache lives at `~/Library/Caches/Ollin/Environments/`, overridable with the
/// `OLLIN_ENVIRONMENT_CACHE` environment variable.
@main
final class HighResEnvironment: Sketch {

    let balls: [(material: Material, fill: Color, x: Double)] = [
        (.polishedMetal,            .white,                                            -2.3),
        (.metal(roughness: 0.3),    Color(hue: 0.09, saturation: 0.45, brightness: 0.95), 0),
        (.dielectric(roughness: 0.4), Color(hue: 0.58, saturation: 0.6, brightness: 0.9),  2.3),
    ]

    override func draw() {
        background(.black)
        toneMap(.aces)
        cameraShowcase(.sway(amplitude: 0.4, period: .tau / 0.12), target: .zero, radius: 6.5,
                    elevation: 0.12, fieldOfView: .pi / 4.2)

        // A 4K Venice sunset, downloaded once and cached. The bundled 1K shows until it arrives.
        environment(.sunset.highResolution(.fourK).rotated(time * 0.05))

        for ball in balls {
            withState {
                translate(ball.x, 0, 0)
                fill(ball.fill)
                material(ball.material)
                drawSphere(radius: 0.95)
            }
        }
    }
}
