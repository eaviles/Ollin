/// A coarse quality dial — three intent tiers — shared across the rendering knobs that
/// trade fidelity for frame rate (today the soft-shadow ray count; the same shape fits
/// future ones like blur or ambient-occlusion sample counts).
///
/// The tiers are **relative to the GPU**: a feature maps each one to a concrete setting
/// chosen for the hardware it's running on, the way a game's quality presets scale to your
/// machine. So `.default` is the balanced choice on whatever GPU you have — the frame-rate-
/// safe count on a software-ray-tracing GPU (M1/M2), a richer one on a hardware-RT GPU (M3
/// and up) — and a sketch that does nothing gets nicer shadows for free on better hardware.
/// `.performance` favors frame rate, `.detail` favors visual quality. For an exact, hardware-
/// independent value use the feature's raw setter instead (for shadows, `Sketch.shadowSamples`).
public enum RenderQuality: Sendable, Equatable, CaseIterable {
    /// Favor frame rate.
    case performance
    /// The balanced, recommended choice for the hardware (the default).
    case `default`
    /// Favor visual quality.
    case detail
}

/// The soft-shadow quality intent a sketch sets: a hardware-relative `RenderQuality` tier
/// (the renderer turns it into a concrete ray count for the GPU it's on) or an exact ray
/// count (hardware-independent). Default is `.tier(.default)`.
enum ShadowQualitySetting: Sendable, Equatable {
    case tier(RenderQuality)
    case absolute(Int)
}
