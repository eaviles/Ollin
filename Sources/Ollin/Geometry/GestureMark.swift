import Foundation

/// One drawn gesture made into marks a plotter can draw: a path, the width
/// at every point of it, and a seed turned into outlines and lines.
///
/// Build one from a mark the pointer recorded (its widths come along, times
/// the `width` you give it), or from any contour at one width, then ask it
/// for a family of marks:
///
/// ```swift
/// let gesture = GestureMark(pen, width: 40)          // a recorded StrokeMark
/// noStroke(); fill(.black)
/// drawShape(gesture.cloud(seed: 3).shape)            // one silhouette
/// for piece in gesture.dashes(rows: 3, seed: 3) {    // pieces to color
///     fill(palette[piece.row]); drawShape(piece.shape)
/// }
/// ```
///
/// The families fall in four groups. Outlines: a `cloud` of discs, a `chain`
/// of rounded squares, a band with `spikes`. Rows across the width:
/// `dashes`, `dots`, and `strips`, each row its own sequence, all of them
/// following a taper. Sprouts off both sides: a `feather`, `leaves`, a
/// `fringe`. Resampled from the ribbon: `pixels`, `facets`, `lanes`. Lines
/// around the path: a `spiral`, `strands` that wander across each other,
/// short `fragments`, a `wiggle`. Each returns `Piece`s: a closed contour is
/// a region to fill and an open one a line to stroke, so every piece draws,
/// hatches, and plots straight to SVG. Beside them, `hull` and `blob` are
/// regions that enclose the whole gesture, and `figure(_:)` is the shape its
/// two ends span.
///
/// **Sizes follow the width.** Every length a family takes (a dash, a gap,
/// a spike's spacing, a spiral's cycle) is a fraction of the gesture's width
/// where the piece sits, so a mark looks the same at any canvas size and
/// narrows with a taper. The pixels are the exception, since their grid is
/// the canvas's: their cell is in canvas units.
///
/// **A growing gesture never moves what it has drawn.** Every piece is
/// placed by its distance along the path from the start, and every row draws
/// its sizes from a sequence of its own seeded at that start, so adding a
/// point to the end only adds pieces: the ones already there keep their
/// exact points, except the last piece of a row, which reaches the tip and
/// grows with it. A sketch can rebuild the marks from its pen every frame and
/// nothing behind the pen flickers. The fragments wait until they are whole,
/// so they come in the order they finish.
public struct GestureMark: Equatable, Sendable {

    /// One mark a family laid down. A closed contour is a region to fill, an
    /// open one a line to stroke.
    public struct Piece: Equatable, Sendable {
        /// The outline or line.
        public let contour: Contour
        /// Which row it belongs to. Rows across the width count from the
        /// left edge (the left of the direction of travel); sprouts and
        /// pixels use `0` for the left side and `1` for the right; facets
        /// number the four triangles between two stations; strands and lanes
        /// number the copy. Everything else is row `0`.
        public let row: Int
        /// Its place in its row's sequence. A feather's two barbs at one
        /// station share it, so a palette indexed by it colors them alike.
        public let index: Int
        /// How far along the gesture it sits, from the start.
        public let distance: Double

        public init(contour: Contour, row: Int = 0, index: Int = 0, distance: Double = 0) {
            self.contour = contour
            self.row = row
            self.index = index
            self.distance = distance
        }

        /// The piece as a shape to hand `drawShape(_:)`.
        public var shape: Shape { Shape(contours: [contour], winding: .nonZero) }
    }

    /// A shape the gesture's two ends define, the way a drag defines one.
    public enum Figure: Equatable, Sendable {
        /// Centered on the start, through the end.
        case circle
        /// Filling the box the two ends span.
        case ellipse
        /// The box the two ends span.
        case rectangle
        /// A regular polygon centered on the start with a corner at the end.
        case polygon(sides: Int)
        /// A star centered on the start with a tip at the end; `inner` is its
        /// inner radius as a fraction of the outer.
        case star(points: Int, inner: Double = 0.45)
    }

    /// The path's points, as given.
    public let points: [Vector2]
    /// The width at each point.
    public let widths: [Double]

    let spine: GestureSpine

    /// A recorded mark at `width`: each point's width is `width` times the
    /// width the mark recorded there, as `drawMark(_:)` reads it under a
    /// `strokeWeight` of `width`.
    public init(_ mark: StrokeMark, width: Double) {
        self.init(points: mark.samples.map(\.position), widths: mark.samples.map { width * $0.width })
    }

    /// A contour at one width. A closed contour runs back to its first point.
    public init(_ spine: Contour, width: Double) {
        var points = spine.points
        if spine.isClosed, let first = points.first, points.count > 2 { points.append(first) }
        self.init(points: points, widths: Array(repeating: width, count: points.count))
    }

    /// Points with a width each. A short `widths` repeats its last value (an
    /// empty one is width 0).
    public init(points: [Vector2], widths: [Double]) {
        self.points = points
        self.widths = points.indices.map { i in
            widths.isEmpty ? 0 : Swift.max(widths[Swift.min(i, widths.count - 1)], 0)
        }
        spine = GestureSpine(points: points, widths: self.widths)
    }

    public static func == (a: GestureMark, b: GestureMark) -> Bool {
        a.points == b.points && a.widths == b.widths
    }

    /// The path's length.
    public var length: Double { spine.length }

    // MARK: - Outlines

