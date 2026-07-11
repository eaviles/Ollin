import Foundation
import simd
import COllinShaders   // OllinParticle, OllinSpatialGrid (the shared GPU structs)

/// A GPU uniform-grid neighbor search: the primitive that lets each particle find
/// the others near it, which the one-thread-per-particle compute path can't do on
/// its own. It's the enabler under the particle-interaction sims (`ParticleLife`,
/// `PPS`) and the thing to reach for when you write your own.
///
/// Each frame it sorts the particles into a grid of square cells (a **counting
/// sort**: count how many land in each cell, prefix-sum the counts into per-cell
/// start offsets, then scatter each particle's index into its cell's slot), leaving
/// three buffers a query kernel walks: `sortedIndices`, `cellStart`, `cellCount`.
/// The cell edge equals the query radius over a **toroidal** domain, so every
/// neighbor within the radius sits in the queried cell's wrapped 3×3 block.
///
/// Drive it through the `neighborStep(_:over:reading:writing:)` facade, whose kernel
/// walks the neighbors with the `OLLIN_FOR_NEIGHBORS` macro:
///
/// ```swift
/// let hash = spatialHash(in: bounds, radius: 24, count: 20_000)
/// let pp = PingPong<OllinParticle>(count: 20_000)   // your particle buffers
/// let step = ComputeKernel(entry: "my_step", """
/// kernel void my_step(
///     device const OllinParticle *inBuf  [[buffer(0)]],
///     device OllinParticle       *outBuf [[buffer(1)]],
///     device const uint *sortedIdx [[buffer(2)]],
///     device const uint *cellStart [[buffer(3)]],
///     device const uint *cellCount [[buffer(4)]],
///     constant OllinSpatialGrid &grid [[buffer(5)]],
///     constant OllinComputeUniforms &u [[buffer(10)]],
///     uint id [[thread_position_in_grid]]) {
///     if (id >= u.particleCount) return;
///     OllinParticle p = inBuf[id];
///     uint n = 0;
///     OLLIN_FOR_NEIGHBORS(p.position, grid, sortedIdx, cellStart, cellCount, j)
///         if (j == id) continue;
///         float2 d = ollin_torus_delta(p.position, inBuf[j].position, grid.worldSize);
///         if (length(d) < grid.cellSize) n++;
///     OLLIN_END_NEIGHBORS
///     p.color = float4(float(n) / 12.0, 0.4, 1.0, 1.0);
///     outBuf[id] = p;
/// }
/// """)
///
/// override func draw() {
///     neighborStep(step, over: hash, reading: pp.read, writing: pp.write)
///     drawParticles(pp.read); pp.advance()
/// }
/// ```
///
/// The scatter's within-cell order is set by the GPU's atomic race, so a query that
/// *sums* over neighbors (a force) is reproducible only up to float rounding, and
/// these sims are chaotic, so they carry no frame-exact export guarantee. The
/// neighbor *set* (and so any count) is order-independent and fully deterministic.
@MainActor
public final class SpatialHash {
    /// The number of particles the hash sorts each build.
    public let count: Int
    /// The cell edge, which is also the neighbor query radius (points).
    public let cellSize: Double
    /// The grid's min corner in canvas space (points, top-left origin).
    public let origin: Vector2
    /// The toroidal domain the grid tiles (points); positions wrap within
    /// `[origin, origin + worldSize)`, matching how the grid wraps cell indices.
    public let worldSize: Vector2
    /// Cells across.
    public let gridWidth: Int
    /// Cells down.
    public let gridHeight: Int

    /// Per-particle sorted index (length `count`): `sortedIndices[k]` is the particle
    /// in slot `k`. A query kernel binds this at buffer index 2.
    public let sortedIndices: ComputeBuffer<UInt32>
    /// Per-cell start offset into `sortedIndices` (length `gridWidth * gridHeight`).
    /// Bound at buffer index 3.
    public let cellStart: ComputeBuffer<UInt32>
    /// Per-cell particle count (length `gridWidth * gridHeight`). Bound at index 4.
    public let cellCount: ComputeBuffer<UInt32>
    /// The grid parameters as a one-element buffer, bound at index 5 (`constant
    /// OllinSpatialGrid&`) for the neighbor macro and toroidal-distance helper.
    public let gridBuffer: ComputeBuffer<OllinSpatialGrid>

    /// A scratch cursor (length `numCells`) the scatter atomically advances; not read
    /// by queries.
    private let cellCursor: ComputeBuffer<UInt32>

    // The four counting-sort kernels share one compiled source (keyed by hash), so
    // creating them is cheap and they compile together.
    private let clearKernel: ComputeKernel
    private let countKernel: ComputeKernel
    private let scanKernel: ComputeKernel
    private let scatterKernel: ComputeKernel

