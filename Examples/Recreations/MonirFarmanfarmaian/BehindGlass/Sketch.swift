//  Recreation after Monir Shahroudy Farmanfarmaian - the Maze series (2014
//  and 2015), mirror mosaic and reverse-glass painting: a triangle, a square,
//  a pentagon, and a hexagon, each laid out as spiral channels of painted
//  glass between strips of mirror.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or her estate.
//  https://www.jamescohan.com/artists/monir-shahroudy-farmanfarmaian
//
//  An original Ollin interpretation, written from the works and from how
//  reverse-glass painting is done. Nothing was ported: the works were made by
//  hand in her Tehran studio.

import Ollin

/// After the Maze series (Monir Shahroudy Farmanfarmaian, 2014 and 2015). In
/// the mazes, a polygon is laid out as channels that spiral in toward the
/// middle, the channels cut from glass painted a mottled green on the back
/// and edged in blue, the strips between them cut from mirror. Painting on
/// the back of glass, a technique that reached Iran from Europe, has one rule
/// that decides everything: you paint the picture backwards, in both senses.
/// What you paint first is what is seen on top, so the fine lines go down
/// first, the color after them, and the backing last, and everything you
/// paint is the mirror image of what will be seen.
///
/// The sketch paints one pane that way. The polygon is split into kites, one
/// at each corner, and a channel spirals into each kite at a steady `band` from
/// lap to lap. A kite always has a circle that touches all four of its sides,
/// which is what lets a spiral stepped in from every side meet in the middle
/// without any side running out first.
///
/// From behind, in the order the painter works: the blue lines along both
/// edges of every channel and around the flower at the center, then the green
/// sponged into the channels and the red into the petals, then silver over
/// the whole back, which hides everything painted before it. Then the pane
/// turns over. From the front the silver is at the back, the green over it,
/// the blue lines on top, and every spiral turns the other way. The pane
/// hangs for `hold` seconds with light moving across the silver, and the next
/// panel starts: triangle, square, pentagon, hexagon, and on up to the
/// octagon. `firstSides` is the panel the run starts on, `pace` sets how fast
/// the hand works, and a press moves on to the next panel.
///
/// `--export-svg pane.svg` gives back every mark in the order it was painted,
/// so a frame from behind and a frame from the front can be compared: the
/// same marks in the opposite order of layers, each one reflected.
@main
final class BehindGlass: Sketch {
    @Param(3 ... 8, icon: "hexagon") var firstSides = 6
    @Param(20 ... 60, icon: "lines.measurement.horizontal") var band = 30.0
    @Param(0.25 ... 4, icon: "paintbrush.pointed") var pace = 1.0
    @Param(0 ... 30, icon: "clock") var hold = 8.0

    private let wall = Color(hex: 0xEDE9E1)
    private let edge = Color(hex: 0x1C1C1C)
    private let blue = Color(hex: 0x2B45C2)
    /// The sponge's greens, dark to pale, and the flat coat under them.
    private nonisolated static let greens: [Color] = [Color(hex: 0x123F2B), Color(hex: 0x1D5C40),
                                                      Color(hex: 0x2F7A52), Color(hex: 0x6E9F6B)]
    private let coat = Color(hex: 0x1F6043)
    private let petal = Color(hex: 0xB3322B)
    private let petalLine = Color(hex: 0x5B1713)
    private let silverLight = Color(hex: 0xF1F3F4)
    private let silverDark = Color(hex: 0x9EA5AC)

    /// How long each stage of a panel takes at `pace` 1, in seconds.
    private let lineTime = 6.0, colorTime = 5.0, silverTime = 2.4
    private let restTime = 0.8, turnTime = 1.4

    /// One spot of paint pressed on with a sponge.
    private struct Dab {
        var center: Vector2
        var radius: Double
        var color: Color
    }

    /// Everything painted on one pane, laid out as it is seen from the front.
    private struct Pane {
        var outline: [Vector2]
        var kites: [[Vector2]]
        /// The channel's middle, and its two edges, for each kite.
        var channels: [[[Vector2]]]
        var edges: [[[Vector2]]]
        var dabs: [[Dab]]
        var petals: [[Vector2]]
        var heart: [Vector2]
    }