    /// A cloud: discs strung along the path, each centered near it and
    /// reaching up to the edge of the width, their sizes and offsets drawn
    /// from the seed. `variation` from 0 (every disc the full width, on the
    /// path) to 1 (discs down to about half the width, wandering farther).
    /// Every disc covers the path where it sits and the next one overlaps it,
    /// so the union (`shape`) is one lumpy silhouette with no gap; the last
    /// disc sits on the tip.
    public func cloud(variation: Double = 0.5, seed: Int = 0) -> [Piece] {
        guard spine.isDrawable else { return [] }
        let variation = Swift.min(Swift.max(variation, 0), 1)
        var rng = Self.stream(seed, 1, 0)
        var pieces: [Piece] = []
        var s = 0.0
        var i = 0
        while s <= spine.settled {
            let frame = spine.frame(at: s)
            let h = Swift.max(frame.halfWidth, 0.25)
            let r = h * (1 - 0.45 * variation * Self.unit(&rng))
            let across = (h - r) * (2 * Self.unit(&rng) - 1)
            let center = frame.position + frame.normal * (i == 0 ? 0 : across)
            pieces.append(Piece(contour: Circle(center: center, radius: r).contour, index: i, distance: s))
            s += h * (0.2 + 0.3 * Self.unit(&rng))
            i += 1
        }
        if pieces.last?.distance != spine.length {
            let tip = spine.frame(at: spine.length)
            let r = Swift.max(tip.halfWidth, 0.25) * (1 - 0.225 * variation)
            pieces.append(Piece(contour: Circle(center: tip.position, radius: r).contour, index: i,
                                distance: spine.length))
        }
        return pieces
    }

    /// A chain of rounded squares stood on the path, each a little turned,
    /// its side the width there (a little less, drawn from the seed), one
    /// every `spacing` widths so neighbors overlap below 1. `roundness` is
    /// the corner radius as a fraction of half a side, 0 square to 1 round.
    public func chain(spacing: Double = 0.9, roundness: Double = 0.35, seed: Int = 0) -> [Piece] {
        guard spine.isDrawable else { return [] }
        let roundness = Swift.min(Swift.max(roundness, 0), 1)
        var rng = Self.stream(seed, 2, 0)
        var pieces: [Piece] = []
        var s = 0.0
        var i = 0
        while s <= spine.settled {
            let frame = spine.frame(at: s)
            let w = Swift.max(2 * frame.halfWidth, 0.5)
            let side = w * (0.85 + 0.15 * Self.unit(&rng))
            let angle = frame.tangent.angle + 0.18 * (2 * Self.unit(&rng) - 1)
            pieces.append(Piece(contour: Self.roundedSquare(center: frame.position, side: side, angle: angle,
                                                            radius: roundness * side / 2),
                                index: i, distance: s))
            s += Swift.max(spacing * w, 0.5)
            i += 1
        }
        return pieces
    }

    /// The band of the width with spikes along both edges, one every
    /// `spacing` widths on each side. Each edge is pushed out by `height`
    /// widths times a triangle wave raised to `sharpness`: the wave's peak
    /// keeps every tip a sharp point and, above 1, the power rounds every
    /// valley, which sits back on the band's edge and steepens the flanks
    /// (at the defaults every tip is narrower than about 65 degrees; at a
    /// `sharpness` of 1 the flanks are straight and a short spike can open
    /// past a right angle). A spike's height (down to about two thirds) and
    /// where its tip leans within its period are drawn from the seed. One
    /// piece per period; their union (`shape`) is the band.
    public func spikes(spacing: Double = 0.5, height: Double = 0.3, sharpness: Double = 2,
                       seed: Int = 0) -> [Piece] {
        guard spine.isDrawable else { return [] }
        let power = Swift.max(sharpness, 0.1)
        var rng = Self.stream(seed, 3, 0)
        var pieces: [Piece] = []
        var s = 0.0
        var i = 0
        while s < spine.length {
            let w = 2 * spine.frame(at: s).halfWidth
            let period = Swift.max(spacing * w, 0.5)
            var sides: [(height: Double, lean: Double)] = []
            for _ in 0 ..< 2 {
                let tall = Swift.max(height, 0) * w * (1 - 0.35 * Self.unit(&rng))
                sides.append((tall, 0.5 + 0.125 * (2 * Self.unit(&rng) - 1)))
            }
            let end = s + period
            let cut = end > spine.settled ? Swift.min(end, spine.length) : end
            func edge(_ side: Int, _ sign: Double) -> [Vector2] {
                let (tall, lean) = sides[side]
                let limit = (cut - s) / period
                var fractions = (0 ... 12).map { lean * Double($0) / 12 } + (1 ... 12).map { lean + (1 - lean) * Double($0) / 12 }
                fractions = fractions.filter { $0 < limit - 1e-12 } + [Swift.min(limit, 1)]
                return fractions.map { f in
                    let frame = spine.frame(at: s + f * period)
                    let wave = f <= lean ? f / lean : (1 - f) / (1 - lean)
                    return frame.position + frame.normal * (sign * (frame.halfWidth + tall * pow(wave, power)))
                }
            }
            let left = edge(0, 1)
            let right = edge(1, -1)
            pieces.append(Piece(contour: Contour(left + right.reversed(), closed: true), index: i, distance: s))
            if end > spine.settled { break }
            s = end
            i += 1
        }
        return pieces
    }

    // MARK: - Rows across the width

    /// Dashes in `rows` rows across the width, each row its own seeded run
    /// of dashes and gaps: a dash about `length` and a gap about `gap` of
    /// the row's own thickness (half to one and a half times that), the rows
    /// staggered, each dash's sides following the path and the taper.
    public func dashes(rows: Int = 3, length: Double = 2, gap: Double = 0.6, seed: Int = 0) -> [Piece] {
        rowRuns(rows: rows, salt: 4, seed: seed, inset: 0.12) { rng, thickness in
            (Swift.max(length * thickness * (0.5 + Self.unit(&rng)), 0.5),
             Swift.max(gap * thickness * (0.5 + Self.unit(&rng)), 0.25))
        }
    }

    /// Strips in `rows` rows across the width: each row cut end to end into
    /// lengths about `length` of the row's thickness (a third to over twice
    /// that), no gaps, so a palette indexed by `index` makes a patchwork.
    public func strips(rows: Int = 4, length: Double = 2, seed: Int = 0) -> [Piece] {
        rowRuns(rows: rows, salt: 5, seed: seed, inset: 0) { rng, thickness in
            (Swift.max(length * thickness * (0.3 + 1.4 * Self.unit(&rng)), 0.5), 0)
        }
    }

