import Foundation
import Testing
@testable import Ollin

/// The marks one gesture makes, on the CPU: a growing gesture never moves a
/// piece it has laid down (every family, a point at a time); the cloud's
/// discs cover the path; every spike tip is under a right angle and every
/// valley sits on the band's edge; the rows stay inside their share of the
/// width and follow a taper; sprouts leave the path at the angle asked; the
/// spiral turns once per cycle; the regions enclose every point; the
/// figures are the shapes their two ends span; the spiked and wobbled fills
/// keep their base; every family repeats from its seed; and the pieces come
/// back from the SVG a sketch writes.
@Suite struct GestureMarkTests {

    /// A wavy, tapering gesture sampled a few units apart, as a pen records.
    static func pen(count: Int = 160) -> GestureMark {
        let points: [Vector2] = (0 ..< count).map { (i: Int) -> Vector2 in
            let t = Double(i)
            let y: Double = 200 + 60 * sin(t * 0.045) + 18 * sin(t * 0.13)
            return Vector2(30 + 3.1 * t, y)
        }
        let widths: [Double] = (0 ..< count).map { (i: Int) -> Double in
            let u = Double(i) / Double(max(count, 1))
            let wobble: Double = 4 * sin(Double(i) * 0.2)
            return 36 - 20 * u + wobble
        }
        return GestureMark(points: points, widths: widths)
    }

    /// A straight gesture along x at y = 100, from x = 20 to x = `end`.
    static func straight(to end: Double = 420, width: Double = 40, taperTo: Double? = nil) -> GestureMark {
        let count = 60
        let last: Double = taperTo ?? width
        let points: [Vector2] = (0 ... count).map { (i: Int) -> Vector2 in
            let u = Double(i) / Double(count)
            return Vector2(20 + (end - 20) * u, 100)
        }
        let widths: [Double] = (0 ... count).map { (i: Int) -> Double in
            let u = Double(i) / Double(count)
            return width + (last - width) * u
        }
        return GestureMark(points: points, widths: widths)
    }

    /// Every family with fixed settings, by name.
    static let families: [(String, @Sendable (GestureMark) -> [GestureMark.Piece])] = [
        ("cloud", { $0.cloud(seed: 3) }),
        ("chain", { $0.chain(seed: 3) }),
        ("spikes", { $0.spikes(seed: 3) }),
        ("dashes", { $0.dashes(rows: 3, seed: 3) }),
        ("strips", { $0.strips(rows: 4, seed: 3) }),
        ("dots", { $0.dots(rows: 3, seed: 3) }),
        ("feather", { $0.feather(seed: 3) }),
        ("leaves", { $0.leaves(seed: 3) }),
        ("fringe", { $0.fringe(seed: 3) }),
        ("pixels", { $0.pixels(cell: 5, seed: 3) }),
        ("facets", { $0.facets(seed: 3) }),
        ("lanes", { $0.lanes(count: 3, seed: 3) }),
        ("spiral", { $0.spiral() }),
        ("strands", { $0.strands(count: 4, seed: 3) }),
        ("fragments", { $0.fragments(seed: 3) }),
        ("wiggle", { $0.wiggle() }),
    ]

    static func byRow(_ pieces: [GestureMark.Piece]) -> [Int: [GestureMark.Piece]] {
        Dictionary(grouping: pieces, by: \.row)
    }

    // MARK: The stability rule

    /// A gesture grown a point at a time: in every row of every family, each
    /// piece but the last (the one at the tip) keeps its exact points, its
    /// place, and its distance, and the rows never lose a piece.
    @Test(arguments: families.indices)
    func aGrowingGestureNeverMovesWhatItDrew(_ family: Int) {
        let (name, make) = Self.families[family]
        let full = Self.pen()
        var compared = 0
        var previous = make(GestureMark(points: Array(full.points.prefix(20)), widths: Array(full.widths.prefix(20))))
        for n in 21 ... full.points.count {
            let grown = make(GestureMark(points: Array(full.points.prefix(n)), widths: Array(full.widths.prefix(n))))
            let before = Self.byRow(previous), after = Self.byRow(grown)
            for (row, old) in before {
                let new = after[row] ?? []
                #expect(new.count >= old.count - 1, "\(name): row \(row) lost pieces at \(n) points")
                for (i, piece) in old.dropLast().enumerated() where i < new.count {
                    if piece != new[i] {
                        Issue.record("\(name): row \(row) piece \(i) of \(old.count) moved when point \(n) arrived")
                        return
                    }
                    compared += 1
                }
            }
            previous = grown
        }
        #expect(compared > 200, "\(name): only \(compared) pieces compared")
    }

