import Metal

/// How a shape's color combines with what's already on the canvas.
///
/// The default, `.normal`, lays each shape over the previous ones (a
/// translucent shape shows what's beneath it). The other modes *combine* the
/// new color with the destination instead of replacing it — the headline being
/// `.add`, which sums colors as light so overlapping marks brighten toward
/// white. That additive accumulation is what light-field and particle sketches
/// want: a thousand faint dots pile into a glow rather than the topmost one
/// winning.
///
/// Blend mode is drawing state, set with `blendMode(_:)` and saved/restored by
/// `withState { }` like `fill` or `tint`. It applies to every shape drawn while
/// it's active — the analytic SDF shapes, the tessellated paths, images, and
/// text alike.
///
/// Because the canvas blends in linear light (see the gamma-correct pipeline),
/// `.add` sums physically: two half-bright reds make a full-bright red, the way
/// two lights would. Set against a dark background, additive drawing reads as
/// glowing accumulation; the brighter modes (`.screen`, `.lightest`) lighten,
/// the darker ones (`.multiply`, `.darkest`) deepen.
public enum BlendMode: Hashable, Sendable, CaseIterable {

    /// Lay the shape over the canvas, the new color showing through by its alpha
    /// (the default — ordinary source-over compositing).
    case normal

    /// Sum the shape's color with the canvas, so overlapping marks brighten
    /// toward white. The mode light-accumulation and particle sketches use;
    /// best against a dark background.
    case add

    /// Subtract the shape's color from the canvas, darkening where marks
    /// overlap (the inverse of `.add`).
    case subtract

    /// Multiply the shape's color into the canvas, darkening (white leaves the
    /// canvas unchanged, black drives it to black) — like stacked ink or gels.
    case multiply

    /// Invert, multiply, invert — the optical opposite of `.multiply`. Always
    /// lightens (black leaves the canvas unchanged, white drives it to white),
    /// like overlapping projected light.
    case screen

    /// Keep the lighter of the shape and the canvas, channel by channel.
    case lightest

    /// Keep the darker of the shape and the canvas, channel by channel.
    case darkest
}

extension BlendMode {
    /// The fixed-function blend descriptor for this mode, resolved against the
    /// pipeline's alpha convention. `premultiplied` is true for the textured
    /// (image) path, whose fragment outputs premultiplied color, and false for
    /// the straight-alpha paths (solid, SDF, glyph). `.normal` reproduces the
    /// renderer's original factors exactly, so existing renders are unchanged.
    ///
    /// Two rules hold across the table. A color reaches the blend weighted by
    /// its coverage: the ordinary and the additive blend, and the subtraction,
    /// weight a straight color in their own source factor, and the other four
    /// cannot, so their pipelines build the fragment in the form
    /// `fragmentForm` names. And the surface's alpha stays a coverage: a mode
    /// that lightens (add, screen, lightest) covers as an ordinary shape does,
    /// by the over rule, so over nothing it leaves the shape itself; a mode
    /// that darkens (subtract, multiply, darkest) acts on what is already
    /// there and leaves its coverage alone, so over nothing it leaves nothing.
    struct BlendState {
        var colorOperation: MTLBlendOperation
        var alphaOperation: MTLBlendOperation
        var sourceColor: MTLBlendFactor
        var destinationColor: MTLBlendFactor
        var sourceAlpha: MTLBlendFactor
        var destinationAlpha: MTLBlendFactor
    }

    func blendState(premultiplied: Bool) -> BlendState {
        // The source-color factor that scales a fragment by its own coverage.
        // Premultiplied fragments already carry alpha baked in, so they scale by
        // `.one`; straight-alpha fragments scale by `.sourceAlpha`.
        let byCoverage: MTLBlendFactor = premultiplied ? .one : .sourceAlpha
        switch self {
        case .normal:
            return BlendState(colorOperation: .add, alphaOperation: .add,
                              sourceColor: byCoverage, destinationColor: .oneMinusSourceAlpha,
                              sourceAlpha: .one, destinationAlpha: .oneMinusSourceAlpha)
        case .add:
            // The light is summed whole; the coverage is the over rule's, so a
            // layer of added marks never holds an alpha past 1.
            return BlendState(colorOperation: .add, alphaOperation: .add,
                              sourceColor: byCoverage, destinationColor: .one,
                              sourceAlpha: .one, destinationAlpha: .oneMinusSourceAlpha)
        case .subtract:
            return BlendState(colorOperation: .reverseSubtract, alphaOperation: .add,
                              sourceColor: byCoverage, destinationColor: .one,
                              sourceAlpha: .zero, destinationAlpha: .one)
        case .multiply:
            // s * d + d * (1 - a), the fragment's color already weighted (form 1).
            return BlendState(colorOperation: .add, alphaOperation: .add,
                              sourceColor: .destinationColor, destinationColor: .oneMinusSourceAlpha,
                              sourceAlpha: .zero, destinationAlpha: .one)
        case .screen:
            // s + d - s * d, the fragment's color already weighted (form 1).
            return BlendState(colorOperation: .add, alphaOperation: .add,
                              sourceColor: .oneMinusDestinationColor, destinationColor: .one,
                              sourceAlpha: .one, destinationAlpha: .oneMinusSourceAlpha)
        case .lightest:
            // The maximum ignores its factors; the fragment's color is the
            // shape over black (form 2).
            return BlendState(colorOperation: .max, alphaOperation: .add,
                              sourceColor: .one, destinationColor: .one,
                              sourceAlpha: .one, destinationAlpha: .oneMinusSourceAlpha)
        case .darkest:
            // The minimum ignores its factors; the fragment's color is the
            // shape over white (form 3).
            return BlendState(colorOperation: .min, alphaOperation: .add,
                              sourceColor: .one, destinationColor: .one,
                              sourceAlpha: .zero, destinationAlpha: .one)
        }
    }

    /// The form a fragment hands its color to this mode's blend in: the value
    /// of the `kOllinBlendForm` function constant its pipeline is built with
    /// (see *What a fragment hands the blend* in OllinShaderLib.metal). 0 is
    /// the color as written, 1 weighted by coverage, 2 the same for the
    /// maximum, 3 the shape as it lies over white for the minimum.
    var fragmentForm: Int32 {
        switch self {
        case .normal, .add, .subtract: 0
        case .multiply, .screen: 1
        case .lightest: 2
        case .darkest: 3
        }
    }
}