    /// Dots in `rows` rows across the width, each row its own seeded run:
    /// a dot `size` of the row's thickness across (down to six tenths of
    /// that), `gap` of it apart (a third to all of it), centered in its row.
    public func dots(rows: Int = 3, size: Double = 0.8, gap: Double = 0.4, seed: Int = 0) -> [Piece] {
        guard spine.isDrawable else { return [] }
        let rows = Swift.max(rows, 1)
        var pieces: [Piece] = []
        for row in 0 ..< rows {
            var rng = Self.stream(seed, 6, row)
            let middle = 1 - (2 * Double(row) + 1) / Double(rows)
            var s = gap * thickness(at: 0, rows: rows) * Self.unit(&rng)
            var i = 0
            while true {
                let t = thickness(at: s, rows: rows)
                let diameter = Swift.max(size * t * (0.6 + 0.4 * Self.unit(&rng)), 0.5)
                let space = Swift.max(gap * t * (0.3 + 0.7 * Self.unit(&rng)), 0.1)
                let center = s + diameter / 2
                guard center <= spine.settled else { break }
                let frame = spine.frame(at: center)
                let at = frame.position + frame.normal * (middle * frame.halfWidth)
                pieces.append(Piece(contour: Circle(center: at, radius: diameter / 2).contour,
                                    row: row, index: i, distance: center))
                s += diameter + space
                i += 1
            }
        }
        return pieces
    }

    // MARK: - Sprouts

    /// A feather: a barb off each side at every station, leaning forward
    /// `angle` off the path and reaching the edge of the width, bowed a
    /// little toward the base. The stations stand about `spacing` widths
    /// apart; the two barbs at one station share an `index`.
    public func feather(angle: Double = .pi / 4, spacing: Double = 0.12, seed: Int = 0) -> [Piece] {
        sprouts(salt: 7, seed: seed, spacing: { w, rng in Swift.max(spacing * w, 0.5) * (0.8 + 0.4 * Self.unit(&rng)) }) {
            frame, side, _, rng in
            let lean = Self.clampedAngle(angle + 0.1 * (2 * Self.unit(&rng) - 1))
            let reach = frame.halfWidth / sin(lean) * (0.85 + 0.15 * Self.unit(&rng))
            let direction = frame.tangent * cos(lean) + frame.normal * (side * sin(lean))
            let bow = frame.tangent * (-0.08 * reach)
            let line = (0 ... 6).map { j -> Vector2 in
                let t = Double(j) / 6
                return frame.position + direction * (reach * t) + bow * (4 * t * (1 - t))
            }
            return Contour(line, closed: false)
        }
    }

    /// Leaves on alternate sides, leaving the path `angle` forward, each a
    /// pointed blade up to `size` times the reach to the edge of the width
    /// (down to about half of it), the gaps between them drawn from the seed.
    public func leaves(angle: Double = .pi / 4, size: Double = 1, seed: Int = 0) -> [Piece] {
        guard spine.isDrawable else { return [] }
        var rng = Self.stream(seed, 8, 0)
        var pieces: [Piece] = []
        var s = Swift.max(2 * spine.frame(at: 0).halfWidth, 0.5) * 0.3 * Self.unit(&rng)
        var i = 0
        while s <= spine.settled {
            let frame = spine.frame(at: s)
            let w = Swift.max(2 * frame.halfWidth, 0.5)
            let side: Double = i % 2 == 0 ? 1 : -1
            let lean = Self.clampedAngle(angle + 0.15 * (2 * Self.unit(&rng) - 1))
            let reach = Swift.max(size, 0) * frame.halfWidth / sin(lean) * (0.55 + 0.45 * Self.unit(&rng))
            let direction = frame.tangent * cos(lean) + frame.normal * (side * sin(lean))
            let across = direction.perpendicular
            let blade = reach * 0.28
            var outline: [Vector2] = []
            for j in 0 ... 16 {
                let t = Double(j) / 16
                outline.append(frame.position + direction * (reach * t) + across * (blade * Self.bladeWidth(t)))
            }
            for j in stride(from: 15, through: 1, by: -1) {
                let t = Double(j) / 16
                outline.append(frame.position + direction * (reach * t) - across * (blade * Self.bladeWidth(t)))
            }
            pieces.append(Piece(contour: Contour(outline, closed: true), row: side > 0 ? 0 : 1, index: i,
                                distance: s))
            s += w * (0.35 + 0.5 * Self.unit(&rng))
            i += 1
        }
        return pieces
    }

    /// A fringe: thin straight hairs off both sides, dense, every `spacing`
    /// widths along, each leaving the path `angle` forward and reaching about
    /// the edge of the width (seven tenths to past it), its angle a little
    /// jittered by the seed. A palette indexed by `row` colors each side.
    public func fringe(angle: Double = .pi / 3, spacing: Double = 0.05, seed: Int = 0) -> [Piece] {
        sprouts(salt: 9, seed: seed, spacing: { w, _ in Swift.max(spacing * w, 0.4) }) { frame, side, _, rng in
            let lean = Self.clampedAngle(angle + 0.08 * (2 * Self.unit(&rng) - 1))
            let reach = frame.halfWidth / sin(lean) * (0.7 + 0.5 * Self.unit(&rng))
            let direction = frame.tangent * cos(lean) + frame.normal * (side * sin(lean))
            return Contour([frame.position, frame.position + direction * reach], closed: false)
        }
    }

    // MARK: - Resampled from the ribbon

