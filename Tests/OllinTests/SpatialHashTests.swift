import CoreGraphics
import Foundation
import Testing
import simd
import COllinShaders   // OllinParticle
@testable import Ollin

/// The GPU spatial-hash neighbor search and the artificial-life sims built on it. The
/// grid math and struct layout run everywhere; the counting-sort correctness and the
/// sims' evolution are Metal-gated and refuse themselves without a GPU (`Snapshot.hasMetal`).
///
/// The scatter lists a cell's particles in whatever order the GPU's threads arrive;
/// a run that can repeat then ranks them into index order, and a live frame keeps
/// the scatter's order. The set facts hold on both paths: the per-cell counts, the
/// exact prefix sum, that `sortedIndices` is a permutation, that each cell's bucket
/// holds exactly the right particles, and that a particle's neighbor *set* matches
/// brute force. The index order is the export path's own law. (The sims still carry
/// no pixel snapshot: a chaotic run repeats on one GPU, and another GPU's arithmetic
/// can take it somewhere else.)
@Suite
@MainActor
struct SpatialHashTests {

    // MARK: GPU-free: grid derivation & layout

    @Test func gridStrideMatchesHeader() {
        // The shared CPU/GPU struct is stride 32 (float2 @0, float2 @8, float @16,
        // three uints @20…28). A drift here would corrupt every hash dispatch.
        #expect(MemoryLayout<OllinSpatialGrid>.stride == 40)
    }

    @Test func gridDerivation() {
        // radius divides bounds evenly: the world equals the bounds, grid is 8×8.
        let h = SpatialHash(bounds: Rectangle(x: 0, y: 0, width: 400, height: 400),
                            cellSize: 50, count: 100)
        #expect(h.gridWidth == 8 && h.gridHeight == 8)
        #expect(h.worldSize.x == 400 && h.worldSize.y == 400)
        #expect(h.cellCount.count == 64 && h.sortedIndices.count == 100)
    }

