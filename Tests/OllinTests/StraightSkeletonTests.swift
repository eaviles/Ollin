import Ollin
import Testing

/// Pure-CPU checks on `straightSkeleton(of:)`, pinned to exact geometry
/// wherever a shape has a closed-form skeleton: the square's diagonals, the
/// rectangle's ridge, the regular polygon's spokes, mitered insets compared
/// against hand-offset polygons, and the degenerate pile-ups (a plus sign's
/// four simultaneous splits, a collinear midpoint, a symmetric square ring
/// whose wavefronts annihilate along whole lines). The universal invariant
/// throughout: the faces partition the shape, so their areas must sum to
/// its area. No GPU.
@Suite
struct StraightSkeletonTests {
    private let tol = 1e-9

    // MARK: Helpers

    private func area(of ring: [Vector2]) -> Double {
        var sum = 0.0
        for i in ring.indices {
            let a = ring[i], b = ring[(i + 1) % ring.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    private func signedArea(of shape: Shape) -> Double {
        shape.contours.reduce(0) { $0 + area(of: $1.points) }
    }

    private func sortedPoints(of shape: Shape) -> [Vector2] {
        shape.contours.flatMap(\.points)
            .sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
    }

    private func expectSamePoints(_ shape: Shape, _ expected: [Vector2],
                                  within tolerance: Double = 1e-7) {
        let got = sortedPoints(of: shape)
        let want = expected.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        #expect(got.count == want.count)
        guard got.count == want.count else { return }
        for (g, w) in zip(got, want) {
            #expect((g - w).length < tolerance, "got \(g), wanted \(w)")
        }
    }

    /// The faces partition the shape: positive areas, summing to the whole.
    /// Pass `expecting` for holed shapes (a hole ring's stored orientation
    /// is whatever the caller gave, so the naive signed sum lies).
    private func expectFacesPartition(_ skeleton: StraightSkeleton, _ shape: Shape,
                                      expecting: Double? = nil,
                                      within relative: Double = 1e-9) {
        var total = 0.0
        for face in skeleton.faces {
            let a = area(of: face.points)
            #expect(a > 0, "face wound backward or corrupt")
            total += a
        }
        let expected = expecting ?? abs(signedArea(of: shape))
        #expect(abs(total - expected) <= relative * max(expected, 1),
                "faces cover \(total), shape is \(expected)")
    }

    // MARK: Exact closed forms

    @Test func squareCollapsesToItsCenter() {
        let square = Shape([Vector2(0, 0), Vector2(200, 0), Vector2(200, 200), Vector2(0, 200)])
        let skeleton = straightSkeleton(of: square)

        #expect(skeleton.faces.count == 4)
        #expect(abs(skeleton.maxInset - 100) < tol * 200)
        #expect(skeleton.arcs.count == 4)
        for arc in skeleton.arcs {
            #expect(arc.startDistance == 0)
            #expect((arc.end - Vector2(100, 100)).length < 1e-7)
            #expect(abs(arc.endDistance - 100) < 1e-7)
        }
        expectFacesPartition(skeleton, square)
        expectSamePoints(skeleton.inset(by: 50),
                         [Vector2(50, 50), Vector2(150, 50), Vector2(150, 150), Vector2(50, 150)])
    }

    @Test func rectangleGrowsItsRidge() {
        let rect = Shape([Vector2(0, 0), Vector2(300, 0), Vector2(300, 100), Vector2(0, 100)])
        let skeleton = straightSkeleton(of: rect)

        #expect(skeleton.faces.count == 4)
        #expect(abs(skeleton.maxInset - 50) < 1e-7)
        // Four corner diagonals plus the ridge between the two peaks.
        #expect(skeleton.arcs.count == 5)
        let ridge = skeleton.arcs.filter { $0.startDistance > 1 }
        #expect(ridge.count == 1)
        if let ridge = ridge.first {
            #expect((ridge.start - Vector2(50, 50)).length < 1e-7)
            #expect((ridge.end - Vector2(250, 50)).length < 1e-7)
        }
        expectFacesPartition(skeleton, rect)
        expectSamePoints(skeleton.inset(by: 25),
                         [Vector2(25, 25), Vector2(275, 25), Vector2(275, 75), Vector2(25, 75)])
    }

    @Test func regularPolygonSpokesMeetAtTheApothem() {
        let n = 5
        let radius = 100.0
        let corners = (0 ..< n).map { i in
            let angle = Double(i) / Double(n) * 2 * .pi
            return Vector2(radius * cos(angle), radius * sin(angle))
        }
        let skeleton = straightSkeleton(of: Shape(corners))
        let apothem = radius * cos(.pi / Double(n))

        #expect(skeleton.arcs.count == n)
        #expect(abs(skeleton.maxInset - apothem) < 1e-7)
        for arc in skeleton.arcs {
            #expect(arc.startDistance == 0)
            #expect(arc.end.length < 1e-7)
        }
        // The inset of a regular polygon is the same polygon scaled about
        // its center.
        let half = skeleton.inset(by: apothem / 2)
        expectSamePoints(half, corners.map { $0 * 0.5 })
        expectFacesPartition(skeleton, Shape(corners))
    }

    @Test func insetMatchesTheHandMiteredLShape() {
        let l = Shape([Vector2(0, 0), Vector2(10, 0), Vector2(10, 4),
                       Vector2(4, 4), Vector2(4, 10), Vector2(0, 10)])
        let skeleton = straightSkeleton(of: l)

        #expect(skeleton.faces.count == 6)
        #expect(abs(skeleton.maxInset - 2) < 1e-9)
        expectFacesPartition(skeleton, l)
        // Offsetting each edge inward by 1 and intersecting neighbors by
        // hand: the reflex corner slides diagonally to (3, 3).
        expectSamePoints(skeleton.inset(by: 1),
                         [Vector2(1, 1), Vector2(9, 1), Vector2(9, 3),
                          Vector2(3, 3), Vector2(3, 9), Vector2(1, 9)])
    }

    // MARK: Degenerate pile-ups

    @Test func plusSignSurvivesFourSimultaneousSplits() {
        let plus = Shape([Vector2(6, -2), Vector2(6, 2), Vector2(2, 2), Vector2(2, 6),
                          Vector2(-2, 6), Vector2(-2, 2), Vector2(-6, 2), Vector2(-6, -2),
                          Vector2(-2, -2), Vector2(-2, -6), Vector2(2, -6), Vector2(2, -2)])
        let skeleton = straightSkeleton(of: plus)

        #expect(skeleton.faces.count == 12)
        #expect(abs(skeleton.maxInset - 2) < 1e-9)
        expectFacesPartition(skeleton, plus)
        expectSamePoints(skeleton.inset(by: 1),
                         [Vector2(5, -1), Vector2(5, 1), Vector2(1, 1), Vector2(1, 5),
                          Vector2(-1, 5), Vector2(-1, 1), Vector2(-5, 1), Vector2(-5, -1),
                          Vector2(-1, -1), Vector2(-1, -5), Vector2(1, -5), Vector2(1, -1)])
    }

    @Test func notchPinchSplitsTheInsetInTwo() {
        let notched = Shape([Vector2(0, 0), Vector2(30, 0), Vector2(30, 10), Vector2(18, 10),
                             Vector2(18, 3), Vector2(12, 3), Vector2(12, 10), Vector2(0, 10)])
        let skeleton = straightSkeleton(of: notched)

        expectFacesPartition(skeleton, notched)
        // Shallow inset: still one ring, the notch mitered.
        let shallow = skeleton.inset(by: 1)
        #expect(shallow.contours.count == 1)
        // Past the pinch depth (the 3-unit strip under the notch halves at
        // 1.5), the region separates into two exact rectangles.
        let deep = skeleton.inset(by: 2)
        #expect(deep.contours.count == 2)
        expectSamePoints(deep,
                         [Vector2(2, 2), Vector2(10, 2), Vector2(10, 8), Vector2(2, 8),
                          Vector2(20, 2), Vector2(28, 2), Vector2(28, 8), Vector2(20, 8)])
    }

    @Test func holedSquareInsetsBothWays() {
        let ring = Shape(outer: [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)],
                         holes: [[Vector2(4, 3), Vector2(7, 3), Vector2(7, 6), Vector2(4, 6)]])
        let skeleton = straightSkeleton(of: ring)

        expectFacesPartition(skeleton, ring, expecting: 100 - 9)
        let inset = skeleton.inset(by: 1)
        #expect(inset.contours.count == 2)
        // The outer ring shrinks, the hole grows, and the signed areas keep
        // the hole a hole.
        expectSamePoints(inset,
                         [Vector2(1, 1), Vector2(9, 1), Vector2(9, 9), Vector2(1, 9),
                          Vector2(3, 2), Vector2(8, 2), Vector2(8, 7), Vector2(3, 7)])
        #expect(abs(signedArea(of: inset) - (64 - 25)) < 1e-7)
    }

    @Test func symmetricSquareRingAnnihilatesCleanly() {
        // Wavefronts from the outer square and the centered hole meet along
        // whole segments at once, the worst simultaneous-event pile-up.
        let ring = Shape(outer: [Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)],
                         holes: [[Vector2(4, 4), Vector2(6, 4), Vector2(6, 6), Vector2(4, 6)]])
        let skeleton = straightSkeleton(of: ring)

        #expect(!skeleton.arcs.isEmpty)
        #expect(abs(skeleton.maxInset - 2) < 1e-9)
        expectFacesPartition(skeleton, ring, expecting: 100 - 4)
        expectSamePoints(skeleton.inset(by: 1),
                         [Vector2(1, 1), Vector2(9, 1), Vector2(9, 9), Vector2(1, 9),
                          Vector2(3, 3), Vector2(7, 3), Vector2(7, 7), Vector2(3, 7)])
        #expect(straightSkeleton(of: ring) == skeleton)
    }

