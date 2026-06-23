import Foundation

/// A texture → texture image operation applied to a `RenderTarget` (or to the
/// whole frame via `postProcess`). A filter reads one off-screen layer and
/// produces a new one, entirely on the GPU, so chaining filters never touches
/// the CPU.
///
/// Filters are plain value descriptors: the renderer reads the parameters and
/// runs the matching GPU work (a tuned Metal Performance Shaders kernel where one
/// fits, an Ollin fragment pass otherwise). Build them with the static factories
/// and hand them to `RenderTarget.filtered(_:)` or `postProcess(_:)`:
///
/// ```swift
/// let layer = renderTarget()
/// withTarget(layer) {
///     background(.black)
///     fill(.orange); drawCircle(width / 2, height / 2, 200)
/// }
/// let glow = layer.filtered(.bloom(threshold: 0.6, intensity: 1.4, radius: 24))
/// drawImage(glow.image, 0, 0)
/// ```
///
/// Filters chain: `layer.filtered(.colorGrade(saturation: 1.4)).filtered(.bloom())`
/// reads as one expression, and `postProcess(_:)` runs one over the whole frame.
public struct Filter: Sendable {

    /// How `pixelate` collapses each block's color: keep it, or read one channel
    /// out as a gray value (which a `tint` can then recolor).
    public enum PixelChannel: Sendable {
        case color, gray, red, green, blue

        /// The shader's mode index (kept in step with `pixelate`'s fragment).
        var rawIndex: Float {
            switch self {
            case .color: return 0
            case .gray:  return 1
            case .red:   return 2
            case .green: return 3
            case .blue:  return 4
            }
        }
    }

    /// The concrete operations the renderer knows how to run. Internal: a sketch
    /// builds a `Filter` through the static factories below, never this directly.
    enum Kind: Sendable {
        /// Separable Gaussian blur of the given pixel radius (≈ the kernel sigma).
        case gaussianBlur(radius: Double)
        /// Bloom: keep the part of the image above `threshold` brightness, blur it by
        /// `radius`, and add it back at `intensity`, a self-contained glowing copy.
        case bloom(threshold: Double, intensity: Double, radius: Double)

        // Color & tone -------------------------------------------------------
        /// Brightness offset, contrast around mid-gray, saturation, hue rotation (turns).
        case colorGrade(brightness: Double, contrast: Double, saturation: Double, hue: Double)
        /// Mix toward the photographic negative by `amount` (1 = full invert).
        case invert(amount: Double)
        /// Quantize each channel to `levels` steps (≥ 2).
        case posterize(levels: Double)
        /// Two-tone cut at `value` brightness, with a `softness`-wide ramp.
        case threshold(value: Double, softness: Double)
        /// Blend toward a warm sepia tone by `amount`.
        case sepia(amount: Double)
        /// Map luminance between two colors, blended over the original by `amount`.
        case duotone(dark: SIMD4<Float>, light: SIMD4<Float>, amount: Double)
        /// Map luminance through a baked 256-step color ramp (linear, straight alpha),
        /// blended over the original by `amount`.
        case gradientMap(lut: [SIMD4<Float>], amount: Double)
        /// Invert the tones above `value` (with a `softness`-wide fold) — the
        /// part-positive, part-negative darkroom solarization.
        case solarize(value: Double, softness: Double)
        /// White balance: `amount` warms (>0) or cools (<0); `tint` shifts toward
        /// magenta (>0) or green (<0).
        case temperature(amount: Double, tint: Double)
        /// Smart saturation: raise the muted colors most, the already-vivid ones least.
        case vibrance(amount: Double)
        /// Multiply linear-light color by `gain` (an exposure stop is `2^stops`).
        case exposure(gain: Double)
        /// Remap tones: lift `blackPoint` to 0 and `whitePoint` to 1, then apply `gamma`.
        case levels(blackPoint: Double, whitePoint: Double, gamma: Double)
        /// Cycle the hue wheel `cycles` times across the luminance range (rainbow banding).
        case colorama(cycles: Double, shift: Double)
        /// Set alpha from a luminance band (`low`…`high`), optionally inverted — a luma key.
        case lumaKey(low: Double, high: Double, invert: Bool)

