import Ollin
import Testing

/// Pure-CPU checks on `spanningTree(through:)`: the chains cover exactly the
/// minimum spanning tree (matched against brute force), the decomposition is
/// minimal and complete, and degenerate inputs pass through. No GPU.
@Suite
struct SpanningTreeTests {
    /// A seeded scatter of points to span.
    private func scatter(_ count: Int, seed: UInt64) -> [Vector2] {
        var rng = SplitMix64(seed: seed)
        return (0 ..< count).map { _ in
            Vector2(Double.random(in: 0 ..< 400, using: &rng),
                    Double.random(in: 0 ..< 300, using: &rng))
        }
    }

    private func totalLength(_ chains: [Contour]) -> Double {
        chains.reduce(0) { sum, chain in
            var length = 0.0
            for i in 1 ..< chain.points.count {
                length += chain.points[i - 1].distance(to: chain.points[i])
            }
            return sum + length
        }
    }

    private func edgeCount(_ chains: [Contour]) -> Int {
        chains.reduce(0) { $0 + $1.points.count - 1 }
    }

    /// Brute-force Prim, the O(n^2) reference the fast build must match.
    private func primLength(_ points: [Vector2]) -> Double {
        var inTree = [Bool](repeating: false, count: points.count)
        var best = [Double](repeating: .infinity, count: points.count)
        inTree[0] = true
        for i in 1 ..< points.count { best[i] = points[i].distanceSquared(to: points[0]) }
        var total = 0.0
        for _ in 1 ..< points.count {
            var pick = -1
            var pickDistance = Double.infinity
            for i in 0 ..< points.count where !inTree[i] && best[i] < pickDistance {
                pickDistance = best[i]
                pick = i
            }
            inTree[pick] = true
            total += pickDistance.squareRoot()
            for i in 0 ..< points.count where !inTree[i] {
                best[i] = min(best[i], points[i].distanceSquared(to: points[pick]))
            }
        }
        return total
    }

    /// The chains hold n - 1 edges, reach every input point, and connect:
    /// together they are a spanning tree.
    @Test func chainsFormASpanningTree() {
        let points = scatter(300, seed: 5)
        let chains = spanningTree(through: points)
        #expect(edgeCount(chains) == points.count - 1)

        var index: [String: Int] = [:]
        for (i, p) in points.enumerated() { index["\(p.x),\(p.y)"] = i }
        var parent = Array(points.indices)
        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r { r = parent[r] }
            return r
        }
        var covered = Set<Int>()
        for chain in chains {
            for i in 1 ..< chain.points.count {
                let a = index["\(chain.points[i - 1].x),\(chain.points[i - 1].y)"]!
                let b = index["\(chain.points[i].x),\(chain.points[i].y)"]!
                covered.insert(a)
                covered.insert(b)
                parent[find(a)] = find(b)
            }
        }
        #expect(covered.count == points.count)
        #expect(points.indices.allSatisfy { find($0) == find(0) })
    }

    /// The total length equals the brute-force minimum spanning tree's: the
    /// Delaunay-restricted build loses nothing.
    @Test func matchesBruteForceMinimum() {
        for seed: UInt64 in [3, 11, 27] {
            let points = scatter(160, seed: seed)
            let chains = spanningTree(through: points)
            let reference = primLength(points)
            #expect(abs(totalLength(chains) - reference) < 1e-6 * reference)
        }
    }

    /// One chain per pair of odd-degree vertices: the decomposition never
    /// spends more pen lifts than the branching demands.
    @Test func decompositionIsMinimal() {
        let points = scatter(220, seed: 9)
        let chains = spanningTree(through: points)
        var degree: [String: Int] = [:]
        for chain in chains {
            for i in 1 ..< chain.points.count {
                degree["\(chain.points[i - 1].x),\(chain.points[i - 1].y)", default: 0] += 1
                degree["\(chain.points[i].x),\(chain.points[i].y)", default: 0] += 1
            }
        }
        let odd = degree.values.count { $0 % 2 == 1 }
        #expect(chains.count == odd / 2)
    }

    /// The same points span the same way.
    @Test func spanIsDeterministic() {
        let points = scatter(250, seed: 13)
        let a = spanningTree(through: points)
        let b = spanningTree(through: points)
        #expect(a.count == b.count)
        #expect(zip(a, b).allSatisfy { $0.points == $1.points })
    }

    /// Degenerate inputs pass through without trouble.
    @Test func degenerateInputsAreSafe() {
        #expect(spanningTree(through: []).isEmpty)
        #expect(spanningTree(through: [Vector2(1, 1)]).isEmpty)

        let pair = spanningTree(through: [Vector2(1, 1), Vector2(4, 5)])
        #expect(pair.count == 1)
        #expect(pair[0].points.count == 2)

        // Collinear points: one chain walking the line in order.
        let line = (0 ..< 50).map { Vector2(Double($0) * 3, 10) }
        let chained = spanningTree(through: line.shuffledDeterministically())
        #expect(edgeCount(chained) == 49)
        #expect(abs(totalLength(chained) - 147) < 1e-9)

        // Coincident points: still spans all, at zero length, no hang.
        let same = [Vector2](repeating: Vector2(5, 5), count: 20)
        let spanned = spanningTree(through: same)
        #expect(edgeCount(spanned) == 19)
        #expect(totalLength(spanned) == 0)

        // Duplicates beside a real triangle: the stragglers still join.
        var mixed = [Vector2(0, 0), Vector2(90, 10), Vector2(40, 80)]
        mixed.append(contentsOf: [Vector2](repeating: Vector2(90, 10), count: 5))
        #expect(edgeCount(spanningTree(through: mixed)) == mixed.count - 1)
    }
}

private extension [Vector2] {
    /// A fixed reshuffle so the collinear test doesn't hand the input in
    /// sorted order.
    func shuffledDeterministically() -> [Vector2] {
        var rng = SplitMix64(seed: 99)
        var copy = self
        copy.shuffle(using: &rng)
        return copy
    }
}
