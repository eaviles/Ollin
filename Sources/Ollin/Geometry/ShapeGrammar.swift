import Foundation

/// A shape grammar: a start shape, and a handful of rules that each say what
/// one labeled shape turns into. Apply the rules again and again, and the
/// design grows out of them.
///
/// A rule reads as one sentence: *a piece labeled `cell` becomes two pieces,
/// cut apart by a straight line*. Nothing in that sentence says where the line
/// goes, so the rule stands for every design it could make rather than for one
/// drawing. That is the whole idea. You write the rules, and the run writes the
/// picture.
///
/// Every piece is a closed polygon with a label. The label decides which rule
/// may rewrite it, and a label that no rule names is finished. A run sweeps the
/// design once per generation: it offers each piece to the rules that name its
/// label, picks one of them by weight, and puts the pieces that come back in
/// its place. A piece smaller than a rule's `minimumArea` is left alone, which
/// is what brings a run to a stop.
///
/// The built-in rules are the moves the classic grammars are written from:
///
/// - ``Rule/cut(_:into:balance:sides:avoidingCorners:minimumArea:weight:)``
///   draws one straight line between two edges of the piece. This is the
///   ice-ray move, the one behind the lattice window frames whose bars look
///   like cracks in river ice.
/// - ``Rule/split(_:along:at:into:minimumArea:weight:)`` cuts straight across
///   at fractions of the piece's width or height, which is how a wall becomes
///   floors and a floor becomes windows.
/// - ``Rule/inset(_:by:into:border:minimumArea:weight:)`` pulls the outline
///   inward by the same distance all the way round, which is how a cell becomes
///   a bar of a lattice.
/// - ``Rule/nested(_:scale:turn:into:keeping:minimumArea:weight:)`` puts a
///   smaller copy of the piece inside itself.
/// - ``Rule/custom(_:weight:minimumArea:_:)`` does anything else.
///
/// The built-in rules expect a **convex** piece, and they hand back convex
/// pieces, so a run that starts convex stays that way. A `custom` rule may
/// return whatever it likes.
///
/// The product is geometry, ready for stroking, filling, hatching, the shape
/// booleans, and a pen plotter. A run is driven by a seeded generator, so the
/// same seed always draws the same design.
///
/// ```swift
/// // In setup():
/// let frame = Rectangle(center: center, width: 900, height: 900)
/// pieces = ShapeGrammar.iceRay(in: frame, minimumArea: 9_000)
///     .run(generations: 9, seed: 7)
///
/// // In draw():
/// noFill(); stroke(.white); strokeWeight(2)
/// for piece in pieces { drawPolyline(piece.corners, closed: true) }
/// ```
public struct ShapeGrammar: Sendable {

    /// The design the run begins with.
    public var start: [Piece]
    /// The rules, in the order they were given. Order decides nothing except
    /// how a tie between equal weights falls.
    public var rules: [Rule]
    /// A run stops rewriting once the design holds this many pieces, give or
    /// take the pieces one last rule hands back. It is a backstop against a
    /// grammar that never settles, not a target.
    public var maximumPieces: Int

    public init(start: [Piece], rules: [Rule], maximumPieces: Int = 20_000) {
        self.start = start
        self.rules = rules
        self.maximumPieces = maximumPieces
    }

    public init(start: Piece, rules: [Rule], maximumPieces: Int = 20_000) {
        self.init(start: [start], rules: rules, maximumPieces: maximumPieces)
    }

    /// Which way a `split` rule cuts.
    public enum Axis: Sendable, Equatable {
        /// Cut across the piece's width, so the parts sit side by side.
        case x
        /// Cut down the piece's height, so the parts stack.
        case y
        /// Whichever of the two the piece's upright box is longer in. This is
        /// the one that keeps subdivided parts from growing thin.
        case longest
        /// The shorter of the two.
        case shortest
    }

    // MARK: - A piece of the design

    /// One labeled shape in the design.
    public struct Piece: Sendable, Equatable {
        /// The word the rules match on.
        public var label: String
        /// The outline, always closed.
        public var contour: Contour
        /// How many rules deep the piece is. The start pieces are at 0.
        public var depth: Int

        public init(_ label: String, _ contour: Contour, depth: Int = 0) {
            self.label = label
            self.contour = Contour(contour.points, closed: true)
            self.depth = depth
        }

        public init(_ label: String, _ corners: [Vector2], depth: Int = 0) {
            self.init(label, Contour(corners, closed: true), depth: depth)
        }

