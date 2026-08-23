import Foundation

// MARK: - The pattern

/// A crease pattern: a flat sheet with the folds drawn on it.
///
/// This is how a folded thing is written down. Every fold is a straight line on
/// the flat sheet, and every line is one of two kinds: a *mountain*, which
/// points up out of the sheet, and a *valley*, which points down into it. Draw
/// those lines and you have said everything about the finished form. A sheet
/// that is parted rather than folded is written the same way, with `cut` lines,
/// which is kirigami.
///
/// What comes out is ordinary geometry, so it strokes, hatches, and exports to
/// SVG like anything else. That matters here more than usual: a crease pattern
/// is a set of instructions for a machine. The fold lines go to a scoring
/// blade or a pen, and the cut lines go to a cutter.
///
/// Two laws decide whether a pattern can fold flat, and this type measures both
/// of them at every interior vertex:
///
/// - **Kawasaki's law.** Walk around a vertex and list the angles between one
///   fold and the next. Add the first, take away the second, add the third, and
///   so on all the way around. The sheet can fold flat only if that number
///   comes to zero at every vertex.
/// - **Maekawa's law.** Count the mountains and the valleys that meet at a
///   vertex. One count is always exactly two more than the other.
///
/// ```swift
/// let sheet = CreasePattern.miura(columns: 8, rows: 5).fitted(in: bounds)
/// strokeWeight(2)
/// stroke(.red)
/// for line in sheet.contours(.mountain) { drawPolyline(line.points) }
/// stroke(.blue)
/// for line in sheet.contours(.valley) { drawPolyline(line.points) }
/// ```
///
/// Which side is a mountain and which is a valley depends on which way up the
/// sheet is. Turn the paper over and every mountain becomes a valley, so
/// `inverted` is a whole answer rather than a different pattern.
public struct CreasePattern: Equatable, Sendable {

    /// What one line on the sheet asks for.
    public enum Assignment: Sendable, Hashable, CaseIterable {
        /// A fold that points up out of the sheet.
        case mountain
        /// A fold that points down into the sheet.
        case valley
        /// The edge of the sheet. Nothing is folded here.
        case boundary
        /// A line the sheet is parted along. This is the kirigami one.
        case cut

        /// Whether this line is folded, rather than an edge or a cut.
        public var isFold: Bool { self == .mountain || self == .valley }

        /// The same line with the sheet turned over. A mountain becomes a
        /// valley and a valley becomes a mountain; edges and cuts stay as they
        /// are.
        public var inverted: Assignment {
            switch self {
            case .mountain: return .valley
            case .valley: return .mountain
            default: return self
            }
        }
    }

    /// One straight line on the flat sheet.
    public struct Crease: Equatable, Sendable {
        /// Where the line starts.
        public var start: Vector2
        /// Where it ends.
        public var end: Vector2
        /// What the line asks the sheet to do.
        public var assignment: Assignment

        public init(from start: Vector2, to end: Vector2, _ assignment: Assignment) {
            self.start = start
            self.end = end
            self.assignment = assignment
        }

        /// How long the line is.
        public var length: Double { start.distance(to: end) }

        /// The point halfway along it.
        public var midpoint: Vector2 { (start + end) * 0.5 }

        /// The way it points, as a unit vector from `start` to `end`.
        public var direction: Vector2 { (end - start).normalized }

        /// The line as a two-point open contour, ready to draw or export.
        public var line: Contour { Contour([start, end], closed: false) }
    }

    /// Every line on the sheet, in the order the pattern was built.
    public var creases: [Crease]

    public init(_ creases: [Crease] = []) {
        self.creases = creases
    }
}

// MARK: - Reading a pattern

public extension CreasePattern {

    /// The box the sheet sits in. An empty pattern gives an empty box at the
    /// origin.
    var bounds: Rectangle {
        guard let first = creases.first else {
            return Rectangle(corner: .zero, width: 0, height: 0)
        }
        var minX = first.start.x, maxX = minX, minY = first.start.y, maxY = minY
        for crease in creases {
            for point in [crease.start, crease.end] {
                minX = Swift.min(minX, point.x); maxX = Swift.max(maxX, point.x)
                minY = Swift.min(minY, point.y); maxY = Swift.max(maxY, point.y)
            }
        }
        return Rectangle(corner: Vector2(minX, minY), width: maxX - minX, height: maxY - minY)
    }

