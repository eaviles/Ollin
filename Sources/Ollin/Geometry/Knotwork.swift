import Foundation

/// Celtic knotwork: the same line a [`Kolam`](Kolam.swift) draws, given width
/// and a rule about who passes over whom.
///
/// A plait is one line, or a few, launched between a field of dots at 45
/// degrees and turned by the edge of the field and by any wall placed between
/// two dots. Wherever two passes meet, one goes over and the other goes under,
/// and the whole design holds together because that choice alternates: follow
/// any cord and it goes over, under, over, under, forever. A knot drawn that
/// way is called alternating, and it is what makes the weave read as woven
/// rather than as a tangle of lines.
///
/// The value hands back the cords already broken where they dive under, so
/// stroking the pieces *is* the weave. No masking, no draw order to get right:
///
/// ```swift
/// let knot = knotwork(columns: 7, rows: 5)
/// strokeCap(.round)
/// for band in knot.bands() {
///     stroke(.black); strokeWeight(22)      // the outline
///     drawPolyline(band.smoothed(iterations: 3).points, closed: band.isClosed)
///     stroke(.white); strokeWeight(15)      // the cord inside it
///     drawPolyline(band.smoothed(iterations: 3).points, closed: band.isClosed)
/// }
/// ```
///
/// Walls steer it exactly as they steer a kolam, and are what turn a plain
/// plait into a knot with a shape.
public struct Knotwork: Equatable, Sendable {
    /// The field of dots the cords weave around. One dot per cell, so the
    /// grid's `gutter` does not apply.
    public let grid: Grid
    /// The walls placed between dots, in the same terms a `Kolam` takes them.
    public let mirrors: [Kolam.Mirror]

    public init(grid: Grid, mirrors: [Kolam.Mirror] = []) {
        self.grid = grid
        self.mirrors = mirrors
    }

    // MARK: - The faces

    /// The whole cords, unbroken, one closed `Contour` each. This is the same
    /// line-work a `Kolam` over the same field gives, and it is what to draw
    /// when the weave is not wanted.
    public var cords: [Contour] {
        Kolam(grid: grid, mirrors: mirrors).loops
    }

    /// Where two passes meet. A point of the field where the line runs straight
    /// through is a crossing; a point where it turns (the outside edge, or a
    /// wall) is not, because only one pass ever reaches it.
    public var crossings: [Vector2] {
        let curve = MirrorCurve(columns: grid.columns, rows: grid.rows, mirrors: mirrors)
        var seen = [Bool](repeating: false, count: (curve.width + 1) * (curve.height + 1))
        var out: [Vector2] = []
        for walk in curve.loops {
            for pass in Self.passes(along: walk, of: curve) {
                let index = pass.point.y * (curve.width + 1) + pass.point.x
                // Both passes reach the same point, so it is kept once, in the
                // order the walk found it (never a Set: the order is the value).
                if !seen[index] {
                    seen[index] = true
                    out.append(curve.place(pass.point, in: grid.bounds))
                }
            }
        }
        return out
    }

    /// The cords broken where they pass under another, one open `Contour` per
    /// visible piece, in canvas coordinates. Stroke them and the weave is drawn.
    ///
    /// `gap` is how much cord is taken out at each dive, in canvas points. Left
    /// to itself it is a little over half the distance between two crossings,
    /// which suits a band about as wide as it. A cord that dives nowhere (a
    /// small loop with no crossing of its own) comes back whole and closed.
    public func bands(gap: Double? = nil) -> [Contour] {
        let curve = MirrorCurve(columns: grid.columns, rows: grid.rows, mirrors: mirrors)
        guard curve.columns > 0, curve.rows > 0 else { return [] }

        let step = curve.place(SIMD2(1, 1), in: grid.bounds) - curve.place(SIMD2(0, 0), in: grid.bounds)
        let span = step.length
        // Never as long as the piece between two crossings, or a cord that dives
        // twice in a row would have nothing left to draw between the dives.
        let cut = min(max(gap ?? span * 0.55, 0), span * 0.9) / 2

        var out: [Contour] = []
        for walk in curve.loops {
            let places = walk.map { curve.place($0, in: grid.bounds) }
            // The walk index, not the crossing's place in the list: a point the
            // line turns at carries no crossing, so the two do not line up.
            let dives = Self.passes(along: walk, of: curve).filter { !$0.isOver }.map(\.index)
            guard let first = dives.first else {
                out.append(Contour(places, closed: true))
                continue
            }

            // Start at a dive, so every piece runs from one dive to the next and
            // the wrap around the end of the walk needs no special case.
            let count = places.count
            var piece: [Vector2] = []
            let diving = Set(dives)
            for offset in 0 ... count {
                let index = (first + offset) % count
                let here = places[index]
                if diving.contains(index) {
                    let back = here - Self.direction(from: places, to: index, count: count) * cut
                    if !piece.isEmpty {
                        piece.append(back)
                        out.append(Contour(piece, closed: false))
                        piece = []
                    }
                    if offset < count {
                        let ahead = here + Self.direction(from: places, to: index + 1, count: count) * cut
                        piece = [ahead]
                    }
                } else if offset < count {
                    piece.append(here)
                }
            }
            if piece.count > 1 { out.append(Contour(piece, closed: false)) }
        }
        return out
    }

