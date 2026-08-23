import Ollin

/// **Crease patterns**: the flat sheet that folds into a shape, and the folding
/// itself, side by side.
///
/// The lower half is the pattern: every line the paper is folded along, in two
/// colors for the two directions a fold can go. The upper half is the same
/// sheet folded, worked out from those lines and nothing else.
///
/// This is the Miura fold, and it is worth knowing because of what it does
/// rather than how it looks. Pull two opposite corners and the whole sheet
/// opens at once, in both directions together. There is no order of operations,
/// which is why it goes into maps, into stents, and into solar arrays that
/// travel folded and open in orbit. Watch the caption: the sheet gets narrower
/// as it gets shorter, which is the opposite of what a squeezed rubber band
/// does.
///
/// Turn on `cutInstead` for the kirigami half: a sheet cut into squares joined
/// at their corners, which grows the same amount in both directions when it is
/// pulled. Nothing there stretches either. The squares only turn.
///
/// Try it: `corner` is the sharp corner of each parallelogram. Take it toward a
/// right angle and the zigzag straightens into plain pleats, and the sheet
/// stops opening sideways at all.
@main
final class CreasePatternSketch: Sketch {
    @Param(3 ... 12, icon: "square.grid.3x3") var across = 8.0
    @Param(2 ... 8, icon: "rectangle.split.1x2") var down = 5.0
    @Param(25 ... 88, icon: "angle") var corner = 60.0
    @Param(icon: "scissors") var cutInstead = false

    private let paper = Color(hex: 0x11131A)
    private let chalk = Color(hex: 0xF2ECDD)
    private let ridge = Color(hex: 0xE0724A)
    private let groove = Color(hex: 0x5A8FC7)

    override func draw() {
        background(paper)
        let drive = 0.5 * (1 - cos(time * 0.7))
        if cutInstead { drawCutSheet(opened: drive) } else { drawFoldedSheet(at: drive) }
    }

    // MARK: - The Miura fold

    private func drawFoldedSheet(at amount: Double) {
        var sheet = MiuraFold(columns: Int(across), rows: Int(down),
                              major: 1.0, minor: 0.78, angle: corner * .pi / 180,
                              fold: amount)

        let stage = Rectangle(x: width * 0.06, y: height * 0.08,
                              width: width * 0.88, height: height * 0.42)
        drawPanels(sheet, in: stage)

        let sheetBelow = Rectangle(x: width * 0.06, y: height * 0.56,
                                   width: width * 0.88, height: height * 0.30)
        let pattern = sheet.pattern.fitted(in: sheetBelow)
        strokeWeight(width * 0.0022)
        strokeCap(.round)
        stroke(chalk.withAlpha(0.18))
        drawCreases(pattern, .boundary)
        stroke(ridge)
        drawCreases(pattern, .mountain)
        stroke(groove)
        drawCreases(pattern, .valley)

        sheet.fold = amount
        let size = sheet.size
        let flat = MiuraFold(columns: sheet.columns, rows: sheet.rows,
                             major: sheet.major, minor: sheet.minor, angle: sheet.angle).size
        caption("\(sheet.columns) by \(sheet.rows) panels, \(percent(amount)) folded: "
                + "\(percent(size.x / flat.x)) as wide and \(percent(size.y / flat.y)) as long")
    }

    /// The folded sheet seen from a corner, far panels first so near ones cover
    /// them, each shaded by the way it happens to be facing.
    private func drawPanels(_ sheet: MiuraFold, in frame: Rectangle) {
        let panels = sheet.facets
        let flattened = panels.map { $0.map(isometric) }
        let placed = place(flattened.flatMap { $0 }, in: frame)
        let light = Vector3(-0.35, -0.55, 0.76).normalized

        let order = panels.indices.sorted {
            depth(of: panels[$0]) < depth(of: panels[$1])
        }
        strokeWeight(width * 0.0016)
        for index in order {
            let corners = Array(placed[(index * 4) ..< (index * 4 + 4)])
            let edge1 = panels[index][1] - panels[index][0]
            let edge2 = panels[index][3] - panels[index][0]
            var normal = edge1.cross(edge2)
            if normal.length > 0 { normal = normal.normalized } else { normal = Vector3.unitZ }
            let lit = max(0, abs(normal.dot(light)))
            fill(Color.mix(Color(hex: 0x2B3550), chalk, t: 0.18 + lit * 0.72))
            stroke(paper.withAlpha(0.55))
            drawPolygon(corners)
        }
    }

    private func isometric(_ point: Vector3) -> Vector2 {
        let lean = cos(Double.pi / 6), rise = sin(Double.pi / 6)
        return Vector2((point.x - point.y) * lean, (point.x + point.y) * rise - point.z)
    }

    private func depth(of panel: [Vector3]) -> Double {
        panel.reduce(0) { $0 + $1.x + $1.y } / Double(panel.count)
    }

    // MARK: - The kirigami sheet

    private func drawCutSheet(opened amount: Double) {
        var lattice = RotatingSquares(columns: Int(across), rows: Int(across),
                                      side: 1, ligament: 0.08, opening: amount)

        // The sheet as the cutting machine gets it: flat, closed, with a thread
        // of material left at every corner so it stays in one piece.
        let left = Rectangle(x: width * 0.06, y: height * 0.20,
                             width: width * 0.40, height: height * 0.52)
        let cuts = lattice.pattern.fitted(in: left)
        strokeWeight(width * 0.0026)
        strokeCap(.butt)
        stroke(chalk.withAlpha(0.20))
        drawCreases(cuts, .boundary)
        stroke(ridge)
        drawCreases(cuts, .cut)

        // The same sheet pulled open. Nothing stretches: the squares only turn.
        let right = Rectangle(x: width * 0.54, y: height * 0.20,
                              width: width * 0.40, height: height * 0.52)
        var widest = lattice
        widest.opening = 1
        let frame = widest.bounds
        let squares = lattice.squares
        noStroke()
        for (index, square) in squares.enumerated() {
            let along = Double(index) / Double(max(squares.count - 1, 1))
            fill(Color.mix(chalk, ridge, t: along * 0.8))
            drawPolygon(place(square.points, from: frame, in: right))
        }

        let turned = Int((lattice.angle * 180 / Double.pi).rounded())
        caption("\(squares.count) squares, turned \(turned) degrees: "
                + "\(percent(lattice.spacing / lattice.side)) as wide and as long, both at once")
    }

    // MARK: - Shared

    /// Points scaled by the same amount in both directions and centered in
    /// `frame`. The points move, so the strokes on them do not get fatter.
    private func place(_ points: [Vector2], in frame: Rectangle) -> [Vector2] {
        fitted(points, in: frame)
    }

    private func place(_ points: [Vector2], from box: Rectangle, in frame: Rectangle) -> [Vector2] {
        let scale = min(box.width > 0 ? frame.width / box.width : 1,
                        box.height > 0 ? frame.height / box.height : 1)
        let from = box.center, to = frame.center
        return points.map { Vector2(to.x + ($0.x - from.x) * scale, to.y + ($0.y - from.y) * scale) }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func caption(_ line: String) {
        noStroke()
        fill(chalk.withAlpha(0.75))
        textFont(.system); textSize(width * 0.021); textAlign(.center, .bottom)
        drawText(line, width / 2, height - width * 0.045)
    }
}
