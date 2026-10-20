import Foundation

/// Hoarfrost as line work a plotter can draw: needles sprouted along an
/// outline's normals, each a straight spine with barbs leaning toward its
/// tip, the way frost grows on a pane's edge or a twig.
///
/// The needles stand `spacing` apart along the outline and point away from
/// it (`side`), each tilted a little. Their lengths follow a slow noise along
/// the outline mixed with a draw per needle (`clump`), so long needles come
/// in runs with short ones between. The barbs follow one law: they start
/// `barbStart` of the way up the spine, sit `barbSpacing` apart from there,
/// lean forward at `barbAngle` off the spine on both sides, and shorten
/// toward the tip (`barbStations(length:spacing:)` is that law, so a sketch
/// can read it). Every stroke is a point list, so the frost feeds stroking,
/// hatching, and the vector exports; the same seed grows the same frost.
///
/// ```swift
/// let pane = Frost.grow(along: Contour(canvasRectangle.points), spacing: 7, length: 90, side: .inside, seed: 2)
/// stroke(.white); strokeWeight(1); noFill()
/// for line in pane.strokes { drawPolyline(line) }
/// ```
public struct Frost: Equatable, Sendable {

    /// Which side of the outline the needles grow on. For a closed outline
    /// `outside` is away from its interior; for an open path it is the left
    /// of the direction of travel, and `inside` the right.
    public enum Side: Equatable, Sendable {
        case outside, inside, both
    }

    /// One barb off a needle's spine.
    public struct Barb: Equatable, Sendable {
        /// Where the barb leaves the spine.
        public let base: Vector2
        /// Its far end.
        public let tip: Vector2
        /// Where along the needle it sits, 0 the root to 1 the tip.
        public let station: Double
        /// `1` on the left of the needle's direction, `-1` on the right.
        public let side: Int

        public init(base: Vector2, tip: Vector2, station: Double, side: Int) {
            self.base = base
            self.tip = tip
            self.station = min(max(station, 0), 1)
            self.side = side < 0 ? -1 : 1
        }

        /// The barb as a two-point stroke.
        public var points: [Vector2] { [base, tip] }
        public var length: Double { (tip - base).length }
    }

    /// One needle: a straight spine from its root with barbs on both sides.
    public struct Needle: Equatable, Sendable {
        /// Where the needle stands on the outline.
        public let root: Vector2
        /// The spine's direction in radians.
        public let angle: Double
        /// The spine's length.
        public let length: Double
        /// The barbs, from the root toward the tip, left then right at each
        /// station.
        public let barbs: [Barb]

        public init(root: Vector2, angle: Double, length: Double, barbs: [Barb]) {
            self.root = root
            self.angle = angle
            self.length = max(length, 0)
            self.barbs = barbs
        }

        /// The spine's far end.
        public var tip: Vector2 { root + Vector2(angle: angle, length: length) }
        /// The spine as a two-point stroke.
        public var spine: [Vector2] { [root, tip] }
        /// The spine and every barb, each a stroke.
        public var strokes: [[Vector2]] { [spine] + barbs.map(\.points) }
    }

    /// The needles, in order along the outline.
    public let needles: [Needle]

    public init(needles: [Needle]) {
        self.needles = needles
    }

    /// Every spine and barb, for a loop that only strokes.
    public var strokes: [[Vector2]] { needles.flatMap(\.strokes) }
    /// Where the needles stand.
    public var roots: [Vector2] { needles.map(\.root) }

    /// How far up a needle its first barb sits, as a fraction of its length;
    /// the base below it is bare.
    public static let barbStart = 0.25
    /// A barb's length at the root's station, as a fraction of the needle,
    /// never past `barbCap` barb spacings; the barbs shorten linearly from
    /// there to nothing at the tip.
    public static let barbReach = 0.3
    /// The longest a barb grows, in barb spacings.
    public static let barbCap = 2.5

    /// The barb law: the distances along a needle of `length` at which it
    /// carries a pair of barbs, `barbStart` of the way up and then `spacing`
    /// apart, stopping half a spacing short of the tip.
    public static func barbStations(length: Double, spacing: Double) -> [Double] {
        guard length > 0, spacing > 0 else { return [] }
        var stations: [Double] = []
        var d = barbStart * length
        while d <= length - spacing * 0.5 {
            stations.append(d)
            d += spacing
        }
        return stations
    }

    // MARK: - Growing

