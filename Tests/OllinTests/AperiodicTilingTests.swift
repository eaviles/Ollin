import Ollin
import Testing

/// Pure-geometry checks on the aperiodic tilings (Penrose, Wang, girih,
/// spectre). No GPU, so these run everywhere. The load-bearing properties:
/// substitutions produce crack-free edge-to-edge tilings (no T-junctions),
/// halves merge completely into whole tiles, decoration arcs meet across
/// edges, and every generator is deterministic.
@Suite
struct AperiodicTilingTests {
    private let bounds = Rectangle(x: 0, y: 0, width: 400, height: 400)

    /// Quantize a point so shared corners hash identically.
    private func key(_ p: Vector2) -> SIMD2<Int64> {
        SIMD2(Int64((p.x * 512).rounded()), Int64((p.y * 512).rounded()))
    }

    private struct EdgeKey: Hashable {
        let a: SIMD2<Int64>, b: SIMD2<Int64>
        init(_ p: SIMD2<Int64>, _ q: SIMD2<Int64>) {
            if (p.x, p.y) <= (q.x, q.y) { a = p; b = q } else { a = q; b = p }
        }
    }

    /// Every edge appears at most twice (once per side), and no tile corner
    /// lies strictly inside another tile's edge: the crack/T-junction test.
    private func expectEdgeToEdge(_ outlines: [[Vector2]],
                                  file: StaticString = #filePath) {
        var edgeCount: [EdgeKey: Int] = [:]
        var corners = Set<SIMD2<Int64>>()
        for outline in outlines {
            for i in outline.indices {
                let p = outline[i], q = outline[(i + 1) % outline.count]
                edgeCount[EdgeKey(key(p), key(q)), default: 0] += 1
                corners.insert(key(p))
            }
        }
        for (_, count) in edgeCount {
            #expect(count <= 2, "an edge is shared by more than two tiles")
        }
        // T-junctions: a corner strictly inside some edge's interior.
        var junctions = 0
        for outline in outlines {
            for i in outline.indices {
                let p = outline[i], q = outline[(i + 1) % outline.count]
                let mid = key(p.lerp(to: q, 0.5))
                if corners.contains(mid), mid != key(p), mid != key(q) {
                    junctions += 1
                }
            }
        }
        #expect(junctions == 0, "\(junctions) T-junctions found")
    }

    // MARK: - Penrose

    @Test func penroseRhombsHaveEqualSidesAndBothKinds() {
        let tiles = Penrose.tiles(.rhombs, in: bounds, tileEdge: 40)
        #expect(tiles.contains { $0.kind == .thick })
        #expect(tiles.contains { $0.kind == .thin })
        for tile in tiles {
            #expect(tile.points.count == 4)
            let sides = (0..<4).map {
                tile.points[$0].distance(to: tile.points[($0 + 1) % 4])
            }
            for s in sides {
                #expect(abs(s - sides[0]) < 1e-6, "rhomb sides should be equal")
            }
        }
    }

    @Test func penroseKitesAndDartsHaveGoldenEdges() {
        let tiles = Penrose.tiles(.kitesAndDarts, in: bounds, tileEdge: 40)
        #expect(tiles.contains { $0.kind == .kite })
        #expect(tiles.contains { $0.kind == .dart })
        let phi = (1 + 5.0.squareRoot()) / 2
        for tile in tiles {
            let sides = (0..<4).map {
                tile.points[$0].distance(to: tile.points[($0 + 1) % 4])
            }
            // Symmetric about the axis; the kite leads with its long edges
            // (the nose), the dart with its short ones (the reflex corner).
            #expect(abs(sides[0] - sides[3]) < 1e-6)
            #expect(abs(sides[1] - sides[2]) < 1e-6)
            let expected = tile.kind == .kite ? phi : 1 / phi
            #expect(abs(sides[0] / sides[1] - expected) < 1e-6)
        }
    }

    @Test func penroseTilingIsCrackFree() {
        for variant in Penrose.Variant.allCases {
            let tiles = Penrose.tiles(variant, in: bounds, tileEdge: 30)
            #expect(tiles.count > 50)
            expectEdgeToEdge(tiles.map(\.points))
        }
    }

    @Test func penroseKindRatioApproachesGolden() {
        // In the limit, kites outnumber darts (and thick rhombs thin ones) by
        // the golden ratio. A finite patch sits near it.
        let tiles = Penrose.tiles(.rhombs, in: Rectangle(x: 0, y: 0, width: 900, height: 900),
                                  tileEdge: 18)
        let thick = Double(tiles.count { $0.kind == .thick })
        let thin = Double(tiles.count { $0.kind == .thin })
        let phi = (1 + 5.0.squareRoot()) / 2
        #expect(abs(thick / thin - phi) < 0.2, "thick:thin was \(thick / thin)")
    }