    /// The ribbon as pixels: the canvas cells of side `cell` (in canvas
    /// units) the width covers, each side out to its own ragged extent (the
    /// width's half times one plus `roughness` of a slow noise, seeded per
    /// side), so the two edges step independently. A cell is claimed once,
    /// by the side that reached it first (`row` 0 the left, 1 the right).
    public func pixels(cell: Double, roughness: Double = 0.3, seed: Int = 0) -> [Piece] {
        guard spine.isDrawable else { return [] }
        let cell = Swift.max(cell, 0.5)
        var claimed = Set<GridCell>()
        var pieces: [Piece] = []
        var counts = [0, 0]
        let station = cell / 3
        var k = 0
        while Double(k) * station <= spine.settled {
            let s = Double(k) * station
            let frame = spine.frame(at: s)
            for (row, sign) in [(0, 1.0), (1, -1.0)] {
                let ragged = 1 + roughness * Self.smooth(s / (4 * cell), seed, 10 + row)
                let extent = Swift.max(frame.halfWidth * ragged, 0)
                var a = 0.0
                while a <= extent + 1e-9 {
                    let q = frame.position + frame.normal * (sign * a)
                    let key = GridCell(x: Int((q.x / cell).rounded(.down)), y: Int((q.y / cell).rounded(.down)))
                    if claimed.insert(key).inserted {
                        let x = Double(key.x) * cell, y = Double(key.y) * cell
                        let square = Contour([Vector2(x, y), Vector2(x + cell, y), Vector2(x + cell, y + cell),
                                              Vector2(x, y + cell)], closed: true)
                        pieces.append(Piece(contour: square, row: row, index: counts[row], distance: s))
                        counts[row] += 1
                    }
                    a += station
                }
            }
            k += 1
        }
        return pieces
    }

    /// The ribbon as facets: stations about `spacing` widths apart, each
    /// with a point on either edge and one on the path, every point moved by
    /// up to `jitter` of the half width (seeded per station), and four
    /// triangles between each two stations (`row` 0 to 3).
    public func facets(spacing: Double = 0.7, jitter: Double = 0.3, seed: Int = 0) -> [Piece] {
        guard spine.isDrawable else { return [] }
        func corners(_ k: Int, _ s: Double) -> [Vector2] {
            let frame = spine.frame(at: s)
            return [1.0, 0, -1].enumerated().map { j, side in
                let wobble = Vector2(2 * Self.hash(seed, 11, k, 2 * j) - 1, 2 * Self.hash(seed, 11, k, 2 * j + 1) - 1)
                return frame.position + frame.normal * (side * frame.halfWidth) + wobble * (jitter * frame.halfWidth)
            }
        }
        var pieces: [Piece] = []
        var s = 0.0
        var k = 0
        var here = corners(0, 0)
        while s < spine.length {
            let step = Swift.max(spacing * 2 * spine.frame(at: s).halfWidth, 0.5)
            let next = s + step
            let reached = next > spine.settled ? Swift.min(next, spine.length) : next
            let there = corners(k + 1, reached)
            let (l0, c0, r0, l1, c1, r1) = (here[0], here[1], here[2], there[0], there[1], there[2])
            let triangles = k % 2 == 0
                ? [[l0, c0, c1], [l0, c1, l1], [c0, r0, r1], [c0, r1, c1]]
                : [[l0, c0, l1], [c0, c1, l1], [c0, r0, c1], [r0, r1, c1]]
            for (row, triangle) in triangles.enumerated() {
                pieces.append(Piece(contour: Contour(triangle, closed: true), row: row, index: k, distance: s))
            }
            if next > spine.settled { break }
            here = there
            s = next
            k += 1
        }
        return pieces
    }

    /// The ribbon split into `count` lanes running side by side, `gap` of a
    /// lane's width between neighbors, the borders between them wandering
    /// across by up to `wander` of a lane on a slow seeded noise. One piece
    /// per lane per width of length; `row` numbers the lane from the left.
    public func lanes(count: Int = 3, gap: Double = 0.12, wander: Double = 0.5, seed: Int = 0) -> [Piece] {
        guard spine.isDrawable else { return [] }
        let count = Swift.max(count, 1)
        let lane = 2 / Double(count)
        let margin = Swift.min(Swift.max(gap, 0), 0.9) * lane / 2
        func border(_ i: Int, _ s: Double) -> Double {
            let base = 1 - Double(i) * lane
            guard i > 0, i < count else { return base }
            return base + wander * lane / 2 * Self.smooth(spine.widthsAlong(s) / 3, seed, 12 + i)
        }
        var pieces: [Piece] = []
        var s = 0.0
        var j = 0
        while s < spine.length {
            let next = s + Swift.max(2 * spine.frame(at: s).halfWidth, 1)
            let end = next > spine.settled ? Swift.min(next, spine.length) : next
            for i in 0 ..< count {
                pieces.append(Piece(contour: band(from: s, to: end,
                                                  lower: { border(i + 1, $0) + margin },
                                                  upper: { border(i, $0) - margin }),
                                    row: i, index: j, distance: s))
            }
            if next > spine.settled { break }
            s = next
            j += 1
        }
        return pieces
    }

    // MARK: - Around the path

    /// A coil wound along the path: a point that circles the path once every
    /// `cycle` widths of length while its center walks it, across the full
    /// width and `loop` half widths along, so above about a third it throws
    /// loops. One piece per turn.
    public func spiral(cycle: Double = 1, loop: Double = 1) -> [Piece] {
        cycles(of: Swift.max(cycle, 0.05), samples: 64) { frame, phase in
            frame.position + frame.normal * (frame.halfWidth * sin(2 * .pi * phase))
                + frame.tangent * (frame.halfWidth * loop * cos(2 * .pi * phase))
        }
    }

    /// `count` copies of the path drifting across it on slow seeded waves,
    /// each up to `spread` of the half width either side, a wave about
    /// `wavelength` widths long, so they cross and recross like loose
    /// strands. One piece per wavelength; `row` numbers the strand.
    public func strands(count: Int = 5, spread: Double = 1, wavelength: Double = 4, seed: Int = 0) -> [Piece] {
        let wavelength = Swift.max(wavelength, 0.1)
        return (0 ..< Swift.max(count, 1)).flatMap { strand in
            cycles(of: wavelength, samples: 32, row: strand) { frame, phase in
                frame.position + frame.normal * (frame.halfWidth * spread * Self.smooth(phase, seed, 20 + strand))
            }
        }
    }

