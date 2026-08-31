import Ollin

/// Remote environments: sharper backdrops and whole HDRIs fetched from the web.
///
/// The built-in environments ship at 1K, for instant, offline use. Two calls reach past
/// that, and pressing any key switches this scene between them:
///
/// - `highResolution(_:)` fetches a sharper 2K / 4K / 8K version of a bundled
///   environment on the first run and caches it (the bundled 1K shows meanwhile, then
///   it swaps in once the download lands). Only the *backdrop* gets sharper (the
///   lighting and the reflections are the same), so it's purely for a crisp background
///   behind the subjects, without bloating the framework with large assets.
/// - `Environment.hdri(downloadURL:)` downloads any equirectangular HDRI (`.exr` /
///   `.hdr`) from a URL on the first run and caches it the same way, so a sketch can
///   light itself with any HDRI on the web (here `golden_gate_hills` from Poly Haven,
///   CC0). The scene is unlit until the download lands; the `placeholder:` shows a
///   bundled built-in (the studio) meanwhile, then it swaps in.
///
/// Both cache at `~/Library/Caches/Ollin/Environments/`, overridable with the
/// `OLLIN_ENVIRONMENT_CACHE` environment variable.
@main
final class RemoteEnvironment: Sketch {

    /// Press any key to switch between the high-resolution built-in and the URL HDRI.
    var showsURLEnvironment = false

    // A CC0 Poly Haven HDRI at 4K (downloaded once, ~50 MB, cached). Swap "4k" for "2k"/"8k"
    // in the path for a smaller/larger backdrop.
    let hdriURL = "https://dl.polyhaven.org/file/ph-assets/HDRIs/exr/4k/golden_gate_hills_4k.exr"

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

        if showsURLEnvironment {
            environment(.hdri(downloadURL: hdriURL, placeholder: "studio").rotated(time * 0.05))
        } else {
            // A 4K Venice sunset, downloaded once and cached. The bundled 1K shows until it arrives.
            environment(.sunset.highResolution(.fourK).rotated(time * 0.05))
        }

        for ball in balls {
            withState {
                translate(ball.x, 0, 0)
                fill(ball.fill)
                material(ball.material)
                drawSphere(radius: 0.95)
            }
        }
    }

    override func keyPressed() { showsURLEnvironment.toggle() }
}
