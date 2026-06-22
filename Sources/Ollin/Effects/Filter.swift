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
}

/// Bake a 256-step LUT of linear, straight-alpha samples from a `0…1 → Color`
/// ramp, the form `gradientMap` uploads as a small lookup texture.
func bakeLUT(_ color: (Double) -> Color) -> [SIMD4<Float>] {
    (0..<256).map { i in color(Double(i) / 255).linearRGBA }
}