    /// Every place two or more lines meet, plus the loose ends, each listed
    /// once. The order is the order the pattern names them, so it does not
    /// change from run to run.
    var vertices: [Vector2] { topology().points }

    /// The vertices with sheet all the way around them: no edge of the sheet
    /// and no cut arrives here. These are the ones the two laws are about.
    var interiorVertices: [Vector2] {
        let map = topology()
        return map.points.indices.filter { map.isInterior($0) }.map { map.points[$0] }
    }

    /// Only the lines of one kind.
    func creases(_ assignment: Assignment) -> [Crease] {
        creases.filter { $0.assignment == assignment }
    }

    /// The lines of one kind joined into as few strokes as possible, which is
    /// what a pen or a blade wants. Where several lines of the same kind meet
    /// at a vertex, the stroke carries on through the straightest one. A stroke
    /// that comes back to where it started is closed.
    func contours(_ assignment: Assignment) -> [Contour] {
        let map = topology()
        let wanted = creases.indices.filter { creases[$0].assignment == assignment }
        guard !wanted.isEmpty else { return [] }
        var unused = Set(wanted)

        /// The lines of the wanted kind at a vertex.
        func spokes(at vertex: Int) -> [Int] {
            map.spokes(at: vertex).map(\.crease).filter { creases[$0].assignment == assignment }
        }

        /// Walk away from `vertex` along `crease`, always taking the
        /// straightest turn, until the trail runs out.
        func walk(from vertex: Int, along crease: Int) -> [Int] {
            var trail: [Int] = []
            var here = vertex
            var step = crease
            while unused.contains(step) {
                unused.remove(step)
                trail.append(step)
                let arriving = map.other(of: step, than: here)
                let heading = map.direction(of: step, from: here)
                var best: Int?
                var straightest = -2.0
                for candidate in spokes(at: arriving) where unused.contains(candidate) {
                    let onward = map.direction(of: candidate, from: arriving)
                    let straightness = heading.dot(onward)
                    if straightness > straightest { straightest = straightness; best = candidate }
                }
                guard let onward = best else { break }
                here = arriving
                step = onward
            }
            return trail
        }

        /// Turn a run of lines into the points along it.
        func points(of trail: [Int], from vertex: Int) -> Contour {
            var here = vertex
            var walked = [map.points[here]]
            for step in trail {
                here = map.other(of: step, than: here)
                walked.append(map.points[here])
            }
            let closed = walked.count > 2 && here == vertex
            return Contour(closed ? Array(walked.dropLast()) : walked, closed: closed)
        }

        var strokes: [Contour] = []
        // Open runs first, started from an end or a junction so a stroke is
        // never cut in half.
        for vertex in map.points.indices where spokes(at: vertex).count != 2 {
            for start in spokes(at: vertex) where unused.contains(start) {
                let trail = walk(from: vertex, along: start)
                if !trail.isEmpty { strokes.append(points(of: trail, from: vertex)) }
            }
        }
        // Whatever is left is a loop, so any vertex on it will do as a start.
        for vertex in map.points.indices {
            for start in spokes(at: vertex) where unused.contains(start) {
                let trail = walk(from: vertex, along: start)
                if !trail.isEmpty { strokes.append(points(of: trail, from: vertex)) }
            }
        }
        return strokes
    }

    /// Kawasaki's number at a vertex: the angles between one fold and the next
    /// all the way around, added and taken away in turn.
    ///
    /// Zero means the sheet can fold flat here. The number is only meaningful
    /// where an even count of folds meets, because an odd count can never fold
    /// flat whatever the angles are.
    func kawasakiResidual(at vertex: Vector2) -> Double {
        let map = topology()
        guard let index = map.nearest(to: vertex) else { return 0 }
        return map.kawasakiResidual(at: index)
    }

    /// Maekawa's number at a vertex: the mountains meeting there, less the
    /// valleys. A vertex that folds flat always reads `2` or `-2`.
    func maekawaResidual(at vertex: Vector2) -> Int {
        let map = topology()
        guard let index = map.nearest(to: vertex) else { return 0 }
        return map.maekawaResidual(at: index)
    }

