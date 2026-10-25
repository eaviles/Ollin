import Foundation

// A line that looks drawn by hand: `handDrawn(...)` on a `Contour`, a `Shape`,
// and a `StrokeMark`. Each returns its own type. The hand's four habits are
// a wobble off the ideal line (signed noise across the heading, read by the
// distance along the line), a slight bow over each straight run between
// corners, ends that run a little short or long, and on a mark a blot where
// the pen landed. Everything is read in the line's own frame, from its own
// start along its own length, and drawn from the seed alone, so a line that
// moves across the canvas carries its wobble with it rather than boiling, and
// two lines with one seed wobble alike (give each line of a family its own).

/// The geometry the three `handDrawn` forms share.
enum HandDrawn {

    /// How far apart the line is resampled before it is bent, in canvas points.
    static let step = 3.0
    /// The turn at a vertex that makes it a corner, where one bowed run ends
    /// and the next begins: about 35 degrees.
    static let cornerTurn = 0.61
    /// The wobble's two features, in canvas points along the line.
    static let wobbleLong = 26.0
    static let wobbleShort = 7.0

    /// One point of the line with what travels with it.
    struct Point {
        var position: Vector2
        var width: Double
        var speed: Double?
        /// Whether the point was one of the line's own, which is what can be
        /// a corner.
        var original: Bool
    }

