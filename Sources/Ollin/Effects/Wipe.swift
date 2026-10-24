import Foundation

/// The order a wipe takes a layer's pixels in: a number for every pixel from 0,
/// which goes first, to 1, which goes last. A wipe's `progress` climbs from 0 to
/// 1 and each pixel turns over as the progress passes its number, across a soft
/// front, so the order alone decides whether the wipe is a straight edge, a
/// growing circle, a clock hand, a grid of blocks, or a dissolve.
///
/// ```swift
/// let doors = WipeOrder.directional().folded()             // two doors opening from the middle
/// let blinds = WipeOrder.directional(angle: .pi / 2).tiled(12)
/// let bars = WipeOrder.directional().bands(24).shuffled(seed: 3)
/// let rings = WipeOrder.radial().bands(6)
/// let blocks = WipeOrder.cells(columns: 8, rows: 8).shuffled(seed: 1)
/// ```
///
/// An order starts from one of five shapes and takes any of the modifiers after
/// it. The modifiers apply in one fixed order, whatever order they are written
/// in: the fold, the tiling, the bands, the shuffle, the checkerboard, the
/// diamonds, and last the reversal. The shuffle, the checkerboard, and the
/// diamonds reorder whole pieces, so they need pieces to work on: the cells of
/// `.cells`, or the bands of `.bands(_:)`. On a continuous order with neither,
/// they change nothing.
///
/// Positions are fractions of the layer with the origin at its top left, and
/// angles are in radians in the canvas's own directions, so an angle of 0 runs
/// left to right and `.pi / 2` top to bottom. Distances are measured with the
/// layer's aspect taken out, so a radial wipe grows as a circle on any layer.
public struct WipeOrder: Sendable, Equatable {

    enum Shape: Sendable, Equatable {
        case directional(angle: Double)
        case radial(center: Vector2)
        case angular(center: Vector2, angle: Double)
        case cells(columns: Int, rows: Int)
        case noise(size: Double, seed: Int)
    }

    var shape: Shape
    var isFolded = false
    var tiles = 0
    var bandCount = 0
    var shuffleSeed: Int?
    var isChecker = false
    var isDiamond = false
    var isReversed = false

    init(_ shape: Shape) { self.shape = shape }

    /// A straight edge sweeping across the layer, along `angle`: 0 sweeps left to
    /// right, `.pi / 2` top to bottom. The first pixel to go is the corner farthest
    /// back along the direction and the last the corner farthest ahead.
    public static func directional(angle: Double = 0) -> WipeOrder {
        WipeOrder(.directional(angle: angle))
    }

    /// A circle growing from `center` (fractions of the layer, the middle by
    /// default) until it reaches the layer's farthest corner.
    public static func radial(center: Vector2 = Vector2(0.5, 0.5)) -> WipeOrder {
        WipeOrder(.radial(center: center))
    }

    /// A clock hand sweeping once around `center`, starting at `angle` and turning
    /// clockwise on the canvas.
    public static func angular(center: Vector2 = Vector2(0.5, 0.5), angle: Double = -.pi / 2) -> WipeOrder {
        WipeOrder(.angular(center: center, angle: angle))
    }

    /// A grid of `columns` by `rows` blocks that each go whole, in reading order:
    /// along the top row first, then down. Up to 128 each way.
    public static func cells(columns: Int = 8, rows: Int = 8) -> WipeOrder {
        WipeOrder(.cells(columns: min(max(columns, 1), 128), rows: min(max(rows, 1), 128)))
    }

    /// A dissolve along smooth noise whose blobs are about `size` of the layer's
    /// height across, the soft film dissolve; `seed` picks the noise.
    public static func noise(size: Double = 0.2, seed: Int = 0) -> WipeOrder {
        WipeOrder(.noise(size: max(size, 0.001), seed: seed))
    }

    /// Fold the order in half, so the middle goes first and the two ends last:
    /// one edge becomes two opening outward, and a radial wipe closes in from a
    /// ring halfway out.
    public func folded() -> WipeOrder {
        var copy = self
        copy.isFolded = true
        return copy
    }

    /// Repeat the order `count` times across its run, so each strip wipes on its
    /// own at the same time: venetian blinds from a directional order.
    public func tiled(_ count: Int) -> WipeOrder {
        var copy = self
        copy.tiles = min(max(count, 1), 1024)
        return copy
    }

    /// Cut the order into `count` bands that each go whole, in turn: bars from a
    /// directional order, rings popping outward from a radial one.
    public func bands(_ count: Int) -> WipeOrder {
        var copy = self
        copy.bandCount = min(max(count, 1), 4096)
        return copy
    }

    /// Take the pieces (the bands, or else the cells) in an order picked by `seed`
    /// rather than in turn. The same seed always gives the same order, and every
    /// piece still gets a slot of its own.
    public func shuffled(seed: Int = 0) -> WipeOrder {
        var copy = self
        copy.shuffleSeed = seed
        return copy
    }

    /// Take the pieces as a checkerboard: every other cell (or band) first, then
    /// the rest, each half in its own order.
    public func checker() -> WipeOrder {
        var copy = self
        copy.isChecker = true
        return copy
    }

    /// Open each cell as a diamond growing from its middle, still in the cells'
    /// order, so the grid reads as a lattice of diamonds while it goes. Only cells
    /// have a middle to grow from; a band ignores it.
    public func diamond() -> WipeOrder {
        var copy = self
        copy.isDiamond = true
        return copy
    }