    @Test func theWorldIsTheBoundsWhenTheRadiusDoesNotDivideThem() {
        // 253 by 340 at a radius of 15 is 16 by 22 cells. The world used to be
        // 240 by 330, the last whole cells, and a sim seeded and wrapped inside
        // it left a bare strip along the far edges of the bounds it was given.
        let h = SpatialHash(bounds: Rectangle(x: 10, y: 20, width: 253, height: 340),
                            cellSize: 15, count: 100)
        #expect(h.gridWidth == 16 && h.gridHeight == 22)
        #expect(h.worldSize.x == 253 && h.worldSize.y == 340)
        #expect(h.cellExtent.x >= 15 && h.cellExtent.y >= 15,
                "a cell is never narrower than the query radius")
        #expect(abs(h.cellExtent.x * 16 - 253) < 1e-9 && abs(h.cellExtent.y * 22 - 340) < 1e-9)
    }

    @Test func gridClampsToThree() {
        // A domain narrower than three cells clamps to 3 (so the wrapped 3×3 block
        // never revisits a cell), rounding the world up past the bounds.
        let h = SpatialHash(bounds: Rectangle(x: 0, y: 0, width: 40, height: 40),
                            cellSize: 30, count: 10)
        #expect(h.gridWidth == 3 && h.gridHeight == 3)
        #expect(h.worldSize.x == 90 && h.worldSize.y == 90)
    }

    @Test func suggestedCountIsPositive() {
        let n = PPS.suggestedCount(for: 22, in: Rectangle(x: 0, y: 0, width: 1080, height: 1080))
        #expect(n > 0)
    }

    // MARK: Metal-gated: the counting sort is correct

    @Test(.enabled(if: Snapshot.hasMetal))
    func countingSortIsCorrect() throws {
        let side = 400.0, radius = 50.0, world = Float(400)   // radius divides side, so world == bounds
        let gw = 8
        var rng = SplitMix64(seed: 0xA11CE)
        let positions = (0..<600).map { _ in
            SIMD2<Float>(Float(Double.random(in: 1..<399, using: &rng)),
                         Float(Double.random(in: 1..<399, using: &rng)))
        }
        let sketch = HashProbeSketch()
        sketch.probeBounds = Rectangle(x: 0, y: 0, width: side, height: side)
        sketch.radius = radius
        sketch.positions = positions
        _ = try OllinApp.image(of: sketch, frame: 0)   // runs the build on the GPU

        guard let counts = sketch.hash.cellCount.snapshot(),
              let starts = sketch.hash.cellStart.snapshot(),
              let sorted = sketch.hash.sortedIndices.snapshot() else {
            Issue.record("hash buffers never realized")
            return
        }
        let n = positions.count

        // Counts sum to N, and cellStart is the exact exclusive prefix sum.
        #expect(counts.reduce(0, +) == UInt32(n))
        var acc: UInt32 = 0
        for c in 0..<counts.count {
            #expect(starts[c] == acc)
            acc += counts[c]
        }

        // sortedIndices is a permutation of 0..<N.
        #expect(Set(sorted) == Set(0..<UInt32(n)))

        // Each cell's bucket holds exactly the particles whose (Float) cell is that
        // cell, so the counting sort bucketed correctly.
        func cell(_ p: SIMD2<Float>) -> Int {
            let cx = ((Int((p.x / Float(radius)).rounded(.down)) % gw) + gw) % gw
            let cy = ((Int((p.y / Float(radius)).rounded(.down)) % gw) + gw) % gw
            return cy * gw + cx
        }
        var byCell: [Int: Set<Int>] = [:]
        for (i, p) in positions.enumerated() { byCell[cell(p), default: []].insert(i) }
        for c in 0..<counts.count {
            let s = Int(starts[c]), e = s + Int(counts[c])
            let bucket = Set(sorted[s..<e].map { Int($0) })
            #expect(bucket == (byCell[c] ?? []))
        }

        // The hash's neighbor set (3×3 wrapped walk, within radius) matches brute force
        // for a spread of sample particles.
        func torusDelta(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            var d = b - a
            d.x -= world * (d.x / world).rounded()
            d.y -= world * (d.y / world).rounded()
            return (d.x * d.x + d.y * d.y).squareRoot()
        }
        for i in stride(from: 0, to: n, by: 37) {
            let p = positions[i]
            let brute = Set((0..<n).filter { $0 != i && torusDelta(p, positions[$0]) < Float(radius) })
            var viaHash: Set<Int> = []
            let base = cell(p)
            let bx = base % gw, by = base / gw
            for dy in -1...1 {
                for dx in -1...1 {
                    let cx = ((bx + dx) % gw + gw) % gw
                    let cy = ((by + dy) % gw + gw) % gw
                    let c = cy * gw + cx
                    let s = Int(starts[c]), e = s + Int(counts[c])
                    for k in s..<e {
                        let j = Int(sorted[k])
                        if j != i && torusDelta(p, positions[j]) < Float(radius) { viaHash.insert(j) }
                    }
                }
            }
            #expect(viaHash == brute)
        }
    }

    /// Particles packed into a few cells of the 8×8 grid the counting-sort test
    /// uses: one cell holds 300 (ten of the rank pass's 32-member chunks), and
    /// others hold counts either side of a chunk's edge (31, 32, 33, 64, 65),
    /// where a slip in the chunk walk would show, with 100 more spread out.
    private func packedLayout() -> [SIMD2<Float>] {
        var rng = SplitMix64(seed: 0xC0FFEE)
        func inCell(_ cx: Int, _ cy: Int, _ n: Int) -> [SIMD2<Float>] {
            (0..<n).map { _ in
                SIMD2<Float>(Float(Double(cx) * 50 + Double.random(in: 1..<49, using: &rng)),
                             Float(Double(cy) * 50 + Double.random(in: 1..<49, using: &rng)))
            }
        }
        var positions = inCell(1, 1, 300) + inCell(3, 3, 33) + inCell(5, 5, 32)
            + inCell(6, 2, 31) + inCell(2, 6, 64) + inCell(7, 7, 65)
        positions += (0..<100).map { _ in
            SIMD2<Float>(Float(Double.random(in: 1..<399, using: &rng)),
                         Float(Double.random(in: 1..<399, using: &rng)))
        }
        positions.shuffle(using: &rng)
        return positions
    }

    /// The hash's three buffers after one build over `positions`, drawn the way
    /// an export draws it.
    private func build(_ positions: [SIMD2<Float>]) throws -> (counts: [UInt32], starts: [UInt32], sorted: [UInt32]) {
        let sketch = HashProbeSketch()
        sketch.probeBounds = Rectangle(x: 0, y: 0, width: 400, height: 400)
        sketch.radius = 50
        sketch.positions = positions
        _ = try OllinApp.image(of: sketch, frame: 0)
        let counts = try #require(sketch.hash.cellCount.snapshot())
        let starts = try #require(sketch.hash.cellStart.snapshot())
        let sorted = try #require(sketch.hash.sortedIndices.snapshot())
        return (counts, starts, sorted)
    }

    /// Every particle sits in the bucket of its own cell, and each exactly once.
    private func expectBucketed(_ positions: [SIMD2<Float>], counts: [UInt32], starts: [UInt32],
                                sorted: [UInt32]) {
        #expect(Set(sorted) == Set(0..<UInt32(positions.count)))
        for c in 0..<counts.count {
            let s = Int(starts[c]), e = s + Int(counts[c])
            let expected = Set(positions.indices.filter {
                Int(positions[$0].y / 50) * 8 + Int(positions[$0].x / 50) == c
            })
            #expect(Set(sorted[s..<e].map { Int($0) }) == expected, "cell \(c)")
        }
    }

    /// In a run that can repeat (an export, a take playing back), every cell
    /// lists its particles in index order, so a query that sums over its
    /// neighbors adds the same numbers in the same order on every run. The
    /// scatter alone lists them in whatever order the GPU's threads arrive,
    /// and in a chaotic sim that rounding difference became a different picture
    /// (ParticleLife, the swarms, the fluid: 31 to 78 percent of the pixels by
    /// the eighth second).
    @Test(.enabled(if: Snapshot.hasMetal))
    func aRunThatCanRepeatListsEachCellInIndexOrder() throws {
        let positions = packedLayout()
        let (counts, starts, sorted) = try build(positions)
        expectBucketed(positions, counts: counts, starts: starts, sorted: sorted)
        #expect((counts.max() ?? 0) >= 300)
        for c in 0..<counts.count {
            let s = Int(starts[c]), e = s + Int(counts[c])
            let bucket = Array(sorted[s..<e])
            #expect(bucket == bucket.sorted(), "cell \(c) is out of index order")
        }
    }

    /// A live frame keeps the one-pass scatter: ranking costs a clumping sim a
    /// fifth of its step, and a clock that follows the wall never repeats a
    /// run anyway. `--bench` stands in for a live window, so it takes the live
    /// path too, and the buckets it leaves are still whole.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aLiveFrameStillBucketsEveryParticle() throws {
        OllinApp.isBenchmarking = true
        defer { OllinApp.isBenchmarking = false }
        let positions = packedLayout()
        let (counts, starts, sorted) = try build(positions)
        expectBucketed(positions, counts: counts, starts: starts, sorted: sorted)
    }

    // MARK: Metal-gated: the sims evolve without blowing up

    @Test(.enabled(if: Snapshot.hasMetal))
    func particleLifeAndPPSStayFinite() throws {
        let life = ParticleLifeProbe()
        _ = try OllinApp.image(of: life, frame: 4)
        guard let ps = life.life.current.snapshot() else {
            Issue.record("ParticleLife never realized"); return
        }
        #expect(ps.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
        #expect(!ps.allSatisfy { $0.position == ps[0].position })   // not collapsed to a point

        let pps = PPSProbe()
        _ = try OllinApp.image(of: pps, frame: 4)
        guard let qs = pps.pps.current.snapshot() else {
            Issue.record("PPS never realized"); return
        }
        #expect(qs.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func physarumGrowsATrail() throws {
        let sketch = PhysarumProbe()
        guard let image = try? OllinApp.image(of: sketch, frame: 12) else {
            Issue.record("render failed"); return
        }
        #expect(maxLuma(of: image) > 0.1)   // the trail lit the canvas
    }

    private func maxLuma(of image: CGImage) -> Double {
        let bytes = pixels(of: image)
        var peak: UInt8 = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            peak = max(peak, bytes[i], bytes[i + 1], bytes[i + 2])
        }
        return Double(peak) / 255
    }
}

