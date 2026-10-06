//  Recreation after Kazuya Sakai - the Ondulaciones paintings of 1975 and
//  1976, read from Filles de Kilimanjaro III (Miles Davis) (1976, acrylic on
//  canvas, 200.6 x 200 cm) and the untitled screenprint of 1975 (55.9 x 55.9
//  cm), both at the Blanton Museum of Art, The University of Texas at
//  Austin, and from the canvases of the series the Museo de Arte Moderno,
//  Mexico City, hung in 2025. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist or his estate.
//  https://blanton.emuseum.com/objects/15134/filles-de-kilimanjaro-iii-miles-davis
//  https://athenaeumreview.org/essay/kazuya-sakai-in-texas/
//  https://inba.gob.mx/prensa/21899/el-museo-de-arte-moderno-presenta-la-exposicion-kazuya-sakai-ondulaciones
//
//  An original Ollin interpretation, written from the paintings. Nothing was
//  ported: the work is acrylic laid flat on canvas, one band up to the next.

import Foundation
import Ollin

/// The undulations (Kazuya Sakai, Mexico City, 1975 and 1976). A ribbon of
/// parallel bands, each a flat color with a hard edge, comes into the panel
/// straight from one side, wraps a disc in concentric arcs, lets go of it
/// and wraps the next one the other way round, and so on across the panel
/// until it runs straight off another side. Every disc sits in the middle
/// of its wrap, a soft gradient on the 1976 canvases and plain white on the
/// print, the ground is one flat color, and the paintings carry the names
/// of the music he played on the radio: Miles Davis, Takemitsu, Xenakis,
/// Babbitt, Steve Reich. He had just published a book of prints after Ogata
/// Korin, whose "repeated curves, circles, and sinuous lines that flow
/// without beginning or apparent end" he said he admired, and the ribbon is
/// that line.
///
/// This sketch keeps the rule and deals the route. The ribbon's centerline
/// is a chain of circles and straight runs: a run in from the left edge or
/// up from the bottom, tangent to the first circle; from each circle to the
/// next either an S, where the two circles touch and the ribbon changes
/// hands, or a straight run to a circle it goes round the same way; and a
/// run out to an edge at the end. Every band edge is the centerline moved
/// across by its own offset, which on a circle is a concentric arc and on a
/// run a parallel line, and neighbors share their edge point for point, so
/// the fills meet with nothing between them. `look` picks the palette and
/// its band order, read from the paintings; `stations` is how many turns
/// the route makes, some of them around nothing on the print's look;
/// `bandWidth` is the thinnest band, `discRadius` the discs, `gap` the
/// ground between a disc and its first band, and `winding` how far round
/// each disc the ribbon goes. The seed deals the route, the disc sizes and
/// colors, and where the ribbon comes in and goes out.
///
/// Over one cycle of `seconds` the ribbon is laid down from its entry to
/// its exit, holds, and is taken back the way it came, each disc appearing
/// as the ribbon reaches it, which is also the export loop.
///
/// Every band exports as one closed outline, so `--export-svg` gives the
/// panel back as the regions the paint covers, and every disc as a circle.
@main
final class Ondulaciones: Sketch {
    enum Look: String, CaseIterable, ParamOption { case kilimanjaro, serigrafia, violeta }

    @Param(icon: "paintpalette") var look = Look.kilimanjaro
    @Param(2 ... 9, icon: "circle.grid.cross") var stations = 6
    @Param(2 ... 12, icon: "arrow.left.and.right") var bandWidth = 4.0
    @Param(24 ... 120, icon: "circle") var discRadius = 60.0
    @Param(0 ... 3, icon: "circle.dashed") var gap = 0.6
    @Param(0 ... 1, icon: "arrow.turn.up.right") var winding = 0.5
    @Param(4 ... 60, icon: "clock") var seconds = 12.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { seconds }

    /// One band of the ribbon: its color and its width in units of the thinnest.
    private struct Band {
        var color: Color
        var width: Double
    }

    /// A disc: a radial gradient from the core to the rim, or flat when they agree.
    private struct Disc {
        var core: Color
        var rim: Color
    }

    private struct Paints {
        var ground: Color
        var bands: [Band]
        var discs: [Disc]
        /// The discs' size against `discRadius`.
        var discScale: Double
        /// The chance a station is a turn around nothing.
        var emptyTurns: Double
    }

