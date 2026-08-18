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
    /// (64 / 256 / 512 for performance / default / detail).
    public var samplesPerPixel: Int
    /// The longest path traced, in surface bounces. 8 covers mirror-in-mirror
    /// scenes; unbiased termination (Russian roulette) trims most paths earlier.
    public var maxDepth: Int

    public init(samplesPerPixel: Int = 256, maxDepth: Int = 8) {
        self.samplesPerPixel = max(1, samplesPerPixel)
        self.maxDepth = max(1, maxDepth)
    }

    /// The tier default sample count the bare `--path-traced` flag resolves to.
    static func tierSamples(for quality: RenderQuality) -> Int {
        switch quality {
        case .performance: return 64
        case .default: return 256
        case .detail: return 512
        }
    }
}
