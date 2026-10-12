//  Recreation after Anwar Jalal Shemza - the Meem paintings (1964 to 1968),
//  in which the letter meem, the first letter of Muhammad and of Mary, his
//  wife, is reduced to a circle and a line and repeated. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist or his
//  estate.
//  https://www.anwarshemza.com/
//
//  An original Ollin interpretation, written from the pictures as the estate
//  and the museums that hold them describe them, and from what Shemza said of
//  his method: a simplification of the solid, architectural reality of the
//  decorative element of calligraphy. There is no code to port; the rule for
//  stacking the heads, laying the tails, and writing right to left is this
//  sketch's own.

import Ollin

/// Meem (Anwar Jalal Shemza, Stafford, 1964 to 1968). The letter meem is a
/// round head and a tail that drops below the line. Shemza, who had come to
/// London from Lahore and settled in Stafford, took the letter apart into the
/// two forms he said his pictures were built from, the circle and the square,
/// and kept the circle and a line: a disc for the head and a long vertical for
/// the tail, running to the bottom edge of the canvas. He painted it again
/// and again. In the oils of 1967 the discs stack in red columns and the tails
/// hang beside them as thin red lines over a blue ground crossed by green
/// bands, the tail of the top disc hooking over its shoulder the way the pen
/// enters the letter. In *Meem One* of the same year the discs crowd together
/// in reds and oranges at the top of wide green stems outlined in white, like
/// the long-stemmed flowers of a stained-glass window. He signed each one in
/// Urdu with its year.
///
/// This sketch keeps the letter as he reduced it. The canvas is ruled into
/// `lanes` of equal width. A cluster is a few heads laid one touching the
/// next, below or beside it, and every head drops a tail on the cluster's
/// outer side: the tails lie in slots spaced one gap apart, the lowest head
/// taking the innermost slot and the topmost the outermost, so each tail
/// leaves its head as a quarter turn around it and falls straight to the
/// bottom edge. The top head's turn passes over its own shoulder, which is
/// the hook. `clusters` is how many clusters the seed deals; with `mirrored`
/// on, the left half is dealt and reflected, and a cluster on the axis is
/// built symmetric, its axis head dropping a tail to either side. `look`
/// chooses the oils' thin red lines over blue and green, or the stained-glass
/// window's wide green stems with white outlines and heads of several sizes
/// and colors. The seed deals the clusters, and a press deals the next one.
///
/// Over one cycle of `seconds` the ground is laid, then the letters are
/// written as the pen would write them, right to left, the way Urdu reads:
/// each head drawn round, then its tail hooked and dropped; then the picture
/// holds and fades back, which is also the export loop.
///
/// Every head exports as a circle, every tail as a line or a rectangle, every
/// hook as its arc, and every ground band as a rectangle, so `--export-svg`
/// with a frame in the hold gives back the rule: the heads of a cluster touch
/// and never overlap, the tails of a cluster are exactly one gap apart and
/// reach the bottom edge, every hook is centered on its head, the bands fill
/// whole lanes, and a mirrored picture is its own reflection.
@main
final class Meem: Sketch {
    enum Look: String, CaseIterable, ParamOption {
        /// After the oils of 1967: thin red lines over blue and green.
        case oil
        /// After *Meem One*: wide green stems outlined in white, heads of
        /// several sizes and colors.
        case window
    }

    @Param(icon: "paintpalette") var look = Look.oil
    @Param(2 ... 9, icon: "circle.grid.2x1") var clusters = 5
    @Param(icon: "arrow.left.and.right") var mirrored = true
    @Param(16 ... 40, icon: "square.grid.3x3") var lanes = 24
    @Param(8 ... 90, icon: "clock") var seconds = 24.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { seconds }

    private enum Side { case left, right }

    private struct Head {
        var center: Vector2
        var radius: Double
        var paint: Int
    }

    /// A tail: the quarter turn around its head, then the fall.
    private struct Tail {
        var head: Int
        var side: Side
        var x: Double
        /// The slot from the cluster's edge, 1 the innermost.
        var slot: Int
        var isHook: Bool
    }

    private struct Cluster {
        var heads: [Head]
        var tails: [Tail]
        var anchor: Double
    }

    private struct Band {
        var lane: Int
        var lanes: Int
    }