    /// The line bent as a hand would draw it. `widths` and `speeds` ride along
    /// where given (a mark's), interpolated where the line is resampled.
    /// `salt` tells one outline of a shape from the next under one seed.
    static func apply(_ points: [Vector2], widths: [Double]?, speeds: [Double?]?, closed: Bool,
                      wobble: Double, bow: Double, overshoot: Double, blot: Double,
                      seed: Int, salt: Int) -> [Point] {
        // The line's own points, repeats dropped, each with its width and speed.
        var own: [Point] = []
        for (i, p) in points.enumerated() {
            if let last = own.last, last.position.distance(to: p) < 1e-9 { continue }
            own.append(Point(position: p, width: widths?[i] ?? 1, speed: speeds?[i], original: true))
        }
        if closed, own.count > 1, let first = own.first, let last = own.last,
           first.position.distance(to: last.position) < 1e-9 {
            own.removeLast()
        }
        guard own.count >= 2 else { return own }

        // Resampled every `step` so the wobble has points to move, the line's
        // own points kept where they are.
        var dense: [Point] = []
        let segments = closed ? own.count : own.count - 1
        for i in 0 ..< segments {
            let a = own[i], b = own[(i + 1) % own.count]
            dense.append(a)
            let span = a.position.distance(to: b.position)
            let pieces = Int((span / step).rounded(.up))
            for k in 1 ..< max(pieces, 1) {
                let f = Double(k) / Double(pieces)
                let speed: Double? = (a.speed != nil && b.speed != nil) ? a.speed! + (b.speed! - a.speed!) * f : nil
                dense.append(Point(position: a.position + (b.position - a.position) * f,
                                   width: a.width + (b.width - a.width) * f, speed: speed, original: false))
            }
        }
        if !closed { dense.append(own[own.count - 1]) }
        let n = dense.count
        guard n >= 2 else { return dense }

        // The distance along at each point, and the whole length.
        var arc = [Double](repeating: 0, count: n)
        for i in 1 ..< n { arc[i] = arc[i - 1] + dense[i - 1].position.distance(to: dense[i].position) }
        let total = arc[n - 1] + (closed ? dense[n - 1].position.distance(to: dense[0].position) : 0)
        guard total > 1e-9 else { return dense }

        // The heading at each point: the mean of the segments meeting there.
        var tangents = [Vector2](repeating: Vector2(1, 0), count: n)
        for i in 0 ..< n {
            let prev = i == 0 ? (closed ? n - 1 : 0) : i - 1
            let next = i == n - 1 ? (closed ? 0 : n - 1) : i + 1
            let d = dense[next].position - dense[prev].position
            tangents[i] = d.length > 1e-12 ? d / d.length : (i > 0 ? tangents[i - 1] : Vector2(1, 0))
        }

        // The corners, where one bowed run ends and the next begins: the
        // line's own points where the heading turns sharply, and an open
        // line's two ends.
        var corners: [Int] = []
        for i in 0 ..< n where dense[i].original {
            let prev = i == 0 ? (closed ? n - 1 : -1) : i - 1
            let next = i == n - 1 ? (closed ? 0 : -1) : i + 1
            guard prev >= 0, next >= 0 else { continue }
            let a = dense[i].position - dense[prev].position
            let b = dense[next].position - dense[i].position
            guard a.length > 1e-12, b.length > 1e-12 else { continue }
            let turn = acos(min(max(a.dot(b) / (a.length * b.length), -1), 1))
            if turn > cornerTurn { corners.append(i) }
        }
        var runs: [(from: Int, to: Int)] = []
        if closed {
            if corners.count >= 2 {
                for (k, c) in corners.enumerated() { runs.append((c, corners[(k + 1) % corners.count])) }
            }
        } else {
            var bounds = [0] + corners.filter { $0 != 0 && $0 != n - 1 } + [n - 1]
            bounds = Array(Set(bounds)).sorted()
            for k in 0 ..< bounds.count - 1 { runs.append((bounds[k], bounds[k + 1])) }
        }

        // The bow of each run: a sag across its chord, up to `bow`, to one side
        // or the other by the seed.
        var bows = [Double](repeating: 0, count: n)
        for (r, run) in runs.enumerated() {
            let chord = dense[run.to].position - dense[run.from].position
            guard chord.length > 1e-9 else { continue }
            let sign: Double = GestureMark.hash(seed, salt * 31 + 2, r, 0) < 0.5 ? -1 : 1
            let amount = bow * sign * (0.6 + 0.4 * GestureMark.hash(seed, salt * 31 + 2, r, 1))
            let span = run.to > run.from ? arc[run.to] - arc[run.from] : total - arc[run.from] + arc[run.to]
            guard span > 1e-9 else { continue }
            let normal = chord.perpendicular / chord.length
            var i = run.from
            var along = 0.0
            while true {
                let f = min(max(along / span, 0), 1)
                let sag = amount * 4 * f * (1 - f)
                // The sag is laid along the chord's normal, so it is stored as
                // a signed distance along the point's own normal where the two
                // agree and a plain offset otherwise.
                bows[i] += sag * normal.dot(tangents[i].perpendicular)
                if i == run.to { break }
                let next = (i + 1) % n
                along += dense[i].position.distance(to: dense[next].position)
                i = next
                if i == run.from { break }
            }
        }

        // The wobble: two features of signed noise read by the distance along,
        // and on a closed line faded into its own start so the seam is smooth.
        func noise(_ s: Double) -> Double {
            0.72 * GestureMark.smooth(s / wobbleLong, seed, salt * 31 + 5)
                + 0.28 * GestureMark.smooth(s / wobbleShort, seed, salt * 31 + 6)
        }
        var bent = dense
        for i in 0 ..< n {
            var w = noise(arc[i])
            if closed {
                let fade = min(total * 0.2, 60)
                let into = arc[i] - (total - fade)
                if into > 0, fade > 0 {
                    let k = into / fade
                    let eased = k * k * (3 - 2 * k)
                    w = w * (1 - eased) + noise(arc[i] - total) * eased
                }
            }
            bent[i].position = dense[i].position + tangents[i].perpendicular * (wobble * w + bows[i])
        }

        // An open line's ends run a little short or long along their heading.
        if !closed, overshoot > 0 {
            for end in 0 ..< 2 {
                let delta = overshoot * (2 * GestureMark.hash(seed, salt * 31 + 3, end, 0) - 1)
                if abs(delta) < 1e-9 { continue }
                let atStart = end == 0
                if delta > 0 {
                    let i = atStart ? 0 : bent.count - 1
                    let direction = atStart ? tangents[0] * -1 : tangents[n - 1]
                    var extra = bent[i]
                    extra.position = bent[i].position + direction * delta
                    extra.original = false
                    if atStart { bent.insert(extra, at: 0) } else { bent.append(extra) }
                } else {
                    var left = -delta
                    while bent.count >= 2, left > 0 {
                        let i = atStart ? 0 : bent.count - 1
                        let j = atStart ? 1 : bent.count - 2
                        let span = bent[i].position.distance(to: bent[j].position)
                        if span <= left {
                            left -= span
                            bent.remove(at: i)
                        } else {
                            let f = left / span
                            bent[i].position = bent[i].position + (bent[j].position - bent[i].position) * f
                            bent[i].width += (bent[j].width - bent[i].width) * f
                            left = 0
                        }
                    }
                }
            }
        }

        // The blot where the pen landed: the width swells by half and settles
        // over `blot` canvas points.
        if blot > 0, !closed {
            var s = 0.0
            for i in bent.indices {
                if i > 0 { s += bent[i - 1].position.distance(to: bent[i].position) }
                bent[i].width *= 1 + 0.5 * exp(-s / blot)
            }
        }
        return bent
    }
}