        public init(_ label: String, _ rectangle: Rectangle, depth: Int = 0) {
            self.init(label, [rectangle.topLeft, rectangle.topRight,
                              rectangle.bottomRight, rectangle.bottomLeft], depth: depth)
        }

        /// The corners of the outline, in order.
        public var corners: [Vector2] { contour.points }
        /// The area the outline encloses. Never negative.
        public var area: Double { abs(polygonSignedArea(contour.points)) }
        /// The point the area balances on.
        public var centroid: Vector2 { polygonCentroid(contour.points) }
        /// The upright box the outline fits in.
        public var bounds: Rectangle { polygonBounds(contour.points) }
    }

    // MARK: - A rule

    /// One rule: a label on the left, and what that label turns into on the
    /// right. Build one with ``Rule/cut(_:into:balance:sides:avoidingCorners:minimumArea:weight:)``
    /// and its siblings.
    public struct Rule: Sendable {
        /// The label this rule rewrites.
        public var label: String
        /// How often this rule is picked among the rules that share its label.
        /// A rule of weight 3 is picked three times as often as one of weight 1.
        /// A rule of weight 0 is only reached once every other rule on the
        /// label has refused the piece, which is how a fallback is written.
        public var weight: Double
        /// A piece of less area than this is left alone by this rule. It is
        /// what the classic grammars use to decide when a design is finished.
        public var minimumArea: Double

        let body: @Sendable (Piece, inout SplitMix64) -> [Piece]?

        init(label: String, weight: Double, minimumArea: Double,
             body: @escaping @Sendable (Piece, inout SplitMix64) -> [Piece]?) {
            self.label = label
            self.weight = max(weight, 0)
            self.minimumArea = minimumArea
            self.body = body
        }
    }

    // MARK: - Running it

    /// The design after `generations` sweeps, driven by `source`.
    public func run(generations: Int, source: inout SplitMix64) -> [Piece] {
        var pieces = start
        for _ in 0 ..< max(generations, 0) {
            pieces = step(pieces, source: &source)
        }
        return pieces
    }

    /// The design after `generations` sweeps, driven by any generator. The
    /// grammar draws one number from `rng` and runs off that, so a seeded
    /// generator gives a design that reproduces.
    public func run<R: RandomNumberGenerator>(generations: Int, using rng: inout R) -> [Piece] {
        var source = SplitMix64(seed: rng.next())
        return run(generations: generations, source: &source)
    }

    /// The design after `generations` sweeps, from a seed. The same seed always
    /// gives the same design.
    public func run(generations: Int, seed: Int = 0) -> [Piece] {
        var source = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        return run(generations: generations, source: &source)
    }

    /// One sweep: every piece offered to its rules once. Hold the pieces and
    /// the source yourself to grow a design a generation per frame.
    public func step(_ pieces: [Piece], source: inout SplitMix64) -> [Piece] {
        guard !rules.isEmpty else { return pieces }
        var grown: [Piece] = []
        grown.reserveCapacity(pieces.count * 2)
        for (index, piece) in pieces.enumerated() {
            let waiting = pieces.count - index - 1
            guard grown.count + waiting < maximumPieces,
                  let children = rewrite(piece, source: &source) else {
                grown.append(piece)
                continue
            }
            grown.append(contentsOf: children)
        }
        return grown
    }

    /// The pieces one rule application leaves in place of `piece`, or `nil`
    /// when no rule takes it.
    private func rewrite(_ piece: Piece, source: inout SplitMix64) -> [Piece]? {
        let area = piece.area
        var candidates = rules.indices.filter {
            rules[$0].label == piece.label && area >= rules[$0].minimumArea
        }
        while !candidates.isEmpty {
            let slot = pick(candidates, source: &source)
            let rule = rules[candidates[slot]]
            candidates.remove(at: slot)
            if let children = rule.body(piece, &source) {
                return children.map { Piece($0.label, $0.contour, depth: piece.depth + 1) }
            }
        }
        return nil
    }

    /// A slot in `candidates`, drawn in proportion to the rules' weights.
    private func pick(_ candidates: [Int], source: inout SplitMix64) -> Int {
        guard candidates.count > 1 else { return 0 }
        let total = candidates.reduce(0.0) { $0 + rules[$1].weight }
        guard total > 0 else { return 0 }
        var roll = Double.random(in: 0 ..< total, using: &source)
        for (slot, index) in candidates.enumerated() {
            roll -= rules[index].weight
            if roll < 0 { return slot }
        }
        return candidates.count - 1
    }
}

