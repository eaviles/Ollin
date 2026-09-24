//  Recreation after Vicente Rojo - the "Señales" series (1966-1972), the
//  paintings where the circle, the triangle, and the square became signs on
//  worked grounds. A homage, not a reproduction, and not affiliated with or
//  endorsed by the artist or his estate.
//  https://www.denverartmuseum.org/en/blog/legendary-signs-remembering-vicente-rojos-impact-modern-mexico
//  https://museoblaisten.com/Obra/2536/Vieja-senal--2
//  https://memoricamexico.gob.mx/es/memorica/Senales
//
//  An original Ollin interpretation written from the paintings: Señal sobre
//  fondo violeta (1967, oil on canvas, Denver Art Museum), Vieja señal # 2
//  (1967, oil on canvas, Colección Andrés Blaisten), and the four Señales in
//  the first room of Memórica's Vicente Rojo exhibition. Nothing was ported:
//  the series is oil on canvas.

import Ollin

/// "Señales" (Vicente Rojo, 1966-1972). His first series, and the one where
/// he began working on many canvases at once, which he did for the rest of
/// his life. Each painting is one sign, and the signs are built from the
/// circle, the triangle, and the square: a triangle standing on a bar, a
/// square turned on its corner, an arch standing on a band, the letter T
/// hanging from a crossbar. Every sign stands on the canvas's middle line,
/// mirrored left to right, and its surfaces are of two kinds. Some shapes
/// are laid flat in one color. Others are worked, scraped with the knife
/// and scratched and dripped, so that a flat triangle sits inside a worked
/// one and a worked bar crosses a flat shield. The grounds are dark and
/// split once across, and the sign often runs off the edge.
///
/// This sketch keeps painting them. A sign is a stack read down the middle
/// line: a crown (a triangle, an arch, a disk, or a triangle with its top
/// cut off), a bar (plain, a band with a row of dots, or the crossbar of a
/// T), a body (a shield, a turned square, a triangle cut and turned point
/// down, or a door standing on the bottom edge), and sometimes a foot. Each
/// piece is cut from one of the three shapes, a piece nested inside another
/// takes the other finish, and a worked piece gets its scrapes, its knife
/// marks, and its drips from the hand, which is the one thing on the canvas
/// that is not mirrored. The palettes are read off the paintings. Every
/// `pace` seconds the next sign is painted over the last: the ground rolls
/// down, the pieces are laid from the top, and then the work goes in.
/// `work` is how heavily the worked pieces are scraped, and `variation` the
/// whole series. A press starts the next sign now.
///
/// Every piece exports as its own rectangle, circle, or polygon, and every
/// worked piece's marks sit in a clip group shaped like it, so
/// `--export-svg` gives the sign back as its cut shapes with the hand laid
/// over them.
@main
final class Senales: Sketch {
    @Param(4 ... 30, icon: "clock") var pace = 10.0
    @Param(0 ... 1, icon: "paintbrush.pointed") var work = 0.7

    override var canvasSize: CanvasSize { .size(900, 1200) }

    /// The palette of one painting: the two grounds, the worked paint and
    /// the lighter and darker paint scraped into it, the flat colors, and the
    /// mark color for dots.
    private struct Family {
        var top, bottom, worked, light, dark: Color
        var flats: [Color]
        var accent: Color
    }