    private var pane: Pane?
    private var began = 0.0
    private var index = 0
    private var program = (first: 0, band: 0.0)

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func mousePressed() {
        index += 1
        pane = nil
    }

    override func draw() {
        background(wall)
        let wanted = (first: firstSides, band: band)
        if program != wanted {
            program = wanted
            index = 0
            pane = nil
        }
        if pane == nil {
            let sides = 3 + (firstSides - 3 + index) % 6
            pane = Self.lay(sides: sides, radius: 400, band: band, at: paneCenter)
            began = time
        }
        guard let pane else { return }

        let t = (time - began) * pace
        let painted = lineTime + colorTime + silverTime + restTime
        if t > painted + turnTime + hold * pace {
            index += 1
            self.pane = nil
        }

        // The turn: seen from behind the pane is drawn reflected, and it
        // narrows to its edge and opens again the right way round.
        let turn = min(1, max(0, (t - painted) / turnTime))
        let facing = -cos(.pi * ease(turn))
        let fromBehind = facing < 0

        withState {
            translate(paneCenter.x, paneCenter.y)
            scale(facing, 1)
            translate(-paneCenter.x, -paneCenter.y)

            let line = min(1, t / lineTime)
            let color = min(1, max(0, (t - lineTime) / colorTime))
            let silver = min(1, max(0, (t - lineTime - colorTime) / silverTime))
            if fromBehind {
                paintLines(pane, upTo: line)
                paintColor(pane, upTo: color)
                paintSilver(pane, upTo: silver)
            } else {
                paintSilver(pane, upTo: 1)
                paintColor(pane, upTo: 1)
                paintLines(pane, upTo: 1)
            }
            noFill()
            stroke(edge)
            strokeWeight(5)
            drawPolyline(pane.outline, closed: true)
        }

        let caption: String
        if t < lineTime { caption = "from behind: the lines first" }
        else if t < lineTime + colorTime { caption = "from behind: then the color" }
        else if t < painted { caption = "from behind: the silver last" }
        else if !fromBehind { caption = "turned over" }
        else { caption = "turning the pane over" }
        noStroke()
        drawText(caption, width / 2, height - 44, size: 22, color: Color(hex: 0x6B665E),
                 align: .center, .middle)
    }

    private func paintLines(_ pane: Pane, upTo f: Double) {
        guard f > 0 else { return }
        noFill()
        strokeCap(.round)
        strokeJoin(.round)
        stroke(blue)
        strokeWeight(3)
        for kite in pane.edges {
            for path in kite {
                let part = Self.prefix(path, fraction: f)
                if part.count > 1 { drawPolyline(part) }
            }
        }
        stroke(petalLine)
        strokeWeight(2.5)
        for outline in pane.petals + [pane.heart] {
            let part = Self.prefix(outline + [outline[0]], fraction: f)
            if part.count > 1 { drawPolyline(part) }
        }
    }

    private func paintColor(_ pane: Pane, upTo f: Double) {
        guard f > 0 else { return }
        // A flat coat first, then the sponge, so no silver shows through.
        noFill()
        stroke(coat)
        strokeCap(.butt)
        strokeJoin(.round)
        strokeWeight(band / 2 - 2)
        for kite in pane.channels {
            for path in kite {
                let part = Self.prefix(path, fraction: f)
                if part.count > 1 { drawPolyline(part) }
            }
        }
        noStroke()
        for kite in pane.dabs {
            for dab in kite.prefix(Int(Double(kite.count) * f)) {
                fill(dab.color)
                drawCircle(center: dab.center, radius: dab.radius)
            }
        }
        fill(petal)
        for outline in pane.petals.prefix(Int((Double(pane.petals.count) * f).rounded(.up))) {
            drawPolygon(outline)
        }
        if f >= 1 {
            fill(Color(hex: 0xE2B64B))
            drawPolygon(pane.heart)
        }
    }

