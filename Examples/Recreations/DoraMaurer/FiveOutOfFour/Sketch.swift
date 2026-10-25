//  Recreation after Dóra Maurer - 5 out of 4 (1979, acrylic on wood,
//  190 x 240 cm, private collection), 5 out of 4 (1975, tempera on cardboard,
//  five panels of 50 x 40 cm), and 4 out of 3 (1976, wood and mirror,
//  100 x 300 cm, Tate). A homage, not a reproduction, and not affiliated with
//  or endorsed by the artist or her estate.
//  https://doramaurer.com/artists/maurer-dora/works
//  https://www.tate.org.uk/art/artworks/maurer-4-out-of-3-t15452
//
//  An original Ollin interpretation, written from the works themselves as the
//  artist's catalog and Tate photograph them, and from the Ludwig Museum's
//  account of the series (the colored motifs follow the frames of the
//  canvases, but the right side of a frame is displaced onto the next canvas).
//  The rule, read off all three works alike: frames laid side by side, and
//  the run cut into one panel more than there are frames, every panel the
//  same width. Nothing was ported; the proportions of the 1975 and 1979
//  panels and the 1976 frames are measured from those photographs, and the
//  motion, the wall, and the wood are this sketch's own.

import Foundation
import Ollin

/// 5 out of 4 (Dóra Maurer, 1975 and 1979; 4 out of 3, 1976). Four frames
/// stand side by side, and the run of them is cut into five panels of equal
/// width, so a frame no longer fits on a panel: the first panel holds the
/// first frame without its right side, which has gone onto the second panel
/// beside the next frame's left side, and the seams between frames move along
/// the panels a quarter of a panel at a time until the last panel holds only
/// the last frame's right side. Hung apart, the five panels read as five
/// pictures, each a different state of the same four frames; side by side
/// they close up into the four again. Maurer painted it in 1975 as four
/// fields of black and white stripes, each turned an eighth of a turn from the
/// one before, and in 1979 as frames in crimson and blue on white panels; in
/// 1976 she cut three wooden frames into four and hung the pieces apart.
///
/// This sketch keeps the rule: `frames` frames, cut into `frames` + 1 panels.
/// Over a lap the frames stand whole, the cuts run down the seams, the panels
/// part and hang, and then they close up again. `look` picks the 1979
/// painting, the 1975 stripes, or the 1976 wood; `seconds` is the length of
/// the lap.
///
/// `--export-svg` gives every panel back as its ground and every piece of a
/// frame as a rectangle (or, in the stripes, every stripe as a polygon) at
/// its place on the wall, so the rule can be read from the file: the panels
/// all one width, as many as the frames and one more, each holding exactly
/// the pieces of the frames that the cut leaves on it, moved by the panel's
/// own displacement.
@main
final class FiveOutOfFour: Sketch {
    /// The three works, by their medium.
    enum Look: String, CaseIterable, ParamOption {
        /// 1979: frames in crimson and blue, alternating, on white panels.
        case painted
        /// 1975: fields of black and white stripes, each turned 45 degrees.
        case tempera
        /// 1976: wooden frames, cut and hung on wires.
        case wood
    }

    @Param(icon: "paintpalette") var look = Look.painted
    @Param(1 ... 6, icon: "square.split.2x1") var frames = 4
    @Param(4 ... 30, icon: "clock") var seconds = 10.0

    override var canvasSize: CanvasSize { .size(2160, 864) }
    override var loopDuration: Double? { seconds }

    /// The row in its own measure: `frame` wide and `height` tall a frame,
    /// `band` the width of the band each frame is painted or built from.
    struct Row {
        var count: Int
        var frame: Double
        var height: Double
        var band: Double
        /// The panel's width: the run of frames over one more panel than frames.
        var panel: Double { Double(count) * frame / Double(count + 1) }

        /// The four bands of frame `k`, from the row's left end and top: the two
        /// rails across its full width, and the two posts between them.
        func bands(of k: Int) -> [Rectangle] {
            let x = Double(k) * frame
            return [Rectangle(x: x, y: 0, width: frame, height: band),
                    Rectangle(x: x, y: height - band, width: frame, height: band),
                    Rectangle(x: x, y: band, width: band, height: height - 2 * band),
                    Rectangle(x: x + frame - band, y: band, width: band, height: height - 2 * band)]
        }

