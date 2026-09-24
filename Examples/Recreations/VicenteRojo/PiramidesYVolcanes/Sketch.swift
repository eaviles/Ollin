//  Recreation after Vicente Rojo - "Pirámides y volcanes", the part of the
//  "Escenarios" series (1989-2006) where the pyramid and the volcano meet,
//  read from the four prints of "Prosa del Popocatépetl" (2003, wax and
//  aquatint, 39 x 43 cm) shown in "Volcanes construidos" at the Instituto
//  Cervantes. A homage, not a reproduction, and not affiliated with or
//  endorsed by the artist or his estate.
//  https://cvc.cervantes.es/artes/rojo/galeria/galeria_15.htm
//  https://cvc.cervantes.es/artes/rojo/pitol.htm
//  https://memoricamexico.gob.mx/es/memorica/Escenarios_y_obras
//
//  An original Ollin interpretation written from the prints and from Sergio
//  Pitol's essay on the series. Nothing was ported: the works are prints and
//  paintings.

import Ollin

/// "Pirámides y volcanes" (Vicente Rojo, from 1989). In the *Escenarios*
/// Rojo painted pyramids, stelae, and volcanoes, and Sergio Pitol, writing
/// on the first of them, found the tension of the series between "the rigid
/// structure of the pyramid and the fleeting fluidity of the volcanoes":
/// Rojo "organizes an order in order to knock it down later and raise it
/// again." The four prints of *Prosa del Popocatépetl* (2003) take that
/// apart in four states. First a stepped pyramid, every course of it filled
/// with a line of small signs like writing, and one stream of lava running
/// down it. Then many streams in several colors, each one drawn as a band
/// outlined twice with round ends, some rising out of the stone and turning
/// over before they fall. Then the steps melting into lobes, the streams
/// filled solid, and last the pyramid gone soft into a mountain.
///
/// This sketch plays the four states in order and starts again. The pyramid
/// is laid course by course from the ground, `courses` of them, each course
/// written with its row of signs as it goes down. Then the volcano wakes:
/// `streams` streams break out of the steps one after another, the first
/// from the crater, and flow. A stream may rise and turn over once, and
/// after that it only falls, since lava does. Then the steps lose their
/// edges, as far as `melt` says, while the streams fill in, and the pyramid
/// is taken down from the top. `seconds` is one whole cycle, and every cycle
/// deals a new print: its colors, where the streams break out, and how they
/// fall. `variation` is the whole series.
///
/// Every course exports as a rectangle, every sign as a stroked polyline,
/// and every strand of a stream as one closed outline around the stream's
/// middle line, so `--export-svg` gives the print back as the order and the
/// fire drawn over it.
@main
final class PiramidesYVolcanes: Sketch {
    @Param(6 ... 24, icon: "square.stack.3d.up") var courses = 13
    @Param(1 ... 12, icon: "flame") var streams = 5
    @Param(0 ... 1, icon: "drop") var melt = 1.0
    @Param(12 ... 60, icon: "clock") var seconds = 24.0

    override var canvasSize: CanvasSize { .size(1100, 1000) }

    private let paper = Color(hex: 0xF2F0EA)

    /// One print's colors: the stone, the ink of its signs, the lava colors
    /// with how many streams in a cycle each gets, and how many strands
    /// outline a stream.
    private struct Look {
        var stone, ink: Color
        var lava: [(color: Color, share: Int)]
        var strands: Int
    }

    /// Read off the four prints, in their order: the grey pyramid with its
    /// one magenta stream, the sand one with red, green, and blue streams
    /// outlined twice, the ochre one with its filled streams, and the grey
    /// and ochre mountain with streams of several strands.
    private static let looks: [Look] = [
        Look(stone: Color(hex: 0xA3A3A6), ink: Color(hex: 0x505056),
             lava: [(Color(hex: 0xB23C6E), 1)], strands: 1),
        Look(stone: Color(hex: 0xBDB095), ink: Color(hex: 0x756A52),
             lava: [(Color(hex: 0xC0364E), 2), (Color(hex: 0x3F9A7E), 2), (Color(hex: 0x3858A8), 1)], strands: 2),
        Look(stone: Color(hex: 0xC98E3C), ink: Color(hex: 0x7E5424),
             lava: [(Color(hex: 0xB8284E), 2), (Color(hex: 0x3A8C74), 1), (Color(hex: 0x4460AA), 1),
                    (Color(hex: 0xD0506A), 1)], strands: 2),
        Look(stone: Color(hex: 0xB8BCB6), ink: Color(hex: 0x7D8088),
             lava: [(Color(hex: 0xB83462), 2), (Color(hex: 0x4A5CB4), 2), (Color(hex: 0x6FA88A), 1)], strands: 3),
    ]