    // MARK: - Over and under

    /// Each point the walk passes through, and whether this pass goes over the
    /// one that crosses it there. A point the line *turns* at is left out: only
    /// one pass ever reaches it, so nothing crosses.
    ///
    /// The rule is one line long and it is the whole reason the weave holds:
    /// **the pass running up-right goes over wherever the crossing sits between
    /// two side-by-side dots, and under wherever it sits between two stacked
    /// ones.** Every step changes the crossing's x by one, so that parity flips
    /// at every crossing along a cord, which is exactly the alternation an
    /// alternating knot needs. And the two passes through one crossing run in
    /// opposite diagonal senses, so one of them is always the one that goes
    /// over.
    static func passes(along walk: [SIMD2<Int>],
                       of curve: MirrorCurve) -> [(index: Int, point: SIMD2<Int>, isOver: Bool)] {
        let count = walk.count
        guard count > 1 else { return [] }
        var out: [(Int, SIMD2<Int>, Bool)] = []
        out.reserveCapacity(count)
        for index in 0 ..< count {
            let here = walk[index]
            let previous = walk[(index + count - 1) % count]
            let next = walk[(index + 1) % count]
            let arrived = here &- previous, leaves = next &- here
            // A turn is not a crossing: the line bounced off the edge or a wall,
            // and no second pass comes through.
            guard arrived == leaves else { continue }
            let upRight = leaves.x * leaves.y > 0
            out.append((index, here, (here.x % 2 == 0) == upRight))
        }
        return out
    }

    /// The unit direction along the walk arriving at `index`, for stepping back
    /// off a crossing by the gap.
    private static func direction(from places: [Vector2], to index: Int, count: Int) -> Vector2 {
        let here = places[index % count]
        let previous = places[(index + count - 1) % count]
        let along = here - previous
        return along.length > 0 ? along / along.length : Vector2(1, 0)
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// A Celtic knot woven over a `columns × rows` field of dots filling
    /// `bounds` (the canvas by default). Hold the value to draw its `bands`,
    /// `cords`, and `crossings` yourself.
    func knotwork(in bounds: Rectangle? = nil, columns: Int, rows: Int,
                  mirrors: [Kolam.Mirror] = []) -> Knotwork {
        Knotwork(grid: Grid(in: bounds ?? self.bounds, columns: columns, rows: rows),
                 mirrors: mirrors)
    }

    /// Draw a knot as a two-tone band: the current `stroke` as the outline at
    /// `weight`, and `cordColor` filling it. The pieces are already broken where
    /// they dive under, so the weave comes out of the drawing order of one band
    /// at a time.
    func drawKnotwork(in bounds: Rectangle? = nil, columns: Int, rows: Int,
                      mirrors: [Kolam.Mirror] = [], weight: Double = 18,
                      cordColor: Color = .white, rounding: Int = 3) {
        let knot = knotwork(in: bounds, columns: columns, rows: rows, mirrors: mirrors)
        for band in knot.bands(gap: weight * 1.35) {
            let line = band.smoothed(iterations: rounding)
            // One band at a time, outline then cord: the next band's outline is
            // what cuts the last one where it passes over. Scoped so the cord
            // color never becomes the next band's outline.
            withState {
                strokeCap(.round)
                strokeJoin(.round)
                strokeWeight(weight)
                drawPolyline(line.points, closed: line.isClosed)
                stroke(cordColor)
                strokeWeight(max(weight - 6, 1))
                drawPolyline(line.points, closed: line.isClosed)
            }
        }
    }
}
