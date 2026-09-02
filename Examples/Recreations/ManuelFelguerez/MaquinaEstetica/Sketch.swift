//  Recreation after Manuel Felguerez - "La maquina estetica" (1975-1977), the
//  program he built with the engineer Mayer Sasson at Harvard. It composed
//  designs in the geometric language of his own paintings, and a plotter drew
//  them, one every eleven seconds. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist or his estate.
//  https://cultura.uam.mx/manuel-felguerez-una-maquina-estetica/
//
//  An original Ollin interpretation, written from the work and from published
//  accounts of how the machine was made. Nothing was ported: the program ran on
//  a mainframe, it is not published, and the program here is not it. The rules
//  honored below are the published ones (the six by eight format, the touched
//  margins, an alphabet of eight elements, and balance as the test). The eight
//  elements themselves are a reading of his shapes, not his catalog.

import Foundation
import Ollin

/// "La maquina estetica" (Manuel Felguerez and Mayer Sasson, 1975-1977): a
/// machine that composes in an artist's own language, and an artist who then
/// keeps, refuses, or reworks what it makes.
///
/// Felguerez first took his own paintings apart. He cut the shapes out of them
/// and weighed the pieces, because he held that the information in a picture
/// sits in the balance between its forms, not in the forms themselves. From
/// that study came a model: an alphabet of eight simple elements, and rules the
/// composition must obey. Every design lies down in a field of six by eight
/// units, eight of them across. Each of the four invisible margins of that
/// field must be touched by at least one element. A random term makes each design different, and the
/// weighed balance decides which ones may stand.
///
/// So this sketch composes the way the machine did. It rolls a design, weighs
/// the ink of every element, and finds the center of that weight. If the center
/// sits far from the middle of the field, the sheet goes in the bin and it
/// rolls another one. What you watch is the survivor, and a new one arrives
/// every `seconds`. The machine took eleven seconds per drawing; on a screen
/// that wait reads as a slideshow, so the default runs at five, and `seconds`
/// at 11 gives the machine's own pace.
///
/// The plotter made drawings, not pictures. Felguerez then painted the ones he
/// kept. `penOnly` shows the two ends of that process: on, you get the drawing
/// the machine hands over; off, the sober tones he took it to.
///
/// Try it: `variation` is the whole piece, so step the seed in the inspector
/// and keep the design you like. `--export-grid sheet.png --seeds 36` prints
/// the pile the plotter turned out in a day, which is where his own choosing
/// began. `showRule` draws the field, the tolerance, and the center of the
/// weight, so you can watch the test the design had to pass.
@main
final class MaquinaEstetica: Sketch {
    @Param(4 ... 12, icon: "square.on.circle") var elements = 7.0
    @Param(0.15 ... 1.5, icon: "scalemass") var tolerance = 0.5
    @Param(2 ... 20, icon: "clock") var seconds = 5.0
    @Param(icon: "pencil") var penOnly = false
    @Param(icon: "ruler") var showRule = false

    /// The format: eight units across, six down, lying flat.
    private let across = 8.0
    private let down = 6.0

    /// The sheet keeps the proportions of the format itself.
    override var canvasSize: CanvasSize { .size(1440, 1080) }

    private let paper = Color(red: 0.93, green: 0.92, blue: 0.89)
    private let ink = Color(red: 0.11, green: 0.10, blue: 0.10)
    /// Sober tones, the range his canvases keep to.
    private let tones = [
        Color(red: 0.80, green: 0.59, blue: 0.20),
        Color(red: 0.63, green: 0.24, blue: 0.17),
        Color(red: 0.27, green: 0.35, blue: 0.45),
        Color(red: 0.56, green: 0.53, blue: 0.43),
        Color(red: 0.33, green: 0.31, blue: 0.29),
    ]

    private var design = Design()
    private var onSheet = -1

    override func draw() {
        background(paper)

        // A new sheet every `seconds`. The first one is already on the table
        // when you arrive, so frame zero is always a finished design.
        let slot = max(1.0, seconds)
        let sheet = Int(floor(time / slot))
        if sheet != onSheet {
            design = compose(sheet)
            onSheet = sheet
        }
        let intoSheet = time - Double(sheet) * slot
        let pace = min(0.3, 1.8 / Double(max(1, design.parts.count)))

        let unit = min(width * 0.80 / across, height * 0.80 / down)
        let field = Rectangle(center: center, width: across * unit, height: down * unit)

        for (order, part) in design.parts.enumerated() {
            // The pen reaches each element in turn. The opening sheet skips
            // this, so a contact sheet at frame zero shows whole designs.
            let arrival = sheet == 0
                ? 1.0
                : min(1, max(0, (intoSheet - Double(order) * pace) / 0.22))
            if arrival <= 0 { continue }
            draw(part, in: field, unit: unit, arrival: arrival)
        }

        if showRule { drawTheRule(field, unit: unit, sheet: sheet) }
    }