        /// The stretch of the row that panel `j` carries.
        func span(of j: Int) -> ClosedRange<Double> {
            Double(j) * panel ... Double(j + 1) * panel
        }

        /// The frames that reach into panel `j`.
        func frames(on j: Int) -> [Int] {
            let span = span(of: j)
            return (0 ..< count).filter { k in
                Double(k + 1) * frame > span.lowerBound + 1e-9 && Double(k) * frame < span.upperBound - 1e-9
            }
        }

        /// `rect` cut to the stretch of panel `j`, or nil if none of it is there.
        func cut(_ rect: Rectangle, to j: Int) -> Rectangle? {
            let span = span(of: j)
            let x0 = max(rect.x, span.lowerBound), x1 = min(rect.x + rect.width, span.upperBound)
            guard x1 - x0 > 1e-9 else { return nil }
            return Rectangle(x: x0, y: rect.y, width: x1 - x0, height: rect.height)
        }
    }

    /// 1979: the crimson and the blue, the white of the panels, and the wall.
    static let crimson = Color(hex: 0x700D2C)
    static let blue = Color(hex: 0x1042F1)

    override func draw() {
        let row = makeRow()
        let n = row.count

        // The lap: the frames stand whole, the cuts run down the seams, the
        // panels part and hang, they close up, and the seams heal.
        let u = (time / max(0.5, seconds)).truncatingRemainder(dividingBy: 1)
        let cut = eased(u, 0.12, 0.3)
        let apart = eased(u, 0.35, 0.55) - eased(u, 0.8, 0.93)
        let healed = eased(u, 0.93, 1)

        // Each panel's place: side by side, or hung with a gap between panels.
        let gap = row.panel * gapRatio
        let wholeLeft = (width - Double(n + 1) * row.panel) / 2
        let hungLeft = (width - Double(n + 1) * row.panel - Double(n) * gap) / 2
        let top = look == .wood ? height * 0.27 : (height - row.height) / 2
        let offsets = (0 ... n).map { j in
            let whole = wholeLeft, hung = hungLeft + Double(j) * gap
            return whole + (hung - whole) * apart
        }

        switch look {
        case .painted: background(Color(hex: 0xDCDEDA))
        case .tempera: background(Color(hex: 0xCBCCC8))
        case .wood: background(Color(hex: 0xEFEEE9))
        }
        noStroke()

        // Every shadow first, so that no panel's shadow falls across the
        // panel beside it and the frames stand whole until they are cut.
        let corners = (0 ... n).map { j in Vector2(offsets[j], top) }
        let panels = (0 ... n).map { j in
            Rectangle(x: offsets[j] + Double(j) * row.panel, y: top, width: row.panel, height: row.height)
        }
        for j in 0 ... n {
            if look == .wood {
                hang(row, on: j, offset: corners[j])
            } else {
                shadow(of: [panels[j]], depth: row.panel * 0.03, apart: apart)
            }
        }
        // Then every ground, and only then what is painted or built on them:
        // a shape's softened edge reaches a little past it, so a ground laid
        // after its neighbor's frame would lighten the frame along the seam.
        switch look {
        case .painted, .tempera:
            fill(look == .painted ? Color(hex: 0xF3F4F0) : Color(hex: 0xF1F0EB))
            for panel in panels { drawRect(panel) }
            for j in 0 ... n {
                if look == .painted {
                    paintFrames(row, on: j, offset: corners[j])
                } else {
                    paintStripes(row, on: j, offset: corners[j])
                }
            }
        case .wood:
            for layer in WoodLayer.allCases {
                for j in 0 ... n { buildFrames(row, on: j, offset: corners[j], layer: layer) }
            }
        }

        // The cuts: a hairline down each seam while the row is whole.
        let seamAlpha = (1 - healed) * (1 - apart)
        if cut > 0, seamAlpha > 0.01 {
            stroke(Color(hex: 0x2A2A2A).withAlpha(0.55 * seamAlpha))
            strokeWeight(1.2)
            strokeCap(.butt)
            for j in 1 ... n {
                let x = wholeLeft + Double(j) * row.panel
                drawLine(x, top - 2, x, top - 2 + (row.height + 4) * cut)
            }
            noStroke()
        }

        drawText("\(n + 1) out of \(n)", width * 0.04, height * 0.93, size: height * 0.026,
                 color: Color(hex: 0x3A3A38).withAlpha(0.8), align: .left, .middle)
    }

