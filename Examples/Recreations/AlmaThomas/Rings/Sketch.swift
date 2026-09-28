//  Recreation after Alma Thomas - the concentric paintings of 1966 to 1970,
//  read from Resurrection (1966; in the White House collection since 2014)
//  and The Eclipse (1970; acrylic on canvas, 62 x 49 3/4 in., Smithsonian
//  American Art Museum, gift of the artist, 1978.40.3), the last painting of
//  her Space series, after the total solar eclipse of March 7, 1970. A
//  homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or her estate.
//  https://americanart.si.edu/artwork/eclipse-24007
//  https://americanart.si.edu/artist/alma-thomas-4778
//  https://chrysler.org/exhibition/alma-thomas/
//
//  An original Ollin interpretation, written from the paintings. Nothing was
//  ported: the work is acrylic laid in short strokes on a primed canvas, the
//  ground left showing between them.

import Foundation
import Ollin

/// The concentric paintings (Alma Thomas, Washington). From 1966, when she
/// was seventy-four, she painted with one mark: a short stroke of a flat
/// brush, laid down and lifted, the next laid a little way on, the primed
/// canvas left showing between them. In the ring paintings the strokes run
/// around circles: a core in the middle, a ring of one color around it, a
/// ring of the next around that, and so on out past the edges of the canvas,
/// two or three rows of strokes to a ring, each row on its own circle with a
/// thread of ground between it and the next. The colors go around the
/// spectrum from the core outward, and the last color goes on in rings until
/// it fills the corners. `Resurrection` sets its core in the middle and its
/// rings run green, blue, violet, red, orange and out into yellow; `The
/// Eclipse` sets a dark core up and to the right and its rings run grey,
/// blue, indigo, red, orange and out into yellow, so the light seems to move
/// off the canvas the way the moon moved across the sun.
///
/// This sketch keeps the rule and deals the numbers. Every row is one circle
/// stroked with a brush whose tip is a rounded block `dabLength` long and
/// `dabWidth` wide, stamped along the circle at even steps of one length plus
/// `gap`, turned to follow it, so each stroke lies along its ring the way the
/// brush went. The rows sit `channel` of a width apart. A stamp's size varies
/// by `jitter` and its turn by `tilt`, which is the hand; the cuts at the
/// block's corners are dealt once a row. `look` picks the
/// painting, and the seed deals the core's place and size, how many rows each
/// color gets, each row's tone, where each ring's seam falls, and the hand.
///
/// The picture is painted stroke by stroke over the first two thirds of
/// `seconds`, from the core outward and around each ring in the order the
/// brush went, holds, and is taken back the way it came, which is also the
/// export loop.
///
/// Every stroke exports as its own closed outline, so `--export-svg` gives the
/// painting back as the blocks of paint, each centered on its circle.
@main
final class Rings: Sketch {
    enum Look: String, CaseIterable, ParamOption { case resurrection, eclipse }

    @Param(icon: "paintpalette") var look = Look.resurrection
    @Param(18 ... 56, icon: "ruler") var dabLength = 34.0
    @Param(10 ... 40, icon: "arrow.left.and.right") var dabWidth = 24.0
    @Param(0.05 ... 0.6, icon: "arrow.up.and.down") var gap = 0.25
    @Param(0.05 ... 0.8, icon: "circle.dashed") var channel = 0.24
    @Param(0 ... 0.5, icon: "dice") var jitter = 0.22
    @Param(0 ... 0.3, icon: "angle") var tilt = 0.06
    @Param(12 ... 60, icon: "clock") var seconds = 30.0

    override var loopDuration: Double? { seconds }

    /// One circle of strokes: its stations (even ones are stroke centers, odd
    /// ones the midpoints between them, so a stamp lands exactly on a station),
    /// and the runs of strokes that fall on the canvas.
    private struct Row {
        var color: Color
        var stations: [Vector2]
        var count: Int
        var runs: [Run]
        var brush: Brush
    }

