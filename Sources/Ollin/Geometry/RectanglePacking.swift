import Foundation

// Rectangles of given sizes packed into one bin, by maximal free rectangles:
// the free space is kept as every largest empty rectangle it holds (they
// overlap), a placement goes to the top-left corner of one of them, and each
// free rectangle the placement cuts is replaced by the up-to-four largest
// pieces left around it, any piece inside another dropped. Each step places
// the rectangle and free region that fit most snugly on their shorter
// leftover side (the long side breaks a tie), choosing among every
// rectangle still waiting rather than taking them in the order given, the
// combination that packed best among the variants Jylänki compared.

/// Rectangles packed into a bin by `packRectangles(_:in:padding:allowsRotation:)`:
/// where each one went, and which did not fit.
public struct RectanglePacking: Equatable, Sendable {
    /// One rectangle placed in the bin.
    public struct Placement: Equatable, Sendable {
        /// The rectangle's place in the list of sizes that was packed.
        public let index: Int
        /// Where it went, in the bin's coordinates. A rotated rectangle's
        /// width is the height it was given, and its height the width.
        public let rectangle: Rectangle
        /// Whether it was turned a quarter turn to fit, which only happens
        /// when the packing allows rotation.
        public let isRotated: Bool

        init(index: Int, rectangle: Rectangle, isRotated: Bool) {
            self.index = index
            self.rectangle = rectangle
            self.isRotated = isRotated
        }
    }

    /// The region the rectangles were packed into.
    public let bin: Rectangle
    /// Every rectangle that fit, in the order of the sizes given (by
    /// `index`), which is not the order they were placed in.
    public let placed: [Placement]
    /// The places in the list of sizes of every rectangle that did not fit,
    /// in order: too big for the room left, or a size with no area.
    public let unplaced: [Int]

    init(bin: Rectangle, placed: [Placement], unplaced: [Int]) {
        self.bin = bin
        self.placed = placed
        self.unplaced = unplaced
    }

    /// The share of the bin's area the placed rectangles cover, 0 to 1:
    /// how tight the packing is. Padding counts as uncovered.
    public var occupancy: Double {
        let area = bin.width * bin.height
        guard area > 0, area.isFinite else { return 0 }
        return placed.reduce(0) { $0 + $1.rectangle.width * $1.rectangle.height } / area
    }
}

