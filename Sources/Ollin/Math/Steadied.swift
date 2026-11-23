import Foundation

/// A thing found in a picture that can be held steady from one frame to the
/// next: a detector's box, a rectangle's four corners, a blob a sketch found
/// itself. It says where it is as points and can be made again at others, and
/// that is all `@Steadied` needs to follow it and smooth it.
///
/// `Rectangle` conforms, and so do the vision detectors' results. A type of
/// your own conforms in a few lines:
///
/// ```swift
/// struct Blob: Steadiable {
///     var center: Vector2
///     var radius: Double
///
///     var steadyPoints: [Vector2] { [center - Vector2(radius, radius), center + Vector2(radius, radius)] }
///     func steadied(at points: [Vector2]) -> Blob {
///         Blob(center: (points[0] + points[1]) * 0.5, radius: (points[1].x - points[0].x) / 2)
///     }
/// }
/// ```
public protocol Steadiable: Sendable {
    /// Where the thing is, as points in a fixed order: two opposite corners
    /// for a box, an outline's corners in turn for anything else. The units
    /// are the type's own (pixels, or a share of the picture), as long as
    /// every finding of the type uses the same ones and the same count.
    var steadyPoints: [Vector2] { get }

    /// How sure the finder is of it, from 0 to 1. A type with no such number
    /// leaves the default, 1.
    var steadyConfidence: Double { get }

    /// The same thing with its points moved to `points`: as many as
    /// `steadyPoints` gave, in the same order.
    func steadied(at points: [Vector2]) -> Self

    /// The settings that suit findings of this type, which `@Steadied` and
    /// `Steadier` start from. A type whose finder behaves in a way of its own
    /// says so here, once, so every sketch that steadies it starts right; the
    /// default is `Steadiness()`.
    static var steadiness: Steadiness { get }
}

public extension Steadiable {
    var steadyConfidence: Double { 1 }
    static var steadiness: Steadiness { Steadiness() }
}

/// How found things are held steady: how long before one appears and after
/// it is gone, what counts as the same thing, and how hard its points are
/// smoothed. `@Steadied` and `Steadier` take one, and each `Steadiable` type
/// gives the one that suits its finder.
public struct Steadiness: Sendable, Equatable {

    /// How long a thing must be found, without a break, before it appears, in
    /// seconds. `0` shows a thing the frame it is found. Longer keeps out
    /// what a finder sees for a frame or two and never again.
    public var appearDelay: Double

    /// How long a thing stays after it was last found, in seconds, held where
    /// it was. It covers the frames a finder misses a thing that is still
    /// there, and it is also how long a thing that has left hangs on.
    public var holdTime: Double

    /// The confidence a finding needs to start a new thing.
    public var minConfidence: Double

    /// The confidence a finding needs to continue a thing already there,
    /// lower than `minConfidence`, so a thing whose confidence dips stays and
    /// a faint guess never appears. Fainter findings are ignored.
    public var minKeptConfidence: Double

    /// The least overlap at which a finding is taken for a thing that is
    /// not showing yet, as the area the two boxes share over the area they
    /// cover together, 0 to 1. With `appearDelay` it is what a thing has to
    /// get through to appear: found again and again in nearly the same place.
    /// High keeps findings that only pile up in one place from being taken
    /// for one thing that hops.
    public var minOverlap: Double

    /// The least overlap at which a finding is taken for a thing that is
    /// showing. No higher than `minOverlap`, since a thing that has earned
    /// its place may be followed more loosely than it was admitted: low
    /// follows a thing that moves far between two findings, or whose box
    /// changes shape.
    public var minKeptOverlap: Double

    /// The smoothing's cutoff at rest, in Hz. Lower holds a still thing
    /// stiller and follows a slow one later.
    public var minCutoff: Double

    /// How fast the cutoff opens as a thing moves. Higher follows a moving
    /// thing closer and lets more shake through while it moves. It
    /// multiplies the thing's speed counted in its own sizes a second (the
    /// mean of its box's two sides), so it means the same for points in
    /// pixels as for points given as a share of the picture.
    public var beta: Double

