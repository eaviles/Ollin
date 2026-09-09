import Ollin
import OllinSamplePhotos

/// The whole `Filter` catalog on one switchable contact sheet: a segmented parameter
/// picks a family (blur, color & tone, stylize & optical, retro, distortion,
/// design), and every tile is `scene.filtered(...)` resolved on the GPU, laid
/// out with `drawSheet`.
///
/// Two scenes feed the tiles. Most families read one of the bundled sample
/// photographs, a young woman in a lace headdress and an embroidered blouse
/// (fine lace, flat skin, a wide range of hue and brightness), with one bright
/// breathing ring and a faint grid drawn over it so the retro looks have
/// something to tear and every warp's geometry stays easy to read; what each
/// filter keeps and what it throws away then reads at a glance. The design
/// family's alpha readers (`liquidMetal`, `heatmap`, `gemSmoke`) instead read
/// the *shape* drawn into a transparent layer (draw a shape, filter it), so
/// their tiles get a plain heart. The retro glitch and grain ride their
/// `seed`s, and the distortion family animates its warp parameters, so those
/// sheets move.
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
    private var photograph = Image(width: 1, height: 1)

    override func setup() {
        photograph = SamplePhoto.portrait.load()
    }

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
            drawImage(layer.image, in: cell, fit: .cover)
        }
    }

    /// The picture most families read: the photograph, one bright breathing ring
    /// for the retro looks to tear and scan, and a faint grid so each warp's
    /// geometry stays easy to read.
    private func makeScene() -> RenderTarget {
        let scene = makeRenderTarget()
        withTarget(scene) {
            drawImage(photograph, in: canvasRectangle, fit: .cover)

            stroke(Color(hex: 0x66FFE0)); strokeWeight(9); noFill()
            drawCircle(width * 0.5, height * 0.5, 165 + sin(time) * 26)

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
