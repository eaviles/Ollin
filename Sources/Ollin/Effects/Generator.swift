import Foundation

/// A procedural pattern that fills a `RenderTarget` from nothing (no input layer),
/// just math evaluated per pixel on the GPU. Where a `Filter` transforms a layer
/// you drew, a `Generator` *is* a layer: a source you composite, filter, or feed
/// into another effect.
///
/// Build one with a static factory and realize it with `generate(_:)`, which hands
/// back a `RenderTarget` (itself drawable via `gen.image` and filterable via
/// `gen.filtered(...)`), so a pattern flows straight into the rest of the effects
/// chain:
///
/// ```swift
/// let stripes = generate(.bars(scale: 24, foreground: .black, background: .white))
/// drawImage(stripes.filtered(.gaussianBlur(radius: 4)).image, 0, 0)
/// ```
///
/// The patterns keep their cells square regardless of the layer's aspect ratio.
public struct Generator: Sendable {

    /// The concrete patterns the renderer knows how to evaluate. Internal: a sketch
    /// builds a `Generator` through the static factories below.
    enum Kind: Sendable {
        /// A checkerboard, `scale` cells across.
        case checkers(scale: Double, foreground: SIMD4<Float>, background: SIMD4<Float>)
        /// A grid of lines, `scale` cells across, `weight` (0…1) of a cell wide.
        case gridLines(scale: Double, weight: Double, foreground: SIMD4<Float>, background: SIMD4<Float>)
        /// Parallel bars, `scale` across; `vertical` chooses the axis.
        case bars(scale: Double, vertical: Bool, foreground: SIMD4<Float>, background: SIMD4<Float>)
        /// Fractal value noise, `scale` features across. `sharpness` 0 is a soft
        /// cloud blending `background`→`foreground`; 1 is a hard two-tone threshold.
        /// `warp` > 0 domain-warps the field (0 leaves it byte-identical).
        case noise(scale: Double, sharpness: Double, warp: Double,
                   foreground: SIMD4<Float>, background: SIMD4<Float>)
        /// Worley cellular noise: `scale` cells across, styled by `style`
        /// (cells / borders / mosaic), feature points wandering with `phase`.
        case cellular(scale: Double, jitter: Double, style: CellularStyle,
                      foreground: SIMD4<Float>, background: SIMD4<Float>, phase: Double)
        /// A user-supplied `Shader` run as a source layer (it reads no input).
        case shader(Shader)

        // Design patterns ------------------------------------------------------
        /// Soft color blobs drifting on orbits, blended by inverse-distance
        /// weighting over a domain-warped, optionally swirled field.
        case meshGradient(colors: [SIMD4<Float>], distortion: Double, swirl: Double,
                          mixing: Double, grain: Double, phase: Double)
        /// A glowing web of thin filaments (a cross-octave sine-feedback fractal).
        case filaments(color: SIMD4<Float>, highlight: SIMD4<Float>, background: SIMD4<Float>,
                       scale: Double, brightness: Double, contrast: Double, phase: Double)
        /// A billowing ring of smoke, radially banded through the palette.
        case smokeRing(colors: [SIMD4<Float>], background: SIMD4<Float>, radius: Double,
                       thickness: Double, fill: Double, scale: Double, detail: Double,
                       phase: Double)
        /// Translucent color panes fanning around a central vertical axis in
        /// fake perspective.
        case colorPanels(colors: [SIMD4<Float>], background: SIMD4<Float>, density: Double,
                         length: Double, skew: Double, blur: Double, fadeIn: Double,
                         fadeOut: Double, gradient: Double, phase: Double)
        /// A two-color spiral: line-art to whirlpool to wobbly hand-drawn rings.
        case spiral(foreground: SIMD4<Float>, background: SIMD4<Float>, density: Double,
                    distortion: Double, strokeWidth: Double, taper: Double, cap: Double,
                    noise: Double, noiseScale: Double, softness: Double, scale: Double,
                    phase: Double)
        /// Horizontal wavy-line stripes, morphable zigzag through sine to irregular.
        case waves(foreground: SIMD4<Float>, background: SIMD4<Float>, shape: Double,
                   frequency: Double, amplitude: Double, spacing: Double,
                   proportion: Double, softness: Double, scale: Double, phase: Double)
        /// A grid of dots, each orbiting its own cell on its own phase.
        case dotOrbit(colors: [SIMD4<Float>], background: SIMD4<Float>, scale: Double,
                      size: Double, sizeVariation: Double, spread: Double, steps: Double,
                      phase: Double)
        /// Poster-style banded gradients over an animated scalar field, the band
        /// edges chewed by film grain.
        case grainGradient(colors: [SIMD4<Float>], background: SIMD4<Float>, shape: GrainShape,
                           softness: Double, intensity: Double, noise: Double, phase: Double)
        /// A glowing rounded border hugging the layer edge, with racing light
        /// spots, a heartbeat pulse, and smoke wisps.
        case pulsingBorder(colors: [SIMD4<Float>], background: SIMD4<Float>, roundness: Double,
                           thickness: Double, softness: Double, intensity: Double,
                           bloom: Double, spots: Double, spotSize: Double, pulse: Double,
                           smoke: Double, smokeScale: Double, margins: Insets, phase: Double)
        /// Crepuscular rays streaming from a point, layered per color.
        case godRays(colors: [SIMD4<Float>], background: SIMD4<Float>, x: Double, y: Double,
                     density: Double, breakup: Double, coreSize: Double,
                     coreIntensity: Double, intensity: Double, bloom: Double,
                     bloomTint: SIMD4<Float>, phase: Double)