    /// Run the order backward: what went last goes first, so a radial wipe closes
    /// in from the corners instead of growing from the middle.
    public func reversed() -> WipeOrder {
        var copy = self
        copy.isReversed = !isReversed
        return copy
    }

    /// The number of pieces a shuffle or a checkerboard reorders: the bands, or
    /// else the cells, or 0 for a continuous order.
    var pieces: Int {
        if bandCount > 0 { return bandCount }
        if case let .cells(columns, rows) = shape { return columns * rows }
        return 0
    }

    /// The pieces' shuffled slots, one texel each (the slot in `x`), or a single
    /// unused texel when nothing is shuffled. A Fisher-Yates walk over a seeded
    /// SplitMix64, so the order is the same on every machine.
    var permutation: [SIMD4<Float>] {
        guard let seed = shuffleSeed, pieces > 1 else { return [.zero] }
        var slots = Array(0..<pieces)
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)) &+ 0x5749_5045)
        for i in stride(from: slots.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            slots.swapAt(i, j)
        }
        return slots.map { SIMD4(Float($0), 0, 0, 0) }
    }

    /// The three rows `ollin_wipe_order` reads, at a layer `aspect` wide for a
    /// height of 1 (kept in step with the shader).
    func rows(aspect: Float) -> [SIMD4<Float>] {
        let head: SIMD4<Float>
        switch shape {
        case let .directional(angle):
            head = SIMD4(0, Float(cos(angle)), Float(sin(angle)), 0)
        case let .radial(center):
            head = SIMD4(1, Float(center.x), Float(center.y), 0)
        case let .angular(center, angle):
            head = SIMD4(2, Float(center.x), Float(center.y), Float(angle))
        case let .cells(columns, rows):
            head = SIMD4(3, Float(columns), Float(rows), 0)
        case let .noise(size, seed):
            // The seed moves the noise by whole cells, kept small so a float
            // holds the position exactly.
            head = SIMD4(4, Float(size), Float(seed % 4096) * 37.0, 0)
        }
        let shuffles = shuffleSeed != nil && pieces > 1
        return [head,
                SIMD4(isFolded ? 1 : 0, Float(tiles), Float(bandCount), shuffles ? Float(pieces) : 0),
                SIMD4(isChecker ? 1 : 0, isDiamond ? 1 : 0, isReversed ? 1 : 0, aspect)]
    }
}

extension Combine {
    /// Wipe from the base to the aux layer in `order`: as `progress` climbs from 0
    /// to 1, each pixel turns from the base to the aux when the progress passes its
    /// place in the order, across a soft front `feather` of the order's run wide.
    ///
    /// ```swift
    /// let t = (time * 0.25).truncatingRemainder(dividingBy: 1)
    /// drawImage(day.combined(with: night, .wipe(.radial(), progress: t)).image, 0, 0)
    /// ```
    ///
    /// At a progress of 0 the result is the base and at 1 the aux, each exactly, so
    /// a wipe that has finished costs the picture nothing. The front is centered on
    /// the progress, so at 0.5 a directional wipe has each layer on one half with
    /// the feather straddling the middle; a `feather` of 0 is a hard edge. Only the
    /// mix changes, one pointwise pass, so the two layers can be anything: two
    /// scenes, a scene and a blank layer, a picture and its filtered self.
    public static func wipe(_ order: WipeOrder, progress: Double, feather: Double = 0.05) -> Combine {
        Combine(kind: .wipe(order, progress: min(max(progress, 0), 1), feather: max(feather, 0)))
    }
}

extension Filter {
    /// Reveal the layer in `order`: as `progress` climbs from 0 to 1, each pixel
    /// appears when the progress passes its place in the order, across a soft
    /// front `feather` of the order's run wide, so the layer composites over
    /// whatever is behind it as it comes in.
    ///
    /// ```swift
    /// let title = makeRenderTarget()
    /// withTarget(title) { fill(.white); textSize(200); drawText("Ollin", 160, 600) }
    /// drawImage(title.filtered(.wipe(.cells(columns: 12, rows: 6).shuffled(), progress: t)).image, 0, 0)
    /// ```
    ///
    /// Only the layer's coverage changes: at 0 it is fully transparent, at 1 it is
    /// exactly as it was, and in between each pixel keeps its color while it fades
    /// in. To take a layer away instead, run the progress from 1 down to 0. It is
    /// `Combine.wipe(_:progress:feather:)` from an empty layer to this one.
    public static func wipe(_ order: WipeOrder, progress: Double, feather: Double = 0.05) -> Filter {
        Filter(kind: .wipe(order, progress: min(max(progress, 0), 1), feather: max(feather, 0)))
    }
}

extension ComposeLayer {
    /// Wipe this layer away to an `aside` layer in `order`, as
    /// `Combine.wipe(_:progress:feather:)` does: 0 is this layer, 1 the aside. The
    /// aside is drawn only to feed the wipe, not composited on its own.
    ///
    /// ```swift
    /// layer { drawDay() }
    ///     .wiped(to: aside { drawNight() }, .angular(), progress: t)
    /// ```
    public func wiped(to aside: ComposeLayer, _ order: WipeOrder, progress: Double,
                      feather: Double = 0.05) -> ComposeLayer {
        var copy = self
        copy.steps.append(.combine(aside: aside, op: .wipe(order, progress: progress, feather: feather)))
        return copy
    }
}