// MARK: - The rules

public extension ShapeGrammar.Rule {

    /// The ice-ray move: cut the piece in two along one straight line drawn
    /// between two of its edges.
    ///
    /// The line never starts at a corner, so the two parts always carry
    /// `n + 4` corners between them, where `n` is what the piece had. That one
    /// fact is the whole rule table of the classic lattice grammar. Hold
    /// `sides` at `3...5` and a triangle can only become a triangle and a
    /// quadrilateral; a quadrilateral can only become a triangle and a
    /// pentagon, or two quadrilaterals; and a pentagon can only become a
    /// quadrilateral and another pentagon.
    ///
    /// - Parameters:
    ///   - label: the pieces this rule cuts.
    ///   - into: the labels the two parts take.
    ///   - balance: how uneven the two parts may be, as a fraction of the
    ///     piece's area. At 0 they take exactly half each. At 0.2 one of them
    ///     may take up to 60 percent. The cut lands inside that band or the
    ///     rule does not apply.
    ///   - sides: how many corners a part may have. The default `3...5` is the
    ///     lattice family.
    ///   - avoidingCorners: how far from either end of an edge the line must
    ///     land, as a fraction of that edge.
    ///   - tries: how many cuts to weigh up before keeping the shortest of
    ///     them. This is what keeps the parts compact: a balanced cut down the
    ///     length of a piece leaves two pieces just as long, and the shortest
    ///     stick that reaches always goes across. At 1 the rule keeps the first
    ///     cut that fits, and the parts grow long and thin.
    ///   - minimumArea: a piece smaller than this is left alone.
    ///   - weight: how often this rule is picked against others on the label.
    static func cut(_ label: String, into parts: (String, String),
                    balance: Double = 0.2, sides: ClosedRange<Int> = 3 ... 5,
                    avoidingCorners: Double = 0.2, tries: Int = 4,
                    minimumArea: Double = 0, weight: Double = 1) -> Self {
        let low = min(max(avoidingCorners, 0), 0.49)
        let high = 1 - low
        let spread = min(max(balance, 0), 1)
        return Self(label: label, weight: weight, minimumArea: minimumArea) { piece, source in
            let points = piece.contour.points
            let n = points.count
            guard n >= 3 else { return nil }
            let whole = polygonSignedArea(points)
            let orientation: Double = whole >= 0 ? 1 : -1
            let area = abs(whole)
            guard area > 1e-12 else { return nil }

            // Every ordered pair of edges whose two parts are allowed shapes.
            var pairs: [(Int, Int)] = []
            for i in 0 ..< n {
                for step in 1 ..< n {
                    let j = (i + step) % n
                    guard sides.contains(step + 2), sides.contains(n - step + 2) else { continue }
                    pairs.append((i, j))
                }
            }
            guard !pairs.isEmpty else { return nil }
            pairs.shuffle(using: &source)
            var best: (length: Double, parts: ([Vector2], [Vector2]))?
            var weighed = 0

            for (i, j) in pairs {
                if weighed >= max(tries, 1) { break }
                let s = Double.random(in: low ... high, using: &source)
                // The first part's area moves in a straight line as the far end
                // of the cut slides along its edge, so the reach of this pair
                // is its two ends and the balance solves in one step.
                let atLow = orientation * polygonSignedArea(
                    cutParts(points, from: i, at: s, to: j, at: low).0)
                let atHigh = orientation * polygonSignedArea(
                    cutParts(points, from: i, at: s, to: j, at: high).0)
                guard atHigh - atLow > 1e-12 else { continue }
                let leanest = max(atLow, (0.5 - spread / 2) * area)
                let fullest = min(atHigh, (0.5 + spread / 2) * area)
                guard leanest <= fullest else { continue }
                let target = leanest < fullest
                    ? Double.random(in: leanest ... fullest, using: &source)
                    : leanest
                let t = low + (target - atLow) / (atHigh - atLow) * (high - low)
                let (first, second) = cutParts(points, from: i, at: s, to: j, at: t)
                guard first.count >= 3, second.count >= 3 else { continue }
                weighed += 1
                let length = first[0].distance(to: first[first.count - 1])
                if let kept = best, length >= kept.length { continue }
                best = (length, (first, second))
            }
            guard let kept = best else { return nil }
            return [ShapeGrammar.Piece(parts.0, kept.parts.0),
                    ShapeGrammar.Piece(parts.1, kept.parts.1)]
        }
    }

