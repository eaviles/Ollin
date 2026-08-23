@testable import Ollin
import Testing
import Foundation

/// Pure-CPU checks on the shape grammar. Nearly every one is a law rather than
/// a matter of taste, which is what makes a rule-driven design testable at all:
/// a lattice cut by the wrong lines looks exactly as convincing as one cut by
/// the right ones.
///
/// The load-bearing pair is area and corners. A cut is one straight line
/// between two edges, so the parts must add back up to the whole, and they must
/// carry `n + 4` corners between them. The second law is the surprise: hold the
/// corner count to `3...5` and the four rules of the classic lattice grammar
/// fall out of that one arithmetic fact, rather than having to be written down
/// one at a time.
@Suite
struct ShapeGrammarTests {

    private typealias Piece = ShapeGrammar.Piece
    private typealias Rule = ShapeGrammar.Rule

    private func square(_ size: Double = 100, at corner: Vector2 = .zero) -> Piece {
        Piece("cell", Rectangle(corner: corner, width: size, height: size))
    }

    private func regular(_ sides: Int, radius: Double = 100) -> Piece {
        let points = (0 ..< sides).map { i -> Vector2 in
            let angle = Double(i) / Double(sides) * 2 * .pi
            return Vector2(500 + cos(angle) * radius, 500 + sin(angle) * radius)
        }
        return Piece("cell", points)
    }

