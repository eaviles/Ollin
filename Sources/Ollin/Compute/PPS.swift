import Foundation
import simd
import COllinShaders   // OllinParticle, OllinSpatialGrid

/// Primordial Particle System: one turning rule, and cells that grow, divide, and
/// die emerge from it (Schmickl, Stefanec & Crailsheim, *Scientific Reports* 2016).
/// Every step, each particle counts its neighbors within `radius`, splits them into
/// how many sit to its left versus its right, then turns by a fixed amount `alpha`
/// plus a crowd-proportional amount `beta · N` toward the busier side, and steps
/// forward at a constant `speed`. That is the whole law.
///
/// Runs on the GPU over the `SpatialHash` neighbor search. Coloring is by local
/// crowd size (the paper's tell for where structure is forming), so dense cell walls
/// read differently from free particles:
///
/// ```swift
/// var pps: PPS!
/// override func setup() { pps = primordialParticles(count: 12_000, radius: 36) }
/// override func draw() {
///     background(Color(white: 0.05))
///     updatePPS(pps)
///     drawParticles(pps)
/// }
/// ```
///
/// The defaults are the paper's canonical set, `⟨α = 180°, β = 17°, v = 0.67·(r/5)⟩`
/// (the speed scaled from the paper's `r = 5` up to your `radius`). Density matters:
/// pick `count` so an open particle has roughly 13–15 neighbors, which is where the
/// paper's cell-forming regime lives; `suggestedCount(for:in:)` estimates it.
@MainActor
public final class PPS {
    /// Particle count.
    public let count: Int

    /// The fixed per-step turn, in degrees (the paper's α, default 180).
    public var alphaDegrees: Double = 180
    /// The per-neighbor turn, in degrees (the paper's β, default 17).
    public var betaDegrees: Double = 17
    /// Forward distance per step, in points (default scales the paper's 0.67 from its
    /// `r = 5` up to this system's `radius`).
    public var speed: Double

    private let hash: SpatialHash
    private let pingpong: PingPong<OllinParticle>
    private let kernel: ComputeKernel

    /// Estimate a `count` that puts an open particle near the paper's 13–15 neighbors
    /// (its cell-forming density) for a `radius` over `bounds`.
    public static func suggestedCount(for radius: Double, in bounds: Rectangle) -> Int {
        let perParticle = Double.pi * radius * radius / 14.0   // ~14 neighbors per disc
        return max(1, Int((bounds.width * bounds.height / perParticle).rounded()))
    }

    /// Build `count` particles over `bounds` interacting within `radius`, headings and
    /// positions randomized from `seed`.
    public init(count: Int, bounds: Rectangle, radius: Double, seed: UInt64) {
        precondition(count > 0, "PPS needs a positive count")
        self.count = count
        self.speed = 0.67 * (radius / 5.0)
        self.hash = SpatialHash(bounds: bounds, cellSize: radius, count: count)

        var rng = SplitMix64(seed: seed)
        let origin = hash.origin, world = hash.worldSize
        var seeds: [OllinParticle] = []
        seeds.reserveCapacity(count)
        for _ in 0..<count {
            let px = origin.x + Double.random(in: 0..<world.x, using: &rng)
            let py = origin.y + Double.random(in: 0..<world.y, using: &rng)
            let heading = Double.random(in: 0..<(2 * .pi), using: &rng)
            seeds.append(OllinParticle(
                position: SIMD2<Float>(Float(px), Float(py)),
                velocity: SIMD2<Float>(0, 0),
                color: SIMD4<Float>(0.4, 0.9, 0.4, 1),
                size: 2.6, life: 1, seedA: Float(heading), seedB: 0))
        }
        self.pingpong = PingPong(seeds)
        self.kernel = PPS.makeKernel()
    }

    /// The current particle state (what `drawParticles` draws).
    var current: ComputeBuffer<OllinParticle> { pingpong.read }

    /// Record one step: build the neighbor hash, then the turn/move kernel. Called by
    /// `Sketch.updatePPS`.
    func recordStep(into drawer: Drawer) {
        let read = pingpong.read, write = pingpong.write
        hash.recordBuild(into: drawer, positions: read)
        let custom = SIMD4<Float>(
            Float(alphaDegrees * .pi / 180), Float(betaDegrees * .pi / 180), Float(speed), 0)
        var bytes: [UInt8] = []
        withUnsafeBytes(of: custom) { bytes.append(contentsOf: $0) }
        drawer.recordDispatch(RecordedDispatch(
            kernel: kernel, threadCount: count,
            buffers: [read, write, hash.sortedIndices, hash.cellStart, hash.cellCount,
                      hash.gridBuffer], params: bytes))
        pingpong.advance()
    }

    /// The turn + move kernel. `custom` carries α (rad), β (rad), and the step speed;
    /// the heading rides `seedA`. One frame is one discrete step (no `dt` scaling), so
    /// the rule stays the paper's. The neighbor macro and toroidal helpers come from
    /// the spliced shader library.
    private static func makeKernel() -> ComputeKernel {
        let source = """
        kernel void ollin_pps_step(
            device const OllinParticle *inBuf  [[buffer(0)]],
            device OllinParticle       *outBuf [[buffer(1)]],
            device const uint *sortedIdx [[buffer(2)]],
            device const uint *cellStart [[buffer(3)]],
            device const uint *cellCount [[buffer(4)]],
            constant OllinSpatialGrid &grid [[buffer(5)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            constant float4 &custom          [[buffer(11)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            float alpha = custom.x, beta = custom.y, speed = custom.z;
            OllinParticle p = inBuf[id];
            float phi = p.seedA;
            float2 heading = float2(cos(phi), sin(phi));

            // Count neighbors within the radius, split by which side of the heading
            // they fall on (the sign of heading × delta).
            int left = 0, right = 0;
            OLLIN_FOR_NEIGHBORS(p.position, grid, sortedIdx, cellStart, cellCount, j)
                if (j == id) { continue; }
                float2 d = ollin_torus_delta(p.position, inBuf[j].position, grid.worldSize);
                if (length(d) < grid.cellSize) {
                    float side = heading.x * d.y - heading.y * d.x;   // cross-product z
                    if (side > 0.0) { right++; } else { left++; }
                }
            OLLIN_END_NEIGHBORS

            int n = left + right;
            float turn = alpha + beta * float(n) * sign(float(right - left));
            phi += turn;
            heading = float2(cos(phi), sin(phi));
            p.position += heading * speed;
            // Toroidal wrap.
            float2 rel = p.position - grid.origin;
            rel = rel - grid.worldSize * floor(rel / grid.worldSize);
            p.position = grid.origin + rel;
            p.seedA = phi;

            // Color by local crowd size (the paper's structure tell).
            float3 rgb;
            if (n > 35)      { rgb = float3(0.95, 0.25, 0.85); }   // dense wall: magenta
            else if (n > 15) { rgb = float3(0.95, 0.85, 0.30); }   // forming: yellow
            else if (n >= 13){ rgb = float3(0.40, 0.90, 0.45); }   // open regime: green
            else             { rgb = float3(0.35, 0.55, 0.95); }   // sparse: blue
            p.color = float4(rgb, 1.0);
            outBuf[id] = p;
        }
        """
        return ComputeKernel(entry: "ollin_pps_step", source)
    }
}