    /// One movement of the pen, in writing order, with its length in the
    /// units the pen travels.
    private enum Stroke {
        case head(cluster: Int, head: Int)
        case tail(cluster: Int, tail: Int)
    }

    private struct Picture {
        var clusters: [Cluster]
        var bands: [Band]
        var strokes: [Stroke]
        var lengths: [Double]
        var total: Double
    }

    private struct Dealt: Equatable {
        var look: Look, clusters: Int, mirrored: Bool, lanes: Int, seed: Int
    }

    // The paints.
    private let oilGround = Color(hex: 0x4C4FB3)
    private let oilBand = Color(hex: 0x2B8A6C)
    private let oilRed = Color(hex: 0xEE4D3D)
    private let windowGround = Color(hex: 0xC8CAD2)
    private let windowStems = [Color(hex: 0x2B5C55), Color(hex: 0x7AAE86)]
    private let windowHeads = [Color(hex: 0xE4502D), Color(hex: 0xEF7A2A), Color(hex: 0x9A2733),
                               Color(hex: 0xF39A3C), Color(hex: 0xDB3F2B)]
    private let windowWhite = Color(hex: 0xF4F2EA)

    private var picture: Picture?
    private var dealtFor: Dealt?
    private var pressed = false

    private var unit: Double { width / Double(lanes) }
    private var gap: Double { look == .oil ? 0.35 * unit : 0.8 * unit }
    private var lineWidth: Double { look == .oil ? 0.16 * unit : 0.08 * unit }

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if pressed {
            pressed = false
            seed(variation + 1)
        }
        let wanted = Dealt(look: look, clusters: clusters, mirrored: mirrored, lanes: lanes, seed: variation)
        if dealtFor != wanted || picture == nil {
            dealtFor = wanted
            picture = deal()
        }
        guard let picture else { return }

        let ground = look == .oil ? oilGround : windowGround
        background(ground)

        let phase = loopProgress(over: seconds)
        let laid = 0.05, written = 0.78, held = 0.92

        // The ground bands, whole lanes wide.
        noStroke()
        fill(oilBand.withAlpha(smoothstep(0, laid, phase)))
        for band in picture.bands {
            drawRect(Double(band.lane) * unit, 0, Double(band.lanes) * unit, height)
        }

        // How far the pen has traveled, in the units the strokes measure.
        let writing = phase < laid ? 0 : min(1, (phase - laid) / (written - laid))
        let traveled = writing * picture.total

        // Tails first and heads on top, as the paintings layer them, so a
        // tail's turn around a lower head passes behind the heads above it.
        var done = 0.0
        for (i, stroke) in picture.strokes.enumerated() {
            let share = min(1, max(0, (traveled - done) / picture.lengths[i]))
            done += picture.lengths[i]
            if case .tail(let c, let t) = stroke, share > 0 {
                drawTail(picture.clusters[c].tails[t], of: picture.clusters[c], share: share)
            }
        }
        done = 0
        for (i, stroke) in picture.strokes.enumerated() {
            let share = min(1, max(0, (traveled - done) / picture.lengths[i]))
            done += picture.lengths[i]
            if case .head(let c, let h) = stroke, share > 0 {
                drawHead(picture.clusters[c].heads[h], share: share)
            }
        }