    /// Read off the six paintings in the header, in that order: the violet
    /// shield, the plum and blue triangle, the ochre frame on charcoal, the
    /// red square turned on its corner, the crimson house, and the red band
    /// over teal doors.
    private static let families: [Family] = [
        Family(top: Color(hex: 0x6A6456), bottom: Color(hex: 0x55504A), worked: Color(hex: 0x8C6440),
               light: Color(hex: 0xC99A62), dark: Color(hex: 0x3F3326),
               flats: [Color(hex: 0xA4599B), Color(hex: 0x4D4D4B), Color(hex: 0x55607A)],
               accent: Color(hex: 0xE8D2A8)),
        Family(top: Color(hex: 0x2E2F35), bottom: Color(hex: 0x1F2227), worked: Color(hex: 0x353849),
               light: Color(hex: 0xC98590), dark: Color(hex: 0x14151B),
               flats: [Color(hex: 0x3A0A24), Color(hex: 0x0B3A96)],
               accent: Color(hex: 0x0B0B0E)),
        Family(top: Color(hex: 0x3D342B), bottom: Color(hex: 0x33291F), worked: Color(hex: 0xA06A3E),
               light: Color(hex: 0xE0A060), dark: Color(hex: 0x5A2E1C),
               flats: [Color(hex: 0x2B2521), Color(hex: 0xA0543C)],
               accent: Color(hex: 0x2F3D8A)),
        Family(top: Color(hex: 0x55524A), bottom: Color(hex: 0x42433C), worked: Color(hex: 0xB23A30),
               light: Color(hex: 0xE0704E), dark: Color(hex: 0x5A1A14),
               flats: [Color(hex: 0x353A43), Color(hex: 0x6B50B0)],
               accent: Color(hex: 0x1F3C9A)),
        Family(top: Color(hex: 0x6C5A6C), bottom: Color(hex: 0x3A3839), worked: Color(hex: 0xA0202E),
               light: Color(hex: 0xD84452), dark: Color(hex: 0x4A0A16),
               flats: [Color(hex: 0xD8322E), Color(hex: 0x2E2C2F)],
               accent: Color(hex: 0x2A2A2E)),
        Family(top: Color(hex: 0x5A5058), bottom: Color(hex: 0x6A4E54), worked: Color(hex: 0x6E5444),
               light: Color(hex: 0xE04A3C), dark: Color(hex: 0x2A2020),
               flats: [Color(hex: 0x2E8C98), Color(hex: 0x3C3438)],
               accent: Color(hex: 0x2E8C98)),
    ]

    /// What a piece is cut from. Every piece is one of the three shapes or a
    /// cut of one: a rectangle is a square stretched, a turned square keeps
    /// its right angles, a trapezoid is a triangle with its point cut off, a
    /// shield is a square with a triangle's point, and a half-disk is a
    /// circle cut through its center.
    private enum Cut {
        case rect(Rectangle)
        case polygon([Vector2])
        case disk(Vector2, Double)
        /// A half-disk standing on a rectangle as wide as it, the two drawn
        /// as one piece: `base` is the middle of the half-disk's flat side.
        case arch(base: Vector2, radius: Double, shaft: Double)
    }

    /// One piece of a sign: its cut, its paint, and, for a worked piece, the
    /// direction the knife ran.
    private struct Piece {
        var cut: Cut
        var color: Color
        var worked: Bool
        var grain = 0.0
    }

    /// One painting: its ground, its pieces in the order they are laid, and
    /// the hand's marks.
    private struct Sign {
        var family: Family
        var horizon: Double
        /// A full-width band of the lower ground behind the bar, or none.
        var shadow: Rectangle?
        var pieces: [Piece] = []
        var marks: [Mark] = []
        var ground: [Mark] = []
        var spatter: [Vector2] = []
    }

    /// A stroke of the hand: a scrape or a knife mark inside its piece, or a
    /// drip running down from it. `piece` is the piece it belongs to, and
    /// `order` when it goes on, from 0 to 1 across the working.
    private struct Mark {
        var piece: Int
        var from: Vector2
        var to: Vector2
        var width: Double
        var color: Color
        var clipped: Bool
        var order: Double
    }

    private var current = (generation: 0, start: 0.0)
    private var previous: (generation: Int, start: Double)?
    private var nextStart = 0.0
    private var signs: [Int: Sign] = [:]
    private var built = (variation: Int.min, width: 0.0, height: 0.0, work: -1.0)
    private var pressed = false

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if built.variation != variation || built.width != width || built.height != height || built.work != work {
            built = (variation, width, height, work)
            signs = [:]
            current = (0, 0)
            previous = nil
            nextStart = pace
        }
        while time >= nextStart {
            previous = current
            current = (current.generation + 1, nextStart)
            nextStart += pace
        }
        if pressed {
            pressed = false
            previous = current
            current = (current.generation + 1, time)
            nextStart = time + pace
        }

