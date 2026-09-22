//  Recreation after Nasreen Mohamedi - the untitled ink and graphite drawings
//  of about 1980, read from the sheets Talwar Gallery shows (Untitled, ca.
//  1980, ink and graphite on paper, 19 1/2 x 27 in., TG 1658; Untitled, ca.
//  1980, 19 x 27 in., TG 1659; Untitled, ca. 1980s, 22.28 x 28.38 in., TG
//  1683) and the works of that period in the Metropolitan Museum of Art's
//  2016 retrospective. Every work of hers is untitled, so nothing here is
//  named after one. A homage, not a reproduction, and not affiliated with or
//  endorsed by the artist or her estate.
//  https://www.talwargallery.com/artists/nasreen-mohamedi
//  https://www.metmuseum.org/exhibitions/listings/2016/nasreen-mohamedi
//
//  An original Ollin interpretation, written from the drawings. Nothing was
//  ported: the work is a ruling pen and a pencil on paper.

import Foundation
import Ollin

/// The floating diagonals of about 1980 (Nasreen Mohamedi, Baroda). Late in
/// the 1970s she let go of the sheet-wide grid. The drawings of her last
/// decade are wide sheets left mostly empty, with a figure floating low or
/// in the middle: a chevron drawn heavy in ink, two arms meeting at a corner,
/// most often a right angle and sometimes an open one; then, laid off one of
/// its arms, a wake of hairlines that run parallel to the other, packed close
/// against it and opening out, their ends staggered, fading as they go; and
/// from some sheets a fan of hairlines that lean a little more with every
/// line and would meet at a point somewhere past the edge of the paper. The
/// whole figure sits on one diagonal. The heavy arms are a ruling pen's:
/// loaded at the corner and thinning as the stroke runs out, so an arm is
/// widest where the two meet and finest at its end. Huntington's disease was
/// taking her hands by then, and the drawings only got more exact.
///
/// This sketch keeps that vocabulary and deals a figure from the seed. One
/// axis crosses the sheet at a slant. Along it stand one to four chevrons,
/// nested corner behind corner or strung out along the axis, each with its
/// opening angle, its arm lengths, and its weight, drawn as one stroke whose
/// width is full at the corner and ramps down to the tip of each arm. A
/// chevron may carry a wake: hairlines parallel to its long arm, laid along
/// the short one at intervals that grow by a ratio, each shorter and paler
/// than the last. It may carry a fan: hairlines from stations along the short
/// arm toward one point well off the sheet, cut at the margin, so they lean
/// apart as they leave. The figure floats: over one cycle it slides a little
/// along its axis and back, each fan's far point moves so the fan sweeps,
/// and the wakes' ends breathe. `chevrons` is how many, `drift` how far all
/// of that goes (0 holds the sheet still), `seconds` the cycle and the export
/// loop, and `wakes` and `fans` switch each kind of hairline off. The seed is
/// the sheet.
///
/// `--export-svg` gives the drawing back for a pen: every hairline as a
/// line, and each chevron as the outline of the region its stroke covers, so
/// the thinning survives on paper. In the file every wake's lines share one
/// angle exactly, every fan's lines meet at one point outside the margin,
/// each arm's width runs one way from the corner, and nothing crosses the
/// margin.
@main
final class Diagonals: Sketch {
    @Param(1 ... 4, icon: "chevron.up") var chevrons = 2
    @Param(0 ... 1, icon: "wind") var drift = 0.5
    @Param(8 ... 60, icon: "clock") var seconds = 24.0
    @Param(icon: "line.3.horizontal") var wakes = true
    @Param(icon: "line.diagonal") var fans = true

    override var canvasSize: CanvasSize { .size(1440, 1040) }
    override var loopDuration: Double? { max(4, seconds) }

    /// The paper's margin: no ink crosses it.
    private let margin = 60.0

    private let paper = Color(hex: 0xF0EBDB)
    private let ink = Color(white: 0.07)

