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
        case noise(scale: Double, sharpness: Double, foreground: SIMD4<Float>, background: SIMD4<Float>)
        /// A user-supplied `Shader` run as a source layer (it reads no input).
        case shader(Shader)

        // Design patterns ------------------------------------------------------
        /// Soft color blobs drifting on orbits, blended by inverse-distance
        /// weighting over a domain-warped, optionally swirled field.
        case meshGradient(colors: [SIMD4<Float>], distortion: Double, swirl: Double,
                          grain: Double, phase: Double)
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
                           smoke: Double, smokeScale: Double, phase: Double)
        /// Crepuscular rays streaming from a point, layered per color.
        case godRays(colors: [SIMD4<Float>], background: SIMD4<Float>, x: Double, y: Double,
                     density: Double, breakup: Double, coreSize: Double,
                     coreIntensity: Double, intensity: Double, bloom: Double, phase: Double)
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
    /// cloud (0, blending the two colors) to a hard two-tone split (1).
    public static func noise(scale: Double = 4, sharpness: Double = 0,
                             foreground: Color = .white,
                             background: Color = .black) -> Generator {
        Generator(kind: .noise(scale: max(0.1, scale), sharpness: min(max(sharpness, 0), 1),
                               foreground: foreground.linearRGBA,
                               background: background.linearRGBA))
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
    /// organic smear, `swirl` (0…1) winds a vortex around the center, `grain`
    /// (0…1) dithers the color boundaries and adds a film-grain overlay, and
    /// `phase` drives the drift: feed it your `time`, or hold it fixed for a
    /// still composition.
    public static func meshGradient(colors: [Color] = [Color(hex: 0xE0EAFF), Color(hex: 0x241D9A),
                                                       Color(hex: 0xF75092), Color(hex: 0x9F50D3)],
                                    distortion: Double = 0.8, swirl: Double = 0.1,
                                    grain: Double = 0, phase: Double = 0) -> Generator {
        Generator(kind: .meshGradient(colors: colorRows(colors, max: 8),
                                      distortion: min(max(distortion, 0), 1),
                                      swirl: min(max(swirl, 0), 1),
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

    /// A glowing rounded border hugging the layer's edges, with up to four light
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
                                     phase: Double = 0) -> Generator {
        Generator(kind: .pulsingBorder(colors: colorRows(colors, max: 5),
                                       background: background.linearRGBA,
                                       roundness: min(max(roundness, 0), 1),
                                       thickness: min(max(thickness, 0.01), 1),
                                       softness: min(max(softness, 0), 1),
                                       intensity: min(max(intensity, 0), 1),
                                       bloom: min(max(bloom, 0), 1),
                                       spots: min(max(spots, 1), 4),
                                       spotSize: min(max(spotSize, 0), 1),
                                       pulse: min(max(pulse, 0), 1),
                                       smoke: min(max(smoke, 0), 1),
                                       smokeScale: min(max(smokeScale, 0.05), 1), phase: phase))
    }

    /// Crepuscular rays streaming from a point, one drifting streak layer per
    /// color. `x`/`y` place the source (fractions of the layer), `density` sets
    /// the ray count, `breakup` chops streaks into dashes, `coreSize`/
    /// `coreIntensity` shape the central glow, `bloom` morphs the layers from
    /// alpha stacking toward additive light, and `phase` streams them outward
    /// (feed it your `time`).
    public static func godRays(colors: [Color] = [Color(hex: 0xA600FF, alpha: 0.43),
                                                  Color(hex: 0x6200FF, alpha: 0.94),
                                                  .white, Color(hex: 0x33FFF5)],
                               background: Color = .black,
                               x: Double = 0.5, y: Double = 0.05,
                               density: Double = 0.3, breakup: Double = 0.3,
                               coreSize: Double = 0.2, coreIntensity: Double = 0.4,
                               intensity: Double = 0.8, bloom: Double = 0.4,
                               phase: Double = 0) -> Generator {
        Generator(kind: .godRays(colors: colorRows(colors, max: 5),
                                 background: background.linearRGBA, x: x, y: y,
                                 density: min(max(density, 0), 1), breakup: min(max(breakup, 0), 1),
                                 coreSize: min(max(coreSize, 0), 1),
                                 coreIntensity: min(max(coreIntensity, 0), 1),
                                 intensity: min(max(intensity, 0), 1),
                                 bloom: min(max(bloom, 0), 1), phase: phase))
    }
}

/// Clamp a palette to `max` stops (at least one) as linear RGBA rows, the form
/// the pattern generators upload.
private func colorRows(_ colors: [Color], max maxCount: Int) -> [SIMD4<Float>] {
    let capped = colors.isEmpty ? [Color.white] : Array(colors.prefix(maxCount))
    return capped.map(\.linearRGBA)
}