        // Pattern fields -------------------------------------------------------
        /// A quasicrystal interference field: plane waves at evenly spaced
        /// angles, their sum walked through the palette.
        case quasicrystal(colors: [SIMD4<Float>], background: SIMD4<Float>, symmetry: Double,
                          scale: Double, contrast: Double, phase: Double)
        /// Moiré fringes from a few ring gratings on slowly orbiting centers.
        case moire(foreground: SIMD4<Float>, background: SIMD4<Float>, sources: Double,
                   frequency: Double, scale: Double, phase: Double)
        /// A slice of the gyroid surface, drawn as interwoven bands.
        case gyroid(foreground: SIMD4<Float>, background: SIMD4<Float>, scale: Double,
                    thickness: Double, phase: Double)
        /// The Vogel phyllotaxis spiral as a continuous dot field, colored by age.
        case phyllotaxis(colors: [SIMD4<Float>], background: SIMD4<Float>, count: Double,
                         dotSize: Double, phase: Double)
        /// Per-cell brightness pulses over a hexagonal lattice.
        case hexPulse(colors: [SIMD4<Float>], background: SIMD4<Float>, scale: Double,
                      gap: Double, phase: Double)
        /// The Chladni standing-wave field of a square plate, read as sand
        /// gathered on the nodal lines or as the breathing wave itself.
        case chladni(m: Double, n: Double, style: ChladniStyle, weight: Double,
                     grain: Double, foreground: SIMD4<Float>, background: SIMD4<Float>,
                     scale: Double, phase: Double)
        /// An escape-time fractal (Mandelbrot or Julia), colored by smooth
        /// iteration count through the palette. `mode` 0 = Mandelbrot, 1 = Julia.
        case escapeTime(colors: [SIMD4<Float>], interior: SIMD4<Float>, mode: Double,
                        c: Vector2, center: Vector2, zoom: Double, iterations: Double,
                        cycles: Double, phase: Double)
        /// The same escape-time iteration colored by the orbit's closest pass
        /// to a trap shape held in the plane, not by when it escapes.
        case orbitTrap(colors: [SIMD4<Float>], trap: OrbitTrap, mode: Double,
                       c: Vector2, center: Vector2, zoom: Double, iterations: Double,
                       glow: Double, angle: Double)
    }

    let kind: Kind

    /// A checkerboard, `scale` cells across the layer's width.
    public static func checkers(scale: Double = 8,
                                foreground: Color = .white,
                                background: Color = .black) -> Generator {
        Generator(kind: .checkers(scale: max(1, scale),
                                  foreground: foreground.linearRGBA,
                                  background: background.linearRGBA))
    }

    /// A line grid, `scale` cells across, each line `weight` (0…1) of a cell wide.
    public static func gridLines(scale: Double = 8, weight: Double = 0.1,
                                 foreground: Color = .black,
                                 background: Color = .white) -> Generator {
        Generator(kind: .gridLines(scale: max(1, scale), weight: min(max(weight, 0), 1),
                                   foreground: foreground.linearRGBA,
                                   background: background.linearRGBA))
    }

    /// Parallel bars, `scale` across; `vertical` runs them up the canvas (the
    /// default) or across it.
    public static func bars(scale: Double = 8, vertical: Bool = true,
                            foreground: Color = .black,
                            background: Color = .white) -> Generator {
        Generator(kind: .bars(scale: max(1, scale), vertical: vertical,
                              foreground: foreground.linearRGBA,
                              background: background.linearRGBA))
    }

    /// Fractal value noise, `scale` features across. `sharpness` runs from a soft
    /// cloud (0, blending the two colors) to a hard two-tone split (1). `warp`
    /// domain-warps the field (the layers displace their own sampling
    /// coordinates, twice over): 0 is the plain field, 1 the classic flowing
    /// marble-and-cloud smear, above 1 churn.
    public static func noise(scale: Double = 4, sharpness: Double = 0, warp: Double = 0,
                             foreground: Color = .white,
                             background: Color = .black) -> Generator {
        Generator(kind: .noise(scale: max(0.1, scale), sharpness: min(max(sharpness, 0), 1),
                               warp: min(max(warp, 0), 4),
                               foreground: foreground.linearRGBA,
                               background: background.linearRGBA))
    }

