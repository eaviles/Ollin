import Ollin
import COllinShaders   // OllinParticle (the raw particle struct the hash sorts)

/// Building your own particle-interaction sim on the public `SpatialHash`. The three
/// artificial-life examples (Particle Life, PPS, Physarum) hide the hash inside a typed
/// sim; this one drives it directly, so you can see the whole loop: hold your own
/// `PingPong<OllinParticle>`, hand the hash your positions each frame with
/// `neighborStep`, and write a kernel that walks each particle's neighbors with the
/// `OLLIN_FOR_NEIGHBORS` macro.
///
/// The kernel here does two things at once: it nudges each particle toward the average
/// of its neighbors (a weak cohesion that lets loose clumps form) and colors it by how
/// many neighbors it has. So the color *is* the neighbor search made visible: cool where
/// space is empty, hot where the crowd is thick.
@main
final class NeighborSearch_Example: Sketch {
    let particleCount = 18_000
    let radius = 40.0

    var hash: SpatialHash!
    var particles: PingPong<OllinParticle>!
    var seeded = false

    // Scatter the particles across the hash's toroidal domain (region = origin.xy,
    // worldSize.xy), run once on the first frame.
    lazy var seedKernel = ComputeKernel(entry: "neighbor_seed", """
    kernel void neighbor_seed(
        device OllinParticle *buf [[buffer(0)]],
        constant OllinComputeUniforms &u [[buffer(10)]],
        constant float4 &region [[buffer(11)]],
        uint id [[thread_position_in_grid]]) {
        if (id >= u.particleCount) { return; }
        float2 r = hash22(float2(float(id), 7.0));
        OllinParticle p = buf[id];
        p.position = region.xy + r * region.zw;
        p.velocity = float2(0.0);
        p.size = 2.6;
        p.color = float4(0.35, 0.6, 1.0, 1.0);
        buf[id] = p;
    }
    """)

    // One step: count neighbors, drift toward their center, color by the count.
    lazy var stepKernel = ComputeKernel(entry: "neighbor_step", """
    kernel void neighbor_step(
        device const OllinParticle *inBuf  [[buffer(0)]],
        device OllinParticle       *outBuf [[buffer(1)]],
        device const uint *sortedIdx [[buffer(2)]],
        device const uint *cellStart [[buffer(3)]],
        device const uint *cellCount [[buffer(4)]],
        constant OllinSpatialGrid &grid [[buffer(5)]],
        constant OllinComputeUniforms &u [[buffer(10)]],
        uint id [[thread_position_in_grid]]) {
        if (id >= u.particleCount) { return; }
        OllinParticle p = inBuf[id];
        uint n = 0;
        float2 toCenter = float2(0.0);
        OLLIN_FOR_NEIGHBORS(p.position, grid, sortedIdx, cellStart, cellCount, j)
            if (j == id) { continue; }
            float2 d = ollin_torus_delta(p.position, inBuf[j].position, grid.worldSize);
            if (length(d) < grid.cellSize) { n++; toCenter += d; }
        OLLIN_END_NEIGHBORS

        float2 vel = p.velocity;
        if (n > 0u) { vel += (toCenter / float(n)) * 0.008; }        // gentle cohesion
        vel += curlNoise(p.position * 0.004 + u.time * 0.05) * 0.75; // wander (keeps density varying, not clumped)
        vel *= 0.9;                                                  // damping
        float2 pos = p.position + vel;
        float2 rel = pos - grid.origin;
        rel = rel - grid.worldSize * floor(rel / grid.worldSize);    // toroidal wrap
        p.position = grid.origin + rel;
        p.velocity = vel;

        // Color by neighbor count on a blue -> green -> orange heat ramp (a distinct
        // midtone reads better than a straight blue->orange lerp, which muddies).
        float t = clamp(float(n) / 42.0, 0.0, 1.0);
        float3 cool = float3(0.15, 0.35, 1.00);
        float3 mid  = float3(0.20, 0.90, 0.55);
        float3 hot  = float3(1.00, 0.55, 0.20);
        float3 rgb = (t < 0.5) ? mix(cool, mid, t * 2.0) : mix(mid, hot, t * 2.0 - 1.0);
        p.color = float4(rgb, 1.0);
        outBuf[id] = p;
    }
    """)

    override func setup() {
        hash = spatialHash(radius: radius, count: particleCount)
        particles = PingPong<OllinParticle>(count: particleCount)
    }

    override func draw() {
        if !seeded {
            var region = ComputeParams()
            region.append(SIMD4<Float>(Float(hash.origin.x), Float(hash.origin.y),
                                       Float(hash.worldSize.x), Float(hash.worldSize.y)))
            compute(seedKernel, over: particles.read, params: region)
            seeded = true
        }

        background(Color(white: 0.05))
        neighborStep(stepKernel, over: hash, reading: particles.read, writing: particles.write)
        particles.advance()
        drawParticles(particles.read)

        drawCaption("SpatialHash · \(particleCount) particles colored by neighbor count")
    }
}