    public init(appearDelay: Double = 0.1, holdTime: Double = 0.3,
                minConfidence: Double = 0.5, minKeptConfidence: Double = 0.1,
                minOverlap: Double = 0.2, minKeptOverlap: Double = 0.2,
                minCutoff: Double = 1, beta: Double = 3) {
        self.appearDelay = appearDelay
        self.holdTime = holdTime
        self.minConfidence = minConfidence
        self.minKeptConfidence = minKeptConfidence
        self.minOverlap = minOverlap
        self.minKeptOverlap = minKeptOverlap
        self.minCutoff = minCutoff
        self.beta = beta
    }
}

extension Rectangle: Steadiable {
    public var steadyPoints: [Vector2] { [Vector2(x, y), Vector2(x + width, y + height)] }

    public func steadied(at points: [Vector2]) -> Rectangle {
        guard points.count == 2 else { return self }
        return Rectangle(x: points[0].x, y: points[0].y,
                         width: points[1].x - points[0].x, height: points[1].y - points[0].y)
    }
}

/// One found thing as `Steadier` holds it: the same thing from frame to
/// frame, at a place that does not shake.
public struct Steady<Thing: Steadiable>: Identifiable, Sendable {
    /// The thing's number, which it keeps for as long as it lasts. Numbers
    /// start at 1 and count the things that have appeared, so `id` picks a
    /// color or a name that stays with the thing.
    public let id: Int

    /// The thing at its steadied place: the newest finding, moved.
    public let value: Thing

    /// The thing as it was last found, shake and all.
    public let found: Thing

    /// Seconds since it was first found.
    public let age: Double

    /// Seconds since it was last found: `0` while it is being found, and
    /// counting up while it is held through a gap. A sketch that fades a
    /// thing out rather than dropping it reads this against `holdTime`.
    public let unseenFor: Double
}

/// Holds found things steady. Each frame it is handed what a detector found
/// and hands back the same things matched to the ones before, smoothed, each
/// with a number it keeps: a thing has to be found for a moment before it
/// appears, and it stays through a brief gap in the findings.
///
/// `@Steadied` is the form a sketch reaches for; this is the value under it,
/// for a sketch that wants to own the state or run it on a clock of its own:
///
/// ```swift
/// var steadier = Steadier<Rectangle>()
/// let things = steadier.steady(found, deltaTime: deltaTime)
/// ```
///
/// Findings are matched to the things already held by how much their boxes
/// overlap, all at once, so that the pairing with the most overlap in total
/// wins; `minOverlap` is the least overlap that counts as the same thing
/// before it shows, and `minKeptOverlap` once it does. A thing's box is first
/// carried a little way on at the speed it was going, which is what keeps two
/// things that cross from trading places.
/// Confident findings (`minConfidence` and up) are matched first and are the
/// only ones that start a new thing. Fainter ones, down to
/// `minKeptConfidence`, can then continue a thing already there and are
/// otherwise let go.
///
/// A new thing is shown once it has been found without a break for
/// `appearDelay` seconds; one that misses a frame before then is dropped
/// unseen. A thing that is showing and goes unfound stays where it was for
/// `holdTime` seconds, and comes back as itself if it is found again in that
/// time.
///
/// Every point of a thing is smoothed by a `OneEuroFilter` of its own, tuned
/// by `minCutoff` and `beta` as `@Smoothed` is, with the thing's speed
/// counted in its own sizes. All eight settings are one `Steadiness`.
///
/// Implemented from the published methods and not ported: matching by
/// overlap with an optimal pairing, a probation before a thing counts, and a
/// thing carried on at its speed before it is matched (Bewley and others,
/// 2016), and the two passes by confidence (Zhang and others, 2021). The
/// pairing is `Matching.optimal`.
public struct Steadier<Thing: Steadiable>: Sendable {

    /// The settings, which may be changed between frames.
    public var steadiness: Steadiness

    /// A steadier with `steadiness`, which is the type's own unless given.
    public init(_ steadiness: Steadiness = Thing.steadiness) {
        self.steadiness = steadiness
    }

    /// The things that are showing, oldest first.
    public private(set) var things: [Steady<Thing>] = []