        // Blur ---------------------------------------------------------------
        /// Directional (motion) blur: average `samples` taps along `angle`, span `distance`.
        case motionBlur(angle: Double, distance: Double)
        /// Zoom (radial) blur: average taps along the ray from center, strength `amount`.
        case radialBlur(amount: Double)
        /// Edge-preserving smoothing: a spatial+range Gaussian (bilateral) of pixel `radius`.
        case bilateral(radius: Double, sigma: Double)

        // Stylize & optical --------------------------------------------------
        /// Sobel edge magnitude, scaled by `intensity`.
        case edges(intensity: Double)
        /// Unsharp mask: add back `amount` of the high-frequency detail.
        case sharpen(amount: Double)
        /// Darken toward the corners; `radius` sets where it starts, `softness` the falloff.
        case vignette(amount: Double, radius: Double, softness: Double)
        /// Split the channels radially out from the center by `amount` (lens fringing).
        case chromaticAberration(amount: Double)
        /// Dot screen: cells `scale` across, rotated by `angle` (radians).
        case halftone(scale: Double, angle: Double)
        /// Ordered (Bayer) dithering down to `levels` steps per channel, the cells
        /// `pixelSize` pixels across.
        case dither(levels: Double, pixelSize: Double)
        /// Add film grain at `amount`; `seed` shifts the noise (animate it per frame).
        case grain(amount: Double, seed: Double)
        /// Mosaic into blocks `size` canvas-pixels across; `channel` and `tint`
        /// optionally read one channel out as gray and recolor it.
        case pixelate(size: Double, channel: PixelChannel, tint: SIMD4<Float>?)
        /// Brightness → bar-width line screen: cells `scale` across, rotated by
        /// `angle` (radians), `softness`-wide edges, painted `foreground` over `background`.
        case lineScreen(scale: Double, softness: Double, angle: Double,
                        foreground: SIMD4<Float>, background: SIMD4<Float>)
        /// Directional relief: the luminance slope along `angle` lit as gray, scaled by `amount`.
        case emboss(amount: Double, angle: Double)
        /// Kuwahara region filter: replace each pixel with its lowest-variance quadrant
        /// mean, flattening detail into oil-paint patches. `radius` is the quadrant size (px).
        case oilPaint(radius: Double)
        /// Pencil cross-hatching: stack rotated line screens at brightness thresholds,
        /// painted `foreground` over `background`. `scale` sets the hatch density.
        case crosshatch(scale: Double, foreground: SIMD4<Float>, background: SIMD4<Float>)
        /// Cel shading: quantize luminance into `levels` bands and ink `edges` (Sobel) over them.
        case toon(levels: Double, edges: Double)
        /// 3×3 median: replace each pixel with the per-channel median of its neighbourhood
        /// (removes speckle while keeping edges).
        case median
        /// Iso-luminance contour lines: dark lines where brightness crosses each of `levels`
        /// steps, drawn over the image at `intensity` (the topographic look).
        case contour(levels: Double, intensity: Double)
        /// CMYK halftone: four rotated dot screens (cyan/magenta/yellow/black at the classic
        /// print angles), dot size tracking each channel — the colour-process look.
        case cmykHalftone(scale: Double)
        /// Height-field normal map: encode the luminance gradient as an RGB surface normal
        /// (feeds `displace` or lighting). `strength` exaggerates the slope.
        case normalMap(strength: Double)
        /// Scanlines: darken alternating horizontal lines (`count` across the height) by `intensity`.
        case scanlines(count: Double, intensity: Double)
        /// Glitch: shove random blocks of rows sideways and split their channels; `seed` reshuffles.
        case glitch(amount: Double, seed: Double)
        /// CRT display: barrel curvature + scanlines + edge vignette + a touch of aberration.
        case crt(curvature: Double, scanline: Double, aberration: Double)