    /// The look a `cellular` generator paints from its cell distances.
    public enum CellularStyle: Sendable {
        /// The classic cell field: each cell dark at its core, brightening
        /// toward its walls (the nearest-point distance).
        case cells
        /// Thin foreground lines tracing the borders between cells (where the
        /// nearest and second-nearest distances meet): cracks and veins.
        case borders
        /// Every cell a flat hashed blend of the two colors: stained glass.
        case mosaic

        /// The shader's style index (kept in step with `ollin_gen_cellular`).
        var rawIndex: Float {
            switch self {
            case .cells: return 0
            case .borders: return 1
            case .mosaic: return 2
            }
        }
    }

    /// Worley cellular noise: space shaded into organic cells (stone, foam,
    /// cracked earth), `scale` cells across. `jitter` runs the cells from a
    /// regular grid (0) to fully organic (1), `style` picks the look (see
    /// `CellularStyle`), and `phase` makes the feature points wander on their
    /// own small orbits so the cells crawl and reform; it is periodic over 2π,
    /// so `phase: loopProgress(over: 12) * .tau` loops seamlessly (or feed it
    /// a slow multiple of `time` and never look back).
    public static func cellular(scale: Double = 8, jitter: Double = 1,
                                style: CellularStyle = .cells,
                                foreground: Color = .white,
                                background: Color = .black,
                                phase: Double = 0) -> Generator {
        Generator(kind: .cellular(scale: max(0.5, scale), jitter: min(max(jitter, 0), 1),
                                  style: style,
                                  foreground: foreground.linearRGBA,
                                  background: background.linearRGBA, phase: phase))
    }

    /// A user-supplied `Shader` as a procedural source layer: it reads no input and
    /// fills the layer from its `shade(uv, info)` function. Use it with `generate`.
    public static func shader(_ shader: Shader) -> Generator { Generator(kind: .shader(shader)) }

    // MARK: Design patterns

    /// The scalar field a `grainGradient` bands: a sloshing horizontal wave, a
    /// drifting soft dot grid, quarter-arc truchet tiles, a two-corner diagonal
    /// sweep, concentric ripples, an orbiting metaball blob, or a lit sphere.
    public enum GrainShape: Sendable {
        case wave, dots, truchet, corners, ripple, blob, sphere

        /// The shader's field index (kept in step with `ollin_gen_grain_gradient`).
        var rawIndex: Float {
            switch self {
            case .wave: return 0
            case .dots: return 1
            case .truchet: return 2
            case .corners: return 3
            case .ripple: return 4
            case .blob: return 5
            case .sphere: return 6
            }
        }
    }

    /// A mesh gradient: soft blobs of the given `colors` (2…8) drifting on
    /// independent orbits, blended by inverse-distance weighting so regions stay
    /// blobby-but-distinct, over a domain-warped field. `distortion` (0…1) is the
    /// organic smear, `swirl` (0…1) winds a vortex around the center, `mixing`
    /// (0…1) runs the blend from hard poster-like cells (0) through the classic
    /// mesh look (0.5) to a buttery wash (1), `grain`
    /// (0…1) dithers the color boundaries and adds a film-grain overlay, and
    /// `phase` drives the drift: feed it your `time`, or hold it fixed for a
    /// still composition.
    public static func meshGradient(colors: [Color] = [Color(hex: 0xE0EAFF), Color(hex: 0x241D9A),
                                                       Color(hex: 0xF75092), Color(hex: 0x9F50D3)],
                                    distortion: Double = 0.8, swirl: Double = 0.1,
                                    mixing: Double = 0.5, grain: Double = 0,
                                    phase: Double = 0) -> Generator {
        Generator(kind: .meshGradient(colors: colorRows(colors, max: 8),
                                      distortion: min(max(distortion, 0), 1),
                                      swirl: min(max(swirl, 0), 1),
                                      mixing: min(max(mixing, 0), 1),
                                      grain: min(max(grain, 0), 1), phase: phase))
    }

    /// A glowing web of thin filaments over a dark ground, the neural-lace /
    /// mycelium look, a cross-octave sine-feedback fractal. `color` paints the
    /// web, `highlight` its hot crossings, `scale` the filament frequency,
    /// `brightness`/`contrast` shape the tone curve, and `phase` makes it writhe
    /// (feed it your `time`).
    public static func filaments(color: Color = Color(hex: 0x47A6FF),
                                 highlight: Color = .white,
                                 background: Color = .black,
                                 scale: Double = 1, brightness: Double = 0.05,
                                 contrast: Double = 0.3, phase: Double = 0) -> Generator {
        Generator(kind: .filaments(color: color.linearRGBA, highlight: highlight.linearRGBA,
                                   background: background.linearRGBA, scale: max(0.05, scale),
                                   brightness: min(max(brightness, 0), 1),
                                   contrast: min(max(contrast, 0), 1), phase: phase))
    }