        let scale = min(1, pace / 10)
        let local = time - current.start
        background(sign(current.generation).family.bottom)
        if let previous, local < 0.9 * scale {
            paint(sign(previous.generation), at: .infinity, scale: 1)
        }
        paint(sign(current.generation), at: local, scale: scale)
        signs = signs.filter { $0.key >= (previous?.generation ?? current.generation) }
    }

    private func sign(_ generation: Int) -> Sign {
        if let cached = signs[generation] { return cached }
        let fresh = compose(generation: generation)
        signs[generation] = fresh
        return fresh
    }

    // MARK: - Painting

    /// Paint one sign as it stands `local` seconds after it was begun. The
    /// ground rolls down in the first 0.9 seconds with its scumble, each
    /// piece is laid from its top edge down over 0.35 seconds, 0.3 seconds
    /// after the one before, and then the work goes in, piece by piece in the
    /// order they were laid, so a later piece covers an earlier one's marks
    /// and its drips. The spatter comes last. `scale` shortens the whole
    /// schedule when `pace` is under ten seconds.
    private func paint(_ sign: Sign, at local: Double, scale: Double) {
        noStroke()
        let roll = height * min(1, local / (0.9 * scale))
        fill(sign.family.top)
        drawRect(0, 0, width, min(sign.horizon, roll))
        if roll > sign.horizon {
            fill(sign.family.bottom)
            drawRect(0, sign.horizon, width, roll - sign.horizon)
        }
        if let shadow = sign.shadow, roll > shadow.y {
            fill(sign.family.bottom)
            drawRect(shadow.x, shadow.y, shadow.width, min(shadow.height, roll - shadow.y))
        }
        let zones = [Rectangle(x: 0, y: 0, width: width, height: min(sign.horizon, roll)),
                     Rectangle(x: 0, y: sign.horizon, width: width, height: max(0, roll - sign.horizon))]
        for (zone, region) in zones.enumerated() where region.height > 0 {
            withClip(region) {
                for mark in sign.ground where mark.piece == zone {
                    stroke(at: 1, mark, scale: scale)
                }
            }
        }

        let laid = 0.9 * scale
        let lay = 0.3 * scale
        let working = laid + lay * Double(sign.pieces.count) + 0.2 * scale
        let workTime = 2.6 * scale
        for (index, piece) in sign.pieces.enumerated() {
            let begun = laid + lay * Double(index)
            guard local >= begun else { break }
            let bounds = extent(of: piece.cut)
            let progress = min(1, (local - begun) / (0.35 * scale))
            if progress < 1 {
                let edge = bounds.top + (bounds.bottom - bounds.top) * progress
                withClip(Rectangle(x: -width, y: -height, width: 3 * width, height: edge + height)) {
                    draw(piece)
                }
            } else {
                draw(piece)
            }

            // The piece's work: the marks clipped to its outline, then the
            // drips that run out of it onto whatever is below.
            guard piece.worked, local >= working else { continue }
            let marks = sign.marks.filter { $0.piece == index }
            let reached = (local - working) / workTime
            withClip(clipShape(of: piece.cut)) {
                for mark in marks where mark.clipped {
                    stroke(at: reached, mark, scale: scale)
                }
            }
            for mark in marks where !mark.clipped {
                stroke(at: reached, mark, scale: scale)
            }
        }

        let spattered = working + workTime + 0.4 * scale
        guard local >= spattered, !sign.spatter.isEmpty else { return }
        strokeCap(.round)
        stroke(sign.family.dark.withAlpha(0.85))
        let shown = Int(Double(sign.spatter.count) * min(1, (local - spattered) / (0.5 * scale)))
        for (index, dot) in sign.spatter.prefix(shown).enumerated() {
            strokeWeight(3 + Double(index % 4) * 1.4)
            drawLine(dot, dot + Vector2(0.4, 0.3))
        }
        noStroke()
    }

    /// Draw one mark as far as it has got: a mark begins at its `order`
    /// through the working and runs to its full length in 0.12 seconds, a
    /// drip in 0.8.
    private func stroke(at working: Double, _ mark: Mark, scale: Double) {
        let span = (mark.clipped ? 0.12 : 0.8) / 2.6
        let grown = (working - mark.order) / span
        guard grown > 0 else { return }
        let end = grown >= 1 ? mark.to : mark.from + (mark.to - mark.from) * grown
        strokeCap(.round)
        stroke(mark.color)
        strokeWeight(mark.width)
        drawLine(mark.from, end)
        noStroke()
    }

    private func draw(_ piece: Piece) {
        noStroke()
        fill(piece.color)
        switch piece.cut {
        case let .rect(rect):
            drawRect(rect)
        case let .polygon(points):
            // Every polygon here is convex, so the fan is exact.
            drawPolygon(points)
        case let .disk(center, radius):
            drawCircle(center: center, radius: radius)
        case let .arch(base, radius, shaft):
            drawRect(base.x - radius, base.y, 2 * radius, shaft)
            drawArc(base.x, base.y, radius, radius, start: .pi, stop: 2 * .pi, mode: .chord)
        }
    }

    private func clipShape(of cut: Cut) -> Shape {
        Shape(outline(of: cut))
    }

    /// A cut's outline as a convex polygon, for the clip and for finding
    /// where its drips leave from.
    private func outline(of cut: Cut) -> [Vector2] {
        switch cut {
        case let .rect(rect):
            return [Vector2(rect.x, rect.y), Vector2(rect.x + rect.width, rect.y),
                    Vector2(rect.x + rect.width, rect.y + rect.height), Vector2(rect.x, rect.y + rect.height)]
        case let .polygon(points):
            return points
        case let .disk(center, radius):
            return (0 ..< 96).map { i in
                let a = Double(i) / 96 * 2 * .pi
                return center + Vector2(cos(a), sin(a)) * radius
            }
        case let .arch(base, radius, shaft):
            let top = (0 ... 48).map { i in
                let a = .pi + Double(i) / 48 * .pi
                return base + Vector2(cos(a), sin(a)) * radius
            }
            return top + [Vector2(base.x + radius, base.y + shaft), Vector2(base.x - radius, base.y + shaft)]
        }
    }

    private func extent(of cut: Cut) -> (top: Double, bottom: Double) {
        let ys = outline(of: cut).map(\.y)
        return (ys.min() ?? 0, ys.max() ?? 0)
    }

    // MARK: - Composing a sign

    /// Deal one sign. Everything is placed about the middle line `axis`, and
    /// a piece that nests inside another takes the other finish.
    private func compose(generation: Int) -> Sign {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation &* 1_000_003 &+ generation &* 7919 &+ 17)))
        let w = width, h = height, axis = width / 2
        let family = Senales.families[Int.random(in: 0 ..< Senales.families.count, using: &rng)]
        func roll(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
        func coin(_ p: Double) -> Bool { Double.random(in: 0 ..< 1, using: &rng) < p }
        var flatIndex = Int.random(in: 0 ..< family.flats.count, using: &rng)
        func nextFlat() -> Color {
            flatIndex = (flatIndex + 1) % family.flats.count
            return family.flats[flatIndex]
        }
        func paint(_ worked: Bool) -> Color { worked ? family.worked : nextFlat() }
        /// A polygon scaled toward `center` by `k`: the same cut, smaller.
        func nested(_ points: [Vector2], toward center: Vector2, by k: Double) -> [Vector2] {
            points.map { center + ($0 - center) * k }
        }

        // The bar is the anchor: everything else stands on it or hangs from it.
        enum BarKind { case bar, band, tee }
        let barKind: BarKind = coin(0.42) ? .bar : coin(0.55) ? .band : .tee
        let barY = h * roll(0.34 ... 0.5)
        let barHeight = h * roll(0.07 ... 0.11) * (barKind == .band ? 1.7 : 1)
        let barHalf = coin(0.45) ? w / 2 + 12 : w * roll(0.34 ... 0.46)
        let barTop = barY - barHeight / 2, barBottom = barY + barHeight / 2
        let fitHalf = min(barHalf, w * 0.47)

        var sign = Sign(family: family, horizon: coin(0.5) ? barBottom : h * roll(0.7 ... 0.86))
        if coin(0.35) {
            sign.shadow = Rectangle(x: 0, y: barTop - barHeight * 0.15, width: w, height: barHeight * 1.3)
        }
        var pieces: [Piece] = []
        var barWorked = coin(0.6)

        // The crown, standing on the bar, and what nests in it.
        let crownWorked = coin(0.55)
        switch Int.random(in: 0 ..< 10, using: &rng) {
        case 0 ..< 4:
            let half = roll(0.28 * w ... max(0.29 * w, fitHalf))
            let apex = barTop - h * roll(0.22 ... 0.4)
            let outer = [Vector2(axis, apex), Vector2(axis + half, barTop), Vector2(axis - half, barTop)]
            pieces.append(Piece(cut: .polygon(outer), color: paint(crownWorked), worked: crownWorked,
                                grain: roll(-0.1 ... 0.1)))
            if coin(0.75) {
                let inner = nested(outer, toward: Vector2(axis, barTop), by: roll(0.4 ... 0.62))
                pieces.append(Piece(cut: .polygon(inner), color: paint(!crownWorked), worked: !crownWorked))
            }
        case 4 ..< 6:
            let radius = roll(0.2 * w ... max(0.21 * w, min(fitHalf, 0.34 * w)))
            let shaft = h * roll(0.03 ... 0.13)
            pieces.append(Piece(cut: .arch(base: Vector2(axis, barTop - shaft), radius: radius, shaft: shaft + 1),
                                color: paint(crownWorked), worked: crownWorked, grain: roll(-0.06 ... 0.06)))
            if coin(0.7) {
                let k = roll(0.45 ... 0.65)
                pieces.append(Piece(cut: .arch(base: Vector2(axis, barTop - shaft * k), radius: radius * k,
                                               shaft: shaft * k + 1),
                                    color: paint(!crownWorked), worked: !crownWorked))
            }
        case 6 ..< 8:
            let radius = w * roll(0.17 ... 0.28)
            let center = Vector2(axis, barTop - radius * roll(0.35 ... 1.0))
            pieces.append(Piece(cut: .disk(center, radius), color: paint(crownWorked), worked: crownWorked,
                                grain: roll(-0.2 ... 0.2)))
            if coin(0.65) {
                pieces.append(Piece(cut: .disk(center, radius * roll(0.35 ... 0.6)), color: paint(!crownWorked),
                                    worked: !crownWorked))
            }
        default:
            let bottomHalf = roll(0.26 * w ... max(0.27 * w, fitHalf))
            let topHalf = bottomHalf * roll(0.3 ... 0.55)
            let top = barTop - h * roll(0.14 ... 0.26)
            let outer = [Vector2(axis - topHalf, top), Vector2(axis + topHalf, top),
                         Vector2(axis + bottomHalf, barTop), Vector2(axis - bottomHalf, barTop)]
            pieces.append(Piece(cut: .polygon(outer), color: paint(crownWorked), worked: crownWorked,
                                grain: roll(-0.08 ... 0.08)))
            if coin(0.6) {
                // The triangle the cut was taken from, smaller, inside it.
                let apex = barTop - (barTop - top) * bottomHalf / (bottomHalf - topHalf)
                let whole = [Vector2(axis, apex), Vector2(axis + bottomHalf, barTop), Vector2(axis - bottomHalf, barTop)]
                pieces.append(Piece(cut: .polygon(nested(whole, toward: Vector2(axis, barTop), by: roll(0.4 ... 0.6))),
                                    color: paint(!crownWorked), worked: !crownWorked))
            }
        }

        // The body, hanging from the bar, and what nests in it. `point` is
        // the body's lower left edge, where legs can stand beside it.
        let bodyWorked = coin(0.45)
        var bodyBottom = barBottom
        var point: (Vector2, Vector2)?
        switch Int.random(in: 0 ..< 10, using: &rng) {
        case 0 ..< 4:
            let half = roll(0.26 * w ... max(0.27 * w, min(fitHalf, 0.45 * w)))
            let shoulder = barBottom + h * roll(0.1 ... 0.24)
            let tip = shoulder + half * roll(0.55 ... 0.95)
            let outer = [Vector2(axis - half, barBottom - 1), Vector2(axis + half, barBottom - 1),
                         Vector2(axis + half, shoulder), Vector2(axis, tip), Vector2(axis - half, shoulder)]
            pieces.append(Piece(cut: .polygon(outer), color: paint(bodyWorked), worked: bodyWorked,
                                grain: roll(-0.08 ... 0.08)))
            if coin(0.6) {
                let inner = nested(outer, toward: Vector2(axis, (barBottom + tip) / 2), by: roll(0.55 ... 0.75))
                pieces.append(Piece(cut: .polygon(inner), color: paint(!bodyWorked), worked: !bodyWorked))
            }
            bodyBottom = tip
            point = (Vector2(axis - half, shoulder), Vector2(axis, tip))
        case 4 ..< 7:
            let d = roll(0.22 * w ... max(0.23 * w, min(fitHalf, 0.38 * w)))
            let center = Vector2(axis, barBottom + d * roll(0.55 ... 1.0))
            let outer = [Vector2(center.x, center.y - d), Vector2(center.x + d, center.y),
                         Vector2(center.x, center.y + d), Vector2(center.x - d, center.y)]
            pieces.append(Piece(cut: .polygon(outer), color: paint(bodyWorked), worked: bodyWorked,
                                grain: coin(0.5) ? .pi / 4 : -.pi / 4))
            if coin(0.75) {
                pieces.append(Piece(cut: .polygon(nested(outer, toward: center, by: roll(0.45 ... 0.7))),
                                    color: paint(!bodyWorked), worked: !bodyWorked, grain: .pi / 4))
            }
            bodyBottom = center.y + d
        case 7 ..< 9:
            let topHalf = roll(0.26 * w ... max(0.27 * w, fitHalf))
            let bottomHalf = topHalf * roll(0.25 ... 0.5)
            let bottom = barBottom + h * roll(0.2 ... 0.36)
            let outer = [Vector2(axis - topHalf, barBottom - 1), Vector2(axis + topHalf, barBottom - 1),
                         Vector2(axis + bottomHalf, bottom), Vector2(axis - bottomHalf, bottom)]
            pieces.append(Piece(cut: .polygon(outer), color: paint(bodyWorked), worked: bodyWorked,
                                grain: roll(-0.08 ... 0.08)))
            if coin(0.6) {
                let inner = nested(outer, toward: Vector2(axis, (barBottom + bottom) / 2), by: roll(0.45 ... 0.65))
                pieces.append(Piece(cut: .polygon(inner), color: paint(!bodyWorked), worked: !bodyWorked))
            }
            bodyBottom = bottom
            point = (Vector2(axis - topHalf, barBottom), Vector2(axis - bottomHalf, bottom))
        default:
            let half = w * roll(0.18 ... 0.34)
            let top = barBottom + h * roll(0.06 ... 0.18)
            pieces.append(Piece(cut: .rect(Rectangle(x: axis - half, y: top, width: 2 * half, height: h - top + 12)),
                                color: paint(bodyWorked), worked: bodyWorked, grain: roll(-0.05 ... 0.05)))
            bodyBottom = h
        }

        // The stem of a T hangs from the crossbar over the body.
        if barKind == .tee {
            let half = w * roll(0.035 ... 0.07)
            let length = max(h * 0.1, min(bodyBottom, h * 0.94) - barBottom) * roll(0.55 ... 0.85)
            let stemWorked = coin(0.4)
            pieces.append(Piece(cut: .rect(Rectangle(x: axis - half, y: barBottom - 1, width: 2 * half, height: length)),
                                color: stemWorked ? family.worked : family.flats[0], worked: stemWorked,
                                grain: .pi / 2 + roll(-0.05 ... 0.05)))
            barWorked = true
        }

        // The bar goes on over the joins, and a band carries a row of dots.
        let bar = Rectangle(x: axis - barHalf, y: barTop, width: 2 * barHalf, height: barHeight)
        pieces.append(Piece(cut: .rect(bar), color: paint(barWorked), worked: barWorked, grain: roll(-0.05 ... 0.05)))
        if barKind == .band {
            let count = Int.random(in: 7 ... 11, using: &rng)
            let spacing = 2 * min(barHalf, w / 2) / Double(count)
            let radius = min(barHeight * 0.14, spacing * 0.28)
            for i in 0 ..< count {
                let x = axis + (Double(i) - Double(count - 1) / 2) * spacing
                pieces.append(Piece(cut: .disk(Vector2(x, barY), radius), color: family.accent, worked: false))
            }
        }

        // The foot: a triangle on the bottom edge, the legs beside a point
        // that leave by the bottom edge before they meet, a flat bar across
        // the bottom, or nothing.
        let footWorked = coin(0.5)
        let foot = Int.random(in: 0 ..< 10, using: &rng)
        if foot < 3, bodyBottom < h * 0.78 {
            let half = w * roll(0.1 ... 0.2)
            let apex = h - h * roll(0.1 ... 0.18)
            pieces.append(Piece(cut: .polygon([Vector2(axis, apex), Vector2(axis + half, h + 2), Vector2(axis - half, h + 2)]),
                                color: paint(footWorked), worked: footWorked, grain: roll(-0.1 ... 0.1)))
        } else if foot < 6, let (a, b) = point {
            let along = (b - a).normalized
            let outward = Vector2(-along.y, along.x)
            let gap = w * roll(0.01 ... 0.03), thick = w * roll(0.05 ... 0.08)
            let inner = a + outward * gap
            let leaves = (h + 8 - inner.y) / along.y
            let meets = (axis - inner.x) / along.x
            if leaves < meets {
                let start = -w * roll(0.02 ... 0.1), end = leaves + thick
                let left = [inner + along * start, inner + along * end,
                            inner + along * end + outward * thick, inner + along * start + outward * thick]
                let color = paint(footWorked)
                let grain = atan2(along.y, along.x)
                pieces.append(Piece(cut: .polygon(left), color: color, worked: footWorked, grain: grain))
                pieces.append(Piece(cut: .polygon(left.reversed().map { Vector2(2 * axis - $0.x, $0.y) }),
                                    color: color, worked: footWorked, grain: .pi - grain))
            }
        } else if foot < 8, bodyBottom < h * 0.84 {
            let thick = h * roll(0.025 ... 0.045)
            let y = h * roll(max(0.86, bodyBottom / h + 0.02) ... 0.93)
            pieces.append(Piece(cut: .rect(Rectangle(x: -12, y: y, width: w + 24, height: thick)),
                                color: paint(false), worked: false))
        }

        sign.pieces = pieces
        sign.marks = hand(for: sign, using: &rng)
        sign.ground = scumble(for: sign, using: &rng)
        let spatterCount = Int(Double(Int.random(in: 4 ... 18, using: &rng)) * work)
        sign.spatter = (0 ..< spatterCount).map { _ in Vector2(roll(0 ... w), roll(0 ... h)) }
        return sign
    }

    /// The hand's marks for every worked piece, in the order a painter works
    /// a surface: broad thin passes of the lighter and darker paint along the
    /// piece's grain that cloud its tone, a scumble of shorter strokes over
    /// them, crisp scratches through to the paint below at looser angles,
    /// and a line or two of pale impasto. Drips leave from the piece's lowest
    /// edge. How much of each follows `work` and the piece's size.
    private func hand(for sign: Sign, using rng: inout SplitMix64) -> [Mark] {
        var marks: [Mark] = []
        let family = sign.family
        func roll(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
        for (index, piece) in sign.pieces.enumerated() where piece.worked {
            let points = outline(of: piece.cut)
            let xs = points.map(\.x), ys = points.map(\.y)
            let box = Rectangle(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            let area = abs(signedArea(points))
            let reach = max(box.width, box.height)
            let across = min(box.width, box.height)
            let lighter = piece.color.mixed(with: family.light, 0.6)
            let darker = piece.color.mixed(with: family.dark, 0.6)

            /// One layer of marks: how many, how wide, how long against the
            /// piece's reach, how opaque, how far off the grain, which tones,
            /// and the stretch of the working it goes on in.
            func layer(_ count: Int, width: ClosedRange<Double>, length: ClosedRange<Double>,
                       alpha: ClosedRange<Double>, spread: Double, tones: [Color], during: ClosedRange<Double>) {
                var layer: [Mark] = []
                for _ in 0 ..< max(0, count) {
                    let angle = piece.grain + roll(-spread ... spread)
                    let direction = Vector2(cos(angle), sin(angle))
                    let middle = Vector2(roll(box.x ... box.x + box.width), roll(box.y ... box.y + box.height))
                    let half = reach * roll(length) / 2
                    let tone = tones[Int.random(in: 0 ..< tones.count, using: &rng)]
                    layer.append(Mark(piece: index, from: middle - direction * half, to: middle + direction * half,
                                      width: roll(width), color: tone.withAlpha(roll(alpha)), clipped: true, order: 0))
                }
                for (k, var mark) in layer.enumerated() {
                    mark.order = during.lowerBound
                        + (during.upperBound - during.lowerBound) * Double(k) / Double(max(1, layer.count))
                    marks.append(mark)
                }
            }

            let broad = max(8, min(64, across * 0.45))
            layer(Int(area / 5000 * (0.5 + work)) + 3, width: broad * 0.5 ... broad, length: 0.4 ... 1.1,
                  alpha: 0.07 ... 0.18, spread: 0.06, tones: [lighter, darker, family.light], during: 0 ... 0.3)
            layer(Int(area / 2400 * work) + 2, width: 4 ... 13, length: 0.06 ... 0.3,
                  alpha: 0.12 ... 0.3, spread: 0.12, tones: [lighter, darker], during: 0.25 ... 0.62)
            layer(Int(area / 5200 * work) + 2, width: 0.8 ... 2.0, length: 0.1 ... 0.55,
                  alpha: 0.45 ... 0.85, spread: 0.3, tones: [family.light, family.light, family.dark],
                  during: 0.55 ... 0.82)
            if work > 0.3 {
                layer(Int.random(in: 0 ... 2, using: &rng), width: 2.5 ... 4.5, length: 0.15 ... 0.4,
                      alpha: 0.85 ... 0.95, spread: 0.2, tones: [family.light.mixed(with: .white, 0.45)],
                      during: 0.82 ... 0.86)
            }

            // Drips leave from the lowest part of the piece.
            let drips = Int(Double(Int.random(in: 0 ... 2, using: &rng)) * work + 0.5)
            for _ in 0 ..< drips {
                let x = roll(box.x + box.width * 0.15 ... box.x + box.width * 0.85)
                guard let bottom = lowest(points, at: x), bottom < height - 4 else { continue }
                let run = roll(14 ... 90) * (0.4 + work)
                marks.append(Mark(piece: index, from: Vector2(x, bottom - 3), to: Vector2(x, bottom + run),
                                  width: roll(2.4 ... 4.8), color: darker.withAlpha(0.92), clipped: false, order: 0.88))
            }
        }
        return marks
    }

    /// The ground's scumble: long faint passes across each zone, lighter and
    /// darker than it, and a few scratches. `piece` names the zone, 0 above
    /// the horizon and 1 below.
    private func scumble(for sign: Sign, using rng: inout SplitMix64) -> [Mark] {
        var marks: [Mark] = []
        func roll(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
        let zones = [(sign.family.top, 0.0, sign.horizon), (sign.family.bottom, sign.horizon, height)]
        for (zone, (color, top, bottom)) in zones.enumerated() where bottom > top {
            let count = Int((bottom - top) / 22 * (0.4 + work))
            for i in 0 ..< count {
                let scratch = i % 7 == 6
                let y = roll(top ... bottom), x = roll(-0.2 * width ... width)
                let length = width * roll(scratch ? 0.1 ... 0.4 : 0.3 ... 0.9)
                let slope = roll(-0.02 ... 0.02)
                let tone = Double.random(in: 0 ..< 1, using: &rng) < 0.5
                    ? color.mixed(with: .white, 0.25) : color.mixed(with: .black, 0.35)
                marks.append(Mark(piece: zone, from: Vector2(x, y), to: Vector2(x + length, y + length * slope),
                                  width: scratch ? roll(0.7 ... 1.4) : roll(8 ... 34),
                                  color: tone.withAlpha(scratch ? roll(0.2 ... 0.4) : roll(0.04 ... 0.1)),
                                  clipped: true, order: 0))
            }
        }
        return marks
    }

    /// Where a vertical line at `x` leaves a convex outline at its bottom.
    private func lowest(_ points: [Vector2], at x: Double) -> Double? {
        var best: Double?
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            guard (a.x - x) * (b.x - x) <= 0, a.x != b.x else { continue }
            let y = a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
            best = max(best ?? y, y)
        }
        return best
    }

    private func signedArea(_ points: [Vector2]) -> Double {
        var sum = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }
}