    private struct Track: Sendable {
        /// 0 until the thing appears.
        var id = 0
        var found: Thing
        /// The points as last found, in the track's own order.
        var foundPoints: [Vector2]
        var filters: [OneEuroFilter<Vector2>]
        /// The steadied points, in the track's own order.
        var points: [Vector2]
        /// How many places round the newest finding's points sit from the
        /// track's: an outline's first corner is whichever the finder calls
        /// first, and that can change from one frame to the next.
        var turn = 0
        var seenFor = 0.0
        var age = 0.0
        var unseenFor = 0.0
        /// Seconds since the filters last took a sample.
        var sinceSample = 0.0
        /// How fast the thing's middle is going, in the points' units a
        /// second, from one changed finding to the next, and the seconds
        /// since the findings last changed.
        var velocity = Vector2.zero
        var sinceMoved = 0.0
    }

    /// How far ahead a thing's motion is carried when findings are matched to
    /// it, in seconds. Enough for two things that cross to stay themselves,
    /// and short, since a thing in the open rarely keeps its speed for long.
    private static var reach: Double { 0.1 }

    private var tracks: [Track] = []
    private var nextID = 1

    /// One frame: `found` is everything the detector has right now, and
    /// `deltaTime` the seconds since the last call. Returns the things that
    /// are showing, oldest first, which `things` then holds until the next
    /// call.
    ///
    /// Call it every frame, with the same findings again when the detector
    /// has nothing newer: the delays are measured in seconds, so a detector
    /// slower than the sketch costs nothing but the steps between its
    /// answers, which the smoothing rounds off.
    @discardableResult
    public mutating func steady(_ found: [Thing], deltaTime: Double) -> [Steady<Thing>] {
        let dt = max(0, deltaTime)
        let (appearDelay, holdTime) = (steadiness.appearDelay, steadiness.holdTime)
        let (minConfidence, minKeptConfidence) = (steadiness.minConfidence, steadiness.minKeptConfidence)
        let (minOverlap, minCutoff, beta) = (steadiness.minOverlap, steadiness.minCutoff, steadiness.beta)
        let minKeptOverlap = Swift.min(steadiness.minKeptOverlap, minOverlap)
        let boxes = found.map { Self.box(of: $0.steadyPoints) }
        var confident: [Int] = [], faint: [Int] = []
        for (index, thing) in found.enumerated() {
            let confidence = thing.steadyConfidence
            if confidence >= minConfidence {
                confident.append(index)
            } else if confidence >= minKeptConfidence {
                faint.append(index)
            }
        }

        // The confident findings against every thing held, then the faint
        // ones against the things still unmatched.
        var match = [Int?](repeating: nil, count: tracks.count)
        var taken = Set<Int>()
        for candidates in [confident, faint] where !candidates.isEmpty {
            let open = tracks.indices.filter { match[$0] == nil }
            guard !open.isEmpty else { break }
            let overlap = open.map { index in
                // Where the thing was last found, and where it would be by now
                // at the speed it was going. Either may say it is the same
                // thing, since a speed read off shaking findings is rough; the
                // pairing goes by both, which is what tells two things that
                // cross apart.
                let track = tracks[index]
                let ahead = track.velocity * Swift.min(track.sinceMoved + dt, Self.reach)
                let last = Self.box(of: track.foundPoints)
                let expected = (min: last.min + ahead, max: last.max + ahead)
                // It takes more to be admitted than to stay.
                let least = track.id == 0 ? minOverlap : minKeptOverlap
                return candidates.map { candidate in
                    let here = Self.overlap(last, boxes[candidate])
                    let there = Self.overlap(expected, boxes[candidate])
                    return Swift.max(here, there) >= least ? (here + there) / 2 : 0
                }
            }
            // The most overlap in total is the least of what is missing from
            // it; a pair that may not be made costs infinity, which forbids it.
            let pairing = Matching.optimal(costs: overlap.map { row in row.map { $0 > 0 ? 1 - $0 : .infinity } })
            for pair in pairing.pairs {
                match[open[pair.first]] = candidates[pair.second]
                taken.insert(candidates[pair.second])
            }
        }

        var kept: [Track] = []
        kept.reserveCapacity(tracks.count + confident.count)
        for (index, var track) in tracks.enumerated() {
            track.age += dt
            track.sinceSample += dt
            track.sinceMoved += dt
            if let foundIndex = match[index] {
                let thing = found[foundIndex]
                let points = thing.steadyPoints
                guard points.count == track.points.count else { continue }   // not the thing it was
                track.turn = Self.turn(of: points, onto: track.foundPoints)
                let count = points.count
                // A finding read again while the detector has nothing newer
                // says nothing about speed; a changed one does.
                var moved = Vector2.zero
                var changed = false
                for i in 0..<count {
                    let point = points[(i + track.turn) % count]
                    if point != track.foundPoints[i] { changed = true }
                    moved = moved + (point - track.foundPoints[i])
                }
                if changed, track.sinceMoved > 0 {
                    let velocity = moved * (1 / (Double(count) * track.sinceMoved))
                    track.velocity = track.velocity + (velocity - track.velocity) * 0.5
                    track.sinceMoved = 0
                }
                // A speed is counted in the thing's own sizes a second, so the
                // settings mean the same in pixels as in shares of the picture.
                let found = boxes[foundIndex]
                let size = Swift.max(((found.max.x - found.min.x) + (found.max.y - found.min.y)) / 2, .leastNormalMagnitude)
                for i in 0..<count {
                    let point = points[(i + track.turn) % count]
                    track.foundPoints[i] = point
                    track.filters[i].minCutoff = minCutoff
                    track.filters[i].beta = beta / size
                    track.points[i] = track.filters[i].filter(point, deltaTime: track.sinceSample)
                }
                track.sinceSample = 0
                track.found = thing
                track.unseenFor = 0
                track.seenFor += dt
                if track.id == 0, track.seenFor >= appearDelay {
                    track.id = nextID
                    nextID += 1
                }
                kept.append(track)
            } else if track.id != 0 {
                // Showing and unfound: held where it was, for a while.
                track.unseenFor += dt
                if track.unseenFor <= holdTime { kept.append(track) }
            }
            // Not yet showing and unfound: dropped unseen.
        }

        // A confident finding that matched nothing starts a thing.
        for index in confident where !taken.contains(index) {
            let points = found[index].steadyPoints
            guard !points.isEmpty else { continue }
            var track = Track(found: found[index], foundPoints: points,
                              filters: points.map { point in
                                  var filter = OneEuroFilter<Vector2>(minCutoff: minCutoff, beta: beta)
                                  filter.jump(to: point)
                                  return filter
                              },
                              points: points)
            if appearDelay <= 0 {
                track.id = nextID
                nextID += 1
            }
            kept.append(track)
        }
        tracks = kept

        things = tracks.filter { $0.id != 0 }.sorted { $0.id < $1.id }.map { track in
            // Back in the order the newest finding gave its points in.
            let count = track.points.count
            var points = track.points
            for i in 0..<count { points[(i + track.turn) % count] = track.points[i] }
            return Steady(id: track.id, value: track.found.steadied(at: points), found: track.found,
                          age: track.age, unseenFor: track.unseenFor)
        }
        return things
    }