    /// The same family over a whole gesture and over its first part agree on
    /// the first part, the rule seen from the other end: cutting a gesture
    /// short only takes pieces away from its tip.
    @Test func aShorterGestureIsAPrefix() {
        let full = Self.pen()
        let half = GestureMark(points: Array(full.points.prefix(80)), widths: Array(full.widths.prefix(80)))
        for (name, make) in Self.families {
            let long = Self.byRow(make(full)), short = Self.byRow(make(half))
            for (row, pieces) in short {
                let prefix = Array((long[row] ?? []).prefix(pieces.count - 1))
                #expect(Array(pieces.dropLast()) == prefix, "\(name): row \(row)")
            }
        }
    }

    // MARK: Outlines

    /// Every point of the path lies inside some disc of the cloud.
    @Test func theCloudCoversThePath() {
        for variation in [0.0, 0.5, 1.0] {
            let gesture = Self.pen()
            let discs = gesture.cloud(variation: variation, seed: 5).map { piece -> (Vector2, Double) in
                var sum = Vector2(0, 0)
                for p in piece.contour.points { sum = sum + p }
                let c: Vector2 = sum / Double(piece.contour.points.count)
                return (c, piece.contour.points[0].distance(to: c))
            }
            var s = 0.0
            var missed = 0
            while s <= gesture.length {
                let p = gesture.spine.frame(at: s).position
                if !discs.contains(where: { $0.0.distance(to: p) <= $0.1 + 1e-6 }) { missed += 1 }
                s += 0.5
            }
            #expect(missed == 0, "variation \(variation): \(missed) path points outside every disc")
        }
    }

    /// On a straight band every spike's tip is sharper than a right angle
    /// (from the default sharpness up) and every valley lies exactly on the
    /// band's edge.
    @Test func spikeTipsAreSharpAndValleysSitOnTheEdge() {
        let gesture = Self.straight(width: 40)
        for sharpness in [2.0, 3.0] {
            let periods = gesture.spikes(sharpness: sharpness, seed: 2)
            #expect(periods.count >= 10)
            var tips = 0
            for piece in periods.dropLast() {
                let points = piece.contour.points
                let half = points.count / 2
                for side in [Array(points[..<half]), Array(points[half...].reversed())] {
                    // The valleys: the side's two ends, on the band's edge.
                    #expect(abs(abs(side.first!.y - 100) - 20) < 1e-9)
                    #expect(abs(abs(side.last!.y - 100) - 20) < 1e-9)
                    // Every point at or past the edge.
                    #expect(side.allSatisfy { abs($0.y - 100) >= 20 - 1e-9 })
                    // The tip: the point farthest out, and the angle there.
                    let tip = side.indices.max { abs(side[$0].y - 100) < abs(side[$1].y - 100) }!
                    let a = side[tip - 1] - side[tip], b = side[tip + 1] - side[tip]
                    let angle = acos(a.dot(b) / (a.length * b.length))
                    #expect(angle < .pi / 2, "a tip of \(angle * 180 / .pi) degrees at sharpness \(sharpness)")
                    tips += 1
                }
            }
            #expect(tips >= 20)
        }
    }

    // MARK: Rows