    // MARK: The alphabet

    /// The eight elements the compositions are built from.
    private enum Element: CaseIterable {
        case bar, block, disk, halfDisk, wedge, triangle, band, ruled
    }

    /// One element in place: a footprint in field units, a quarter turn, and
    /// which of the design's inks it carries.
    private struct Part {
        var element = Element.block
        var box = Rectangle(x: 0, y: 0, width: 1, height: 1)
        var turn = 0
        var tone = 0
        /// The band elements are the only ones with a wall thickness.
        var thickness = 0.0
    }

    private struct Design {
        var parts: [Part] = []
        var accents: [Color] = []
        /// How far the center of the weight sits from the middle of the field.
        var offset = 0.0
        var tries = 0
    }

    /// The element's size before its quarter turn, since a turn lays the
    /// footprint on its side.
    private func upright(_ part: Part) -> (width: Double, height: Double) {
        part.turn % 2 == 0
            ? (part.box.width, part.box.height)
            : (part.box.height, part.box.width)
    }

    // MARK: Composing

    /// Roll designs until one passes the test, and keep the best of the run if
    /// none of them do. The seed is the sheet number and the variation, so any
    /// sheet of any seed comes back the same.
    private func compose(_ sheet: Int) -> Design {
        randomSeed(variation &* 7919 &+ sheet &* 104_729)

        let count = Int(elements.rounded())
        var accents = tones
        var chosen: [Color] = []
        for _ in 0 ..< 2 where !accents.isEmpty {
            let pick = Int(random(0, Double(accents.count)))
            chosen.append(accents.remove(at: min(pick, accents.count - 1)))
        }

        var best = Design()
        for attempt in 1 ... 60 {
            // Elements are allowed to lie over one another, which his pictures
            // do, but not to bury one another.
            var parts: [Part] = []
            for _ in 0 ..< count {
                var part = roll()
                for _ in 0 ..< 10 where buries(part, parts) { part = place(part) }
                parts.append(part)
            }
            touchTheMargins(&parts)

            let candidate = Design(parts: parts.sorted { area(of: $0) > area(of: $1) },
                                   accents: chosen,
                                   offset: imbalance(of: parts),
                                   tries: attempt)
            if attempt == 1 || candidate.offset < best.offset { best = candidate }
            if candidate.offset <= tolerance { return candidate }
        }
        best.tries = 60
        return best
    }

    /// One element, sized and placed by the roll of the die.
    private func roll() -> Part {
        var part = Part()
        part.element = randomChoice(Element.allCases)
        part.turn = Int(random(0, 4)) % 4

        var wide = 0.0, high = 0.0
        switch part.element {
        case .bar:
            wide = snap(random(2.5, 5.5)); high = 0.5
        case .block:
            wide = snap(random(1.25, 3)); high = snap(random(1, 2.5))
        case .disk:
            wide = snap(random(1, 3)); high = wide
        case .halfDisk:
            wide = snap(random(1.5, 3.5)); high = wide / 2
        case .wedge:
            wide = snap(random(1, 3)); high = wide
        case .triangle:
            wide = snap(random(1.25, 3)); high = snap(random(1.25, 3))
        case .band:
            wide = snap(random(2, 3.5)); high = wide
            // A wall thin enough that the ring still reads as a ring.
            part.thickness = snap(wide * random(0.14, 0.3))
        case .ruled:
            wide = snap(random(1.5, 4)); high = snap(random(1, 2.5))
        }
        if part.turn % 2 == 1 { swap(&wide, &high) }

        part.box = Rectangle(x: 0, y: 0, width: wide, height: high)
        // The ink: mostly black, two accents, and now and then an outline only.
        part.tone = randomChoice([0, 0, 0, 1, 1, 2, 3])
        return place(part)
    }

    /// The same element, dropped somewhere else in the field.
    private func place(_ part: Part) -> Part {
        var moved = part
        moved.box = Rectangle(x: snap(random(0, across - part.box.width)),
                              y: snap(random(0, down - part.box.height)),
                              width: part.box.width, height: part.box.height)
        return moved
    }

    /// True when the element would cover more than half of one already there,
    /// or be covered that far itself.
    private func buries(_ part: Part, _ others: [Part]) -> Bool {
        for other in others {
            let wide = min(part.box.corner.x + part.box.width, other.box.corner.x + other.box.width)
                - max(part.box.corner.x, other.box.corner.x)
            let high = min(part.box.corner.y + part.box.height, other.box.corner.y + other.box.height)
                - max(part.box.corner.y, other.box.corner.y)
            guard wide > 0, high > 0 else { continue }
            let smaller = min(part.box.width * part.box.height,
                              other.box.width * other.box.height)
            if smaller > 0, wide * high / smaller > 0.5 { return true }
        }
        return false
    }

