import Foundation

/// The stepped, bleeding edge of a resist-dyed stripe, as geometry a plotter
/// can draw. In ikat the threads are tied in bundles and dyed before they are
/// woven, and every bundle lands a little out of place on the loom, so a
/// stripe's edge is not a line but a stair: one step per bundle, each at its
/// own height, with a few bundles pulled far out as spikes and a few pulled
/// in as intrusions, and the whole edge leaning along the warp.
///
/// A `Stripe` is a band, the stripe as it was designed, with an offset per
/// bundle at each of its two edges. A bundle's *slip* moves both its edges
/// together (the bundle shifted on the loom, with the stripe's `skew` as a
/// shear across it); its *bleed* moves each edge on its own (the dye
/// creeping, flaring in and out by a slow noise, spiking out on a share of
/// the bundles and intruding on another). The two stepped edges and the
/// shape between them are what a sketch strokes and fills. The same seed
/// dyes the same stripe.
///
/// ```swift
/// let cloth = Ikat.stripes(in: canvasRectangle, count: 5, bundle: 14, bleed: 26, seed: 3)
/// fill(Color(hex: 0x1F2B5B)); noStroke()
/// for stripe in cloth.stripes { drawShape(stripe.shape) }
/// ```
public struct Ikat: Equatable, Sendable {

    /// The direction the warp threads run, which is the direction the bundles
    /// slip in: a stripe lies across it.
    public enum Warp: Equatable, Sendable {
        case vertical, horizontal
    }

    /// One stripe: a band with an offset per bundle at each edge.
    public struct Stripe: Equatable, Sendable {
        /// The stripe as designed, before any bundle slipped or any dye bled.
        public let band: Rectangle
        /// The width of a bundle across the warp.
        public let bundle: Double
        /// The direction the threads run.
        public let warp: Warp
        /// The leading edge's offset per bundle along the warp (the top edge
        /// for a vertical warp, the left for a horizontal one): negative
        /// moves it out of the band.
        public let leading: [Double]
        /// The trailing edge's offset per bundle along the warp: positive
        /// moves it out of the band.
        public let trailing: [Double]

        public init(band: Rectangle, bundle: Double, warp: Warp = .vertical, leading: [Double], trailing: [Double]) {
            self.band = band
            self.bundle = max(bundle, 1e-6)
            self.warp = warp
            let n = min(leading.count, trailing.count)
            self.leading = Array(leading.prefix(n))
            self.trailing = Array(trailing.prefix(n))
        }

        /// How many bundles the stripe spans.
        public var bundles: Int { leading.count }

        /// The leading edge as a stepped polyline, across the warp: two
        /// points per bundle, one riser between bundles.
        public var leadingEdge: [Vector2] { edge(leading, along: alongStart) }
        /// The trailing edge as a stepped polyline, in the same direction.
        public var trailingEdge: [Vector2] { edge(trailing, along: alongStart + alongLength) }
        /// Both edges.
        public var edges: [[Vector2]] { [leadingEdge, trailingEdge] }

        /// The stripe between its two edges, closed.
        public var shape: Shape {
            Shape(leadingEdge + trailingEdge.reversed())
        }

        private var acrossLength: Double { warp == .vertical ? band.width : band.height }
        private var alongLength: Double { warp == .vertical ? band.height : band.width }
        private var alongStart: Double { warp == .vertical ? band.y : band.x }
        private var acrossOrigin: Double { warp == .vertical ? band.x : band.y }

        private func point(across: Double, along: Double) -> Vector2 {
            warp == .vertical ? Vector2(across, along) : Vector2(along, across)
        }

        private func edge(_ offsets: [Double], along base: Double) -> [Vector2] {
            var points: [Vector2] = []
            points.reserveCapacity(offsets.count * 2)
            for (b, offset) in offsets.enumerated() {
                let a0 = acrossOrigin + Double(b) * bundle
                let a1 = min(a0 + bundle, acrossOrigin + acrossLength)
                let y = base + offset
                points.append(point(across: a0, along: y))
                points.append(point(across: a1, along: y))
            }
            return points
        }
    }

    /// The stripes, in order along the warp.
    public let stripes: [Stripe]

    public init(stripes: [Stripe]) {
        self.stripes = stripes
    }

    /// Every stripe's shape.
    public var shapes: [Shape] { stripes.map(\.shape) }
    /// Every stripe's two stepped edges.
    public var edges: [[Vector2]] { stripes.flatMap(\.edges) }