    private func paints(for look: Look) -> Paints {
        switch look {
        case .kilimanjaro:
            // Filles de Kilimanjaro III: a dark green ground, the ribbon red,
            // yellow, indigo, black, violet, a wide navy and red again, and
            // discs that glow from a bright core to a saturated rim.
            let red = Color(hex: 0xE62E08)
            return Paints(ground: Color(hex: 0x0A4A12), bands: [
                Band(color: red, width: 3.8),
                Band(color: Color(hex: 0xFFF200), width: 1),
                Band(color: Color(hex: 0x2A0A5E), width: 3.4),
                Band(color: Color(hex: 0x0C1C0A), width: 2.4),
                Band(color: Color(hex: 0x9A38A0), width: 2.4),
                Band(color: Color(hex: 0x0B0D96), width: 8),
                Band(color: red, width: 3.8),
            ], discs: [
                Disc(core: Color(hex: 0xFF4A1E), rim: Color(hex: 0xB01478)),
                Disc(core: Color(hex: 0x5CCBFF), rim: Color(hex: 0x0C34C8)),
                Disc(core: Color(hex: 0xFFC41E), rim: Color(hex: 0xFF5A08)),
                Disc(core: Color(hex: 0xFF7A20), rim: Color(hex: 0x1E9C3E)),
                Disc(core: Color(hex: 0xFF3C2E), rim: Color(hex: 0x6A2AA6)),
            ], discScale: 1, emptyTurns: 0)
        case .serigrafia:
            // The 1975 print: orange paper, the ribbon navy, white,
            // blue-violet, a thread of the paper, navy and red, white discs,
            // and turns around nothing on the way.
            let navy = Color(hex: 0x2A2C6A)
            let paper = Color(hex: 0xF25C10)
            let white = Color(hex: 0xFDFBF4)
            return Paints(ground: paper, bands: [
                Band(color: navy, width: 7),
                Band(color: white, width: 1),
                Band(color: Color(hex: 0x4A4690), width: 4.2),
                Band(color: paper, width: 2.8),
                Band(color: navy, width: 2.4),
                Band(color: Color(hex: 0xD8081E), width: 9),
            ], discs: [Disc(core: white, rim: white)], discScale: 0.6, emptyTurns: 0.35)
        case .violeta:
            // The purple canvases of the series: a lilac band on one side of
            // the ribbon, then white, orange, pink, blues, yellow and green,
            // and flat discs in lilac, blue, red, orange and green.
            return Paints(ground: Color(hex: 0x4B2E8E), bands: [
                Band(color: Color(hex: 0xAE93DC), width: 5),
                Band(color: Color(hex: 0xF4ECF6), width: 1),
                Band(color: Color(hex: 0xDC6418), width: 5),
                Band(color: Color(hex: 0xE45C8E), width: 3.5),
                Band(color: Color(hex: 0x2A4CC0), width: 1.2),
                Band(color: Color(hex: 0x30A6E0), width: 2.5),
                Band(color: Color(hex: 0x148C8A), width: 1.7),
                Band(color: Color(hex: 0xECD83C), width: 1.2),
                Band(color: Color(hex: 0x5CB030), width: 1.7),
                Band(color: Color(hex: 0x1E58C8), width: 4.5),
            ], discs: [
                Disc(core: Color(hex: 0xB9A0E6), rim: Color(hex: 0xB9A0E6)),
                Disc(core: Color(hex: 0x2040B8), rim: Color(hex: 0x2040B8)),
                Disc(core: Color(hex: 0xCC2A1E), rim: Color(hex: 0xCC2A1E)),
                Disc(core: Color(hex: 0xE8781E), rim: Color(hex: 0xE8781E)),
                Disc(core: Color(hex: 0x3CB04C), rim: Color(hex: 0x3CB04C)),
            ], discScale: 0.9, emptyTurns: 0.3)
        }
    }

    // MARK: - The route

    /// One turn of the route: the circle the ribbon's centerline follows,
    /// which way round (clockwise is +1 with y down), the angle it arrives
    /// at and how far it goes, and the disc in the middle, if there is one.
    private struct Station {
        var center: Vector2
        var radius: Double
        var sense: Double
        var arrival: Double
        var sweep = 0.0
        var disc: Disc?
        var discRadius: Double
    }

