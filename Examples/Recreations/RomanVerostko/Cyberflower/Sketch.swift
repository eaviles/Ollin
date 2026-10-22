//  Recreation after Roman Verostko - the Cyberflowers (from 2000), read from
//  Cyberflower, Sunshine Version I (2008; pen plotter drawing in colored
//  inks on paper, 28 x 21.8 cm, Victoria and Albert Museum, London), the
//  Cyberflower Duet: Red and Green (2003), and Cyberflower V, 1 (2000; pen
//  and ink on Strathmore paper, 29 x 23 in., St. Olaf College), with his
//  statements that the series is generated from a single set of coordinates
//  and that the stroke in the lower left is the initiator every pen stroke
//  of the work was improvised from. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist or his estate.
//  https://collections.vam.ac.uk/item/O499690/
//  https://history.siggraph.org/artwork/roman-verostko-cyberflower-duet-red-and-green/
//  https://verostko.com/shows/tempe/tempe.html
//
//  An original Ollin interpretation, written from the drawings and his
//  statements. His software, Hodos, was never published, so nothing was
//  ported, and how a copy of the curve moves from one line to the next is
//  this sketch's own reading.

import Foundation
import Ollin

/// The Cyberflowers (Roman Verostko, Minneapolis). He named the series for
/// forms grown from one curved line repeating itself: the pen plotter draws
/// the curve, then draws it again a hair away, thousands of times, so that
/// what reads as a color field is very closely drawn lines, and where the
/// repeated curve turns over on itself the lines crowd into a dark fold.
/// The curve comes from a single set of coordinates cast at random, and he
/// drew that curve small in the lower left of a sheet, the initiator, the
/// stroke that carries the information every line of the work was improvised
/// from. *Sunshine Version I* lays two such flowers over each other, one in
/// orange and one in yellow.
///
/// This sketch keeps one set of coordinates for everything, as he said the
/// series does. The initiator is a curve through `controlPoints` points,
/// each chained from the last by a step (unequal by up to `stepJitter`) and
/// a turn of up to `turn`. A flower is that curve repeated `lines` times
/// along a larger copy of itself: the copies stand at even steps along the
/// path, each `ribbon` of the flower's size and shrinking toward both ends
/// by `taper`, each turned with the path plus a steady twist of `twist`
/// turns from one end to the other. Where a copy lines up with its own path
/// the ribbon folds and the lines crowd. `look` picks the sheet: the two
/// flowers of *Sunshine*, or one flower in the red or the green of the
/// *Duet*. `lineWeight` and `density` are the pen and its ink.
///
/// Each cycle of `seconds` plots one sheet the way the machine did, the
/// initiator first and then every line in order, holds it, and plots the
/// next sheet of the family: the same settings, the next seed.
///
/// `--export-svg` gives every line back as a polyline through the same
/// number of points as the initiator, each one the initiator moved, turned,
/// and scaled, so the rule can be read from the file.
@main
final class Cyberflower: Sketch {
    enum Look: String, CaseIterable, ParamOption { case sunshine, red, green }

    @Param(icon: "paintpalette") var look = Look.sunshine
    @Param(4 ... 10, icon: "point.topleft.down.to.point.bottomright.curvepath") var controlPoints = 6
    @Param(0.2 ... 2.2, icon: "arrow.turn.up.right") var turn = 1.0
    @Param(0 ... 0.9, icon: "dice") var stepJitter = 0.5
    @Param(200 ... 2400, icon: "line.3.horizontal") var lines = 1800
    @Param(0.1 ... 0.6, icon: "arrow.left.and.right") var ribbon = 0.4
    @Param(0 ... 4, icon: "arrow.triangle.2.circlepath") var twist = 1.5
    @Param(0 ... 0.9, icon: "arrowtriangle.right") var taper = 0.5
    @Param(0.3 ... 1.5, icon: "lineweight") var lineWeight = 0.6
    @Param(0.1 ... 1, icon: "drop") var density = 0.35
    @Param(10 ... 90, icon: "clock") var seconds = 20.0

    override var canvasSize: CanvasSize { .size(864, 1080) }
    override var loopDuration: Double? { seconds }

    /// How many points every line is drawn through, the initiator's own.
    static let samples = 64
    /// How many finished lines are kept in one retained recording.
    static let chunk = 100

    private struct Flower {
        var ink: Color
        var lines: [[Vector2]]
    }

    private var initiator: [Vector2] = []
    private var flowers: [Flower] = []
    private var built: [Double] = []
    private var batches: [Int: Batch] = [:]

    private static let paper = Color(hex: 0xF8F6F0)
    private static let graphite = Color(hex: 0x3A3631)

