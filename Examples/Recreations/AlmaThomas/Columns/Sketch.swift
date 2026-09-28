//  Recreation after Alma Thomas - the vertical mosaics of 1970 to 1972, read
//  from Snoopy Sees Earth Wrapped in Sunset (1970; acrylic on canvas, 47 7/8
//  x 47 7/8 in., Smithsonian American Art Museum, gift of the artist,
//  1978.40.4), Earth Sermon: Beauty, Love and Peace (1971), Mars Dust (1972;
//  Whitney Museum of American Art), and the Art Institute of Chicago's
//  description of Starry Night and the Astronauts (1972; acrylic on canvas,
//  60 x 53 in.). A homage, not a reproduction, and not affiliated with or
//  endorsed by the artist or her estate.
//  https://americanart.si.edu/artwork/snoopy-sees-earth-wrapped-sunset-24020
//  https://www.artic.edu/artworks/129884/starry-night-and-the-astronauts
//  https://americanart.si.edu/artist/alma-thomas-4778
//
//  An original Ollin interpretation, written from the paintings. Nothing was
//  ported: the work is acrylic laid in short strokes on a primed canvas, the
//  ground left showing between them.

import Foundation
import Ollin

/// The vertical mosaics (Alma Thomas, Washington). Around 1970 she ruled her
/// canvases into columns and laid her one mark down them: a short stroke of a
/// flat brush, then the next below it, the primed canvas showing between them
/// and in the thin channels between the columns. In the *Space* paintings the
/// columns fill a disc, the earth seen from the moon, red on the side turned
/// from the sun and orange on the side wrapped in its light, a seam of yellow
/// between; in *Earth Sermon* the columns run the height of the canvas in
/// bands of one color after another, red beside green beside blue; in *Mars
/// Dust* red strokes stand on a dark ground; in *Starry Night and the
/// Astronauts* blues fill the canvas with a patch of red, orange and yellow
/// up at one corner.
///
/// This sketch keeps the rule and deals the numbers. Every column is one
/// vertical line stroked with a brush whose tip is a block `dabLength` long
/// and `dabWidth` wide, stamped down the line at even steps of one length plus
/// `gap`; the columns sit `channel` of a width apart, and each starts at its
/// own dealt height so the strokes of neighbors never line up. A stamp's size
/// varies by `jitter` and its turn by `tilt`, which is the hand; the cuts at
/// the block's corners are dealt once a column. `look` picks the painting,
/// and the seed deals the bands and their colors, each column's tone, its
/// start, and the hand.
///
/// The picture is painted stroke by stroke over the first two thirds of
/// `seconds`, column after column from the left and down each one, holds,
/// and is taken back the way it came, which is also the export loop.
///
/// Every stroke exports as its own closed outline, so `--export-svg` gives the
/// painting back as the blocks of paint, each centered on its column.
@main
final class Columns: Sketch {
    enum Look: String, CaseIterable, ParamOption { case sunset, sermon, marsDust, starryNight }

    @Param(icon: "paintpalette") var look = Look.sunset
    @Param(18 ... 64, icon: "ruler") var dabLength = 38.0
    @Param(8 ... 40, icon: "arrow.left.and.right") var dabWidth = 17.0
    @Param(0.05 ... 0.6, icon: "arrow.up.and.down") var gap = 0.16
    @Param(0.05 ... 1, icon: "rectangle.split.3x1") var channel = 0.32
    @Param(0 ... 0.5, icon: "dice") var jitter = 0.25
    @Param(0 ... 0.3, icon: "angle") var tilt = 0.05
    @Param(12 ... 60, icon: "clock") var seconds = 24.0

    override var loopDuration: Double? { seconds }

    /// One ruled column: its stations (even ones are stroke centers, odd ones the
    /// midpoints between them, so a stamp lands exactly on a station) and the
    /// runs of strokes down it, each in its own color.
    private struct Column {
        var stations: [Vector2]
        var count: Int
        var runs: [Run]
        var brush: Brush
    }

    /// `length` strokes from stroke `start`, counted down the column, in one
    /// color and with a hand of their own.
    private struct Run {
        var start: Int
        var length: Int
        var seed: Int
        var color: Color
    }

    private var ground = Color.white
    private var outside: Color?
    private var disc: Circle?
    private var columns: [Column] = []
    private var strokesOnCanvas = 0

