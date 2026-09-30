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
/// let hash = makeSpatialHash(in: bounds, radius: 24, count: 20_000)
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
///     drawParticles(pp.read); pp.swap()
/// }
/// ```
///
/// The scatter hands out slots within a cell in whatever order the GPU's threads
/// reach it, and a query that *sums* over its neighbors rounds differently in
/// each order, which in a chaotic sim grows from the last bit to a different
/// picture within seconds. So in an export, and while a take plays back, a last
/// pass puts each cell's particles in index order, and the same seed draws the
/// same frames. A live window skips that pass: it costs a clumping sim about a
/// fifth of its step, and a clock that follows the wall never repeats a run
/// anyway. The neighbor *set*, and any count of it, is the same either way.
@MainActor
public final class SpatialHash {
    /// The number of particles the hash sorts each build.
    public let count: Int
    /// The cell edge, which is also the neighbor query radius (points).
    public let cellSize: Double
    /// A cell's width and height: each side of `bounds` divided into as many
    /// cells of at least `cellSize` as fit, so the cells tile the bounds exactly.
    let cellExtent: Vector2
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
    /// The scatter's output when the run can repeat (length `count`): every cell's
    /// particles in the order the GPU's threads reached the cursor, which the rank
    /// pass reads to put them in index order in `sortedIndices`. Not read by queries.
    private let scattered: ComputeBuffer<UInt32>
    /// Where each cell's run of 32-member chunks starts in the rank pass's work
    /// (length `numCells + 1`, the last entry the total), written by the scan.
    private let chunkStart: ComputeBuffer<UInt32>

    // The counting-sort kernels share one compiled source (keyed by hash), so
    // creating them is cheap and they compile together.
    private let clearKernel: ComputeKernel
    private let countKernel: ComputeKernel
    private let scanKernel: ComputeKernel
    private let scatterKernel: ComputeKernel
    private let rankKernel: ComputeKernel

    /// Build a hash over `bounds` with cells at least `cellSize` on a side (set this
    /// to the neighbor radius your query uses), sorting `count` particles. The world
    /// is `bounds` itself: as many cells as `cellSize` divides each side into, each
    /// stretched to the side's exact share, so a particle wraps at the bounds a
    /// sketch gave and not at the last whole cell short of them (a 253-wide panel
    /// at a radius of 15 would wrap at 240 and leave a bare strip). The grid is
    /// clamped to at least 3×3 cells so the wrapped 3×3 neighbor block never revisits
    /// a cell, which is the one case the world rounds up past `bounds`, to three
    /// cells of `cellSize`.
    public init(bounds: Rectangle, cellSize: Double, count: Int) {
        precondition(count > 0, "SpatialHash needs a positive count")
        precondition(cellSize > 0, "SpatialHash needs a positive cellSize")
        let gw = max(3, Int((bounds.width / cellSize).rounded(.down)))
        let gh = max(3, Int((bounds.height / cellSize).rounded(.down)))
        let cell = Vector2(max(cellSize, bounds.width / Double(gw)),
                           max(cellSize, bounds.height / Double(gh)))
        let world = Vector2(cell.x * Double(gw), cell.y * Double(gh))

        self.count = count
        self.cellSize = cellSize
        self.cellExtent = cell
        self.origin = bounds.corner
        self.worldSize = world
        self.gridWidth = gw
        self.gridHeight = gh

        let numCells = gw * gh
        self.sortedIndices = ComputeBuffer(count: count)
        self.cellStart = ComputeBuffer(count: numCells)
        self.cellCount = ComputeBuffer(count: numCells)
        self.cellCursor = ComputeBuffer(count: numCells)
        self.scattered = ComputeBuffer(count: count)
        self.chunkStart = ComputeBuffer(count: numCells + 1)

        let grid = OllinSpatialGrid(
            origin: SIMD2<Float>(Float(bounds.x), Float(bounds.y)),
            worldSize: SIMD2<Float>(Float(world.x), Float(world.y)),
            cellSize: Float(cellSize),
            gridW: UInt32(gw), gridH: UInt32(gh), numCells: UInt32(numCells),
            cell: SIMD2<Float>(Float(cell.x), Float(cell.y)))
        self.gridBuffer = ComputeBuffer([grid])

        let source = SpatialHash.kernelSource
        self.clearKernel = ComputeKernel(entry: "ollin_hash_clear", source)
        self.countKernel = ComputeKernel(entry: "ollin_hash_count", source)
        self.scanKernel = ComputeKernel(entry: "ollin_hash_scan", source)
        self.scatterKernel = ComputeKernel(entry: "ollin_hash_scatter", source)
        self.rankKernel = ComputeKernel(entry: "ollin_hash_rank", source)
    }