    /// Every corner turns the same way, so the outline never folds back on
    /// itself. The built-in rules promise this.
    private func isConvex(_ points: [Vector2]) -> Bool {
        guard points.count >= 3 else { return false }
        var sign = 0.0
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            let c = points[(i + 2) % points.count]
            let turn = (b - a).cross(c - b)
            if abs(turn) < 1e-9 { continue }
            if sign == 0 { sign = turn < 0 ? -1 : 1 }
            else if (turn < 0 ? -1.0 : 1.0) != sign { return false }
        }
        return true
    }

    // MARK: - One cut

    @Test func aCutKeepsTheWholeArea() {
        // A straight line between two edges takes nothing away and adds
        // nothing, so the parts have to add back up to the piece.
        let rule = Rule.cut("cell", into: ("cell", "cell"), sides: 3 ... 9)
        var source = SplitMix64(seed: 11)
        var cuts = 0
        for start in [square(), regular(3), regular(5), regular(7, radius: 60)] {
            for _ in 0 ..< 60 {
                guard let parts = rule.body(start, &source) else { continue }
                cuts += 1
                let sum = parts.reduce(0) { $0 + $1.area }
                #expect(abs(sum - start.area) < 1e-6)
            }
        }
        #expect(cuts > 200)
    }

    @Test func aCutLandsInsideItsBalance() {
        // The published rule asks for two parts of approximately equal area.
        // `balance` is what "approximately" is allowed to mean, and the cut is
        // solved for it rather than searched for, so it holds exactly.
        var source = SplitMix64(seed: 5)
        for balance in [0.0, 0.05, 0.2, 0.6] {
            let rule = Rule.cut("cell", into: ("a", "b"), balance: balance)
            let start = square(200)
            var cuts = 0
            for _ in 0 ..< 80 {
                guard let parts = rule.body(start, &source) else { continue }
                cuts += 1
                let gap = abs(parts[0].area - parts[1].area)
                #expect(gap <= balance * start.area + 1e-6)
            }
            #expect(cuts > 40)
        }
    }

    @Test func aBalanceOfZeroHalvesTheArea() {
        let rule = Rule.cut("cell", into: ("a", "b"), balance: 0)
        var source = SplitMix64(seed: 3)
        let start = square(120)
        var cuts = 0
        for _ in 0 ..< 40 {
            guard let parts = rule.body(start, &source) else { continue }
            cuts += 1
            #expect(abs(parts[0].area - start.area / 2) < 1e-6)
            #expect(abs(parts[1].area - start.area / 2) < 1e-6)
        }
        #expect(cuts > 30)
    }

    @Test func aCutAddsFourCorners() {
        // The line meets two edges away from their ends, so it adds one corner
        // to each part at each end. Both parts also keep a share of the
        // original corners, and every original corner lands in exactly one of
        // them. That is `n + 4` between the two, whatever the piece was.
        let rule = Rule.cut("cell", into: ("a", "b"), sides: 3 ... 12)
        var source = SplitMix64(seed: 21)
        var cuts = 0
        for sides in [3, 4, 5, 6, 8] {
            let start = regular(sides)
            for _ in 0 ..< 40 {
                guard let parts = rule.body(start, &source) else { continue }
                cuts += 1
                #expect(parts[0].corners.count + parts[1].corners.count == sides + 4)
            }
        }
        // Without this, a change that stops every cut from applying leaves the
        // law above with nothing to check, and it passes having seen nothing.
        #expect(cuts > 150)
    }

    @Test func theLatticeFamilyFallsOutOfTheCornerRange() {
        // Hold the parts to 3, 4, or 5 corners and the classic lattice rules
        // are the only cuts left: a triangle becomes a triangle and a
        // quadrilateral; a quadrilateral becomes a triangle and a pentagon or
        // two quadrilaterals; a pentagon becomes a quadrilateral and another
        // pentagon. Nothing here writes those four rules down.
        let rule = Rule.cut("cell", into: ("a", "b"), balance: 0.6, sides: 3 ... 5)
        var source = SplitMix64(seed: 77)
        var seen: [Int: Set<[Int]>] = [:]
        var cuts = 0
        for sides in [3, 4, 5] {
            let start = regular(sides)
            for _ in 0 ..< 400 {
                guard let parts = rule.body(start, &source) else { continue }
                cuts += 1
                let shape = [parts[0].corners.count, parts[1].corners.count].sorted()
                seen[sides, default: []].insert(shape)
            }
        }
        #expect(cuts > 900)
        #expect(seen[3] == [[3, 4]])
        #expect(seen[4] == [[3, 5], [4, 4]])
        #expect(seen[5] == [[4, 5]])
    }

    @Test func theCornerRangeDecidesWhatCanBeCutAtAll() {
        // The parts carry `n + 4` corners between them, so a piece of seven
        // corners would need parts of 3 and 8, or 4 and 7, and so on. Under a
        // range of 3 to 5 there is no such pair, and the piece is finished
        // whatever its size. A hexagon has exactly one legal cut, into two
        // pentagons, which is why a lattice grammar settles into three, four,
        // and five sided cells rather than wandering upward.
        let rule = Rule.cut("cell", into: ("a", "b"), balance: 0.6, sides: 3 ... 5)
        var source = SplitMix64(seed: 31)
        for _ in 0 ..< 50 {
            #expect(rule.body(regular(7), &source) == nil)
            #expect(rule.body(regular(8), &source) == nil)
        }
        var hexagonCuts = 0
        for _ in 0 ..< 50 {
            guard let parts = rule.body(regular(6), &source) else { continue }
            hexagonCuts += 1
            #expect(parts.map { $0.corners.count } == [5, 5])
        }
        #expect(hexagonCuts > 20)
    }

    @Test func aCutKeepsBothPartsConvex() {
        let rule = Rule.cut("cell", into: ("a", "b"), sides: 3 ... 9)
        var source = SplitMix64(seed: 90)
        var cuts = 0
        for sides in [3, 4, 5, 7] {
            let start = regular(sides)
            for _ in 0 ..< 40 {
                guard let parts = rule.body(start, &source) else { continue }
                cuts += 1
                for part in parts { #expect(isConvex(part.corners)) }
            }
        }
        #expect(cuts > 120)
    }

    @Test func aCutStaysAwayFromTheCorners() {
        // A sliver is the failure mode of a random cut, and the corner window
        // is what rules it out. Every new corner sits well inside an edge.
        let rule = Rule.cut("cell", into: ("a", "b"), avoidingCorners: 0.25)
        var source = SplitMix64(seed: 13)
        let start = square(100)
        let originals = start.corners
        var cuts = 0
        for _ in 0 ..< 60 {
            guard let parts = rule.body(start, &source) else { continue }
            cuts += 1
            for part in parts {
                for point in part.corners where !originals.contains(where: { $0.distance(to: point) < 1e-9 }) {
                    // A new corner lies on an edge, a quarter of the way in at
                    // the very least.
                    let onX = abs(point.y) < 1e-9 || abs(point.y - 100) < 1e-9
                    let along = onX ? point.x : point.y
                    #expect(along > 24.9 && along < 75.1)
                }
            }
        }
        #expect(cuts > 40)
    }

    // MARK: - The run

    @Test func aRunKeepsTheWholeArea() {
        // Cuts partition, so a whole ice-ray design still covers its frame.
        let frame = Rectangle(x: 0, y: 0, width: 900, height: 600)
        let pieces = ShapeGrammar.iceRay(in: frame, minimumArea: 4_000).run(generations: 9, seed: 4)
        let total = pieces.reduce(0) { $0 + $1.area }
        #expect(abs(total - frame.width * frame.height) < 1e-4)
        #expect(pieces.count > 30)
    }

    @Test func noPieceFallsBelowTheFloorTheMinimumSets() {
        // A piece is only ever cut while it is at least `minimumArea`, and the
        // smaller part of a cut keeps at least `(1 - balance) / 2` of it. So
        // the smallest piece a run can leave is known before it runs.
        let balance = 0.3
        let minimumArea = 5_000.0
        let floor = minimumArea * (0.5 - balance / 2)
        let grammar = ShapeGrammar.iceRay(in: Rectangle(x: 0, y: 0, width: 1000, height: 800),
                                          minimumArea: minimumArea, balance: balance)
        for seed in 0 ..< 6 {
            let pieces = grammar.run(generations: 12, seed: seed)
            #expect(pieces.allSatisfy { $0.area > floor - 1e-6 })
        }
    }

    @Test func aRunReproducesFromItsSeed() {
        let grammar = ShapeGrammar.iceRay(in: Rectangle(x: 0, y: 0, width: 800, height: 800),
                                          minimumArea: 6_000)
        #expect(grammar.run(generations: 8, seed: 12) == grammar.run(generations: 8, seed: 12))
        #expect(grammar.run(generations: 8, seed: 12) != grammar.run(generations: 8, seed: 13))
    }

    @Test func everyPieceOfALatticeStaysConvex() {
        let grammar = ShapeGrammar.iceRay(in: Rectangle(x: 0, y: 0, width: 900, height: 900),
                                          minimumArea: 5_000)
        let pieces = grammar.run(generations: 10, seed: 8)
        #expect(pieces.allSatisfy { isConvex($0.corners) })
        #expect(pieces.allSatisfy { (3 ... 5).contains($0.corners.count) })
    }

    @Test func aLabelWithNoRuleIsFinished() {
        let grammar = ShapeGrammar(start: Piece("cell", square(100).contour),
                                   rules: [.split("cell", along: .x, at: [0.5], into: ["done"])])
        let once = grammar.run(generations: 1, seed: 1)
        let twice = grammar.run(generations: 6, seed: 1)
        #expect(once.count == 2)
        #expect(twice.count == 2)
        #expect(twice.allSatisfy { $0.label == "done" })
    }

    @Test func depthCountsTheRulesApplied() {
        let grammar = ShapeGrammar(start: square(400),
                                   rules: [.split("cell", along: .longest, at: [0.5],
                                                  into: ["cell"], minimumArea: 5_000)])
        let pieces = grammar.run(generations: 4, seed: 1)
        #expect(pieces.count == 16)
        #expect(pieces.allSatisfy { $0.depth == 4 })
    }

    @Test func aRunStopsAtTheCeiling() {
        var grammar = ShapeGrammar(start: square(4_000),
                                   rules: [.split("cell", along: .longest, at: [0.5], into: ["cell"])])
        grammar.maximumPieces = 100
        let pieces = grammar.run(generations: 20, seed: 1)
        #expect(pieces.count >= 100 && pieces.count <= 101)
    }

    @Test func aStopRuleEndsABranchEarly() {
        // Weighted heavily against the cut, most pieces should retire after a
        // generation or two rather than run to the size limit.
        let grammar = ShapeGrammar(
            start: Piece("cell", Rectangle(x: 0, y: 0, width: 1000, height: 1000)),
            rules: [.cut("cell", into: ("cell", "cell"), minimumArea: 100, weight: 1),
                    .stop("cell", into: "done", weight: 3)])
        let pieces = grammar.run(generations: 10, seed: 2)
        #expect(pieces.allSatisfy { $0.label == "done" })
        #expect(pieces.count < 40)
    }

    @Test func weightDecidesHowOftenARuleIsPicked() {
        let grammar = ShapeGrammar(
            start: Piece("cell", Rectangle(x: 0, y: 0, width: 100, height: 100)),
            rules: [.stop("cell", into: "often", weight: 3),
                    .stop("cell", into: "seldom", weight: 1)])
        var often = 0
        for seed in 0 ..< 400 where grammar.run(generations: 1, seed: seed)[0].label == "often" {
            often += 1
        }
        #expect(often > 260 && often < 340)   // 3 in 4 of 400, with room to roll
    }

    // MARK: - Splitting

    @Test func aSplitLandsOnItsFractions() {
        let piece = Piece("cell", Rectangle(x: 100, y: 50, width: 400, height: 200))
        let rule = Rule.split("cell", along: .x, at: [0.25, 0.5], into: ["a", "b", "c"])
        var source = SplitMix64(seed: 1)
        let parts = try! #require(rule.body(piece, &source))
        #expect(parts.count == 3)
        #expect(abs(parts[0].bounds.width - 100) < 1e-9)
        #expect(abs(parts[1].bounds.width - 100) < 1e-9)
        #expect(abs(parts[2].bounds.width - 200) < 1e-9)
        #expect(abs(parts.reduce(0) { $0 + $1.area } - piece.area) < 1e-6)
        #expect(parts.map(\.label) == ["a", "b", "c"])
    }

    @Test func aSplitCyclesItsLabels() {
        let piece = Piece("cell", Rectangle(x: 0, y: 0, width: 400, height: 100))
        let rule = Rule.split("cell", along: .x, at: [0.25, 0.5, 0.75], into: ["bar", "gap"])
        var source = SplitMix64(seed: 1)
        let parts = try! #require(rule.body(piece, &source))
        #expect(parts.map(\.label) == ["bar", "gap", "bar", "gap"])
    }

    @Test func theLongestAxisIsTheOneThatKeepsPartsFromGoingThin() {
        // Split a wide piece down its length and it stays wide forever. The
        // point of `.longest` is that the parts stay near square.
        let grammar = ShapeGrammar(start: Piece("cell", Rectangle(x: 0, y: 0, width: 800, height: 100)),
                                   rules: [.split("cell", along: .longest, at: [0.5],
                                                  into: ["cell"], minimumArea: 2_000)])
        let pieces = grammar.run(generations: 5, seed: 1)
        for piece in pieces {
            let ratio = piece.bounds.width / piece.bounds.height
            #expect(ratio > 0.4 && ratio < 2.5)
        }
    }

    // MARK: - Insetting

    @Test func anInsetKeepsTheWholeArea() {
        // The middle plus the ring around it is the piece it came from, so a
        // lattice drawn as bars still covers its frame.
        let piece = Piece("cell", Rectangle(x: 0, y: 0, width: 300, height: 200))
        let rule = Rule.inset("cell", by: 10, into: "hole", border: "bar")
        var source = SplitMix64(seed: 1)
        let parts = try! #require(rule.body(piece, &source))
        #expect(parts.count == 5)
        #expect(abs(parts.reduce(0) { $0 + $1.area } - piece.area) < 1e-6)
        let hole = try! #require(parts.first { $0.label == "hole" })
        #expect(abs(hole.area - 280 * 180) < 1e-6)
    }

    @Test func anInsetThatWouldCollapseDoesNotApply() {
        let piece = Piece("cell", Rectangle(x: 0, y: 0, width: 40, height: 40))
        let rule = Rule.inset("cell", by: 30, into: "hole")
        var source = SplitMix64(seed: 1)
        #expect(rule.body(piece, &source) == nil)
    }

    @Test func anInsetHoldsItsWidthOnASlantedEdge() {
        // Pushing each edge along its own normal is what keeps the bar the same
        // width all the way round. Scaling toward the middle would not.
        let piece = Piece("cell", regular(6, radius: 200).contour)
        let rule = Rule.inset("cell", by: 12, into: "hole")
        var source = SplitMix64(seed: 1)
        let parts = try! #require(rule.body(piece, &source))
        let hole = parts[0].corners
        let outline = piece.corners
        for k in outline.indices {
            let a = outline[k], b = outline[(k + 1) % outline.count]
            let heading = (b - a).normalized
            let away = abs((hole[k] - a).dot(heading.perpendicular))
            #expect(abs(away - 12) < 1e-6)
        }
    }

    // MARK: - Nesting

    @Test func nestingScalesAndTurnsExactlyOnce() {
        let start = square(400, at: Vector2(100, 100))
        let grammar = ShapeGrammar(start: Piece("square", start.contour),
                                   rules: [.nested("square", scale: 0.8, turn: .pi / 6,
                                                   into: "square", keeping: "drawn",
                                                   minimumArea: 1)])
        let pieces = grammar.run(generations: 5, seed: 1)
        for piece in pieces where piece.label == "drawn" {
            let expected = start.area * pow(0.8, 2 * Double(piece.depth - 1))
            #expect(abs(piece.area - expected) < 1e-6)
        }
        // The turn accumulates: the copy at depth n is n sixths of pi round.
        let drawn = pieces.filter { $0.label == "drawn" }.sorted { $0.depth < $1.depth }
        for piece in drawn {
            let heading = (piece.corners[1] - piece.corners[0]).angle
            let turned = Double(piece.depth - 1) * .pi / 6
            let apart = atan2(sin(heading - turned), cos(heading - turned))
            #expect(abs(apart) < 1e-9)
        }
    }

    @Test func theClassicNestedSquareMeetsTheEdgeMiddles() {
        // A scale of one over root two with an eighth turn is the figure the
        // whole family is named for: every corner of the copy sits on the
        // middle of an edge of the square that holds it.
        let frame = Rectangle(x: 0, y: 0, width: 400, height: 400)
        let pieces = ShapeGrammar.nestedSquares(in: frame, minimumArea: 100)
            .run(generations: 3, seed: 1)
        let inner = try! #require(pieces.first { $0.depth == 2 && $0.label == "drawn" })
        let outer = try! #require(pieces.first { $0.depth == 1 && $0.label == "drawn" })
        for corner in inner.corners {
            let onAnEdge = outer.corners.indices.contains { k in
                let a = outer.corners[k], b = outer.corners[(k + 1) % outer.corners.count]
                return a.lerp(to: b, 0.5).distance(to: corner) < 1e-6
            }
            #expect(onAnEdge)
        }
    }

    // MARK: - A grammar written by hand

    @Test func aFacadeGrammarReadsAsThreeSentences() {
        // Floors, then windows across each floor, then a pane inset in each
        // window. Three rules, and the design is a building front.
        let grammar = ShapeGrammar(
            start: Piece("wall", Rectangle(x: 0, y: 0, width: 600, height: 400)),
            rules: [.split("wall", along: .y, at: [0.25, 0.5, 0.75], into: ["floor"]),
                    .split("floor", along: .x, at: [0.2, 0.4, 0.6, 0.8], into: ["window"]),
                    .inset("window", by: 8, into: "pane", border: "frame")])
        let pieces = grammar.run(generations: 3, seed: 1)
        #expect(pieces.filter { $0.label == "pane" }.count == 20)
        #expect(pieces.filter { $0.label == "frame" }.count == 80)
        #expect(abs(pieces.reduce(0) { $0 + $1.area } - 600 * 400) < 1e-6)
    }

    @Test func aRuleOfNoWeightIsTheFallback() {
        // A weight of zero cannot be drawn, so the rule is only ever reached
        // when the others have refused. That is what lets a lattice ask for a
        // wide bar first and settle for a narrow one where there is no room.
        let wide = Rule.inset("cell", by: 30, into: "pane")
        let narrow = Rule.inset("cell", by: 4, into: "pane", weight: 0)
        let roomy = ShapeGrammar(start: Piece("cell", Rectangle(x: 0, y: 0, width: 400, height: 400)),
                                 rules: [wide, narrow]).run(generations: 1, seed: 5)
        let tight = ShapeGrammar(start: Piece("cell", Rectangle(x: 0, y: 0, width: 400, height: 40)),
                                 rules: [wide, narrow]).run(generations: 1, seed: 5)
        #expect(abs(roomy[0].area - 340 * 340) < 1e-6)
        #expect(abs(tight[0].area - 392 * 32) < 1e-6)
    }

    @Test func aCustomRuleCanRefuseAndPassThePieceOn() {
        let grammar = ShapeGrammar(
            start: Piece("cell", Rectangle(x: 0, y: 0, width: 100, height: 100)),
            rules: [.custom("cell", weight: 100) { _, _ in nil },
                    .stop("cell", into: "fallback", weight: 1)])
        let pieces = grammar.run(generations: 1, seed: 1)
        #expect(pieces.map(\.label) == ["fallback"])
    }
}