    override func draw() {
        let work = Int((time / seconds).rounded(.down))
        let signature: [Double] = [Double(variation), Double(work), Double(Look.allCases.firstIndex(of: look) ?? 0),
                                   Double(controlPoints), turn, stepJitter, Double(lines), ribbon, twist, taper]
        if signature != built {
            deal(work: work)
            built = signature
            batches = [:]
        }

        background(Cyberflower.paper)
        noFill()
        let phase = (time / seconds).truncatingRemainder(dividingBy: 1)
        let plotEnd = 0.65
        let share = min(phase / plotEnd, 1)

        // The initiator, small in the lower left, plotted first.
        strokeWeight(1.2)
        stroke(Cyberflower.graphite)
        drawPolyline(initiator)

        // Then every line of every flower in order, the finished hundreds
        // replayed from their recordings.
        let total = flowers.reduce(0) { $0 + $1.lines.count }
        var budget = Int((Double(total) * share).rounded(.down))
        strokeWeight(lineWeight)
        for (f, flower) in flowers.enumerated() where budget > 0 {
            stroke(flower.ink.withAlpha(density))
            let shown = min(budget, flower.lines.count)
            var start = 0
            while start < shown {
                let end = min(start + Cyberflower.chunk, flower.lines.count)
                if end <= shown {
                    let key = f * 1_000_000 + start
                    if batches[key] == nil {
                        let piece = flower.lines[start ..< end]
                        batches[key] = makeBatch { for line in piece { drawPolyline(line) } }
                    }
                    if let batch = batches[key] { drawBatch(batch) }
                } else {
                    for line in flower.lines[start ..< shown] { drawPolyline(line) }
                }
                start = end
            }
            budget -= shown
        }
    }

    // MARK: - Dealing one sheet

    private func deal(work: Int) {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation &* 1_000_003 &+ work &* 7919 &+ 29)))
        func roll(_ a: Double, _ b: Double) -> Double { Double.random(in: a ... b, using: &rng) }

        let curve = Cyberflower.curve(controlPoints: controlPoints, turn: turn, stepJitter: stepJitter, using: &rng)
        // The curve stands upright, its longest reach along the sheet's height.
        let upright = Double.pi / 2 - Cyberflower.principalAngle(of: curve)

        initiator = curve.map { Cyberflower.rotate($0, by: upright) * (0.05 * height) + Vector2(0.11 * width, 0.9 * height) }

        let inks: [Color]
        let centers: [Vector2]
        let size: Double
        switch look {
        case .sunshine:
            inks = [Color(hex: 0xE88A1E), Color(hex: 0xF2C514)]
            centers = [Vector2(0.48 * width, 0.37 * height), Vector2(0.53 * width, 0.61 * height)]
            size = 0.3 * height
        case .red:
            inks = [Color(hex: 0xC42F2A)]
            centers = [Vector2(0.5 * width, 0.48 * height)]
            size = 0.36 * height
        case .green:
            inks = [Color(hex: 0x3D8A4C)]
            centers = [Vector2(0.5 * width, 0.48 * height)]
            size = 0.36 * height
        }

        flowers = zip(inks, centers).map { ink, center in
            let phase = roll(0, .tau)
            let path = curve.map { Cyberflower.rotate($0, by: upright) * size + center }
            return Flower(ink: ink, lines: Cyberflower.flower(of: curve, along: path, lines: lines,
                                                               ribbon: ribbon * size, twist: twist, taper: taper,
                                                               phase: phase))
        }
    }

    /// One flower: the curve repeated `lines` times at even steps along `path`
    /// (a larger copy of itself), each copy `ribbon` across at the middle and
    /// shrinking toward both ends by `taper`, turned with the path plus
    /// `phase` and a steady `twist` turns from end to end.
    static func flower(of curve: [Vector2], along path: [Vector2], lines: Int, ribbon: Double,
                       twist: Double, taper: Double, phase: Double) -> [[Vector2]] {
        let stations = resample(path, count: lines + 2)
        return (0 ..< lines).map { k in
            let t = Double(k) / Double(max(lines - 1, 1))
            let here = stations[k + 1]
            let heading = stations[k + 2] - stations[k]
            let angle = atan2(heading.y, heading.x) + phase + .tau * twist * t
            let scale = ribbon * (1 - taper * pow(abs(2 * t - 1), 2))
            return curve.map { here + rotate($0, by: angle) * scale }
        }
    }

    /// The initiator: a curve through `controlPoints` points, each chained
    /// from the one before by a step (unequal by up to `stepJitter`) and a turn
    /// of up to `turn`, drawn through `samples` points evenly spaced along it,
    /// moved so their middle is the origin and scaled so the farthest is 1.
    static func curve(controlPoints: Int, turn: Double, stepJitter: Double,
                      using rng: inout SplitMix64) -> [Vector2] {
        var heading = Double.random(in: 0 ..< .tau, using: &rng)
        var controls = [Vector2.zero]
        for _ in 1 ..< max(controlPoints, 3) {
            heading += Double.random(in: -turn ... turn, using: &rng)
            let step = 1 + stepJitter * Double.random(in: -1 ... 1, using: &rng)
            controls.append(controls[controls.count - 1] + Vector2(cos(heading), sin(heading)) * step)
        }
        let points = resample(Contour(curveThrough: controls, closed: false).points, count: samples)
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

    static func rotate(_ p: Vector2, by angle: Double) -> Vector2 {
        let c = cos(angle), s = sin(angle)
        return Vector2(c * p.x - s * p.y, s * p.x + c * p.y)
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
}
