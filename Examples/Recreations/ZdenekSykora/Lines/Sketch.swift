//  Recreation after Zdeněk Sýkora - the Lines (Linie, from 1973), paintings of
//  colored lines on white whose every number was drawn from chance: where a
//  line starts, how wide it is, which paints mix into its color, and the
//  lengths and directions of the tangents it is built from. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist or his
//  estate.
//  http://www.zdeneksykora.cz/
//
//  An original Ollin interpretation, written from what Sýkora said of the
//  method in interviews (with Vítek Čapek, 1982 to 1985; with Vít Petrjanoš,
//  1991; with Lenka Lindaurová, 1995). Nothing was ported: the scores were
//  series of random numbers, first pulled from a canvas bag and later from a
//  computer, and the lines were constructed and painted by hand. The ranges,
//  the thirty paints, and the reading of how an arc's radius follows from its
//  tangents are this sketch's own.

import Ollin

/// Lines (Zdeněk Sýkora, Louny and Prague, from 1973). After a decade of
/// Structures Sýkora noticed that the borders between the black and the white
/// of his elements had become lines, and he turned to lines themselves. A
/// line was built from tangents: each began where the one before it ended,
/// and at every angle two tangents made, an arc joined them, its radius
/// worked out from the tangents' lengths and the angle between them. At first
/// the tangents ran along a grid and its diagonals, which he found too stiff;
/// then along the twelve directions of a clock face; later along any even
/// number of degrees. Everything else came from chance, in a score: the start
/// in whole centimeters on the canvas, the width, the number of paints (most
/// often one to five, out of thirty) mixed one to one into the line's color,
/// and then the length and direction of every tangent. Where two lines cross,
/// a last series of ones and twos, used one number at a time, decided which
/// goes over. "I must take those that are generated, precisely one after the
/// other." From 1985 his wife, Lenka Sýkorová, worked with him: the radius of
/// every arc was worked out on a calculator, the picture constructed in pencil
/// (for one canvas the pencil alone took four months), and the lines painted
/// one by one. The white of the canvas, he said, "represents emptiness as a
/// natural environment for randomness".
///
/// This sketch writes such a score and paints it. The canvas is 150 by 150
/// centimeters. Each of `lines` lines starts at whole centimeters anywhere on
/// it, takes a width from 0.2 to 4 centimeters, mixes one to five of thirty
/// oil paints one to one the way pigments mix, and runs along three to eight
/// tangents of 8 to 60 whole centimeters. `directions` is the stage of the
/// rule: the grid's eight directions, the clock's twelve, or every even
/// degree. At each angle the arc touches both tangents at the same distance
/// from their meeting point, half the shorter tangent, so its radius is that
/// distance over the tangent of half the turn: a sharp turn on short tangents
/// is a tight curl, a gentle one on long tangents a wide sweep, and a line
/// that turns straight back folds on itself. Lines run off the edges as they
/// do on his canvases. The crossings are walked line by line in the order of
/// the score, and each one not yet decided takes the next number of a series
/// of ones and twos: a two puts the line being walked over the other, a one
/// under it. Two lines that only graze, never crossing, leave the later one
/// on top, as painting them in order would. Where three lines overlap at one
/// place and each is over the next, no paint can show all three, and one of
/// them gives way. The seed writes the score, and a press writes the next one.
///
/// Over one cycle of `seconds` the lines are constructed in pencil, painted
/// one after another from their starts, and then the crossings are settled:
/// where the score puts the line painted first on top, the lens where the two
/// overlap is painted again with every line in it in the order the score
/// gives. The painting holds and fades back to white, which is also the
/// export loop.
///
/// Every line exports as one polyline at its width, the two ends of every arc
/// written twice and a turn with no arc (straight on, or straight back)
/// three times, so `--export-svg` with a frame in the hold gives the score
/// back: the start, every tangent's direction and length, and the width. A
/// settled crossing exports as the lines in its lens drawn again inside a
/// clip of the lens, so the file shows which line is on top at every
/// crossing.
@main
final class Lines: Sketch {
    /// The stage of the rule: which directions a tangent may take.
    enum Directions: String, CaseIterable, ParamOption {
        case grid, clock, even

        /// Degrees between neighboring directions.
        var step: Int {
            switch self {
            case .grid: 45
            case .clock: 30
            case .even: 2
            }
        }
    }

