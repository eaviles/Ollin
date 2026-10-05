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
    /// Under a `noiseThreshold` this is the most a pixel traces; a pixel that
    /// settles sooner stops sooner.
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
    public var denoises: Bool
    /// The grain a pixel may be left with, which lets it stop before
    /// `samplesPerPixel` (`--pt-noise`). 0, the default, traces every pixel to the
    /// full count. Above 0, every eight samples past the minimum each pixel reads
    /// the standard error of the brightness it shows against the square root of that
    /// brightness, and stops once the ratio falls under this value, so the count
    /// goes where the grain is: the black margins and a sharp, evenly lit face end
    /// early and a blurred or glossy region runs to the cap. At 0.01 a settled
    /// pixel's standard error is about one level in 255 at any brightness, which
    /// is a final still's figure and one that few pixels reach under a few hundred
    /// samples; 0.04 is about four levels, the grain a sequence at that count
    /// already shows, and the everyday figure. A pixel still sampling keeps its
    /// eight neighbors sampling, and the frame stays a pure function of its index.
    /// What the stop cannot know is a rare bright path a pixel has not seen yet,
    /// so a scene of small hot highlights wants the minimum raised.
    public var noiseThreshold: Double
    /// The fewest samples a pixel takes before it may stop, under a
    /// `noiseThreshold` (`--pt-min`). `nil`, the default, is the square root of
    /// `samplesPerPixel`, rounded up to a multiple of eight and never under eight.
    /// Raise it when a scene's grain is rare and bright (a small source caught by
    /// a glossy surface), since a pixel's first few samples can miss such a path
    /// and read as settled.
    public var minSamplesPerPixel: Int?

    /// The most light that has bounced twice or more may add to a sample, in units
    /// of white (`--pt-clamp`). 0, the default, is no bound. Above 0, light that
    /// scattered at least twice on its way to the eye (a lamp's reflection in a
    /// ball seen again on the floor, a bright wall lighting a shelf, a highlight
    /// passed from one polished bead to the next) is held to this value in its
    /// brightest channel, scaled down whole so its color holds. What one bounce
    /// shows, a lamp in a mirror, a window on a glossy floor, the lamps a surface
    /// faces, is direct light and is never touched. A polished scene's grain is
    /// made of the twice-bounced paths, a hot source caught every few hundred
    /// samples, which no count brings down and which the per-pixel stop cannot
    /// read past; bounded, the grain is gone at a few hundred samples and the stop
    /// can settle. The price is the light the bound takes, which dims the
    /// brightest inter-reflections and is a bias: the frame's recipe records the
    /// share of its light the bound dropped, and a bound that drops more than a
    /// percent or two is darkening the picture rather than cleaning it. 4 to 10
    /// is the usual range.
    public var maxBounceLight: Double

    /// How many earlier frames' samples a pixel may carry into its own, across a
    /// sequence (`--pt-reuse`). 0, the default, is none: every frame is traced on
    /// its own. Above 0, each frame finds where every pixel was in the frame before
    /// (a mover's own motion, from `withMotion`, or the camera's through the depth),
    /// takes the samples that frame had gathered there, and adds them to its own, up
    /// to this many frames' worth of the count. A pixel whose surface changed, another
    /// object, a different depth or facing, starts over, and a pixel whose light
    /// changed by more than its own grain allows pulls the carried light to within
    /// that grain, so a reflection sliding over a polished surface, a shadow sweeping
    /// a floor, or a lamp that moved is followed rather than smeared. The first frame
    /// of a run has no frame before it and traces the whole history's worth itself,
    /// so a sequence starts as settled as it goes on. A frame is then a function of
    /// the frames before it: the same command renders the same sequence byte for
    /// byte, and a still of one frame rendered alone has no history and traces that
    /// worth itself. 8 is the usual figure: a sequence at 32 samples a frame then
    /// carries 256, and the grain stops moving from frame to frame.
    public var reusedFrames: Int

    /// The most time a frame's trace may take, in seconds (`--pt-seconds`). 0, the
    /// default, is no budget: every frame traces to its count. Above 0, the trace
    /// stops at the sample where the time runs out, so the count follows the scene
    /// (a fast scene reaches more, a slow one fewer) and a sequence fits the hours
    /// it has, while `samplesPerPixel` stays the most a pixel traces. The frame it
    /// leaves is a fixed render of the count it reached, byte for byte, and the
    /// recipe records that count beside the budget, so the frame reproduces with the
    /// count in place of the budget. `minSamplesPerPixel` is a floor the clock may
    /// not cut under. Under `reusedFrames` the first frame of a run, which traces
    /// the history's worth itself, gets the history's worth of time, and a sequence
    /// is then no longer the same bytes twice, since each frame's count follows the
    /// clock. The budget covers the tracing alone; the scene's setup, the filter,
    /// and the file add a fraction of a second to a frame.
    public var secondsPerFrame: Double

    public init(samplesPerPixel: Int = 256, maxDepth: Int = 8, denoises: Bool = false,
                noiseThreshold: Double = 0, minSamplesPerPixel: Int? = nil,
                maxBounceLight: Double = 0, reusedFrames: Int = 0,
                secondsPerFrame: Double = 0) {
        self.samplesPerPixel = max(1, samplesPerPixel)
        self.maxDepth = max(1, maxDepth)
        self.denoises = denoises
        self.noiseThreshold = noiseThreshold.isFinite ? max(0, noiseThreshold) : 0
        self.minSamplesPerPixel = minSamplesPerPixel.map { max(1, $0) }
        self.maxBounceLight = maxBounceLight.isFinite ? max(0, maxBounceLight) : 0
        self.reusedFrames = max(0, reusedFrames)
        self.secondsPerFrame = secondsPerFrame.isFinite ? max(0, secondsPerFrame) : 0
    }

    /// Whether pixels may stop early: a threshold above zero and more than one
    /// sample to spread over.
    var isAdaptive: Bool { noiseThreshold > 0 && samplesPerPixel > 1 }

    /// Whether the light a bounce adds to a sample is bounded.
    var isBounded: Bool { maxBounceLight > 0 }

    /// Whether a frame carries the earlier frames' samples.
    var isReusing: Bool { reusedFrames > 0 }

    /// Whether the clock may end a frame's trace before its count.
    var isBudgeted: Bool { secondsPerFrame > 0 }

    /// The time a frame's trace may take: the budget, or the history's worth of it
    /// for the first frame of a reusing run, which traces that worth of samples
    /// itself so the sequence starts settled. Infinite with no budget.
    func timeBudget(tracingTheHistory: Bool) -> Double {
        guard isBudgeted else { return .infinity }
        return secondsPerFrame * (tracingTheHistory && isReusing ? Double(max(1, reusedFrames)) : 1)
    }

    /// The fewest samples a budgeted frame takes before the clock may stop it: the
    /// named minimum, else one dispatch's worth, either clamped to the count. (The
    /// per-pixel stop's own first check is `firstCheck`, which the budget never
    /// moves.)
    var timeFloor: Int { min(samplesPerPixel, max(1, minSamplesPerPixel ?? 1)) }

    /// The most samples a pixel carries under reuse, its own and the carried
    /// together: the history's worth at the count.
    var carriedCap: Int { max(1, reusedFrames) * samplesPerPixel }

    /// The samples every pixel takes before the first convergence check: the named
    /// minimum as given, or the square root of the count rounded up to a multiple
    /// of the check step and never under one step, either clamped to the count.
    var firstCheck: Int {
        if let named = minSamplesPerPixel { return min(samplesPerPixel, max(1, named)) }
        let step = Self.checkStep
        let automatic = step * Int((Double(samplesPerPixel).squareRoot() / Double(step)).rounded(.up))
        return min(samplesPerPixel, max(step, automatic))
    }

    /// How many samples a still-open pixel takes between convergence checks. Small
    /// enough that a pixel wastes at most a handful past the one it settled at,
    /// large enough that consecutive reads of the same running sums are not asked
    /// the same question twice.
    static let checkStep = 8

    /// The tier default sample count the bare `--path-traced` flag resolves to.
    static func tierSamples(for quality: RenderQuality) -> Int {
        switch quality {
        case .performance: return 64
        case .default: return 256
        case .detail: return 4096
        }
    }
}