    /// Short copies of the path scattered beside it: one starts every so
    /// often (about `0.15` to `0.65` widths apart, divided by `density`),
    /// runs about `length` widths (half to one and a half times that), and
    /// sits up to `spread` of the half width to one side. A fragment appears
    /// once it is whole, so they come in the order they end.
    public func fragments(density: Double = 1, length: Double = 2, spread: Double = 1, seed: Int = 0) -> [Piece] {
        guard spine.isDrawable else { return [] }
        let density = Swift.max(density, 0.05)
        var rng = Self.stream(seed, 13, 0)
        var found: [(end: Double, piece: Piece)] = []
        var s = Swift.max(2 * spine.frame(at: 0).halfWidth, 0.5) * 0.5 / density * Self.unit(&rng)
        var i = 0
        while s < spine.settled {
            let w = Swift.max(2 * spine.frame(at: s).halfWidth, 0.5)
            let run = Swift.max(length * w * (0.5 + Self.unit(&rng)), 1)
            let across = spread * (2 * Self.unit(&rng) - 1)
            if s + run <= spine.settled {
                let line = stations(from: s, to: s + run).map { at -> Vector2 in
                    let frame = spine.frame(at: at)
                    return frame.position + frame.normal * (across * frame.halfWidth)
                }
                found.append((s + run, Piece(contour: Contour(line, closed: false).simplified(tolerance: 0.02),
                                             index: i, distance: s)))
            }
            s += Swift.max(w * (0.15 + 0.5 * Self.unit(&rng)) / density, 0.25)
            i += 1
        }
        return found.sorted { $0.end != $1.end ? $0.end < $1.end : $0.piece.index < $1.piece.index }.map(\.piece)
    }

    /// The path with one even wiggle: across `amplitude` of the half width
    /// either side, once every `wavelength` widths of length. One piece per
    /// wavelength.
    public func wiggle(wavelength: Double = 1, amplitude: Double = 0.5) -> [Piece] {
        cycles(of: Swift.max(wavelength, 0.05), samples: 32) { frame, phase in
            frame.position + frame.normal * (frame.halfWidth * amplitude * sin(2 * .pi * phase))
        }
    }

    // MARK: - Regions around the whole gesture

    /// The convex hull of the gesture's points grown by `padding` with
    /// round corners: the smooth blob a gesture sketches around a group.
    /// `padding` defaults to half the gesture's mean width.
    public func hull(padding: Double? = nil) -> Shape {
        guard !points.isEmpty else { return Shape(contours: [], winding: .nonZero) }
        let pad = Swift.max(padding ?? meanWidth / 2, 0)
        let corners = convexHull(of: points)
        if corners.count == 1 {
            return Shape(contours: [Circle(center: corners[0], radius: Swift.max(pad, 0.25)).contour], winding: .nonZero)
        }
        if corners.count < 3 {
            return Contour(corners, closed: false).stroked(width: Swift.max(2 * pad, 0.5), join: .round, cap: .round)
        }
        return Shape(contours: [Contour(corners, closed: true)], winding: .nonZero).offset(by: pad, join: .round)
    }

    /// The tight blob: the gesture closed into a loop and everything within
    /// `radius` of it, the region inside included, so a lasso becomes the
    /// shape it drew round. `radius` defaults to half the gesture's mean
    /// width; a gesture that crosses itself keeps every lobe.
    public func blob(radius: Double? = nil) -> Shape {
        guard !points.isEmpty else { return Shape(contours: [], winding: .nonZero) }
        let r = Swift.max(radius ?? meanWidth / 2, 0)
        if spine.length == 0 {
            return Shape(contours: [Circle(center: points[0], radius: Swift.max(r, 0.25)).contour], winding: .nonZero)
        }
        if points.count < 3 {
            return Contour(points, closed: false).stroked(width: Swift.max(2 * r, 0.5), join: .round, cap: .round)
        }
        let loop = Shape(contours: [Contour(points, closed: true)], winding: .nonZero)
        return loop.offset(by: r, join: .round)
    }

    /// The figure the gesture's start and end define, the way a drag defines
    /// a shape (see `Figure`).
    public func figure(_ kind: Figure) -> Shape {
        guard let start = points.first, let end = points.last else { return Shape(contours: [], winding: .nonZero) }
        let reach = end - start
        let radius = reach.length
        let box = Rectangle(x: Swift.min(start.x, end.x), y: Swift.min(start.y, end.y),
                            width: abs(reach.x), height: abs(reach.y))
        let outline: Contour
        switch kind {
        case .circle:
            outline = Circle(center: start, radius: radius).contour
        case .ellipse:
            let center = Vector2(box.x + box.width / 2, box.y + box.height / 2)
            let count = Circle.segmentCount(forRadius: Swift.max(box.width, box.height) / 2)
            outline = Contour((0 ..< count).map { i in
                let a = Double(i) / Double(count) * 2 * .pi
                return center + Vector2(cos(a) * box.width / 2, sin(a) * box.height / 2)
            }, closed: true)
        case .rectangle:
            outline = box.contour
        case .polygon(let sides):
            let n = Swift.max(sides, 3)
            outline = Contour((0 ..< n).map { i in
                start + reach.rotated(by: Double(i) / Double(n) * 2 * .pi)
            }, closed: true)
        case .star(let tips, let inner):
            let n = Swift.max(tips, 2)
            outline = Contour((0 ..< 2 * n).map { i in
                let arm = i % 2 == 0 ? reach : reach * Swift.min(Swift.max(inner, 0), 1)
                return start + arm.rotated(by: Double(i) / Double(2 * n) * 2 * .pi)
            }, closed: true)
        }
        return Shape(contours: [outline], winding: .nonZero)
    }

    // MARK: - Internals

    private var meanWidth: Double {
        widths.isEmpty ? 0 : widths.reduce(0, +) / Double(widths.count)
    }

    /// A row's thickness at `s`: the width split across `rows`.
    private func thickness(at s: Double, rows: Int) -> Double {
        Swift.max(2 * spine.frame(at: s).halfWidth / Double(rows), 0.25)
    }

