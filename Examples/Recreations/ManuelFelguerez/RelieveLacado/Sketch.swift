//  Recreation after Manuel Felguerez - the lacquered reliefs and sculptures of
//  1975 to 1977 that grew out of "La maquina estetica", the program he wrote
//  with the engineer Mayer Sasson: designs the machine composed and weighed,
//  raised off the board in lacquered layers. A homage, not a reproduction,
//  and not affiliated with or endorsed by the artist or his estate.
//  https://cultura.uam.mx/manuel-felguerez-una-maquina-estetica/
//
//  An original Ollin interpretation. The composing half repeats the rules the
//  sibling MaquinaEstetica honors (the six by eight field lying down, the
//  four margins touched, an alphabet of eight elements, balance as the test);
//  the finishing half is a reading of the lacquered pieces, not a catalog of
//  them. Nothing was ported: the machine's program is unpublished.

import Foundation
import Ollin

/// A design "La maquina estetica" accepted, raised into a lacquered relief.
///
/// The machine made drawings. Felguerez kept the ones he wanted and took them
/// on: to paint, and by 1976 to reliefs and sculptures in lacquered metal and
/// board, each element of a design cut out, set a step above the last, and
/// finished under a coat of lacquer. This sketch does that second half. It
/// composes and weighs a design exactly as the sibling `MaquinaEstetica`
/// does, so `variation` names the same design there and here, and then
/// raises it: the board is the lowest layer, the largest element sits on it,
/// and each smaller one stands a step higher, so the machine's paint order
/// becomes the relief's depth. Every layer wears lacquer. The board and the
/// black elements take a piano finish, the two accent tones a lacquered
/// color, and the element the pen had left as an outline becomes the one
/// plate of bare aluminum. A key light rakes across the board and circles
/// slowly, so the shadows the layers throw turn with it; that light, more
/// than the color, is what a relief has that the drawing did not.
///
/// `view` picks how it is seen: `relief` walks slowly round it, `wall` is the
/// gallery view, straight on and orthographic, and `drawing` is the plan the
/// machine handed over, flat and exportable (`--export-svg`). `depth` is the
/// step between layers. `unlit` turns the lights off, which shows what the
/// relief keeps of the drawing: seen straight on with no light it is the
/// drawing again. `elements`, `tolerance` and `showRule` are the machine's
/// own controls, and the test the design passed can be drawn on the plan.
@main
final class RelieveLacado: Sketch {
    enum View: String, CaseIterable, ParamOption { case relief, wall, drawing }

    @Param(icon: "eye") var view = View.relief
    @Param(4 ... 12, icon: "square.on.circle") var elements = 7.0
    @Param(0.15 ... 1.5, icon: "scalemass") var tolerance = 0.5
    @Param(0.05 ... 0.4, icon: "arrow.up.and.down") var depth = 0.16
    @Param(icon: "lightbulb.slash") var unlit = false
    @Param(icon: "ruler") var showRule = false

    /// The format: eight units across, six down, lying flat.
    private let across = 8.0
    private let down = 6.0
    /// The board under everything, in the same units.
    private let board = 0.25

    override var canvasSize: CanvasSize { .size(1440, 1080) }

    /// Lacquer laid on by hand: the coat a little less than a mirror.
    private let lacquer: Material = {
        var coat = Material.lacquer
        coat.clearcoatRoughness = 0.2
        return coat
    }()

    private let cream = Color(red: 0.93, green: 0.89, blue: 0.80)
    private let ink = Color(red: 0.09, green: 0.08, blue: 0.08)
    private let aluminum = Color(red: 0.84, green: 0.85, blue: 0.87)
    /// Sober tones, the range his canvases keep to.
    private let tones = [
        Color(red: 0.80, green: 0.59, blue: 0.20),
        Color(red: 0.63, green: 0.24, blue: 0.17),
        Color(red: 0.27, green: 0.35, blue: 0.45),
        Color(red: 0.56, green: 0.53, blue: 0.43),
        Color(red: 0.33, green: 0.31, blue: 0.29),
    ]

    private var design = Design()
    private var composedFor = ""

    override func draw() {
        // One design per seed, and it stays until the seed or the machine's
        // own controls change.
        let key = "\(variation)/\(Int(elements.rounded()))/\(tolerance)"
        if key != composedFor {
            design = compose()
            composedFor = key
        }

        if view == .drawing {
            drawThePlan()
            return
        }

        background(Color(red: 0.30, green: 0.29, blue: 0.28))
        placeCamera()
        light()

        // The board, then the elements in the machine's order, each a step
        // above the last. Every one is a slab from the board up to its top.
        withState {
            translate(0, 0, board / 2)
            fill(cream)
            material(lacquer)
            drawExtrude(raised(rectangle(across, down)), depth: board)
        }
        for (order, part) in design.parts.enumerated() {
            let top = board + Double(order + 1) * depth
            let at = Vector2(part.box.center.x - across / 2, down / 2 - part.box.center.y)
            withState {
                translate(at.x, at.y, top / 2)
                fill(color(of: part))
                material(part.tone == 3 ? .metal(roughness: 0.18) : lacquer)
                for outline in outlines(of: part) {
                    drawExtrude(raised(outline), depth: top)
                }
            }
        }
    }

    /// The plan: the same outlines flat, in the machine's order, with its test
    /// drawn over it on request.
    private func drawThePlan() {
        background(Color(red: 0.30, green: 0.29, blue: 0.28))
        noStroke()
        let unit = self.unit
        let field = Rectangle(center: center, width: across * unit, height: down * unit)
        fill(cream)
        drawPolygon(rectangle(across, down).map { field.center + $0 * unit })
        for part in design.parts {
            fill(color(of: part))
            for outline in outlines(of: part) {
                let points = outline.map { field.corner + (part.box.center + $0) * unit }
                // A quarter ring bends in along its inner arc, so it goes
                // through the shape call; the rest are convex.
                if part.element == .band {
                    drawShape(Shape(points, closed: true))
                } else {
                    drawPolygon(points)
                }
            }
        }
        if showRule { drawTheRule(field, unit: unit) }
    }

