//  Recreation after Kazuya Sakai - Miles Davis, A Tribute to Jack Johnson
//  (II) Right Off (1973, acrylic on raw canvas, 154.5 x 109.1 cm), at the
//  Blanton Museum of Art, The University of Texas at Austin, the year the
//  circle came into his fields of flat color. A homage, not a reproduction,
//  and not affiliated with or endorsed by the artist or his estate.
//  https://blanton.emuseum.com/objects/13898/miles-davis-a-tribute-to-jack-johnson-ii-right-off
//  https://athenaeumreview.org/essay/kazuya-sakai-in-texas/
//
//  An original Ollin interpretation, written from the painting. Nothing was
//  ported: the work is acrylic on raw canvas.

import Foundation
import Ollin

/// Right Off (Kazuya Sakai, Mexico City, 1973). Before the ribbons there
/// were fields: by the late 1960s he had left the gestural brush for strips
/// of paint with hard edges and large areas of one flat color, and around
/// 1973 the circle came into them. The canvas named after the first side of
/// Miles Davis's boxing record is a landscape of arcs: two navy suns at the
/// top corners, each ruled inside with thin white rings a step apart; a red
/// arch of ground between them; two hills of orange-red that are bands of a
/// circle, with thin stripes of green, lavender and orange running across
/// them where the sky meets the land; and two great red lobes rising from
/// the bottom corners, between which a valley opens down to a navy floor
/// and a dark band with two white hairlines.
///
/// This sketch keeps the picture's parts and deals the numbers. The ground
/// is a score of horizontal bands: a maroon top, a zone of thin stripes in
/// a dealt order, a dark band with two hairlines, and navy to the bottom.
/// Over it, `suns` discs set in from the top corners, each with `rings`
/// white rings spaced evenly and a white rim; `hills` crescents of circles
/// centered far below, each thickest at its own edge of the panel and
/// thinning to nothing toward the other; the stripes again, so they cross
/// the hills; and last the two lobes, circles
/// centered out past the bottom corners, whose arcs leave the valley
/// between them. The seed deals every height, center, radius and color of
/// the stripes. Over one cycle of `seconds` the rings travel outward
/// through each sun `laps` times, the lobes rise and fall against each
/// other so the valley breathes, and the hills slide a little, which is
/// also the export loop.
///
/// `--export-svg` gives the score as rectangles, every ring and lobe as a
/// circle, and each hill as one outline with a hole, the two circles it
/// lies between.
@main
final class RightOff: Sketch {
    @Param(1 ... 4, icon: "sun.max") var suns = 2
    @Param(0 ... 3, icon: "mountain.2") var hills = 2
    @Param(2 ... 6, icon: "circle.circle") var rings = 3
    @Param(0 ... 4, icon: "metronome") var laps = 1
    @Param(4 ... 60, icon: "clock") var seconds = 12.0

    override var canvasSize: CanvasSize { .size(764, 1080) }
    override var loopDuration: Double? { seconds }

    private let maroon = Color(hex: 0x6E1A12)
    private let field = Color(hex: 0xB8341A)
    private let dark = Color(hex: 0x3C1B14)
    private let navy = Color(hex: 0x1B2058)
    private let sun = Color(hex: 0x151A3A)
    private let white = Color(hex: 0xF6F3EC)
    private let stripePaints = [Color(hex: 0x3A6A3A), Color(hex: 0x8A86C8), Color(hex: 0x4A3C78),
                                Color(hex: 0xE07A28), Color(hex: 0xF4F2EC), Color(hex: 0x6A5CA8)]
    private let hillPaints = [Color(hex: 0xC23A1C), Color(hex: 0xC84A1E), Color(hex: 0xB03018)]
    private let lobePaints = [Color(hex: 0xB4281A), Color(hex: 0xA8261C)]

    private struct Stripe {
        var color: Color
        var y: Double
        var height: Double
    }

    private struct Sun {
        var center: Vector2
        var radius: Double
    }

    private struct Hill {
        var center: Vector2
        var radius: Double
        /// The inner circle, moved toward the far side, so the hill is
        /// thickest at its own edge and closes before the other one.
        var inner: Vector2
        var innerRadius: Double
        var color: Color
        var drift: Double
    }

    private struct Lobe {
        var center: Vector2
        var radius: Double
        var color: Color
    }

    private struct Plan {
        var skyBottom = 0.0
        var stripesBottom = 0.0
        var darkBottom = 0.0
        var hairlines: [Double] = []
        var stripes: [Stripe] = []
        var suns: [Sun] = []
        var hills: [Hill] = []
        var lobes: [Lobe] = []
    }