    /// Whether every interior vertex obeys both laws, which is what a flat fold
    /// asks of the pattern. A pattern with no folds at all, such as a plain
    /// kirigami cut sheet, reads `true`, because it asks for nothing.
    ///
    /// The two laws are necessary rather than sufficient: they are about one
    /// vertex at a time, and they cannot see a sheet that would have to pass
    /// through itself. A pattern that fails them certainly cannot fold flat.
    var isFlatFoldable: Bool {
        let map = topology()
        let span = Swift.max(bounds.width, bounds.height)
        let tolerance = Swift.max(1e-9, span * 1e-9)
        for index in map.points.indices where map.isInterior(index) {
            let folds = map.spokes(at: index).filter { creases[$0.crease].assignment.isFold }
            guard !folds.isEmpty else { continue }
            if folds.count % 2 != 0 { return false }
            if abs(map.kawasakiResidual(at: index)) > tolerance { return false }
            if abs(map.maekawaResidual(at: index)) != 2 { return false }
        }
        return true
    }

    /// The same pattern with the sheet turned over: every mountain is now a
    /// valley and every valley a mountain.
    var inverted: CreasePattern {
        CreasePattern(creases.map {
            Crease(from: $0.start, to: $0.end, $0.assignment.inverted)
        })
    }

    /// The same pattern with every point moved. Moving, turning, and scaling by
    /// the same amount in both directions all keep the angles, so they keep the
    /// two laws too.
    func mapPoints(_ transform: (Vector2) -> Vector2) -> CreasePattern {
        CreasePattern(creases.map {
            Crease(from: transform($0.start), to: transform($0.end), $0.assignment)
        })
    }

    /// The pattern scaled by the same amount in both directions and centered to
    /// fill `frame`. This is the way to put a sheet on the canvas: the points
    /// are moved, so a stroke does not get fatter with them.
    func fitted(in frame: Rectangle) -> CreasePattern {
        let box = bounds
        let factor = Swift.min(box.width > 0 ? frame.width / box.width : .infinity,
                               box.height > 0 ? frame.height / box.height : .infinity)
        let scale = factor.isFinite ? factor : 1
        let from = box.center
        let to = frame.center
        return mapPoints { Vector2(to.x + ($0.x - from.x) * scale, to.y + ($0.y - from.y) * scale) }
    }
}

// MARK: - Who meets whom

extension CreasePattern {

    /// Which lines meet at which point. Built on demand from the lines
    /// themselves, so a pattern stays a plain list.
    struct Topology {
        struct Spoke { var crease: Int; var away: Vector2 }

        var points: [Vector2] = []
        var spokesByPoint: [[Spoke]] = []
        var endsByCrease: [(Int, Int)] = []
        var interior: [Bool] = []
        var tolerance: Double = 1e-9

        func spokes(at vertex: Int) -> [Spoke] { spokesByPoint[vertex] }

        func isInterior(_ vertex: Int) -> Bool { interior[vertex] }

        /// The far end of `crease`, given one of its ends.
        func other(of crease: Int, than vertex: Int) -> Int {
            let ends = endsByCrease[crease]
            return ends.0 == vertex ? ends.1 : ends.0
        }

        /// The way `crease` points when you leave `vertex` along it.
        func direction(of crease: Int, from vertex: Int) -> Vector2 {
            for spoke in spokesByPoint[vertex] where spoke.crease == crease { return spoke.away }
            return .zero
        }

        func nearest(to point: Vector2) -> Int? {
            var best: Int?
            var closest = tolerance * tolerance
            for (index, candidate) in points.enumerated() {
                let distance = candidate.distanceSquared(to: point)
                if distance <= closest { closest = distance; best = index }
            }
            return best
        }

        func kawasakiResidual(at vertex: Int) -> Double {
            let angles = spokesByPoint[vertex].map(\.away.angle).sorted()
            guard angles.count > 1 else { return 0 }
            var residual = 0.0
            for index in angles.indices {
                let next = angles[(index + 1) % angles.count]
                var gap = next - angles[index]
                if gap <= 0 { gap += 2 * .pi }
                residual += index % 2 == 0 ? gap : -gap
            }
            return residual
        }