    @Test func penroseArcsMeetAcrossEveryEdge() {
        // The matching-rule arcs must land on shared edges at the same point
        // from both sides: collect each arc endpoint, bucketed by position,
        // and require every interior-edge endpoint to appear exactly twice.
        for variant in Penrose.Variant.allCases {
            let tiles = Penrose.tiles(variant, in: bounds, tileEdge: 45)

            // Interior edges (shared by two tiles).
            var edgeCount: [EdgeKey: Int] = [:]
            for tile in tiles {
                for i in 0..<4 {
                    let p = tile.points[i], q = tile.points[(i + 1) % 4]
                    edgeCount[EdgeKey(key(p), key(q)), default: 0] += 1
                }
            }

            var endpointCount: [SIMD2<Int64>: Int] = [:]
            var interiorEndpoints: [SIMD2<Int64>: EdgeKey] = [:]
            for tile in tiles {
                for arc in tile.arcs {
                    for endpoint in [arc.points.first!, arc.points.last!] {
                        endpointCount[key(endpoint), default: 0] += 1
                        // Which edge does this endpoint sit on?
                        for i in 0..<4 {
                            let p = tile.points[i], q = tile.points[(i + 1) % 4]
                            let toEnd = endpoint - p
                            let along = q - p
                            let t = toEnd.dot(along) / along.lengthSquared
                            if t > 0.01, t < 0.99,
                               abs(toEnd.cross(along)) < 1e-6 * along.length {
                                interiorEndpoints[key(endpoint)] =
                                    EdgeKey(key(p), key(q))
                            }
                        }
                    }
                }
            }

            var mismatches = 0
            for (endpoint, edge) in interiorEndpoints {
                guard edgeCount[edge] == 2 else { continue }   // patch rim
                if endpointCount[endpoint] != 2 { mismatches += 1 }
            }
            #expect(mismatches == 0,
                    "\(variant): \(mismatches) arc ends missed their partner")
        }
    }

    @Test func penroseIsDeterministic() {
        let a = Penrose.tiles(.kitesAndDarts, in: bounds, tileEdge: 35)
        let b = Penrose.tiles(.kitesAndDarts, in: bounds, tileEdge: 35)
        #expect(a == b)
    }

    // MARK: - Wang tiles

    @Test func wangCompleteSetAlwaysFillsAndMatches() {
        var rng = SplitMix64(seed: 7)
        let tiles = WangTiling.completeSet(colors: 2)
        #expect(tiles.count == 16)
        let tiling = WangTiling.fill(tiles: tiles, columns: 9, rows: 7, using: &rng)
        #expect(tiling != nil)
        guard let tiling else { return }
        for row in 0..<tiling.rows {
            for column in 0..<tiling.columns {
                let tile = tiling.tile(column: column, row: row)
                if column > 0 {
                    #expect(tile.left == tiling.tile(column: column - 1, row: row).right)
                }
                if row > 0 {
                    #expect(tile.top == tiling.tile(column: column, row: row - 1).bottom)
                }
            }
        }
    }

    @Test func wangImpossibleSetReturnsNil() {
        // Two tiles that can never sit side by side horizontally.
        var rng = SplitMix64(seed: 1)
        let tiles = [
            WangTile(top: 0, right: 0, bottom: 0, left: 1),
            WangTile(top: 1, right: 0, bottom: 1, left: 1),
        ]
        #expect(WangTiling.fill(tiles: tiles, columns: 3, rows: 2, using: &rng) == nil)
    }

    @Test func wangFillIsSeedDeterministic() {
        let tiles = WangTiling.completeSet(colors: 3)
        var rngA = SplitMix64(seed: 42)
        var rngB = SplitMix64(seed: 42)
        let a = WangTiling.fill(tiles: tiles, columns: 8, rows: 8, using: &rngA)
        let b = WangTiling.fill(tiles: tiles, columns: 8, rows: 8, using: &rngB)
        #expect(a == b)
    }

    @Test func wangZeroWeightTilesAreNeverPicked() {
        var rng = SplitMix64(seed: 3)
        var tiles = WangTiling.completeSet(colors: 2)
        // Zero out every tile with color-1 top; tops of row 0 never show it.
        tiles = tiles.map {
            WangTile(top: $0.top, right: $0.right, bottom: $0.bottom,
                     left: $0.left, weight: $0.top == 1 ? 0 : 1)
        }
        let tiling = WangTiling.fill(tiles: tiles, columns: 6, rows: 1, using: &rng)
        guard let tiling else {
            Issue.record("fill unexpectedly failed")
            return
        }
        for column in 0..<6 {
            #expect(tiling.tile(column: column, row: 0).top == 0)
        }
    }

    // MARK: - Girih

    @Test func girihTilesCloseWithUnitEdges() {
        for tile in Girih.Tile.allCases {
            let pts = tile.points
            for i in pts.indices {
                let side = pts[i].distance(to: pts[(i + 1) % pts.count])
                #expect(abs(side - 1) < 1e-9, "\(tile) edge \(i) is \(side)")
            }
        }
    }

    @Test func girihMotifOnRegularPolygonMatchesEveryRay() {
        // On a regular n-gon every ray pairs up, so the motif has exactly n
        // strands, and it inherits the polygon's n-fold symmetry.
        let decagon = Girih.Tile.decagon.points(edge: 60, at: Vector2(200, 200))
        let motif = Girih.pattern(in: decagon, angle: 54)
        #expect(motif.count == 10)

        // n-fold symmetry: rotating the whole motif by one step maps its
        // segment set onto itself.
        var segments = Set<EdgeKey>()
        for contour in motif {
            for i in 0..<(contour.points.count - 1) {
                segments.insert(EdgeKey(key(contour.points[i]), key(contour.points[i + 1])))
            }
        }
        let center = Vector2(200, 200)
        let step = 2 * Double.pi / 10
        for contour in motif {
            for i in 0..<(contour.points.count - 1) {
                let p = contour.points[i].rotated(by: step, around: center)
                let q = contour.points[i + 1].rotated(by: step, around: center)
                #expect(segments.contains(EdgeKey(key(p), key(q))),
                        "rotated strand segment missing")
            }
        }
    }

    @Test func girihMotifsJoinAcrossSharedEdges() {
        // Two squares side by side: each strand endpoint on the shared edge
        // must appear from both tiles.
        let a = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
        let b = [Vector2(100, 0), Vector2(200, 0), Vector2(200, 100), Vector2(100, 100)]
        let motifA = Girih.pattern(in: a, angle: 45)
        let motifB = Girih.pattern(in: b, angle: 45)
        let sharedMid = Vector2(100, 50)
        let endsA = motifA.flatMap { [$0.points.first!, $0.points.last!] }
            .filter { $0.distance(to: sharedMid) < 1e-6 }
        let endsB = motifB.flatMap { [$0.points.first!, $0.points.last!] }
            .filter { $0.distance(to: sharedMid) < 1e-6 }
        #expect(endsA.count == 2)
        #expect(endsB.count == 2)
    }

    @Test func girihBowtieGetsAMotif() {
        let bowtie = Girih.Tile.bowtie.points(edge: 80, at: Vector2(200, 200))
        let motif = Girih.pattern(in: bowtie, angle: 54)
        #expect(!motif.isEmpty)
    }

    // MARK: - Spectre

    @Test func spectreOutlineClosesWithUnitEdges() {
        let tiles = Spectre.tiles(in: Rectangle(x: 0, y: 0, width: 120, height: 120),
                                  tileEdge: 30)
        #expect(!tiles.isEmpty)
        for tile in tiles.prefix(4) {
            #expect(tile.points.count == 14)
            for i in 0..<14 {
                let side = tile.points[i].distance(to: tile.points[(i + 1) % 14])
                #expect(abs(side - 30) < 1e-6, "edge \(i) is \(side)")
            }
        }
    }

    @Test func spectreTilesAreCongruentAndOneHanded() {
        // Every tile's cyclic turn sequence must equal the first tile's, and
        // never its reversal: same shape, same handedness, no mirrors.
        let tiles = Spectre.tiles(in: bounds, tileEdge: 30)
        #expect(tiles.count > 20)

        func turns(_ pts: [Vector2]) -> [Int] {
            (0..<pts.count).map { i in
                let a = pts[i]
                let b = pts[(i + 1) % pts.count]
                let c = pts[(i + 2) % pts.count]
                let cross = (b - a).cross(c - b)
                let dot = (b - a).dot(c - b)
                // Angles are multiples of 30 degrees; quantize the turn.
                let angle = atan2(cross, dot) * 6 / .pi
                return Int(angle.rounded())
            }
        }

        let reference = turns(tiles[0].points)
        let doubled = reference + reference
        for tile in tiles {
            let t = turns(tile.points)
            var matched = false
            for start in 0..<reference.count where Array(doubled[start..<(start + t.count)]) == t {
                matched = true
                break
            }
            #expect(matched, "tile turn sequence should match the reference cyclically")
        }
    }

    @Test func spectrePatchIsCrackFree() {
        let tiles = Spectre.tiles(in: bounds, tileEdge: 40)
        expectEdgeToEdge(tiles.map(\.points))
    }

    @Test func spectreOddTilesAreSparse() {
        // The odd (mystic partner) tiles are the rare ones: far fewer than
        // one in four.
        let tiles = Spectre.tiles(in: bounds, tileEdge: 25)
        let odd = tiles.count { $0.isOdd }
        #expect(odd > 0)
        #expect(Double(odd) / Double(tiles.count) < 0.25)
    }

    @Test func spectreCurvedOutlineIsStillCongruent() {
        let tiles = Spectre.tiles(in: Rectangle(x: 0, y: 0, width: 300, height: 300),
                                  tileEdge: 30, curve: 0.5)
        #expect(!tiles.isEmpty)
        let count = tiles[0].points.count
        #expect(count > 14)
        for tile in tiles { #expect(tile.points.count == count) }
    }

    @Test func spectreIsDeterministic() {
        let a = Spectre.tiles(in: bounds, tileEdge: 30)
        let b = Spectre.tiles(in: bounds, tileEdge: 30)
        #expect(a == b)
    }
}
