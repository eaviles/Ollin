//  Recreation after Mohamed Melehi - Flamme (1975, cellulose paint on wood,
//  109.5 x 95.5 cm), shown in New Waves at The Mosaic Rooms, London (2019),
//  read beside the untitled panel of 1980 (cellulose paint on wood, 84 x 84
//  cm) where the same wave rises out of a wall of grey stripes, and the
//  Volcanique pair of 1985. A homage, not a reproduction, and not affiliated
//  with or endorsed by the artist or his estate.
//  https://www.lawrieshabibi.com/exhibitions/78-new-waves-mohamed-melehi-and-the-casablanca-art-mohamed-melehi-at-the-mosaic-rooms-london/overview/
//  https://hyperallergic.com/new-waves-mohamed-melehi-casablanca-art-school-mosaic-room/
//  https://www.labiennale.org/en/art/2024/abstractions/mohamed-melehi
//
//  An original Ollin interpretation, written from the paintings. Nothing was
//  ported: the work is cellulose paint laid flat on a wooden panel, one color
//  up to the next with no edge between them.

import Foundation
import Ollin

/// The wave standing up (Mohamed Melehi, 1975). In the panels of the middle
/// 1970s the wave turns vertical and burns: a row of bands, pink and navy
/// turn and turn about, each the same undulating curve as its neighbor moved
/// over by one band, rises from the bottom edge and is cut flat at the top,
/// every band at its own height, the tops stepping up to a peak and down
/// again so the row reads as one flame. A straight ribbon of yellow, orange
/// and blue crosses the panel behind it on a slant, the wave's other state,
/// and the ground is a flat sage. The Biennale's text reads his waves as
/// flames, as parts of a body, as magma bursting upward, and traces them
/// back to the bands of the flatwoven Glaoua rugs of the Atlas.
///
/// This sketch keeps the rule and deals the numbers. `bands` bands of
/// `bandWidth` stand side by side, each edge the one curve `x = amplitude *
/// sin(2 * pi * y / wavelength)` moved over by its band, so neighbors share
/// their edge point for point and the fills meet with nothing between them.
/// The peak's band and height, and every step down from it, are dealt from
/// the seed, the steps on the far side of the peak a little longer, and no
/// band ends closer than a hand to the bottom edge. Over one cycle the wave
/// climbs one wavelength, since the phase is the clock, and every top
/// breathes about its height by up to `flicker`, a whole number of times per
/// cycle so the loop closes, but never past the steps to its neighbors, so
/// the tops keep their order, and never under the hand. `stripe` lays the
/// straight ribbon behind the flame; its angle and where it crosses are
/// dealt with the rest.
///
/// Every band and every stripe exports as one closed outline, so
/// `--export-svg` gives the panel back as the regions the paint covers.
@main
final class Flamme: Sketch {
    @Param(4 ... 24, icon: "flame") var bands = 10
    @Param(30 ... 140, icon: "arrow.left.and.right") var bandWidth = 72.0
    @Param(0 ... 80, icon: "water.waves") var amplitude = 24.0
    @Param(80 ... 600, icon: "ruler") var wavelength = 210.0
    @Param(0 ... 60, icon: "wind") var flicker = 16.0
    @Param(icon: "line.diagonal") var stripe = true
    @Param(4 ... 60, icon: "clock") var seconds = 10.0

    override var canvasSize: CanvasSize { .size(940, 1080) }
    override var loopDuration: Double? { seconds }

    /// Edge points are this far apart up a band.
    private let step = 2.5
    /// The shortest band still shows this much above the bottom edge.
    private let hand = 70.0
    /// The straight ribbon's bands, this wide each.
    private let stripeWidth = 24.0

    private let ground = Color(hex: 0x4E9C8C)
    private let pink = Color(hex: 0xF08FB1)
    private let navy = Color(hex: 0x1E2A6A)
    private let stripeColors = [
        Color(hex: 0xF7E37B), Color(hex: 0xF6C93A), Color(hex: 0xF58A1E), Color(hex: 0x2C3E8C),
    ]

