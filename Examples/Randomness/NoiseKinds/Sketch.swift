import Ollin

/// The CPU noise kinds past `noise()`, side by side on the same coordinates.
/// Top left: `simplexNoise`, the even-grained cousin of the classic field.
/// Top right: `signedSimplexNoise`, the same field read as -1...1, shown split
/// at zero (warm above, cool below, dark right on the zero line the 0...1
/// reading flattens away). Bottom left: `worley`, cellular distance, with its
/// `feature` reading and `jitter` on knobs. Bottom right: `turbulence`, fbm
/// over folded octaves, the creased billows behind clouds and marble.
///
/// Every panel samples the identical (x, y) under one `noiseSeed`, so the
/// grains compare directly; only the reading changes. The pictures rebuild
/// when a knob moves and are cached between frames.
@main
final class NoiseKinds: Sketch {
    /// The three `WorleyFeature` readings, as a menu the inspector can show.
    enum Feature: String, CaseIterable, ParamOption { case nearest, second, border }

    @Param(0 ... 1, icon: "circle.hexagongrid") var jitter = 1.0
    @Param(icon: "slider.horizontal.3") var feature = Feature.nearest

    let tile = 256          // pixels per panel picture
    let frequency = 5.0     // the shared coordinate scale
    var panels: [Image] = []
    var builtWith: (jitter: Double, feature: Feature)?

    override func setup() {
        noiseSeed(7)
    }

    override func draw() {
        rebuildIfNeeded()
        background(Color(hex: 0x121316))
        textSize(24)
        fill(Color(white: 0.85))
        textAlign(.center)

        let jitterShown = (jitter * 100).rounded() / 100
        let labels = ["simplexNoise", "signedSimplexNoise",
                      "worley(feature: .\(feature.rawValue), jitter: \(jitterShown))",
                      "turbulence"]
        let side = 400.0
        for (i, image) in panels.enumerated() {
            let x = i % 2 == 0 ? 100.0 : 580.0
            let y = i < 2 ? 70.0 : 560.0
            drawImage(image, x, y, side, side)
            drawText(labels[i], x + side / 2, y + side + 32)
        }

        drawCaption("four readings of one seeded field: every panel samples the same (x, y), scaled by \(Int(frequency))")
    }

    /// Rebuild the four pictures when a knob has moved (and once at the start).
    func rebuildIfNeeded() {
        if let built = builtWith, built.jitter == jitter, built.feature == feature { return }
        let worleyFeature: WorleyFeature = switch feature {
        case .nearest: .nearest
        case .second: .second
        case .border: .border
        }
        panels = [
            picture { x, y in
                let g = self.simplexNoise(x, y)
                return (g, g, g)
            },
            picture { x, y in
                let v = self.signedSimplexNoise(x, y)
                return v >= 0 ? (v, 0.72 * v, 0.3 * v) : (0.3 * -v, 0.62 * -v, 0.85 * -v)
            },
            picture { x, y in
                let g = self.worley(x, y, feature: worleyFeature, jitter: self.jitter)
                return (g, g, g)
            },
            picture { x, y in
                let g = self.turbulence(x, y)
                return (g, g, g)
            },
        ]
        builtWith = (jitter, feature)
    }

    /// A square picture from a function of the shared coordinates: the closure
    /// receives the same (x, y) whichever kind it reads.
    func picture(_ shade: (Double, Double) -> (Double, Double, Double)) -> Image {
        var bytes = [UInt8](repeating: 255, count: tile * tile * 4)
        for py in 0 ..< tile {
            for px in 0 ..< tile {
                let x = (Double(px) + 0.5) / Double(tile) * frequency
                let y = (Double(py) + 0.5) / Double(tile) * frequency
                let (r, g, b) = shade(x, y)
                let i = (py * tile + px) * 4
                bytes[i] = byte(r)
                bytes[i + 1] = byte(g)
                bytes[i + 2] = byte(b)
            }
        }
        return Image(width: tile, height: tile, premultipliedRGBA: bytes)!
    }

    func byte(_ v: Double) -> UInt8 { UInt8((clamp(v, 0, 1) * 255).rounded()) }
}