        func maekawaResidual(at vertex: Int) -> Int { mountains[vertex] - valleys[vertex] }

        var mountains: [Int] = []
        var valleys: [Int] = []
    }

    /// Work out which lines meet at which point.
    ///
    /// Points are matched within a tolerance that follows the size of the
    /// pattern, so a sheet fitted to the canvas and one built in unit steps
    /// both come out with the same vertices.
    func topology() -> Topology {
        var map = Topology()
        let box = bounds
        let span = Swift.max(box.width, box.height)
        let tolerance = Swift.max(1e-9, span * 1e-9)
        map.tolerance = tolerance

        // A lattice of cells one tolerance across, so a point is matched
        // against its own neighborhood rather than against everything.
        struct Cell: Hashable { var x: Int; var y: Int }
        var cells: [Cell: [Int]] = [:]
        func index(of point: Vector2) -> Int {
            let cx = Int((point.x / tolerance).rounded(.down))
            let cy = Int((point.y / tolerance).rounded(.down))
            for dx in -1 ... 1 {
                for dy in -1 ... 1 {
                    for candidate in cells[Cell(x: cx + dx, y: cy + dy), default: []]
                    where map.points[candidate].distanceSquared(to: point) <= tolerance * tolerance {
                        return candidate
                    }
                }
            }
            map.points.append(point)
            map.spokesByPoint.append([])
            map.mountains.append(0)
            map.valleys.append(0)
            map.interior.append(true)
            cells[Cell(x: cx, y: cy), default: []].append(map.points.count - 1)
            return map.points.count - 1
        }

        for (number, crease) in creases.enumerated() {
            let a = index(of: crease.start)
            let b = index(of: crease.end)
            map.endsByCrease.append((a, b))
            guard a != b else { continue }
            map.spokesByPoint[a].append(.init(crease: number, away: (crease.end - crease.start).normalized))
            map.spokesByPoint[b].append(.init(crease: number, away: (crease.start - crease.end).normalized))
            switch crease.assignment {
            case .mountain:
                map.mountains[a] += 1; map.mountains[b] += 1
            case .valley:
                map.valleys[a] += 1; map.valleys[b] += 1
            case .boundary, .cut:
                // The sheet stops here, so neither end is surrounded by paper.
                map.interior[a] = false; map.interior[b] = false
            }
        }
        return map
    }
}

// MARK: - The Miura fold

/// The Miura fold: a sheet folded into a field of parallelograms that opens and
/// closes in one movement.
///
/// It is the most useful fold there is. Pull two opposite corners and the whole
/// sheet opens at once, in both directions together; push them back and it
/// closes into a flat packet. There is no order of operations to remember,
/// which is why it is used for maps, for solar arrays that travel folded, and
/// for stents.
///
/// Two things make it behave that way. Every panel stays flat while the sheet
/// moves, so stiff material folds as happily as paper. And it gets *narrower*
/// as it gets shorter, which is the opposite of what most things do: squeeze a
/// rubber band and it bulges. A material that thins as it shortens is called
/// auxetic, and the sheet's two Poisson numbers, one for each direction,
/// multiply to exactly one.
///
/// ```swift
/// var sheet = MiuraFold(columns: 8, rows: 5, angle: .pi / 3)
/// drawCreases(sheet.pattern.fitted(in: bounds), .mountain)
///
/// sheet.fold = 0.5 * (1 - cos(time))     // open and close it
/// for panel in sheet.facets { ... }      // the folded form, in three dimensions
/// ```
///
/// Five numbers describe one:
///
/// - `columns` and `rows`: how many parallelograms across and down.
/// - `major`: the length of a straight fold, which runs across the sheet.
/// - `minor`: the length of one step of a zigzag fold, which runs down it.
/// - `angle`: the sharp corner of the parallelogram. A right angle gives plain
///   pleats with no zigzag and no auxetic behavior; smaller angles lean the
///   zigzag over more.
/// - `fold`: how far the sheet is folded, from `0` (the flat sheet) to `1` (the
///   flat packet).
///
/// `pattern` is the flat sheet with its creases, and it does not depend on
/// `fold`. `points` and `facets` are the folded form in three dimensions. The
/// two agree at `fold` of `0`.
public struct MiuraFold: Equatable, Sendable {