    /// A ring of smoke centered on the layer: wispy noise billowing outward,
    /// radially banded through `colors` (hottest band first). `radius` and
    /// `thickness` size the annulus (fractions of the layer), `fill` (0…4)
    /// softens the inner edge from crisp ring toward filled smoky disk, `scale`
    /// sets the wisp frequency, `detail` (1…8) the noise octaves, and `phase`
    /// billows it (feed it your `time`).
    public static func smokeRing(colors: [Color] = [.white], background: Color = .black,
                                 radius: Double = 0.25, thickness: Double = 0.65,
                                 fill: Double = 0.7, scale: Double = 3, detail: Double = 8,
                                 phase: Double = 0) -> Generator {
        Generator(kind: .smokeRing(colors: colorRows(colors, max: 8),
                                   background: background.linearRGBA,
                                   radius: max(0, radius), thickness: max(0.01, thickness),
                                   fill: min(max(fill, 0), 4), scale: min(max(scale, 0.01), 8),
                                   detail: min(max(detail, 1), 8), phase: phase))
    }

    /// Translucent color panes fanning around a central vertical axis in fake
    /// perspective, like sheets of colored acetate revolving through the frame.
    /// `density` spaces the panes apart, `length` stretches them, `skew` slants
    /// their side edges with depth, `blur` softens edges toward the axis,
    /// `fadeIn`/`fadeOut` dissolve the far and near ends, `gradient` blends each
    /// pane toward the next color along its depth, and `phase` revolves the fan
    /// (feed it your `time`).
    public static func colorPanels(colors: [Color] = [Color(hex: 0xFF9D00), Color(hex: 0xFD4F30),
                                                      Color(hex: 0x809BFF), Color(hex: 0x6D2EFF),
                                                      Color(hex: 0x333AFF), Color(hex: 0xF15CFF),
                                                      Color(hex: 0xFFD557)],
                                   background: Color = .black,
                                   density: Double = 3, length: Double = 1.1,
                                   skew: Double = 0, blur: Double = 0,
                                   fadeIn: Double = 1, fadeOut: Double = 0.3,
                                   gradient: Double = 0, phase: Double = 0) -> Generator {
        Generator(kind: .colorPanels(colors: colorRows(colors, max: 7),
                                     background: background.linearRGBA,
                                     density: min(max(density, 0.25), 7), length: max(0.05, length),
                                     skew: min(max(skew, -1), 1), blur: min(max(blur, 0), 0.5),
                                     fadeIn: min(max(fadeIn, 0), 1), fadeOut: min(max(fadeOut, 0), 1),
                                     gradient: min(max(gradient, 0), 1), phase: phase))
    }

    /// A two-color spiral. `density` (0…1) eases the turns from even (1) toward
    /// a compressed whirlpool center (below 1), `distortion` bends the arms,
    /// `strokeWidth` (0…1) balances stroke against gap, `taper` thins the stroke
    /// outward, `cap` (0…1) rounds the innermost turn into a dot, `noise` +
    /// `noiseScale` wobble the arms hand-drawn, `softness` blurs the edges,
    /// `scale` sets how many turns fill the layer, and `phase` rotates it (feed
    /// it your `time`).
    public static func spiral(foreground: Color = Color(hex: 0x79D1FF),
                              background: Color = Color(hex: 0x001429),
                              density: Double = 1, distortion: Double = 0,
                              strokeWidth: Double = 0.5, taper: Double = 0, cap: Double = 0,
                              noise: Double = 0, noiseScale: Double = 0.5,
                              softness: Double = 0, scale: Double = 1,
                              phase: Double = 0) -> Generator {
        Generator(kind: .spiral(foreground: foreground.linearRGBA, background: background.linearRGBA,
                                density: min(max(density, 0), 1), distortion: min(max(distortion, 0), 1),
                                strokeWidth: min(max(strokeWidth, 0), 1), taper: min(max(taper, 0), 1),
                                cap: min(max(cap, 0), 1), noise: min(max(noise, 0), 1),
                                noiseScale: min(max(noiseScale, 0), 1),
                                softness: min(max(softness, 0), 1), scale: max(0.05, scale),
                                phase: phase))
    }

    /// Horizontal wavy-line stripes. `shape` (0…3) morphs the wave profile from
    /// zigzag (0) through sine (1) to two irregular mixes (2, 3), `frequency`
    /// and `amplitude` shape the waves, `spacing` sets the stripe pitch,
    /// `proportion` (0…1) the ink-to-gap balance, `softness` blurs the edges,
    /// and `phase` scrolls the pattern sideways (feed it your `time`).
    public static func waves(foreground: Color = Color(hex: 0xFFBB00), background: Color = .black,
                             shape: Double = 0, frequency: Double = 0.5,
                             amplitude: Double = 0.5, spacing: Double = 1.2,
                             proportion: Double = 0.1, softness: Double = 0,
                             scale: Double = 1, phase: Double = 0) -> Generator {
        Generator(kind: .waves(foreground: foreground.linearRGBA, background: background.linearRGBA,
                               shape: min(max(shape, 0), 3), frequency: min(max(frequency, 0), 2),
                               amplitude: min(max(amplitude, 0), 1), spacing: max(0.05, spacing),
                               proportion: min(max(proportion, 0), 1),
                               softness: min(max(softness, 0), 1), scale: max(0.05, scale),
                               phase: phase))
    }