    /// Frost grown along one outline, see `grow(along:spacing:length:clump:barbSpacing:barbAngle:side:seed:)`
    /// over a shape.
    public static func grow(along outline: Contour, spacing: Double = 6, length: Double = 40, clump: Double = 0.5,
                            barbSpacing: Double = 5, barbAngle: Double = .pi / 3, side: Side = .outside,
                            seed: Int = 0) -> Frost {
        grow(along: [outline], inside: outline.isClosed ? { outline.contains($0) } : nil,
             spacing: spacing, length: length, clump: clump, barbSpacing: barbSpacing, barbAngle: barbAngle,
             side: side, seed: seed)
    }

    /// Frost grown along every contour of a shape. The needles stand `spacing`
    /// apart along each outline, pointing away from it on `side`, each
    /// tilted up to a tenth of a turn either way. A needle's length is
    /// `length` scaled by a mix of a slow noise along the outline and a draw
    /// of its own (`clump` weights the noise, so at 1 long needles come in
    /// runs and at 0 every needle draws alone), squared so most needles are
    /// short, between a sixth and the whole of `length`. Its barbs follow
    /// `barbStations(length:spacing:)` with `barbSpacing`, lean forward
    /// `barbAngle` off the spine (a tenth of a turn of jitter), and reach
    /// `barbReach` of the needle at the root's station, never past `barbCap`
    /// spacings, shrinking to nothing at the tip. The same seed grows the
    /// same frost.
    public static func grow(along shape: Shape, spacing: Double = 6, length: Double = 40, clump: Double = 0.5,
                            barbSpacing: Double = 5, barbAngle: Double = .pi / 3, side: Side = .outside,
                            seed: Int = 0) -> Frost {
        grow(along: shape.contours, inside: { shape.contains($0) },
             spacing: spacing, length: length, clump: clump, barbSpacing: barbSpacing, barbAngle: barbAngle,
             side: side, seed: seed)
    }

    private static func grow(along contours: [Contour], inside: ((Vector2) -> Bool)?, spacing: Double,
                             length: Double, clump: Double, barbSpacing: Double, barbAngle: Double, side: Side,
                             seed: Int) -> Frost {
        let spacing = max(spacing, 0.5)
        let length = max(length, 0)
        let clump = min(max(clump, 0), 1)
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed)))
        let fields = NoiseFields(seed: seed)
        var needles: [Needle] = []
        var walked = 0.0

        for contour in contours {
            let outline = contour.resampled(spacing: spacing)
            let points = outline.points
            guard points.count >= 2 else { continue }
            let probe = max(spacing * 0.5, 1)
            for (i, root) in points.enumerated() {
                let before: Vector2
                let after: Vector2
                if outline.isClosed {
                    before = points[(i + points.count - 1) % points.count]
                    after = points[(i + 1) % points.count]
                } else {
                    before = points[max(i - 1, 0)]
                    after = points[min(i + 1, points.count - 1)]
                }
                let tangent = after - before
                guard tangent.lengthSquared > 1e-12 else { continue }
                var outward = tangent.normalized.perpendicular
                if let inside, inside(root + outward * probe) { outward = -outward }

                let u = walked + Double(i) * spacing
                let slow = fields.noise(u / (length * 1.5 + 1e-6) + 3.7)
                let directions: [Vector2]
                switch side {
                case .outside: directions = [outward]
                case .inside: directions = [-outward]
                case .both: directions = [outward, -outward]
                }
                for direction in directions {
                    let draw = Double.random(in: 0 ... 1, using: &rng)
                    let mix = clump * slow + (1 - clump) * draw
                    let needleLength = length * (0.15 + 0.85 * mix * mix)
                    let angle = direction.angle + Double.random(in: -0.2 ... 0.2, using: &rng)
                    needles.append(needle(root: root, angle: angle, length: needleLength,
                                          barbSpacing: barbSpacing, barbAngle: barbAngle, using: &rng))
                }
            }
            walked += outline.length + spacing * 7
        }
        return Frost(needles: needles)
    }

    /// One needle under the barb law.
    private static func needle<R: RandomNumberGenerator>(root: Vector2, angle: Double, length: Double,
                                                         barbSpacing: Double, barbAngle: Double,
                                                         using rng: inout R) -> Needle {
        let axis = Vector2(angle: angle)
        var barbs: [Barb] = []
        for d in barbStations(length: length, spacing: barbSpacing) {
            let station = d / length
            let base = root + axis * d
            for side in [1, -1] {
                let lean = barbAngle + Double.random(in: -0.17 ... 0.17, using: &rng)
                let reach = min(length * barbReach, barbSpacing * barbCap) * (1 - station)
                    * Double.random(in: 0.8 ... 1, using: &rng)
                let tip = base + Vector2(angle: angle + Double(side) * lean, length: reach)
                barbs.append(Barb(base: base, tip: tip, station: station, side: side))
            }
        }
        return Needle(root: root, angle: angle, length: length, barbs: barbs)
    }
}
