import Ollin

/// Material textures by name, the line kind: wood grain, hoarfrost, the
/// crackle of batik wax, and the stepped edge of an ikat stripe, one picker
/// across them. Each is geometry the sketch holds (`WoodGrain`, `Frost`,
/// `Crackle`, `Ikat`), polylines and shapes a pen can draw, so the picture
/// plots straight to SVG with `--export-svg`. The pen draws it over the loop:
/// the strokes appear in the order a plotter would lay them, then the finished
/// sheet holds for the last stretch before the next lap starts it again.
@main
final class LineTextures: Sketch {
    enum Texture: String, CaseIterable, ParamOption { case woodGrain, frost, crackle, ikat }

    @Param(style: .segmented, icon: "scribble") var texture = Texture.woodGrain
    @Param("Seed", 1 ... 99, icon: "dice") var seed = 7
    @Param("Detail", 0.5 ... 2, icon: "slider.horizontal.3") var detail = 1.0
    @Param("Pen weight", 0.6 ... 3, icon: "pencil.tip") var penWeight = 1.2
    @Param("Pen draws it", icon: "pencil.and.outline") var penDraws = true

    override var loopDuration: Double? { 12 }

    /// One stroke the pen lays: its points, whether it closes, and a tone the
    /// wood grain sets by its ring (1 everywhere else).
    private struct Line {
        var points: [Vector2]
        var isClosed = false
        var tone = 1.0
    }

    private var lines: [Line] = []
    private var fills: [(Shape, Color)] = []
    private var paper = Color.white
    private var ink = Color.black
    private var builtFor: (Texture, Int, Double)?

    private func rebuildIfNeeded() {
        if let builtFor, builtFor == (texture, seed, detail) { return }
        lines = []
        fills = []
        let canvas = canvasRectangle
        switch texture {
        case .woodGrain:
            paper = Color(hex: 0xEADFC8)
            ink = Color(hex: 0x4A2A14)
            let plank = WoodGrain.trace(in: canvas, direction: 0.12, spacing: 5.5 * scale / detail, knots: 2,
                                        ringSpacing: 44 * scale, ringContrast: 0.65, wobble: 0.4, seed: seed)
            lines = plank.strokes.map { Line(points: $0.points, isClosed: $0.isClosed, tone: $0.tone) }
        case .frost:
            paper = Color(hex: 0x0B1B33)
            ink = Color(hex: 0xEAF4FF)
            // The pane's frame, frosting inward, and a round pane frosting out.
            let frame = Rectangle(x: 26 * scale, y: 26 * scale, width: width - 52 * scale, height: height - 52 * scale)
            let pane = Frost.grow(along: frame.contour, spacing: 8 * scale / detail, length: 110 * scale,
                                  clump: 0.6, barbSpacing: 7 * scale / detail, side: .inside, seed: seed)
            let disc = Circle(center: Vector2(width / 2, height / 2), radius: width * 0.17).contour
            let rim = Frost.grow(along: disc, spacing: 7 * scale / detail, length: 80 * scale,
                                 clump: 0.5, barbSpacing: 6 * scale / detail, side: .outside, seed: seed + 1)
            lines = (pane.strokes + rim.strokes).map { Line(points: $0) }
        case .crackle:
            // Batik: a waxed panel over indigo; the dye got in where the wax
            // cracked, most along the two folds.
            paper = Color(hex: 0x1F2B5B)
            ink = Color(hex: 0x1F2B5B)
            let panel = Rectangle(x: 70 * scale, y: 70 * scale, width: width - 140 * scale, height: height - 140 * scale)
            let folds: [[Vector2]] = [
                [Vector2(panel.x + panel.width * 0.42, panel.y), Vector2(panel.x + panel.width * 0.46, panel.y + panel.height)],
                [Vector2(panel.x, panel.y + panel.height * 0.58), Vector2(panel.x + panel.width, panel.y + panel.height * 0.52)],
            ]
            let wax = Crackle.grow(in: panel, spacing: 34 * scale / detail, creases: folds, forkChance: 0.55,
                                   wobble: 0.3, seed: seed)
            fills = [(Shape(contours: [panel.contour]), Color(hex: 0xF1E6C8))]
            lines = wax.lines.map { Line(points: $0) }
        case .ikat:
            // Five stripes across a vertical warp, two dyes by turns.
            paper = Color(hex: 0xF1E6C8)
            ink = Color(hex: 0x15203F)
            let cloth = Rectangle(x: 40 * scale, y: 40 * scale, width: width - 80 * scale, height: height - 80 * scale)
            let stripes = Ikat.stripes(in: cloth, count: 5, bundle: 13 * scale / detail, bleed: 24 * scale,
                                       spikes: 0.14, intrusions: 0.14, skew: 1.2, seed: seed)
            let dyes = [Color(hex: 0x1F2B5B), Color(hex: 0x9E3A2F)]
            for (i, stripe) in stripes.stripes.enumerated() {
                fills.append((stripe.shape, dyes[i % dyes.count]))
                lines.append(contentsOf: stripe.edges.map { Line(points: $0) })
            }
        }
        builtFor = (texture, seed, detail)
    }

    override func draw() {
        rebuildIfNeeded()
        background(paper)

        noStroke()
        for (shape, color) in fills {
            fill(color)
            drawShape(shape)
        }

        // The pen's progress: every stroke by four fifths of the loop, the
        // one it is on drawn point by point.
        let progress = penDraws ? smoothstep(0, 0.8, loopProgress(over: 12)) : 1
        let reach = progress * Double(lines.count)
        let whole = Int(reach)

        noFill()
        strokeCap(.round)
        strokeJoin(.round)
        for (i, line) in lines.enumerated() where i <= whole {
            let alpha = texture == .woodGrain ? 0.3 + 0.7 * line.tone : 1
            stroke(ink.withAlpha(alpha))
            strokeWeight(penWeight * scale * (texture == .woodGrain ? 0.55 + 0.65 * line.tone : 1))
            if i < whole {
                if line.isClosed { drawPolygon(line.points) } else { drawPolyline(line.points) }
            } else {
                let part = reach - Double(whole)
                let count = max(2, Int(part * Double(line.points.count)))
                if count < line.points.count { drawPolyline(Array(line.points.prefix(count))) }
                else if line.isClosed { drawPolygon(line.points) } else { drawPolyline(line.points) }
            }
        }
    }
}
