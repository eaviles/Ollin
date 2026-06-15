import Ollin

/// A million particles flowing through a curl-noise field — on the GPU, every
/// frame. Each particle is updated by a compute kernel (it never touches the CPU)
/// and drawn as a faint additive disc, so where streams cross they sum into light.
/// The flow is `curlNoise`, which is divergence-free: particles swirl and braid
/// without ever clumping into sinks. They live a short, staggered life and respawn
/// at a fresh random spot, so the field keeps churning.
///
/// This is the headline of Ollin's compute path, and it's about *scale*: a count
/// the CPU draw loop can't approach (the per-particle work is one struct write on
/// the GPU). The whole simulation is the `step:` snippet below — Ollin generates
/// the kernel around it, owns the double-buffering, and renders the result.
///
/// In the snippet you read and write the particle's fields as plain locals
/// (`position`, `velocity`, `color`, `size`, `life`, `seedA`/`seedB`), with `id`
/// (this particle's index), `u` (per-frame constants — `u.time`, `u.dt`,
/// `u.resolution`, …), and the prelude helpers (`hash21`, `curlNoise`, …) in scope.
@main
final class CurlField_Example: Sketch {
    lazy var sand = Particles(count: 1_000_000, step: """
        // Respawn the dead at a fresh spot with a staggered lifetime, so the field
        // never empties or pulses all at once (seedA decorrelates each respawn).
        if (life <= 0.0) {
            position = hash22(float2(id, seedA + float(u.frameCount))) * u.resolution;
            life = 0.4 + hash21(float2(seedA, id)) * 1.1;
            seedA += 1.0;
        }

        // Curl noise: a smooth, divergence-free flow field that slowly drifts.
        float2 flow = curlNoise(position * 0.0016 + float2(0.0, u.time * 0.05));
        position += flow * 95.0 * u.dt;
        life -= u.dt;

        // Colour by flow direction; faint, so crossing streams sum into bright veins.
        float angle = atan2(flow.y, flow.x);
        color = float4(0.5 + 0.5 * cos(angle + float3(0.0, 2.1, 4.2)), 0.45);
        size = 1.3;
    """)

    override func setup() {
        toneMap(.aces)   // roll the bright overlaps off into a glow instead of clipping
    }

    override func draw() {
        background(Color(red: 0.02, green: 0.02, blue: 0.05))
        blendMode(.add)
        updateParticles(sand)   // one GPU simulation step
        drawParticles(sand)     // a million additive discs

        blendMode(.normal)
        drawCaption("1,000,000 particles · curl-noise flow on the GPU")
    }
}