    /// His rule: every margin of the field carries at least one element. The
    /// nearest element slides out to meet any margin left untouched.
    private func touchTheMargins(_ parts: inout [Part]) {
        guard !parts.isEmpty else { return }
        let edge = 0.02

        func slide(_ index: Int, to box: Rectangle) { parts[index].box = box }

        if !parts.contains(where: { $0.box.corner.x <= edge }) {
            let i = nearest(parts) { $0.box.corner.x }
            slide(i, to: Rectangle(x: 0, y: parts[i].box.corner.y,
                                   width: parts[i].box.width, height: parts[i].box.height))
        }
        if !parts.contains(where: { $0.box.corner.x + $0.box.width >= across - edge }) {
            let i = nearest(parts) { across - ($0.box.corner.x + $0.box.width) }
            slide(i, to: Rectangle(x: across - parts[i].box.width, y: parts[i].box.corner.y,
                                   width: parts[i].box.width, height: parts[i].box.height))
        }
        if !parts.contains(where: { $0.box.corner.y <= edge }) {
            let i = nearest(parts) { $0.box.corner.y }
            slide(i, to: Rectangle(x: parts[i].box.corner.x, y: 0,
                                   width: parts[i].box.width, height: parts[i].box.height))
        }
        if !parts.contains(where: { $0.box.corner.y + $0.box.height >= down - edge }) {
            let i = nearest(parts) { down - ($0.box.corner.y + $0.box.height) }
            slide(i, to: Rectangle(x: parts[i].box.corner.x, y: down - parts[i].box.height,
                                   width: parts[i].box.width, height: parts[i].box.height))
        }
    }

    private func nearest(_ parts: [Part], by distance: (Part) -> Double) -> Int {
        var index = 0
        for (i, part) in parts.enumerated() where distance(part) < distance(parts[index]) {
            index = i
        }
        return index
    }

    // MARK: Weighing

    /// The area of ink the element lays down, in square units. This is the
    /// weight of the piece he would have cut out and put on the scale.
    private func area(of part: Part) -> Double {
        let (wide, high) = upright(part)
        switch part.element {
        case .bar, .block:
            return wide * high
        case .disk:
            return .pi * (wide / 2) * (wide / 2)
        case .halfDisk:
            let radius = wide / 2
            return .pi * radius * radius / 2
        case .wedge:
            return .pi * wide * wide / 4
        case .triangle:
            return wide * high / 2
        case .band:
            let inner = max(wide * 0.1, wide - part.thickness)
            return .pi * (wide * wide - inner * inner) / 4
        case .ruled:
            // The pen covers about a third of the field it rules.
            return wide * high * 0.35
        }
    }

    /// Where that ink sits, as an offset from the middle of the footprint and
    /// before the quarter turn. A round shape carries its weight off center.
    private func weightOffset(of part: Part) -> Vector2 {
        let (wide, high) = upright(part)
        switch part.element {
        case .bar, .block, .disk, .ruled:
            return .zero
        case .halfDisk:
            // A half disk sits nearer its flat side than its bulge.
            return Vector2(0, high / 2 - 0.4244 * (wide / 2))
        case .wedge:
            let pull = 0.4244 * wide * 0.7071
            return Vector2(-wide / 2 + pull, high / 2 - pull)
        case .triangle:
            return Vector2(-wide / 6, high / 6)
        case .band:
            // The center of a quarter ring, out along its own diagonal.
            let inner = max(wide * 0.1, wide - part.thickness)
            let reach = (2.0 / 3.0) * 0.9003
                * (pow(wide, 3) - pow(inner, 3)) / (wide * wide - inner * inner)
            let pull = reach * 0.7071
            return Vector2(-wide / 2 + pull, high / 2 - pull)
        }
    }

    /// How far the center of the weight lies from the middle of the field, in
    /// units. This is the number the design has to keep small.
    private func imbalance(of parts: [Part]) -> Double {
        var total = 0.0
        var moment = Vector2.zero
        for part in parts {
            let weight = area(of: part)
            let at = part.box.center + turned(weightOffset(of: part), by: part.turn)
            total += weight
            moment = moment + at * weight
        }
        guard total > 0 else { return .infinity }
        let middle = Vector2(across / 2, down / 2)
        let center = moment * (1 / total)
        return (center - middle).length
    }

    /// A vector taken through the same quarter turns as its element.
    private func turned(_ v: Vector2, by turn: Int) -> Vector2 {
        switch ((turn % 4) + 4) % 4 {
        case 1: return Vector2(-v.y, v.x)
        case 2: return Vector2(-v.x, -v.y)
        case 3: return Vector2(v.y, -v.x)
        default: return v
        }
    }