    /// How many parallelograms across the sheet.
    public var columns: Int

    /// How many parallelograms down it.
    public var rows: Int

    /// The length of one straight fold, the one that runs across the sheet.
    public var major: Double

    /// The length of one step of a zigzag fold, the one that runs down it.
    public var minor: Double

    /// The sharp corner of the parallelogram, in radians.
    public var angle: Double

    /// How far the sheet is folded: `0` is flat, `1` is a flat packet.
    public var fold: Double

    public init(columns: Int = 6, rows: Int = 4,
                major: Double = 1, minor: Double = 1,
                angle: Double = .pi / 3, fold: Double = 0) {
        self.columns = Swift.max(1, columns)
        self.rows = Swift.max(1, rows)
        self.major = major
        self.minor = minor
        self.angle = Swift.min(Swift.max(angle, 1e-6), .pi / 2)
        self.fold = Swift.min(Swift.max(fold, 0), 1)
    }
}

public extension MiuraFold {

    /// How high the folded sheet stands.
    var height: Double { major * sin(fold * .pi / 2) * sin(angle) }

    /// How far one parallelogram reaches across the sheet once it is folded.
    /// It shortens from `major` to `major * cos(angle)` as the sheet closes.
    var cellWidth: Double {
        let drop = sin(fold * .pi / 2) * sin(angle)
        return major * (1 - drop * drop).squareRoot()
    }

    /// How far one parallelogram steps sideways as it goes down the sheet. This
    /// is the zigzag, and it grows from `minor * cos(angle)` to `minor` as the
    /// sheet closes.
    var cellShift: Double {
        guard cellWidth > 0 else { return minor }
        return Swift.min(minor, major * minor * cos(angle) / cellWidth)
    }

    /// How far one parallelogram reaches down the sheet once it is folded. It
    /// shortens to nothing, which is the sheet closing into its packet.
    var cellLength: Double {
        let shift = cellShift
        return (Swift.max(0, minor * minor - shift * shift)).squareRoot()
    }

    /// The folded sheet's width, length, and height.
    var size: Vector3 {
        Vector3(Double(columns) * cellWidth + cellShift, Double(rows) * cellLength, height)
    }

    /// Where one vertex of the flat sheet is, before anything is folded.
    func flatPoint(column: Int, row: Int) -> Vector2 {
        Vector2(Double(column) * major + (row % 2 == 1 ? minor * cos(angle) : 0),
                Double(row) * minor * sin(angle))
    }

    /// Where one vertex of the folded sheet is.
    ///
    /// The whole folded form is this one line: a lattice that steps `cellWidth`
    /// across and `cellLength` down, with every second row pushed sideways by
    /// `cellShift` and every second column lifted to `height`.
    func point(column: Int, row: Int) -> Vector3 {
        Vector3(Double(column) * cellWidth + (row % 2 == 1 ? cellShift : 0),
                Double(row) * cellLength,
                column % 2 == 1 ? height : 0)
    }

    /// The folded sheet's vertices, a row of `columns + 1` points at a time.
    var points: [[Vector3]] {
        (0 ... rows).map { row in (0 ... columns).map { point(column: $0, row: row) } }
    }

