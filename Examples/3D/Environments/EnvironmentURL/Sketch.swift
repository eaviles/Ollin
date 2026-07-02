import Ollin

/// An environment loaded from a URL.
///
/// `Environment.hdri(downloadURL:)` downloads any equirectangular HDRI (`.exr` / `.hdr`) from
/// a URL on the first run and caches it, the same way `highRes(_:)` fetches the built-ins. So
/// a sketch can light itself with any HDRI on the web (here `golden_gate_hills` from Poly
/// Haven, CC0). The scene is unlit until the download lands; the `placeholder:` shows a
/// bundled built-in (the studio) meanwhile, then it swaps in.
///
/// (Cache at `~/Library/Caches/Ollin/Environments/`, overridable with `OLLIN_ENVIRONMENT_CACHE`.)
@main
final class EnvironmentURL: Sketch {

    // A CC0 Poly Haven HDRI at 4K (downloaded once, ~50 MB, cached). Swap "4k" for "2k"/"8k"
    // in the path for a smaller/larger backdrop.
    let hdriURL = "https://dl.polyhaven.org/file/ph-assets/HDRIs/exr/4k/golden_gate_hills_4k.exr"

    override func draw() {
        background(.black)
        toneMap(.aces)
        cameraShowcase(.sway(amplitude: 0.4, period: .tau / 0.12), target: .zero, radius: 6.5,
                    elevation: 0.12, fieldOfView: .pi / 4.2)

        environment(.hdri(downloadURL: hdriURL, placeholder: "studio").rotated(time * 0.05))

        let balls: [(Material, Color, Double)] = [
            (.polishedMetal,             .white,                                            -2.3),
            (.metal(roughness: 0.3),     Color(hue: 0.09, saturation: 0.45, brightness: 0.95), 0),
            (.dielectric(roughness: 0.4), Color(hue: 0.58, saturation: 0.6, brightness: 0.9),  2.3),
        ]
        for (material, fill, x) in balls {
            withState { translate(x, 0, 0); self.fill(fill); self.material(material); drawSphere(radius: 0.95) }
        }
    }
}