    @Param(1 ... 200, icon: "scribble") var lines = 40
    @Param(icon: "safari") var directions = Directions.even
    @Param(8 ... 90, icon: "clock") var seconds = 36.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { seconds }

    /// The canvas side, in centimeters.
    private let side = 150
    // The score's ranges.
    private let widths = [0.2, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0]
    private let paintsPerLine = 1 ... 5
    private let tangentsPerLine = 3 ... 8
    private let tangentLengths = 8 ... 60

    /// Thirty oil paints, this sketch's own box.
    private static let paints: [Color] = [
        0xF3F1EA, 0xEDE3C8, 0xF1D21F, 0xF0B20A, 0xE9C77D, 0xC8922D, 0xB3713A, 0x8C4027,
        0x5D4834, 0x4A3125, 0xE76E1E, 0xD8352B, 0xA6232B, 0x7D1D2D, 0xC35A6E, 0x8D2452,
        0x7B5A9C, 0x3D2A5C, 0x2D3A9C, 0x2E55A9, 0x2E80B6, 0x1C3250, 0x2A93A4, 0x2D6E5A,
        0x5A7A39, 0x4D5A26, 0x6E7A5C, 0x3E4A53, 0x8B8A86, 0x1E1C1A,
    ].map { Color(hex: $0) }

    private let ground = Color(hex: 0xF2F0EB)
    private let pencil = Color(hex: 0x8E8A84)

    private struct Line {
        /// The centerline in pixels, the ends of every arc written twice.
        var marked: [Vector2]
        /// The same centerline with each point once, for walking.
        var contour: Contour
        var width: Double
        var color: Color
    }

    /// Where two lines meet: the stretch of each that overlaps the other, and
    /// the line the score puts on top. Two crossings of one pair whose
    /// overlaps touch are one meeting, since paint cannot show them apart.
    private struct Meeting {
        var lines: (Int, Int)
        var spans: ((Double, Double), (Double, Double))
        /// Where along each line the centerlines first cross.
        var fractions: (Double, Double)
        var over = 0
    }

    /// Where the score puts the line painted first on top: the lens where the
    /// two bands overlap (several lenses, where they overlap one another),
    /// and every line inside in the order the decisions there give, painted
    /// again inside it.
    private struct Fix {
        var region: Shape
        var order: [Int]
    }

    private struct Dealt: Equatable {
        var lines: Int, directions: Directions, seed: Int
    }

    private var score: [Line] = []
    /// The meetings the order of painting gets wrong, settled one after
    /// another once every line is on.
    private var fixes: [Fix] = []
    private var pencilBatches: [Batch?] = []
    private var paintBatches: [Batch?] = []
    private var dealtFor: Dealt?
    private var pressed = false

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if pressed {
            pressed = false
            seed(variation + 1)
        }
        let wanted = Dealt(lines: lines, directions: directions, seed: variation)
        if dealtFor != wanted {
            dealtFor = wanted
            deal()
        }

        background(ground)
        noFill()
        strokeJoin(.round)

        let phase = loopProgress(over: seconds)
        let constructed = 0.2, painted = 0.72, settled = 0.8, held = 0.93
        let count = Double(score.count)

        // Pencil first, line after line, each one gone once its paint is on.
        let drawnInPencil = count * min(1, phase / constructed)
        let paintedLines = phase < constructed ? 0 : count * min(1, (phase - constructed) / (painted - constructed))
        stroke(pencil)
        strokeWeight(1)
        strokeCap(.round)
        for (i, line) in score.enumerated() where Double(i) < drawnInPencil && Double(i + 1) > paintedLines {
            let t = min(1, drawnInPencil - Double(i))
            if t < 1 {
                drawPolyline(line.contour.piece(from: 0, to: t).points)
            } else {
                drawBatch(pencilBatch(i))
            }
        }

        // The paint, one line at a time from its start.
        for (i, line) in score.enumerated() where Double(i) < paintedLines {
            let t = min(1, paintedLines - Double(i))
            if t < 1 {
                stroke(line.color)
                strokeWeight(line.width)
                strokeCap(.round)
                drawPolyline(line.contour.piece(from: 0, to: t).points)
            } else {
                drawBatch(paintBatch(i))
            }
        }