    /// On a taper from 60 wide to 20, every dash, strip, and dot stays inside
    /// its row's share of the local width, so the rows narrow with it.
    @Test func rowsStayInTheirShareAndFollowATaper() {
        let gesture = Self.straight(to: 620, width: 60, taperTo: 20)
        func half(at x: Double) -> Double {
            let u: Double = (x - 20) / 600
            return (60 - 40 * u) / 2
        }
        for (name, rows, inset, pieces) in [
            ("dashes", 3, 0.12, gesture.dashes(rows: 3, seed: 1)),
            ("strips", 4, 0.0, gesture.strips(rows: 4, seed: 1)),
            ("dots", 3, 0.0, gesture.dots(rows: 3, seed: 1)),
        ] {
            let span = 2 / Double(rows)
            for piece in pieces {
                let top = 1 - Double(piece.row) * span - inset * span
                let bottom = 1 - Double(piece.row + 1) * span + inset * span
                for p in piece.contour.points {
                    // Across as a fraction of the half width there (y grows down,
                    // and the left of travel along +x is +y).
                    let across = (p.y - 100) / half(at: p.x)
                    #expect(across <= top + 0.02 && across >= bottom - 0.02,
                            "\(name) row \(piece.row): \(across) outside \(bottom)...\(top)")
                }
            }
            // The rows narrow: a row's pieces near the end are thinner than
            // near the start.
            let early = pieces.filter { $0.distance < 100 }.map { Self.height(of: $0.contour) }
            let late = pieces.filter { $0.distance > 480 }.map { Self.height(of: $0.contour) }
            let lateMean: Double = late.reduce(0, +) / Double(late.count)
            let earlyMean: Double = early.reduce(0, +) / Double(early.count)
            #expect(lateMean < 0.6 * earlyMean, "\(name)")
        }
    }

    static func height(of contour: Contour) -> Double {
        let ys = contour.points.map(\.y)
        return ys.max()! - ys.min()!
    }

    // MARK: Sprouts

    /// A fringe hair and a feather barb leave the path at the angle asked,
    /// within their stated jitter, forward and on their own side.
    @Test func sproutsLeaveAtTheStatedAngle() {
        let gesture = Self.straight(width: 40)
        for angle in [Double.pi / 6, .pi / 4, .pi / 3] {
            for (name, jitter, pieces) in [("fringe", 0.08, gesture.fringe(angle: angle, seed: 4)),
                                           ("feather", 0.1, gesture.feather(angle: angle, seed: 4))] {
                #expect(pieces.count > 40)
                for piece in pieces {
                    let base = piece.contour.points.first!, tip = piece.contour.points.last!
                    #expect(abs(base.y - 100) < 1e-9, "\(name): a sprout off the path")
                    let d = tip - base
                    let off = atan2(abs(d.y), d.x)
                    #expect(abs(off - angle) <= jitter + 1e-9, "\(name): \(off) for \(angle)")
                    #expect((d.y > 0) == (piece.row == 0), "\(name): row \(piece.row) on the wrong side")
                }
                // Pairs share an index: one left and one right at every station.
                let stations = Dictionary(grouping: pieces, by: \.index)
                #expect(stations.values.allSatisfy { Set($0.map(\.row)) == [0, 1] })
            }
        }
    }

    // MARK: Around

    /// The spiral makes one piece per turn: its count is the length over the
    /// cycle, rounded up, at constant width.
    @Test func theSpiralTurnsOncePerCycle() {
        let gesture = Self.straight(to: 420, width: 40)
        for cycle in [0.5, 1.0, 1.7] {
            let turns = gesture.spiral(cycle: cycle)
            let expected = Int((400.0 / (cycle * 40.0)).rounded(.up))
            #expect(turns.count == expected, "cycle \(cycle): \(turns.count) turns")
            // A whole turn ends where it began across the path.
            for turn in turns.dropLast() {
                let first = turn.contour.points.first!, last = turn.contour.points.last!
                #expect(abs(first.y - last.y) < 1e-6)
                let advance: Double = last.x - first.x
                #expect(abs(advance - cycle * 40) < 1e-6)
            }
        }
    }

    /// A wiggle at one width's wavelength crosses the path twice a wave.
    @Test func theWiggleKeepsItsWavelength() {
        let gesture = Self.straight(to: 420, width: 40)
        let waves = gesture.wiggle(wavelength: 1, amplitude: 0.5)
        #expect(waves.count == 10)
        let line = waves.flatMap(\.contour.points)
        #expect(line.map { abs($0.y - 100) }.max()! <= 10 + 1e-9)
    }

    // MARK: Regions

    /// The hull and the blob enclose every point of the gesture.
    @Test func theRegionsEncloseEveryPoint() {
        let gesture = Self.pen()
        let hull = gesture.hull(), blob = gesture.blob()
        for p in gesture.points {
            #expect(hull.contains(p))
            #expect(blob.contains(p))
        }
        // A lasso: the blob fills what it went round.
        let loop = GestureMark(Circle(center: Vector2(200, 200), radius: 80).contour, width: 10)
        #expect(loop.blob().contains(Vector2(200, 200)))
        #expect(!loop.blob().contains(Vector2(200, 295)))
    }

    /// The figures are the shapes their two ends span.
    @Test func figuresSpanTheirEnds() {
        let gesture = GestureMark(points: [Vector2(100, 100), Vector2(130, 90), Vector2(160, 140)], widths: [4])
        let reach: Double = sqrt(5200)
        let disc: Double = Double.pi * reach * reach
        let circle = gesture.figure(.circle)
        #expect(abs(circle.area - disc) / disc < 0.01)
        let box = gesture.figure(.rectangle)
        #expect(abs(box.area - 60 * 40) < 1e-6)
        let ellipse = gesture.figure(.ellipse)
        let oval: Double = Double.pi * 600
        #expect(abs(ellipse.area - oval) / oval < 0.01)
        let hexagon = gesture.figure(.polygon(sides: 6))
        #expect(hexagon[0].points.count == 6)
        #expect(hexagon[0].points.allSatisfy { abs($0.distance(to: Vector2(100, 100)) - reach) < 1e-9 })
        let star = gesture.figure(.star(points: 5, inner: 0.5))
        #expect(star[0].points.count == 10)
        #expect(star[0].points[0].distance(to: Vector2(160, 140)) < 1e-9)
    }

    // MARK: Fills

    /// A spiked fill grows the count of spikes asked, every valley on the
    /// base outline and no point inside it.
    @Test func aSpikedFillKeepsItsValleysOnTheBase() {
        let disc = Shape(contours: [Circle(center: Vector2(0, 0), radius: 100).contour(segments: 720)])
        for count in [5, 12] {
            let spiked = disc.spiked(count, height: 30, seed: 3)
            let radii = spiked[0].points.map { $0.length }
            #expect(radii.allSatisfy { $0 >= 100 - 0.05 })
            #expect(radii.max()! > 100 + 30 * 0.6)
            // The tips: local maxima of the radius, one per spike.
            var tips = 0
            for i in radii.indices {
                let before = radii[(i + radii.count - 1) % radii.count], after = radii[(i + 1) % radii.count]
                if radii[i] > before && radii[i] > after && radii[i] > 101 { tips += 1 }
            }
            #expect(tips == count, "\(tips) tips for \(count)")
        }
    }

    /// A wobbled fill moves every point by at most the distance asked, and a
    /// closed outline meets itself: noise read at the world position has no
    /// seam where the outline starts.
    @Test func aWobbledFillStaysWithinItsDistance() {
        let square = Shape(contours: [Rectangle(x: 0, y: 0, width: 200, height: 200).contour])
        let wobbled = square.wobbled(by: 8, scale: 40, seed: 2)
        let outline = wobbled[0].points
        #expect(outline.count > 60)
        for p in outline {
            let inside: Double = min(min(p.x, p.y), min(200 - p.x, 200 - p.y))
            let outside: Double = max(max(-p.x, -p.y), max(p.x - 200, p.y - 200))
            #expect(inside <= 8 + 1e-6 && outside <= 8 + 1e-6)
        }
        let step = outline.indices.map { outline[$0].distance(to: outline[($0 + 1) % outline.count]) }
        #expect(step.max()! < 12, "a seam: a jump of \(step.max()!)")
        #expect(wobbled != square.wobbled(by: 8, scale: 40, seed: 3))
    }

    // MARK: Seeds

    /// Every family repeats from its seed, and the seeded ones differ on
    /// another seed.
    @Test func everyFamilyRepeatsFromItsSeed() {
        let gesture = Self.pen()
        for (name, make) in Self.families {
            #expect(make(gesture) == make(gesture), "\(name)")
        }
        let reseeded: [(String, (Int) -> [GestureMark.Piece])] = [
            ("cloud", { gesture.cloud(seed: $0) }), ("chain", { gesture.chain(seed: $0) }),
            ("spikes", { gesture.spikes(seed: $0) }), ("dashes", { gesture.dashes(seed: $0) }),
            ("strips", { gesture.strips(seed: $0) }), ("dots", { gesture.dots(seed: $0) }),
            ("feather", { gesture.feather(seed: $0) }), ("leaves", { gesture.leaves(seed: $0) }),
            ("fringe", { gesture.fringe(seed: $0) }), ("pixels", { gesture.pixels(cell: 5, seed: $0) }),
            ("facets", { gesture.facets(seed: $0) }), ("lanes", { gesture.lanes(seed: $0) }),
            ("strands", { gesture.strands(seed: $0) }), ("fragments", { gesture.fragments(seed: $0) }),
        ]
        for (name, make) in reseeded {
            #expect(make(1) != make(2), "\(name) ignores its seed")
        }
    }

    /// A gesture from a recorded mark carries the mark's widths times the
    /// width it is given.
    @Test func aRecordedMarkCarriesItsWidths() {
        let mark = StrokeMark(samples: [.init(position: Vector2(0, 0), width: 0.5),
                                        .init(position: Vector2(10, 0), width: 1),
                                        .init(position: Vector2(20, 0), width: 2)])
        let gesture = GestureMark(mark, width: 30)
        #expect(gesture.widths == [15, 30, 60])
        #expect(gesture.length == 20)
        #expect(GestureMark(points: [Vector2(0, 0)], widths: [10]).cloud().isEmpty)
    }

    /// The union of a cloud is one silhouette with no hole.
    @Test func aCloudsUnionIsOneSilhouette() {
        let shape = Self.pen().cloud(seed: 1).shape
        #expect(shape.contours.count == 1, "\(shape.contours.count) outlines")
    }

    // MARK: SVG

    /// The pieces a sketch draws come back from the SVG it writes, one path
    /// each, so a plotter gets exactly the geometry.
    @Test @MainActor func thePiecesRoundTripThroughSVG() throws {
        final class Plate: Sketch {
            lazy var gesture: GestureMark = {
                let points: [Vector2] = (0 ... 40).map { (i: Int) -> Vector2 in
                    let x = Double(i)
                    let y: Double = 120 + 30 * sin(x * 0.2)
                    return Vector2(20 + 5 * x, y)
                }
                return GestureMark(points: points, widths: [30])
            }()
            lazy var pieces = gesture.dashes(rows: 2, seed: 1) + gesture.feather(seed: 1) + gesture.spiral()
            override var canvasSize: CanvasSize { .square(240) }
            override func draw() {
                background(.white)
                stroke(.black); strokeWeight(1); noFill()
                for piece in pieces { drawPolyline(piece.contour.points, closed: piece.contour.isClosed) }
            }
        }
        let sketch = Plate()
        let text = try OllinApp.svg(of: sketch)
        let parsed = try SVG(data: Data(text.utf8))
        let drawn = sketch.pieces
        #expect(drawn.count > 60)
        #expect(parsed.contours.count == drawn.count + 1, "\(parsed.contours.count) paths for \(drawn.count) pieces")
        var missing = 0
        for piece in drawn {
            let points = piece.contour.points
            let found = parsed.contours.contains { c in
                c.points.count == points.count && zip(c.points, points).allSatisfy { $0.distance(to: $1) < 0.01 }
            }
            if !found { missing += 1 }
        }
        #expect(missing == 0, "\(missing) pieces did not come back")
    }
}