/// Rectangles of the given sizes (`x` the width, `y` the height) packed into
/// `bin` without overlapping: photos at their own proportions on a contact
/// sheet, a collage, sprites into a texture atlas. Each placed rectangle
/// keeps its size; the ones that do not fit are listed by their place in
/// `sizes`, so a sketch can shrink them, start a second sheet, or leave
/// them out.
///
/// ```swift
/// let sizes = (0 ..< 40).map { _ in Vector2(random(60, 260), random(60, 260)) }
/// let packing = packRectangles(sizes, in: Rectangle(x: 40, y: 40, width: 1000, height: 1000),
///                              padding: 8)
/// for place in packing.placed { drawRect(place.rectangle) }
/// ```
///
/// The packer keeps the free space as the largest empty rectangles it
/// holds and places each rectangle in the top-left corner of the one it fits
/// most snugly, measured by the smaller of the two gaps it leaves (the
/// larger gap breaks a tie). At every step it weighs every rectangle still
/// waiting, not only the next in the list, and places the snuggest fit of
/// all, so the order of `sizes` matters only between equal fits, where the
/// earlier wins. The result is the same for the same input every time.
///
/// `padding` is the gap left between neighboring rectangles; they may still
/// touch the bin's edges, so inset the bin to leave a margin there. With
/// `allowsRotation`, a rectangle may be turned a quarter turn when that fits
/// it better (`Placement.isRotated` says which were). A size whose width or
/// height is not above zero, or not finite, is never placed.
///
/// Weighing every waiting rectangle at every step makes the cost grow
/// faster than the count: three hundred rectangles pack in about twenty
/// milliseconds and a thousand in about half a second, while three thousand
/// take over ten seconds, so pack a large set once and hold the result.
public func packRectangles(_ sizes: [Vector2], in bin: Rectangle,
                           padding: Double = 0, allowsRotation: Bool = false) -> RectanglePacking {
    let gap = padding.isFinite ? Swift.max(padding, 0) : 0
    let binOK = bin.width.isFinite && bin.height.isFinite && bin.corner.x.isFinite && bin.corner.y.isFinite
        && bin.width > 0 && bin.height > 0
    var waiting: [Int] = []
    var unplaced: [Int] = []
    for (i, s) in sizes.enumerated() {
        if binOK, s.x.isFinite, s.y.isFinite, s.x > 0, s.y > 0 { waiting.append(i) } else { unplaced.append(i) }
    }
    guard binOK else { return RectanglePacking(bin: bin, placed: [], unplaced: unplaced) }

    // Every rectangle and the bin are padded by the gap on their right and
    // bottom, so neighbors sit a gap apart while the last ones still reach
    // the bin's far edges.
    var packer = MaxRectsPacker(bin: FreeRect(x: bin.corner.x, y: bin.corner.y,
                                              width: bin.width + gap, height: bin.height + gap))
    let padded = sizes.map { Vector2($0.x + gap, $0.y + gap) }

    // Each waiting rectangle's snuggest fit, kept between steps: a placement
    // only takes free regions away and adds a few new ones, so a fit whose
    // region survives can only be bettered by a new region, and only a
    // rectangle whose region was cut needs every region weighed again.
    var best = [MaxRectsPacker.Fit?](repeating: nil, count: sizes.count)
    for i in waiting {
        best[i] = packer.bestFit(width: padded[i].x, height: padded[i].y, rotating: allowsRotation)
    }
    var placed: [RectanglePacking.Placement] = []
    while true {
        // A rectangle with no fit now never fits: the free space only shrinks.
        waiting.removeAll { i in
            if best[i] == nil { unplaced.append(i); return true }
            return false
        }
        // The snuggest fit of all; between equal fits, the earlier size.
        var choice: (index: Int, fit: MaxRectsPacker.Fit)? = nil
        for i in waiting {
            guard let fit = best[i] else { continue }
            if let c = choice, !(fit.short < c.fit.short || (fit.short == c.fit.short && fit.long < c.fit.long)) {
                continue
            }
            choice = (i, fit)
        }
        guard let (i, fit) = choice else { break }
        waiting.removeAll { $0 == i }
        best[i] = nil
        let (pw, ph) = fit.rotated ? (sizes[i].y, sizes[i].x) : (sizes[i].x, sizes[i].y)
        let change = packer.place(FreeRect(x: fit.x, y: fit.y, width: pw + gap, height: ph + gap))
        placed.append(.init(index: i, rectangle: Rectangle(x: fit.x, y: fit.y, width: pw, height: ph),
                            isRotated: fit.rotated))
        for j in waiting {
            guard let old = best[j] else { continue }
            if change.removed.contains(old.region) {
                best[j] = packer.bestFit(width: padded[j].x, height: padded[j].y, rotating: allowsRotation)
            } else {
                let fresh = packer.bestFit(width: padded[j].x, height: padded[j].y, rotating: allowsRotation,
                                           among: change.added)
                if let fresh, fresh.beats(old) { best[j] = fresh }
            }
        }
    }
    unplaced.append(contentsOf: waiting)
    placed.sort { $0.index < $1.index }
    unplaced.sort()
    return RectanglePacking(bin: bin, placed: placed, unplaced: unplaced)
}

public extension Sketch {
    /// Rectangles of the given sizes packed into `bin` (the whole canvas by
    /// default) without overlapping, each kept at its size; see
    /// `packRectangles(_:in:padding:allowsRotation:)`. The packing uses no
    /// randomness, so the same sizes always land the same way.
    ///
    /// ```swift
    /// let packing = packRectangles(photos.map { Vector2($0.width, $0.height) * 0.2 }, padding: 6)
    /// for place in packing.placed { drawImage(photos[place.index], in: place.rectangle) }
    /// ```
    func packRectangles(_ sizes: [Vector2], in bin: Rectangle? = nil,
                        padding: Double = 0, allowsRotation: Bool = false) -> RectanglePacking {
        Ollin.packRectangles(sizes, in: bin ?? canvasRectangle, padding: padding, allowsRotation: allowsRotation)
    }
}

// MARK: - The free space

/// A free region of the bin, plain numbers for the inner loops.
struct FreeRect: Equatable {
    var x, y, width, height: Double
    var right: Double { x + width }
    var bottom: Double { y + height }

    /// Room for a `w` by `h` rectangle, allowing for the rounding a run of
    /// sums leaves.
    func fits(_ w: Double, _ h: Double) -> Bool {
        let slack = 1e-9 * Swift.max(1, Swift.max(width, height))
        return w <= width + slack && h <= height + slack
    }

    func contains(_ other: FreeRect) -> Bool {
        let slack = 1e-9 * Swift.max(1, Swift.max(width, height))
        return other.x >= x - slack && other.y >= y - slack
            && other.right <= right + slack && other.bottom <= bottom + slack
    }
}

