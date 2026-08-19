/// A coarse quality dial (three intent tiers) shared across the rendering knobs that trade
/// fidelity for frame rate: soft-shadow ray count, depth-of-field bokeh taps, ambient-occlusion
/// samples, and the raymarched-3D-SDF render resolution. A feature maps each tier to a concrete
/// setting tuned for the frame-rate band it should hold (`.performance` ~120fps, `.default`
/// 60–90fps, `.detail` 15–30fps, measured per GPU; `Scripts/benchmark.sh` recommends the
/// values), and where a GPU affords more (a hardware-RT GPU vs software-RT) the same tier lifts
/// on its own, like a game's quality presets.
///
/// **`.default` doubles as "automatic":** a feature left at `.default` follows the *render
/// path*, resolving to `.default` on the live window (frame-rate-safe) and `.detail` on
/// `--export`/headless (no frame-rate pressure, so best quality; the `--render-quality` flag
/// overrides it). A sketch that dials a *non-default* tier is making an explicit choice and is
/// honored on every path. For an exact, hardware-independent value use the feature's raw setter
/// instead (for shadows, `Sketch.shadowSamples`; for the raymarch, `Sketch.raymarchSteps`).
///
/// **Scope: GPU sampling budgets only.** Every consumer trades sampling density for frame rate
/// on the *same* image, which is what makes the export auto-upgrade safe. Dials that change
/// generated *geometry* (a growth's `maxVertices`, `subdivided(_:levels:)`, an isosurface's
/// `resolution`, an erosion's length) are artwork parameters, never tier consumers: geometry is
/// data a sketch reads back, so a tier change would change the piece itself, and a per-GPU tier
/// would make the same seed produce different forms on different machines. See `ARCHITECTURE.md`
/// section *Performance and the quality dial*.
public enum RenderQuality: Sendable, Equatable, CaseIterable {
    /// Favor frame rate.
    case performance
    /// The balanced, recommended choice for the hardware (the default).
    case `default`
    /// Favor visual quality.
    case detail
}

public extension RenderQuality {
    /// Parse a CLI / config string (the `--render-quality` flag): `performance`/`perf`/`fast`,
    /// `default`/`balanced`/`auto`, or `detail`/`high`/`best` (case-insensitive). `nil` otherwise.
    init?(name: String) {
        switch name.lowercased() {
        case "performance", "perf", "fast": self = .performance
        case "default", "balanced", "auto": self = .default
        case "detail", "high", "best":      self = .detail
        default:                            return nil
        }
    }
}

/// The soft-shadow quality intent a sketch sets: a hardware-relative `RenderQuality` tier
/// (the renderer turns it into a concrete ray count for the GPU it's on) or an exact ray
/// count (hardware-independent). Default is `.tier(.default)`.
enum ShadowQualitySetting: Sendable, Equatable {
    case tier(RenderQuality)
    case absolute(Int)
}

/// The raymarched-3D-SDF quality intent a sketch sets (`drawSDF3D`): a `RenderQuality` tier
/// the renderer resolves to an internal **live-preview** render scale (the dominant lever,
/// since the fullscreen sphere-tracer's cost is bound to pixel count) plus a march-step budget,
/// or an exact camera-march step count. The tier scales the live preview's resolution
/// (`.detail` full, `.default` half so ¼ the pixels, `.performance` quarter so 1/16), a
/// depth-aware upsample compositing it back; `--export`/headless always trace at full
/// resolution. Default is `.tier(.default)`.
enum RaymarchQualitySetting: Sendable, Equatable {
    case tier(RenderQuality)
    case absolute(Int)        // an exact camera-march step count (full resolution)
    case resolution(Double)   // an exact live-preview resolution fraction, 0…1 (default steps)
}

/// The volumetric-light march quality intent a sketch sets (`volumetricQuality` /
/// `volumetricSteps`): a `RenderQuality` tier the renderer resolves to a step budget for the
/// in-scatter march (one shadow-map tap per step), or an exact step count. Default is
/// `.tier(.default)`.
enum VolumetricQualitySetting: Sendable, Equatable {
    case tier(RenderQuality)
    case absolute(Int)
}