        // Distortion (uv warps) ----------------------------------------------
        /// Mirror the image into `segments` reflected wedges around the center, rotated by `angle`.
        case kaleidoscope(segments: Double, angle: Double)
        /// Twirl: rotate around the center by `angle`, strongest at the center, fading by `radius`.
        case swirl(angle: Double, radius: Double)
        /// Bulge (>0, fisheye) / pinch (<0) within `radius`, magnitude `amount`.
        case bulge(amount: Double, radius: Double)
        /// Sinusoidal displacement: `amplitude` (fraction), `frequency` cycles, `phase`, `vertical` axis.
        case wave(amplitude: Double, frequency: Double, phase: Double, vertical: Bool)
        /// Concentric ripples from the center: `amplitude`, `frequency` rings, `phase`.
        case ripple(amplitude: Double, frequency: Double, phase: Double)
        /// Reflect one half of the image onto the other; `vertical` axis, `flip` chooses the source half.
        case mirror(vertical: Bool, flip: Bool)
        /// Cartesian↔polar warp, blended by `amount` (a tunnel / fold of the image around the center).
        case polar(amount: Double)
        /// Repeat the image in a `count`×`count` grid, optionally mirror-tiled.
        case tile(count: Double, mirror: Bool)
        /// Self-displace by internal fbm noise: organic warp of `amount`, noise `scale`, `phase`.
        case perturb(amount: Double, scale: Double, phase: Double)
    }

    let kind: Kind

    // MARK: Blur & glow

    /// A Gaussian blur. `radius` is the blur extent in pixels (the kernel sigma);
    /// larger is softer. Backed by a hardware Gaussian kernel.
    public static func gaussianBlur(radius: Double) -> Filter {
        Filter(kind: .gaussianBlur(radius: max(0, radius)))
    }

    /// Bloom (glow). Pixels brighter than `threshold` bleed light into their
    /// surroundings: the bright parts are extracted, blurred by `radius`, and added
    /// back at `intensity`. The result is the original image *plus* its glow, ready
    /// to composite (often additively). Brightness is the max color channel (so a
    /// vivid full-brightness mark blooms whatever its hue); `threshold` runs 0…1
    /// over the linear-light frame, so values above 1 (HDR highlights) bloom hardest.
    public static func bloom(threshold: Double = 0.6,
                             intensity: Double = 1.0,
                             radius: Double = 16) -> Filter {
        Filter(kind: .bloom(threshold: max(0, threshold),
                            intensity: max(0, intensity),
                            radius: max(0, radius)))
    }

    // MARK: Color & tone

    /// A color grade in linear light: an additive `brightness` offset, `contrast`
    /// pivoting around mid-gray (1 = unchanged), `saturation` toward or past gray
    /// (0 = grayscale, 1 = unchanged, >1 = punchier), and a `hue` rotation in turns
    /// (0…1 wraps the wheel). All default to no-op, so pass only what you want.
    public static func colorGrade(brightness: Double = 0, contrast: Double = 1,
                                  saturation: Double = 1, hue: Double = 0) -> Filter {
        Filter(kind: .colorGrade(brightness: brightness, contrast: max(0, contrast),
                                 saturation: max(0, saturation), hue: hue))
    }

    /// Invert toward the photographic negative. `amount` 1 is a full invert; lower
    /// values cross-fade with the original.
    public static func invert(amount: Double = 1) -> Filter {
        Filter(kind: .invert(amount: min(max(amount, 0), 1)))
    }

    /// Posterize: quantize each channel to `levels` flat steps for a banded,
    /// screen-printed look. `levels` is clamped to at least 2.
    public static func posterize(levels: Double = 4) -> Filter {
        Filter(kind: .posterize(levels: max(2, levels)))
    }

    /// Threshold to two tones at `value` brightness (0…1). `softness` widens the
    /// transition into a smooth ramp; 0 is a hard cut.
    public static func threshold(_ value: Double = 0.5, softness: Double = 0) -> Filter {
        Filter(kind: .threshold(value: value, softness: max(0, softness)))
    }

    /// A warm sepia tone, blended over the original by `amount` (1 = full sepia).
    public static func sepia(amount: Double = 1) -> Filter {
        Filter(kind: .sepia(amount: min(max(amount, 0), 1)))
    }