    /// The row for the look and the count, sized so the hung panels fill the
    /// wall's width. The painted panels are 3 by 4 and the stripes 4 by 5, as
    /// the 1979 and 1975 panels are; the wooden frames keep their own shape
    /// and the panels follow from them.
    private func makeRow() -> Row {
        let n = max(1, frames)
        let fit = width * 0.88 / (Double(n + 1) + Double(n) * gapRatio)
        switch look {
        case .painted:
            let panel = min(fit, height * 0.74 * 0.75)
            let h = panel / 0.75
            return Row(count: n, frame: panel * Double(n + 1) / Double(n), height: h, band: h / 12)
        case .tempera:
            let panel = min(fit, height * 0.74 * 0.8)
            let h = panel / 0.8
            return Row(count: n, frame: panel * Double(n + 1) / Double(n), height: h, band: 0)
        case .wood:
            let h = min(height * 0.6, fit * Double(n + 1) / Double(n) / 0.43)
            let frame = h * 0.43
            return Row(count: n, frame: frame, height: h, band: h * 0.07)
        }
    }

    /// The gap between hung panels as a share of a panel's width.
    private var gapRatio: Double {
        switch look {
        case .painted: 0.1
        case .tempera: 0.04
        case .wood: 0.8
        }
    }

    /// 1979: every band of every frame that reaches the panel, cut to it, the
    /// frames crimson and blue in turn.
    private func paintFrames(_ row: Row, on j: Int, offset: Vector2) {
        for k in row.frames(on: j) {
            fill(k % 2 == 0 ? Self.crimson : Self.blue)
            for band in row.bands(of: k) {
                guard let piece = row.cut(band, to: j) else { continue }
                drawRect(piece.x + offset.x, piece.y + offset.y, piece.width, piece.height)
            }
        }
    }

    /// 1975: each frame a field of stripes, the first upright and each next one
    /// turned 45 degrees further, half black and half white at a pitch of a
    /// fortieth of the panel, cut to the panel like the frames.
    private func paintStripes(_ row: Row, on j: Int, offset: Vector2) {
        let pitch = row.panel / 40
        fill(Color(hex: 0x141414))
        for k in row.frames(on: j) {
            let field = Rectangle(x: Double(k) * row.frame, y: 0, width: row.frame, height: row.height)
            guard let piece = row.cut(field, to: j) else { continue }
            let angle = Double.pi / 2 + Double(k) * Double.pi / 4
            let across = Vector2(-sin(angle), cos(angle))
            let anchor = Vector2(field.x, field.y)
            let corners = [piece.topLeft, piece.topRight, piece.bottomRight, piece.bottomLeft]
            let reach = corners.map { ($0 - anchor).dot(across) }
            let first = Int((reach.min()! / pitch).rounded(.down))
            let last = Int((reach.max()! / pitch).rounded(.up))
            for m in first ... last {
                let low = Double(m) * pitch, high = low + pitch / 2
                let stripe = Self.clip(Self.clip(corners, across, anchor, low, keepsAbove: true),
                                       across, anchor, high, keepsAbove: false)
                // A stripe that only touches the piece's corner has no area.
                guard stripe.count >= 3, Self.area(stripe) > 1e-6 else { continue }
                drawPolygon(stripe.map { $0 + offset })
            }
        }
    }

    /// 1976: a wooden piece's two wires from above, and its shadow on the wall.
    private func hang(_ row: Row, on j: Int, offset: Vector2) {
        let span = row.span(of: j)
        stroke(Color(hex: 0x9A9A96).withAlpha(0.8))
        strokeWeight(1)
        for f in [0.18, 0.82] {
            let x = span.lowerBound + (span.upperBound - span.lowerBound) * f + offset.x
            drawLine(x, 0, x, offset.y)
        }
        noStroke()
        var pieces: [Rectangle] = []
        for k in row.frames(on: j) {
            for band in row.bands(of: k) {
                if let piece = row.cut(band, to: j) { pieces.append(piece.offsetBy(offset)) }
            }
        }
        shadow(of: pieces, depth: row.band * 0.9, apart: 1)
    }