    /// Record the counting sort over `particles`' positions: clear the per-cell
    /// counts, count, prefix-sum into start offsets, scatter indices into slots,
    /// then, when the frame's clock can repeat, rank each particle among its
    /// cell's indices.
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
        // scan: exclusive prefix sum into cellStart (3), seed the cursor (6), read count (4),
        // and each cell's first rank chunk (7)
        drawer.recordDispatch(RecordedDispatch(
            kernel: scanKernel, threadCount: 1,
            buffers: [nil, nil, nil, cellStart, cellCount, gridBuffer, cellCursor, chunkStart],
            params: []))
        // scatter: write each particle index into its cell's next free slot (out 1,
        // cursor 6), straight into the query's order live, or into scratch for
        // the rank pass when the run can repeat
        let ranks = drawer.runsOnFixedClock
        drawer.recordDispatch(RecordedDispatch(
            kernel: scatterKernel, threadCount: count,
            buffers: [particles, ranks ? scattered : sortedIndices, nil, nil, nil, gridBuffer, cellCursor],
            params: []))
        guard ranks else { return }
        // rank: each particle at its place among its cell's indices, 32 members a
        // chunk (scattered 1, sorted 2, start 3, count 4, grid 5, chunks 7). The
        // chunk total is only known on the GPU, so the dispatch covers the most
        // there can be, one per 32 particles plus one per cell for the
        // remainders, and the threads past the total return at once.
        drawer.recordDispatch(RecordedDispatch(
            kernel: rankKernel, threadCount: (count / 32 + numCells + 1) * 32,
            buffers: [nil, scattered, sortedIndices, cellStart, cellCount, gridBuffer, nil, chunkStart],
            params: []))
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
        device uint *chunkStart [[buffer(7)]],
        uint id [[thread_position_in_grid]]) {
        if (id != 0u) { return; }
        uint acc = 0u;
        uint chunks = 0u;
        for (uint c = 0u; c < grid.numCells; ++c) {
            cellStart[c] = acc;
            cellCursor[c] = acc;
            chunkStart[c] = chunks;
            uint n = cellCount[c];
            acc += n;
            chunks += (n + 31u) / 32u;
        }
        chunkStart[grid.numCells] = chunks;
    }

    // Scatter each particle's index into the next free slot of its cell. The
    // slot within the cell is whichever the thread reached first; live that is
    // the order a query reads, and for a run that repeats it is scratch the
    // rank pass reads.
    kernel void ollin_hash_scatter(
        device const OllinParticle *particles [[buffer(0)]],
        device uint *scattered [[buffer(1)]],
        constant OllinSpatialGrid &grid [[buffer(5)]],
        device atomic_uint *cellCursor [[buffer(6)]],
        constant OllinComputeUniforms &u [[buffer(10)]],
        uint id [[thread_position_in_grid]]) {
        if (id >= u.particleCount) { return; }
        uint cell = ollin_grid_cell(particles[id].position, grid);
        uint slot = atomic_fetch_add_explicit(&cellCursor[cell], 1u, memory_order_relaxed);
        scattered[slot] = id;
    }

    // Place each particle at its rank among its cell's indices, so a query that
    // sums over a cell adds the same numbers in the same order on every run. The
    // rank is how many of the cell's particles have a smaller index. The work is
    // cut into chunks of 32 members, 32 threads a chunk, so every thread of a
    // chunk runs the same count and reads the same address at each step, and a
    // cell a clumping sim has packed with thousands spreads over as many chunks.
    // (One thread per particle would leave each SIMD group waiting on the
    // densest cell among its 32; one SIMD group per cell would put a packed
    // cell on a single core.)
    kernel void ollin_hash_rank(
        device const uint *scattered [[buffer(1)]],
        device uint *sortedIndices [[buffer(2)]],
        device const uint *cellStart [[buffer(3)]],
        device const uint *cellCount [[buffer(4)]],
        constant OllinSpatialGrid &grid [[buffer(5)]],
        device const uint *chunkStart [[buffer(7)]],
        uint tid [[thread_position_in_grid]]) {
        uint chunk = tid / 32u;
        if (chunk >= chunkStart[grid.numCells]) { return; }
        // The chunk's cell: the last one whose run starts at or before it.
        uint lo = 0u, hi = grid.numCells;
        while (hi - lo > 1u) {
            uint mid = (lo + hi) / 2u;
            if (chunkStart[mid] <= chunk) { lo = mid; } else { hi = mid; }
        }
        uint start = cellStart[lo];
        uint n = cellCount[lo];
        uint i = (chunk - chunkStart[lo]) * 32u + tid % 32u;
        if (i >= n) { return; }
        uint v = scattered[start + i];
        uint rank = 0u;
        for (uint k = 0u; k < n; ++k) {
            rank += (scattered[start + k] < v) ? 1u : 0u;
        }
        sortedIndices[start + rank] = v;
    }
    """
}
