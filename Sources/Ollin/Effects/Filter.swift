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
/// let layer = makeRenderTarget()
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

    /// Which channel of a layer the Fourier transform reads. A transform works
    /// on one signal, and a color layer is three, so the one to transform is
    /// named rather than guessed. `luminance` is the linear-light brightness,
    /// which is what a picture's own structure lives in.
    public enum FourierChannel: Sendable {
        case luminance, red, green, blue, alpha

        /// The shader's channel index (kept in step with `ollin_fft_extract`).
        var rawIndex: Float {
            switch self {
            case .luminance: return 0
            case .red:       return 1
            case .green:     return 2
            case .blue:      return 3
            case .alpha:     return 4
            }
        }
    }

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

    /// How a chromatic-aberration filter pulls the channels apart. The members are
    /// different pictures rather than one look at different strengths: a lens, a
    /// misregistered plate, a fringe that only appears at edges, and a difference in
    /// focus rather than in position. Every one of them hands back the layer unchanged
    /// at `amount: 0`, so the parameter is honest and an A/B costs nothing.
    public enum Dispersion: Sendable, Equatable {
        /// A per-channel scale of the frame about its center: the split grows straight
        /// with the distance from the middle, so straight lines stay straight and the
        /// fringe is exactly radial everywhere. The physically honest form of lateral
        /// color, and the default.
        case magnify
        /// A radial slide whose length you shape: `radius` (0…1, in fractions of the
        /// half-diagonal) is where the fringe starts to show at all, and `falloff` is the
        /// exponent it grows by past there (about 2 reads like glass). Unlike `.magnify`
        /// the slide is no longer proportional to the radius, so a straight line bends a
        /// little, which is what real edge softening looks like. `.lens(radius: 0,
        /// falloff: 1)` is `.magnify` again.
        case lens(radius: Double = 0.25, falloff: Double = 2)
        /// One flat shift for every pixel, at `angle` radians: the middle splits as much
        /// as the corner. This is misregistration rather than optics, the look of a plate
        /// printed a hair off, an anaglyph, or a badly aligned scan.
        case offset(angle: Double = 0)
        /// A fringe only where there is an edge: the split runs along the local
        /// luminance gradient and is scaled by how strong that gradient is, so a flat
        /// region keeps its color. Real color fringing is only visible at high-contrast
        /// edges, so putting it exactly there reads as a lens where a global split reads
        /// as a filter.
        case edges
        /// Longitudinal (axial) color: the channels differ in *focus* rather than in
        /// position, so one end of the spectrum is sharp while the other is soft. A
        /// positive `amount` keeps red sharp, a negative one keeps blue sharp, which is
        /// what turns an out-of-focus highlight green on one side of focus and magenta
        /// on the other. Most of the fast-lens-wide-open look, and it pairs with
        /// `Combine.defocus` rather than replacing it.
        case axial

        /// The shader's mode index (kept in step with `ollin_fx_chromatic`).
        var rawIndex: Float {
            switch self {
            case .lens:    return 0
            case .offset:  return 1
            case .magnify: return 2
            case .edges:   return 3
            case .axial:   return 4
            }
        }

        /// The first shape scalar: a lens's `radius`, an offset's `angle`, else unused.
        var shapeA: Float {
            switch self {
            case .lens(let radius, _): return Float(min(max(radius, 0), 0.999))
            case .offset(let angle):   return Float(angle)
            default:                   return 0
            }
        }

        /// The second shape scalar: a lens's `falloff`, else unused.
        var shapeB: Float {
            if case .lens(_, let falloff) = self { return Float(max(0, falloff)) }
            return 0
        }
    }

    /// Which value in a layer a measured distance field cuts at its threshold: the
    /// coverage a shape was drawn with, its brightness, or one color channel.
    public enum FieldSource: Sendable {
        case alpha, luminance, red, green, blue

        /// The shader's mode index (kept in step with `ollin_field_value`).
        var rawIndex: Float {
            switch self {
            case .alpha:     return 0
            case .luminance: return 1
            case .red:       return 2
            case .green:     return 3
            case .blue:      return 4
            }
        }
    }

    /// The concrete operations the renderer knows how to run. Internal: a sketch
    /// builds a `Filter` through the static factories below, never this directly.
    enum Kind: Sendable {
        /// A user-supplied `Shader` run as a one-input filter (reads the layer with
        /// `sample(info, uv)`).
        case shader(Shader)
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
        /// Show the layer as somebody with the given color vision sees it.
        case colorVision(ColorVision)
        /// Map luminance between two colors, blended over the original by `amount`.
        case duotone(dark: SIMD4<Float>, light: SIMD4<Float>, amount: Double)
        /// Map luminance through a baked 256-step color ramp (linear, straight alpha),
        /// blended over the original by `amount`.
        case gradientMap(lut: [SIMD4<Float>], amount: Double)
        /// Show the layer as a printing condition reproduces it, read from a lattice
        /// baked once per condition (`nil` when its profiles could not be read, which
        /// leaves the layer alone). `warning`, when present, replaces every color the
        /// destination cannot hold.
        case softProof(lut: ProofLUT?, warning: SIMD4<Float>?, amount: Double)
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
        /// Print accumulated light: scale by `exposure`, roll off through the
        /// Reinhard curve, then add `ground` as a display color and write the
        /// result as the display value itself.
        case develop(exposure: Double, ground: SIMD4<Float>)
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
        /// Soften the stair-stepped edges of a layer a fragment shader wrote per
        /// pixel. `threshold` is the contrast an edge needs before the pass touches
        /// it, `quality` how far it may look along one, and `amount` how much of the
        /// result to keep (0 hands the layer back unchanged).
        case antialias(amount: Double, threshold: Double, quality: RenderQuality)
        /// The layer's frequency spectrum: one channel of it transformed, with the
        /// lowest frequency in the middle. The output is complex (red the real part,
        /// green the imaginary one) rather than a picture.
        case fourier(FourierChannel)
        /// A spectrum turned back into a picture, the exact opposite of `fourier`.
        case inverseFourier
        /// A spectrum as something to look at: its magnitude, compressed so the
        /// high frequencies are visible beside the low ones.
        case spectrum(gain: Double)
        /// Sobel edge magnitude, scaled by `intensity`.
        case edges(intensity: Double)
        /// Unsharp mask: add back `amount` of the high-frequency detail.
        case sharpen(amount: Double)
        /// Darken toward the corners; `radius` sets where it starts, `softness` the falloff.
        case vignette(amount: Double, radius: Double, softness: Double)
        /// Pull the channels apart by `amount`, the way `mode` describes (lens fringing,
        /// misregistration, an edge-only fringe, a difference in focus). `spectral` trades
        /// the three hard ghosts for a continuous smear taken over a `quality`-sized set of
        /// wavelength taps.
        case chromaticAberration(amount: Double, mode: Dispersion, spectral: Bool,
                                 quality: RenderQuality)
        /// Dot screen: cells `scale` across, rotated by `angle` (radians).
        case halftone(scale: Double, angle: Double)
        /// Ordered (Bayer) dithering down to `levels` steps per channel, the cells
        /// `pixelSize` pixels across.
        case dither(levels: Double, pixelSize: Double)
        /// Two-tone ordered dithering: the Bayer pattern mapped onto two chosen
        /// colors, cut by tone with a `bias` shift.
        case ditherDuo(dark: SIMD4<Float>, light: SIMD4<Float>, bias: Double, pixelSize: Double)
        /// Read the layer as a height map and light it with a curated material
        /// finish (the cheap 2D cousin of the 3D materials).
        case relight(finish: RelightFinish, angle: Double, elevation: Double,
                     height: Double, intensity: Double, color: SIMD4<Float>?)
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
        /// 3×3 median: replace each pixel with the per-channel median of its neighborhood
        /// (removes speckle while keeping edges).
        case median
        /// Iso-luminance contour lines: dark lines where brightness crosses each of `levels`
        /// steps, drawn over the image at `intensity` (the topographic look).
        case contour(levels: Double, intensity: Double)
        /// CMYK halftone: four rotated dot screens (cyan/magenta/yellow/black at the classic
        /// print angles), dot size tracking each channel — the color-process look.
        case cmykHalftone(scale: Double)
        /// Height-field normal map: encode the luminance gradient as an RGB surface normal
        /// (feeds `displace` or lighting). `strength` exaggerates the slope.
        case normalMap(strength: Double)
        /// Thin-film rainbow sheen (soap film / oil slick) washed over the content:
        /// `amount` blends it in, `scale` sets the swirl frequency, `bands` how many
        /// color cycles the film runs through, `shift` slides the colors (animate it).
        case iridescence(amount: Double, scale: Double, bands: Double, shift: Double)
        /// Twinkling sparkle flecks over the content: `density` fleck cells across,
        /// `amount` brightness, `size` fleck size, `saturation` 0 white … 1 colored,
        /// `phase` animates the twinkle.
        case glitter(density: Double, amount: Double, size: Double, saturation: Double,
                     phase: Double)
        /// A measured thin film washed over the content: interference worked out per
        /// wavelength for a film `thickness` nanometers deep (swirled by `variation`),
        /// index `ior`, so the colors follow the real film color order.
        case thinFilm(amount: Double, thickness: Double, variation: Double, ior: Double,
                      scale: Double, shift: Double, quality: RenderQuality)
        /// Diffraction grating: bright content repeats into rainbow-split orders along
        /// `angle`, each order's offset growing with wavelength (the grating equation).
        case diffraction(amount: Double, angle: Double, orders: Double, falloff: Double,
                         quality: RenderQuality)
        /// Scanlines: darken alternating horizontal lines (`count` across the height) by `intensity`.
        case scanlines(count: Double, intensity: Double)
        /// Glitch: shove random blocks of rows sideways and split their channels; `seed` reshuffles.
        case glitch(amount: Double, seed: Double)
        /// CRT display: barrel curvature + scanlines + edge vignette + a touch of aberration.
        case crt(curvature: Double, scanline: Double, aberration: Double)

        // Distortion (uv warps) ----------------------------------------------
        /// Mirror the image into `segments` reflected wedges around the center, rotated by `angle`.
        case kaleidoscope(segments: Double, angle: Double)
        /// Twirl: rotate around `center` by `angle`, strongest at the center, fading by `radius`.
        case swirl(angle: Double, radius: Double, center: Vector2)
        /// Bulge (>0, fisheye) / pinch (<0) within `radius` of `center`, magnitude `amount`.
        case bulge(amount: Double, radius: Double, center: Vector2)
        /// Sinusoidal displacement: `amplitude` (fraction), `frequency` cycles, `phase`, `vertical` axis.
        case wave(amplitude: Double, frequency: Double, phase: Double, vertical: Bool)
        /// Concentric ripples from `center`: `amplitude`, `frequency` rings, `phase`.
        case ripple(amplitude: Double, frequency: Double, phase: Double, center: Vector2)
        /// The picture inside itself without end: the ring between `inner` and the layer's
        /// edge repeated at every scale, `twist` copies stepped per turn, slid by `zoom`.
        case droste(inner: Double, twist: Double, zoom: Double, center: Vector2, rotation: Double)
        /// Reflect one half of the image onto the other; `vertical` axis, `flip` chooses the source half.
        case mirror(vertical: Bool, flip: Bool)
        /// Cartesian↔polar warp, blended by `amount` (a tunnel / fold of the image around the center).
        case polar(amount: Double)
        /// Repeat the image in a `count`×`count` grid, optionally mirror-tiled.
        case tile(count: Double, mirror: Bool)
        /// Self-displace by internal fbm noise: organic warp of `amount`, noise `scale`, `phase`.
        case perturb(amount: Double, scale: Double, phase: Double)

        // Design filters ------------------------------------------------------
        /// Ribbed architectural glass: per-flute refraction with boundary
        /// highlights, per-flute shadow ramps, and an optional frost blur.
        case flutedGlass(flutes: Double, shape: FluteShape, profile: FluteProfile,
                         distortion: Double, shift: Double, stretch: Double, blur: Double,
                         edges: Double, highlights: Double, shadows: Double,
                         margins: Insets, angle: Double)
        /// Shallow rippling water over the image: wave + caustic refraction with
        /// bright caustic filaments.
        case water(scale: Double, waves: Double, refraction: Double, layering: Double,
                   edges: Double, highlights: Double, highlight: SIMD4<Float>, phase: Double)
        /// A sheet of paper the image is laid onto: tooth, crumples, fold
        /// creases, and speckles lit as emboss relief.
        case paperTexture(paper: SIMD4<Float>, shading: SIMD4<Float>, contrast: Double,
                          roughness: Double, fiber: Double, crumples: Double,
                          folds: Double, drops: Double, seed: Double)
        /// Liquid chrome over the layer's alpha shape: flowing reflectance bands
        /// that wrap the silhouette, with chromatic fringing.
        case liquidMetal(repetition: Double, softness: Double, dispersion: Double,
                         distortion: Double, contour: Double, angle: Double,
                         tint: SIMD4<Float>, phase: Double)
        /// Thermal-camera rendering of the layer's alpha shape: heat blooming
        /// inside, a halo radiating outside, mapped through a palette.
        case heatmap(colors: [SIMD4<Float>], contour: Double, innerGlow: Double,
                     outerGlow: Double, angle: Double, noise: Double, phase: Double)
        /// Swirling smoke trapped inside (and leaking out of) the layer's alpha
        /// shape, over a glassy body fill.
        case gemSmoke(colors: [SIMD4<Float>], body: SIMD4<Float>, innerSwirl: Double,
                      outerSwirl: Double, innerGlow: Double, outerGlow: Double,
                      offset: Double, scale: Double, angle: Double, phase: Double)
        /// Luminance melt: the layer liquified by a warped noise field and
        /// poured through a four-stop palette, its brightness steering the
        /// field back.
        case melt(colors: [SIMD4<Float>], scale: Double, warp: Double,
                  liquify: Double, blend: Double, phase: Double)
        /// Every drawn pixel held as a color source, and the color let out into
        /// the empty space between them until it settles.
        case diffuse(threshold: Double, sharpness: Double)

        // Measured fields -----------------------------------------------------
        /// Measure how far every pixel is from the nearest place the layer crosses
        /// `threshold`, and which way that place lies. Beyond `maxDistance` the
        /// measurement stops (and the ladder gets shorter); nil measures the whole layer.
        case distanceField(source: FieldSource, threshold: Double, maxDistance: Double?)
        /// Read a measured field back as a picture: signed distance mapped through a
        /// 256-step ramp over `from`…`to` pixels, wrapped rather than clamped when
        /// `repeating` (which draws the field as contour bands).
        case fieldMap(lut: [SIMD4<Float>], from: Double, to: Double, repeating: Bool)
        /// Average every pixel with the square of the given radius around it, over a
        /// summed-area table, so the cost does not grow with the radius.
        case boxBlur(radius: Double)
        /// Cut each pixel against the average of the `window`-wide square around it
        /// rather than against one number for the whole layer (nil sizes the window at
        /// an eighth of the layer). A pixel goes dark where it sits `bias` below that
        /// local average.
        case adaptiveThreshold(window: Double?, bias: Double, invert: Bool)
    }

    let kind: Kind

    /// A user-supplied `Shader` as a one-input filter: it reads this layer with
    /// `sample(info, uv)` and returns a new color. Use with `filtered(_:)` /
    /// `postProcess(_:)`.
    public static func shader(_ shader: Shader) -> Filter { Filter(kind: .shader(shader)) }

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
                             amount: Double = 1,
                             radius: Double = 16) -> Filter {
        Filter(kind: .bloom(threshold: max(0, threshold),
                            intensity: max(0, amount),
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

    /// The layer as somebody with the given color vision sees it.
    ///
    /// Put it on the whole frame with `postProcess(.colorVision(.deuteranopia))`
    /// to check that a piece still reads. The matrix belongs in linear light,
    /// which is what a layer already holds, so nothing is encoded on the way in
    /// or out.
    ///
    /// ```swift
    /// postProcess(.colorVision(.deuteranopia))
    /// ```
    public static func colorVision(_ vision: ColorVision) -> Filter {
        Filter(kind: .colorVision(vision))
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

    /// Soft proof: show the layer as a printing condition will reproduce it. The
    /// colors ink cannot reach come in, the blacks lift to what ink can actually
    /// do, and with `simulatesPaper` the stock's own color arrives too.
    ///
    /// ```swift
    /// let press = SoftProof(.genericCMYK)
    /// postProcess(.softProof(press))                                // proofed
    /// postProcess(.softProof(press, warning: .magenta))             // and what will not survive
    /// postProcess(.softProof(press, warning: .magenta, amount: 0))  // flag only, colors untouched
    /// ```
    ///
    /// The profile round trip is baked into a lattice once per printing
    /// condition (about 4 ms) and sampled per pixel after that, so proofing
    /// live costs one pass. `warning`, when given, paints every color the
    /// destination cannot hold in that color instead. See
    /// `Docs/Output/PrintColor.md`.
    public static func softProof(_ proof: SoftProof, warning: Color? = nil,
                                 amount: Double = 1) -> Filter {
        Filter(kind: .softProof(lut: ProofLUTCache.lut(for: proof),
                                warning: warning?.linearRGBA,
                                amount: min(max(amount, 0), 1)))
    }

    /// Soft proof against a printer profile, from an sRGB canvas: the short
    /// form of `softProof(SoftProof(...))`.
    public static func softProof(_ profile: ICCProfile, intent: RenderingIntent = .relative,
                                 simulatesPaper: Bool = false, warning: Color? = nil,
                                 amount: Double = 1) -> Filter {
        softProof(SoftProof(profile, intent: intent, simulatesPaper: simulatesPaper),
                  warning: warning, amount: amount)
    }

    // MARK: Stylize & optical

    /// Smooth the stair-stepped edges in a layer that a fragment shader wrote pixel
    /// by pixel: a `generate(_:)` pattern, a raymarched field, an imported shader, or
    /// a finished chain. Those have no coverage of their own, and none of the
    /// renderer's other anti-aliasing reaches them, so a hard edge inside one comes
    /// out as a staircase. This pass works from the finished image alone: it finds
    /// each edge by brightness, follows it to both ends, and reads the layer back a
    /// fraction of a pixel across it, which turns the steps into a ramp.
    ///
    /// `threshold` is the contrast an edge needs before the pass touches it at all
    /// (lower reaches fainter edges and costs more), `quality` how far it may follow
    /// one (a long, nearly flat edge needs the longer look), and `amount` how much of
    /// the result to keep, so `amount: 0` hands the layer back unchanged.
    ///
    /// It reads pixels, not shapes, so it cannot tell a stair-step from detail that
    /// is genuinely one pixel wide, and it softens both. That is why it is a filter
    /// you place rather than something every layer gets.
    public static func antialias(amount: Double = 1, threshold: Double = 0.125,
                                 quality: RenderQuality = .default) -> Filter {
        Filter(kind: .antialias(amount: min(max(amount, 0), 1),
                                threshold: min(max(threshold, 0.01), 1), quality: quality))
    }

    /// The layer's frequency spectrum: what it is made of, wave by wave, instead
    /// of pixel by pixel. Slow, smooth gradients sit near the middle of the
    /// result and fine detail out at the edges, so the picture becomes a map of
    /// its own scales.
    ///
    /// ```swift
    /// let plate = makeRenderTarget(width: 512, height: 512)
    /// withTarget(plate) { background(.black); fill(.white); drawCircle(256, 256, 90) }
    /// drawImage(plate.filtered(.fourier()).filtered(.spectrum()).image, 0, 0)
    /// ```
    ///
    /// Three things are worth knowing. The layer has to be square and its side a
    /// power of two (512, 1024), which is what the transform works on; a layer
    /// that is not comes back untouched with a note. The result is not a picture
    /// but a pair of numbers per texel (red the real part, green the imaginary
    /// one), so look at it through `.spectrum()` and turn it back into a picture
    /// with `.inverseFourier()`. And it transforms one channel, the linear
    /// luminance unless you name another.
    ///
    /// Between the two, a layer drawn over the spectrum multiplies it, which is
    /// filtering by scale: keep the middle and the picture comes back soft, keep
    /// the outside and only its edges come back.
    public static func fourier(of channel: FourierChannel = .luminance) -> Filter {
        Filter(kind: .fourier(channel))
    }

    /// A spectrum turned back into a picture: the exact opposite of `fourier`,
    /// so the two with nothing in between hand back the channel that went in.
    /// The result is gray (one channel went in, one comes out).
    public static func inverseFourier() -> Filter {
        Filter(kind: .inverseFourier)
    }

    /// A spectrum as something to look at: the strength of each wave as gray.
    /// The lowest frequencies of an ordinary picture are tens of thousands of
    /// times the highest, so the scale is compressed by a logarithm and `gain`
    /// decides how hard. The useful range is wide (a few thousand to a few
    /// million): raise it until the faint high frequencies come up out of the
    /// black, and drop it if the middle floods.
    public static func spectrum(gain: Double = 12_000) -> Filter {
        Filter(kind: .spectrum(gain: max(1, gain)))
    }

    /// Sobel edge detection: bright edges on black, scaled by `intensity`. A quick
    /// outline / comic-ink pass.
    public static func edges(amount: Double = 1) -> Filter {
        Filter(kind: .edges(intensity: max(0, amount)))
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

    /// Chromatic aberration: pull the color channels apart, the way cheap glass, a
    /// misprinted plate, or a lens wide open does. `amount` is the split in fractions
    /// of the canvas, and `mode` chooses which of those pictures you get (see
    /// `Dispersion`; the default scales each channel about the center).
    ///
    /// ```swift
    /// layer.filtered(.chromaticAberration(amount: 0.012))                     // a lens
    /// layer.filtered(.chromaticAberration(amount: 0.01, mode: .offset(angle: .pi / 4)))
    /// layer.filtered(.chromaticAberration(amount: 0.02, mode: .edges))        // edges only
    /// ```
    ///
    /// `spectral: true` takes a whole set of wavelength taps along the split instead of
    /// three, which turns three hard ghosts into a continuous rainbow smear; it is the
    /// single largest jump in quality here, and it costs a tap count the `quality` tier
    /// sets. `amount: 0` always hands the layer back unchanged.
    ///
    /// Every tap is unpremultiplied before its channel is read, so a layer with soft
    /// edges of its own keeps them instead of growing a dark rim. Past the frame edge
    /// the sampler clamps, so a flat `.offset` smears its border strip inward, the way
    /// a misregistered plate does.
    ///
    /// See `Combine.disperse(amount:mode:spectral:quality:)` to drive the amount from a
    /// second layer.
    public static func chromaticAberration(amount: Double = 0.005,
                                           mode: Dispersion = .magnify,
                                           spectral: Bool = false,
                                           quality: RenderQuality = .default) -> Filter {
        Filter(kind: .chromaticAberration(amount: amount, mode: mode,
                                          spectral: spectral, quality: quality))
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

    /// Two-tone ordered dither: screen the image's tone into the Bayer pattern in
    /// exactly two colors, `light` where it's bright and `dark` where it isn't, the
    /// 1-bit / newsprint look in any palette. `bias` shifts the cut (positive
    /// lightens, negative darkens), and `pixelSize` sizes the pattern cells in
    /// pixels. Either color may be transparent, so the dark half can drop out.
    public static func dither(dark: Color, light: Color, bias: Double = 0,
                              pixelSize: Double = 1) -> Filter {
        Filter(kind: .ditherDuo(dark: dark.linearRGBA, light: light.linearRGBA,
                                bias: min(max(bias, -1), 1), pixelSize: max(1, pixelSize)))
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

    /// Print a layer of accumulated light as a picture. The layer's linear values
    /// (an `Accumulator`'s mean, a `noClear` pile) are scaled by `exposure`, rolled
    /// off through the Reinhard curve `x / (1 + x)` so nothing ever clips, and laid
    /// on `ground`, which is added *after* the curve as a display color and never
    /// touched by it: the paper the light is printed on. The sum is written as the
    /// display value itself rather than re-encoded, which is what gives a
    /// sandpainting its deep midtones. Alpha comes out 1. For a picture rather
    /// than a pile of light, `.exposure` plus the frame's `toneMap` is the ordinary
    /// route.
    public static func develop(exposure: Double = 1, ground: Color = .black) -> Filter {
        Filter(kind: .develop(exposure: max(0, exposure),
                              ground: SIMD4<Float>(Float(ground.red), Float(ground.green),
                                                   Float(ground.blue), 1)))
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
    /// base). `radius` is the blur extent in pixels, `sigma` how different a neighbor's
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

    /// Median: replace each pixel with the median of its 3×3 neighborhood, knocking out
    /// speckle and stray pixels while leaving edges sharp.
    public static func median() -> Filter { Filter(kind: .median) }

    /// Contour: draw dark iso-brightness lines (a contour every `1/levels` of the range)
    /// over the image at `intensity`, turning tone into a topographic map.
    public static func contour(levels: Double = 10, amount: Double = 1) -> Filter {
        Filter(kind: .contour(levels: max(1, levels), intensity: min(max(amount, 0), 1)))
    }

    /// CMYK halftone: separate the image into cyan/magenta/yellow/black and screen each as
    /// rotated dots at the classic print angles. `scale` sets the dot frequency.
    public static func cmykHalftone(scale: Double = 70) -> Filter {
        Filter(kind: .cmykHalftone(scale: max(1, scale)))
    }

    /// Normal map: read the image as a height field and output its surface normal as an RGB
    /// vector (the bluish bump-map look), ready to feed `displace` or a lighting pass.
    /// `strength` exaggerates the slope.
    public static func normalMap(amount: Double = 1) -> Filter {
        Filter(kind: .normalMap(strength: max(0, amount)))
    }

    /// The curated material a `relight` shades the height field with: `matte`
    /// clay, `metal` (reflections tinted by the surface color), wet `glass`
    /// (a sharp glint plus a bright edge rim), grainy `sand` (a roughened
    /// surface with tiny glints), or `liquid` (a smooth wet sheen that also
    /// refracts the image beneath).
    public enum RelightFinish: Sendable {
        case matte, metal, glass, sand, liquid

        /// The shader's finish index (kept in step with `ollin_fx_relight`).
        var rawIndex: Float {
            switch self {
            case .matte:  return 0
            case .metal:  return 1
            case .glass:  return 2
            case .sand:   return 3
            case .liquid: return 4
            }
        }
    }

    /// Relight: read the layer as a height map (bright = raised), turn its
    /// slopes into a surface, and light that surface with a curated material
    /// `finish`, so a noise field or a simulation reads as embossed physical
    /// matter. `angle` (radians) sets where the light comes from, `elevation`
    /// (0 grazing … π/2 overhead) how low it rakes, `height` exaggerates the
    /// relief, `intensity` scales the light, and `color` overrides the material
    /// color (by default the layer keeps its own). The cheap 2D cousin of the
    /// 3D materials.
    public static func relight(_ finish: RelightFinish = .matte,
                               angle: Double = -.pi * 0.75, elevation: Double = 0.9,
                               height: Double = 2, intensity: Double = 1,
                               color: Color? = nil) -> Filter {
        Filter(kind: .relight(finish: finish, angle: angle,
                              elevation: min(max(elevation, 0.05), .pi / 2),
                              height: max(0, height), intensity: max(0, intensity),
                              color: color?.linearRGBA))
    }

    /// Iridescence: wash the content with the shifting rainbow sheen of a soap film or
    /// oil slick. The colors come from thin-film interference (each channel cycling at
    /// its own wavelength, so the bands run through the film color order), swirled by a
    /// noise field and following the content's own shading. `amount` (0…1) blends the
    /// sheen over the original, `scale` sets how fine the swirl is, `bands` how many
    /// color cycles the film runs through (more = busier rainbow), and `shift` slides
    /// the colors: feed it your `time` for a sheen that flows.
    public static func iridescence(amount: Double = 0.7, scale: Double = 2.5,
                                   bands: Double = 2.5, shift: Double = 0) -> Filter {
        Filter(kind: .iridescence(amount: min(max(amount, 0), 1), scale: max(0.001, scale),
                                  bands: max(0, bands), shift: shift))
    }

    /// Glitter: scatter twinkling sparkle flecks across the content, a dense dust of
    /// small glints plus occasional bright cross-flare flashes, landing only where
    /// something is drawn. `density` is the fleck grid resolution (cells across the
    /// layer), `amount` the sparkle brightness (flashes run past 1.0 in linear light,
    /// so a following `.bloom` makes them glow), `size` scales the flecks, and
    /// `saturation` tints them from white (0) toward each fleck's own color (1).
    /// `phase` drives the twinkle: feed it your `time` so the glitter sparkles.
    public static func glitter(density: Double = 90, amount: Double = 1,
                               size: Double = 1, saturation: Double = 0.3,
                               phase: Double = 0) -> Filter {
        Filter(kind: .glitter(density: max(4, density), amount: max(0, amount),
                              size: min(max(size, 0.25), 3), saturation: min(max(saturation, 0), 1),
                              phase: phase))
    }

    /// Thin film, measured: wash the content with the colors a real film shows,
    /// worked out per wavelength (a `quality`-sized set of taps) instead of a styled
    /// rainbow, so the bands follow the film color order a soap bubble drains
    /// through. `thickness` is the film's mean depth in nanometers (about 100 for
    /// the near-clear film, 300 to 600 for the strong colors, toward 1500 for the
    /// pale crowded bands), `variation` how many nanometers the swirl adds and
    /// removes, `ior` the film's refractive index (1.35 soap, 1.45 oil), `scale` how
    /// fine the swirl is, and `shift` slides the swirl: feed it your `time` for a
    /// draining film. The stylized sibling is `iridescence`; this one buys the real
    /// interference spectrum, including the pale washed-out look of a thick film.
    public static func thinFilm(amount: Double = 0.7, thickness: Double = 420,
                                variation: Double = 280, ior: Double = 1.35,
                                scale: Double = 2.5, shift: Double = 0,
                                quality: RenderQuality = .default) -> Filter {
        Filter(kind: .thinFilm(amount: min(max(amount, 0), 1),
                               thickness: min(max(thickness, 20), 2000),
                               variation: min(max(variation, 0), 1200),
                               ior: min(max(ior, 1.05), 2.5),
                               scale: max(0.001, scale), shift: shift, quality: quality))
    }

    /// Diffraction grating: split the content into rainbow orders along `angle`, the
    /// way a bright light streaks across a groove pattern. Each side of the image
    /// repeats `orders` times, every repeat offset by wavelength (red reaching
    /// farther than blue, the grating equation), so bright marks stretch into
    /// spectral streaks while the image itself stays put. `amount` is the first
    /// order's reach (a fraction of the layer), `falloff` how much dimmer each
    /// further order is, and `quality` the wavelength tap count (more taps, smoother
    /// rainbow). Run it on bright-on-dark content and follow with `.bloom` for the
    /// full lens-flare sparkle.
    public static func diffraction(amount: Double = 0.05, angle: Double = 0,
                                   orders: Int = 2, falloff: Double = 0.55,
                                   quality: RenderQuality = .default) -> Filter {
        Filter(kind: .diffraction(amount: max(0, amount), angle: angle,
                                  orders: Double(min(max(orders, 1), 3)),
                                  falloff: min(max(falloff, 0), 1), quality: quality))
    }

    // MARK: Retro / optical

    /// Scanlines: darken alternating horizontal lines, the CRT look. `count` is how many
    /// lines span the height, `intensity` (0…1) how dark the gaps go.
    public static func scanlines(count: Double = 240, amount: Double = 0.4) -> Filter {
        Filter(kind: .scanlines(count: max(1, count), intensity: min(max(amount, 0), 1)))
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

    /// Swirl (twirl): wind the image into a vortex, rotating by `angle` (radians) strongest at
    /// `center`, easing to none at `radius` (in fractions of the layer). `center` is also in
    /// fractions of the layer (top-left origin, the middle by default), so a cursor-driven
    /// vortex is `center: Vector2(mouseX / width, mouseY / height)`.
    public static func swirl(angle: Double = 3, radius: Double = 0.5,
                             center: Vector2 = Vector2(0.5, 0.5)) -> Filter {
        Filter(kind: .swirl(angle: angle, radius: max(0.001, radius), center: center))
    }

    /// Droste: the picture inside itself, without end. The ring between `inner` and the layer's
    /// edge is repeated at every scale, so a copy of the picture sits in the middle of the
    /// picture, with a copy in the middle of that one, and so on.
    ///
    /// - Parameters:
    ///   - inner: The radius of the hole in the middle, as a fraction of the layer's shorter
    ///     side. It is also how much smaller each copy is than the one around it.
    ///   - twist: How many copies one turn around the middle steps down. `0` leaves the copies
    ///     as plain concentric rings; `1` winds them into the single spiral of the Escher
    ///     construction, and a negative value winds it the other way. Whole numbers close on
    ///     themselves; anything between leaves a visible seam.
    ///   - zoom: How far the picture has fallen into itself, in copies. Add `1` and the picture
    ///     is exactly back where it started, so `zoom: time * 0.2` is an endless fall that
    ///     loops every five seconds.
    ///   - center: Where the middle sits, in fractions of the layer (top-left origin).
    ///   - rotation: Turn the whole thing, in radians.
    public static func droste(inner: Double = 0.35, twist: Double = 1, zoom: Double = 0,
                              center: Vector2 = Vector2(0.5, 0.5),
                              angle: Double = 0) -> Filter {
        Filter(kind: .droste(inner: min(max(inner, 0.001), 0.99), twist: twist,
                             zoom: zoom, center: center, rotation: angle))
    }

    /// Bulge / pinch: a radial lens within `radius` of `center`. `amount` > 0 bulges (fisheye
    /// magnifying the center), < 0 pinches (sucks toward it); the warp eases back to the image
    /// at `radius`. `center` is in fractions of the layer (top-left origin, the middle by
    /// default), so a cursor-driven lens is `center: Vector2(mouseX / width, mouseY / height)`.
    public static func bulge(amount: Double = 0.5, radius: Double = 0.5,
                             center: Vector2 = Vector2(0.5, 0.5)) -> Filter {
        Filter(kind: .bulge(amount: max(-0.95, min(amount, 4)), radius: max(0.001, radius),
                            center: center))
    }

    /// Wave: ripple the image sinusoidally. `vertical` false ripples rows side to side, true
    /// ripples columns up and down. `amplitude` is the shift (fraction of the layer),
    /// `frequency` the cycles across it, `phase` slides the wave (animate it).
    public static func wave(amplitude: Double = 0.02, frequency: Double = 8,
                            phase: Double = 0, vertical: Bool = false) -> Filter {
        Filter(kind: .wave(amplitude: max(0, amplitude), frequency: frequency,
                           phase: phase, vertical: vertical))
    }

    /// Ripple: concentric waves spreading from `center`, like a drop in water.
    /// `amplitude` is the shift (fraction of the layer), `frequency` the number of rings,
    /// `phase` moves them outward (animate it). `center` is in fractions of the layer
    /// (top-left origin, the middle by default), so the drop can land where the cursor is.
    public static func ripple(amplitude: Double = 0.02, frequency: Double = 12,
                              phase: Double = 0,
                              center: Vector2 = Vector2(0.5, 0.5)) -> Filter {
        Filter(kind: .ripple(amplitude: max(0, amplitude), frequency: frequency, phase: phase,
                             center: center))
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

    // MARK: Design filters

    /// The flute layout `flutedGlass` slices the image into: straight `lines`,
    /// unevenly-spaced `irregular` lines, a sinuous `wave`, a `zigzag`, or a 2D
    /// `eggCrate` cell pattern.
    public enum FluteShape: Sendable {
        case lines, irregular, wave, zigzag, eggCrate

        /// The shader's shape index (kept in step with `ollin_fx_fluted_glass`).
        var rawIndex: Float {
            switch self {
            case .lines: return 0
            case .irregular: return 1
            case .wave: return 2
            case .zigzag: return 3
            case .eggCrate: return 4
            }
        }
    }

    /// The refraction profile within each flute of `flutedGlass`: a `prism`
    /// wedge, a rounded `lens`, a flat-centered `contour`, a sawtooth `cascade`,
    /// or a nearly-`flat` pane.
    public enum FluteProfile: Sendable {
        case prism, lens, contour, cascade, flat

        /// The shader's profile index (kept in step with `ollin_fx_fluted_glass`).
        var rawIndex: Float {
            switch self {
            case .prism: return 0
            case .lens: return 1
            case .contour: return 2
            case .cascade: return 3
            case .flat: return 4
            }
        }
    }

    /// Fluted (reeded) glass: the image seen through ribbed architectural glass.
    /// Each of the `flutes` refracts its slice of the image through `profile`,
    /// with bright hairlines and shadow ramps at the flute boundaries. `shape`
    /// bends the flute layout, `distortion` scales the refraction, `shift` slides
    /// it, `stretch` streaks the image along the flutes near their borders,
    /// `blur` frosts the glass, `edges` softens samples pushed off the layer,
    /// `margins` (layer pixels) leaves a plain undistorted frame around the
    /// glass, and `angle` (radians) rotates the whole assembly.
    public static func flutedGlass(flutes: Double = 80, shape: FluteShape = .lines,
                                   profile: FluteProfile = .prism,
                                   distortion: Double = 0.5, shift: Double = 0,
                                   stretch: Double = 0, blur: Double = 0,
                                   edges: Double = 0.25, highlights: Double = 0.1,
                                   shadows: Double = 0.25, margins: Insets = .zero,
                                   angle: Double = 0) -> Filter {
        Filter(kind: .flutedGlass(flutes: min(max(flutes, 3), 300), shape: shape,
                                  profile: profile, distortion: min(max(distortion, 0), 1),
                                  shift: min(max(shift, -1), 1), stretch: min(max(stretch, 0), 1),
                                  blur: min(max(blur, 0), 1), edges: min(max(edges, 0), 1),
                                  highlights: min(max(highlights, 0), 1),
                                  shadows: min(max(shadows, 0), 1), margins: margins,
                                  angle: angle))
    }

    /// Water: the image seen through shallow rippling water. Broad `waves`
    /// wobble it, fine caustic `refraction` shimmers it (`layering` adds a
    /// second finer caustic octave), and bright caustic
    /// filaments wash over it in `highlight`. `scale` sizes the ripple field,
    /// `edges` (0…1) lets the distortion reach the layer's borders, and `phase`
    /// animates the water: feed it your `time`.
    public static func water(scale: Double = 1, waves: Double = 0.3,
                             refraction: Double = 0.1, layering: Double = 0.5,
                             edges: Double = 0.8,
                             highlightAmount: Double = 0.07, highlightColor: Color = .white,
                             phase: Double = 0) -> Filter {
        Filter(kind: .water(scale: min(max(scale, 0.05), 7), waves: min(max(waves, 0), 1),
                            refraction: min(max(refraction, 0), 1),
                            layering: min(max(layering, 0), 1), edges: min(max(edges, 0), 1),
                            highlights: min(max(highlightAmount, 0), 1),
                            highlight: highlightColor.linearRGBA, phase: phase))
    }

    /// Paper: lay the image onto a synthesized sheet of paper, embossed by its
    /// relief. The height field mixes tooth (`roughness`), curly `fiber`
    /// filaments, `crumples` facets, long fold creases (`folds`), and ink-drop
    /// speckles (`drops`); `contrast` steepens the lighting, `seed` re-rolls the
    /// creases and speckles. `paper` is the sheet color where the layer is
    /// transparent, `shading` the relief tint. Static by design.
    public static func paperTexture(paper: Color = .white,
                                    shading: Color = Color(hex: 0x9FADBC),
                                    contrast: Double = 0.3, roughness: Double = 0.4,
                                    fiber: Double = 0.3, crumples: Double = 0.3,
                                    folds: Double = 0.65, drops: Double = 0.2,
                                    seed: Double = 5.8) -> Filter {
        Filter(kind: .paperTexture(paper: paper.linearRGBA, shading: shading.linearRGBA,
                                   contrast: min(max(contrast, 0), 1),
                                   roughness: min(max(roughness, 0), 1),
                                   fiber: min(max(fiber, 0), 1),
                                   crumples: min(max(crumples, 0), 1),
                                   folds: min(max(folds, 0), 1),
                                   drops: min(max(drops, 0), 1), seed: seed))
    }

    /// Liquid metal: render the layer's alpha shape as flowing chrome. Diagonal
    /// reflectance bands compress and wrap along the silhouette as if the shape
    /// were inflated, with chromatic fringing on the band edges. `repetition`
    /// sets the band count, `softness` blurs them, `dispersion` splits the
    /// channels, `distortion` wobbles the flow, `contour` strengthens the
    /// silhouette wrap, `angle` (radians) turns the bands, `tint` color-burns
    /// the chrome, and `phase` flows it: feed it your `time`. Draw a shape into
    /// a layer, then filter it.
    public static func liquidMetal(repetition: Double = 2, softness: Double = 0.1,
                                   dispersion: Double = 0.3, distortion: Double = 0.07,
                                   contour: Double = 0.4, angle: Double = 1.2217,
                                   tint: Color = .white, phase: Double = 0) -> Filter {
        Filter(kind: .liquidMetal(repetition: min(max(repetition, 1), 10),
                                  softness: min(max(softness, 0), 1),
                                  dispersion: min(max(dispersion, -1), 1),
                                  distortion: min(max(distortion, 0), 1),
                                  contour: min(max(contour, 0), 1), angle: angle,
                                  tint: tint.linearRGBA, phase: phase))
    }

    /// Heatmap: render the layer's alpha shape as thermal imaging. Heat blooms
    /// inside the shape and a halo radiates outside, pulsing in slow traveling
    /// waves, mapped through `colors` cold-to-hot (the first stop fades to
    /// transparent). `contour` glows the inner edge, `innerGlow`/`outerGlow`
    /// scale the two fields, `angle` (radians) steers the traveling waves,
    /// `noise` adds thermal grain, and `phase` drives the waves: feed it your
    /// `time`.
    public static func heatmap(colors: [Color] = [Color(hex: 0x0B1026), Color(hex: 0x1E3A8A),
                                                  Color(hex: 0x0EA5E9), Color(hex: 0x67E8F9),
                                                  Color(hex: 0xFDE047), Color(hex: 0xF97316),
                                                  Color(hex: 0xDC2626)],
                               contour: Double = 0.5, innerGlow: Double = 0.5,
                               outerGlow: Double = 0.5, angle: Double = 0,
                               noise: Double = 0, phase: Double = 0) -> Filter {
        let capped = colors.isEmpty ? [Color.white] : Array(colors.prefix(8))
        return Filter(kind: .heatmap(colors: capped.map(\.linearRGBA),
                                     contour: min(max(contour, 0), 1),
                                     innerGlow: min(max(innerGlow, 0), 1),
                                     outerGlow: min(max(outerGlow, 0), 1), angle: angle,
                                     noise: min(max(noise, 0), 1), phase: phase))
    }

    /// Gem smoke: coil swirling smoke inside (and leaking out of) the layer's
    /// alpha shape, over a glassy `body` fill, colored through `colors`. The
    /// inner and outer plumes warp by `innerSwirl`/`outerSwirl` and scale by
    /// `innerGlow`/`outerGlow`; `offset` slides the trapped smoke vertically,
    /// `scale` sizes the plume, `angle` (radians) tilts it, and `phase` coils
    /// it: feed it your `time`. Draw a shape into a layer, then filter it.
    public static func gemSmoke(colors: [Color] = [Color(hex: 0x333333), Color(hex: 0xE7E6DF)],
                                body: Color = Color(hex: 0xFAFAF5),
                                innerSwirl: Double = 0.8, outerSwirl: Double = 0.6,
                                innerGlow: Double = 1, outerGlow: Double = 0.55,
                                offset: Double = 0, scale: Double = 0.8,
                                angle: Double = 0, phase: Double = 0) -> Filter {
        let capped = colors.isEmpty ? [Color.white] : Array(colors.prefix(6))
        return Filter(kind: .gemSmoke(colors: capped.map(\.linearRGBA), body: body.linearRGBA,
                                      innerSwirl: min(max(innerSwirl, 0), 1),
                                      outerSwirl: min(max(outerSwirl, 0), 1),
                                      innerGlow: min(max(innerGlow, 0), 1),
                                      outerGlow: min(max(outerGlow, 0), 1),
                                      offset: min(max(offset, -1), 1),
                                      scale: min(max(scale, 0), 1), angle: angle, phase: phase))
    }

    /// Luminance melt: the layer liquified by a warped noise field and poured
    /// through a four-stop palette. One displacement does double duty: it
    /// warps the field's own domain and shifts where the layer is sampled, so
    /// the picture smears along the field's currents while its brightness
    /// steers the field back. `liquify` is the smear amount, `blend` how much
    /// the image leads the field (`1` reads the liquified photo straight
    /// through the palette), `warp` the field's turbulence, `scale` its zoom.
    /// `colors` is the ramp dark to light; `phase` animates the churn: feed
    /// it your `time`.
    public static func melt(colors: [Color] = [Color(hex: 0x0A0A1A), Color(hex: 0x3A1F7A),
                                               Color(hex: 0xC84FE0), Color(hex: 0xFFE1F5)],
                            scale: Double = 1.5, warp: Double = 4.5,
                            liquify: Double = 0.8, blend: Double = 0.6,
                            phase: Double = 0) -> Filter {
        var stops = colors.isEmpty ? [Color(hex: 0x0A0A1A)] : Array(colors.prefix(4))
        while stops.count < 4 { stops.append(stops[stops.count - 1]) }
        return Filter(kind: .melt(colors: stops.map(\.linearRGBA),
                                  scale: min(max(scale, 0.05), 7),
                                  warp: min(max(warp, 0), 10),
                                  liquify: min(max(liquify, 0), 2),
                                  blend: min(max(blend, 0), 1),
                                  phase: phase))
    }

    // MARK: Diffusion

    /// **Diffusion curves**: hold every pixel you drew as a color source, and let
    /// the color out into the empty space between them until it settles. What
    /// comes back is a smooth field that no gradient can make, because its shape
    /// is decided by where the marks are rather than by a direction and two ends.
    ///
    /// The rule the solve obeys is the one a soap film obeys: away from the
    /// marks, every pixel ends up the average of its four neighbors. That single
    /// sentence is why the result looks the way it does. Nothing overshoots, no
    /// color appears that was not put there, and a mark's influence falls away
    /// smoothly in every direction at once.
    ///
    /// A pixel counts as a source when its alpha is at least `threshold`, so
    /// draw the marks into a layer of their own and filter that:
    ///
    /// ```swift
    /// let marks = makeRenderTarget()
    /// withTarget(marks) {
    ///     strokeWeight(6); stroke(Color(hex: 0xE2544C))
    ///     drawLine(120, 200, 900, 340)
    ///     fill(Color(hex: 0x2B6C8C)); noStroke()
    ///     drawCircle(540, 800, 40)
    /// }
    /// drawImage(marks.filtered(.diffuse()).image, 0, 0)
    /// ```
    ///
    /// `drawDiffusionCurve(_:left:right:)` lays a curve with a different color on
    /// each side, which is the form the technique is named for: the field jumps
    /// across the curve and is smooth everywhere else.
    ///
    /// `sharpness` (0…1) decides how much of the work is done at full size. Low
    /// is faster and softer, and 1 keeps a thin mark's color crisp right up
    /// against it.
    public static func diffuse(threshold: Double = 0.35, sharpness: Double = 0.7) -> Filter {
        Filter(kind: .diffuse(threshold: min(max(threshold, 0.01), 1),
                              sharpness: min(max(sharpness, 0), 1)))
    }

    // MARK: Measured fields

    /// Measure a distance field back out of what the layer already holds: for every
    /// pixel, how far it lies from the nearest edge of the drawn shape, and which way
    /// that edge is. The counterpart of `SDF`, which is the field a sketch *writes*;
    /// this is the one it *reads*.
    ///
    /// The result is a layer like any other, and it chains like one, but its channels
    /// carry measurements rather than a picture:
    ///
    /// - **red**: the distance in pixels, negative *inside* the shape, positive outside
    /// - **green, blue**: the unit direction from this pixel toward that nearest edge
    /// - **alpha**: 1
    ///
    /// so `pixel + direction * abs(distance)` is the edge point itself. That is what a
    /// user `Shader` reads to look up whatever was drawn there (a Voronoi keyed to a
    /// picture), or to push things apart along the direction they are crowded from.
    ///
    /// ```swift
    /// let marks = makeRenderTarget()
    /// withTarget(marks) { fill(.white); drawCircle(540, 540, 200) }
    /// let field = marks.filtered(.distanceField())
    /// drawImage(field.filtered(.fieldMap(.viridis, from: -200, to: 200)).image, 0, 0)
    /// ```
    ///
    /// `from` picks the value the threshold cuts: `.alpha`, the coverage a shape was
    /// drawn with, is the usual one; brightness or a single channel suit a layer with no
    /// transparency in it. The edge is found *between* pixels rather than at their
    /// centers, so an antialiased shape measures to a fraction of a pixel.
    ///
    /// `maxDistance` stops the measurement early. It is both an answer ("I only care
    /// about the first 64 pixels") and the speed parameter, since the flood costs one pass per
    /// doubling of the distance it has to carry. Past it the field reads flat, with a
    /// zero direction, which says "nothing within reach" rather than pointing nowhere.
    public static func distanceField(from source: FieldSource = .alpha,
                                     threshold: Double = 0.5,
                                     maxDistance: Double? = nil) -> Filter {
        Filter(kind: .distanceField(source: source,
                                    threshold: max(0, threshold),
                                    maxDistance: maxDistance.map { max(1, $0) }))
    }

    /// Read a measured `distanceField` back as a picture: its signed distance mapped
    /// through `ramp` across the `from`…`to` window in pixels, where 0 is the edge and
    /// negative is inside. This is what makes a field visible, and it is also how a
    /// field does its work: a ramp that turns over at one distance dilates or erodes the
    /// shape, a narrow dark band draws an outline at a chosen offset, and `repeating`
    /// wraps the ramp instead of clamping it, which draws the field as contour bands.
    public static func fieldMap(_ ramp: Ramp, from: Double = -32, to: Double = 32,
                                repeating: Bool = false) -> Filter {
        Filter(kind: .fieldMap(lut: bakeLUT { ramp.color(at: $0) },
                               from: from, to: to, repeating: repeating))
    }

    /// `fieldMap` through a `Colormap` (viridis, magma, turbo, …).
    public static func fieldMap(_ colormap: Colormap, from: Double = -32, to: Double = 32,
                                repeating: Bool = false) -> Filter {
        Filter(kind: .fieldMap(lut: bakeLUT { colormap.color(at: $0) },
                               from: from, to: to, repeating: repeating))
    }

    /// Average every pixel with the square of `radius` pixels around it.
    ///
    /// The blur itself is the plainest one there is, and the reason to reach for it is
    /// the price rather than the look: it runs over a summed-area table, where the
    /// average of any rectangle is four lookups, so **a radius of 400 costs what a radius
    /// of 4 costs**. A Gaussian is the better-looking blur and the cheaper one while the
    /// radius stays small, so prefer `gaussianBlur` there and come here when the reach is
    /// large or when the radius has to change while a sketch runs.
    ///
    /// ```swift
    /// let layer = makeRenderTarget()
    /// withTarget(layer) { background(.black); fill(.orange); drawCircle(540, 540, 120) }
    /// drawImage(layer.filtered(.boxBlur(radius: 300)).image, 0, 0)
    /// ```
    ///
    /// Three of them in a row approximate a Gaussian closely enough that the eye stops
    /// telling them apart, and that is still three passes rather than a kernel that grows.
    /// A window that hangs over the border averages what is really there, so the edges
    /// keep their brightness instead of fading.
    ///
    /// Two costs are worth knowing, and neither depends on the radius. Building the table
    /// is about twenty passes over the layer, measured at 6 ms of GPU time for a 1080
    /// square, so one of these in a frame is comfortable and a dozen are not. And a
    /// running total spends most of a float's mantissa on itself, which leaves an error
    /// that is *absolute*: divided by the window, it falls away as the window grows. On a
    /// 1080 square that is about 7/255 in the worst corner of a 3-pixel window and under
    /// 1.5/255 from 37 pixels up. Both point the same way: this is the blur for a wide
    /// reach, and `gaussianBlur` is the one for a narrow one.
    public static func boxBlur(radius: Double = 16) -> Filter {
        Filter(kind: .boxBlur(radius: max(0, radius)))
    }

    /// Cut the layer to two tones, pixel by pixel, against the average of the
    /// neighborhood around each one rather than against a single number for the whole
    /// picture (Bradley & Roth 2007).
    ///
    /// This is what reads lettering off a photograph lit from one side. A global
    /// `threshold` has to pick one value, so it loses the shadowed corner or floods the
    /// lit one; comparing each pixel against its own surroundings keeps hard contrast and
    /// ignores a slow change in illumination, so both corners come out.
    ///
    /// ```swift
    /// let page = makeRenderTarget()
    /// withTarget(page) { drawImage(photo, 0, 0) }
    /// drawImage(page.filtered(.adaptiveThreshold()).image, 0, 0)
    /// ```
    ///
    /// `window` is how wide that neighborhood is, in pixels, and it wants to be large
    /// enough to hold both ink and paper: too small and the middle of a thick stroke
    /// reads as its own background and hollows out. Left `nil` it is an eighth of the
    /// layer, the published default. `bias` is the *fraction* below the local average a
    /// pixel must fall before it goes dark, which keeps flat paper from breaking up into
    /// noise. A fraction rather than a distance is what makes the cut survive uneven
    /// light, since light falling on a page multiplies what comes back off it. The window
    /// costs nothing to widen, so it is a parameter to adjust freely.
    public static func adaptiveThreshold(window: Double? = nil, bias: Double = 0.15,
                                         invert: Bool = false) -> Filter {
        Filter(kind: .adaptiveThreshold(window: window.map { max(1, $0) },
                                        bias: bias, invert: invert))
    }
}

/// Bake a 256-step LUT of linear, straight-alpha samples from a `0…1 → Color`
/// ramp, the form `gradientMap` uploads as a small lookup texture.
func bakeLUT(_ color: (Double) -> Color) -> [SIMD4<Float>] {
    (0..<256).map { i in color(Double(i) / 255).linearRGBA }
}