        // The crossings, settled one after another: inside the lens of each,
        // every line there painted again in the order the score gives them.
        let settling = phase < painted ? 0 : (phase - painted) / (settled - painted)
        let shown = min(fixes.count, Int(Double(fixes.count) * settling + 0.5))
        for fix in fixes.prefix(shown) {
            withClip(fix.region) {
                for i in fix.order { drawBatch(paintBatch(i)) }
            }
        }

        if phase > held {
            noStroke()
            fill(ground.withAlpha(smoothstep(held, 1, phase)))
            drawRect(0, 0, width, height)
        }
    }

    /// A line in pencil, kept once it is whole.
    private func pencilBatch(_ i: Int) -> Batch {
        if let batch = pencilBatches[i] { return batch }
        let batch = makeBatch {
            noFill()
            stroke(pencil)
            strokeWeight(1)
            strokeCap(.round)
            strokeJoin(.round)
            drawPolyline(score[i].contour.points)
        }
        pencilBatches[i] = batch
        return batch
    }

    /// A line in paint, kept once it is whole.
    private func paintBatch(_ i: Int) -> Batch {
        if let batch = paintBatches[i] { return batch }
        let batch = makeBatch {
            noFill()
            stroke(score[i].color)
            strokeWeight(score[i].width)
            strokeCap(.round)
            strokeJoin(.round)
            drawPolyline(score[i].marked)
        }
        paintBatches[i] = batch
        return batch
    }

    /// A whole number from a range, drawn evenly.
    private func whole(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + min(range.count - 1, Int(random(0, Double(range.count))))
    }

    /// Writes the score for the seed and constructs it.
    private func deal() {
        randomSeed(variation)
        let scale = width / Double(side)
        let turns = 360 / directions.step
        score = (0 ..< lines).map { _ in
            let start = Vector2(Double(whole(0 ... side)), Double(whole(0 ... side)))
            let lineWidth = randomChoice(widths)
            let chosen = shuffled(Array(Self.paints.indices)).prefix(whole(paintsPerLine))
            // One to one: each paint added at its share of the mix so far,
            // which in the pigment model is the same as all at once.
            var mix = Spectrum(Self.paints[chosen.first!])
            for (k, paint) in chosen.enumerated().dropFirst() {
                mix = mix.mixedAsPaint(with: Spectrum(Self.paints[paint]), 1 / Double(k + 1))
            }
            let tangents = (0 ..< whole(tangentsPerLine)).map { _ in
                (length: Double(whole(tangentLengths)),
                 angle: Double(whole(0 ... turns - 1) * directions.step) * .pi / 180)
            }
            let marked = centerline(from: start, along: tangents).map { $0 * scale }
            var once: [Vector2] = []
            for p in marked where once.last.map({ ($0 - p).length > 1e-9 }) ?? true { once.append(p) }
            return Line(marked: marked, contour: Contour(once, closed: false),
                        width: lineWidth * scale, color: mix.color)
        }
        pencilBatches = Array(repeating: nil, count: score.count)
        paintBatches = Array(repeating: nil, count: score.count)
        settleCrossings()
    }

    /// The line through its tangents, in centimeters: straight along each
    /// tangent, and at each angle an arc touching both tangents half the
    /// shorter one's length from where they meet.
    private func centerline(from start: Vector2, along tangents: [(length: Double, angle: Double)]) -> [Vector2] {
        let heading = tangents.map { Vector2(cos($0.angle), sin($0.angle)) }
        var corner = start
        var out = [start]
        for j in 1 ..< tangents.count {
            corner = corner + heading[j - 1] * tangents[j - 1].length
            let u = heading[j - 1], v = heading[j]
            let turn = atan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y)
            let reach = min(tangents[j - 1].length, tangents[j].length) / 2
            let a = corner - u * reach
            // Straight on, or straight back: no arc, the turn written three times.
            if abs(turn) < 1e-9 {
                out += [corner, corner, corner]
                continue
            }
            if abs(abs(turn) - .pi) < 1e-9 {
                out += [a, a, a]
                continue
            }
            let radius = reach / tan(abs(turn) / 2)
            let center = a + Vector2(-u.y, u.x) * (turn > 0 ? radius : -radius)
            let from = atan2(a.y - center.y, a.x - center.x)
            let steps = max(4, Int((abs(turn) * 90 / .pi - 1e-6).rounded(.up)))
            let arc = (0 ... steps).map { i in
                center + Vector2(cos(from + turn * Double(i) / Double(steps)),
                                 sin(from + turn * Double(i) / Double(steps))) * radius
            }
            out += [arc[0]] + arc + [arc[steps]]
        }
        out.append(corner + heading[tangents.count - 1] * tangents[tangents.count - 1].length)
        return out
    }

    /// Every line walked at even steps, and a grid over all the steps, so
    /// asking which lines pass near a point looks only at the cells around it.
    private struct Walks {
        static let spacing = 2.0
        static let cell = 16.0
        var points: [[Vector2]] = []
        var grid: [SIMD2<Int>: [(line: Int, index: Int)]] = [:]

        init(_ contours: [Contour]) {
            for (line, contour) in contours.enumerated() {
                // Even fractions of the length, so a step's index is its fraction.
                let count = max(2, Int((contour.length / Self.spacing).rounded(.up)) + 1)
                let pts = contour.points
                var walk: [Vector2] = []
                var segment = 0, before = 0.0
                for i in 0 ..< count {
                    let at = contour.length * Double(i) / Double(count - 1)
                    while segment < pts.count - 2, before + (pts[segment + 1] - pts[segment]).length < at {
                        before += (pts[segment + 1] - pts[segment]).length
                        segment += 1
                    }
                    let run = (pts[segment + 1] - pts[segment]).length
                    let t = run > 0 ? min(1, max(0, (at - before) / run)) : 0
                    walk.append(pts[segment] + (pts[segment + 1] - pts[segment]) * t)
                }
                for (index, p) in walk.enumerated() {
                    grid[Self.key(p), default: []].append((line, index))
                }
                points.append(walk)
            }
        }

        static func key(_ p: Vector2) -> SIMD2<Int> {
            SIMD2(Int((p.x / cell).rounded(.down)), Int((p.y / cell).rounded(.down)))
        }

        /// The lines with a step within their own `radius` of a point.
        func lines(near p: Vector2, within radius: (Int) -> Double, reach: Double) -> Set<Int> {
            var found = Set<Int>()
            let low = Self.key(p - Vector2(reach, reach)), high = Self.key(p + Vector2(reach, reach))
            for x in low.x ... high.x {
                for y in low.y ... high.y {
                    for (line, index) in grid[SIMD2(x, y)] ?? [] where !found.contains(line) {
                        if (points[line][index] - p).length <= radius(line) { found.insert(line) }
                    }
                }
            }
            return found
        }

        /// Whether line `line` passes within `radius` of a point.
        func passes(_ line: Int, near p: Vector2, within radius: Double) -> Bool {
            let low = Self.key(p - Vector2(radius, radius)), high = Self.key(p + Vector2(radius, radius))
            for x in low.x ... high.x {
                for y in low.y ... high.y {
                    for step in grid[SIMD2(x, y)] ?? [] where step.line == line {
                        if (points[line][step.index] - p).length <= radius { return true }
                    }
                }
            }
            return false
        }

        /// The step of line `line` nearest a point, within `radius` of it.
        func nearest(_ line: Int, to p: Vector2, within radius: Double) -> Int? {
            var best: (Int, Double)?
            let low = Self.key(p - Vector2(radius, radius)), high = Self.key(p + Vector2(radius, radius))
            for x in low.x ... high.x {
                for y in low.y ... high.y {
                    for step in grid[SIMD2(x, y)] ?? [] where step.line == line {
                        let d = (points[line][step.index] - p).length
                        if d <= radius, best.map({ d < $0.1 }) ?? true { best = (step.index, d) }
                    }
                }
            }
            return best?.0
        }

        func fraction(_ line: Int, _ index: Int) -> Double { Double(index) / Double(points[line].count - 1) }
        func index(_ line: Int, _ fraction: Double) -> Int {
            min(points[line].count - 1, max(0, Int((fraction * Double(points[line].count - 1)).rounded())))
        }
    }

    /// The stretch either way from `fraction` where line `a` overlaps line
    /// `b`: where its centerline stays within both half widths of the other's,
    /// a step past it on each side.
    private func overlap(of a: Int, with b: Int, around fraction: Double, in walks: Walks) -> (Double, Double) {
        let reach = (score[a].width + score[b].width) / 2 + Walks.spacing
        let walk = walks.points[a]
        var low = walks.index(a, fraction), high = low
        while low > 0, walks.passes(b, near: walk[low - 1], within: reach) { low -= 1 }
        while high < walk.count - 1, walks.passes(b, near: walk[high + 1], within: reach) { high += 1 }
        return (walks.fraction(a, max(0, low - 1)), walks.fraction(a, min(walk.count - 1, high + 1)))
    }

    /// Finds where the lines meet and walks the meetings in the order of the
    /// score, each undecided one taking the next number of ones and twos, then
    /// lists the meetings the order of painting gets wrong and how to settle
    /// each one.
    private func settleCrossings() {
        func touch(_ x: (Double, Double), _ y: (Double, Double)) -> Bool { x.0 <= y.1 && y.0 <= x.1 }
        func union(_ x: (Double, Double), _ y: (Double, Double)) -> (Double, Double) { (min(x.0, y.0), max(x.1, y.1)) }
        let walks = Walks(score.map(\.contour))
        var meetings: [Meeting] = []
        for i in score.indices {
            for j in score.indices where j > i {
                var pair: [Meeting] = []
                for hit in score[i].contour.crossings(with: score[j].contour) {
                    let mine = overlap(of: i, with: j, around: hit.fraction, in: walks)
                    let theirs = overlap(of: j, with: i, around: hit.otherFraction, in: walks)
                    if let k = pair.firstIndex(where: { touch($0.spans.0, mine) || touch($0.spans.1, theirs) }) {
                        pair[k].spans = (union(pair[k].spans.0, mine), union(pair[k].spans.1, theirs))
                    } else {
                        pair.append(Meeting(lines: (i, j), spans: (mine, theirs),
                                            fractions: (hit.fraction, hit.otherFraction)))
                    }
                }
                meetings += pair
            }
        }

        // The series of ones and twos, walked line by line along each line.
        var decided = Array(repeating: false, count: meetings.count)
        for i in score.indices {
            let along = meetings.indices
                .filter { meetings[$0].lines.0 == i || meetings[$0].lines.1 == i }
                .sorted { a, b in
                    let fa = meetings[a].lines.0 == i ? meetings[a].fractions.0 : meetings[a].fractions.1
                    let fb = meetings[b].lines.0 == i ? meetings[b].fractions.0 : meetings[b].fractions.1
                    return fa < fb
                }
            for k in along where !decided[k] {
                let other = meetings[k].lines.0 == i ? meetings[k].lines.1 : meetings[k].lines.0
                meetings[k].over = whole(1 ... 2) == 2 ? i : other
                decided[k] = true
            }
        }

        // Painted in the order of the score, a later line already lies over
        // an earlier one wherever they cross or graze, so only a meeting the
        // score gives to the earlier line needs settling. Inside the lens
        // where the two overlap, every line present is painted again, in an
        // order that keeps every decision made there: the score's where two
        // of them meet, the order of painting where they only graze. Where
        // three lines overlap at one place and each is over the next, no order
        // shows all three decisions; the ring is broken at the line with the
        // fewest decisions left to keep, never the meeting's own. Lenses that
        // overlap one another are one place with one order.
        let widths = score.map(\.width)
        let contours = score.map(\.contour)
        let widest = widths.max() ?? 0
        struct Lens {
            var meeting: Meeting
            var shape: Shape
            var spans: (Contour, Contour)
            var half: (Double, Double)
            var box: Rectangle
            func holds(_ p: Vector2, give: Double) -> Bool {
                spans.0.distance(to: p) <= half.0 + give && spans.1.distance(to: p) <= half.1 + give
            }
        }
        // The lens where two bands overlap, a little past both edges, for
        // every meeting the score gives to the earlier line.
        var lenses: [Lens] = meetings.filter { $0.over == $0.lines.0 }.map { m in
            let (a, b) = m.lines
            let half = (widths[a] / 2 + 1.5, widths[b] / 2 + 1.5)
            let spans = (contours[a].piece(from: m.spans.0.0, to: m.spans.0.1),
                         contours[b].piece(from: m.spans.1.0, to: m.spans.1.1))
            let shape = spans.0.stroked(width: 2 * half.0, join: .round, cap: .round)
                .intersection(spans.1.stroked(width: 2 * half.1, join: .round, cap: .round))
            let points = shape.contours.flatMap(\.points)
            let low = points.reduce(Vector2(.infinity, .infinity)) { Vector2(min($0.x, $1.x), min($0.y, $1.y)) }
            let high = points.reduce(-Vector2(.infinity, .infinity)) { Vector2(max($0.x, $1.x), max($0.y, $1.y)) }
            return Lens(meeting: m, shape: shape, spans: spans, half: half,
                        box: Rectangle(x: low.x, y: low.y,
                                       width: max(0, high.x - low.x), height: max(0, high.y - low.y)))
        }
        lenses.removeAll { $0.shape.contours.isEmpty }

        // Lenses that overlap are settled together, as one place with one
        // order, so a knot of several lines is painted one way throughout.
        var cluster = Array(lenses.indices)
        func root(_ k: Int) -> Int { cluster[k] == k ? k : root(cluster[k]) }
        for i in lenses.indices {
            let a = lenses[i].box
            for j in lenses.indices where j > i {
                let b = lenses[j].box
                guard a.x <= b.x + b.width, b.x <= a.x + a.width,
                      a.y <= b.y + b.height, b.y <= a.y + a.height else { continue }
                if !lenses[i].shape.intersection(lenses[j].shape).contours.isEmpty {
                    cluster[root(j)] = root(i)
                }
            }
        }
        let groups = Dictionary(grouping: lenses.indices, by: root).values.sorted { $0.min()! < $1.min()! }

        fixes = groups.map { group in
            let members = group.map { lenses[$0] }
            func inside(_ p: Vector2, give: Double) -> Bool { members.contains { $0.holds(p, give: give) } }
            // Every line with a step inside the place.
            var present = Set(members.flatMap { [$0.meeting.lines.0, $0.meeting.lines.1] })
            for member in members {
                let b = member.meeting.lines.1
                let low = walks.index(b, member.meeting.spans.1.0), high = walks.index(b, member.meeting.spans.1.1)
                for index in low ... high {
                    for x in walks.lines(near: walks.points[b][index], within: { member.half.1 + widths[$0] / 2 },
                                         reach: member.half.1 + widest / 2) where !present.contains(x) {
                        if walks.points[x].contains(where: { inside($0, give: widths[x] / 2) }) { present.insert(x) }
                    }
                }
            }
            // Where a meeting's overlap reaches into the place, and how far its
            // crossing is from the nearest of the place's own, to settle a pair
            // that meets twice nearby by the nearer meeting.
            let crossings = members.map { contours[$0.meeting.lines.0].point(at: $0.meeting.fractions.0) }
            func reach(_ meeting: Meeting) -> Double? {
                let x = meeting.lines.0, span = meeting.spans.0
                let touches = stride(from: walks.index(x, span.0), through: walks.index(x, span.1), by: 1).contains {
                    inside(walks.points[x][$0], give: widths[x] / 2)
                }
                let here = contours[x].point(at: meeting.fractions.0)
                return touches ? crossings.map { ($0 - here).length }.min() : nil
            }
            let lines = present.sorted()
            var overs = [Int: [Int]](), under = [Int: Int]()
            for (k, x) in lines.enumerated() {
                for y in lines[(k + 1)...] {
                    let meeting = meetings.filter { $0.lines == (x, y) }
                        .compactMap { candidate in reach(candidate).map { (candidate, $0) } }
                        .min { $0.1 < $1.1 }?.0
                    let top = meeting?.over ?? y
                    overs[top == x ? y : x, default: []].append(top)
                    under[top, default: 0] += 1
                }
            }
            // A ring is broken at the line with the fewest decisions left to
            // keep, never one the place was opened to put on top.
            let tops = Set(members.map { $0.meeting.lines.0 })
            var order: [Int] = []
            var left = lines
            while let next = left.first(where: { (under[$0] ?? 0) <= 0 })
                ?? left.filter({ !tops.contains($0) }).min(by: { (under[$0] ?? 0) < (under[$1] ?? 0) })
                ?? left.min(by: { (under[$0] ?? 0) < (under[$1] ?? 0) }) {
                order.append(next)
                left.removeAll { $0 == next }
                for o in overs[next] ?? [] { under[o, default: 0] -= 1 }
            }
            let region = members.dropFirst().reduce(members[0].shape) { $0.union($1.shape) }
            return Fix(region: region, order: order)
        }
    }
}