    private struct Chevron {
        var corner: Vector2
        /// The long arm's direction, along the sheet's axis.
        var long: Vector2
        /// The short arm's direction, turned from the long one by the opening.
        var short: Vector2
        var longLength, shortLength: Double
        /// The stroke's width at the corner, and the fraction left at a tip.
        var weight, tip: Double
        /// The wake, if any: how many hairlines, their ratio, their first
        /// length, whether they run back behind the corner, and a phase.
        var wake: (count: Int, ratio: Double, length: Double, back: Bool, phase: Double)?
        /// The fan, if any: its stations, the far point's distance along the
        /// long arm, its offset to the side, and how far it sweeps.
        var fan: (count: Int, distance: Double, offset: Double, sweep: Double, phase: Double)?
    }

    override func draw() {
        background(paper)
        noFill()
        strokeCap(.butt)
        strokeJoin(.miter)
        randomSeed(variation)

        // The field a hairline's center may reach; the chevrons keep their
        // own width inside it.
        let hair = 0.6
        let x0 = margin + hair / 2, y0 = margin + hair / 2
        let x1 = width - margin - hair / 2, y1 = height - margin - hair / 2
        let cycle = max(4, seconds)
        let phase = (time / cycle).truncatingRemainder(dividingBy: 1) * 2 * .pi

        // 1. Deal the sheet: the axis, then every chevron and what it carries.
        let slant = random(16, 34) * .pi / 180
        let rising = random(1) < 0.5
        let long = Vector2(cos(slant), rising ? -sin(slant) : sin(slant))
        let side = random(1) < 0.5 ? 1.0 : -1.0
        let across = long.perpendicular * side
        // The figure's home, and the slow slide it makes from there and back
        // over the cycle; the deal never reads the clock.
        let home = Vector2(width / 2 + random(-100, 100), height * 0.56 + random(-80, 80))
        let slide = long * (60 * drift * sin(phase)) + across * (24 * drift * sin(2 * phase + 1.3))
        let center = home + slide
        let nested = random(1) < 0.5
        let gap = nested ? random(60, 150) : random(200, 340)
        var dealt: [Chevron] = []
        for j in 0 ..< chevrons {
            let opening: Double = {
                let pick = random(1)
                if pick < 0.6 { return .pi / 2 }
                if pick < 0.8 { return .pi * 2 / 3 }
                return .pi * 5 / 6
            }()
            let short = long * cos(opening) + across * sin(opening)
            let step = Double(j) - Double(chevrons - 1) / 2
            let bisector = long + short
            let bisectorLength = hypot(bisector.x, bisector.y)
            let corner = nested
                ? center + bisector / max(bisectorLength, 1e-9) * (step * gap) + long * random(-60, 60)
                : center + long * (step * gap) + across * random(-70, 70)
            let weight = random(5, 9)
            var chevron = Chevron(corner: corner, long: long, short: short,
                                  longLength: random(220, 560), shortLength: random(140, 420),
                                  weight: weight, tip: random(0.25, 0.5), wake: nil, fan: nil)
            if wakes, random(1) < 0.75 {
                chevron.wake = (count: Int(random(10, 26)), ratio: random(1.05, 1.16),
                                length: random(320, 720), back: random(1) < 0.5, phase: random(0, 2 * .pi))
            }
            if fans, random(1) < 0.55 {
                chevron.fan = (count: Int(random(8, 18)), distance: random(2200, 3600),
                               offset: random(-420, 420), sweep: random(160, 360), phase: random(0, 2 * .pi))
            }
            dealt.append(chevron)
        }

        // 2. Keep every chevron's arms inside the margin by their own width,
        //    and a little more, so the figure floats rather than touches. The
        //    reach is measured from the figure's home with the whole slide
        //    allowed for, so an arm keeps one length through the cycle.
        for k in dealt.indices {
            let inset = dealt[k].weight + 36 + 84 * drift
            let at = dealt[k].corner - slide
            dealt[k].longLength = min(dealt[k].longLength,
                                      reach(from: at, along: dealt[k].long,
                                            x0: x0 + inset, y0: y0 + inset, x1: x1 - inset, y1: y1 - inset))
            dealt[k].shortLength = min(dealt[k].shortLength,
                                       reach(from: at, along: dealt[k].short,
                                             x0: x0 + inset, y0: y0 + inset, x1: x1 - inset, y1: y1 - inset))
        }

        // 3. The hairlines first, under the ink.
        strokeWeight(hair)
        for chevron in dealt {
            if let wake = chevron.wake {
                let heading = chevron.long * (wake.back ? -1 : 1)
                var offset = chevron.weight
                for i in 0 ..< wake.count {
                    let share = Double(i) / Double(max(1, wake.count - 1))
                    let breath = 1 + 0.18 * drift * sin(phase + wake.phase + Double(i) * 0.45)
                    let length = wake.length * (1 - 0.55 * share) * breath
                    let start = chevron.corner + chevron.short * offset
                    stroke(Color(white: 0.34 + 0.48 * share))
                    if let (a, b) = clipped(start, start + heading * length, x0: x0, y0: y0, x1: x1, y1: y1) {
                        drawLine(a, b)
                    }
                    offset += chevron.weight * 0.9 * pow(wake.ratio, Double(i))
                }
            }
            if let fan = chevron.fan {
                let sway = fan.offset + fan.sweep * drift * sin(phase + fan.phase)
                let far = chevron.corner + chevron.long * fan.distance + across * sway
                for i in 0 ..< fan.count {
                    let share = Double(i) / Double(max(1, fan.count - 1))
                    // Stations sit on the short arm itself, from just past
                    // the stroke's width to its tip.
                    let station = chevron.corner
                        + chevron.short * (chevron.weight * 1.5
                                           + share * (chevron.shortLength - chevron.weight * 1.5))
                    stroke(Color(white: 0.36 + 0.44 * share))
                    if let (a, b) = clipped(station, far, x0: x0, y0: y0, x1: x1, y1: y1) {
                        drawLine(a, b)
                    }
                }
            }
        }

        // 4. The chevrons: one stroke each, full at the corner, thinning to
        //    both tips.
        stroke(ink)
        for chevron in dealt {
            let total = chevron.longLength + chevron.shortLength
            strokeWeight(chevron.weight)
            strokeProfile(.values([chevron.tip, 1, chevron.tip], at: [0, chevron.longLength / total, 1]))
            drawPolyline([chevron.corner + chevron.long * chevron.longLength,
                          chevron.corner,
                          chevron.corner + chevron.short * chevron.shortLength])
        }
        noStrokeProfile()
    }