    /// The folded sheet's panels, four corners each, wound the same way round.
    /// Every one stays a flat parallelogram whatever `fold` says, which is the
    /// property the whole fold rests on.
    var facets: [[Vector3]] {
        var panels: [[Vector3]] = []
        panels.reserveCapacity(columns * rows)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                panels.append([point(column: column, row: row),
                               point(column: column + 1, row: row),
                               point(column: column + 1, row: row + 1),
                               point(column: column, row: row + 1)])
            }
        }
        return panels
    }

    /// How much narrower the sheet gets as it gets longer, which is a negative
    /// number: the sheet grows in both directions at once.
    ///
    /// This is the width against the length. The length against the width is
    /// `1 / poissonRatio`, so the two multiply to one. A right `angle` gives
    /// plain pleats that only move one way, and no finite number describes
    /// that.
    var poissonRatio: Double {
        let shift = cellShift
        guard shift > 0 else { return -.infinity }
        let length = cellLength
        return -(length * length) / (shift * shift)
    }

    /// The flat sheet with its creases drawn on it.
    ///
    /// The straight folds run across the sheet and change kind at every step
    /// along their length. The zigzag folds run down it, and each one is a
    /// mountain or a valley for its whole length, taking turns as you go
    /// across. That difference is what a Miura pattern looks like on the page.
    var pattern: CreasePattern {
        var creases: [CreasePattern.Crease] = []
        creases.reserveCapacity(2 * columns * rows + columns + rows)

        // The straight folds, across the sheet.
        for row in 0 ... rows {
            for column in 0 ..< columns {
                let edge = row == 0 || row == rows
                let kind: CreasePattern.Assignment = edge
                    ? .boundary
                    : ((column + row) % 2 == 0 ? .mountain : .valley)
                creases.append(.init(from: flatPoint(column: column, row: row),
                                     to: flatPoint(column: column + 1, row: row), kind))
            }
        }
        // The zigzag folds, down the sheet.
        for column in 0 ... columns {
            for row in 0 ..< rows {
                let edge = column == 0 || column == columns
                let kind: CreasePattern.Assignment = edge
                    ? .boundary
                    : (column % 2 == 1 ? .mountain : .valley)
                creases.append(.init(from: flatPoint(column: column, row: row),
                                     to: flatPoint(column: column, row: row + 1), kind))
            }
        }
        return CreasePattern(creases)
    }
}

// MARK: - Rotating squares

/// The rotating-squares cut: a sheet cut into squares joined at their corners,
/// which opens like a lattice when it is pulled.
///
/// Kirigami is origami that is allowed to cut. This is its plainest useful
/// pattern. Cut a grid of squares, leaving a thread of material at every
/// corner, and the squares turn one way and the next as the sheet is pulled.
/// Square holes open between them. Because every square turns and none of them
/// stretches, the sheet grows the same amount in both directions at once, so
/// its Poisson number is exactly `-1`, the extreme case for a flat material.
///
/// ```swift
/// var lattice = RotatingSquares(columns: 6, rows: 6, side: 90)
/// lattice.opening = 0.5 * (1 - cos(time))
/// for square in lattice.squares { drawPolygon(square.points) }
///
/// // and the sheet it is cut from, for the cutting machine:
/// drawCreases(lattice.pattern, .cut)
/// ```
///
/// The mechanism is exact for a corner that is a point. A real sheet needs the
/// `ligament` to hold together, and the wider it is the further the real
/// movement drifts from the ideal one.
public struct RotatingSquares: Equatable, Sendable {

    /// How many squares across.
    public var columns: Int

    /// How many squares down.
    public var rows: Int

    /// The side of one square, which never changes.
    public var side: Double

    /// How much material is left at each end of a cut, so the sheet stays in
    /// one piece.
    public var ligament: Double

    /// How far the lattice is pulled open, from `0` (a closed sheet) to `1`
    /// (squares turned a full 45 degrees, where the holes are as big as the
    /// squares).
    public var opening: Double

    public init(columns: Int = 6, rows: Int = 6, side: Double = 1,
                ligament: Double = 0, opening: Double = 0) {
        self.columns = Swift.max(1, columns)
        self.rows = Swift.max(1, rows)
        self.side = side
        self.ligament = Swift.max(0, ligament)
        self.opening = Swift.min(Swift.max(opening, 0), 1)
    }
}

public extension RotatingSquares {

    /// How far each square has turned, in radians.
    var angle: Double { opening * .pi / 4 }

    /// The distance between one square's middle and the next one's. It grows
    /// from `side` to `side * sqrt(2)` as the lattice opens, by the same amount
    /// in both directions, which is where the Poisson number of `-1` comes
    /// from.
    var spacing: Double { side * (cos(angle) + sin(angle)) }

    /// How much narrower the sheet gets as it is pulled longer: exactly `-1`,
    /// because it gets wider instead, by the same amount.
    var poissonRatio: Double { -1 }

