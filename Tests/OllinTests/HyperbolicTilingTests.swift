import Ollin
import Testing

/// Pure-geometry checks on the hyperbolic tiling. No GPU, so these run
/// everywhere. The load-bearing properties: the central tile sits at the
/// exact derived radius, every point stays strictly inside the horizon,
/// reflection lands the first ring on the central tile's own edges, the
/// two-coloring checkerboards when `meeting` is even, panning keeps the
/// picture inside the horizon, and the generator is deterministic.
@Suite
struct HyperbolicTilingTests {
    private let bounds = Rectangle(x: 0, y: 0, width: 400, height: 400)
    private var fitRadius: Double { 200 }
    private var origin: Vector2 { bounds.center }

    /// The Euclidean vertex radius of the central tile, from the right
    /// triangle with angles pi/sides and pi/meeting: cosh of the hyperbolic
    /// circumradius is cot(pi/sides) * cot(pi/meeting).
    private func vertexRadius(sides: Int, meeting: Int) -> Double {
        let coshC = 1 / (tan(.pi / Double(sides)) * tan(.pi / Double(meeting)))
        return ((coshC - 1) / (coshC + 1)).squareRoot()
    }

    /// The tile's corner points: the flattened outline keeps each corner as
    /// a sample, and corners are the points farthest from the tile center,
    /// so matching against the exact radius recovers them.
    private func corners(of tile: HyperbolicTiling.Tile, count: Int) -> [Vector2] {
        // Corners are the local maxima of distance from the tile center
        // along the outline.
        let points = tile.points
        var found: [Vector2] = []
        for i in points.indices {
            let previous = (points[(i + points.count - 1) % points.count] - tile.center).lengthSquared
            let here = (points[i] - tile.center).lengthSquared
            let next = (points[(i + 1) % points.count] - tile.center).lengthSquared
            if here >= previous && here >= next { found.append(points[i]) }
        }
        #expect(found.count == count)
        return found
    }

    @Test func centralTileSitsAtTheDerivedRadius() {
        let tiles = HyperbolicTiling.tiles(sides: 5, meeting: 4, in: bounds, minEdge: 30)
        let expected = vertexRadius(sides: 5, meeting: 4) * fitRadius
        let central = tiles[0]
        #expect(central.depth == 0)
        #expect((central.center - origin).length < 1e-9)
        for corner in corners(of: central, count: 5) {
            #expect(abs((corner - origin).length - expected) < 1e-9)
        }
    }

    @Test func everyPointStaysInsideTheHorizon() {
        let tiles = HyperbolicTiling.tiles(sides: 7, meeting: 3, in: bounds, minEdge: 4)
        #expect(tiles.count > 50)
        for tile in tiles {
            for point in tile.points {
                #expect((point - origin).length < fitRadius)
            }
        }
    }

    @Test func theFirstRingReflectsOntoTheCentralEdges() {
        let tiles = HyperbolicTiling.tiles(sides: 7, meeting: 3, in: bounds, minEdge: 30)
        let central = tiles[0]
        let ring = tiles.filter { $0.depth == 1 }
        #expect(ring.count == 7)
        let centralCorners = corners(of: central, count: 7)
        // Each neighbor shares exactly one whole edge, so exactly two of the
        // central tile's corners must reappear among its points.
        for neighbor in ring {
            var shared = 0
            for corner in centralCorners {
                if neighbor.points.contains(where: { ($0 - corner).length < 1e-9 }) {
                    shared += 1
                }
            }
            #expect(shared == 2)
        }
    }

    @Test func paritiesCheckerboardWhenMeetingIsEven() {
        let tiles = HyperbolicTiling.tiles(sides: 6, meeting: 4, in: bounds, minEdge: 25)
        #expect(tiles.count > 10)
        // Edge neighbors share two corner points; vertex neighbors share one.
        for i in tiles.indices {
            for j in (i + 1) ..< tiles.count {
                var shared = 0
                for a in tiles[i].points {
                    if tiles[j].points.contains(where: { ($0 - a).length < 1e-6 }) {
                        shared += 1
                    }
                }
                if shared >= 2 {
                    #expect(tiles[i].parity != tiles[j].parity)
                }
            }
        }
    }

    @Test func panningKeepsTheTilingInsideTheHorizon() {
        let viewpoint = Vector2(0.5, 0.2)
        let tiles = HyperbolicTiling.tiles(sides: 5, meeting: 4, in: bounds,
                                           viewpoint: viewpoint, minEdge: 6)
        #expect(tiles.count > 20)
        // The motion carries the viewpoint to the middle, so the tile that
        // was central lands at minus the viewpoint.
        let expected = origin - viewpoint * fitRadius
        #expect((tiles[0].center - expected).length < 1e-9)
        for tile in tiles {
            for point in tile.points {
                #expect((point - origin).length < fitRadius)
            }
        }

        // The pan is a rigid motion of the hyperbolic plane, so every panned
        // tile must be the exact image of a centered tile under
        // z -> (z - w) / (1 - conj(w) z). This pins the transform itself; a
        // wrong transform makes overlapping junk tiles that still stay
        // inside the horizon.
        // A wrong transform makes overlapping junk tiles that still stay
        // inside the horizon, and the junk multiplies, so gate on the count
        // first and bail before the per-tile matching drowns in failures.
        #expect(abs(tiles.count - 221) < 60)
        guard tiles.count < 1000 else { return }

        let centered = HyperbolicTiling.tiles(sides: 5, meeting: 4, in: bounds, minEdge: 1)
        let w = viewpoint
        func view(_ z: Vector2) -> Vector2 {
            let top = z - w
            let bottom = Vector2(1 - (w.x * z.x + w.y * z.y), w.y * z.x - w.x * z.y)
            let d = bottom.lengthSquared
            return Vector2((top.x * bottom.x + top.y * bottom.y) / d,
                           (top.y * bottom.x - top.x * bottom.y) / d)
        }
        func cell(_ p: Vector2) -> SIMD2<Int64> {
            SIMD2(Int64((p.x * 1e8).rounded(.down)), Int64((p.y * 1e8).rounded(.down)))
        }
        var moved: Set<SIMD2<Int64>> = []
        for tile in centered {
            let image = view((tile.center - origin) / fitRadius)
            let base = cell(image)
            for dx in Int64(-1) ... 1 {
                for dy in Int64(-1) ... 1 {
                    moved.insert(SIMD2(base.x + dx, base.y + dy))
                }
            }
        }
        for tile in tiles {
            #expect(moved.contains(cell((tile.center - origin) / fitRadius)))
        }
    }

    @Test func smallerMinEdgeReachesFurtherOut() {
        let coarse = HyperbolicTiling.tiles(sides: 7, meeting: 3, in: bounds, minEdge: 12)
        let fine = HyperbolicTiling.tiles(sides: 7, meeting: 3, in: bounds, minEdge: 3)
        #expect(fine.count > coarse.count)
        // The coarse tiling is a prefix-closed subset: every coarse tile
        // reappears in the fine one.
        for tile in coarse {
            #expect(fine.contains(where: { ($0.center - tile.center).length < 1e-9 }))
        }
    }

    @Test func theGeneratorIsDeterministic() {
        let first = HyperbolicTiling.tiles(sides: 7, meeting: 3, in: bounds, minEdge: 5)
        let second = HyperbolicTiling.tiles(sides: 7, meeting: 3, in: bounds, minEdge: 5)
        #expect(first == second)
    }
}