    /// A piece of the centerline: a straight run, or the arc of a station.
    private enum Leg {
        case run(Vector2, Vector2)
        case arc(Int)
    }

    private struct Route {
        var stations: [Station] = []
        var legs: [Leg] = []
        /// Where along the centerline each station's arc begins.
        var arcStarts: [Double] = []
        var length = 0.0
    }

    private static let twoPi = 2 * Double.pi

    /// The angle swept going from `a` round to `b` in `sense`, in 0 ..< 2 pi.
    private static func turn(from a: Double, to b: Double, sense: Double) -> Double {
        var d = ((b - a) * sense).truncatingRemainder(dividingBy: twoPi)
        if d < 0 { d += twoPi }
        return d
    }

    private static func radial(_ theta: Double) -> Vector2 { Vector2(cos(theta), sin(theta)) }

    /// The direction of travel at angle `theta` on a circle gone round in `sense`.
    private static func heading(_ theta: Double, sense: Double) -> Vector2 {
        sense > 0 ? Vector2(-sin(theta), cos(theta)) : Vector2(sin(theta), -cos(theta))
    }

    private static func distance(_ p: Vector2, toSegment a: Vector2, _ b: Vector2) -> Double {
        let d = b - a
        let len2 = d.x * d.x + d.y * d.y
        if len2 == 0 { return (p - a).length }
        let t = min(max(((p - a).x * d.x + (p - a).y * d.y) / len2, 0), 1)
        return (p - (a + d * t)).length
    }