    /// Where the middle of one square is.
    func center(column: Int, row: Int) -> Vector2 {
        Vector2((Double(column) + 0.5) * spacing, (Double(row) + 0.5) * spacing)
    }

    /// One square, turned to where the opening puts it.
    func square(column: Int, row: Int) -> Contour {
        let turn = (column + row) % 2 == 0 ? -angle : angle
        let middle = center(column: column, row: row)
        let half = side / 2
        let corners = [Vector2(-half, -half), Vector2(half, -half),
                       Vector2(half, half), Vector2(-half, half)]
        return Contour(corners.map {
            Vector2(middle.x + $0.x * cos(turn) - $0.y * sin(turn),
                    middle.y + $0.x * sin(turn) + $0.y * cos(turn))
        }, closed: true)
    }

    /// Every square, row by row.
    var squares: [Contour] {
        (0 ..< rows).flatMap { row in (0 ..< columns).map { square(column: $0, row: row) } }
    }

    /// The box that holds every square.
    var bounds: Rectangle {
        let points = squares.flatMap(\.points)
        guard let first = points.first else { return Rectangle(corner: .zero, width: 0, height: 0) }
        var minX = first.x, maxX = minX, minY = first.y, maxY = minY
        for point in points {
            minX = Swift.min(minX, point.x); maxX = Swift.max(maxX, point.x)
            minY = Swift.min(minY, point.y); maxY = Swift.max(maxY, point.y)
        }
        return Rectangle(corner: Vector2(minX, minY), width: maxX - minX, height: maxY - minY)
    }

    /// The closed sheet with the cuts drawn on it, ready for a cutting machine.
    /// The `opening` is ignored here: a sheet is cut flat, and only then
    /// pulled.
    var pattern: CreasePattern {
        var creases: [CreasePattern.Crease] = []
        let width = Double(columns) * side
        let height = Double(rows) * side
        let corners = [Vector2(0, 0), Vector2(width, 0), Vector2(width, height), Vector2(0, height)]
        for index in corners.indices {
            creases.append(.init(from: corners[index],
                                 to: corners[(index + 1) % corners.count], .boundary))
        }
        guard ligament * 2 < side else { return CreasePattern(creases) }

        for column in 1 ..< Swift.max(1, columns) {
            for row in 0 ..< rows {
                let x = Double(column) * side
                creases.append(.init(from: Vector2(x, Double(row) * side + ligament),
                                     to: Vector2(x, Double(row + 1) * side - ligament), .cut))
            }
        }
        for row in 1 ..< Swift.max(1, rows) {
            for column in 0 ..< columns {
                let y = Double(row) * side
                creases.append(.init(from: Vector2(Double(column) * side + ligament, y),
                                     to: Vector2(Double(column + 1) * side - ligament, y), .cut))
            }
        }
        return CreasePattern(creases)
    }
}

// MARK: - Sugar

public extension CreasePattern {

    /// A Miura fold's flat crease pattern, in units of one parallelogram.
    /// Call `fitted(in:)` to put it on the canvas.
    static func miura(columns: Int = 6, rows: Int = 4,
                      major: Double = 1, minor: Double = 1,
                      angle: Double = .pi / 3) -> CreasePattern {
        MiuraFold(columns: columns, rows: rows, major: major, minor: minor, angle: angle).pattern
    }

    /// A rotating-squares cut sheet, in units of one square.
    static func rotatingSquares(columns: Int = 6, rows: Int = 6,
                                side: Double = 1, ligament: Double = 0) -> CreasePattern {
        RotatingSquares(columns: columns, rows: rows, side: side, ligament: ligament).pattern
    }
}

public extension Sketch {

    /// Stroke the lines of one kind with the current `stroke`, joined into as
    /// few strokes as the pattern allows.
    ///
    /// ```swift
    /// stroke(.red);  drawCreases(sheet, .mountain)
    /// stroke(.blue); drawCreases(sheet, .valley)
    /// ```
    func drawCreases(_ pattern: CreasePattern, _ assignment: CreasePattern.Assignment) {
        for line in pattern.contours(assignment) {
            drawPolyline(line.points, closed: line.isClosed)
        }
    }
}
