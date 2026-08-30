import Ollin

/// A reaction-diffusion field evolving on the GPU — the texture half of Ollin's
/// compute path, the way `CurlField` is the buffer half. Two chemicals diffuse and
/// react in every cell of a 512² field; where they balance, Turing patterns emerge —
/// coral, fingerprints, mitosis, stripes. The feed and kill rates vary across the
/// field, so a *range* of patterns coexists in one frame; drag the mouse to inject
/// chemical and watch the reaction chase your cursor.
///
/// The pipeline is three GPU passes per frame, no pixel ever touching the CPU:
/// a `Simulation` runs the reaction-diffusion (many small steps per frame for
/// stability), a small `compute` pass colourises the chemical field into a display
/// texture, and `drawImage` composites that texture like any other image.
///
/// **Two ways to write the Metal** are shown here, so you can pick per kernel:
/// - The seed and colourise passes live in their own **`Kernels.metal`** file — real
///   Metal syntax highlighting and editor checking — loaded with
///   `ComputeKernel(entry:resource:in:)`.
/// - The reaction step is an inline **`step:` snippet**: just the per-cell math, with
///   `value`/`result`/`tap(dx,dy)`/`size` in scope (Ollin generates the kernel
///   around it). Terse, for the part you tweak most.
@main
final class ReactionDiffusion_Example: Sketch {
    static let gridSize = 512

    /// The reaction-diffusion field: chemical A in `.r`, chemical B in `.g`. Twelve
    /// sub-steps per frame keep the explicit integration stable and the patterns
    /// lively.
    lazy var field = Simulation(width: Self.gridSize, height: Self.gridSize,
                                substeps: 12, step: rdStep)

    /// A second texture the colourise pass writes for display, kept off the
    /// simulation state so the chemistry stays pure float concentration.
    lazy var display = ComputeTexture(width: Self.gridSize, height: Self.gridSize)

    // Loaded from Kernels.metal (bundled as a resource on this example's target).
    let seedKernel = ComputeKernel(entry: "rd_seed", resource: "Kernels", in: .module)
    let colorizeKernel = ComputeKernel(entry: "rd_colorize", resource: "Kernels", in: .module)
    private var seeded = false

    override func draw() {
        guard let seedKernel, let colorizeKernel else {
            // The .metal resource only ships with this example's own target; run the
            // Example-Compute-ReactionDiffusion product (not the dynamic gallery loader).
            drawStatus("ReactionDiffusion needs its Kernels.metal — run the Example-Compute-ReactionDiffusion target.",
                       style: .warning)
            return
        }

        // Seed the starting chemistry once (a one-shot write into the field).
        if !seeded { compute(seedKernel, writing: field.current); seeded = true }

        // One frame of reaction-diffusion (custom.x flags a mouse-held inject).
        updateSimulation(field, custom: SIMD4(mouseIsPressed ? 1 : 0, 0, 0, 0))

        // Colourise the chemical field into the display texture, then draw it.
        compute(colorizeKernel, reading: field.current, writing: display)
        drawImage(display.image, in: Rectangle(x: 0, y: 0, width: Double(width), height: Double(height)))

        drawCaption("Gray-Scott reaction-diffusion · 512² field on the GPU · drag to seed")
    }
}

/// The per-cell reaction-diffusion update (an inline `Simulation` `step:` snippet).
/// In scope: `value`/`result` (this cell, read/write), `tap(dx,dy)` (the source field
/// at an integer offset, toroidal), `gid`/`size`, `u`, `custom`, and the prelude.
let rdStep = """
    // Feed and kill rates vary across the field, so different Turing regimes — spots,
    // stripes, coral — emerge in different regions of one image.
    float feed = 0.030 + 0.020 * (float(gid.x) / float(size.x));
    float kill = 0.057 + 0.011 * (float(gid.y) / float(size.y));

    // Laplacian of (A, B) via a 9-point stencil (orthogonal 0.2, diagonal 0.05).
    float2 lap = -value.xy
        + 0.20 * (tap(-1, 0).xy + tap(1, 0).xy + tap(0, -1).xy + tap(0, 1).xy)
        + 0.05 * (tap(-1, -1).xy + tap(1, -1).xy + tap(-1, 1).xy + tap(1, 1).xy);

    // Gray-Scott reaction: A is consumed where B is present (reaction = A·B²),
    // A is fed back toward 1, B is killed back toward 0.
    float a = value.x, b = value.y;
    float reaction = a * b * b;
    a += 1.0 * lap.x - reaction + feed * (1.0 - a);
    b += 0.5 * lap.y + reaction - (kill + feed) * b;

    // Drag to paint chemical B (u.mouse is canvas points; map into field texels).
    if (custom.x > 0.5) {
        float2 m = u.mouse / u.resolution * float2(size);
        if (distance(float2(gid), m) < 7.0) { b = 1.0; }
    }

    result = float4(clamp(a, 0.0, 1.0), clamp(b, 0.0, 1.0), 0.0, 1.0);
"""