    /// Cut straight across the piece at fractions of its upright box.
    ///
    /// `at: [0.3]` makes two parts, `at: [0.25, 0.5, 0.75]` makes four. The
    /// labels in `into` are used in turn and start over when they run out, so
    /// two labels stripe a piece.
    static func split(_ label: String, along axis: ShapeGrammar.Axis,
                      at fractions: [Double], into labels: [String],
                      minimumArea: Double = 0, weight: Double = 1) -> Self {
        let cuts = fractions.map { min(max($0, 0), 1) }.sorted()
        return Self(label: label, weight: weight, minimumArea: minimumArea) { piece, _ in
            guard !labels.isEmpty else { return nil }
            let points = piece.contour.points
            guard points.count >= 3 else { return nil }
            let direction = axis.direction(for: piece.bounds)
            let bands = splitPolygon(points, along: direction, at: cuts)
            guard bands.count > 1 else { return nil }
            return bands.enumerated().map { slot, band in
                ShapeGrammar.Piece(labels[slot % labels.count], band)
            }
        }
    }

    /// Pull the outline inward by the same distance all the way round.
    ///
    /// The middle comes back under `into`. Give `border` a label and the ring
    /// left over comes back too, as one piece per edge of the outline, which is
    /// how a cell of a lattice becomes its bars.
    static func inset(_ label: String, by distance: Double, into inner: String,
                      border: String? = nil,
                      minimumArea: Double = 0, weight: Double = 1) -> Self {
        Self(label: label, weight: weight, minimumArea: minimumArea) { piece, _ in
            let points = piece.contour.points
            guard distance > 0, let pulled = insetPolygon(points, by: distance) else { return nil }
            var made = [ShapeGrammar.Piece(inner, pulled)]
            if let border {
                for k in points.indices {
                    let next = (k + 1) % points.count
                    made.append(ShapeGrammar.Piece(border, [points[k], points[next],
                                                            pulled[next], pulled[k]]))
                }
            }
            return made
        }
    }

    /// Put a smaller copy of the piece inside itself, turned by `turn` radians
    /// about the middle.
    ///
    /// At a `scale` of `1 / sqrt(2)` and a quarter of a right angle, the copy
    /// meets the middle of every edge of a square, which is the oldest figure
    /// in this family. Give `keeping` a label to leave the piece itself in the
    /// design under that name; leave it out and only the copy stays.
    static func nested(_ label: String, scale: Double, turn: Double = 0,
                       into inner: String, keeping outline: String? = nil,
                       minimumArea: Double = 0, weight: Double = 1) -> Self {
        Self(label: label, weight: weight, minimumArea: minimumArea) { piece, _ in
            guard scale > 0, piece.contour.points.count >= 3 else { return nil }
            let middle = piece.centroid
            let copy = piece.contour.points.map {
                middle + ($0 - middle).rotated(by: turn) * scale
            }
            var made: [ShapeGrammar.Piece] = []
            if let outline { made.append(ShapeGrammar.Piece(outline, piece.contour)) }
            made.append(ShapeGrammar.Piece(inner, copy))
            return made
        }
    }

    /// Rename the piece and leave its outline alone. Weighted against another
    /// rule on the same label, this is how a branch of a run stops early.
    static func stop(_ label: String, into finished: String, weight: Double = 1) -> Self {
        Self(label: label, weight: weight, minimumArea: 0) { piece, _ in
            [ShapeGrammar.Piece(finished, piece.contour)]
        }
    }

    /// Anything else. Hand back the pieces that replace `piece`, or `nil` to
    /// say this rule does not apply, which passes the piece to the other rules
    /// on its label. Depth is stamped for you.
    static func custom(_ label: String, weight: Double = 1, minimumArea: Double = 0,
                       _ body: @escaping @Sendable (ShapeGrammar.Piece, inout SplitMix64)
                           -> [ShapeGrammar.Piece]?) -> Self {
        Self(label: label, weight: weight, minimumArea: minimumArea, body: body)
    }
}

// MARK: - Grammars worth knowing

public extension ShapeGrammar {

    /// The lattice grammar: cut a frame in two again and again, each cut a
    /// straight line between two edges, each pair of parts about equal in area,
    /// and nothing cut once it is small enough.
    ///
    /// It is the whole of a traditional ice-ray window frame, whose bars were
    /// cut from finished sticks and fitted one at a time, and the run tells the
    /// same story: divide the area into large and equal spots, then keep
    /// dividing until the pieces are the size you wanted.
    static func iceRay(in frame: Rectangle, minimumArea: Double,
                       balance: Double = 0.2, sides: ClosedRange<Int> = 3 ... 5,
                       avoidingCorners: Double = 0.2) -> ShapeGrammar {
        ShapeGrammar(start: Piece("cell", frame),
                     rules: [.cut("cell", into: ("cell", "cell"), balance: balance,
                                  sides: sides, avoidingCorners: avoidingCorners,
                                  minimumArea: minimumArea)])
    }