    /// What the wood is built up from, in the order it is laid over every
    /// panel, so a seam never shows across a member.
    private enum WoodLayer: CaseIterable { case member, shade, grain }

    /// 1976: the frames in wood, cut to the panel, each member lit from above
    /// with the underside of a rail or the far side of a post in shade and
    /// three lines of grain along it, laid on the whole member and cut with it.
    private func buildFrames(_ row: Row, on j: Int, offset: Vector2, layer: WoodLayer) {
        for k in row.frames(on: j) {
            for (b, band) in row.bands(of: k).enumerated() {
                let isRail = b < 2
                func along(_ f: Double, _ w: Double) -> Rectangle {
                    isRail
                        ? Rectangle(x: band.x, y: band.y + band.height * f, width: band.width, height: band.height * w)
                        : Rectangle(x: band.x + band.width * f, y: band.y, width: band.width * w, height: band.height)
                }
                switch layer {
                case .member:
                    fill(Color(hex: 0xA8673A))
                    if let piece = row.cut(band, to: j) { drawRect(piece.offsetBy(offset)) }
                case .shade:
                    fill(Color(hex: 0x6E3F1E).withAlpha(0.55))
                    if let shade = row.cut(along(0.82, 0.18), to: j) { drawRect(shade.offsetBy(offset)) }
                case .grain:
                    fill(Color(hex: 0x7C4520).withAlpha(0.35))
                    for g in 0 ..< 3 {
                        if let line = row.cut(along(Self.grain(k * 4 + b, g), 0.05), to: j) {
                            drawRect(line.offsetBy(offset))
                        }
                    }
                }
            }
        }
    }

    /// A soft shadow under `rects`, cast down and to the right, stronger when
    /// the panels hang apart from one another.
    private func shadow(of rects: [Rectangle], depth: Double, apart: Double) {
        let steps = 5
        for s in 0 ..< steps {
            let grow = depth * Double(s) / Double(steps)
            fill(Color(white: 0, alpha: 0.035 * (0.6 + 0.4 * apart)))
            for r in rects {
                drawRect(r.x + depth * 0.5 - grow / 2, r.y + depth - grow / 2,
                         r.width + grow, r.height + grow)
            }
        }
    }

    /// A smoothstep from 0 at `a` to 1 at `b`.
    private func eased(_ u: Double, _ a: Double, _ b: Double) -> Double {
        let t = min(1, max(0, (u - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// The fraction across a member where its `g`-th grain line runs, fixed by
    /// the member's index.
    private static func grain(_ member: Int, _ g: Int) -> Double {
        let h = sin(Double(member * 31 + g * 17) * 12.9898) * 43758.5453
        return 0.12 + 0.6 * (h - h.rounded(.down))
    }

    /// The area a polygon encloses.
    private static func area(_ points: [Vector2]) -> Double {
        var twice = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            twice += a.x * b.y - b.x * a.y
        }
        return abs(twice) / 2
    }

    /// The part of the convex polygon `points` on one side of the line where
    /// `(p - anchor) · across == level`.
    private static func clip(_ points: [Vector2], _ across: Vector2, _ anchor: Vector2,
                             _ level: Double, keepsAbove: Bool) -> [Vector2] {
        guard !points.isEmpty else { return [] }
        func side(_ p: Vector2) -> Double {
            let d = (p - anchor).dot(across) - level
            return keepsAbove ? d : -d
        }
        var out: [Vector2] = []
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            let sa = side(a), sb = side(b)
            if sa >= 0 { out.append(a) }
            if (sa >= 0) != (sb >= 0) {
                out.append(a + (b - a) * (sa / (sa - sb)))
            }
        }
        return out
    }
}

private extension Rectangle {
    func offsetBy(_ v: Vector2) -> Rectangle {
        Rectangle(x: x + v.x, y: y + v.y, width: width, height: height)
    }
}