    private func paintSilver(_ pane: Pane, upTo f: Double) {
        guard f > 0 else { return }
        noStroke()
        // The light crosses the silver slowly, so the backing reads as mirror.
        let sweep = sin(time * 0.35) * 160
        let from = paneCenter + Vector2(-420 + sweep, -420)
        let to = paneCenter + Vector2(420 + sweep, 420)
        for (i, kite) in pane.kites.enumerated() {
            let amount = min(1, max(0, f * Double(pane.kites.count) - Double(i)))
            guard amount > 0 else { continue }
            fill(Gradient.linear(from: from, to: to,
                                 [silverDark.withAlpha(amount), silverLight.withAlpha(amount),
                                  silverDark.withAlpha(amount), silverLight.withAlpha(amount)]))
            drawPolygon(kite)
        }
    }

    /// Where the pane hangs, a little above the middle to leave room for the
    /// caption.
    private var paneCenter: Vector2 { Vector2(width / 2, height / 2 - 20) }

    private func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    /// Lays out one pane: the kites, the spiral in each, the sponge marks, and
    /// the flower where the kites meet.
    private nonisolated static func lay(sides n: Int, radius: Double, band: Double,
                                        at center: Vector2) -> Pane {
        let sector = 2 * Double.pi / Double(n)
        // Screen y runs down, so a corner at the top is at -pi/2; an even
        // polygon hangs flat along its top edge instead.
        let top = -Double.pi / 2 + (n % 2 == 0 ? sector / 2 : 0)
        let corners = (0 ..< n).map { i in
            center + Vector2(cos(top + Double(i) * sector), sin(top + Double(i) * sector)) * radius
        }
        let middles = (0 ..< n).map { (corners[$0] + corners[($0 + 1) % n]) / 2 }
        let heartRadius = radius * 0.16

        var kites: [[Vector2]] = [], channels: [[[Vector2]]] = [], edges: [[[Vector2]]] = []
        var dabs: [[Dab]] = []
        for i in 0 ..< n {
            let kite = [middles[(i + n - 1) % n], corners[i], middles[i], center]
            kites.append(kite)
            let middle = spiral(in: kite, first: band / 2, step: band)
            let clear = heartRadius + band / 3
            channels.append(clip(middle, outside: center, radius: clear))
            // The channel's two edges, one out and the other back, so the blue
            // line closes across both ends of the channel.
            let outer = spiral(in: kite, first: band / 4, step: band, corners: middle.count - 1)
            let inner = spiral(in: kite, first: 3 * band / 4, step: band, corners: middle.count - 1)
            edges.append(clip(outer + inner.reversed() + [outer[0]], outside: center, radius: clear))
            // Sponge marks along the channel, the same for every kite, so the
            // pane keeps its turn.
            var marks: [Dab] = []
            var walked = 0.0
            for path in channels[i] {
                for (a, b) in zip(path, path.dropFirst()) {
                    let length = (b - a).length
                    var s = 0.0
                    while s < length {
                        let p = a + (b - a) * (s / length)
                        let across = Vector2(-(b - a).y, (b - a).x) / length
                        let step = walked + s
                        let r = band * (0.13 + 0.1 * hash(step * 12.9898))
                        let off = (hash(step * 78.233) - 0.5) * 2 * max(0, band / 4 - r - 1)
                        // Mostly the darker greens, now and then a pale vein.
                        let shade = pow(hash(step * 3.17), 1.6)
                        let k = shade * Double(greens.count - 1)
                        let j = min(greens.count - 2, Int(k))
                        let color = greens[j].mixed(with: greens[j + 1], k - Double(j)).withAlpha(0.6)
                        marks.append(Dab(center: p + across * off, radius: r, color: color))
                        s += band * 0.12
                    }
                    walked += length
                }
            }
            dabs.append(marks)
        }

        // The flower: one petal toward every corner, and a heart.
        let petals = (0 ..< n).map { i -> [Vector2] in
            let a = top + Double(i) * sector
            let tip = Vector2(cos(a), sin(a)) * heartRadius * 0.95
            let side = Vector2(-sin(a), cos(a)) * heartRadius * 0.3
            return (0 ... 16).map { j -> Vector2 in
                let u = Double(j) / 16
                let along = tip * u
                return center + along + side * sin(.pi * u)
            } + (1 ..< 16).reversed().map { j -> Vector2 in
                let u = Double(j) / 16
                return center + tip * u - side * sin(.pi * u)
            }
        }
        let heart = (0 ..< 24).map { j -> Vector2 in
            let a = Double(j) / 24 * 2 * .pi
            return center + Vector2(cos(a), sin(a)) * heartRadius * 0.22
        }
        return Pane(outline: corners, kites: kites, channels: channels, edges: edges,
                    dabs: dabs, petals: petals, heart: heart)
    }