    /// A grid of dots, every dot orbiting its own cell center on its own phase
    /// and precession: halftone confetti in motion. Dots pick their color from
    /// `colors` quantized to `steps` flat shades per stop, `size` and
    /// `sizeVariation` set the dot radii, `spread` how far they roam, `scale`
    /// the cell density, and `phase` drives the orbits (feed it your `time`).
    public static func dotOrbit(colors: [Color] = [Color(hex: 0xFFC96B), Color(hex: 0xFF6200),
                                                   Color(hex: 0xFF2F00), Color(hex: 0x421100),
                                                   Color(hex: 0x1A0000)],
                                background: Color = .black,
                                scale: Double = 1, size: Double = 1, sizeVariation: Double = 0,
                                spread: Double = 1, steps: Double = 4,
                                phase: Double = 0) -> Generator {
        Generator(kind: .dotOrbit(colors: colorRows(colors, max: 8),
                                  background: background.linearRGBA, scale: max(0.05, scale),
                                  size: min(max(size, 0), 1),
                                  sizeVariation: min(max(sizeVariation, 0), 1),
                                  spread: min(max(spread, 0), 1), steps: min(max(steps, 1), 4),
                                  phase: phase))
    }

    /// Poster-style banded gradients over an animated scalar field, the band
    /// edges chewed by film grain. `shape` picks the field, `softness` runs the
    /// bands from hard posterized cuts (0) to a smooth gradient (1), `intensity`
    /// is how far the grain tears the band boundaries, `noise` adds granular
    /// sparkle, and `phase` animates the field (feed it your `time`).
    public static func grainGradient(colors: [Color] = [Color(hex: 0x7300FF), Color(hex: 0xEBA8FF),
                                                        Color(hex: 0x00BFFF), Color(hex: 0x2A00FF)],
                                     background: Color = .black,
                                     shape: GrainShape = .corners,
                                     softness: Double = 0.5, intensity: Double = 0.5,
                                     noise: Double = 0.25, phase: Double = 0) -> Generator {
        Generator(kind: .grainGradient(colors: colorRows(colors, max: 7),
                                       background: background.linearRGBA, shape: shape,
                                       softness: min(max(softness, 0), 1),
                                       intensity: min(max(intensity, 0), 1),
                                       noise: min(max(noise, 0), 1), phase: phase))
    }

    /// A glowing rounded border hugging the layer's edges (inset by `margins`,
    /// in layer pixels), with up to eight light
    /// spots per color racing the perimeter, an optional heartbeat `pulse`,
    /// additive `bloom`, and smoke wisps bleeding inward. `roundness` and
    /// `thickness` shape the border, `softness` feathers it, `intensity` scales
    /// the glow, and `phase` drives the motion (feed it your `time`).
    public static func pulsingBorder(colors: [Color] = [Color(hex: 0x0DC1FD), Color(hex: 0xD915EF),
                                                        Color(hex: 0xFF3F2E, alpha: 0.8)],
                                     background: Color = .black,
                                     roundness: Double = 0.25, thickness: Double = 0.1,
                                     softness: Double = 0.75, intensity: Double = 0.2,
                                     bloom: Double = 0.25, spots: Double = 4,
                                     spotSize: Double = 0.5, pulse: Double = 0.25,
                                     smoke: Double = 0.3, smokeScale: Double = 0.6,
                                     margins: Insets = .zero,
                                     phase: Double = 0) -> Generator {
        Generator(kind: .pulsingBorder(colors: colorRows(colors, max: 5),
                                       background: background.linearRGBA,
                                       roundness: min(max(roundness, 0), 1),
                                       thickness: min(max(thickness, 0.01), 1),
                                       softness: min(max(softness, 0), 1),
                                       intensity: min(max(intensity, 0), 1),
                                       bloom: min(max(bloom, 0), 1),
                                       spots: min(max(spots, 1), 8),
                                       spotSize: min(max(spotSize, 0), 1),
                                       pulse: min(max(pulse, 0), 1),
                                       smoke: min(max(smoke, 0), 1),
                                       smokeScale: min(max(smokeScale, 0.05), 1),
                                       margins: margins, phase: phase))
    }