    /// Duotone: remap the image's luminance between two colors (shadows toward
    /// `dark`, highlights toward `light`), blended over the original by `amount`.
    public static func duotone(dark: Color, light: Color, amount: Double = 1) -> Filter {
        Filter(kind: .duotone(dark: dark.linearRGBA, light: light.linearRGBA,
                              amount: min(max(amount, 0), 1)))
    }

    /// Gradient map: read the image's luminance and look its color up along `ramp`
    /// (shadows at 0, highlights at 1), blended over the original by `amount`. A
    /// fast way to recolor a grayscale field or restyle a scene through a palette.
    public static func gradientMap(_ ramp: Ramp, amount: Double = 1) -> Filter {
        Filter(kind: .gradientMap(lut: bakeLUT { ramp.color(at: $0) },
                                  amount: min(max(amount, 0), 1)))
    }

    /// Gradient map through a `Colormap` (viridis, magma, turbo, …).
    public static func gradientMap(_ colormap: Colormap, amount: Double = 1) -> Filter {
        Filter(kind: .gradientMap(lut: bakeLUT { colormap.color(at: $0) },
                                  amount: min(max(amount, 0), 1)))
    }

    // MARK: Stylize & optical

    /// Sobel edge detection: bright edges on black, scaled by `intensity`. A quick
    /// outline / comic-ink pass.
    public static func edges(intensity: Double = 1) -> Filter {
        Filter(kind: .edges(intensity: max(0, intensity)))
    }

    /// Unsharp sharpen: emphasize local detail by `amount` (0 = unchanged).
    public static func sharpen(amount: Double = 1) -> Filter {
        Filter(kind: .sharpen(amount: max(0, amount)))
    }

    /// Vignette: darken toward the corners. `radius` (0…1) sets where the darkening
    /// begins from center, `softness` how gradually it falls off, `amount` how dark.
    public static func vignette(amount: Double = 0.5, radius: Double = 0.75,
                                softness: Double = 0.45) -> Filter {
        Filter(kind: .vignette(amount: min(max(amount, 0), 1),
                               radius: max(0, radius), softness: max(0.001, softness)))
    }

    /// Chromatic aberration: split the red and blue channels radially out from the
    /// center, like cheap-lens fringing. `amount` is the split in fractions of the canvas.
    public static func chromaticAberration(amount: Double = 0.005) -> Filter {
        Filter(kind: .chromaticAberration(amount: amount))
    }

    /// Halftone dot screen: render the image as a grid of dots whose size tracks
    /// brightness, `scale` cells across, the grid rotated by `angle` (radians).
    public static func halftone(scale: Double = 60, angle: Double = .pi / 5) -> Filter {
        Filter(kind: .halftone(scale: max(1, scale), angle: angle))
    }

    /// Ordered (Bayer 4×4) dithering: quantize to `levels` steps per channel with a
    /// patterned threshold, the retro look that fakes more shades than it has.
    /// `pixelSize` sizes the dither cells in pixels; raise it for chunky blocks (it
    /// also keeps the pattern visible when the layer is later drawn smaller, since a
    /// 1-pixel pattern averages away under minification).
    public static func dither(levels: Double = 2, pixelSize: Double = 1) -> Filter {
        Filter(kind: .dither(levels: max(2, levels), pixelSize: max(1, pixelSize)))
    }

    /// Film grain: add per-pixel noise at `amount`. `seed` shifts the pattern; feed
    /// it `time` or `frameCount` for grain that moves.
    public static func grain(amount: Double = 0.08, seed: Double = 0) -> Filter {
        Filter(kind: .grain(amount: max(0, amount), seed: seed))
    }

    /// Pixelate (mosaic): collapse the image into square blocks `size` canvas-pixels
    /// across. `channel` keeps the full color (default) or reads one channel out as a
    /// gray value; an optional `tint` recolors that gray.
    public static func pixelate(size: Double = 16, channel: PixelChannel = .color,
                                tint: Color? = nil) -> Filter {
        Filter(kind: .pixelate(size: max(1, size), channel: channel, tint: tint?.linearRGBA))
    }

