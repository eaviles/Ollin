//  Recreation after Roman Verostko - the pen-and-brush plotted paintings of
//  the Pathway series (from 1987), read from Pathway Series, Bird 2 (1990;
//  multi-pen plotter drawing with brush on paper, Victoria and Albert
//  Museum, London) and Lung Shan I (1989; algorithmic pen and brush drawing
//  on rag paper, 61 x 183 cm, Victoria and Albert Museum), with the
//  procedure taken from his own account in "Epigenetic Painting: Software as
//  Genotype" (Leonardo 23:1, 1990, first read at FISEA in Utrecht, 1988).
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or his estate.
//  https://collections.vam.ac.uk/item/O499689/
//  https://collections.vam.ac.uk/item/O1243131/
//  https://www.isea-archives.org/symposia/fisea-1988/presenter/fisea-1988_paper_verostko/
//  https://verostko.com/archive/writings/epigen-art-revisited.html
//
//  An original Ollin interpretation, written from his published description
//  of the procedure and from the drawings. His software, Hodos, was never
//  published, so nothing was ported.

import Foundation
import Ollin

/// The Pathway paintings (Roman Verostko, Minneapolis). From 1987 his own
/// software, Hodos, drove a pen plotter that held technical pens and, in its
/// drawing arm, a Chinese brush. Each painting grows from one gesture: a
/// curve through a handful of control points cast at random, each point
/// chained from the one before by a random step and turn. The plotter lays
/// that gesture down once as a single brush stroke, and the same gesture,
/// remembered and redrawn smaller and turned, makes the cloud of fine pen
/// strokes behind it, a pen at a time from the warm inks to the cool ones.
/// A few rectangles, planes of flat color the plotter fills with close
/// lines, stand apart from it. He called the code the genotype and the
/// painting its phenotype, and the process epigenesis: every work from the
/// same code is one of a family.
///
/// This sketch follows the rules he wrote down. The sheet is his 36 by 24
/// inches with the 32 by 21.5 inch frame he plotted in. The gesture is a
/// curve through `controlPoints` points, each a step from the last (unequal
/// by up to `stepJitter`), turned by up to `turn`. The brush stroke is that
/// gesture about `brushSize` of the region's shorter side across and
/// `brushWeight` wide, its middle placed by dice weighted so it starts within
/// a quarter of the region from the region's middle (and nudged inside if it
/// overhangs), laid in one ink twice: a solid body, and over it a dry brush
/// that drags off on the paper's grain at its end. The `strokes` pen strokes
/// are the same gesture between `minScale` and `maxScale` of the brush's
/// size, each turned by up to `rotation` from it, and each placed around a
/// point of the brush stroke by the same weighted dice, up to `spread` of the
/// region's shorter side away, since he keyed his distributions to the same
/// control points; a stroke that would leave the frame is thrown again. The
/// `planes` rectangles never overlap each other or the brush, keep their
/// distance from it, and take opposing hues kept near enough to gray.
/// `mirror` repeats the whole drawing across one axis of the sheet, or both,
/// or neither, as his routines could. `pens` picks the inks.
///
/// Each cycle of `seconds` plots one painting the way the machine did, pen
/// by pen, then the planes line by line, then the brush, holds it, and
/// plots the next painting of the family: the same code and settings, the
/// next seed.
///
/// `--export-svg` gives the plot back as the plotter's lines: every pen
/// stroke the gesture under its own scale, turn, and place, every plane its
/// fill lines, and the brush stroke as the flat ribbons of its two coats
/// (the dry brush is raster only).
@main
final class Pathway: Sketch {
    enum Pens: String, CaseIterable, ParamOption { case classical, earth, sepia }
    enum Mirror: String, CaseIterable, ParamOption { case none, sides, topBottom, both }