    /// Crepuscular rays streaming from a point, one drifting streak layer per
    /// color. `x`/`y` place the source (fractions of the layer), `density` sets
    /// the ray count, `breakup` chops streaks into dashes, `coreSize`/
    /// `coreIntensity` shape the central glow, `bloom` morphs the layers from
    /// alpha stacking toward additive light (`bloomTint` washes an extra glow
    /// color over the lit areas), and `phase` streams them outward
    /// (feed it your `time`).
    public static func godRays(colors: [Color] = [Color(hex: 0xA600FF, alpha: 0.43),
                                                  Color(hex: 0x6200FF, alpha: 0.94),
                                                  .white, Color(hex: 0x33FFF5)],
                               background: Color = .black,
                               x: Double = 0.5, y: Double = 0.05,
                               density: Double = 0.3, breakup: Double = 0.3,
                               coreSize: Double = 0.2, coreIntensity: Double = 0.4,
                               intensity: Double = 0.8, bloom: Double = 0.4,
                               bloomTint: Color = .clear,
                               phase: Double = 0) -> Generator {
        Generator(kind: .godRays(colors: colorRows(colors, max: 5),
                                 background: background.linearRGBA, x: x, y: y,
                                 density: min(max(density, 0), 1), breakup: min(max(breakup, 0), 1),
                                 coreSize: min(max(coreSize, 0), 1),
                                 coreIntensity: min(max(coreIntensity, 0), 1),
                                 intensity: min(max(intensity, 0), 1),
                                 bloom: min(max(bloom, 0), 1),
                                 bloomTint: bloomTint.linearRGBA, phase: phase))
    }
    // MARK: Pattern fields

    /// A quasicrystal: `symmetry` plane waves at evenly spaced angles, summed.
    /// One wave is stripes; the sum is a pattern that is ordered but never
    /// repeats, with crisp `symmetry`-fold stars around its bright centers.
    /// The summed field walks `colors` (first stop = the wave troughs), `scale`
    /// sets the wave frequency, `contrast` sharpens the walk from soft wash (0)
    /// toward hard rings (1), and `phase` makes the whole crystal shimmer
    /// (feed it your `time`).
    public static func quasicrystal(colors: [Color] = [Color(hex: 0x0B1026), Color(hex: 0x24457C),
                                                       Color(hex: 0x4FB6E8), Color(hex: 0xF2E8DC)],
                                    background: Color = .black,
                                    symmetry: Double = 7, scale: Double = 1,
                                    contrast: Double = 0.5, phase: Double = 0) -> Generator {
        Generator(kind: .quasicrystal(colors: colorRows(colors, max: 8),
                                      background: background.linearRGBA,
                                      symmetry: min(max(symmetry.rounded(), 3), 12),
                                      scale: min(max(scale, 0.05), 8),
                                      contrast: min(max(contrast, 0), 1), phase: phase))
    }

    /// Moiré interference: `sources` concentric ring gratings on slowly
    /// orbiting centers. Each grating alone is even rings; where they overlap,
    /// their beat sweeps out the large slow fringes the eye actually sees.
    /// `frequency` is the ring count (finer rings give finer fringes), and
    /// `phase` drifts the centers (feed it your `time`; the fringes move much
    /// faster than the centers do, which is the effect's magic).
    public static func moire(foreground: Color = Color(hex: 0x14181F),
                             background: Color = Color(hex: 0xF2EEE4),
                             sources: Double = 3, frequency: Double = 24,
                             scale: Double = 1, phase: Double = 0) -> Generator {
        Generator(kind: .moire(foreground: foreground.linearRGBA,
                               background: background.linearRGBA,
                               sources: min(max(sources.rounded(), 2), 5),
                               frequency: min(max(frequency, 2), 120),
                               scale: min(max(scale, 0.05), 8), phase: phase))
    }

    /// A gyroid slice: the zero-set of the gyroid (a surface that divides space
    /// into two interlocking labyrinths) cut by a plane, drawn as interwoven
    /// organic bands with a dimmed echo for depth. `scale` is the cell count
    /// across, `thickness` the band weight, and `phase` sweeps the slicing
    /// plane through the surface so the bands crawl and reconnect (feed it
    /// your `time`).
    public static func gyroid(foreground: Color = Color(hex: 0xE8DCC8),
                              background: Color = Color(hex: 0x101820),
                              scale: Double = 3, thickness: Double = 0.35,
                              phase: Double = 0) -> Generator {
        Generator(kind: .gyroid(foreground: foreground.linearRGBA,
                                background: background.linearRGBA,
                                scale: min(max(scale, 0.25), 16),
                                thickness: min(max(thickness, 0.02), 1), phase: phase))
    }

    /// A phyllotaxis field: the sunflower's seed arrangement (each floret at
    /// the golden angle past the one before, radius growing by the square
    /// root), evaluated per pixel as a field of dots. `count` is how many
    /// florets fill the layer, `dotSize` their size relative to the local
    /// spacing (past ~1 they fuse into a cellular texture), colors walk from
    /// the center's oldest florets to the rim's newest, and `phase` spins the
    /// whole head (feed it a slow multiple of `time`).
    public static func phyllotaxis(colors: [Color] = [Color(hex: 0xF2B36A), Color(hex: 0xE4572E),
                                                      Color(hex: 0x7C3B5E)],
                                   background: Color = Color(hex: 0x140F14),
                                   count: Double = 700, dotSize: Double = 0.55,
                                   phase: Double = 0) -> Generator {
        Generator(kind: .phyllotaxis(colors: colorRows(colors, max: 8),
                                     background: background.linearRGBA,
                                     count: min(max(count, 20), 4000),
                                     dotSize: min(max(dotSize, 0.05), 2), phase: phase))
    }