    /// Line screen: the brightness-driven bar effect, each cell painting a centered
    /// bar whose width tracks its brightness, `scale` cells across, rotated by `angle`
    /// (radians), with `softness`-wide bar edges, in `foreground` over `background`.
    public static func lineScreen(scale: Double = 80, softness: Double = 0.5,
                                  angle: Double = 0,
                                  foreground: Color = .black,
                                  background: Color = .white) -> Filter {
        Filter(kind: .lineScreen(scale: max(1, scale), softness: max(0, softness),
                                 angle: angle, foreground: foreground.linearRGBA,
                                 background: background.linearRGBA))
    }

    // MARK: Color & tone (continued)

    /// Solarize (Sabattier): invert the tones above `value` while leaving the shadows,
    /// the part-positive, part-negative darkroom look. `softness` blurs the fold.
    public static func solarize(_ value: Double = 0.5, softness: Double = 0.05) -> Filter {
        Filter(kind: .solarize(value: min(max(value, 0), 1), softness: max(0, softness)))
    }

    /// White balance. `amount` warms (>0, toward orange) or cools (<0, toward blue);
    /// `tint` pushes toward magenta (>0) or green (<0). Both clamp to ±1.
    public static func temperature(amount: Double = 0.3, tint: Double = 0) -> Filter {
        Filter(kind: .temperature(amount: min(max(amount, -1), 1), tint: min(max(tint, -1), 1)))
    }

    /// Vibrance: a smart saturation that lifts the muted colors most and the already-vivid
    /// ones least (so it punches up a flat image without blowing skin tones). Negative dulls.
    public static func vibrance(amount: Double = 0.5) -> Filter {
        Filter(kind: .vibrance(amount: min(max(amount, -1), 2)))
    }

    /// Exposure in `stops` (linear-light): +1 doubles the light, −1 halves it.
    public static func exposure(stops: Double = 0) -> Filter {
        Filter(kind: .exposure(gain: pow(2, stops)))
    }

    /// Levels: pull `blackPoint` down to black and `whitePoint` up to white (both 0…1),
    /// then bend the midtones by `gamma` (>1 darkens, <1 lifts). The photo-tool staple.
    public static func levels(blackPoint: Double = 0, whitePoint: Double = 1,
                              gamma: Double = 1) -> Filter {
        Filter(kind: .levels(blackPoint: min(max(blackPoint, 0), 1),
                             whitePoint: min(max(whitePoint, 0), 1), gamma: max(0.01, gamma)))
    }

    /// Colorama: cycle the hue wheel `cycles` times across the image's luminance, turning a
    /// gradient into rainbow bands. `shift` rotates the whole wheel (animate it to spin).
    public static func colorama(cycles: Double = 1, shift: Double = 0) -> Filter {
        Filter(kind: .colorama(cycles: cycles, shift: shift))
    }

    /// Luma key: make the image transparent outside the `low`…`high` brightness band (so a
    /// dark or light backdrop drops out). `invert` keeps the band and cuts the rest instead.
    public static func lumaKey(low: Double = 0.1, high: Double = 1, invert: Bool = false) -> Filter {
        Filter(kind: .lumaKey(low: min(max(low, 0), 1), high: min(max(high, 0), 1), invert: invert))
    }

    // MARK: Blur (continued)

    /// Directional (motion) blur: smear along `angle` (radians) over `distance` (a fraction
    /// of the layer), the streak of a moving subject.
    public static func motionBlur(angle: Double = 0, distance: Double = 0.04) -> Filter {
        Filter(kind: .motionBlur(angle: angle, distance: max(0, distance)))
    }

    /// Zoom (radial) blur: smear outward from the center by `amount` (a fraction of the
    /// layer), the rushing-toward-you streak.
    public static func radialBlur(amount: Double = 0.1) -> Filter {
        Filter(kind: .radialBlur(amount: max(0, amount)))
    }