    /// Pixels per field unit, the field filling most of the canvas.
    private var unit: Double { min(width * 0.80 / across, height * 0.80 / down) }

    private func placeCamera() {
        // The shadow map is boxed to the eye's distance, so the eye stays as
        // near as the board's own size allows and the map's texels stay fine.
        if view == .wall {
            ortho(eye: Vector3(0, 0, 6), target: .zero, height: height / unit)
            return
        }
        // A slow walk in front of the wall: side to side, a little above.
        let sway = sin(time * 2 * .pi / 31) * 0.42
        let elevation = 0.2 + sin(time * 2 * .pi / 47) * 0.08
        let eye = Vector3(sin(sway) * cos(elevation), sin(elevation), cos(sway) * cos(elevation)) * 9.5
        perspective(eye: eye, target: .zero, fieldOfView: 0.72)
    }

    private func light() {
        if unlit {
            noLights()
            return
        }
        // The studio for the lacquer to reflect, kept out of the picture; a warm
        // key raking across the board and circling once a minute, so the
        // shadows of the layers turn; a dim fill so the shaded sides keep their
        // color.
        environment(.studio.intensified(to: 0.35).lightingOnly())
        toneMap(.aces)
        ambientLight(Color(white: 0.06))
        let rake = time * 2 * .pi / 60
        let grazing = 0.3
        let direction = Vector3(-cos(rake) * cos(grazing), -sin(rake) * cos(grazing), -sin(grazing))
        directionalLight(Color(red: 1, green: 0.95, blue: 0.86), direction: direction, intensity: 1.5)
        directionalLight(Color(white: 0.7), direction: (Vector3(0, -0.2, -0.5) - direction).normalized,
                         intensity: 0.2, castsShadow: false)
        castShadows()
    }

    private func color(of part: Part) -> Color {
        switch part.tone {
        case 1: return design.accents.first ?? ink
        case 2: return design.accents.count > 1 ? design.accents[1] : ink
        case 3: return aluminum
        default: return ink
        }
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

    /// The element as closed outlines about the center of its footprint, in
    /// field units, already given its quarter turn. What the pen ruled comes
    /// back as bars, together covering the share of the field the machine
    /// weighed a ruled element at.
    private func outlines(of part: Part) -> [[Vector2]] {
        let (w, h) = upright(part)
        var shapes: [[Vector2]] = []
        switch part.element {
        case .bar, .block:
            shapes = [rectangle(w, h)]
        case .disk:
            shapes = [(0 ..< 48).map { Vector2(cos(Double($0) / 48 * 2 * .pi), sin(Double($0) / 48 * 2 * .pi)) * (w / 2) }]
        case .halfDisk:
            shapes = [(0 ... 24).map { step in
                let angle = .pi + .pi * Double(step) / 24
                return Vector2(0, h / 2) + Vector2(cos(angle), sin(angle)) * (w / 2)
            }]
        case .wedge:
            let corner = Vector2(-w / 2, h / 2)
            var points = [corner]
            for step in 0 ... 16 {
                let angle = 1.5 * .pi + 0.5 * .pi * Double(step) / 16
                points.append(corner + Vector2(cos(angle), sin(angle)) * w)
            }
            shapes = [points]
        case .triangle:
            shapes = [[Vector2(-w / 2, h / 2), Vector2(w / 2, h / 2), Vector2(-w / 2, -h / 2)]]
        case .band:
            shapes = [bandOutline(at: Vector2(-w / 2, h / 2), outer: w, wall: part.thickness)]
        case .ruled:
            let lines = max(2, Int(h / 0.18))
            let bar = 0.35 * h / Double(lines + 1)
            // The end bars keep inside the footprint, so a ruled element at
            // the margin touches it and never crosses it.
            let step = (h - bar) / Double(lines)
            for line in 0 ... lines {
                let y = -h / 2 + bar / 2 + Double(line) * step
                shapes.append([Vector2(-w / 2, y - bar / 2), Vector2(w / 2, y - bar / 2),
                               Vector2(w / 2, y + bar / 2), Vector2(-w / 2, y + bar / 2)])
            }
        }
        return shapes.map { $0.map { turned($0, by: part.turn) } }
    }

    private func rectangle(_ w: Double, _ h: Double) -> [Vector2] {
        [Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2), Vector2(w / 2, h / 2), Vector2(-w / 2, h / 2)]
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

    /// The same outline in the 3D plane: y up, wound counter-clockwise.
    private func raised(_ outline: [Vector2]) -> [Vector2] {
        let flipped = outline.map { Vector2($0.x, -$0.y) }
        var area = 0.0
        for i in flipped.indices {
            let a = flipped[i], b = flipped[(i + 1) % flipped.count]
            area += a.x * b.y - b.x * a.y
        }
        return area < 0 ? flipped.reversed() : flipped
    }

    // MARK: Composing, as the machine does

    /// Roll designs until one passes the test, and keep the best of the run if
    /// none of them do. The seed is the variation, so the design is the one
    /// the machine turns out first for the same seed.
    private func compose() -> Design {
        randomSeed(variation &* 7919)

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
            // A quarter disk's weight sits 4r / 3pi from the corner along each side.
            let pull = 0.4244 * wide
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

    /// The test made visible on the plan: the field, how far off center the
    /// design was allowed to sit, and where its weight actually landed.
    private func drawTheRule(_ field: Rectangle, unit: Double) {
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
    }
}