    /// Per-cell pulses over a hexagonal lattice: every hex breathes on its own
    /// hashed rhythm, brightness (and a little size) riding the pulse, its
    /// color a hashed pick from `colors`. `scale` is the cell count across,
    /// `gap` the grout between cells, and `phase` drives the pulsing (feed it
    /// your `time`).
    public static func hexPulse(colors: [Color] = [Color(hex: 0x1F7A6B), Color(hex: 0x2B6C8C),
                                                   Color(hex: 0xE8B44A), Color(hex: 0xB8442C)],
                                background: Color = Color(hex: 0x0C1014),
                                scale: Double = 8, gap: Double = 0.1,
                                phase: Double = 0) -> Generator {
        Generator(kind: .hexPulse(colors: colorRows(colors, max: 8),
                                  background: background.linearRGBA,
                                  scale: min(max(scale, 1), 64),
                                  gap: min(max(gap, 0), 0.9), phase: phase))
    }

    /// The look a `chladni` generator paints from the standing-wave field.
    public enum ChladniStyle: Sendable {
        /// Sand gathered along the nodal lines: the classic figure, grains
        /// accumulating where the plate stands still.
        case sand
        /// The signed wave itself: antinodes breathing between the two colors
        /// with `phase` while the nodal lines hold still.
        case wave

        /// The shader's style index (kept in step with `ollin_gen_chladni`).
        var rawIndex: Float {
            switch self {
            case .sand: return 0
            case .wave: return 1
            }
        }
    }

    /// A **Chladni figure**: the standing-wave field of a vibrating square
    /// plate, the symmetric line drawing sand traces as it gathers along the
    /// still (nodal) lines. `m` and `n` are the mode numbers: integers ring
    /// true modes (higher, finer), fractional values morph smoothly between
    /// figures, and `m == n` cancels to a still plate (no figure). `style`
    /// picks the reading (see `ChladniStyle`): for `.sand`, `weight` is the
    /// gather width around the nodes and `grain` runs the lines from smooth
    /// ink (0) to loose sand speckle (1), re-thrown as `phase` advances so the
    /// grains shiver on the ringing plate; for `.wave`, `phase` breathes the
    /// antinodes through a full swing per 2π. `scale` above 1 tiles mirrored
    /// plates. The CPU sibling `chladni(_:_:m:n:)` is the same field for
    /// geometry (nodal isolines, settling particles).
    public static func chladni(m: Double = 5, n: Double = 2,
                               style: ChladniStyle = .sand,
                               weight: Double = 0.12, grain: Double = 0.5,
                               foreground: Color = Color(hex: 0xE8DCC8),
                               background: Color = Color(hex: 0x14181F),
                               scale: Double = 1, phase: Double = 0) -> Generator {
        Generator(kind: .chladni(m: min(max(m, 0), 32), n: min(max(n, 0), 32),
                                 style: style,
                                 weight: min(max(weight, 0.01), 1),
                                 grain: min(max(grain, 0), 1),
                                 foreground: foreground.linearRGBA,
                                 background: background.linearRGBA,
                                 scale: min(max(scale, 0.05), 8), phase: phase))
    }

    // MARK: Escape-time fractals

    /// The **Mandelbrot set**: iterate z = z² + c from zero at every pixel's c
    /// and color by how fast the orbit escapes, banded through `colors` (the
    /// smooth-iteration coloring, so the bands are stepless). Points that never
    /// escape are the set itself, painted `interior`. `center` and `zoom` frame
    /// the complex plane (zoom 1 shows the whole set; useful detail holds to a
    /// few thousand times in), `iterations` caps the orbit (raise it as you zoom),
    /// `cycles` is how many palette laps the bands make, and `phase` cycles the
    /// colors along the bands (feed it your `time`).
    public static func mandelbrot(colors: [Color] = [Color(hex: 0x0B1026), Color(hex: 0x2B6C8C),
                                                     Color(hex: 0xE8B44A), Color(hex: 0xF2E8DC)],
                                  interior: Color = .black,
                                  center: Vector2 = Vector2(-0.6, 0), zoom: Double = 1,
                                  iterations: Double = 150, cycles: Double = 3,
                                  phase: Double = 0) -> Generator {
        Generator(kind: .escapeTime(colors: colorRows(colors, max: 8),
                                    interior: interior.linearRGBA, mode: 0,
                                    c: .zero, center: center,
                                    zoom: min(max(zoom, 0.1), 100_000),
                                    iterations: min(max(iterations, 8), 400),
                                    cycles: min(max(cycles, 0.25), 24), phase: phase))
    }