    /// A square holding a smaller turned square, holding a smaller turned
    /// square, for as long as there is room. The default scale and turn land
    /// each copy on the middle of the last one's edges.
    static func nestedSquares(in frame: Rectangle, minimumArea: Double,
                              scale: Double = 0.707_106_781_186_547_6,
                              turn: Double = .pi / 4) -> ShapeGrammar {
        ShapeGrammar(start: Piece("square", frame),
                     rules: [.nested("square", scale: scale, turn: turn,
                                     into: "square", keeping: "drawn",
                                     minimumArea: minimumArea)])
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The pieces a grammar leaves after `generations` sweeps, driven by the
    /// seeded `random`, so `seed(_:)` makes the design reproducible.
    ///
    /// ```swift
    /// seed(4)
    /// noFill(); stroke(.white); strokeWeight(2)
    /// for piece in shapeGrammar(.iceRay(in: bounds, minimumArea: 8_000),
    ///                           generations: 9) {
    ///     drawPolyline(piece.corners, closed: true)
    /// }
    /// ```
    func shapeGrammar(_ grammar: ShapeGrammar, generations: Int) -> [ShapeGrammar.Piece] {
        grammar.run(generations: generations, using: &rng)
    }

    /// Draw every piece a grammar leaves, each with the current `fill` and
    /// `stroke`. For a color per label, walk `shapeGrammar(…)` yourself.
    func drawShapeGrammar(_ grammar: ShapeGrammar, generations: Int) {
        for piece in shapeGrammar(grammar, generations: generations) {
            drawShape(Shape(piece.corners))
        }
    }
}

// MARK: - Polygon arithmetic

private extension ShapeGrammar.Axis {
    /// The direction a cut measures along, for a piece of these bounds.
    func direction(for bounds: Rectangle) -> Vector2 {
        switch self {
        case .x: return .unitX
        case .y: return .unitY
        case .longest: return bounds.width >= bounds.height ? .unitX : .unitY
        case .shortest: return bounds.width >= bounds.height ? .unitY : .unitX
        }
    }
}

/// The signed area of a closed polygon. It is positive when the corners run
/// clockwise on the canvas, where y grows downward.
private func polygonSignedArea(_ points: [Vector2]) -> Double {
    guard points.count >= 3 else { return 0 }
    var total = 0.0
    for i in points.indices {
        let p = points[i], q = points[(i + 1) % points.count]
        total += p.x * q.y - q.x * p.y
    }
    return total / 2
}

/// The point a polygon's area balances on.
private func polygonCentroid(_ points: [Vector2]) -> Vector2 {
    guard points.count >= 3 else { return meanPoint(points) }
    var twiceArea = 0.0, x = 0.0, y = 0.0
    for i in points.indices {
        let p = points[i], q = points[(i + 1) % points.count]
        let cross = p.x * q.y - q.x * p.y
        twiceArea += cross
        x += (p.x + q.x) * cross
        y += (p.y + q.y) * cross
    }
    guard abs(twiceArea) > 1e-12 else { return meanPoint(points) }
    return Vector2(x / (3 * twiceArea), y / (3 * twiceArea))
}

private func meanPoint(_ points: [Vector2]) -> Vector2 {
    guard !points.isEmpty else { return .zero }
    var sum = Vector2.zero
    for p in points { sum += p }
    return sum / Double(points.count)
}

/// The upright box a polygon fits in.
private func polygonBounds(_ points: [Vector2]) -> Rectangle {
    guard let first = points.first else { return Rectangle(x: 0, y: 0, width: 0, height: 0) }
    var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
    for p in points.dropFirst() {
        minX = min(minX, p.x); maxX = max(maxX, p.x)
        minY = min(minY, p.y); maxY = max(maxY, p.y)
    }
    return Rectangle(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

/// The two polygons a straight line leaves, drawn from a point `s` of the way
/// along edge `i` to a point `t` of the way along edge `j`.
private func cutParts(_ points: [Vector2], from i: Int, at s: Double,
              to j: Int, at t: Double) -> ([Vector2], [Vector2]) {
    let n = points.count
    guard n >= 3, i != j else { return (points, []) }
    let a = points[i].lerp(to: points[(i + 1) % n], s)
    let b = points[j].lerp(to: points[(j + 1) % n], t)
    var first = [a], second = [b]
    var k = (i + 1) % n
    while true {
        first.append(points[k])
        if k == j { break }
        k = (k + 1) % n
    }
    first.append(b)
    k = (j + 1) % n
    while true {
        second.append(points[k])
        if k == i { break }
        k = (k + 1) % n
    }
    second.append(a)
    return (first, second)
}

/// A polygon cut into bands by lines square to `direction`, at fractions of the
/// polygon's own reach along it.
private func splitPolygon(_ points: [Vector2], along direction: Vector2,
                  at fractions: [Double]) -> [[Vector2]] {
    guard points.count >= 3 else { return [] }
    let axis = direction.normalized
    var low = points[0].dot(axis), high = low
    for p in points.dropFirst() {
        let d = p.dot(axis)
        low = min(low, d); high = max(high, d)
    }
    let reach = high - low
    guard reach > 1e-12 else { return [] }
    var edges = [low]
    for f in fractions {
        let d = low + f * reach
        if d > edges[edges.count - 1] + 1e-9 { edges.append(d) }
    }
    edges.append(high)
    var bands: [[Vector2]] = []
    for k in 0 ..< edges.count - 1 {
        var band = clipHalfPlane(points, axis: axis, at: edges[k], keepingAbove: true)
        band = clipHalfPlane(band, axis: axis, at: edges[k + 1], keepingAbove: false)
        if band.count >= 3, abs(polygonSignedArea(band)) > 1e-9 { bands.append(band) }
    }
    return bands
}

/// The part of a polygon on one side of a line square to `axis`.
private func clipHalfPlane(_ points: [Vector2], axis: Vector2, at offset: Double,
                           keepingAbove: Bool) -> [Vector2] {
    guard points.count >= 3 else { return [] }
    let sign: Double = keepingAbove ? 1 : -1
    var kept: [Vector2] = []
    kept.reserveCapacity(points.count + 2)
    for i in points.indices {
        let p = points[i], q = points[(i + 1) % points.count]
        let dp = sign * (p.dot(axis) - offset), dq = sign * (q.dot(axis) - offset)
        if dp >= 0 { kept.append(p) }
        if (dp > 0 && dq < 0) || (dp < 0 && dq > 0) {
            kept.append(p.lerp(to: q, dp / (dp - dq)))
        }
    }
    return kept
}

/// A convex polygon with every edge pushed inward by `distance`, or `nil` when
/// that leaves nothing.
private func insetPolygon(_ points: [Vector2], by distance: Double) -> [Vector2]? {
    let n = points.count
    guard n >= 3 else { return nil }
    let orientation: Double = polygonSignedArea(points) >= 0 ? 1 : -1
    var origins = [Vector2](repeating: .zero, count: n)
    var headings = [Vector2](repeating: .zero, count: n)
    for k in 0 ..< n {
        let edge = points[(k + 1) % n] - points[k]
        guard edge.lengthSquared > 1e-18 else { return nil }
        let heading = edge.normalized
        headings[k] = heading
        origins[k] = points[k] + heading.perpendicular * (orientation * distance)
    }
    var pulled = [Vector2]()
    pulled.reserveCapacity(n)
    for k in 0 ..< n {
        let previous = (k + n - 1) % n
        guard let corner = lineCrossing(origins[previous], headings[previous],
                                        origins[k], headings[k]) else { return nil }
        pulled.append(corner)
    }
    // An edge pushed further than the shape is wide crosses its neighbors and
    // comes back pointing the other way. The polygon that leaves is still
    // wound the same way and still measures a positive area, so the only test
    // that sees it is whether each edge still runs the way it used to.
    for k in 0 ..< n {
        let edge = pulled[(k + 1) % n] - pulled[k]
        guard edge.dot(headings[k]) > 1e-9 else { return nil }
    }
    guard polygonSignedArea(pulled) * orientation > 1e-9 else { return nil }
    return pulled
}

/// Where two lines cross, or `nil` when they run parallel.
private func lineCrossing(_ a: Vector2, _ da: Vector2,
                          _ b: Vector2, _ db: Vector2) -> Vector2? {
    let denominator = da.cross(db)
    guard abs(denominator) > 1e-12 else { return nil }
    return a + da * ((b - a).cross(db) / denominator)
}