    /// The distance between two segments: zero when they cross.
    private static func distance(_ a: Vector2, _ b: Vector2, _ c: Vector2, _ d: Vector2) -> Double {
        func side(_ p: Vector2, _ q: Vector2, _ r: Vector2) -> Double {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        let s1 = side(a, b, c), s2 = side(a, b, d), s3 = side(c, d, a), s4 = side(c, d, b)
        if s1 * s2 < 0 && s3 * s4 < 0 { return 0 }
        return min(distance(c, toSegment: a, b), distance(d, toSegment: a, b),
                   distance(a, toSegment: c, d), distance(b, toSegment: c, d))
    }

    /// Deals the chain of circles and runs for this seed. The ribbon comes
    /// in from the left or up from the bottom, and the chain climbs toward
    /// the corner across the panel, each turn aimed a little to one side of
    /// that line, the side set by the sense, which is what makes the wraps
    /// long; a link is an S (the circles touch and the sense flips), an S
    /// with a straight middle (a run along the tangent to a circle across
    /// it), or a run to a circle gone round the same way. Every turn is
    /// placed inside the panel clear of every earlier turn and run, and the
    /// route leaves from the last turn that can let go toward an edge
    /// without crossing itself.
    private func dealRoute(_ paint: Paints, ribbon: Double) -> Route {
        let half = ribbon / 2
        let margin = bandWidth
        var route = Route()
        var runs: [(Vector2, Vector2)] = []
        /// The index in `runs` of the run that arrives at each station, if one does.
        var arriving: [Int?] = []
        /// How many legs the route had once each station was placed.
        var legCounts: [Int] = []

        func dealTurn() -> (disc: Disc?, discRadius: Double, radius: Double) {
            if random(1) < paint.emptyTurns {
                return (nil, 0, bandWidth * random(1, 3) + half)
            }
            let r = discRadius * paint.discScale * random(0.8, 1.2)
            let disc = paint.discs[Int(random(Double(paint.discs.count)))]
            return (disc, r, r + gap * bandWidth + half)
        }
        func outer(_ s: Station) -> Double { s.radius + half }
        /// Whether run `p`-`q` keeps clear of run `a`-`b`: a ribbon and a
        /// margin apart, or, when `b` and `p` sit on one turn's circle and
        /// the arc joins them, not crossing and each run's far end clear of
        /// the other, since a long wrap can send a run back across the one
        /// that came in.
        func clear(_ a: Vector2, _ b: Vector2, _ p: Vector2, _ q: Vector2, joined: Bool) -> Bool {
            if !joined { return Self.distance(a, b, p, q) >= ribbon + margin }
            if Self.distance(a, b, p, q) == 0 { return false }
            return Self.distance(a, toSegment: p, q) >= ribbon + margin
                && Self.distance(q, toSegment: a, b) >= ribbon + margin
        }

        // 1. The entry, and the corner the chain climbs toward.
        let fromBottom = random(1) < 0.3
        let sense: Double = random(1) < 0.5 ? 1 : -1
        let first = dealTurn()
        let reach = first.radius + half + margin
        var center0: Vector2
        let theta0: Double
        let goal: Vector2
        if fromBottom {
            let leftSide = random(1) < 0.5
            center0 = Vector2((leftSide ? random(0.2, 0.45) : random(0.55, 0.8)) * width, random(0.55, 0.8) * height)
            theta0 = sense > 0 ? .pi : 0
            goal = Vector2((leftSide ? 0.9 : 0.1) * width, 0.1 * height)
        } else {
            let low = random(1) < 0.6
            center0 = Vector2(random(0.18, 0.35) * width, (low ? random(0.55, 0.82) : random(0.18, 0.45)) * height)
            theta0 = sense > 0 ? -.pi / 2 : .pi / 2
            goal = Vector2(0.9 * width, (low ? 0.1 : 0.9) * height)
        }
        center0 = Vector2(min(max(center0.x, reach), width - reach), min(max(center0.y, reach), height - reach))
        let into = center0 + Self.radial(theta0) * first.radius
        let from = fromBottom ? Vector2(into.x, height + ribbon) : Vector2(-ribbon, into.y)
        route.stations.append(Station(center: center0, radius: first.radius, sense: sense,
                                      arrival: theta0, disc: first.disc, discRadius: first.discRadius))
        route.legs.append(.run(from, into))
        runs.append((from, into))
        arriving.append(0)
        legCounts.append(1)

        // 2. The chain.
        let zig = (10 + 60 * winding) * Double.pi / 180
        for i in 1 ..< max(stations, 1) {
            var placed = false
            for _ in 0 ..< 80 where !placed {
                let prev = route.stations[i - 1]
                let next = dealTurn()
                let kind = random(1)
                let toward = atan2(goal.y - prev.center.y, goal.x - prev.center.x)
                let jitter = random(-0.15, 0.15)
                let depart: Double
                let center: Vector2
                let arrival: Double
                let newSense: Double
                var run: (Vector2, Vector2)?
                if kind < 0.7 {
                    // An S: the circles touch and the sense flips.
                    depart = toward + prev.sense * zig + jitter
                    center = prev.center + Self.radial(depart) * (prev.radius + next.radius)
                    arrival = depart + .pi
                    newSense = -prev.sense
                } else if kind < 0.9 {
                    // An S with a straight middle: the run leaves along the
                    // tangent and the next circle lies across it.
                    depart = toward + prev.sense * random(-.pi / 2, zig) + jitter
                    let p = prev.center + Self.radial(depart) * prev.radius
                    let heading = depart + prev.sense * .pi / 2
                    let q = p + Self.radial(heading) * (random(0.6, 2.5) * ribbon)
                    center = q + Self.radial(depart) * next.radius
                    arrival = depart + .pi
                    newSense = -prev.sense
                    run = (p, q)
                } else {
                    // A run toward the goal to a circle gone round the same
                    // way, set beside the last one along the run.
                    let heading = toward + jitter
                    depart = heading - prev.sense * .pi / 2
                    let p = prev.center + Self.radial(depart) * prev.radius
                    let q = p + Self.radial(heading) * (prev.radius + next.radius + random(2, 6) * bandWidth)
                    center = q - Self.radial(depart) * next.radius
                    arrival = depart
                    newSense = prev.sense
                    run = (p, q)
                }
                let sweep = Self.turn(from: prev.arrival, to: depart, sense: prev.sense)
                guard sweep >= 0.2 * Self.twoPi, sweep <= 0.92 * Self.twoPi else { continue }
                let r = next.radius + half
                guard center.x - r >= margin, center.x + r <= width - margin,
                      center.y - r >= margin, center.y + r <= height - margin else { continue }
                var ok = true
                for (k, s) in route.stations.enumerated() where k != i - 1 && ok {
                    if (s.center - center).length < outer(s) + r + margin { ok = false }
                }
                for (a, b) in runs where ok {
                    if Self.distance(center, toSegment: a, b) < r + half + margin { ok = false }
                }
                if let (p, q) = run, ok {
                    for (k, s) in route.stations.enumerated() where k != i - 1 && ok {
                        if Self.distance(s.center, toSegment: p, q) < outer(s) + half + margin { ok = false }
                    }
                    for (k, (a, b)) in runs.enumerated() where ok {
                        if !clear(a, b, p, q, joined: k == arriving[i - 1]) { ok = false }
                    }
                }
                guard ok else { continue }
                route.stations[i - 1].sweep = sweep
                route.legs.append(.arc(i - 1))
                var arrivingRun: Int?
                if let (p, q) = run {
                    route.legs.append(.run(p, q))
                    runs.append((p, q))
                    arrivingRun = runs.count - 1
                }
                route.stations.append(Station(center: center, radius: next.radius, sense: newSense,
                                              arrival: arrival, disc: next.disc, discRadius: next.discRadius))
                arriving.append(arrivingRun)
                legCounts.append(route.legs.count)
                placed = true
            }
            if !placed { break }
        }

        // 3. The exit: from the last turn with a heading, of the four, whose
        // run to an edge clears every other turn and run, the one with the
        // wrap nearest the dealt one; a turn with none is dropped and the
        // one before it asked.
        let east = Vector2(1, 0), north = Vector2(0, -1), west = Vector2(-1, 0), south = Vector2(0, 1)
        let quarter = Double.pi / 2
        let target = random(0.5, 0.75) * Self.twoPi
        var k = route.stations.count - 1
        while true {
            let s = route.stations[k]
            let keptLegs = Array(route.legs.prefix(legCounts[k]))
            var keptRuns = 0
            for leg in keptLegs { if case .run = leg { keptRuns += 1 } }
            var headings: [(Vector2, Double)] = []
            if s.sense > 0 {
                headings = [(east, -quarter), (north, Double.pi), (west, quarter), (south, 0)]
            } else {
                headings = [(east, quarter), (north, 0), (west, -quarter), (south, Double.pi)]
            }
            var best: (score: Double, sweep: Double, from: Vector2, to: Vector2)?
            var fallback: (sweep: Double, from: Vector2, to: Vector2)?
            for (h, depart) in headings {
                let sweep = Self.turn(from: s.arrival, to: depart, sense: s.sense)
                let p = s.center + Self.radial(depart) * s.radius
                let reach: Double
                if h.x > 0 { reach = width + ribbon - p.x } else if h.x < 0 { reach = p.x + ribbon }
                else if h.y > 0 { reach = height + ribbon - p.y } else { reach = p.y + ribbon }
                let q = p + h * reach
                var ok = sweep >= 0.2 * Self.twoPi && sweep <= 0.95 * Self.twoPi
                for (j, o) in route.stations.prefix(k + 1).enumerated() where j != k && ok {
                    if Self.distance(o.center, toSegment: p, q) < outer(o) + half + margin { ok = false }
                }
                for (j, (a, b)) in runs.prefix(keptRuns).enumerated() where ok {
                    if !clear(a, b, p, q, joined: j == arriving[k]) { ok = false }
                }
                // Leaving toward the goal's side of the panel is preferred.
                let away = (h.x * (goal.x - s.center.x) + h.y * (goal.y - s.center.y)) < 0
                let score = abs(sweep - target) + (away ? Self.twoPi : 0)
                if ok, best == nil || score < best!.score {
                    best = (score, sweep, p, q)
                }
                if fallback == nil || sweep > fallback!.sweep { fallback = (sweep, p, q) }
            }
            if best == nil && k > 0 {
                k -= 1
                continue
            }
            let exit = best.map { ($0.sweep, $0.from, $0.to) } ?? (fallback!.sweep, fallback!.from, fallback!.to)
            route.stations = Array(route.stations.prefix(k + 1))
            route.legs = keptLegs
            route.stations[k].sweep = exit.0
            route.legs.append(.arc(k))
            route.legs.append(.run(exit.1, exit.2))
            break
        }

        // 4. The lengths.
        route.arcStarts = Array(repeating: 0, count: route.stations.count)
        for leg in route.legs {
            switch leg {
            case .run(let a, let b):
                route.length += (b - a).length
            case .arc(let i):
                route.arcStarts[i] = route.length
                route.length += route.stations[i].radius * route.stations[i].sweep
            }
        }
        return route
    }

    // MARK: - The bands

    /// The points of one band edge: the centerline moved across by `offset`
    /// (to the left of travel), followed along the route up to `laid` of its
    /// length. On a run the offset is a parallel line and two points do; on
    /// an arc it is a concentric arc, sampled at the same angles for every
    /// offset so neighboring bands share their edge point for point.
    private func edge(of route: Route, offset: Double, laid: Double, outermost: Double) -> [Vector2] {
        var points: [Vector2] = []
        var sofar = 0.0
        for leg in route.legs {
            switch leg {
            case .run(let a, let b):
                let d = b - a
                let length = d.length
                let u = d / length
                let left = Vector2(u.y, -u.x)
                if points.isEmpty { points.append(a + left * offset) }
                if sofar + length >= laid {
                    points.append(a + u * max(laid - sofar, 0) + left * offset)
                    return points
                }
                points.append(b + left * offset)
                sofar += length
            case .arc(let i):
                let s = route.stations[i]
                let r = s.radius + s.sense * offset
                let length = s.radius * s.sweep
                let n = max(8, Int((s.sweep * (s.radius + outermost) / 2).rounded(.up)))
                let whole = sofar + length <= laid
                let share = whole ? 1 : max(laid - sofar, 0) / length
                let count = whole ? n : max(1, Int((Double(n) * share).rounded(.up)))
                for k in (points.isEmpty ? 0 : 1) ... count {
                    let t = min(Double(k) / Double(n), share)
                    points.append(s.center + Self.radial(s.arrival + s.sense * s.sweep * t) * r)
                }
                if !whole { return points }
                sofar += length
            }
        }
        return points
    }

    private static func smooth(_ x: Double) -> Double {
        let s = min(max(x, 0), 1)
        return s * s * (3 - 2 * s)
    }

    /// How much of the route is on the panel at `phase` of the cycle: laid
    /// over the first half, whole for a fifth, taken back over the rest.
    private static func laidShare(_ phase: Double) -> Double {
        if phase < 0.5 { return smooth(phase / 0.5) }
        if phase < 0.7 { return 1 }
        return 1 - smooth((phase - 0.7) / 0.3)
    }

    override func draw() {
        let paint = paints(for: look)
        background(paint.ground)
        noStroke()
        randomSeed(variation)

        let widths = paint.bands.map { $0.width * bandWidth }
        let ribbon = widths.reduce(0, +)
        let route = dealRoute(paint, ribbon: ribbon)
        let phase = loopProgress(over: seconds)
        let laid = route.length * Self.laidShare(phase)

        // 1. The discs, each coming up as the ribbon reaches its arc.
        let count = Double(route.stations.count)
        for (i, s) in route.stations.enumerated() {
            guard let disc = s.disc else { continue }
            let span = max(s.radius * s.sweep * 0.3, 1)
            let grown = Self.smooth((laid - route.arcStarts[i]) / span)
            guard grown > 0 else { continue }
            let breath = 1 + 0.03 * sin(2 * .pi * (2 * phase + Double(i) / count))
            let r = s.discRadius * grown * breath
            if disc.core == disc.rim {
                fill(disc.core)
            } else {
                fill(.radial(center: s.center, radius: r, [disc.core, disc.core.mixed(with: disc.rim, 0.55), disc.rim]))
            }
            drawCircle(center: s.center, radius: r)
        }

        // 2. The edges, each computed once, then the bands between them.
        var offset = -ribbon / 2
        var edges = [edge(of: route, offset: offset, laid: laid, outermost: ribbon / 2)]
        for w in widths {
            offset += w
            edges.append(edge(of: route, offset: offset, laid: laid, outermost: ribbon / 2))
        }
        for (j, band) in paint.bands.enumerated() {
            let inner = edges[j], outerEdge = edges[j + 1]
            guard inner.count >= 2 else { continue }
            fill(band.color)
            // A band bends back on itself around every disc, so it is a
            // shape that is triangulated, never a fan.
            drawShape(Shape(outer: inner + outerEdge.reversed(), holes: []))
        }
    }
}