    override func setup() {
        columns = []
        outside = nil
        disc = nil

        let pitch = dabWidth * (1 + channel)
        let step = dabLength * (1 + gap)
        let count = Int((width / pitch).rounded(.up)) + 1
        let x0 = (width - Double(count - 1) * pitch) / 2

        // The painting's own frame: the disc of the earth, or the whole canvas.
        let frame: Rectangle
        switch look {
        case .sunset:
            ground = Color(hex: 0xF1E9D6)
            outside = Color(hex: 0xE0764B)
            let radius = random(0.44, 0.47) * width
            let middle = Vector2(random(0.48, 0.52) * width, random(0.47, 0.51) * height)
            disc = Circle(center: middle, radius: radius)
            frame = Rectangle(x: middle.x - radius, y: middle.y - radius,
                              width: 2 * radius, height: 2 * radius)
        case .sermon:
            ground = Color(hex: 0xF2ECDD)
            frame = bounds
        case .marsDust:
            ground = Color(hex: 0x1B2033)
            frame = bounds
        case .starryNight:
            ground = Color(hex: 0xE9E0CC)
            frame = bounds
        }

        // The bands: how many columns each color takes, dealt down the row.
        let colors = bandColors(count: count, frame: frame, x0: x0, pitch: pitch)

        // The patch of warm strokes up at one corner of the night sky.
        let patch = look == .starryNight
            ? Rectangle(x: random(0.58, 0.64) * width, y: random(0.05, 0.09) * height,
                        width: random(0.26, 0.32) * width, height: random(0.2, 0.26) * height)
            : nil
        let warm = [Color(hex: 0xC93A2E), Color(hex: 0xE6802F), Color(hex: 0xEEC12B)]

        var painted = 0
        for i in 0 ..< count {
            let x = x0 + Double(i) * pitch
            // The strokes start at a dealt height above the top and run a stroke
            // past the bottom, so the columns are cut by the edges the way the
            // canvas cuts them.
            let start = -dabLength + random(0, step)
            let strokes = Int(((height + 2 * dabLength - start) / step).rounded(.up))
            var stations: [Vector2] = []
            stations.reserveCapacity(2 * strokes)
            for k in 0 ..< strokes {
                let y = start + Double(k) * step
                stations.append(Vector2(x, y))
                stations.append(Vector2(x, y + step / 2))
            }
            let tip = Columns.dabTip(width: dabWidth / dabLength,
                                     cutA: random(0.06, 0.22), cutB: random(0.06, 0.22))
            let brush = Brush(.shape(tip), spacing: 1 + gap, sizeJitter: jitter,
                              angle: .followPath, angleJitter: tilt, opacityJitter: 0.08)

            // Which strokes are painted: those whose center lies in the frame,
            // a stroke past its edge (the disc cuts them, the canvas cuts them).
            let inside = frame.inset(by: .all(-dabLength))
            let on = (0 ..< strokes).map { k -> Bool in
                let p = stations[2 * k]
                if let disc { return (p - disc.center).length <= disc.radius + dabLength }
                return inside.contains(p)
            }
            var runs: [Run] = []
            var k = 0
            while k < strokes {
                guard on[k] else { k += 1; continue }
                var length = 0
                while k + length < strokes, on[k + length] { length += 1 }
                // Inside the patch the column changes color for a stretch.
                if let patch, patch.x <= x, x <= (patch.x + patch.width) {
                    let before = (k ..< k + length).filter { stations[2 * $0].y < patch.y }.count
                    let within = (k ..< k + length).filter {
                        stations[2 * $0].y >= patch.y && stations[2 * $0].y <= (patch.y + patch.height)
                    }.count
                    let after = length - before - within
                    let tone = random(-0.08, 0.08)
                    let hot = warm[Int(random(Double(warm.count)))]
                    if before > 0 { runs.append(Run(start: k, length: before, seed: Int(random(1_000_000)), color: colors[i])) }
                    if within > 0 {
                        runs.append(Run(start: k + before, length: within, seed: Int(random(1_000_000)),
                                        color: tone >= 0 ? hot.mixed(with: .white, tone) : hot.mixed(with: .black, -tone)))
                    }
                    if after > 0 { runs.append(Run(start: k + before + within, length: after, seed: Int(random(1_000_000)), color: colors[i])) }
                } else {
                    runs.append(Run(start: k, length: length, seed: Int(random(1_000_000)), color: colors[i]))
                }
                k += length
            }
            painted += runs.reduce(0) { $0 + $1.length }
            columns.append(Column(stations: stations, count: strokes, runs: runs, brush: brush))
        }
        strokesOnCanvas = painted
    }

