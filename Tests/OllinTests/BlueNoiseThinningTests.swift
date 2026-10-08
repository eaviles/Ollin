import Foundation
import Testing
@testable import Ollin

/// The even-spacing pass behind `surfacePoints(..., scatter: .blueNoise)` finds
/// its neighbors through the occupied cells only. The reference below runs the
/// same rule the plainest way, over a dense grid of the whole bounding box, and
/// every case here asks for the same survivors from both, to the point. The
/// order a neighbor walk takes decides how each weight's sum rounds, so a walk
/// that visited the same neighbors in another order would show up here as a
/// different pick wherever two weights come within a rounding of each other.
/// No GPU.
@Suite
struct BlueNoiseThinningTests {

    // MARK: - The reference

    /// The pass over a dense grid: neighbors through `PointGrid3`, and a
    /// heaviest-first heap that takes a fresh entry each time a weight changes
    /// and skips the stale ones as they surface.
    static func denseGridSurvivors(of positions: [Vector3], count: Int, area: Double) -> [Int] {
        let m = positions.count
        guard count < m, count > 0, area > 0 else { return Array(0 ..< min(count, m)) }
        let rMax = (area / (2 * 3.0.squareRoot() * Double(count))).squareRoot()
        let dMax = 2 * rMax
        guard dMax > 0, dMax.isFinite else { return Array(0 ..< count) }
        let dMin = dMax * 0.65 * (1 - pow(Double(count) / Double(m), 1.5))
        let grid = PointGrid3(points: positions, cellSize: dMax)
        func weight(_ d2: Double) -> Double {
            let d = min(max(d2.squareRoot(), dMin), dMax)
            let t = 1 - d / dMax
            let t2 = t * t, t4 = t2 * t2
            return t4 * t4
        }
        var weights = [Double](repeating: 0, count: m)
        var heap = ReferenceHeap()
        for i in 0 ..< m {
            var w = 0.0
            grid.forEachNeighbor(of: positions[i], within: dMax) { j, d2 in
                if j != i { w += weight(d2) }
            }
            weights[i] = w
            heap.push(w, i)
        }
        var dropped = [Bool](repeating: false, count: m)
        var left = m
        while left > count, let top = heap.pop() {
            let i = top.item
            if dropped[i] || top.key != weights[i] { continue }
            dropped[i] = true
            left -= 1
            grid.forEachNeighbor(of: positions[i], within: dMax) { j, d2 in
                guard j != i, !dropped[j] else { return }
                weights[j] -= weight(d2)
                heap.push(weights[j], j)
            }
        }
        return (0 ..< m).filter { !dropped[$0] }
    }

