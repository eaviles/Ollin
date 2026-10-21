import Ollin

/// Marks built from one gesture: a path, a width at every point of it, and a
/// seed turned into geometry a plotter can draw. One picker across the
/// families of `GestureMark`: a cloud of discs, a chain of rounded squares,
/// a band with spikes; dashes, dots, and strips in rows across the width; a
/// feather, leaves, and a fringe sprouting off both sides; the ribbon as
/// pixels, facets, and lanes; a spiral, strands, fragments, and a wiggle
/// around the path; and the regions a gesture encloses, plain, spiked, and
/// wobbling.
///
/// A hand that is not there draws one long stroke across the sheet, heavy
/// where it starts and lifting toward the end, and the marks follow its
/// taper. The marks are rebuilt from the pen every frame, and nothing behind
/// the pen moves: each piece is placed by its distance from the start.
///
/// Drag to draw your own gesture in the chosen family; `c` clears what you
/// drew. Every piece is a filled outline or a line, so the sheet plots
/// straight to SVG with `--export-svg`.
@main
final class GestureMarks: Sketch {
    enum Family: String, CaseIterable, ParamOption {
        case cloud, chain, spikes, dashes, dots, strips, feather, leaves, fringe
        case pixels, facets, lanes, spiral, strands, fragments, wiggle
        case blob, spikedBlob, wobblyBlob
    }

    @Param(icon: "scribble.variable") var family = Family.cloud
    @Param("Width", 30 ... 180, icon: "lineweight") var weight = 110.0
    @Param("Seed", 1 ... 99, icon: "dice") var seed = 7
    @Param("Pen draws it", icon: "pencil.and.outline") var penDraws = true

    override var loopDuration: Double? { 10 }

    let paper = Color(hex: 0xF3EEE3)
    let ink = Color(hex: 0x1F2B5B)
    let palette = [Color(hex: 0x1F2B5B), Color(hex: 0xC4473A), Color(hex: 0xE0A43A),
                   Color(hex: 0x2F7A78), Color(hex: 0xE07A8F)]

    /// The pointer's gesture in progress, and the ones already drawn.
    var mark = StrokeMark()
    var drawn: [StrokeMark] = []

    override func draw() {
        background(paper)

        // The hand's stroke grows over three quarters of the loop and holds.
        let progress = penDraws ? smoothstep(0, 0.75, loopProgress(over: 10)) : 1
        let (points, widths) = handStroke(seed: seed)
        let count = max(2, Int(progress * Double(points.count)))
        draw(GestureMark(points: Array(points.prefix(count)), widths: Array(widths.prefix(count))))

        for gesture in drawn { draw(GestureMark(gesture, width: weight * 0.6)) }
        if mouseIsPressed { record(into: &mark) }
        if mark.count > 1 { draw(GestureMark(mark, width: weight * 0.6)) }

        // The caption in ink, since the sheet is light.
        noStroke()
        fill(Color(white: 0.4))
        textSize(20)
        textAlign(.center, .bottom)
        drawText("\(family.rawValue)  ·  drag to draw  ·  c clears", width / 2, height - 28)
    }

    override func mouseReleased() {
        if mark.count > 1 { drawn.append(mark) }
        mark = StrokeMark()
    }

    override func keyPressed() {
        if key == "c" { drawn = []; mark = StrokeMark() }
    }

    /// One gesture drawn in the chosen family.
    func draw(_ gesture: GestureMark) {
        withState {
            strokeCap(.round)
            strokeJoin(.round)
            switch family {
            case .cloud: fillOne(gesture.cloud(variation: 0.7, seed: seed).shape, ink)
            case .chain: fill(gesture.chain(seed: seed)) { 3 * ($0.index % 2) }
            case .spikes: fillOne(gesture.spikes(seed: seed).shape, palette[1])
            case .dashes: fill(gesture.dashes(rows: 4, seed: seed)) { $0.row }
            case .dots: fill(gesture.dots(rows: 3, seed: seed)) { $0.row + $0.index }
            case .strips: fill(gesture.strips(rows: 3, seed: seed)) { $0.row + 2 * $0.index }
            case .feather: stroke(gesture.feather(seed: seed), weight: 1.6) { $0.index / 6 }
            case .leaves: fill(gesture.leaves(seed: seed)) { 3 - 2 * $0.row }
            case .fringe: stroke(gesture.fringe(seed: seed), weight: 1.2) { 1 + $0.row }
            case .pixels: fill(gesture.pixels(cell: 12, seed: seed)) { 2 * $0.row }
            case .facets:
                noStroke()
                for piece in gesture.facets(seed: seed) {
                    fill(ink.mixed(with: paper, 0.12 * Double(piece.row) + 0.05 * Double(piece.index % 3)))
                    drawShape(piece.shape)
                }
            case .lanes: fill(gesture.lanes(count: 4, seed: seed)) { $0.row }
            case .spiral: stroke(gesture.spiral(cycle: 0.35), weight: 2.4) { _ in 0 }
            case .strands: stroke(gesture.strands(count: 6, seed: seed), weight: 2) { $0.row }
            case .fragments: stroke(gesture.fragments(density: 1.4, seed: seed), weight: 2.2) { $0.index }
            case .wiggle: stroke(gesture.wiggle(wavelength: 0.7, amplitude: 0.8), weight: 4) { _ in 1 }
            case .blob, .spikedBlob, .wobblyBlob:
                var region = gesture.blob()
                if family == .spikedBlob { region = region.spiked(48, height: 26, seed: seed) }
                if family == .wobblyBlob { region = region.wobbled(by: 18, scale: 90, seed: seed) }
                fillOne(gesture.hull(), palette[2].withAlpha(0.35))
                fillOne(region, palette[4])
                noFill()
                stroke(ink)
                strokeWeight(3)
                drawPolyline(gesture.points)
            }
        }
    }

    /// A whole region in one color.
    func fillOne(_ shape: Shape, _ color: Color) {
        noStroke()
        fill(color)
        drawShape(shape)
    }

    /// Closed pieces filled from the palette by `pick`.
    func fill(_ pieces: [GestureMark.Piece], _ pick: (GestureMark.Piece) -> Int) {
        noStroke()
        for piece in pieces {
            fill(palette[pick(piece) % palette.count])
            drawShape(piece.shape)
        }
    }

    /// Open pieces stroked from the palette by `pick`.
    func stroke(_ pieces: [GestureMark.Piece], weight: Double, _ pick: (GestureMark.Piece) -> Int) {
        noFill()
        strokeWeight(weight)
        for piece in pieces {
            stroke(palette[pick(piece) % palette.count])
            drawPolyline(piece.contour.points)
        }
    }

    /// The hand's stroke: a sweep across the sheet through five points that
    /// the seed nudges, sampled every few units, heavy at the start and
    /// lifting toward the end.
    func handStroke(seed: Int) -> (points: [Vector2], widths: [Double]) {
        randomSeed(seed)
        let route = [Vector2(150, 600), Vector2(350, 330), Vector2(580, 520), Vector2(760, 790), Vector2(930, 470)]
        let knots = route.map { $0 + Vector2(random(-50, 50), random(-70, 70)) }
        let points = Contour(curveThrough: knots, closed: false).resampled(spacing: 4).points
        let widths = points.indices.map { i -> Double in
            let u = Double(i) / Double(max(points.count - 1, 1))
            return weight * (1 - 0.7 * u) * (0.35 + 0.65 * smoothstep(0, 0.05, u))
        }
        return (points, widths)
    }
}