    /// One band of the flame: where its top rests, and how it breathes.
    private struct Tongue {
        var top: Double
        var phase: Double
        /// Breaths per cycle, whole so the loop closes.
        var breaths: Double
        /// How far the top breathes, in pixels.
        var breath = 0.0
    }

    override func draw() {
        background(ground)
        noStroke()
        randomSeed(variation)

        // 1. Deal the flame: the peak, the steps away from it, the breathing.
        let peak = Int(random(0.3, 0.6) * Double(bands))
        let peakTop = random(0.10, 0.20) * height
        let lowest = height - hand
        var tongues = [Tongue](repeating: Tongue(top: peakTop, phase: 0, breaths: 1), count: bands)
        // The seed picks which side of the peak falls faster.
        let steepSide = random(1) < 0.5 ? -1.0 : 1.0
        for side in [-1, 1] {
            var top = peakTop
            var j = peak + side
            while j >= 0 && j < bands {
                let long = Double(side) == steepSide
                top = min(top + random(long ? 0.08 : 0.06, long ? 0.16 : 0.11) * height, lowest)
                tongues[j].top = top
                j += side
            }
        }
        for j in 0 ..< bands {
            tongues[j].phase = random(0, 2 * .pi)
            tongues[j].breaths = random(1) < 0.4 ? 2 : 1
            // A band breathes by up to `flicker`, but never past the steps to
            // its neighbors, so the tops keep their order, and never under
            // the hand, so a band that rests on the floor holds still.
            var room = lowest - tongues[j].top
            if j > 0 { room = min(room, 0.45 * abs(tongues[j].top - tongues[j - 1].top)) }
            if j + 1 < bands { room = min(room, 0.45 * abs(tongues[j].top - tongues[j + 1].top)) }
            tongues[j].breath = min(flicker, room)
        }
        let first = random(1) < 0.5 ? pink : navy
        let x0 = (width - Double(bands) * bandWidth) / 2 + random(-40, 40)
        let stripeAngle = random(52, 66) * .pi / 180
        let stripeOffset = random(-0.18, 0.02) * width

        // 2. The straight ribbon, behind the flame.
        if stripe {
            let s = Vector2(cos(stripeAngle), -sin(stripeAngle))
            let m = Vector2(-s.y, s.x)
            let center = Vector2(width / 2, height / 2) + m * stripeOffset
            let reach = center.length + stripeWidth * Double(stripeColors.count)
            for (k, color) in stripeColors.enumerated() {
                let near = Double(k) * stripeWidth - stripeWidth * Double(stripeColors.count) / 2
                let far = near + stripeWidth
                fill(color)
                drawPolygon([
                    center - s * reach + m * near,
                    center + s * reach + m * near,
                    center + s * reach + m * far,
                    center - s * reach + m * far,
                ])
            }
        }

        // 3. The flame. Every edge is the one curve moved over by its band.
        let phase = (time / seconds).truncatingRemainder(dividingBy: 1)
        func edge(_ j: Int, _ y: Double) -> Double {
            x0 + Double(j) * bandWidth + amplitude * sin(2 * .pi * (y / wavelength + phase))
        }
        let bottom = height + 8
        for j in 0 ..< bands {
            let tongue = tongues[j]
            let top = tongue.top + tongue.breath * sin(2 * .pi * tongue.breaths * time / seconds + tongue.phase)
            // Stations from the bottom up, and the top exactly, so the
            // top edge is level between two points of the same curve.
            var ys: [Double] = []
            var y = bottom
            while y > top + step / 2 {
                ys.append(y)
                y -= step
            }
            ys.append(top)
            var points: [Vector2] = []
            points.reserveCapacity(2 * ys.count)
            for y in ys { points.append(Vector2(edge(j, y), y)) }
            for y in ys.reversed() { points.append(Vector2(edge(j + 1, y), y)) }
            fill(j % 2 == 0 ? first : (first == pink ? navy : pink))
            // A band is concave wherever the wave turns, so it is a shape
            // that is triangulated, never a fan.
            drawShape(Shape(outer: points, holes: []))
        }
    }
}