    /// How far a ray from `from` along `along` runs before it leaves the box.
    private func reach(from: Vector2, along: Vector2, x0: Double, y0: Double, x1: Double, y1: Double) -> Double {
        var best = Double.infinity
        if along.x > 1e-9 { best = min(best, (x1 - from.x) / along.x) }
        if along.x < -1e-9 { best = min(best, (x0 - from.x) / along.x) }
        if along.y > 1e-9 { best = min(best, (y1 - from.y) / along.y) }
        if along.y < -1e-9 { best = min(best, (y0 - from.y) / along.y) }
        return max(0, best)
    }

    /// The part of the segment inside the box, or nil when none of it is.
    private func clipped(_ a: Vector2, _ b: Vector2,
                         x0: Double, y0: Double, x1: Double, y1: Double) -> (Vector2, Vector2)? {
        let d = b - a
        var t0 = 0.0, t1 = 1.0
        for (p, q) in [(-d.x, a.x - x0), (d.x, x1 - a.x), (-d.y, a.y - y0), (d.y, y1 - a.y)] {
            if abs(p) < 1e-12 {
                if q < 0 { return nil }
                continue
            }
            let t = q / p
            if p < 0 {
                if t > t1 { return nil }
                t0 = max(t0, t)
            } else {
                if t < t0 { return nil }
                t1 = min(t1, t)
            }
        }
        guard t1 - t0 > 1e-9 else { return nil }
        return (a + d * t0, a + d * t1)
    }
}