    /// A stretch of one ring on the canvas: `length` strokes from stroke `start`,
    /// counted around the ring, with a hand of its own.
    private struct Run {
        var start: Int
        var length: Int
        var seed: Int
    }

    private var ground = Color.white
    private var core = Color.black
    private var origin = Vector2(0, 0)
    private var coreRadius = 60.0
    private var rows: [Row] = []
    private var strokesOnCanvas = 0

    override func setup() {
        rows = []
        let palette = Rings.palette(look)
        ground = palette.ground
        core = palette.core

        switch look {
        case .resurrection:
            origin = center + Vector2(random(-0.02, 0.02) * width, random(-0.02, 0.02) * height)
            coreRadius = random(0.045, 0.065) * width
        case .eclipse:
            origin = Vector2(random(0.62, 0.70) * width, random(0.30, 0.38) * height)
            coreRadius = random(0.13, 0.17) * width
        }

        // The rings reach the farthest corner and a stroke past it.
        let farthest = [Vector2(0, 0), Vector2(width, 0), Vector2(0, height), Vector2(width, height)]
            .map { ($0 - origin).length }.max() ?? width
        let rowPitch = dabWidth * (1 + channel)
        // A stroke counts as on the canvas when its center is within a stroke
        // of the edge, so a stroke cut by the edge is still painted.
        let visible = bounds.inset(by: .all(-dabLength))

        // Each color takes a dealt number of rows; the last color goes on to the corners.
        var dealt: [Color] = []
        for (i, band) in palette.bands.enumerated() {
            let last = i == palette.bands.count - 1
            let rowsHere = last ? Int.max : Int(random(Double(band.rows.lowerBound), Double(band.rows.upperBound + 1)))
            if last {
                var radius = coreRadius + dabWidth * channel + dabWidth / 2 + Double(dealt.count) * rowPitch
                while radius < farthest + dabLength {
                    dealt.append(band.color)
                    radius += rowPitch
                }
            } else {
                for _ in 0 ..< rowsHere { dealt.append(band.color) }
            }
        }

        var painted = 0
        for (j, base) in dealt.enumerated() {
            let radius = coreRadius + dabWidth * channel + dabWidth / 2 + Double(j) * rowPitch
            // Along the ring, one stroke every length and a gap, the count rounded
            // so the ring closes on a whole number of steps.
            let count = max(6, Int((2 * .pi * radius / (dabLength * (1 + gap))).rounded()))
            let seam = random(0, .tau)
            var stations: [Vector2] = []
            stations.reserveCapacity(2 * count)
            for k in 0 ..< 2 * count {
                let angle = seam + Double(k) * .pi / Double(count)
                stations.append(origin + Vector2(cos(angle), sin(angle)) * radius)
            }
            // The brush steps two stations at a time, so every stamp sits on an
            // even station: the chord between neighbors, twice.
            let chord = 2 * radius * sin(.pi / (2 * Double(count)))
            let tone = random(-0.08, 0.08)
            let color = tone >= 0 ? base.mixed(with: .white, tone) : base.mixed(with: .black, -tone)
            let tip = Rings.dabTip(width: dabWidth / dabLength,
                                   cutA: random(0.06, 0.22), cutB: random(0.06, 0.22))
            let brush = Brush(.shape(tip), spacing: 2 * chord / dabLength, sizeJitter: jitter,
                              angle: .followPath, angleJitter: tilt, opacityJitter: 0.08)

            // The runs of strokes on the canvas, counted around the ring from a
            // stroke that is off it when any is, so a run never wraps.
            let on = (0 ..< count).map { visible.contains(stations[2 * $0]) }
            var runs: [Run] = []
            if on.allSatisfy({ $0 }) {
                runs.append(Run(start: 0, length: count, seed: Int(random(1_000_000))))
            } else if let firstOff = on.firstIndex(of: false) {
                var k = 0
                while k < count {
                    let index = (firstOff + k) % count
                    if on[index] {
                        var length = 0
                        while k + length < count, on[(firstOff + k + length) % count] { length += 1 }
                        runs.append(Run(start: index, length: length, seed: Int(random(1_000_000))))
                        k += length
                    } else {
                        k += 1
                    }
                }
            }
            painted += runs.reduce(0) { $0 + $1.length }
            rows.append(Row(color: color, stations: stations, count: count, runs: runs, brush: brush))
        }
        strokesOnCanvas = painted
    }