    // MARK: - Dyeing

    /// One stripe over `band`, its bundles `bundle` wide across the warp.
    /// Each bundle slips along the warp by a slow noise of up to a third of
    /// `bleed` plus the stripe's `skew`, a shear of `skew` times `bleed` from
    /// one end of the stripe to the other, moving both its edges together.
    /// Each edge then bleeds on its own: a flare of up to half of `bleed`
    /// either way by a slow noise, a spike of one to two bleeds out on a
    /// `spikes` share of the bundles (a spike runs into the next bundle a
    /// third of the time), and an intrusion of half to one bleed in on an
    /// `intrusions` share, never past two fifths of the band. The same seed
    /// dyes the same stripe.
    public static func stripe(across band: Rectangle, bundle: Double = 12, bleed: Double = 24, spikes: Double = 0.15,
                              intrusions: Double = 0.15, skew: Double = 1, warp: Warp = .vertical,
                              seed: Int = 0) -> Stripe {
        let bundle = max(bundle, 1e-6)
        let bleed = max(bleed, 0)
        let spikes = min(max(spikes, 0), 1)
        let intrusions = min(max(intrusions, 0), 1)
        let acrossLength = warp == .vertical ? band.width : band.height
        let alongLength = warp == .vertical ? band.height : band.width
        let n = max(1, Int((acrossLength / bundle - 1e-9).rounded(.up)))
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        let fields = NoiseFields(seed: seed)
        let deepest = alongLength * 0.4

        var leading: [Double] = []
        var trailing: [Double] = []
        leading.reserveCapacity(n)
        trailing.reserveCapacity(n)
        var carry = (leading: 0.0, trailing: 0.0)
        for b in 0 ..< n {
            let u = (Double(b) + 0.5) * bundle
            let shear = n > 1 ? skew * bleed * (Double(b) / Double(n - 1) - 0.5) : 0
            let slip = shear + 0.35 * bleed * fields.signedNoise(u / (bundle * 3) + 5.5)

            func bled(_ phase: Double, carried: inout Double) -> Double {
                var out = bleed * (fields.noise(u / (bundle * 5) + phase) - 0.5)
                if carried > 0 {
                    out += carried
                    carried = Double.random(in: 0 ..< 1, using: &rng) < 0.35 ? carried * 0.7 : 0
                } else if Double.random(in: 0 ..< 1, using: &rng) < spikes {
                    let spike = bleed * Double.random(in: 1 ... 2, using: &rng)
                    out += spike
                    carried = Double.random(in: 0 ..< 1, using: &rng) < 0.35 ? spike * 0.7 : 0
                } else if Double.random(in: 0 ..< 1, using: &rng) < intrusions {
                    out -= bleed * Double.random(in: 0.5 ... 1, using: &rng)
                }
                return max(out, -deepest)
            }
            let lead = bled(13, carried: &carry.leading)
            let trail = bled(47, carried: &carry.trailing)
            leading.append(slip - lead)
            trailing.append(slip + trail)
        }
        return Stripe(band: band, bundle: bundle, warp: warp, leading: leading, trailing: trailing)
    }

    /// `count` stripes across `region`, each half as tall as its share of the
    /// region along the warp and centered in it, every one dyed by
    /// `stripe(across:bundle:bleed:spikes:intrusions:skew:warp:seed:)` from
    /// its own draw of the seed.
    public static func stripes(in region: Rectangle, count: Int = 5, bundle: Double = 12, bleed: Double = 24,
                               spikes: Double = 0.15, intrusions: Double = 0.15, skew: Double = 1,
                               warp: Warp = .vertical, seed: Int = 0) -> Ikat {
        let count = max(count, 0)
        var stripes: [Stripe] = []
        stripes.reserveCapacity(count)
        for i in 0 ..< count {
            let share = (warp == .vertical ? region.height : region.width) / Double(count)
            let start = share * (Double(i) + 0.25)
            let band = warp == .vertical
                ? Rectangle(x: region.x, y: region.y + start, width: region.width, height: share * 0.5)
                : Rectangle(x: region.x + start, y: region.y, width: share * 0.5, height: region.height)
            stripes.append(stripe(across: band, bundle: bundle, bleed: bleed, spikes: spikes, intrusions: intrusions,
                                  skew: skew, warp: warp, seed: seed &+ i &* 7919))
        }
        return Ikat(stripes: stripes)
    }
}
