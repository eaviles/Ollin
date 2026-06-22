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
}