    /// The signs a course is written with, each a few strokes in a unit box:
    /// a triangle, a T and a T upside down, a pair of uprights, a chevron, a
    /// square, a ring, a zigzag, a cross, and a step.
    private static let alphabet: [[[Vector2]]] = [
        [[Vector2(0, 1), Vector2(0.5, 0), Vector2(1, 1), Vector2(0, 1)]],
        [[Vector2(0, 0), Vector2(1, 0)], [Vector2(0.5, 0), Vector2(0.5, 1)]],
        [[Vector2(0, 1), Vector2(1, 1)], [Vector2(0.5, 1), Vector2(0.5, 0)]],
        [[Vector2(0.2, 0), Vector2(0.2, 1)], [Vector2(0.8, 0), Vector2(0.8, 1)]],
        [[Vector2(0, 0), Vector2(0.5, 1), Vector2(1, 0)]],
        [[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0, 0)]],
        [(0 ... 12).map { i in
            let a = Double(i) / 12 * 2 * .pi
            return Vector2(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a))
        }],
        [[Vector2(0, 1), Vector2(0.33, 0), Vector2(0.66, 1), Vector2(1, 0)]],
        [[Vector2(0.5, 0), Vector2(0.5, 1)], [Vector2(0, 0.5), Vector2(1, 0.5)]],
        [[Vector2(0, 1), Vector2(0, 0.5), Vector2(0.5, 0.5), Vector2(0.5, 0), Vector2(1, 0)]],
    ]

    /// One stream of lava: its middle line from the vent to where it stops,
    /// sampled every few pixels, how wide it is, and its color.
    private struct Stream {
        var line: [Vector2]
        var width: Double
        var color: Color
        /// When it breaks out and when it has run its length, as fractions
        /// of the cycle.
        var begins: Double
        var ends: Double
    }

    /// One print: the look, and the signs and streams dealt for it.
    private struct Print {
        var look: Look
        var signs: [[(glyph: Int, box: Rectangle)]]
        var streams: [Stream]
    }

    /// How many points round each cap of a strand.
    private let capSteps = 12

    private var cache: (key: [Double], print: Print)?

    // MARK: - The pyramid

    private var base: Double { height * 0.92 }
    private var summit: Double { height * 0.1 }
    private var courseHeight: Double { (base - summit) / Double(courses) }

    /// Course `k` from the ground: a rectangle centered on the middle line,
    /// each one step narrower than the one below.
    private func course(_ k: Int) -> Rectangle {
        let bottomHalf = width * 0.45, topHalf = width * 0.04
        let step = courses > 1 ? (bottomHalf - topHalf) / Double(courses - 1) : 0
        let half = bottomHalf - step * Double(k)
        let y = base - courseHeight * Double(k + 1)
        return Rectangle(x: width / 2 - half, y: y, width: 2 * half, height: courseHeight)
    }

    override func draw() {
        background(paper)
        let cycle = Int((time / seconds).rounded(.down))
        let phase = time / seconds - Double(cycle)
        let key = [Double(variation), Double(cycle), Double(courses), Double(streams), width, height]
        if cache?.key != key {
            cache = (key, deal(cycle: cycle))
        }
        guard let print = cache?.print else { return }

        // The order: laid from the ground in the first quarter, and taken
        // down from the top in the last seventh.
        let laying = 0.02 ... 0.27
        let melting = 0.72 ... 0.86
        let razing = 0.86 ... 0.98
        let soften = melt * smooth(phase, melting)
        let radius = soften * courseHeight / 2
        noStroke()
        for k in 0 ..< courses {
            let laid = laying.lowerBound + (laying.upperBound - laying.lowerBound) * Double(k) / Double(courses)
            let razed = razing.lowerBound
                + (razing.upperBound - razing.lowerBound) * Double(courses - 1 - k) / Double(courses)
            guard phase >= laid, phase < razed else { continue }
            let box = course(k)
            fill(print.look.stone)
            if radius > 0.01 {
                // Melting, a course swells past its step as its corners go.
                let swell = soften * courseHeight * 0.18
                drawRect(box.x - swell, box.y - swell * 0.4, box.width + 2 * swell, box.height + swell * 0.4,
                         cornerRadius: radius)
            } else {
                drawRect(box)
            }

            // The course's line of signs, written left to right as it is laid.
            let written = min(1, (phase - laid) / ((laying.upperBound - laying.lowerBound) / Double(courses)))
            let signs = print.signs[k]
            let shown = Int((Double(signs.count) * written).rounded(.up))
            stroke(print.look.ink.withAlpha(0.85 - 0.4 * soften))
            strokeWeight(1.4)
            strokeJoin(.round)
            noFill()
            // The joint along the course's top, where the stone above sits.
            drawPolyline([Vector2(box.x, box.y + 1), Vector2(box.x + box.width, box.y + 1)])
            for sign in signs.prefix(shown) {
                for part in PiramidesYVolcanes.alphabet[sign.glyph] {
                    drawPolyline(part.map { Vector2(sign.box.x + $0.x * sign.box.width, sign.box.y + $0.y * sign.box.height) })
                }
            }
            noStroke()
        }

        // The fire: every stream grows from its vent at its own time, fills
        // in while the steps melt, and fades while the pyramid comes down.
        let fade = 1 - smooth(phase, razing.lowerBound ... razing.lowerBound + 0.08)
        guard fade > 0 else { return }
        let fullness = 0.16 + 0.64 * smooth(phase, melting)
        for stream in print.streams where phase >= stream.begins {
            let grown = smooth(phase, stream.begins ... stream.ends)
            let count = max(2, Int((Double(stream.line.count - 1) * grown).rounded()) + 1)
            let line = Array(stream.line.prefix(count))
            let strands = print.look.strands
            for j in stride(from: strands - 1, through: 0, by: -1) {
                let half = stream.width / 2 * Double(j + 1) / Double(strands)
                let outline = strand(line, half: half)
                if j == strands - 1 {
                    fill(stream.color.withAlpha(fullness * fade))
                } else {
                    noFill()
                }
                stroke(stream.color.withAlpha(0.95 * fade))
                strokeWeight(2.4)
                drawShape { path in
                    path.move(to: outline[0])
                    for point in outline.dropFirst() { path.line(to: point) }
                    path.close()
                }
            }
        }
        noStroke()
    }

    /// One strand of a stream: the closed outline `half` either side of the
    /// middle line, down the left side, round the end, up the right side,
    /// and round the start, each cap a half circle about the line's end.
    private func strand(_ line: [Vector2], half: Double) -> [Vector2] {
        let n = line.count
        var left: [Vector2] = [], right: [Vector2] = []
        var tangents: [Vector2] = []
        for i in 0 ..< n {
            let a = line[max(0, i - 1)], b = line[min(n - 1, i + 1)]
            let tangent = (b - a).normalized
            tangents.append(tangent)
            let normal = Vector2(-tangent.y, tangent.x)
            left.append(line[i] + normal * half)
            right.append(line[i] - normal * half)
        }
        func cap(at center: Vector2, from normal: Vector2, toward tangent: Vector2) -> [Vector2] {
            (1 ..< capSteps).map { s in
                let a = Double(s) / Double(capSteps) * .pi
                return center + (normal * cos(a) + tangent * sin(a)) * half
            }
        }
        let endTangent = tangents[n - 1], startTangent = tangents[0]
        let endNormal = Vector2(-endTangent.y, endTangent.x)
        let startNormal = Vector2(-startTangent.y, startTangent.x)
        return left
            + cap(at: line[n - 1], from: endNormal, toward: endTangent)
            + right.reversed()
            + cap(at: line[0], from: startNormal * -1, toward: startTangent * -1)
    }

    /// 0 before the range, 1 after it, and an eased step between.
    private func smooth(_ x: Double, _ range: ClosedRange<Double>) -> Double {
        let t = min(1, max(0, (x - range.lowerBound) / (range.upperBound - range.lowerBound)))
        return t * t * (3 - 2 * t)
    }

    // MARK: - Dealing a print

    /// Deal the print for one cycle: the look, every course's signs, and the
    /// streams, their colors handed out by the look's shares.
    private func deal(cycle: Int) -> Print {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation &* 2_000_003 &+ cycle &* 104_729 &+ 11)))
        func roll(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
        let look = PiramidesYVolcanes.looks[Int.random(in: 0 ..< PiramidesYVolcanes.looks.count, using: &rng)]

        // Each course written from end to end with a margin, in two rows
        // when the course is tall enough to hold them, the signs packed
        // close like a line of writing.
        var signs: [[(glyph: Int, box: Rectangle)]] = []
        let rows = courseHeight >= 36 ? 2 : 1
        let glyphHeight = courseHeight * (rows == 2 ? 0.34 : 0.5)
        for k in 0 ..< courses {
            let box = course(k)
            var row: [(glyph: Int, box: Rectangle)] = []
            let gap = (box.height - Double(rows) * glyphHeight) / Double(rows + 1)
            for line in 0 ..< rows {
                var x = box.x + glyphHeight * roll(0.3 ... 0.6)
                let top = box.y + gap + Double(line) * (glyphHeight + gap)
                while true {
                    let glyphWidth = glyphHeight * roll(0.55 ... 1.0)
                    guard x + glyphWidth <= box.x + box.width - glyphHeight * 0.3 else { break }
                    row.append((Int.random(in: 0 ..< PiramidesYVolcanes.alphabet.count, using: &rng),
                                Rectangle(x: x, y: top, width: glyphWidth, height: glyphHeight)))
                    x += glyphWidth + glyphHeight * roll(0.12 ... 0.32)
                }
            }
            signs.append(row)
        }

        // The colors by smooth weighted round robin: every stream, each
        // color earns its share and the richest is dealt, so a cycle of
        // streams as long as the shares add up to holds each color exactly
        // its share.
        let shares = look.lava.map { Double($0.share) }
        let total = shares.reduce(0, +)
        var credit = shares.map { _ in 0.0 }
        var colors: [Color] = []
        let skip = Int.random(in: 0 ..< Int(total), using: &rng)
        for step in 0 ..< streams + skip {
            for i in credit.indices { credit[i] += shares[i] }
            let richest = credit.indices.max { credit[$0] < credit[$1] || (credit[$0] == credit[$1] && $0 > $1) }!
            credit[richest] -= total
            if step >= skip { colors.append(look.lava[richest].color) }
        }

        // The streams: the first from the crater, the rest spread across
        // the face in lanes, each breaking out of a step wide enough to
        // hold it, a little after the one before, in a dealt order.
        let eruption = 0.3 ... 0.5
        var lanes = Array(1 ..< max(1, streams))
        lanes.shuffle(using: &rng)
        var dealt: [Stream] = []
        for s in 0 ..< streams {
            let width = self.width * roll(0.022 ... 0.03)
            var vent = Vector2(self.width / 2, course(courses - 1).y)
            if s > 0 {
                let lane = lanes[s - 1]
                let span = self.width * 0.84
                let x = self.width / 2 - span / 2 + span * (Double(lane - 1) + roll(0.25 ... 0.75)) / Double(streams - 1)
                let steps = (Int(Double(courses) * 0.3) ..< courses).filter { abs(x - self.width / 2) < course($0).width / 2 * 0.85 }
                let k = steps.isEmpty ? 0 : steps[Int.random(in: 0 ..< steps.count, using: &rng)]
                vent = Vector2(x, course(k).y)
            }
            let begins = eruption.lowerBound
                + (eruption.upperBound - eruption.lowerBound) * Double(s) / Double(max(1, streams))
            dealt.append(Stream(line: flow(from: vent, width: width, using: &rng),
                                width: width, color: colors[s], begins: begins, ends: begins + roll(0.08 ... 0.14)))
        }
        return Print(look: look, signs: signs, streams: dealt)
    }

    /// The middle line of one stream from its vent. Half the streams rise
    /// first and turn over in a half circle, away from the middle line more
    /// often than not; then every stream falls, swinging to one side and
    /// back as it goes, never turning tighter than its own width allows, and
    /// stops somewhere down the slope or at the ground.
    private func flow(from vent: Vector2, width: Double, using rng: inout SplitMix64) -> [Vector2] {
        func roll(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
        let spacing = 3.0
        var line = [vent]
        var head = vent
        let outward: Double = vent.x >= self.width / 2 ? 1 : -1
        if Double.random(in: 0 ..< 1, using: &rng) < 0.5 {
            let radius = width * roll(0.8 ... 1.6)
            let rise = min(courseHeight * roll(0.3 ... 1.2), max(courseHeight * 0.2, vent.y - radius - height * 0.03))
            let side = Double.random(in: 0 ..< 1, using: &rng) < 0.7 ? outward : -outward
            let steps = max(1, Int(rise / spacing))
            for i in 1 ... steps {
                line.append(Vector2(vent.x, vent.y - rise * Double(i) / Double(steps)))
            }
            let center = Vector2(vent.x + side * radius, vent.y - rise)
            let arcSteps = max(8, Int(.pi * radius / spacing))
            for i in 1 ... arcSteps {
                let a = .pi * Double(i) / Double(arcSteps)
                line.append(center + Vector2(-side * cos(a), -sin(a)) * radius)
            }
            head = line[line.count - 1]
        }

        let wavelength = (base - summit) * roll(0.35 ... 0.7)
        let k = 2 * .pi / wavelength
        let widest = 1 / (k * k * (width / 2 + 6))
        let amplitude = min(widest, width * roll(0.3 ... 1.2))
        let swing: Double = Double.random(in: 0 ..< 1, using: &rng) < 0.5 ? 1 : -1
        let shortest = (base - summit) * 0.2
        let reach = head.y + max(shortest, (base - head.y) * roll(0.35 ... 1.0))
        let end = min(reach, base - width / 2)
        var y = head.y
        while y < end {
            y = min(end, y + spacing)
            let x = head.x + swing * amplitude * (1 - cos(k * (y - head.y)))
            line.append(Vector2(x, y))
        }
        return line
    }
}