    @Param(icon: "paintpalette") var pens = Pens.classical
    @Param(icon: "arrow.left.and.right.righttriangle.left.righttriangle.right") var mirror = Mirror.none
    @Param(8 ... 16, icon: "point.topleft.down.to.point.bottomright.curvepath") var controlPoints = 12
    @Param(0.3 ... 2.8, icon: "arrow.turn.up.right") var turn = 1.4
    @Param(0 ... 0.9, icon: "dice") var stepJitter = 0.5
    @Param(0.3 ... 1.3, icon: "paintbrush.pointed") var brushSize = 1.0
    @Param(8 ... 48, icon: "lineweight") var brushWeight = 30.0
    @Param(200 ... 4000, icon: "scribble") var strokes = 2400
    @Param(0.02 ... 0.3, icon: "minus.magnifyingglass") var minScale = 0.08
    @Param(0.05 ... 0.5, icon: "plus.magnifyingglass") var maxScale = 0.26
    @Param(0 ... 3.15, icon: "rotate.right") var rotation = 0.8
    @Param(0.05 ... 0.6, icon: "circle.dotted") var spread = 0.3
    @Param(0 ... 6, icon: "rectangle.split.3x1") var planes = 3
    @Param(10 ... 90, icon: "clock") var seconds = 30.0

    override var canvasSize: CanvasSize { .size(1620, 1080) }
    override var loopDuration: Double? { seconds }

    /// How many points every copy of the gesture is drawn through. Every pen
    /// stroke and the brush share them, so each stroke's points are the
    /// gesture's points under one scale, turn, and move.
    static let samples = 96

    /// The gesture, its points about its own middle, its farthest point at 1.
    private var gesture: [Vector2] = []
    /// One painting, dealt from its seed.
    private var brush = Placement(center: .zero, scale: 1, angle: 0)
    /// The pen strokes in the order the plotter draws them, pen by pen.
    private var penStrokes: [PenStroke] = []
    private var planeLines: [[Line]] = []
    private var planeColors: [Color] = []
    private var palette: [Color] = []

    private struct Placement {
        var center: Vector2
        var scale: Double
        var angle: Double

        func apply(_ p: Vector2) -> Vector2 {
            let c = cos(angle), s = sin(angle)
            return center + Vector2(c * p.x - s * p.y, s * p.x + c * p.y) * scale
        }
    }

    private struct PenStroke {
        var pen: Int
        var points: [Vector2]
    }

    private struct Line {
        var a: Vector2
        var b: Vector2
    }

    /// Which painting is dealt, and with which settings, so a change rebuilds it.
    private var built: [Double] = []
    /// One retained recording per finished run of `chunk` pen strokes, made
    /// the first frame it is done, so a frame draws at most one run afresh.
    private var penBatches: [Int: Batch] = [:]
    static let chunk = 100

    private static let paper = Color(hex: 0xF7F4EC)
    private static let ink = Color(hex: 0x17140F)

    override func draw() {
        let work = Int((time / seconds).rounded(.down))
        let signature: [Double] = [Double(variation), Double(work), Double(Pens.allCases.firstIndex(of: pens) ?? 0),
                                   Double(Mirror.allCases.firstIndex(of: mirror) ?? 0), Double(controlPoints),
                                   turn, stepJitter, brushSize, Double(strokes), minScale, maxScale, rotation,
                                   spread, Double(planes)]
        if signature != built {
            deal(work: work)
            built = signature
            penBatches = [:]
        }

        background(Pathway.paper)
        let phase = (time / seconds).truncatingRemainder(dividingBy: 1)
        // The plot: the pens over the first part of the cycle, the planes, then
        // the brush, then the finished painting holds.
        let pensEnd = 0.52, planesEnd = 0.62, brushEnd = 0.74

        noFill()
        let drawn = Int((Double(penStrokes.count) * min(phase / pensEnd, 1)).rounded(.down))
        strokeWeight(1.1)
        for start in stride(from: 0, to: drawn, by: Pathway.chunk) {
            let end = min(start + Pathway.chunk, penStrokes.count)
            if end <= drawn {
                if penBatches[start] == nil {
                    let run = penStrokes[start ..< end]
                    penBatches[start] = makeBatch { mirrored { plot(run) } }
                }
                if let batch = penBatches[start] { drawBatch(batch) }
            } else {
                mirrored { plot(penStrokes[start ..< drawn]) }
            }
        }

        if phase >= pensEnd {
            let lines = planeLines.reduce(0) { $0 + $1.count }
            var left = Int((Double(lines) * min((phase - pensEnd) / (planesEnd - pensEnd), 1)).rounded(.down))
            strokeWeight(1.5)
            for (i, plane) in planeLines.enumerated() where left > 0 {
                stroke(planeColors[i])
                let shown = plane.prefix(left)
                mirrored { for line in shown { drawLine(line.a, line.b) } }
                left -= shown.count
            }
        }

        if phase >= planesEnd {
            let share = min((phase - planesEnd) / (brushEnd - planesEnd), 1)
            drawBrush(upTo: share)
        }
    }