    private func deal() -> Plan {
        var plan = Plan()
        let u = height / 120

        // 1. The suns, set in from the top corners, each clear of the next.
        for k in 0 ..< suns {
            let along = suns == 1 ? 0.5 : Double(k) / Double(suns - 1)
            let cx = lerp(0.08, 0.92, along) * width + random(-0.04, 0.04) * width
            let cy = random(-0.06, 0.04) * height
            var r = random(0.2, 0.27) * height
            if let last = plan.suns.last {
                r = min(r, (Vector2(cx, cy) - last.center).length - last.radius - 2 * u)
            }
            plan.suns.append(Sun(center: Vector2(cx, cy), radius: max(r, 4 * u)))
        }
        let sunsBottom = plan.suns.map { $0.center.y + $0.radius }.max() ?? 0

        // 2. The score: the sky, a zone of stripes, the dark band, the floor.
        plan.skyBottom = max(random(0.31, 0.38) * height, sunsBottom + 3 * u)
        plan.stripesBottom = plan.skyBottom + random(0.08, 0.13) * height
        plan.darkBottom = plan.stripesBottom + random(0.08, 0.12) * height
        plan.hairlines = [plan.stripesBottom + 1 * u, plan.stripesBottom + 2.6 * u]
        var y = plan.skyBottom + random(0.5, 1.5) * u
        var lastPaint = -1
        while y < plan.stripesBottom - u {
            var pick = Int(random(Double(stripePaints.count)))
            if pick == lastPaint { pick = (pick + 1) % stripePaints.count }
            lastPaint = pick
            let h = random(0.6, 3) * u
            if y + h > plan.stripesBottom - 0.5 * u { break }
            plan.stripes.append(Stripe(color: stripePaints[pick], y: y, height: h))
            y += h + random(0.8, 2.5) * u
        }

        // 3. The hills: each the region between two circles centered far
        // below, the outer one's top at its own edge of the panel, the inner
        // one moved toward the valley and sized so the two cross there,
        // which thins the hill from `thickness` at its edge to nothing. The
        // hills from the two sides meet at the valley, their tips just past
        // each other.
        let valley = random(0.45, 0.6) * width
        for k in 0 ..< hills {
            let left = k % 2 == 0
            let cx = (left ? random(-0.15, 0.2) : random(0.8, 1.15)) * width
            let cy = random(1.0, 1.25) * height
            let top = plan.skyBottom + random(-0.01, 0.05) * height
            let radius = cy - top
            let thickness = random(0.05, 0.1) * height
            let closes = abs(valley + (left ? 0.04 : -0.04) * width - cx)
            let shift = thickness * radius / closes
            let innerRadius = (radius * radius + shift * shift - 2 * shift * closes).squareRoot()
            let inner = Vector2(cx + (left ? shift : -shift), cy)
            plan.hills.append(Hill(center: Vector2(cx, cy), radius: radius, inner: inner,
                                   innerRadius: innerRadius, color: hillPaints[k % hillPaints.count],
                                   drift: random(0, 2 * .pi)))
        }

        // 4. The lobes: a circle out past each bottom corner, through a point
        // on its side edge, placed so a valley stays open between them.
        for _ in 0 ..< 20 {
            let yLeft = random(0.33, 0.42) * height
            let cLeft = Vector2(-random(0.3, 0.6) * width, random(0.95, 1.1) * height)
            let rLeft = (cLeft - Vector2(0, yLeft)).length
            let yRight = random(0.4, 0.5) * height
            let cRight = Vector2(width + random(0.4, 0.7) * width, random(0.95, 1.1) * height)
            let rRight = (cRight - Vector2(width, yRight)).length
            let leftFoot = cLeft.x + (rLeft * rLeft - (height - cLeft.y) * (height - cLeft.y)).squareRoot()
            let rightFoot = cRight.x - (rRight * rRight - (height - cRight.y) * (height - cRight.y)).squareRoot()
            plan.lobes = [Lobe(center: cLeft, radius: rLeft, color: lobePaints[0]),
                          Lobe(center: cRight, radius: rRight, color: lobePaints[1])]
            if rightFoot - leftFoot > 3 * u { break }
        }
        return plan
    }

    override func draw() {
        background(maroon)
        noStroke()
        randomSeed(variation)
        let plan = deal()
        let u = height / 120
        let phase = loopProgress(over: seconds)

        // 1. The score's base.
        fill(field)
        drawRect(0, plan.skyBottom, width, plan.stripesBottom - plan.skyBottom)
        fill(dark)
        drawRect(0, plan.stripesBottom, width, plan.darkBottom - plan.stripesBottom)
        fill(navy)
        drawRect(0, plan.darkBottom, width, height - plan.darkBottom)

        // 2. The suns, their rings traveling outward, and their rims.
        for (i, s) in plan.suns.enumerated() {
            fill(sun)
            drawCircle(center: s.center, radius: s.radius)
            noFill()
            let step = s.radius / (Double(rings) + 0.35)
            let travel = Double(laps) * phase + Double(i) / Double(max(plan.suns.count, 1))
            for k in 0 ..< rings {
                let place = (Double(k + 1) + travel).truncatingRemainder(dividingBy: Double(rings) + 1)
                let r = place * step
                // A ring fades in as it is born at the center and out at the rim.
                let fade = min(place / 0.6, (Double(rings) + 1 - place) / 0.6, 1)
                guard fade > 0.01 else { continue }
                stroke(white.withAlpha(fade))
                strokeWeight(0.45 * u)
                drawCircle(center: s.center, radius: r)
            }
            stroke(white)
            strokeWeight(0.8 * u)
            drawCircle(center: s.center, radius: s.radius - 0.9 * u)
            noStroke()
        }

        // 3. The hills, each the region between its two circles, the first
        // dealt in front.
        for h in plan.hills.reversed() {
            let slide = Vector2(0.02 * width * sin(2 * .pi * phase + h.drift), 0)
            fill(h.color)
            drawShape(Shape(outer: Circle(center: h.center + slide, radius: h.radius).contour().points,
                            holes: [Circle(center: h.inner + slide, radius: h.innerRadius).contour().points]))
        }

        // 4. The stripes and the hairlines, over the hills.
        for stripe in plan.stripes {
            fill(stripe.color)
            drawRect(0, stripe.y, width, stripe.height)
        }
        fill(white)
        for y in plan.hairlines {
            drawRect(0, y, width, 0.25 * u)
        }

        // 5. The lobes, rising and falling against each other.
        for (i, lobe) in plan.lobes.enumerated() {
            let rise = 0.015 * height * sin(2 * .pi * phase + Double(i) * .pi)
            fill(lobe.color)
            drawCircle(center: lobe.center + Vector2(0, rise), radius: lobe.radius)
        }
    }
}