    struct ReferenceHeap {
        var entries: [(key: Double, item: Int)] = []
        func heavier(_ a: Int, _ b: Int) -> Bool {
            entries[a].key > entries[b].key
                || (entries[a].key == entries[b].key && entries[a].item > entries[b].item)
        }
        mutating func push(_ key: Double, _ item: Int) {
            entries.append((key, item))
            var child = entries.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard heavier(child, parent) else { break }
                entries.swapAt(child, parent)
                child = parent
            }
        }
        mutating func pop() -> (key: Double, item: Int)? {
            guard let first = entries.first else { return nil }
            entries.swapAt(0, entries.count - 1)
            entries.removeLast()
            var parent = 0
            while true {
                let l = 2 * parent + 1, r = l + 1
                var top = parent
                if l < entries.count, heavier(l, top) { top = l }
                if r < entries.count, heavier(r, top) { top = r }
                if top == parent { break }
                entries.swapAt(parent, top)
                parent = top
            }
            return first
        }
    }

    // MARK: - What the sampling tests ask for

    /// Every `.blueNoise` scatter the surface-sampling tests make, with its
    /// mesh, count, and seed: the candidates are the plain draw of five times
    /// the count from the same seed, which is what the scatter thins.
    @Test(arguments: [
        ("lopsided", 4_000, 12 as UInt64),
        ("plane 10", 900, 19),
        ("plane 8", 462, 20),
        ("torus", 300, 5),
        ("torus", 300, 6),
    ])
    func everyScatterTheTestsMakeIsUnchanged(mesh name: String, count: Int, seed: UInt64) {
        let mesh: Mesh = switch name {
        case "lopsided": SurfaceSamplingTests.lopsided()
        case "plane 10": Mesh.plane(width: 10, depth: 10)
        case "plane 8": Mesh.plane(width: 8, depth: 8)
        default: Mesh.torus(radius: 1, tube: 0.3)
        }
        var draw = SplitMix64(seed: seed)
        let candidates = surfacePoints(on: mesh, count: count * 5, scatter: .random, using: &draw)
        let positions = candidates.map(\.position)
        let survivors = blueNoiseSurvivors(of: positions, count: count, area: mesh.surfaceArea)
        #expect(survivors.count == count)
        #expect(survivors == Self.denseGridSurvivors(of: positions, count: count, area: mesh.surfaceArea))

        // And the scatter itself is those survivors, in the order they were drawn.
        var again = SplitMix64(seed: seed)
        let scattered = surfacePoints(on: mesh, count: count, using: &again)
        #expect(scattered == survivors.map { candidates[$0] })
    }

    /// A terrain big enough that its rows hold many cells and a point's nine
    /// runs come from all over the sorted order, thinned at several counts.
    /// (A count small enough that every point reaches every other is left to
    /// the awkward inputs below, which are small enough for the reference to
    /// walk that quickly.)
    @Test func aTerrainThinsTheSameAtEveryCount() {
        let field = Heightfield(columns: 48, rows: 48) { u, v in
            0.5 + 0.3 * sin(u * 9) * cos(v * 7) + 0.1 * sin(u * 31 + v * 17)
        }
        let land = field.mesh(width: 40, depth: 40, height: 12)
        var draw = SplitMix64(seed: 29)
        let positions = surfacePoints(on: land, count: 12_000, scatter: .random, using: &draw).map(\.position)
        for count in [600, 2_400, 6_000, 11_999] {
            #expect(blueNoiseSurvivors(of: positions, count: count, area: land.surfaceArea)
                    == Self.denseGridSurvivors(of: positions, count: count, area: land.surfaceArea),
                    "count \(count)")
        }
    }

    // MARK: - Awkward inputs

    /// Inputs picked to make weights tie exactly or the grid degenerate: points
    /// stacked on a lattice (equal weights everywhere, so the tie rule decides),
    /// one point repeated, a line, a shell, and a spread far below the smallest
    /// cell the grid allows.
    @Test(arguments: ["lattice", "one point", "line", "shell", "below the floor"])
    func awkwardInputsThinTheSame(_ kind: String) {
        var rng = SplitMix64(seed: 41)
        var positions: [Vector3] = []
        var area = 1.0
        for _ in 0 ..< 600 {
            let u = Double.random(in: 0 ..< 1, using: &rng), v = Double.random(in: 0 ..< 1, using: &rng)
            switch kind {
            case "lattice":
                positions.append(Vector3((u * 4).rounded(), (v * 4).rounded(), 0)); area = 16
            case "one point":
                positions.append(Vector3(1, 2, 3))
            case "line":
                positions.append(Vector3(u * 100, 0, 0))
            case "shell":
                let a = u * .tau, b = acos(2 * v - 1)
                positions.append(Vector3(50 * sin(b) * cos(a), 50 * cos(b), 50 * sin(b) * sin(a)))
                area = 4 * .pi * 2_500
            default:
                positions.append(Vector3(u * 1e-9, v * 1e-9, 0)); area = 1e-18
            }
        }
        for count in [1, 2, 120, 300, 599, 600] {
            #expect(blueNoiseSurvivors(of: positions, count: count, area: area)
                    == Self.denseGridSurvivors(of: positions, count: count, area: area),
                    "count \(count)")
        }
    }

    /// Nothing to thin: the first `count` come back, as the pass always did.
    @Test func aCountAtOrPastTheCandidatesKeepsThemAll() {
        let positions = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]
        #expect(blueNoiseSurvivors(of: positions, count: 3, area: 1) == [0, 1, 2])
        #expect(blueNoiseSurvivors(of: positions, count: 9, area: 1) == [0, 1, 2])
        #expect(blueNoiseSurvivors(of: positions, count: 2, area: 0) == [0, 1])
        #expect(blueNoiseSurvivors(of: [], count: 2, area: 1).isEmpty)
    }
}