    /// The arc lengths a piece from `a` to `b` samples: both ends and every
    /// spine station strictly between, so its sides bend where the path does.
    private func stations(from a: Double, to b: Double) -> [Double] {
        var out = [a]
        var k = Int((a / GestureSpine.step).rounded(.down)) + 1
        while Double(k) * GestureSpine.step < b - 1e-9 {
            out.append(Double(k) * GestureSpine.step)
            k += 1
        }
        out.append(b)
        return out
    }

    /// The region between two offsets across the path, from `a` to `b`
    /// along it; the offsets are fractions of the half width.
    private func band(from a: Double, to b: Double, lower: (Double) -> Double,
                      upper: (Double) -> Double) -> Contour {
        let along = stations(from: a, to: b)
        let frames = along.map { spine.frame(at: $0) }
        let top = zip(along, frames).map { s, f in f.position + f.normal * (upper(s) * f.halfWidth) }
        let bottom = zip(along, frames).map { s, f in f.position + f.normal * (lower(s) * f.halfWidth) }
        return Contour(top + bottom.reversed(), closed: true).simplified(tolerance: 0.02)
    }

    /// Rows of runs across the width: each row walks its own seeded sequence
    /// of (run, gap) lengths from the start, the first run staggered.
    private func rowRuns(rows: Int, salt: Int, seed: Int, inset: Double,
                         next: (inout SplitMix64, Double) -> (run: Double, gap: Double)) -> [Piece] {
        guard spine.isDrawable else { return [] }
        let rows = Swift.max(rows, 1)
        let span = 2 / Double(rows)
        var pieces: [Piece] = []
        for row in 0 ..< rows {
            var rng = Self.stream(seed, salt, row)
            let top = 1 - Double(row) * span - inset * span
            let bottom = 1 - Double(row + 1) * span + inset * span
            var s = -thickness(at: 0, rows: rows) * Self.unit(&rng)
            var i = 0
            while s < spine.length {
                let (run, gap) = next(&rng, thickness(at: Swift.max(s, 0), rows: rows))
                let end = s + run
                let from = Swift.max(s, 0)
                let to = end > spine.settled ? Swift.min(end, spine.length) : end
                if to - from > 1e-6 {
                    pieces.append(Piece(contour: band(from: from, to: to, lower: { _ in bottom }, upper: { _ in top }),
                                        row: row, index: i, distance: from))
                    i += 1
                }
                if end > spine.settled { break }
                s = end + gap
            }
        }
        return pieces
    }

    /// Sprouts off both sides at seeded stations: each station a left and a
    /// right sprout (rows 0 and 1) sharing its index.
    private func sprouts(salt: Int, seed: Int, spacing: (Double, inout SplitMix64) -> Double,
                         make: (GestureSpine.Frame, Double, Int, inout SplitMix64) -> Contour) -> [Piece] {
        guard spine.isDrawable else { return [] }
        var rng = Self.stream(seed, salt, 0)
        var pieces: [Piece] = []
        var s = spacing(Swift.max(2 * spine.frame(at: 0).halfWidth, 0.5), &rng) * Self.unit(&rng)
        var k = 0
        while s <= spine.settled {
            let frame = spine.frame(at: s)
            for (row, side) in [(0, 1.0), (1, -1.0)] {
                pieces.append(Piece(contour: make(frame, side, k, &rng), row: row, index: k, distance: s))
            }
            s += spacing(Swift.max(2 * frame.halfWidth, 0.5), &rng)
            k += 1
        }
        return pieces
    }

    /// A line made one piece per cycle, a cycle `widths` widths of length,
    /// sampled `samples` times a cycle; `point` places a sample from its
    /// frame and its phase in cycles.
    private func cycles(of widths: Double, samples: Int, row: Int = 0,
                        point: (GestureSpine.Frame, Double) -> Vector2) -> [Piece] {
        guard spine.isDrawable else { return [] }
        let reached = spine.widthsAlong(spine.length)
        var pieces: [Piece] = []
        var m = 0
        while Double(m) * widths < reached - 1e-9 {
            let isTip = spine.distance(atWidths: Double(m + 1) * widths) > spine.settled
            var line: [Vector2] = []
            for j in 0 ... samples {
                let phase = Double(m) + Double(j) / Double(samples)
                if phase * widths >= reached {
                    line.append(point(spine.frame(at: spine.length), reached / widths))
                    break
                }
                line.append(point(spine.frame(at: spine.distance(atWidths: phase * widths)), phase))
            }
            pieces.append(Piece(contour: Contour(line, closed: false), row: row, index: m,
                                distance: spine.distance(atWidths: Double(m) * widths)))
            if isTip { break }
            m += 1
        }
        return pieces
    }

    private struct GridCell: Hashable {
        let x: Int
        let y: Int
    }

    /// A rounded square of `side` turned to `angle`, its corners arcs of
    /// `radius`.
    static func roundedSquare(center: Vector2, side: Double, angle: Double, radius: Double) -> Contour {
        let half = side / 2
        let r = Swift.min(Swift.max(radius, 0), half)
        let inner = half - r
        var points: [Vector2] = []
        let corners = [Vector2(inner, inner), Vector2(-inner, inner), Vector2(-inner, -inner), Vector2(inner, -inner)]
        for (c, corner) in corners.enumerated() {
            let start = Double(c) * .pi / 2
            if r < 1e-9 {
                points.append(corner)
                continue
            }
            for j in 0 ... 5 {
                points.append(corner + Vector2(angle: start + Double(j) / 5 * .pi / 2, length: r))
            }
        }
        return Contour(points.map { center + $0.rotated(by: angle) }, closed: true)
    }

    /// A leaf's half width along it, 0 at the base and the tip, widest a
    /// little below the middle.
    static func bladeWidth(_ t: Double) -> Double {
        pow(sin(.pi * pow(t, 0.8)), 0.9)
    }

    /// An angle kept off the path, between about 3 and 177 degrees.
    static func clampedAngle(_ angle: Double) -> Double {
        Swift.min(Swift.max(angle, 0.05), .pi - 0.05)
    }