    /// A number in 0..<1 that looks random but depends only on `x`, so a mark
    /// made at the same distance along every kite's channel is the same mark.
    private nonisolated static func hash(_ x: Double) -> Double {
        fract(sin(x) * 43758.5453)
    }

    /// A spiral stepped in from the sides of a convex quadrilateral that has an
    /// inscribed circle: each side's line moves in by `step / 4` more than the
    /// one before, so a lap is `step` inside the last, and the corners are
    /// where one moved line meets the next. `corners` of them, or as many as
    /// fit before the lines reach the middle.
    private nonisolated static func spiral(in quad: [Vector2], first: Double, step: Double,
                                           corners: Int? = nil) -> [Vector2] {
        let area = zip(quad, quad.dropFirst() + [quad[0]]).reduce(0.0) { $0 + $1.0.cross($1.1) } / 2
        let orientation = area > 0 ? 1.0 : -1.0
        let perimeter = zip(quad, quad.dropFirst() + [quad[0]]).reduce(0.0) { $0 + ($1.1 - $1.0).length }
        let inradius = abs(area) / (perimeter / 2)
        func line(_ g: Int, _ d: Double) -> (point: Vector2, direction: Vector2) {
            let a = quad[g % 4], b = quad[(g + 1) % 4]
            let direction = (b - a).normalized
            let inward = Vector2(-direction.y, direction.x) * orientation
            return (a + inward * d, direction)
        }
        func meet(_ l: (point: Vector2, direction: Vector2), _ m: (point: Vector2, direction: Vector2)) -> Vector2 {
            let t = (m.point - l.point).cross(m.direction) / l.direction.cross(m.direction)
            return l.point + l.direction * t
        }
        var points = [meet(line(0, first), line(3, 0))]
        var g = 0
        while corners.map({ g < $0 }) ?? (first + step * Double(g + 1) / 4 < inradius - step / 4) {
            points.append(meet(line(g, first + step * Double(g) / 4),
                               line(g + 1, first + step * Double(g + 1) / 4)))
            g += 1
        }
        return points
    }

    /// Splits a polyline into the runs that stay outside the circle around
    /// the flower. Only a segment that comes near the circle is cut into short
    /// pieces, so a run ends close to the circle and the rest stays light.
    private nonisolated static func clip(_ path: [Vector2], outside center: Vector2,
                                         radius: Double) -> [[Vector2]] {
        var runs: [[Vector2]] = [], run: [Vector2] = []
        func visit(_ p: Vector2) {
            if (p - center).length > radius {
                run.append(p)
            } else {
                if run.count > 1 { runs.append(run) }
                run = []
            }
        }
        for (a, b) in zip(path, path.dropFirst()) {
            let along = b - a, length = along.length
            let t = max(0, min(1, (center - a).dot(along) / max(length * length, 1e-9)))
            let nearest = (a + along * t - center).length
            let pieces = nearest > radius + 2 ? 1 : max(1, Int(length / 3))
            for j in 0 ..< pieces {
                visit(a + along * (Double(j) / Double(pieces)))
            }
        }
        if let last = path.last { visit(last) }
        if run.count > 1 { runs.append(run) }
        return runs
    }

    /// The first `fraction` of a polyline by length.
    private nonisolated static func prefix(_ path: [Vector2], fraction: Double) -> [Vector2] {
        guard fraction < 1 else { return path }
        let total = zip(path, path.dropFirst()).reduce(0.0) { $0 + ($1.1 - $1.0).length }
        var left = total * fraction
        var out = [path[0]]
        for (a, b) in zip(path, path.dropFirst()) {
            let length = (b - a).length
            if left >= length { out.append(b); left -= length } else {
                out.append(a + (b - a) * (left / max(length, 1e-9)))
                break
            }
        }
        return out
    }
}
