import Ollin

/// The whole `Filter` catalog on one switchable contact sheet: a segmented parameter
/// picks a family (blur, color & tone, stylize & optical, retro, distortion,
/// design), and every tile is `scene.filtered(...)` resolved on the GPU, laid
/// out with `drawSheet`.
///
/// Two scenes feed the tiles. Most families read one detailed picture (flat
/// regions with crisp edges, thin rings and small dots, a wide range of hue and
/// brightness), so what each filter keeps and what it throws away reads at a
/// glance. The design family's alpha readers (`liquidMetal`, `heatmap`,
/// `gemSmoke`) instead read the *shape* drawn into a transparent layer (draw a
/// shape, filter it), so their tiles get a plain heart. The retro glitch and
/// grain ride their `seed`s, and the distortion family animates its warp
/// parameters, so those sheets move.
///
/// Three catalog entries with a dedicated study of their own are left to it:
/// `.relight` (`Effects/Relight`), `.chromaticAberration` (`Effects/Dispersion`),
/// and `.bloom` (`Effects/Layers`).
@main
final class FilterCatalog_Example: Sketch {

    enum Family: String, CaseIterable, ParamOption {
        case blur, color, stylize, retro, distortion, design
    }

    @Param(style: .segmented, icon: "camera.filters") var family = Family.blur

    private let labelFont = OutlineFont.system

    /// The design tiles that read the layer's alpha shape rather than its picture.
    private let alphaReaders: Set<String> = ["liquidMetal", "heatmap", "gemSmoke"]

    private func tiles(_ t: Double) -> [(String, Filter)] {
        switch family {
        case .blur:
            return [
                ("gaussianBlur", .gaussianBlur(radius: 9)),
                ("bilateral", .bilateral(radius: 6, sigma: 0.18)),
                ("motionBlur", .motionBlur(angle: 0.4, distance: 0.06)),
                ("radialBlur", .radialBlur(amount: 0.14)),
            ]
        case .color:
            return [
                ("colorGrade", .colorGrade(contrast: 1.3, saturation: 1.8, hue: 0.05)),
                ("levels", .levels(blackPoint: 0.08, whitePoint: 0.92, gamma: 1.4)),
                ("exposure", .exposure(stops: 0.9)),
                ("temperature +", .temperature(amount: 0.7)),
                ("temperature −", .temperature(amount: -0.7)),
                ("vibrance", .vibrance(amount: 0.9)),
                ("solarize", .solarize(0.5)),
                ("invert", .invert()),
                ("posterize", .posterize(levels: 4)),
                ("threshold", .threshold(0.5, softness: 0.04)),
                ("sepia", .sepia()),
                ("duotone", .duotone(dark: Color(hex: 0x14233B), light: Color(hex: 0xFFD27D))),
                ("gradientMap", .gradientMap(.turbo)),
                ("colorama", .colorama(cycles: 3)),
                ("lumaKey", .lumaKey(low: 0.35)),
            ]
        case .stylize:
            return [
                ("edges", .edges(amount: 2.5)),
                ("sharpen", .sharpen(amount: 2.5)),
                ("emboss", .emboss(amount: 2)),
                ("normalMap", .normalMap(amount: 2)),
                ("toon", .toon(levels: 5)),
                ("oilPaint", .oilPaint(radius: 5)),
                ("brushwork", .brushwork()),
                ("shock", .shock()),
                ("crosshatch", .crosshatch(scale: 95)),
                ("hatching", .hatching(spacing: 4, length: 22)),
                ("xdog", .xdog()),
                ("median", .median()),
                ("contour", .contour(levels: 12)),
                ("vignette", .vignette(amount: 0.85)),
                ("halftone", .halftone(scale: 44)),
                ("cmykHalftone", .cmykHalftone(scale: 56)),
                ("dither", .dither(levels: 4, pixelSize: 6)),
                ("dither duo", .dither(dark: Color(hex: 0x1B1040), light: Color(hex: 0xFFE08A),
                                       pixelSize: 6)),
                ("pixelate", .pixelate(size: 24)),
                ("lineScreen", .lineScreen(scale: 56, angle: .pi / 6)),
            ]
        case .retro:
            return [
                ("scanlines", .scanlines(count: 120, amount: 0.45)),
                ("glitch", .glitch(amount: 0.32, seed: t * 8)),
                ("crt", .crt(curvature: 0.18, scanline: 0.35)),
                ("grain", .grain(amount: 0.25, seed: t)),
            ]
        case .distortion:
            return [
                ("kaleidoscope", .kaleidoscope(segments: 6, angle: t * 0.3)),
                ("swirl", .swirl(angle: 3 * sin(t * 0.6), radius: 0.6)),
                ("bulge", .bulge(amount: 0.6 * sin(t), radius: 0.5)),
                ("wave", .wave(amplitude: 0.03, frequency: 7, phase: t * 2)),
                ("ripple", .ripple(amplitude: 0.025, frequency: 14, phase: t * 3,
                                   center: Vector2(0.5 + 0.22 * cos(t * 0.4),
                                                   0.5 + 0.22 * sin(t * 0.4)))),
                ("mirror", .mirror(vertical: false)),
                ("polar", .polar(amount: 1)),
                ("tile", .tile(count: 3, mirror: true)),
                ("perturb", .perturb(amount: 0.04, scale: 5, phase: t)),
            ]
        case .design:
            return [
                ("liquidMetal", .liquidMetal(phase: t)),
                ("heatmap", .heatmap(phase: t)),
                ("gemSmoke", .gemSmoke(phase: t)),
                ("flutedGlass", .flutedGlass(angle: 0.35)),
                ("water", .water(phase: t)),
                ("paperTexture", .paperTexture()),
            ]
        }
    }