    /// Build a hash over `bounds` with square cells of `cellSize` (set this to the
    /// neighbor radius your query uses), sorting `count` particles. The grid is
    /// clamped to at least 3×3 cells so the wrapped 3×3 neighbor block never revisits
    /// a cell, so the actual `worldSize` may round up to a whole number of cells past
    /// `bounds`.
    public init(bounds: Rectangle, cellSize: Double, count: Int) {
        precondition(count > 0, "SpatialHash needs a positive count")
        precondition(cellSize > 0, "SpatialHash needs a positive cellSize")
        let gw = max(3, Int((bounds.width / cellSize).rounded(.down)))
        let gh = max(3, Int((bounds.height / cellSize).rounded(.down)))
        let world = Vector2(Double(gw) * cellSize, Double(gh) * cellSize)

        self.count = count
        self.cellSize = cellSize
        self.origin = bounds.corner
        self.worldSize = world
        self.gridWidth = gw
        self.gridHeight = gh

        let numCells = gw * gh
        self.sortedIndices = ComputeBuffer(count: count)
        self.cellStart = ComputeBuffer(count: numCells)
        self.cellCount = ComputeBuffer(count: numCells)
        self.cellCursor = ComputeBuffer(count: numCells)

        let grid = OllinSpatialGrid(
            origin: SIMD2<Float>(Float(bounds.x), Float(bounds.y)),
            worldSize: SIMD2<Float>(Float(world.x), Float(world.y)),
            cellSize: Float(cellSize),
            gridW: UInt32(gw), gridH: UInt32(gh), numCells: UInt32(numCells))
        self.gridBuffer = ComputeBuffer([grid])

        let source = SpatialHash.kernelSource
        self.clearKernel = ComputeKernel(entry: "ollin_hash_clear", source)
        self.countKernel = ComputeKernel(entry: "ollin_hash_count", source)
        self.scanKernel = ComputeKernel(entry: "ollin_hash_scan", source)
        self.scatterKernel = ComputeKernel(entry: "ollin_hash_scatter", source)
    }

    /// Record the counting sort over `particles`' positions: clear the per-cell
    /// counts, count, prefix-sum into start offsets, then scatter indices into slots.
    /// Runs before the query kernel that reads the result (the compute encoder is
    /// serial, so each pass sees the previous one's writes). The `Drawer` binds the
    /// standard uniforms at index 10.
    func recordBuild(into drawer: Drawer, positions particles: ComputeBuffer<OllinParticle>) {
        let numCells = gridWidth * gridHeight
        // clear: zero the per-cell counts (index 4)
        drawer.recordDispatch(RecordedDispatch(
            kernel: clearKernel, threadCount: numCells,
            buffers: [nil, nil, nil, nil, cellCount], params: []))
        // count: one atomic add per particle into its cell (particles 0, count 4, grid 5)
        drawer.recordDispatch(RecordedDispatch(
            kernel: countKernel, threadCount: count,
            buffers: [particles, nil, nil, nil, cellCount, gridBuffer], params: []))
        // scan: exclusive prefix sum into cellStart (3), seed the cursor (6), read count (4)
        drawer.recordDispatch(RecordedDispatch(
            kernel: scanKernel, threadCount: 1,
            buffers: [nil, nil, nil, cellStart, cellCount, gridBuffer, cellCursor], params: []))
        // scatter: write each particle index into its cell's next free slot (sorted 2, cursor 6)
        drawer.recordDispatch(RecordedDispatch(
            kernel: scatterKernel, threadCount: count,
            buffers: [particles, nil, sortedIndices, nil, nil, gridBuffer, cellCursor], params: []))
    }

    /// The counting-sort kernels. `ollin_grid_cell`, `OllinSpatialGrid`,
    /// `OllinParticle`, and `OllinComputeUniforms` all come from the spliced shader
    /// library and shared header, so this source writes no includes.
    private static let kernelSource = """
    // Zero the per-cell counts for this frame's build.
    kernel void ollin_hash_clear(
        device uint *cellCount [[buffer(4)]],
        constant OllinComputeUniforms &u [[buffer(10)]],
        uint id [[thread_position_in_grid]]) {
        if (id >= u.particleCount) { return; }
        cellCount[id] = 0u;
    }

    // Tally one particle into its grid cell.
    kernel void ollin_hash_count(
        device const OllinParticle *particles [[buffer(0)]],
        device atomic_uint *cellCount [[buffer(4)]],
        constant OllinSpatialGrid &grid [[buffer(5)]],
        constant OllinComputeUniforms &u [[buffer(10)]],
        uint id [[thread_position_in_grid]]) {
        if (id >= u.particleCount) { return; }
        uint cell = ollin_grid_cell(particles[id].position, grid);
        atomic_fetch_add_explicit(&cellCount[cell], 1u, memory_order_relaxed);
    }

    // Single-thread exclusive prefix sum of the counts into per-cell start offsets,
    // seeding the scatter cursor to the same offsets. (Serial over the cells; the
    // grid is small, and a parallel scan is a later optimization of the same sort.)
    kernel void ollin_hash_scan(
        device const uint *cellCount [[buffer(4)]],
        device uint *cellStart [[buffer(3)]],
        constant OllinSpatialGrid &grid [[buffer(5)]],
        device uint *cellCursor [[buffer(6)]],
        uint id [[thread_position_in_grid]]) {
        if (id != 0u) { return; }
        uint acc = 0u;
        for (uint c = 0u; c < grid.numCells; ++c) {
            cellStart[c] = acc;
            cellCursor[c] = acc;
            acc += cellCount[c];
        }
    }

    // Scatter each particle's index into the next free slot of its cell.
    kernel void ollin_hash_scatter(
        device const OllinParticle *particles [[buffer(0)]],
        device uint *sortedIndices [[buffer(2)]],
        constant OllinSpatialGrid &grid [[buffer(5)]],
        device atomic_uint *cellCursor [[buffer(6)]],
        constant OllinComputeUniforms &u [[buffer(10)]],
        uint id [[thread_position_in_grid]]) {
        if (id >= u.particleCount) { return; }
        uint cell = ollin_grid_cell(particles[id].position, grid);
        uint slot = atomic_fetch_add_explicit(&cellCursor[cell], 1u, memory_order_relaxed);
        sortedIndices[slot] = id;
    }
    """
}