    /// A seeded generator for one family (`salt`) and one row of it.
    static func stream(_ seed: Int, _ salt: Int, _ row: Int) -> SplitMix64 {
        var mixer = SplitMix64(seed: UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15
                                   ^ UInt64(bitPattern: Int64(salt)) &* 0xBF58_476D_1CE4_E5B9
                                   ^ UInt64(bitPattern: Int64(row &+ 1)) &* 0x94D0_49BB_1331_11EB)
        return SplitMix64(seed: mixer.next())
    }

    /// A uniform draw in `0..<1`, written out so it never depends on the
    /// standard library's own conversion.
    static func unit(_ rng: inout SplitMix64) -> Double {
        Double(rng.next() >> 11) * 0x1.0p-53
    }

    /// A uniform value in `0..<1` hashed from a seed, a salt, and two indices.
    static func hash(_ seed: Int, _ salt: Int, _ i: Int, _ j: Int) -> Double {
        var rng = stream(seed, salt, i &* 0x2F1 &+ j)
        return unit(&rng)
    }

    /// Smooth value noise in `-1...1` along one axis: hashed values at the
    /// integers, eased between.
    static func smooth(_ x: Double, _ seed: Int, _ salt: Int) -> Double {
        let i = Int(x.rounded(.down))
        let f = x - Double(i)
        let a = 2 * hash(seed, salt, i, 0) - 1
        let b = 2 * hash(seed, salt, i + 1, 0) - 1
        return a + (b - a) * (f * f * (3 - 2 * f))
    }
}

extension Array where Element == GestureMark.Piece {
    /// The closed pieces as one region, their overlaps merged: the cloud's
    /// silhouette, the spiked band, the pixels as one outline. Open pieces
    /// are left out.
    public var shape: Shape {
        let empty = Shape(contours: [], winding: .nonZero)
        // Each piece is resolved on its own first, so a piece whose outline
        // twists on a tight bend comes back as plain regions wound one way,
        // and a lobe wound backward cannot cancel a neighbor where they overlap.
        let resolved = filter { $0.contour.isClosed && $0.contour.points.count >= 3 }.flatMap { piece in
            Shape(contours: [piece.contour], winding: .nonZero).union(empty).contours
        }
        guard !resolved.isEmpty else { return empty }
        return Shape(contours: resolved, winding: .nonZero).union(empty)
    }
}

extension Shape {
    /// A copy with `count` spikes around each outline, spaced evenly by its
    /// length: each pushes the outline out (away from the filled region) by
    /// up to `height` times a triangle wave raised to `sharpness`, so every
    /// tip is a sharp point and every valley sits back on the original
    /// outline, rounded when `sharpness` is above 1. Each spike's height (down
    /// to about two thirds) and where its tip leans are drawn from the seed
    /// by its index. Holes grow their spikes into the hole; open contours are
    /// kept as they are.
    public func spiked(_ count: Int, height: Double, sharpness: Double = 2, seed: Int = 0) -> Shape {
        let count = Swift.max(count, 1)
        let power = Swift.max(sharpness, 0.1)
        let outlines = contours.enumerated().map { c, contour -> Contour in
            guard let (spine, outward) = outwardLoop(contour) else { return contour }
            let period = spine.length / Double(count)
            var points: [Vector2] = []
            for i in 0 ..< count {
                let tall = Swift.max(height, 0) * (1 - 0.35 * GestureMark.hash(seed, 30 + c, i, 0))
                let lean = 0.5 + 0.125 * (2 * GestureMark.hash(seed, 30 + c, i, 1) - 1)
                let fractions = (0 ..< 12).map { lean * Double($0) / 12 } + (0 ..< 12).map { lean + (1 - lean) * Double($0) / 12 }
                for f in fractions {
                    let frame = spine.frame(at: (Double(i) + f) * period)
                    let wave = f <= lean ? f / lean : (1 - f) / (1 - lean)
                    points.append(frame.position + frame.normal * (outward * tall * pow(wave, power)))
                }
            }
            return Contour(points, closed: true)
        }
        return Shape(contours: outlines, winding: winding)
    }

    /// A copy whose outlines wobble: every point moved across the outline by
    /// up to `distance`, by a noise read at its position on the canvas with
    /// features about `scale` across, so the outline has no seam where it
    /// starts and two shapes that touch wobble alike where they touch. The
    /// outline is resampled every twelfth of `scale` first. Open contours are
    /// kept as they are.
    public func wobbled(by distance: Double, scale: Double, seed: Int = 0) -> Shape {
        let scale = Swift.max(scale, 1e-6)
        let fields = NoiseFields(seed: seed)
        let outlines = contours.map { contour -> Contour in
            guard let (spine, outward) = outwardLoop(contour) else { return contour }
            let spacing = Swift.max(scale / 12, 0.5)
            let count = Swift.max(Int((spine.length / spacing).rounded(.up)), 3)
            return Contour((0 ..< count).map { k in
                let frame = spine.frame(at: Double(k) * spine.length / Double(count))
                let n = Swift.min(Swift.max(2 * (fields.noise(frame.position.x / scale, frame.position.y / scale) - 0.5), -1), 1)
                return frame.position + frame.normal * (outward * distance * n)
            }, closed: true)
        }
        return Shape(contours: outlines, winding: winding)
    }

    /// A closed outline as a loop starting halfway along its longest edge (so
    /// the seam never sits on a corner), with the sign that turns its normal
    /// away from the filled region; nil for an open or degenerate outline.
    private func outwardLoop(_ contour: Contour) -> (GestureSpine, Double)? {
        let points = contour.points
        guard contour.isClosed, points.count >= 3 else { return nil }
        var longest = 0
        var best = -1.0
        for i in points.indices {
            let d = points[i].distanceSquared(to: points[(i + 1) % points.count])
            if d > best { best = d; longest = i }
        }
        let start = (longest + 1) % points.count
        let middle = (points[longest] + points[start]) / 2
        let loop = [middle] + (0 ..< points.count).map { points[(start + $0) % points.count] } + [middle]
        let spine = GestureSpine(points: loop, widths: Array(repeating: 0, count: loop.count))
        guard spine.isDrawable else { return nil }
        let probe = spine.frame(at: 0)
        let reach = Swift.max(sqrt(best) * 1e-3, 1e-6)
        let outward = contains(probe.position + probe.normal * reach) ? -1.0 : 1.0
        return (spine, outward)
    }
}