    /// Draws a run of pen strokes, each in its own pen's ink.
    private func plot(_ run: ArraySlice<PenStroke>) {
        var pen = -1
        for s in run {
            if s.pen != pen {
                pen = s.pen
                stroke(palette[pen].withAlpha(0.82))
            }
            drawPolyline(s.points)
        }
    }

    // MARK: - The brush

    /// The brush stroke, laid along the gesture up to `share` of its length.
    /// A loaded brush leaves solid ink, so the stroke is two marks in one
    /// ink: a plain body that thins out before the end, and over it the dry
    /// brush, whose load runs short toward the tail so the paper's grain
    /// breaks it up there. Both marks fix their width and load per point
    /// along the stroke, so the part drawn so far is exactly the finished
    /// stroke's beginning.
    private func drawBrush(upTo share: Double) {
        guard share > 0 else { return }
        let points = gesture.map(brush.apply)
        var lengths = [0.0]
        for i in 1 ..< points.count { lengths.append(lengths[i - 1] + (points[i] - points[i - 1]).length) }
        let total = lengths.last ?? 1
        let reach = total * share

        // The stations drawn so far, the last one partway along the segment
        // that crosses the reach.
        var stations: [(point: Vector2, t: Double)] = []
        for (i, p) in points.enumerated() {
            if lengths[i] <= reach {
                stations.append((p, lengths[i] / total))
            } else {
                let a = lengths[i - 1], f = (reach - a) / max(lengths[i] - a, 1e-9)
                if f > 1e-6 { stations.append((points[i - 1] + (p - points[i - 1]) * f, reach / total)) }
                break
            }
        }
        guard stations.count > 1 else { return }

        var body = StrokeMark(), dry = StrokeMark()
        for s in stations {
            let w = Pathway.brushWidth(s.t)
            if s.t <= Pathway.bodyEnd {
                body.append(StrokeMark.Sample(position: s.point, width: w, opacity: Pathway.bodyLoad(s.t)))
            }
            dry.append(StrokeMark.Sample(position: s.point, width: w, opacity: Pathway.dryLoad(s.t)))
        }
        stroke(Pathway.ink)
        strokeWeight(brushWeight)
        if body.count > 1 { mirrored { drawMark(body) } }
        strokeMedium(.dryBrush(grain: 1.4, amount: 0, streaks: 22, seed: 7))
        mirrored { drawMark(dry) }
        noStrokeMedium()
    }

    /// The brush's width along its length: set down a little narrow, pressed
    /// to full, a slow swell, and lifted toward the end.
    static func brushWidth(_ t: Double) -> Double {
        let press = 0.6 + 0.4 * smoothstep(0, 0.08, t)
        let lift = 1 - 0.6 * smoothstep(0.72, 1, t)
        return press * lift * (0.9 + 0.1 * sin(.tau * 2.2 * t))
    }