/// The maximal free rectangles of one bin, each with an identity that
/// lasts while it does, so a fit can tell whether its region survived a
/// placement.
struct MaxRectsPacker {
    private(set) var free: [FreeRect]
    private(set) var ids: [Int]
    private var nextID = 1

    /// Where a rectangle fits best, and how snugly: the smaller and larger
    /// gaps it leaves in its region.
    struct Fit {
        var short: Double
        var long: Double
        var x: Double
        var y: Double
        var rotated: Bool
        var region: Int

        /// The snugger of two fits: the smaller short gap, then the smaller
        /// long gap, then the one higher up, then further left, then upright.
        /// Equal on all of these, two fits place the rectangle in the same
        /// place, so which region it came from does not matter.
        func beats(_ other: Fit) -> Bool {
            if short != other.short { return short < other.short }
            if long != other.long { return long < other.long }
            if y != other.y { return y < other.y }
            if x != other.x { return x < other.x }
            return !rotated && other.rotated
        }
    }

    init(bin: FreeRect) {
        free = [bin]
        ids = [0]
    }

    /// The snuggest fit of a `width` by `height` rectangle among the free
    /// regions at `positions` (all of them when nil), turned a quarter turn
    /// too when `rotating`; nil when it fits none of them.
    func bestFit(width: Double, height: Double, rotating: Bool, among positions: [Int]? = nil) -> Fit? {
        var best: Fit? = nil
        func consider(_ k: Int) {
            let f = free[k]
            for rotated in rotating && width != height ? [false, true] : [false] {
                let (w, h) = rotated ? (height, width) : (width, height)
                guard f.fits(w, h) else { continue }
                let dx = Swift.max(f.width - w, 0), dy = Swift.max(f.height - h, 0)
                let fit = Fit(short: Swift.min(dx, dy), long: Swift.max(dx, dy), x: f.x, y: f.y,
                              rotated: rotated, region: ids[k])
                if best.map({ fit.beats($0) }) ?? true { best = fit }
            }
        }
        if let positions { for k in positions { consider(k) } } else { for k in free.indices { consider(k) } }
        return best
    }

    /// Takes `used` out of the free space: every free rectangle it overlaps
    /// is replaced by the largest pieces left above, below, left, and right
    /// of it, and any new piece inside another free rectangle is dropped.
    /// The free rectangles it did not touch were already none inside
    /// another, and none of them can be inside a piece, since a piece is
    /// inside the rectangle it was cut from, so only the pieces are checked.
    /// Returns the identities of the regions that went and the positions of
    /// the ones that arrived.
    mutating func place(_ used: FreeRect) -> (removed: Set<Int>, added: [Int]) {
        var kept: [FreeRect] = [], keptIDs: [Int] = []
        var pieces: [FreeRect] = []
        var removed = Set<Int>()
        kept.reserveCapacity(free.count)
        keptIDs.reserveCapacity(free.count)
        for (k, f) in free.enumerated() {
            // Touching is not overlapping.
            guard used.x < f.right, used.right > f.x, used.y < f.bottom, used.bottom > f.y else {
                kept.append(f)
                keptIDs.append(ids[k])
                continue
            }
            removed.insert(ids[k])
            if used.y > f.y { pieces.append(FreeRect(x: f.x, y: f.y, width: f.width, height: used.y - f.y)) }
            if used.bottom < f.bottom {
                pieces.append(FreeRect(x: f.x, y: used.bottom, width: f.width, height: f.bottom - used.bottom))
            }
            if used.x > f.x { pieces.append(FreeRect(x: f.x, y: f.y, width: used.x - f.x, height: f.height)) }
            if used.right < f.right {
                pieces.append(FreeRect(x: used.right, y: f.y, width: f.right - used.right, height: f.height))
            }
        }
        // A sliver thinner than the rounding of the sums is not room.
        pieces.removeAll { $0.width <= 1e-9 || $0.height <= 1e-9 }

        // A piece inside a region that stayed goes; of two pieces, one
        // inside the other goes, and of two equal ones, the later.
        var keep = [Bool](repeating: true, count: pieces.count)
        for i in pieces.indices {
            if kept.contains(where: { $0.contains(pieces[i]) }) {
                keep[i] = false
                continue
            }
            for j in pieces.indices where j != i && keep[j] {
                if pieces[j].contains(pieces[i]) && (pieces[i] != pieces[j] || j < i) {
                    keep[i] = false
                    break
                }
            }
        }
        var added: [Int] = []
        for i in pieces.indices where keep[i] {
            added.append(kept.count)
            kept.append(pieces[i])
            keptIDs.append(nextID)
            nextID += 1
        }
        free = kept
        ids = keptIDs
        return (removed, added)
    }
}
