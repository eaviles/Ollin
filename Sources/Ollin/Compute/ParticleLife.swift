import Foundation
import simd
import COllinShaders   // OllinParticle, OllinSpatialGrid

/// Particle Life: a few kinds of particle, one attraction/repulsion number for each
/// ordered pair of kinds, and out of that come membranes, cells, chasers, and worms.
/// The classic emergent-matter toy (Jeffrey Ventrella's *Clusters*, the widely-copied
/// "particle life"), here on the GPU over the `SpatialHash` neighbor search so tens of
/// thousands of particles interact in real time.
///
/// Each particle feels every neighbor within `radius`: a short-range repulsion that
/// keeps them from overlapping, then, past a `beta` fraction of the radius, an
/// attraction (or more repulsion) whose sign and strength is the matrix entry for the
/// two kinds. Asymmetry in the matrix (i likes j, j flees i) is what makes things
/// chase and swirl. Build one in `setup()`, step and draw it in `draw()`:
///
/// ```swift
/// var life: ParticleLife!
/// override func setup() {
///     background(.black); noClear()
///     life = particleLife(count: 20_000, kinds: 6, radius: 44)
/// }
/// override func draw() {
///     background(.black)
///     blendMode(.add)
///     updateParticleLife(life)
///     drawParticles(life)
/// }
/// ```
///
/// `kinds`, `radius`, and the matrix are fixed at build; the live feel comes from the
/// `beta`, `forceFactor`, and `frictionHalfLife` knobs (tune them, or bind them to
/// `@Param`s). `randomizeMatrix(seed:)` rolls a fresh rule set without rebuilding.
@MainActor
public final class ParticleLife {
    /// Particle count.
    public let count: Int
    /// Number of distinct kinds (the matrix is `kinds × kinds`).
    public let kinds: Int

    /// Where the repulsion core ends and the attraction lobe begins, as a fraction of
    /// `radius` (0…1). Larger keeps particles further apart.
    public var beta: Double = 0.3
    /// Overall strength of the interaction forces.
    public var forceFactor: Double = 6.0
    /// Seconds for a particle's velocity to halve with no force (the viscosity of the
    /// medium). Small = syrupy, large = drifty.
    public var frictionHalfLife: Double = 0.04

    private let hash: SpatialHash
    private let pingpong: PingPong<OllinParticle>
    private var matrix: ComputeBuffer<Float>
    private let kernel: ComputeKernel

    /// Build `count` particles of `kinds` kinds over `bounds`, feeling each other
    /// within `radius`, with a random interaction matrix (roll it again with
    /// `randomizeMatrix`). `seed` makes the initial layout and matrix reproducible.
    public init(count: Int, kinds: Int, bounds: Rectangle, radius: Double, seed: UInt64) {
        precondition(count > 0, "ParticleLife needs a positive count")
        precondition(kinds > 0, "ParticleLife needs at least one kind")
        self.count = count
        self.kinds = kinds
        self.hash = SpatialHash(bounds: bounds, cellSize: radius, count: count)

        var rng = SplitMix64(seed: seed)
        let origin = hash.origin, world = hash.worldSize
        var seeds: [OllinParticle] = []
        seeds.reserveCapacity(count)
        for i in 0..<count {
            let kind = i % kinds
            let c = Color(hue: Double(kind) / Double(kinds), saturation: 0.72, brightness: 1.0)
            let px = origin.x + Double.random(in: 0..<world.x, using: &rng)
            let py = origin.y + Double.random(in: 0..<world.y, using: &rng)
            seeds.append(OllinParticle(
                position: SIMD2<Float>(Float(px), Float(py)),
                velocity: SIMD2<Float>(0, 0),
                color: SIMD4<Float>(Float(c.red), Float(c.green), Float(c.blue), 1),
                size: 2.4, life: 1, seedA: Float(kind), seedB: 0))
        }
        self.pingpong = PingPong(seeds)
        self.matrix = ParticleLife.makeMatrix(kinds: kinds, seed: seed &+ 0x9E37)
        self.kernel = ParticleLife.makeKernel(kinds: kinds)
    }

    /// The current particle state (what `drawParticles` draws).
    var current: ComputeBuffer<OllinParticle> { pingpong.read }