/// The path a gesture walks, resampled every `step` units of its own length
/// so a point added at the end changes nothing behind the last full step.
struct GestureSpine: Sendable {

    /// A point on the path with the direction there and the half width.
    struct Frame {
        let position: Vector2
        let tangent: Vector2
        let halfWidth: Double
        var normal: Vector2 { tangent.perpendicular }
    }

    /// The resampling step in canvas units.
    static let step = 2.0

    private let positions: [Vector2]
    private let fullWidths: [Double]
    private let distances: [Double]
    private let directions: [Vector2]
    /// The running integral of one over the width at each station, so a
    /// rhythm measured in widths keeps its place as the width changes.
    private let widthsSoFar: [Double]
    /// The path's length.
    let length: Double
    /// How far along nothing can still change when a point is added: the
    /// last full step, or the whole length when the path ends on a step.
    let settled: Double

    init(points: [Vector2], widths: [Double]) {
        var kept: [(Vector2, Double)] = []
        for (p, w) in zip(points, widths) where kept.last.map({ $0.0.distance(to: p) > 1e-9 }) ?? true {
            kept.append((p, w))
        }
        var positions: [Vector2] = []
        var fullWidths: [Double] = []
        var distances: [Double] = []
        let step = Self.step
        if let first = kept.first {
            positions.append(first.0)
            fullWidths.append(first.1)
            distances.append(0)
        }
        var walked = 0.0
        var next = 1
        for i in kept.indices.dropFirst() {
            let (a, wa) = kept[i - 1]
            let (b, wb) = kept[i]
            let span = a.distance(to: b)
            let end = walked + span
            while Double(next) * step <= end {
                let f = (Double(next) * step - walked) / span
                positions.append(a + (b - a) * f)
                fullWidths.append(wa + (wb - wa) * f)
                distances.append(Double(next) * step)
                next += 1
            }
            walked = end
        }
        var onStep = true
        if let last = kept.last, let lastDistance = distances.last, walked - lastDistance > 1e-9 {
            positions.append(last.0)
            fullWidths.append(last.1)
            distances.append(walked)
            onStep = false
        }
        var directions: [Vector2] = []
        for k in positions.indices.dropLast() {
            let d = positions[k + 1] - positions[k]
            directions.append(d.length > 1e-12 ? d / d.length : (directions.last ?? Vector2(1, 0)))
        }
        var integral: [Double] = positions.isEmpty ? [] : [0]
        for k in positions.indices.dropFirst() {
            let mean = Swift.max((fullWidths[k - 1] + fullWidths[k]) / 2, 1)
            integral.append(integral[k - 1] + (distances[k] - distances[k - 1]) / mean)
        }
        self.positions = positions
        self.fullWidths = fullWidths
        self.distances = distances
        self.directions = directions
        widthsSoFar = integral
        length = distances.last ?? 0
        settled = onStep || distances.count < 2 ? length : distances[distances.count - 2]
    }

    /// Whether the path has two distinct points.
    var isDrawable: Bool { positions.count >= 2 }

    /// The station segment `s` falls in: `s` in `(k step, (k + 1) step]`.
    private func segment(at s: Double) -> Int {
        let k = Int((s / Self.step).rounded(.up)) - 1
        return Swift.min(Swift.max(k, 0), positions.count - 2)
    }

    /// The point `s` along the path. Its direction turns from the previous
    /// step's to this step's across the step, which keeps it continuous and
    /// reading nothing ahead of the step it is in.
    func frame(at s: Double) -> Frame {
        guard positions.count >= 2 else {
            return Frame(position: positions.first ?? Vector2(0, 0), tangent: Vector2(1, 0),
                         halfWidth: (fullWidths.first ?? 0) / 2)
        }
        let s = Swift.min(Swift.max(s, 0), length)
        let k = segment(at: s)
        let span = distances[k + 1] - distances[k]
        let f = span > 0 ? (s - distances[k]) / span : 0
        let position = positions[k] + (positions[k + 1] - positions[k]) * f
        let width = fullWidths[k] + (fullWidths[k + 1] - fullWidths[k]) * f
        var tangent = directions[k]
        if k > 0 {
            let from = directions[k - 1]
            let turn = atan2(from.cross(tangent), from.dot(tangent))
            tangent = from.rotated(by: turn * f)
        }
        return Frame(position: position, tangent: tangent, halfWidth: width / 2)
    }

    /// How many widths long the path is up to `s`.
    func widthsAlong(_ s: Double) -> Double {
        guard positions.count >= 2 else { return 0 }
        let s = Swift.min(Swift.max(s, 0), length)
        let k = segment(at: s)
        let span = distances[k + 1] - distances[k]
        let f = span > 0 ? (s - distances[k]) / span : 0
        return widthsSoFar[k] + (widthsSoFar[k + 1] - widthsSoFar[k]) * f
    }

    /// The distance along at which the path is `widths` widths long, the
    /// inverse of `widthsAlong`; past the end it extends at the last width.
    func distance(atWidths widths: Double) -> Double {
        guard positions.count >= 2 else { return 0 }
        guard let total = widthsSoFar.last, widths < total else {
            let last = Swift.max(fullWidths.last ?? 1, 1)
            return length + (widths - (widthsSoFar.last ?? 0)) * last
        }
        guard widths > 0 else { return 0 }
        var lo = 0, hi = widthsSoFar.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if widthsSoFar[mid] <= widths { lo = mid } else { hi = mid }
        }
        let f = (widths - widthsSoFar[lo]) / (widthsSoFar[hi] - widthsSoFar[lo])
        return distances[lo] + (distances[hi] - distances[lo]) * f
    }
}