    /// A **Julia set**: the same z = z² + c iteration as the Mandelbrot set, but
    /// `c` is fixed and every pixel starts the orbit at its own point, so each
    /// `c` yields a different filigree (points from just inside the Mandelbrot
    /// set's edge give the richest ones). Animate `c` a little and the whole
    /// form morphs. Framing, coloring, and `phase` work as in `mandelbrot`.
    public static func julia(c: Vector2 = Vector2(-0.79, 0.15),
                             colors: [Color] = [Color(hex: 0x0B1026), Color(hex: 0x2B6C8C),
                                                Color(hex: 0xE8B44A), Color(hex: 0xF2E8DC)],
                             interior: Color = .black,
                             center: Vector2 = .zero, zoom: Double = 1.2,
                             iterations: Double = 150, cycles: Double = 3,
                             phase: Double = 0) -> Generator {
        Generator(kind: .escapeTime(colors: colorRows(colors, max: 8),
                                    interior: interior.linearRGBA, mode: 1,
                                    c: c, center: center,
                                    zoom: min(max(zoom, 0.1), 100_000),
                                    iterations: min(max(iterations, 8), 400),
                                    cycles: min(max(cycles, 0.25), 24), phase: phase))
    }

    /// The shape an `orbitTrap` generator measures the orbit against, placed in
    /// the same complex plane the fractal lives in (the whole Mandelbrot set
    /// spans about x -2…1, y -1.5…1.5 at zoom 1).
    public enum OrbitTrap: Sendable {
        /// A single point: orbits that pass near it light up as soft knots.
        case point(Vector2)
        /// A horizontal and a vertical line crossing at the point: the classic
        /// stalk look, filaments sprouting wherever an orbit grazes an axis.
        case cross(Vector2)
        /// A circle outline of `radius` around `center`: orbits light up where
        /// they skim the ring, from either side.
        case circle(center: Vector2, radius: Double)
        /// A square outline of half-width `radius` around `center`.
        case square(center: Vector2, radius: Double)

        /// The shader's trap index (kept in step with `ollin_gen_orbittrap`).
        var rawIndex: Float {
            switch self {
            case .point: return 0
            case .cross: return 1
            case .circle: return 2
            case .square: return 3
            }
        }

        /// Where the trap sits in the plane.
        var trapCenter: Vector2 {
            switch self {
            case .point(let p), .cross(let p): return p
            case .circle(let c, _), .square(let c, _): return c
            }
        }

        /// The outline's size, for the shapes that have one.
        var trapRadius: Double {
            switch self {
            case .point, .cross: return 0
            case .circle(_, let r), .square(_, let r): return max(0, r)
            }
        }
    }

    /// An **orbit trap**: the same z = z² + c iteration as `mandelbrot` and
    /// `julia`, but each pixel is colored by how *close* its orbit ever came to
    /// a `trap` shape held in the plane, not by when it escaped. Orbits that
    /// graze the trap glow through the last of `colors`; ones that stay far
    /// read as the first, so filaments (Pickover's stalks) trace where orbits
    /// wander near the shape. Pass `c: nil` for the Mandelbrot plane or a fixed
    /// `c` for that Julia set. `glow` is the distance (in plane units) over
    /// which the light falls off, `angle` turns the trap about its own center
    /// (feed it your `time` and the stalks sweep), and `center`/`zoom`/
    /// `iterations` frame the plane as in `mandelbrot` (`center: nil` frames
    /// whichever set `c` picked).
    public static func orbitTrap(_ trap: OrbitTrap = .cross(.zero),
                                 c: Vector2? = nil,
                                 colors: [Color] = [Color(hex: 0x0B1026), Color(hex: 0x2B6C8C),
                                                    Color(hex: 0xE8B44A), Color(hex: 0xF2E8DC)],
                                 center: Vector2? = nil, zoom: Double = 1,
                                 iterations: Double = 150, glow: Double = 0.08,
                                 angle: Double = 0) -> Generator {
        Generator(kind: .orbitTrap(colors: colorRows(colors, max: 8), trap: trap,
                                   mode: c == nil ? 0 : 1, c: c ?? .zero,
                                   center: center ?? (c == nil ? Vector2(-0.6, 0) : .zero),
                                   zoom: min(max(zoom, 0.1), 100_000),
                                   iterations: min(max(iterations, 8), 400),
                                   glow: min(max(glow, 0.001), 4), angle: angle))
    }
}

/// Clamp a palette to `max` stops (at least one) as linear RGBA rows, the form
/// the pattern generators upload.
private func colorRows(_ colors: [Color], max maxCount: Int) -> [SIMD4<Float>] {
    let capped = colors.isEmpty ? [Color.white] : Array(colors.prefix(maxCount))
    return capped.map(\.linearRGBA)
}