    /// Replace the interaction matrix with a fresh random one (a new "world" without
    /// re-seeding the particles). Allocates a new buffer, so an in-flight frame keeps
    /// the old rules.
    public func randomizeMatrix(seed: UInt64) {
        matrix = ParticleLife.makeMatrix(kinds: kinds, seed: seed)
    }

    /// Record one step: build the neighbor hash over the current particles, then the
    /// force/integration kernel. Called by `Sketch.updateParticleLife`.
    func recordStep(into drawer: Drawer) {
        let read = pingpong.read, write = pingpong.write
        hash.recordBuild(into: drawer, positions: read)
        let custom = SIMD4<Float>(Float(beta), Float(forceFactor), Float(frictionHalfLife), 0)
        var bytes: [UInt8] = []
        withUnsafeBytes(of: custom) { bytes.append(contentsOf: $0) }
        drawer.recordDispatch(RecordedDispatch(
            kernel: kernel, threadCount: count,
            buffers: [read, write, hash.sortedIndices, hash.cellStart, hash.cellCount,
                      hash.gridBuffer, matrix], params: bytes))
        pingpong.advance()
    }

    /// A random `kinds × kinds` interaction matrix in [-1, 1], row-major (`m[i*kinds+j]`
    /// is how kind i feels about kind j).
    private static func makeMatrix(kinds: Int, seed: UInt64) -> ComputeBuffer<Float> {
        var rng = SplitMix64(seed: seed)
        var values = [Float](repeating: 0, count: kinds * kinds)
        for k in values.indices { values[k] = Float(Double.random(in: -1...1, using: &rng)) }
        return ComputeBuffer(values)
    }

    /// The force + integration kernel. `kinds` bakes in as a literal so the matrix
    /// index needs no extra uniform; the live knobs ride `custom` (beta, forceFactor,
    /// frictionHalfLife). The neighbor macro and toroidal helpers come from the
    /// spliced shader library.
    private static func makeKernel(kinds: Int) -> ComputeKernel {
        let source = """
        kernel void ollin_particlelife_step(
            device const OllinParticle *inBuf  [[buffer(0)]],
            device OllinParticle       *outBuf [[buffer(1)]],
            device const uint *sortedIdx [[buffer(2)]],
            device const uint *cellStart [[buffer(3)]],
            device const uint *cellCount [[buffer(4)]],
            constant OllinSpatialGrid &grid [[buffer(5)]],
            device const float *matrix  [[buffer(6)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            constant float4 &custom          [[buffer(11)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            const int KINDS = \(kinds);
            OllinParticle p = inBuf[id];
            int ti = int(p.seedA + 0.5);
            float beta = clamp(custom.x, 0.02, 0.95);
            float forceFactor = custom.y;
            float halfLife = max(custom.z, 1e-3);
            float dt = max(u.dt, 1e-4);

            float2 force = float2(0.0);
            OLLIN_FOR_NEIGHBORS(p.position, grid, sortedIdx, cellStart, cellCount, j)
                if (j == id) { continue; }
                float2 d = ollin_torus_delta(p.position, inBuf[j].position, grid.worldSize);
                float r = length(d);
                if (r > 1e-4 && r < grid.cellSize) {
                    int tj = int(inBuf[j].seedA + 0.5);
                    float a = matrix[ti * KINDS + tj];
                    float rn = r / grid.cellSize;               // 0…1 over the radius
                    float f;
                    if (rn < beta) {
                        f = rn / beta - 1.0;                    // short-range repulsion
                    } else {
                        f = a * (1.0 - fabs(2.0 * rn - 1.0 - beta) / (1.0 - beta));
                    }
                    force += (d / r) * f;
                }
            OLLIN_END_NEIGHBORS

            float2 acc = force * grid.cellSize * forceFactor;
            float friction = pow(0.5, dt / halfLife);
            p.velocity = p.velocity * friction + acc * dt;
            p.position += p.velocity * dt;
            // Wrap into [origin, origin + worldSize) so the field is a torus.
            float2 rel = p.position - grid.origin;
            rel = rel - grid.worldSize * floor(rel / grid.worldSize);
            p.position = grid.origin + rel;
            outBuf[id] = p;
        }
        """
        return ComputeKernel(entry: "ollin_particlelife_step", source)
    }
}