        if phase > held {
            fill(ground.withAlpha(smoothstep(held, 1, phase)))
            noStroke()
            drawRect(0, 0, width, height)
        }
    }

    /// A head drawn round: the whole disc in the hold, else the pen's loop
    /// so far as a pie from the top.
    private func drawHead(_ head: Head, share: Double) {
        let paint = look == .oil ? oilRed : windowHeads[head.paint % windowHeads.count]
        if look == .window {
            stroke(windowWhite)
            strokeWeight(lineWidth)
        } else {
            noStroke()
        }
        fill(paint)
        if share >= 1 {
            drawCircle(head.center.x, head.center.y, head.radius)
        } else {
            drawArc(center: head.center, radiusX: head.radius, radiusY: head.radius,
                    start: -.pi / 2, stop: -.pi / 2 + 2 * .pi * share, mode: .pie)
        }
        noStroke()
    }

    /// A tail: in the oils a line that turns a quarter around its head and
    /// falls; in the window a stem as wide as a slot, rising to the head's
    /// center, outlined in white.
    private func drawTail(_ tail: Tail, of cluster: Cluster, share: Double) {
        let head = cluster.heads[tail.head]
        let bottom = height
        switch look {
        case .oil:
            let reach = abs(head.center.x - tail.x)
            let turn = reach * .pi / 2
            let fall = bottom - head.center.y
            let along = share * (turn + fall)
            stroke(oilRed)
            strokeWeight(lineWidth)
            strokeCap(.butt)
            noFill()
            // From above the head, a quarter turn around it to the slot.
            let sweep = min(1, along / turn) * .pi / 2
            if sweep > 0 {
                if tail.side == .left {
                    drawArc(center: head.center, radiusX: reach, radiusY: reach,
                            start: -.pi / 2 - sweep, stop: -.pi / 2, mode: .open)
                } else {
                    drawArc(center: head.center, radiusX: reach, radiusY: reach,
                            start: -.pi / 2, stop: -.pi / 2 + sweep, mode: .open)
                }
            }
            if along > turn {
                drawLine(tail.x, head.center.y, tail.x, head.center.y + min(fall, along - turn))
            }
            noStroke()
        case .window:
            let fall = bottom - head.center.y
            let y = head.center.y + share * fall
            stroke(windowWhite)
            strokeWeight(lineWidth)
            fill(windowStems[tail.slot % 2])
            drawRect(tail.x - gap / 2, head.center.y, gap, y - head.center.y)
            noStroke()
        }
    }

    /// Deals the clusters and the bands for the seed, and lists the strokes
    /// right to left.
    private func deal() -> Picture {
        randomSeed(variation)
        var result: [Cluster] = []
        let half = width / 2

        // The ground bands, in whole lanes, on the left half and reflected.
        var bands: [Band] = []
        if look == .oil {
            var taken = Set<Int>()
            if random() < 0.6 {
                // A band astride the axis: as many lanes as keeps it there.
                let wide = lanes % 2 == 0 ? 2 : 1 + 2 * Int(random(0, 2))
                let lane = (lanes - wide) / 2
                bands.append(Band(lane: lane, lanes: wide))
                (lane - 1 ... lane + wide).forEach { taken.insert($0) }
            }
            let count = 1
            var placed = 0, tries = 0
            while placed < count, tries < 50 {
                tries += 1
                let wide = 1 + Int(random(0, 3))
                let lane = 1 + Int(random(0, Double(lanes / 2 - wide - 1)))
                let range = lane ..< lane + wide
                guard !range.contains(where: { taken.contains($0) }) else { continue }
                (lane - 1 ... lane + wide).forEach { taken.insert($0) }
                bands.append(Band(lane: lane, lanes: wide))
                if mirrored { bands.append(Band(lane: lanes - lane - wide, lanes: wide)) }
                placed += 1
            }
        }

        // The clusters: one on the axis first when the count is odd and the
        // picture mirrored, then the rest on lane centers, kept apart, on
        // the left half when mirrored and reflected after.
        let wanted = clusters
        let axisCluster = mirrored && wanted % 2 == 1
        let sideClusters = mirrored ? wanted / 2 : wanted
        var extents: [ClosedRange<Double>] = []
        var axis: Cluster?
        if axisCluster, let cluster = makeCluster(anchor: half, side: .left, symmetric: true) {
            axis = cluster
            extents.append(extentOf(cluster))
        }
        var tries = 0
        while result.count < sideClusters, tries < 2000 {
            tries += 1
            let limit = mirrored ? half : width
            let lane = Int(random(1, limit / unit - 1))
            let anchor = (Double(lane) + 0.5) * unit
            let side: Side = mirrored ? .left : (random() < 0.5 ? .left : .right)
            guard let cluster = makeCluster(anchor: anchor, side: side, symmetric: false) else { continue }
            let extent = extentOf(cluster)
            guard extent.lowerBound > 0.5 * unit, extent.upperBound < limit - 0.5 * unit,
                  !extents.contains(where: { $0.overlaps(extent) }) else { continue }
            extents.append(extent)
            result.append(cluster)
        }
        if mirrored {
            result += result.map(reflect)
        }
        if let axis {
            result.append(axis)
        }

        // Right to left, as Urdu reads: the clusters by anchor, the heads of
        // each from the top down, each head then its tail.
        var strokes: [Stroke] = []
        var lengths: [Double] = []
        let order = result.indices.sorted { result[$0].anchor > result[$1].anchor }
        for c in order {
            let cluster = result[c]
            let heads = cluster.heads.indices.sorted { cluster.heads[$0].center.y < cluster.heads[$1].center.y }
            for h in heads {
                strokes.append(.head(cluster: c, head: h))
                lengths.append(2 * .pi * cluster.heads[h].radius)
                for t in cluster.tails.indices where cluster.tails[t].head == h {
                    strokes.append(.tail(cluster: c, tail: t))
                    let head = cluster.heads[h]
                    let reach = abs(head.center.x - cluster.tails[t].x)
                    lengths.append((look == .oil ? reach * .pi / 2 : 0) + height - head.center.y)
                }
            }
        }
        return Picture(clusters: result, bands: bands, strokes: strokes, lengths: lengths,
                       total: lengths.reduce(0, +))
    }

    /// The left and right reach of a cluster, tails included.
    private func extentOf(_ cluster: Cluster) -> ClosedRange<Double> {
        var low = Double.infinity, high = -Double.infinity
        for head in cluster.heads {
            low = min(low, head.center.x - head.radius)
            high = max(high, head.center.x + head.radius)
        }
        for tail in cluster.tails {
            low = min(low, tail.x - gap)
            high = max(high, tail.x + gap)
        }
        return low ... high
    }

    private func reflect(_ cluster: Cluster) -> Cluster {
        var mirror = cluster
        mirror.anchor = width - cluster.anchor
        mirror.heads = cluster.heads.map {
            Head(center: Vector2(width - $0.center.x, $0.center.y), radius: $0.radius, paint: $0.paint)
        }
        mirror.tails = cluster.tails.map {
            Tail(head: $0.head, side: $0.side == .left ? .right : .left, x: width - $0.x,
                 slot: $0.slot, isHook: $0.isHook)
        }
        return mirror
    }

    /// Lays the heads of one cluster, each touching one laid before it, then
    /// drops the tails. In the oils the heads stack, each below the last or
    /// below and a little away from the tails, so the top head's hook stays
    /// tight; the tails hang on the cluster's outer side, the lowest head's
    /// innermost and the top head's outermost, a gap apart. In the window the
    /// heads bunch, beside as well as below, and each stem stands under its
    /// own head, pushed just far enough to clear its neighbor. A symmetric
    /// cluster is laid on the right of its anchor, drifting toward it, and
    /// reflected across it as it grows.
    private func makeCluster(anchor: Double, side: Side, symmetric: Bool) -> Cluster? {
        let count = look == .oil ? 1 + Int(random(0, 4)) : 2 + Int(random(0, 6))
        let top = look == .oil ? random(0.06, 0.32) * height : random(0.03, 0.26) * height
        func radius() -> Double {
            look == .oil ? 1.1 * unit : unit * randomChoice([0.6, 0.8, 1.0, 1.2, 1.5])
        }
        // Down is a half turn; a drift is a ninth or a sixth of a turn off it.
        let down = Double.pi / 2
        let away: Double = symmetric ? 1 : (side == .left ? -1 : 1)
        let angles: [Double] = look == .oil
            ? [down, down - away * .pi / 9, down - away * .pi / 6, down - away * .pi / 3]
            : [down, down - .pi / 6, down + .pi / 6, down - .pi / 3, down + .pi / 3, 0, .pi]

        var heads: [Head] = []
        let first = radius()
        if symmetric, count > 1, look == .oil || random() < 0.5 {
            // Two heads astride the axis: always in the oils, where a lone
            // head on the axis would hook over the whole cluster.
            let paint = Int(random(0, 5))
            heads.append(Head(center: Vector2(anchor + first, top + first), radius: first, paint: paint))
            heads.append(Head(center: Vector2(anchor - first, top + first), radius: first, paint: paint))
        } else {
            heads.append(Head(center: Vector2(anchor, top + first), radius: first, paint: Int(random(0, 5))))
        }
        var tries = 0
        while heads.count < count, tries < 80 {
            tries += 1
            let candidates = symmetric ? heads.indices.filter { heads[$0].center.x >= anchor - 1e-9 } : Array(heads.indices)
            let against = heads[candidates[Int(random(0, Double(candidates.count)))]]
            let r = radius()
            let angle = randomChoice(angles)
            var center = against.center + Vector2(cos(angle), sin(angle)) * (against.radius + r)
            if symmetric {
                let x = abs(center.x - anchor) < 1e-9 ? anchor : max(center.x, anchor)
                center = Vector2(x, center.y)
            }
            guard center.y > top + r - 1e-9, center.y + r < 0.6 * height else { continue }
            guard !heads.contains(where: { ($0.center - center).length < $0.radius + r - 1e-6 }) else { continue }
            let paint = Int(random(0, 5))
            heads.append(Head(center: center, radius: r, paint: paint))
            if symmetric, center.x > anchor + 1e-9 {
                let twin = Vector2(2 * anchor - center.x, center.y)
                guard !heads.contains(where: { ($0.center - twin).length < $0.radius + r - 1e-6 }) else {
                    heads.removeLast()
                    continue
                }
                heads.append(Head(center: twin, radius: r, paint: paint))
            }
        }

        var tails: [Tail] = []
        func leftEdge(_ indices: [Int]) -> Double { indices.map { heads[$0].center.x - heads[$0].radius }.min()! }
        func rightEdge(_ indices: [Int]) -> Double { indices.map { heads[$0].center.x + heads[$0].radius }.max()! }

        /// The oils: slots a gap apart from the edge outward, the lowest
        /// head first.
        func hang(_ indices: [Int], side: Side) {
            guard !indices.isEmpty else { return }
            let edge = side == .left ? leftEdge(indices) : rightEdge(indices)
            let direction: Double = side == .left ? -1 : 1
            let ordered = indices.sorted { heads[$0].center.y > heads[$1].center.y }
            for (i, h) in ordered.enumerated() {
                tails.append(Tail(head: h, side: side, x: edge + direction * Double(i + 1) * gap,
                                  slot: i + 1, isHook: i == ordered.count - 1))
            }
        }

        /// The window: a stem under each head, the run pushed apart to a gap
        /// and recentered, or pushed outward from the axis past the stems
        /// of the heads on it.
        func stand(_ indices: [Int], side: Side, fromAxis: Bool, past: Int = 0) {
            guard !indices.isEmpty else { return }
            let direction: Double = side == .left ? -1 : 1
            let ordered = indices.sorted { (heads[$0].center.x - heads[$1].center.x) * direction < 0 }
            var xs = ordered.map { heads[$0].center.x }
            let floor = fromAxis ? anchor + direction * (Double(past) + 1) * gap / 2 : -Double.infinity * direction
            if fromAxis { xs[0] = direction > 0 ? max(xs[0], floor) : min(xs[0], floor) }
            for i in 1 ..< xs.count {
                xs[i] = direction > 0 ? max(xs[i], xs[i - 1] + gap) : min(xs[i], xs[i - 1] - gap)
            }
            if !fromAxis {
                let shift = zip(xs, ordered).map { $0 - heads[$1].center.x }.reduce(0, +) / Double(xs.count)
                xs = xs.map { $0 - shift }
            }
            for (i, h) in ordered.enumerated() {
                tails.append(Tail(head: h, side: side, x: xs[i], slot: i + 1, isHook: false))
            }
        }

        if symmetric {
            let right = heads.indices.filter { heads[$0].center.x > anchor + 1e-9 }
            let left = heads.indices.filter { heads[$0].center.x < anchor - 1e-9 }
            let axis = heads.indices.filter { abs(heads[$0].center.x - anchor) <= 1e-9 }
            if look == .oil {
                hang(right + axis, side: .right)
                hang(left + axis, side: .left)
            } else {
                // The heads on the axis stand centered on it, a gap apart.
                for (i, h) in axis.sorted(by: { heads[$0].center.y < heads[$1].center.y }).enumerated() {
                    let x = anchor + (Double(i) - Double(axis.count - 1) / 2) * gap
                    tails.append(Tail(head: h, side: .right, x: x, slot: i + 1, isHook: false))
                }
                stand(right, side: .right, fromAxis: true, past: axis.count)
                stand(left, side: .left, fromAxis: true, past: axis.count)
            }
        } else if look == .oil {
            hang(Array(heads.indices), side: side)
        } else {
            stand(Array(heads.indices), side: side, fromAxis: false)
        }
        return Cluster(heads: heads, tails: tails, anchor: anchor)
    }
}