    /// A color for every column: bands of one to three columns dealt from the
    /// look's palette, or, in the disc, the reds of the dark side, the seam of
    /// yellow, and the oranges of the lit side by where the column falls.
    private func bandColors(count: Int, frame: Rectangle, x0: Double, pitch: Double) -> [Color] {
        func toned(_ c: Color) -> Color {
            let tone = random(-0.07, 0.07)
            return tone >= 0 ? c.mixed(with: .white, tone) : c.mixed(with: .black, -tone)
        }
        var colors: [Color] = []
        switch look {
        case .sunset:
            let reds = [Color(hex: 0xC63A2C), Color(hex: 0xD24632)]
            let oranges = [Color(hex: 0xE5762F), Color(hex: 0xEB8A3A)]
            let yellow = Color(hex: 0xF2C227)
            let seam = random(0.58, 0.66)
            let seamWidth = Double(Int(random(1, 3))) * pitch / frame.width
            for i in 0 ..< count {
                let f = (x0 + Double(i) * pitch - frame.x) / frame.width
                if f < seam { colors.append(toned(reds[Int(random(2))])) }
                else if f < seam + seamWidth { colors.append(toned(yellow)) }
                else if f > 0.94 { colors.append(toned(yellow)) }
                else { colors.append(toned(oranges[Int(random(2))])) }
            }
        case .sermon, .marsDust, .starryNight:
            let palette: [Color]
            let widest: Int
            switch look {
            case .sermon:
                palette = [0xC7382C, 0x2F7D4F, 0x2F5FA8, 0xE87A2F, 0xEFC22E,
                           0xE38A9E, 0x2F8F8F, 0xA22A3A, 0x5FA5D6].map { Color(hex: $0) }
                widest = 3
            case .marsDust:
                palette = [0xB8372A, 0xC94433, 0xA63127, 0xD2503A].map { Color(hex: $0) }
                widest = 2
            default:
                palette = [0x1F3A7A, 0x2C55B0, 0x3A7FC8, 0x6FA8DC, 0x4A6FA0, 0x2A2F6E].map { Color(hex: $0) }
                widest = 3
            }
            var last = -1
            while colors.count < count {
                var pick = Int(random(Double(palette.count)))
                if pick == last { pick = (pick + 1) % palette.count }
                last = pick
                let band = Int(random(1, Double(widest + 1)))
                for _ in 0 ..< band where colors.count < count { colors.append(toned(palette[pick])) }
            }
        }
        return colors
    }

    override func draw() {
        if let outside, let disc {
            background(outside)
            noStroke()
            fill(ground)
            drawCircle(center: disc.center, radius: disc.radius)
            withClip(disc) { paint() }
        } else {
            background(ground)
            paint()
        }
    }

    private func paint() {
        noFill()
        strokeWeight(dabLength)
        var budget = strokesPainted()
        for column in columns where budget > 0 {
            for run in column.runs where budget > 0 {
                let painted = min(run.length, budget)
                budget -= painted
                var brush = column.brush
                brush.seed = run.seed
                stroke(run.color)
                strokeBrush(brush)
                drawPolyline(path(of: column, run: run, strokes: painted))
            }
        }
        noStrokeBrush()
    }

    /// The stations of the first `strokes` strokes of a run: each stroke's center
    /// and the midpoint after it, so the path ends half a step past the last
    /// stamp and the brush places exactly that many.
    private func path(of column: Column, run: Run, strokes: Int) -> [Vector2] {
        var points: [Vector2] = []
        points.reserveCapacity(2 * strokes)
        for i in 0 ..< strokes {
            let station = 2 * (run.start + i)
            points.append(column.stations[station])
            points.append(column.stations[station + 1])
        }
        return points
    }

    /// How many strokes are on the canvas now: laid over the first two thirds
    /// of the cycle, all of them through the next part, then taken back.
    private func strokesPainted() -> Int {
        let phase = (time / seconds).truncatingRemainder(dividingBy: 1)
        let paintEnd = 0.66, holdEnd = 0.88
        let share: Double
        if phase < paintEnd {
            share = phase / paintEnd
        } else if phase < holdEnd {
            share = 1
        } else {
            share = 1 - (phase - holdEnd) / (1 - holdEnd)
        }
        return Int((Double(strokesOnCanvas) * share).rounded(.down))
    }

    /// One block of paint, a length of 1 along x and `width` across, its four
    /// corners cut: one pair of opposite corners by `cutA` of the width, the
    /// other pair by `cutB`. Symmetric under a half turn, so a stamp's center is
    /// the block's own center, while the two different cuts keep the block from
    /// reading as a die.
    static func dabTip(width w: Double, cutA: Double, cutB: Double) -> Shape {
        let h = w / 2
        let a = min(cutA * w, h, 0.25), b = min(cutB * w, h, 0.25)
        let points = [
            Vector2(0.5 - a, -h), Vector2(0.5, -h + a),
            Vector2(0.5, h - b), Vector2(0.5 - b, h),
            Vector2(-0.5 + a, h), Vector2(-0.5, h - a),
            Vector2(-0.5, -h + b), Vector2(-0.5 + b, -h),
        ]
        return Shape(outer: points, holes: [])
    }
}