    /// Bilateral blur: smooth flat areas while keeping edges sharp (the cartoon/denoise
    /// base). `radius` is the blur extent in pixels, `sigma` how different a neighbour's
    /// color may be before it stops blending (smaller = more edges preserved).
    public static func bilateral(radius: Double = 4, sigma: Double = 0.2) -> Filter {
        Filter(kind: .bilateral(radius: max(1, radius), sigma: max(0.001, sigma)))
    }

    // MARK: Stylize & optical (continued)

    /// Emboss: light the luminance slope along `angle` as a gray relief, like stamped metal.
    /// `amount` scales the relief; flat areas sit at mid-gray.
    public static func emboss(amount: Double = 1, angle: Double = 0) -> Filter {
        Filter(kind: .emboss(amount: amount, angle: angle))
    }

    /// Oil paint (Kuwahara): flatten detail into paint-like patches while keeping edges
    /// crisp. `radius` is the brush size in pixels (bigger = broader strokes, and costlier —
    /// it samples ~4·(radius+1)² texels, so keep it small).
    public static func oilPaint(radius: Double = 4) -> Filter {
        Filter(kind: .oilPaint(radius: min(max(radius, 1), 8)))
    }

    /// Cross-hatch: shade the image with layered diagonal pen strokes that thicken as it
    /// darkens, in `foreground` over `background`. `scale` sets the hatch density.
    public static func crosshatch(scale: Double = 80, foreground: Color = .black,
                                  background: Color = .white) -> Filter {
        Filter(kind: .crosshatch(scale: max(1, scale), foreground: foreground.linearRGBA,
                                 background: background.linearRGBA))
    }

    /// Cel / toon shading: flatten the image into `levels` brightness bands and ink the
    /// edges over them (`edges` scales the outline strength), the cartoon look.
    public static func toon(levels: Double = 4, edges: Double = 1) -> Filter {
        Filter(kind: .toon(levels: max(2, levels), edges: max(0, edges)))
    }

    /// Median: replace each pixel with the median of its 3×3 neighbourhood, knocking out
    /// speckle and stray pixels while leaving edges sharp.
    public static func median() -> Filter { Filter(kind: .median) }

    /// Contour: draw dark iso-brightness lines (a contour every `1/levels` of the range)
    /// over the image at `intensity`, turning tone into a topographic map.
    public static func contour(levels: Double = 10, intensity: Double = 1) -> Filter {
        Filter(kind: .contour(levels: max(1, levels), intensity: min(max(intensity, 0), 1)))
    }

    /// CMYK halftone: separate the image into cyan/magenta/yellow/black and screen each as
    /// rotated dots at the classic print angles. `scale` sets the dot frequency.
    public static func cmykHalftone(scale: Double = 70) -> Filter {
        Filter(kind: .cmykHalftone(scale: max(1, scale)))
    }

    /// Normal map: read the image as a height field and output its surface normal as an RGB
    /// vector (the bluish bump-map look), ready to feed `displace` or a lighting pass.
    /// `strength` exaggerates the slope.
    public static func normalMap(strength: Double = 1) -> Filter {
        Filter(kind: .normalMap(strength: max(0, strength)))
    }

    // MARK: Retro / optical

    /// Scanlines: darken alternating horizontal lines, the CRT look. `count` is how many
    /// lines span the height, `intensity` (0…1) how dark the gaps go.
    public static func scanlines(count: Double = 240, intensity: Double = 0.4) -> Filter {
        Filter(kind: .scanlines(count: max(1, count), intensity: min(max(intensity, 0), 1)))
    }

    /// Glitch: tear random blocks of rows sideways and split their channels, the corrupted-
    /// signal look. `amount` is the max jump (fraction of width); feed `seed` `time`/`frameCount`
    /// so it flickers.
    public static func glitch(amount: Double = 0.1, seed: Double = 0) -> Filter {
        Filter(kind: .glitch(amount: max(0, amount), seed: seed))
    }

    /// CRT: the full old-monitor look in one pass — `curvature` bows the screen, `scanline`
    /// (0…1) darkens the lines, the corners vignette, and `aberration` fringes the edges.
    public static func crt(curvature: Double = 0.15, scanline: Double = 0.3,
                           aberration: Double = 0.004) -> Filter {
        Filter(kind: .crt(curvature: max(0, curvature), scanline: min(max(scanline, 0), 1),
                          aberration: max(0, aberration)))
    }