    @Test func collinearMidpointGrowsItsRib() {
        let square = Shape([Vector2(0, 0), Vector2(5, 0), Vector2(10, 0),
                            Vector2(10, 10), Vector2(0, 10)])
        let skeleton = straightSkeleton(of: square)

        #expect(skeleton.faces.count == 5)
        expectFacesPartition(skeleton, square)
        // The straight vertex rises perpendicular to its edges: a rib from
        // (5, 0) to the center.
        let rib = skeleton.arcs.first {
            ($0.start - Vector2(5, 0)).length < 1e-7 && ($0.end - Vector2(5, 5)).length < 1e-7
        }
        #expect(rib != nil)
        // The inset is unchanged by the extra vertex (one collinear point
        // rides along on the bottom edge).
        let inset = skeleton.inset(by: 2)
        #expect(abs(abs(signedArea(of: inset)) - 36) < 1e-7)
    }

    // MARK: Universal invariants on irregular shapes

    private func blob(seed: UInt64, points: Int, spikes: Double) -> Shape {
        var rng = SplitMix64(seed: seed)
        let ring = (0 ..< points).map { i in
            let angle = Double(i) / Double(points) * 2 * .pi
            let r = 100 + spikes * sin(angle * 5) + Double.random(in: -8...8, using: &rng)
            return Vector2(200 + r * cos(angle), 200 + r * sin(angle))
        }
        return Shape(ring)
    }