    override func draw() {
        background(ground)
        noStroke()
        fill(core)
        drawCircle(center: origin, radius: coreRadius)

        noFill()
        strokeWeight(dabLength)
        var budget = strokesPainted()
        for row in rows where budget > 0 {
            stroke(row.color)
            for run in row.runs where budget > 0 {
                let painted = min(run.length, budget)
                budget -= painted
                var brush = row.brush
                brush.seed = run.seed
                strokeBrush(brush)
                drawPolyline(path(of: row, run: run, strokes: painted))
            }
        }
        noStrokeBrush()
    }

    /// The stations of the first `strokes` strokes of a run: each stroke's center
    /// and the midpoint after it, so the path ends half a step past the last
    /// stamp and the brush places exactly that many.
    private func path(of row: Row, run: Run, strokes: Int) -> [Vector2] {
        var points: [Vector2] = []
        points.reserveCapacity(2 * strokes)
        for i in 0 ..< strokes {
            let station = 2 * ((run.start + i) % row.count)
            points.append(row.stations[station])
            points.append(row.stations[station + 1])
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

    private struct Band {
        var color: Color
        var rows: ClosedRange<Int>
    }

    private struct Palette {
        var ground: Color
        var core: Color
        var bands: [Band]
    }

    private static func palette(_ look: Look) -> Palette {
        switch look {
        case .resurrection:
            return Palette(
                ground: Color(hex: 0xF3EEE2), core: Color(hex: 0xE9E1A0),
                bands: [
                    Band(color: Color(hex: 0xC9CF6A), rows: 1 ... 2),
                    Band(color: Color(hex: 0x5FA05A), rows: 2 ... 3),
                    Band(color: Color(hex: 0x3A6DB5), rows: 2 ... 3),
                    Band(color: Color(hex: 0x5B4C9E), rows: 2 ... 3),
                    Band(color: Color(hex: 0xC3405C), rows: 1 ... 2),
                    Band(color: Color(hex: 0xD64A3C), rows: 2 ... 3),
                    Band(color: Color(hex: 0xE9863E), rows: 2 ... 3),
                    Band(color: Color(hex: 0xF0AE3F), rows: 2 ... 3),
                    Band(color: Color(hex: 0xF2CC3E), rows: 1 ... 1),
                ])
        case .eclipse:
            return Palette(
                ground: Color(hex: 0xF4EFE3), core: Color(hex: 0x1C2C47),
                bands: [
                    Band(color: Color(hex: 0x8A9A8E), rows: 2 ... 3),
                    Band(color: Color(hex: 0x2F6FB2), rows: 2 ... 3),
                    Band(color: Color(hex: 0x55A8DA), rows: 2 ... 3),
                    Band(color: Color(hex: 0x3B2E7C), rows: 1 ... 2),
                    Band(color: Color(hex: 0x6A3F98), rows: 1 ... 2),
                    Band(color: Color(hex: 0xD23C30), rows: 3 ... 4),
                    Band(color: Color(hex: 0xE2582F), rows: 2 ... 3),
                    Band(color: Color(hex: 0xEC8B34), rows: 3 ... 4),
                    Band(color: Color(hex: 0xF2B233), rows: 2 ... 3),
                    Band(color: Color(hex: 0xF5CF36), rows: 1 ... 1),
                ])
        }
    }
}
