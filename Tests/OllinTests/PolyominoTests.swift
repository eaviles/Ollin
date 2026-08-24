import Foundation
import Ollin
import Testing

/// Laws for polyominoes and for fitting them together. The pieces are whole
/// numbers, so every claim here is exact: how many ways a piece can sit, which
/// boards can be covered, and which famously cannot.
@Suite
struct PolyominoTests {
    // MARK: - The pieces

    /// Twelve pieces of five squares, no two of them the same piece turned or
    /// flipped. That is what "the twelve free pentominoes" means, checked rather
    /// than trusted.
    @Test func theTwelvePentominoesAreTwelveDifferentPiecesOfFive() {
        let pieces = Polyomino.pentominoes
        #expect(pieces.count == 12)
        #expect(Polyomino.pentominoNames.count == 12)
        for (piece, name) in zip(pieces, Polyomino.pentominoNames) {
            #expect(piece.count == 5, "\(name) has \(piece.count) squares")
        }
        for i in pieces.indices {
            let family = Set(pieces[i].orientations())
            for j in (i + 1) ..< pieces.count {
                #expect(!family.contains(pieces[j]),
                        "\(Polyomino.pentominoNames[i]) and \(Polyomino.pentominoNames[j]) are the same piece")
            }
        }
        #expect(Polyomino.tetrominoes.count == 5)
        #expect(Polyomino.tetrominoes.allSatisfy { $0.count == 4 })
    }

    /// The published count of how many ways each pentomino can sit. The symmetric
    /// ones give back fewer than eight, and the plus gives back one, which is the
    /// whole reason the orientations are counted instead of assumed.
    @Test func theOrientationCountsMatchTheKnownTable() {
        let expected = ["F": 8, "I": 2, "L": 8, "N": 8, "P": 8, "T": 4,
                        "U": 4, "V": 4, "W": 4, "X": 1, "Y": 8, "Z": 4]
        var total = 0
        for (piece, name) in zip(Polyomino.pentominoes, Polyomino.pentominoNames) {
            let count = piece.orientations().count
            #expect(count == expected[name], "\(name) has \(count) orientations")
            total += count
        }
        #expect(total == 63)
        // Without mirrors, a chiral piece loses half its ways of sitting.
        #expect(Polyomino.pentominoes[2].orientations(reflections: false).count == 4)   // L
        #expect(Polyomino.pentominoes[9].orientations(reflections: false).count == 1)   // X
    }

    /// A piece is a shape, not a place: however it is written down, it comes back
    /// normalized, so two ways of writing the same piece are the same value.
    @Test func aPieceNormalizesToItsOwnShape() {
        let plain = Polyomino([".X.", "XXX"])
        let shifted = Polyomino(cells: [Polyomino.Cell(11, 7), Polyomino.Cell(10, 8),
                                        Polyomino.Cell(11, 8), Polyomino.Cell(12, 8)])
        #expect(plain == shifted)
        #expect(plain.columns == 3 && plain.rows == 2)
        #expect(Polyomino(cells: []).isEmpty)
        #expect(Polyomino.rectangle(columns: 4, rows: 3).count == 12)
    }

    // MARK: - The outline

    /// The outline is the edges only one cell owns. Two independent measures: it is
    /// as long as those edges are, and it encloses as much as the cells cover.
    @Test func theOutlineIsExactlyTheBoundaryOfThePiece() {
        for piece in Polyomino.pentominoes + Polyomino.tetrominoes {
            let filled = Set(piece.cells)
            var edges = 0
            for cell in piece.cells {
                for step in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    if !filled.contains(Polyomino.Cell(cell.column + step.0, cell.row + step.1)) {
                        edges += 1
                    }
                }
            }
            let loops = piece.outlines(cellSize: 10)
            #expect(loops.count == 1)
            let length = loops.reduce(0.0) { $0 + $1.length }
            #expect(abs(length - Double(edges) * 10) < 1e-9, "outline length for a \(piece.count)-piece")
            let area = loops.reduce(0.0) { $0 + signedArea($1.points) }
            #expect(abs(abs(area) - Double(piece.count) * 100) < 1e-9)
        }
    }

    /// A piece with a hole hands back the hole as its own loop, wound the other
    /// way, so filling the shape leaves the hole open.
    @Test func aPieceWithAHoleHandsBackTwoLoops() {
        let ring = Polyomino(["XXX", "X.X", "XXX"])
        let loops = ring.outlines(cellSize: 10)
        #expect(loops.count == 2)
        let areas = loops.map { signedArea($0.points) }.sorted()
        // Eight cells outside, one cell of hole, and the two wound oppositely.
        #expect(abs(abs(areas[0]) + abs(areas[1]) - 1000) < 1e-9)
        #expect(areas[0] * areas[1] < 0)
    }

    // MARK: - Fitting them together

    /// The twelve pentominoes cover sixty squares, and every rectangle of sixty
    /// squares they can be laid in is a known result. All four have to come back
    /// with a real cover.
    @Test func theTwelvePentominoesTileEveryClassicRectangle() {
        for (columns, rows) in [(20, 3), (15, 4), (12, 5), (10, 6)] {
            let board = Polyomino.rectangle(columns: columns, rows: rows)
            guard let fit = tilePolyominoes(Polyomino.pentominoes, covering: board) else {
                Issue.record("no fit for \(columns) by \(rows)")
                continue
            }
            check(fit, covers: board, pieces: Polyomino.pentominoes, eachOnce: true)
            #expect(fit.count == 12)
        }
    }

    /// The classic impossibility, and the reason it is worth testing: a board with
    /// two opposite corners cut off has two more squares of one color than the
    /// other, and a domino always takes one of each. No search can find a cover,
    /// and the answer has to be nil rather than a wrong one.
    @Test func aBoardMissingTwoOppositeCornersRefusesDominoes() {
        let domino = Polyomino(["XX"])
        let whole = Polyomino.rectangle(columns: 6, rows: 6)
        #expect(tilePolyominoes([domino], covering: whole, reuse: true) != nil)

        let cut = Polyomino(cells: whole.cells.filter {
            !($0.column == 0 && $0.row == 0) && !($0.column == 5 && $0.row == 5)
        })
        #expect(cut.count == 34)
        #expect(tilePolyominoes([domino], covering: cut, reuse: true) == nil)

        // Cutting two squares of *different* colors leaves it tileable, which is
        // the other half of the same fact.
        let evenCut = Polyomino(cells: whole.cells.filter {
            !($0.column == 0 && $0.row == 0) && !($0.column == 1 && $0.row == 0)
        })
        #expect(tilePolyominoes([domino], covering: evenCut, reuse: true) != nil)
    }

    /// Reuse is the difference between a puzzle and a floor. Four T pieces fit a
    /// four-by-four square; one T never does.
    @Test func reuseDecidesWhetherOnePieceCanCoverEverything() {
        let tee = Polyomino(["XXX", ".X."])
        let board = Polyomino.rectangle(columns: 4, rows: 4)
        guard let fit = tilePolyominoes([tee], covering: board, reuse: true) else {
            Issue.record("four T pieces should fit a four by four")
            return
        }
        #expect(fit.count == 4)
        check(fit, covers: board, pieces: [tee], eachOnce: false)
        #expect(tilePolyominoes([tee], covering: board, reuse: false) == nil)
    }

    /// Turning a piece over is a real freedom, not a formality: a chiral piece
    /// cannot cover its own mirror unless mirrors are allowed.
    @Test func refusingMirrorsRefusesAPieceThatOnlyFitsMirrored() {
        let ell = Polyomino(["X.", "X.", "X.", "XX"])
        let mirrored = Polyomino([".X", ".X", ".X", "XX"])
        #expect(tilePolyominoes([ell], covering: mirrored, reflections: true) != nil)
        #expect(tilePolyominoes([ell], covering: mirrored, reflections: false) == nil)
        // And the piece always covers itself either way.
        #expect(tilePolyominoes([ell], covering: ell, reflections: false) != nil)
    }

    /// A piece whose bounding box starts on an empty corner still sits everywhere
    /// it fits. The F is the piece that catches this: its top-left square is not
    /// part of it, so a search that only ever anchors that corner on a board cell
    /// misses the places where the corner hangs off the edge.
    @Test func aPieceIsFoundWhereItsOwnCornerIsOffTheBoard() {
        let ef = Polyomino([".XX", "XX.", ".X."])
        #expect(tilePolyominoes([ef], covering: ef) != nil)
        // The same piece, in the board's top-left, where its bounding-box corner
        // lands outside the region entirely.
        let board = Polyomino(cells: ef.cells)
        guard let fit = tilePolyominoes([ef], covering: board) else {
            Issue.record("a piece has to fit its own outline")
            return
        }
        #expect(fit.count == 1)
        #expect(Set(fit[0].cells) == Set(board.cells))
    }

    /// The seed decides which fit comes back, and the same seed always gives the
    /// same one.
    @Test func theSeedDecidesWhichTilingComesBack() {
        let board = Polyomino.rectangle(columns: 10, rows: 6)
        var first = SplitMix64(seed: 3)
        var again = SplitMix64(seed: 3)
        var other = SplitMix64(seed: 91)
        let a = tilePolyominoes(Polyomino.pentominoes, covering: board, using: &first)
        let b = tilePolyominoes(Polyomino.pentominoes, covering: board, using: &again)
        let c = tilePolyominoes(Polyomino.pentominoes, covering: board, using: &other)
        #expect(a != nil && b != nil && c != nil)
        #expect(a == b)
        #expect(a != c)
        if let a { check(a, covers: board, pieces: Polyomino.pentominoes, eachOnce: true) }
        if let c { check(c, covers: board, pieces: Polyomino.pentominoes, eachOnce: true) }
    }

    /// Nothing to cover, or nothing to cover it with.
    @Test func anEmptyRegionOrAnEmptyBagIsAnsweredPlainly() {
        #expect(tilePolyominoes(Polyomino.pentominoes, covering: Polyomino(cells: []))?.isEmpty == true)
        #expect(tilePolyominoes([], covering: Polyomino.rectangle(columns: 2, rows: 2)) == nil)
        // Five squares can never be covered by pieces of two.
        #expect(tilePolyominoes([Polyomino(["XX"])],
                                covering: Polyomino(["XXXXX"]), reuse: true) == nil)
    }

    // MARK: - Helpers

    /// Every region cell covered exactly once, nothing outside it, and no piece
    /// used more often than allowed.
    private func check(_ fit: [PolyominoPlacement], covers region: Polyomino,
                       pieces: [Polyomino], eachOnce: Bool) {
        var counts: [Polyomino.Cell: Int] = [:]
        for placement in fit {
            for cell in placement.cells { counts[cell, default: 0] += 1 }
            // The shape laid down has to be one the piece can actually take.
            #expect(pieces[placement.piece].orientations().contains(placement.shape),
                    "piece \(placement.piece) was laid in a shape it cannot take")
        }
        for cell in region.cells {
            #expect(counts[cell] == 1, "cell \(cell) covered \(counts[cell] ?? 0) times")
        }
        #expect(counts.count == region.count, "something was covered outside the region")
        if eachOnce {
            let used = fit.map(\.piece)
            #expect(Set(used).count == used.count, "a piece was used twice")
        }
    }

    private func signedArea(_ points: [Vector2]) -> Double {
        guard points.count >= 3 else { return 0 }
        var total = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            total += a.x * b.y - b.x * a.y
        }
        return total / 2
    }
}