/// What a traced frame reports about itself once it is done, for the export's
/// recipe and the sequence's closing line: the settings it ran under, the minimum
/// it resolved, and, under adaptive sampling, the mean count its pixels reached.
struct PathTraceReport: Equatable, Sendable {
    var settings: PathTracing
    /// The samples every pixel took before the first check (the full count under a
    /// fixed render).
    var minSamplesPerPixel: Int
    /// The mean number of samples a pixel took, over the whole frame; `nil` under a
    /// fixed count, where every pixel took `settings.samplesPerPixel`.
    var meanSamplesPerPixel: Double?
    /// The share of the frame's light the bounce bound took off (0 to 1); `nil`
    /// with no bound.
    var lightDropped: Double? = nil
    /// Under reuse, the mean count a pixel's picture held once the earlier frames'
    /// samples were carried in, its own and the carried together, over the whole
    /// frame; `nil` when no frames are reused.
    var carriedSamplesPerPixel: Double? = nil
    /// Under a time budget, the count the clock let the frame reach: the most any
    /// pixel traced, and the count a fixed render reproduces the frame at; `nil`
    /// with no budget, where it is the count.
    var reachedSamplesPerPixel: Int? = nil
    /// Under a time budget, the wall-clock seconds the trace took; `nil` with no
    /// budget.
    var secondsTraced: Double? = nil
}