    /// Where the solid body under the dry brush ends.
    static let bodyEnd = 0.74

    /// The solid body's ink: full, then thinning out before the tail.
    static func bodyLoad(_ t: Double) -> Double {
        1 - smoothstep(0.5, bodyEnd, t)
    }

    /// How much ink the dry brush still carries: full, then running short
    /// over the last part, where the paper's grain shows through.
    static func dryLoad(_ t: Double) -> Double {
        1 - 0.42 * pow(smoothstep(0.55, 1, t), 1.3)
    }

    // MARK: - Mirroring

    /// Runs `body` once for every image the mirror asks for, reflected across
    /// the middle of the sheet.
    private func mirrored(_ body: () -> Void) {
        let flips: [(Double, Double)]
        switch mirror {
        case .none: flips = [(1, 1)]
        case .sides: flips = [(1, 1), (-1, 1)]
        case .topBottom: flips = [(1, 1), (1, -1)]
        case .both: flips = [(1, 1), (-1, 1), (1, -1), (-1, -1)]
        }
        for (sx, sy) in flips {
            withState {
                translate(width / 2, height / 2)
                scale(sx, sy)
                translate(-width / 2, -height / 2)
                body()
            }
        }
    }

    // MARK: - Dealing one painting

    /// The frame on the sheet: 32 by 21.5 inches on a 36 by 24 inch sheet.
    private var frame: Rectangle {
        Rectangle(x: width * 2 / 36, y: height * 1.25 / 24, width: width * 32 / 36, height: height * 21.5 / 24)
    }

    /// The region the painting is dealt in: the frame on the sheet, or the
    /// part of it the mirror repeats.
    private var region: Rectangle {
        switch mirror {
        case .none: return frame
        case .sides: return Rectangle(x: frame.x, y: frame.y, width: frame.width / 2, height: frame.height)
        case .topBottom: return Rectangle(x: frame.x, y: frame.y, width: frame.width, height: frame.height / 2)
        case .both: return Rectangle(x: frame.x, y: frame.y, width: frame.width / 2, height: frame.height / 2)
        }
    }