    /// Forgets every thing held. The next findings start from nothing, and
    /// the numbers start again at 1.
    public mutating func reset() {
        tracks = []
        things = []
        nextID = 1
    }

    // MARK: Geometry

    private static func box(of points: [Vector2]) -> (min: Vector2, max: Vector2) {
        guard var low = points.first else { return (.zero, .zero) }
        var high = low
        for point in points.dropFirst() {
            low = Vector2(Swift.min(low.x, point.x), Swift.min(low.y, point.y))
            high = Vector2(Swift.max(high.x, point.x), Swift.max(high.y, point.y))
        }
        return (low, high)
    }

    /// Intersection over union of two boxes, 0 to 1.
    private static func overlap(_ a: (min: Vector2, max: Vector2), _ b: (min: Vector2, max: Vector2)) -> Double {
        let width = Swift.min(a.max.x, b.max.x) - Swift.max(a.min.x, b.min.x)
        let height = Swift.min(a.max.y, b.max.y) - Swift.max(a.min.y, b.min.y)
        guard width > 0, height > 0 else { return 0 }
        let shared = width * height
        let total = (a.max.x - a.min.x) * (a.max.y - a.min.y) + (b.max.x - b.min.x) * (b.max.y - b.min.y) - shared
        return total > 0 ? shared / total : 0
    }