/// Builds a `SpatialHash` over CPU-authored positions and runs one build via an
/// identity neighbor step, so a test can read the hash buffers back and check them.
@MainActor
private final class HashProbeSketch: Sketch {
    var positions: [SIMD2<Float>] = []
    var probeBounds = Rectangle(x: 0, y: 0, width: 400, height: 400)
    var radius = 50.0
    private(set) var hash: SpatialHash!
    private var reading: ComputeBuffer<OllinParticle>!
    private var writing: ComputeBuffer<OllinParticle>!
    private let identity = ComputeKernel(entry: "hash_identity", """
        kernel void hash_identity(
            device const OllinParticle *inBuf  [[buffer(0)]],
            device OllinParticle       *outBuf [[buffer(1)]],
            constant OllinComputeUniforms &u [[buffer(10)]],
            uint id [[thread_position_in_grid]]) {
            if (id >= u.particleCount) { return; }
            outBuf[id] = inBuf[id];
        }
    """)

    override func setup() {
        hash = SpatialHash(bounds: probeBounds, cellSize: radius, count: positions.count)
        let parts = positions.map {
            OllinParticle(position: $0, velocity: .zero, color: SIMD4<Float>(1, 1, 1, 1),
                          size: 1, life: 1, seedA: 0, seedB: 0)
        }
        reading = ComputeBuffer(parts)
        writing = ComputeBuffer(count: positions.count)
    }

    override func draw() {
        neighborStep(identity, over: hash, reading: reading, writing: writing)
    }
}

@MainActor
private final class ParticleLifeProbe: Sketch {
    var life: ParticleLife!
    override func setup() { life = makeParticleLife(count: 2_000, kinds: 4, radius: 40, seed: 7) }
    override func draw() { stepParticleLife(life) }
}

@MainActor
private final class PPSProbe: Sketch {
    var pps: PPS!
    override func setup() { pps = makePrimordialParticles(count: 3_000, radius: 24, seed: 9) }
    override func draw() { stepPrimordialParticles(pps) }
}

@MainActor
private final class PhysarumProbe: Sketch {
    var slime: Physarum!
    override func setup() { slime = makePhysarum(agents: 20_000, resolution: 256, seed: 3) }
    override func draw() {
        stepPhysarum(slime)
        drawImage(slime.image, in: bounds)
    }
}