public extension Contour {
    /// A copy that looks drawn by hand: the line wobbles off its ideal by up to
    /// `wobble` canvas points, each straight run between corners bows by up to
    /// `bow`, and an open line's ends run short or long by up to `overshoot`,
    /// all from the seed. The wobble is read along the line from its own start,
    /// so a line that moves keeps its character rather than boiling; two lines
    /// with one seed wobble alike, so give each line of a family its own. A
    /// closed outline keeps its corners and stays closed, so it still fills.
    /// The line is resampled about every three points first.
    func handDrawn(wobble: Double = 1, bow: Double = 1, overshoot: Double = 3, seed: Int = 0) -> Contour {
        let bent = HandDrawn.apply(points, widths: nil, speeds: nil, closed: isClosed,
                                   wobble: Swift.max(wobble, 0), bow: Swift.max(bow, 0),
                                   overshoot: Swift.max(overshoot, 0), blot: 0, seed: seed, salt: 0)
        return Contour(bent.map { $0.position }, closed: isClosed)
    }
}

public extension Shape {
    /// A copy whose every outline looks drawn by hand (see `Contour.handDrawn`),
    /// each outline bent its own way under the one seed. Closed outlines stay
    /// closed, so the shape still fills.
    func handDrawn(wobble: Double = 1, bow: Double = 1, overshoot: Double = 3, seed: Int = 0) -> Shape {
        let outlines = contours.enumerated().map { i, contour -> Contour in
            let bent = HandDrawn.apply(contour.points, widths: nil, speeds: nil, closed: contour.isClosed,
                                       wobble: Swift.max(wobble, 0), bow: Swift.max(bow, 0),
                                       overshoot: Swift.max(overshoot, 0), blot: 0, seed: seed, salt: i + 1)
            return Contour(bent.map { $0.position }, closed: contour.isClosed)
        }
        return Shape(contours: outlines, winding: winding)
    }
}

public extension StrokeMark {
    /// A copy that looks drawn by hand (see `Contour.handDrawn`), its widths,
    /// opacities, and speeds carried along, plus the blot a landing pen
    /// leaves: the width swells by about half where the mark begins and
    /// settles over `blot` canvas points, `0` for none.
    func handDrawn(wobble: Double = 1, bow: Double = 1, overshoot: Double = 3, blot: Double = 0,
                   seed: Int = 0) -> StrokeMark {
        let bent = HandDrawn.apply(samples.map(\.position), widths: samples.map(\.width),
                                   speeds: samples.map(\.speed), closed: false,
                                   wobble: Swift.max(wobble, 0), bow: Swift.max(bow, 0),
                                   overshoot: Swift.max(overshoot, 0), blot: Swift.max(blot, 0),
                                   seed: seed, salt: 0)
        // The opacity rides the nearest recorded point by distance along.
        var cumulative = [Double](repeating: 0, count: samples.count)
        for i in 1 ..< max(samples.count, 1) {
            cumulative[i] = cumulative[i - 1] + samples[i - 1].position.distance(to: samples[i].position)
        }
        let opacities = samples.map(\.opacity)
        var walked = 0.0
        var cursor = 0
        var copy = StrokeMark(dynamics, smoothing: smoothing, minSpacing: minSpacing)
        copy.pressureDeadZone = pressureDeadZone
        copy.pressureCurve = pressureCurve
        copy.maxWidthChange = maxWidthChange
        for (i, p) in bent.enumerated() {
            if i > 0 { walked += bent[i - 1].position.distance(to: p.position) }
            while cursor + 1 < cumulative.count, cumulative[cursor + 1] <= walked { cursor += 1 }
            copy.append(Sample(position: p.position, width: p.width,
                               opacity: opacities.isEmpty ? 1 : opacities[min(cursor, opacities.count - 1)],
                               speed: p.speed))
        }
        return copy
    }
}