    /// How many places round `points` must be read from for them to lie
    /// nearest `reference`, point for point. Two points are a box's corners
    /// and never turn.
    private static func turn(of points: [Vector2], onto reference: [Vector2]) -> Int {
        let count = points.count
        guard count > 2, reference.count == count else { return 0 }
        var best = 0
        var bestDistance = Double.infinity
        for turn in 0..<count {
            var distance = 0.0
            for i in 0..<count {
                distance += (points[(i + turn) % count] - reference[i]).lengthSquared
            }
            if distance < bestDistance {
                bestDistance = distance
                best = turn
            }
        }
        return best
    }
}

/// Found things, held steady. Assign what a detector found every frame and
/// read back the same things without the shake: each matched to the one
/// before it and smoothed, shown only once it has been found for a moment,
/// and kept through a brief gap in the findings.
///
/// ```swift
/// final class Table: Sketch {
///     @Steadied var objects: [Detection] = []
///
///     override func draw() {
///         guard let view = drawFrame(feed) else { return }
///         objects = detector.objects              // what was found, as found
///         for object in objects {                 // the same things, steady
///             drawRect(object.bounds(in: view))
///         }
///     }
/// }
/// ```
///
/// `$objects` is the wrapper itself. Its `things` carry what the plain list
/// does not: a number each thing keeps while it lasts, and how long it has
/// gone unfound.
///
/// ```swift
/// for thing in $objects.things {
///     stroke(colors[thing.id % colors.count])
///     drawRect(thing.value.bounds(in: view))
/// }
/// ```
///
/// It works on anything `Steadiable`: the vision detectors' boxes and
/// corners, a `Rectangle`, a type of the sketch's own. The sketch steps it
/// once a frame, before `draw()`, so what is read during a frame is what was
/// assigned the frame before, steadied; a property a sketch declares needs
/// nothing called. The delays and the smoothing start from the type's own
/// settings, can be given where the property is declared
/// (`@Steadied(holdTime: 0.5)`), and can be changed through
/// `$objects.steadiness` while it runs; `Steadiness` documents each of them.
@propertyWrapper
public final class Steadied<Thing: Steadiable>: FrameAdvancing {
    private var steadier: Steadier<Thing>
    private var input: [Thing]

    /// The steadied things, oldest first; assigning sets what was found this
    /// frame.
    public var wrappedValue: [Thing] {
        get { steadier.things.map(\.value) }
        set { input = newValue }
    }

    /// The wrapper itself, via `$objects`: the things with their numbers, the
    /// findings as assigned, and the settings.
    public var projectedValue: Steadied<Thing> { self }

    /// The things that are showing, oldest first, each with its number.
    public var things: [Steady<Thing>] { steadier.things }

    /// What was last assigned, before steadying.
    public var rawValue: [Thing] { input }

    /// The settings, which may be changed while the sketch runs:
    /// `$objects.steadiness.holdTime = 0.5`.
    public var steadiness: Steadiness {
        get { steadier.steadiness }
        set { steadier.steadiness = newValue }
    }

    /// Each setting is the type's own (`Thing.steadiness`) unless given.
    /// `Steadiness` documents them.
    public init(wrappedValue: [Thing] = [],
                appearDelay: Double = Thing.steadiness.appearDelay,
                holdTime: Double = Thing.steadiness.holdTime,
                minConfidence: Double = Thing.steadiness.minConfidence,
                minKeptConfidence: Double = Thing.steadiness.minKeptConfidence,
                minOverlap: Double = Thing.steadiness.minOverlap,
                minKeptOverlap: Double = Thing.steadiness.minKeptOverlap,
                minCutoff: Double = Thing.steadiness.minCutoff,
                beta: Double = Thing.steadiness.beta) {
        steadier = Steadier(Steadiness(appearDelay: appearDelay, holdTime: holdTime, minConfidence: minConfidence,
                                       minKeptConfidence: minKeptConfidence, minOverlap: minOverlap,
                                       minKeptOverlap: minKeptOverlap, minCutoff: minCutoff, beta: beta))
        input = wrappedValue
    }

    /// Forgets every thing held and what was assigned; the numbers start
    /// again at 1.
    public func reset() {
        input = []
        steadier.reset()
    }

    /// One frame of steadying against the latest findings. Called by the
    /// sketch each frame.
    package func advance(by dt: Double) {
        steadier.steady(input, deltaTime: dt)
    }
}