    // MARK: Distortion

    /// Kaleidoscope: fold the image into `segments` mirrored wedges around the center, the
    /// wheel rotated by `angle` (radians). Coordinates outside the layer mirror-repeat in.
    public static func kaleidoscope(segments: Double = 6, angle: Double = 0) -> Filter {
        Filter(kind: .kaleidoscope(segments: max(1, segments), angle: angle))
    }

    /// Swirl (twirl): wind the image into a vortex — rotate by `angle` (radians) strongest at
    /// the center, easing to none at `radius` (in fractions of the layer).
    public static func swirl(angle: Double = 3, radius: Double = 0.5) -> Filter {
        Filter(kind: .swirl(angle: angle, radius: max(0.001, radius)))
    }

    /// Bulge / pinch: a radial lens within `radius`. `amount` > 0 bulges (fisheye magnifying
    /// the center), < 0 pinches (sucks toward it); the warp eases back to the image at `radius`.
    public static func bulge(amount: Double = 0.5, radius: Double = 0.5) -> Filter {
        Filter(kind: .bulge(amount: max(-0.95, min(amount, 4)), radius: max(0.001, radius)))
    }

    /// Wave: ripple the image sinusoidally. `vertical` false ripples rows side to side, true
    /// ripples columns up and down. `amplitude` is the shift (fraction of the layer),
    /// `frequency` the cycles across it, `phase` slides the wave (animate it).
    public static func wave(amplitude: Double = 0.02, frequency: Double = 8,
                            phase: Double = 0, vertical: Bool = false) -> Filter {
        Filter(kind: .wave(amplitude: max(0, amplitude), frequency: frequency,
                           phase: phase, vertical: vertical))
    }

    /// Ripple: concentric waves spreading from the center, like a drop in water.
    /// `amplitude` is the shift (fraction of the layer), `frequency` the number of rings,
    /// `phase` moves them outward (animate it).
    public static func ripple(amplitude: Double = 0.02, frequency: Double = 12,
                              phase: Double = 0) -> Filter {
        Filter(kind: .ripple(amplitude: max(0, amplitude), frequency: frequency, phase: phase))
    }

    /// Mirror: reflect one half of the image onto the other. `vertical` false mirrors left↔
    /// right, true mirrors top↔bottom; `flip` chooses which half is the source.
    public static func mirror(vertical: Bool = false, flip: Bool = false) -> Filter {
        Filter(kind: .mirror(vertical: vertical, flip: flip))
    }

    /// Polar warp: bend the image around the center by remapping between Cartesian and polar
    /// coordinates, blended by `amount` (1 = full warp), a tunnel / fold effect.
    public static func polar(amount: Double = 1) -> Filter {
        Filter(kind: .polar(amount: min(max(amount, 0), 1)))
    }

    /// Tile: repeat the image in a `count`×`count` grid. `mirror` flips alternate cells so
    /// the tiling is seamless (a mirror-repeat) instead of hard-edged.
    public static func tile(count: Double = 3, mirror: Bool = false) -> Filter {
        Filter(kind: .tile(count: max(1, count), mirror: mirror))
    }

    /// Perturb: warp the image by its own internal fbm noise (no map needed), for a
    /// smoky / heat-haze ripple. `amount` is the displacement (fraction of the layer),
    /// `scale` the noise frequency, `phase` animates it.
    public static func perturb(amount: Double = 0.03, scale: Double = 4, phase: Double = 0) -> Filter {
        Filter(kind: .perturb(amount: max(0, amount), scale: max(0.001, scale), phase: phase))
    }
}

/// Bake a 256-step LUT of linear, straight-alpha samples from a `0…1 → Color`
/// ramp, the form `gradientMap` uploads as a small lookup texture.
func bakeLUT(_ color: (Double) -> Color) -> [SIMD4<Float>] {
    (0..<256).map { i in color(Double(i) / 255).linearRGBA }
}
