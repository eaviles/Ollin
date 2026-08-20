/// The offline path-traced export mode (`--path-traced`): the same scene a sketch
/// tunes live, rendered by tracing full light paths instead of rasterizing, for the
/// look the live pipeline cannot reach in a frame budget: physically soft shadows,
/// color bleeding between surfaces, mirror-in-mirror reflections at any depth, and a
/// real thin-lens depth of field (`Camera3D.aperture` / `focusDistance`). Export
/// only, seconds per frame by design; the live window keeps the raster pipeline.
///
/// Reach it with the flag (`--export out.png --path-traced 512`) or set
/// `OllinApp.pathTracedExport` before calling `OllinApp.image(of:)` / `export`.
/// It needs a ray-tracing GPU (the `rayTracedShadows` capability); elsewhere the
/// export falls back to the raster path with a printed note.
public struct PathTracing: Equatable, Sendable {
    /// Light paths traced per pixel. More samples, less noise, linearly more time;
    /// the flag with no count picks a tier default from the render quality
    /// (64 / 256 / 4096 for performance / default / detail). The detail tier is
    /// the leave-it-running one: it is a final render, and on a still it costs
    /// minutes rather than seconds. Name a count for anything shorter, and name
    /// one for a *sequence*, where the tier cost multiplies by the frame count.
    public var samplesPerPixel: Int
    /// The longest path traced, in surface bounces. 8 covers mirror-in-mirror
    /// scenes; unbiased termination (Russian roulette) trims most paths earlier.
    public var maxDepth: Int
    /// Filter the grain out of the finished render (off by default, `--denoise` to
    /// turn it on). The trace measures the spread of its own samples at each pixel,
    /// and the filter takes its strength from that measurement, so a thin render is
    /// smoothed hard and a nearly converged one only a little. It costs a fraction
    /// of a second against minutes of tracing, and it keeps texture and silhouette
    /// edges, which it is told about separately from the light. What it cannot keep
    /// is a true sparkle: glitter and grain are the same signal to it.
    public var denoise: Bool

    public init(samplesPerPixel: Int = 256, maxDepth: Int = 8, denoise: Bool = false) {
        self.samplesPerPixel = max(1, samplesPerPixel)
        self.maxDepth = max(1, maxDepth)
        self.denoise = denoise
    }

    /// The tier default sample count the bare `--path-traced` flag resolves to.
    static func tierSamples(for quality: RenderQuality) -> Int {
        switch quality {
        case .performance: return 64
        case .default: return 256
        case .detail: return 4096
        }
    }
}
