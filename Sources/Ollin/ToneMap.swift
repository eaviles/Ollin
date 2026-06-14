/// How high-dynamic-range color is mapped into the displayable 0…1 range.
///
/// The canvas composites in a linear, floating-point intermediate, so color can
/// run past 1.0 — additive light piling up on a `noClear` surface, a bright
/// gradient, a glow. A tone-map decides what happens to those out-of-range
/// values when the frame is shown on an ordinary 8-bit screen.
///
/// By default a sketch is in `.clamp`: anything above 1.0 is simply clipped, the
/// way a standard renderer behaves, so existing sketches look unchanged. Call
/// `toneMap(_:)` to opt into a curve that *rolls* highlights off instead — the
/// difference between blown-out white where light accumulates and a soft,
/// photographic falloff. `exposure` scales the whole image first, so it reads
/// like a camera's brightness dial: turn it up to pull faint accumulation into
/// view, down to tame a scene that saturates.
///
/// It's a frame-wide setting, not per-shape state: one mapping is applied to the
/// finished frame, so unlike `fill` or `blendMode` it isn't saved by
/// `withState { }`. Set it once in `setup()` (it persists until changed).
public enum ToneMap: Hashable, Sendable, CaseIterable {

    /// Clip values to [0, 1] (the default). The standard-dynamic-range look:
    /// anything brighter than full saturates to white, exactly as before the
    /// float pipeline. An in-range frame is rendered identically to `.clamp`.
    case clamp

    /// Reinhard tone-mapping, `x / (1 + x)` per channel: a simple curve that
    /// compresses every value into [0, 1), so highlights never fully clip. Cheap
    /// and gentle; tends to desaturate bright areas.
    case reinhard

    /// ACES filmic tone-mapping: a film-like S-curve that rolls highlights off
    /// while keeping contrast and saturation in the midtones. The richer choice
    /// for glow and light-accumulation looks.
    case aces

    /// The value passed to the present shader's `toneMapMode` (see
    /// `OllinPresentUniforms`). Kept in sync with the `if`-ladder there.
    var shaderIndex: Int32 {
        switch self {
        case .clamp:    return 0
        case .reinhard: return 1
        case .aces:     return 2
        }
    }
}