    private func deal(work: Int) {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation &* 1_000_003 &+ work &* 7919 &+ 17)))
        func roll(_ a: Double, _ b: Double) -> Double { Double.random(in: a ... b, using: &rng) }
        // Dice weighted toward the middle: the mean of three throws, never past one.
        func dice() -> Double { (roll(-1, 1) + roll(-1, 1) + roll(-1, 1)) / 3 }

        gesture = Pathway.gesture(controlPoints: controlPoints, turn: turn, stepJitter: stepJitter, using: &rng)
        let box = region
        let side = min(box.width, box.height)

        // The brush: across `brushSize` of the region's shorter side, leaning
        // along the region's longer one, its middle within a quarter of the
        // region from the region's middle.
        let lean = Pathway.principalAngle(of: gesture)
        let along = box.width >= box.height ? 0.0 : Double.pi / 2
        var placement = Placement(center: box.center + Vector2(dice() * 0.25 * box.width, dice() * 0.25 * box.height),
                                  scale: brushSize * side / 2, angle: along - lean + dice() * 0.45)
        // Kept inside the region, shrinking if it has to.
        let margin = brushWeight
        for _ in 0 ..< 8 {
            let pts = gesture.map(placement.apply)
            let lo = Vector2(pts.map(\.x).min() ?? 0, pts.map(\.y).min() ?? 0)
            let hi = Vector2(pts.map(\.x).max() ?? 0, pts.map(\.y).max() ?? 0)
            if hi.x - lo.x > box.width - 2 * margin || hi.y - lo.y > box.height - 2 * margin {
                placement.scale *= 0.9
                continue
            }
            var dx = 0.0, dy = 0.0
            if lo.x < box.x + margin { dx = box.x + margin - lo.x }
            if hi.x > box.x + box.width - margin { dx = box.x + box.width - margin - hi.x }
            if lo.y < box.y + margin { dy = box.y + margin - lo.y }
            if hi.y > box.y + box.height - margin { dy = box.y + box.height - margin - hi.y }
            placement.center = placement.center + Vector2(dx, dy)
            break
        }
        brush = placement

        // The pen strokes, dealt a pen each, plotted pen by pen.
        palette = Pathway.palette(pens)
        var byPen = Array(repeating: [PenStroke](), count: palette.count)
        let lo = min(minScale, maxScale), hi = max(minScale, maxScale)
        for _ in 0 ..< strokes {
            let u = roll(0, 1)
            let scale = brush.scale * (lo + (hi - lo) * u * u)
            let angle = brush.angle + roll(-rotation, rotation)
            // Keyed to the gesture: around a point of the brush stroke itself,
            // thrown again until the whole stroke lands on the frame (every
            // point of the gesture is within its scale of its middle).
            var center = brush.center
            for _ in 0 ..< 24 {
                let key = brush.apply(gesture[Int(roll(0, 1) * Double(gesture.count - 1))])
                let c = key + Vector2(dice() * spread * side, dice() * spread * side)
                if c.x - scale >= frame.x, c.x + scale <= frame.x + frame.width,
                   c.y - scale >= frame.y, c.y + scale <= frame.y + frame.height {
                    center = c
                    break
                }
            }
            let place = Placement(center: center, scale: scale, angle: angle)
            let pen = Pathway.pen(for: roll(0, 1), count: palette.count)
            byPen[pen].append(PenStroke(pen: pen, points: gesture.map(place.apply)))
        }
        penStrokes = byPen.flatMap { $0 }

        // The planes: thin rectangles of opposing hues near gray, apart from
        // one another and from the brush.
        let brushPoints = gesture.map(brush.apply)
        var bars: [(center: Vector2, length: Double, breadth: Double, angle: Double)] = []
        var tries = 0
        while bars.count < planes, tries < 4000 {
            tries += 1
            let relax = Double(tries / 1000)
            let length = roll(0.17, 0.27) * box.height * (mirror == .none || mirror == .sides ? 1 : 1.6)
            let breadth = length / roll(5.5, 8)
            let angle = roll(-Double.pi / 2, Double.pi / 2)
            let c = Vector2(roll(box.x + length / 2, box.x + box.width - length / 2),
                            roll(box.y + length / 2, box.y + box.height - length / 2))
            let fromBrush = (c - brush.center).length
            if fromBrush < (0.3 - 0.05 * relax) * side || fromBrush > (0.75 + 0.1 * relax) * max(box.width, box.height) { continue }
            if bars.contains(where: { ($0.center - c).length < ($0.length + length) / 2 + 0.06 * side }) { continue }
            let axis = Vector2(cos(angle), sin(angle))
            let clear = brushPoints.allSatisfy {
                Pathway.distance(from: $0, toSegment: c - axis * (length / 2), c + axis * (length / 2))
                    > breadth / 2 + brushWeight
            }
            if !clear { continue }
            bars.append((c, length, breadth, angle))
        }
        let hue = roll(0, 1)
        planeColors = bars.indices.map { i in
            let h = hue + Double(i) / 3 + roll(-0.04, 0.04)
            let chroma = i == 2 ? roll(0.02, 0.05) : roll(0.07, 0.11)
            let tone = roll(0.74, 0.86)
            // With one pen on the plotter the planes are that ink, thinned.
            if palette.count == 1 { return palette[0].mixed(with: Pathway.paper, tone - 0.25) }
            return Color(OKLCH(l: tone, c: chroma, h: h), alpha: 0.9)
        }
        // Each plane filled with lines along its length, one plotter line a step.
        let pitch = 1.8
        planeLines = bars.map { bar in
            let axis = Vector2(cos(bar.angle), sin(bar.angle))
            let across = Vector2(-axis.y, axis.x)
            let count = max(2, Int((bar.breadth / pitch).rounded()) + 1)
            return (0 ..< count).map { k in
                let offset = -bar.breadth / 2 + bar.breadth * Double(k) / Double(count - 1)
                let mid = bar.center + across * offset
                return Line(a: mid - axis * (bar.length / 2), b: mid + axis * (bar.length / 2))
            }
        }
    }

    /// The gesture: a curve through `controlPoints` points, each chained from
    /// the one before by a step (unequal by up to `stepJitter`) and a turn of
    /// up to `turn`, drawn through `samples` points evenly spaced along it,
    /// moved so their middle is the origin and scaled so the farthest is 1.
    static func gesture(controlPoints: Int, turn: Double, stepJitter: Double,
                        using rng: inout SplitMix64) -> [Vector2] {
        var heading = Double.random(in: 0 ..< .tau, using: &rng)
        var controls = [Vector2.zero]
        for _ in 1 ..< max(controlPoints, 3) {
            heading += Double.random(in: -turn ... turn, using: &rng)
            let step = 1 + stepJitter * Double.random(in: -1 ... 1, using: &rng)
            controls.append(controls[controls.count - 1] + Vector2(cos(heading), sin(heading)) * step)
        }
        let dense = Contour(curveThrough: controls, closed: false, spline: .hobby()).points
        let points = resample(dense, count: samples)
        let middle = points.reduce(Vector2.zero, +) / Double(points.count)
        let centered = points.map { $0 - middle }
        let far = centered.map(\.length).max() ?? 1
        return centered.map { $0 / max(far, 1e-9) }
    }

    /// `count` points evenly spaced by length along a polyline, both ends kept.
    static func resample(_ points: [Vector2], count: Int) -> [Vector2] {
        var lengths = [0.0]
        for i in 1 ..< points.count { lengths.append(lengths[i - 1] + (points[i] - points[i - 1]).length) }
        let total = lengths.last ?? 0
        var out: [Vector2] = []
        var j = 1
        for k in 0 ..< count {
            let target = total * Double(k) / Double(count - 1)
            while j < points.count - 1, lengths[j] < target { j += 1 }
            let a = lengths[j - 1], b = lengths[j]
            let f = b > a ? (target - a) / (b - a) : 0
            out.append(points[j - 1] + (points[j] - points[j - 1]) * min(max(f, 0), 1))
        }
        return out
    }

    /// The angle of the line the points lie closest to.
    static func principalAngle(of points: [Vector2]) -> Double {
        var xx = 0.0, xy = 0.0, yy = 0.0
        for p in points {
            xx += p.x * p.x
            xy += p.x * p.y
            yy += p.y * p.y
        }
        return 0.5 * atan2(2 * xy, xx - yy)
    }

    static func distance(from p: Vector2, toSegment a: Vector2, _ b: Vector2) -> Double {
        let ab = b - a
        let t = min(max((p - a).dot(ab) / max(ab.dot(ab), 1e-12), 0), 1)
        return (p - (a + ab * t)).length
    }

    /// Which pen a stroke is dealt: the warm inks a little more often than the
    /// cool ones, as the cluster's middle reads warm.
    static func pen(for u: Double, count: Int) -> Int {
        min(count - 1, Int(pow(u, 1.25) * Double(count)))
    }

    /// The inks on the plotter's pen stalls, warm to cool, in the order it
    /// picks them up.
    static func palette(_ pens: Pens) -> [Color] {
        switch pens {
        case .classical:
            return [0xB3262E, 0xD2512A, 0xE08A2E, 0xC9A43A, 0x8E9A3C, 0x3F7E6A, 0x3F62A8, 0x6A4A93].map { Color(hex: $0) }
        case .earth:
            return [0x8C3B22, 0xA8662E, 0xB89545, 0x7E7A3A, 0x55603A, 0x5E6E78].map { Color(hex: $0) }
        case .sepia:
            return [Color(hex: 0x5A4128)]
        }
    }
}