    @Test func facesPartitionIrregularBlobs() {
        for seed: UInt64 in [3, 11, 27, 63] {
            let shape = blob(seed: seed, points: 28, spikes: 30)
            let skeleton = straightSkeleton(of: shape)
            #expect(skeleton.faces.count == 28, "seed \(seed)")
            expectFacesPartition(skeleton, shape, within: 1e-7)

            // Every arc stays inside the shape.
            for arc in skeleton.arcs {
                let mid = (arc.start + arc.end) * 0.5
                #expect(shape.contains(mid), "seed \(seed): arc escaped at \(mid)")
            }

            // Insets nest: each ring of a deeper inset lies inside the shape
            // and inside the shallower inset.
            let shallow = skeleton.inset(by: skeleton.maxInset * 0.25)
            let deep = skeleton.inset(by: skeleton.maxInset * 0.6)
            #expect(!shallow.contours.isEmpty, "seed \(seed)")
            for contour in deep.contours {
                for p in contour.points {
                    #expect(shape.contains(p), "seed \(seed)")
                    #expect(shallow.contains(p), "seed \(seed)")
                }
            }
        }
    }

    @Test func facesPartitionSpikyBlobs() {
        // Deep nine-lobed spikes cascade split events and once left ghost
        // corners (two coincident wavefront vertices flanking a zero-length
        // front) that starved a LAV; the coincident-neighbor merge keeps the
        // partition exact.
        for seed: UInt64 in [7, 19] {
            var rng = SplitMix64(seed: seed)
            let ring = (0 ..< 160).map { i -> Vector2 in
                let angle = Double(i) / 160 * 2 * .pi
                let r = 400 + 80 * sin(angle * 9) + Double.random(in: -6...6, using: &rng)
                return Vector2(600 + r * cos(angle), 600 + r * sin(angle))
            }
            let shape = Shape(ring)
            let skeleton = straightSkeleton(of: shape)
            #expect(skeleton.faces.count == 160, "seed \(seed)")
            expectFacesPartition(skeleton, shape, within: 1e-7)
        }
    }

    @Test func facesPartitionATwoHoledSlab() {
        let slab = Shape(contours: [
            Contour([Vector2(0, 0), Vector2(60, 0), Vector2(60, 24), Vector2(0, 24)]),
            Contour([Vector2(8, 8), Vector2(20, 8), Vector2(20, 16), Vector2(8, 16)]),
            Contour([Vector2(34, 6), Vector2(50, 6), Vector2(50, 18), Vector2(34, 18)]),
        ])
        let skeleton = straightSkeleton(of: slab)
        #expect(skeleton.faces.count == 12)
        expectFacesPartition(skeleton, slab,
                             expecting: 60 * 24 - 12 * 8 - 16 * 12, within: 1e-7)
        // A shallow inset keeps all three rings.
        #expect(skeleton.inset(by: 1).contours.count == 3)
    }

    @Test func skeletonIsDeterministic() {
        let shape = blob(seed: 27, points: 32, spikes: 26)
        #expect(straightSkeleton(of: shape) == straightSkeleton(of: shape))
    }

    // MARK: Degenerate inputs pass through

    @Test func degenerateInputsReturnEmpty() {
        #expect(straightSkeleton(of: Shape(contours: [])).arcs.isEmpty)
        #expect(straightSkeleton(of: Shape([Vector2(0, 0), Vector2(10, 0)])).faces.isEmpty)
        let line = Shape([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
        #expect(straightSkeleton(of: line).faces.isEmpty)
        let empty = StraightSkeleton(arcs: [], faces: [], maxInset: 0)
        #expect(empty.inset(by: 5).contours.isEmpty)
    }

    @Test func insetEndpointsBehave() {
        let square = Shape([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
        let skeleton = straightSkeleton(of: square)
        // At or below zero, the shape itself; past the collapse, nothing.
        #expect(abs(abs(signedArea(of: skeleton.inset(by: 0))) - 100) < 1e-9)
        #expect(skeleton.inset(by: 6).contours.isEmpty)
    }
}