    override func draw() {
        background(Color(white: 0.06))

        let scene = makeScene()
        let heart = family == .design ? makeHeart() : nil

        let sheet: [(String, RenderTarget)] = tiles(time).map { name, filter in
            let source = (alphaReaders.contains(name) ? heart : nil) ?? scene
            return (name, source.filtered(filter))
        }

        textFont(labelFont)
        drawSheet(sheet) { layer, cell in
            drawImage(layer.image, in: cell)
        }
    }

    /// The detailed picture most families read: flat regions and crisp edges for
    /// the blurs and warps, a wide hue and brightness range for the grades, fine
    /// rings and dots for the edge and screen passes, one bright breathing ring
    /// for the retro looks to tear and scan.
    private func makeScene() -> RenderTarget {
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(Color(hex: 0x101826))
            noStroke()
            fill(.linear(from: Vector2(0, 0), to: Vector2(width, height),
                         Ramp([Color(hex: 0x1A2A6C), Color(hex: 0xB21F66), Color(hex: 0xFDBB2D)])))
            drawRect(0, 0, width, height)

            // Bold flat shapes with crisp edges.
            fill(Color(hex: 0xFF5252)); drawCircle(width * 0.32, height * 0.36, 150)
            fill(Color(hex: 0x40C4FF)); drawRect(width * 0.52, height * 0.48, width * 0.30, height * 0.28)
            fill(Color(hex: 0xFFD740)); drawTriangle(width * 0.30, height * 0.80,
                                                     width * 0.16, height * 0.58,
                                                     width * 0.46, height * 0.58)

            // A slow orbit of hue circles, so every grade has color to bite on.
            for i in 0 ..< 6 {
                let t = time * 0.25 + Double(i) * .tau / 6
                fill(Color(hue: Double(i) / 6, saturation: 0.8, brightness: 0.95))
                drawCircle(width * 0.5 + cos(t) * width * 0.28,
                           height * 0.5 + sin(t * 1.3) * height * 0.28, 130)
            }

            // Fine high-frequency detail: thin rings and a rim of small dots.
            stroke(Color(white: 1, alpha: 0.7)); strokeWeight(2); noFill()
            for i in 1 ... 8 { drawCircle(width * 0.5, height * 0.5, Double(i) * 55) }
            noStroke(); fill(.white)
            for i in 0 ..< 80 {
                let a = Double(i) * .tau / 80
                drawCircle(width * 0.5 + cos(a) * width * 0.44,
                           height * 0.5 + sin(a) * height * 0.44, 5)
            }

            // One bright breathing ring, high contrast against the ground.
            stroke(Color(hex: 0x66FFE0)); strokeWeight(9); noFill()
            drawCircle(width * 0.5, height * 0.5, 165 + sin(time) * 26)

            // A faint grid, so each warp's geometry stays easy to read.
            stroke(Color(white: 1, alpha: 0.3)); strokeWeight(3)
            for i in 1 ..< 8 {
                let g = width * Double(i) / 8
                drawLine(g, 0, g, height); drawLine(0, g, width, g)
            }
        }
        return scene
    }

    /// The alpha shape the design family's shape readers filter: a plain white
    /// heart in an otherwise transparent layer.
    private func makeHeart() -> RenderTarget {
        let layer = makeRenderTarget()
        withTarget(layer) {
            noStroke(); fill(.white)
            drawHeart(width / 2, height / 2, width * 0.5)
        }
        return layer
    }
}