    private func snap(_ value: Double) -> Double { (value * 4).rounded() / 4 }

    // MARK: Drawing

    private func draw(_ part: Part, in field: Rectangle, unit: Double, arrival: Double) {
        let (wide, high) = upright(part)
        let w = wide * unit, h = high * unit
        let at = field.corner + part.box.center * unit

        let color = penOnly ? ink : tone(part.tone)
        let outline = penOnly || part.tone == 3

        if outline {
            noFill()
            stroke(ink.withAlpha(arrival))
            strokeWeight(max(1.2, unit * 0.022))
        } else {
            fill(color.withAlpha(arrival))
            noStroke()
        }

        withState {
            translate(at)
            rotate(Double(part.turn) * .pi / 2)
            // The element settles the last hair of the way in as it lands.
            let settle = 0.985 + 0.015 * arrival
            scale(settle, settle)

            switch part.element {
            case .bar, .block:
                drawRect(center: .zero, width: w, height: h)
            case .disk:
                drawCircle(0, 0, w / 2)
            case .halfDisk:
                drawArc(center: Vector2(0, h / 2), radiusX: w / 2, radiusY: w / 2,
                        start: .pi, stop: 2 * .pi, mode: .chord)
            case .wedge:
                drawArc(center: Vector2(-w / 2, h / 2), radiusX: w, radiusY: w,
                        start: 1.5 * .pi, stop: 2 * .pi, mode: .pie)
            case .triangle:
                drawTriangle(Vector2(-w / 2, h / 2), Vector2(w / 2, h / 2), Vector2(-w / 2, -h / 2))
            case .band:
                // A quarter of a ring, cut square at both ends: hard edges, and
                // it keeps to its own square of the field.
                let wall = max(1.5, part.thickness * unit)
                drawPolygon(bandOutline(at: Vector2(-w / 2, h / 2), outer: w, wall: wall))
            case .ruled:
                // What a pen does instead of a fill: it rules the field.
                noFill()
                stroke(color.withAlpha(arrival))
                strokeWeight(max(1.0, unit * 0.018))
                let lines = max(2, Int((h / unit) / 0.18))
                let step = h / Double(lines)
                for line in 0 ... lines {
                    let y = -h / 2 + Double(line) * step
                    drawLine(Vector2(-w / 2, y), Vector2(w / 2, y))
                }
            }
        }
    }

    /// A quarter ring as an outline: out along one radius, around the outside,
    /// back along the other, and home around the inside.
    private func bandOutline(at center: Vector2, outer: Double, wall: Double) -> [Vector2] {
        let inner = max(outer * 0.1, outer - wall)
        let steps = 24
        var points: [Vector2] = []
        for step in 0 ... steps {
            let angle = 1.5 * .pi + 0.5 * .pi * Double(step) / Double(steps)
            points.append(center + Vector2(cos(angle), sin(angle)) * outer)
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let angle = 1.5 * .pi + 0.5 * .pi * Double(step) / Double(steps)
            points.append(center + Vector2(cos(angle), sin(angle)) * inner)
        }
        return points
    }

    private func tone(_ index: Int) -> Color {
        switch index {
        case 1: return design.accents.first ?? ink
        case 2: return design.accents.count > 1 ? design.accents[1] : ink
        default: return ink
        }
    }

    /// The test made visible: the field, how far off center the design was
    /// allowed to sit, and where its weight actually landed.
    private func drawTheRule(_ field: Rectangle, unit: Double, sheet: Int) {
        let middle = field.center
        noFill()
        stroke(ink.withAlpha(0.45))
        strokeWeight(1.5)
        drawRect(center: middle, width: field.width, height: field.height)
        drawCircle(middle.x, middle.y, tolerance * unit)

        var total = 0.0
        var moment = Vector2.zero
        for part in design.parts {
            let weight = area(of: part)
            total += weight
            moment = moment + (part.box.center + turned(weightOffset(of: part), by: part.turn)) * weight
        }
        if total > 0 {
            let at = field.corner + (moment * (1 / total)) * unit
            fill(Color(red: 0.63, green: 0.24, blue: 0.17))
            noStroke()
            drawCircle(at.x, at.y, max(4, unit * 0.05))
        }

        // The standard caption draws in white, which the paper would swallow.
        let verdict = design.offset <= tolerance ? "kept after" : "the best of"
        withState {
            noStroke()
            fill(ink.withAlpha(0.65))
            textFont(OutlineFont.systemMedium)
            textSize(15 * scale)
            textAlign(.center, .bottom)
            drawText("design \(sheet + 1), \(verdict) \(design.tries)",
                     width / 2, height - 28 * scale)
        }
    }
}
