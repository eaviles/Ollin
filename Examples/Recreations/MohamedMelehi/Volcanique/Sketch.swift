//  Recreation after Mohamed Melehi - Volcanic (1985, cellulose paint on wood,
//  200 x 150 cm), shown as Volcanique 1 and 2 in New Waves at The Mosaic
//  Rooms, London (2019), read beside the untitled panel of 1980 (cellulose
//  paint on wood, 84 x 84 cm) where nested waves rise out of a wall of gray
//  stripes. A homage, not a reproduction, and not affiliated with or endorsed
//  by the artist or his estate.
//  https://www.lawrieshabibi.com/artists/167-mohamed-melehi/
//  https://hyperallergic.com/new-waves-mohamed-melehi-casablanca-art-school-mosaic-room/
//
//  An original Ollin interpretation, written from the paintings. Nothing was
//  ported: the work is cellulose paint laid flat on wooden panels, one color
//  up to the next with no edge between them.

import Foundation
import Ollin

/// The volcano (Mohamed Melehi, 1985). Four tall panels hang side by side,
/// each its own sky, three blues and a night, and each holds a sun: a disc of
/// blue over a disc of yellow, so only a thin crescent of the yellow shows,
/// like the sun behind the moon. From panel to panel the sun grows and moves
/// toward the panel's left edge, until the edge cuts it and only part of the
/// disc is left. Under the skies stands a mountain made of bands. Up its left
/// face the bands run straight, gray and orange turn and turn about; at the
/// ridge they turn and come down the right face as his wave, white and gold,
/// the first gray and orange carried over the top whole.
///
/// This sketch keeps the rule and deals the numbers. A band is everything
/// between two depths below the mountain's outline, `bandWidth` apart. On
/// the left face the depth is the distance from a straight line; on the right
/// face it is the distance from the wave, so every edge on that face is the
/// one wave moved in by its depth and every band is a whole lane down to the
/// panel's edge. Where the two depths agree is the seam the bands turn on,
/// and a band's two halves meet there on the same points, so the fills meet
/// with nothing between them. `face` colors the straight face and `slope` the
/// wave face, after the bands that cross the ridge in `face`'s colors. The
/// suns grow by one ratio from panel to panel, and a sun the left edge cuts
/// is drawn as the part of its disc the panel keeps, a true arc closed by the
/// edge.
///
/// The wave runs down the slope because the phase is the clock, one
/// wavelength per `seconds`, which is also the export loop, and each sun's
/// crescent swings about its disc once in the same time. The seed deals the
/// ridge, the two slopes, and how high the suns hang.
///
/// Every band, sky and sun exports as one closed outline, so `--export-svg`
/// gives the panels back as the regions the paint covers.
@main
final class Volcanique: Sketch {
    @Param(count: 1 ... 6, icon: "cloud.sun") var skies = Palette(
        Color(hex: 0x7DB6E4), Color(hex: 0xCBE3EC), Color(hex: 0x86C0EA), Color(hex: 0x2F2C3E))
    @Param(count: 1 ... 6, icon: "triangle") var face = Palette(Color(hex: 0xB3ACA4), Color(hex: 0xEE5F0A))
    @Param(count: 1 ... 6, icon: "water.waves") var slope = Palette(Color(hex: 0xF3E7D6), Color(hex: 0xF0A21A))
    @Param(icon: "circle.fill") var disc = Color(hex: 0x4AA2DC)
    @Param(icon: "sun.max") var corona = Color(hex: 0xE6DE6C)
    @Param(1 ... 8, icon: "rectangle.split.3x1") var panels = 4
    @Param(10 ... 80, icon: "arrow.left.and.right") var bandWidth = 27.0
    @Param(0 ... 40, icon: "water.waves") var amplitude = 16.0
    @Param(30 ... 300, icon: "ruler") var wavelength = 120.0
    @Param(0 ... 0.3, icon: "moon") var eclipse = 0.08
    @Param(4 ... 60, icon: "clock") var seconds = 12.0

    override var canvasSize: CanvasSize { .size(810, 1080) }
    override var loopDuration: Double? { seconds }

    /// Edge points are this far apart down the wave face.
    private let step = 2.0
    /// The first sun's radius and the last's, as shares of a panel's width.
    private let smallest = 0.26
    private let largest = 0.47

    override func draw() {
        background(skies[0])
        noStroke()
        randomSeed(variation)

        // 1. Deal the panels: how high the suns hang, the ridge, the two slopes.
        let sunHeight = random(0.18, 0.24) * height
        let apex = Vector2(random(0.18, 0.32) * width, random(0.37, 0.46) * height)
        let rise = random(50, 60) * .pi / 180
        let fall = random(27, 35) * .pi / 180
        let clock = 2 * .pi * time / seconds

        // 2. The skies, and a sun in each, larger by one ratio every panel and
        // nearer its panel's left edge, the crescent swinging once a cycle.
        let panelWidth = width / Double(panels)
        for k in 0 ..< panels {
            let left = Double(k) * panelWidth
            fill(skies[k % skies.count])
            drawRect(left, 0, panelWidth, height)
            let f = panels == 1 ? 0 : Double(k) / Double(panels - 1)
            let radius = panelWidth * smallest * pow(largest / smallest, f)
            let center = Vector2(left + panelWidth * (0.5 - 0.44 * f), sunHeight)
            let lean = (40 + 30 * sin(clock + 2 * .pi * Double(k) / Double(panels))) * .pi / 180
            let shift = Vector2(cos(lean), sin(lean)) * (eclipse * radius * (0.5 + 0.5 * f))
            fill(corona)
            drawSun(center + shift, radius, left, left + panelWidth)
            fill(disc)
            drawSun(center, radius, left, left + panelWidth)
        }

        // 3. The mountain's two faces. `rise` is the straight face's climb and
        // `fall` the wave face's descent; each face has a direction down it and
        // a direction in, toward the mountain's heart.
        let downLeft = Vector2(-cos(rise), sin(rise))
        let downRight = Vector2(cos(fall), sin(fall))
        let inLeft = Vector2(sin(rise), cos(rise))
        let inRight = Vector2(-sin(fall), cos(fall))
        let phase = (time / seconds).truncatingRemainder(dividingBy: 1)
        let wavenumber = 2 * Double.pi / wavelength
        func wave(_ s: Double) -> Double { amplitude * sin(wavenumber * s - 2 * .pi * phase) }
        func waveSlope(_ s: Double) -> Double { amplitude * wavenumber * cos(wavenumber * s - 2 * .pi * phase) }
        /// A point on the wave face, `s` down it and `depth` in from the wave.
        func onSlope(_ depth: Double, _ s: Double) -> Vector2 { apex + downRight * s + inRight * (depth + wave(s)) }

        // Where the two faces' depths agree: the seam the bands turn on. At
        // `s` down the wave face the seam is this deep, and the depth grows
        // steadily down the seam, so each band's corner is found by Newton's
        // method from the straight mountain's answer.
        let turnSin = sin(rise + fall), turnCos = cos(rise + fall)
        func seamDepth(_ s: Double) -> Double { (s * turnSin + wave(s) * turnCos) / (1 - turnCos) }
        func seam(at depth: Double) -> Double {
            var s = depth * (1 - turnCos) / turnSin
            for _ in 0 ..< 8 {
                s -= (seamDepth(s) - depth) / ((turnSin + waveSlope(s) * turnCos) / (1 - turnCos))
            }
            return s
        }

        // Each wave edge runs from its corner on the seam to past the panel's
        // edge, on stations shared by every edge so neighbors match point for
        // point.
        let margin = 8.0
        func stations(_ depth: Double, from s0: Double) -> [Double] {
            let pastRight = (width + margin - apex.x + (depth + amplitude) * sin(fall)) / cos(fall)
            let pastBottom = (height + margin - apex.y - (depth - amplitude) * cos(fall)) / sin(fall)
            let end = max(min(pastRight, pastBottom), s0 + step)
            var ss = [s0]
            var s = ((s0 / step).rounded(.down) + 1) * step
            while s < end {
                if s - s0 > step / 4 { ss.append(s) }
                s += step
            }
            ss.append(s)
            return ss
        }

        // As many bands as reach the deepest point of the canvas. Depth is the
        // smaller of the two faces' depths, so it is deepest on the canvas's
        // edge, where the seam leaves it; the edge is read every few points.
        var deepest = 0.0
        for i in 0 ... 400 {
            let f = Double(i) / 400
            for p in [Vector2(f * width, height), Vector2(0, f * height), Vector2(width, f * height)] {
                deepest = max(deepest, min((p - apex).dot(inLeft), (p - apex).dot(inRight) + amplitude))
            }
        }
        let count = Int((deepest / bandWidth).rounded(.up)) + 1
        let far = Vector2(width, height).length

        // 4. The bands, each the stripe on the straight face and the lane on
        // the wave face that meet on the seam between its two depths.
        var corner = seam(at: 0)
        var upper = stations(0, from: corner).map { onSlope(0, $0) }
        for j in 0 ..< count {
            let inner = Double(j + 1) * bandWidth
            let next = seam(at: inner)
            let lower = stations(inner, from: next).map { onSlope(inner, $0) }
            var turn: [Vector2] = [upper[0]]
            let pieces = max(2, Int(((next - corner) / step).rounded(.up)))
            for i in 1 ..< pieces {
                let s = corner + (next - corner) * Double(i) / Double(pieces)
                turn.append(onSlope(seamDepth(s), s))
            }
            turn.append(lower[0])

            // A stripe's top is the seam, which bends a little with the wave,
            // so it is a shape too.
            fill(face[j % face.count])
            drawShape(Shape(outer: turn + [turn.last! + downLeft * far, turn[0] + downLeft * far], holes: []))
            fill(j < face.count ? face[j] : slope[(j - face.count) % slope.count])
            // A lane is concave wherever the wave turns, so it is a shape that
            // is triangulated, never a fan.
            drawShape(Shape(outer: upper + lower.reversed() + turn.reversed().dropFirst().dropLast(), holes: []))
            corner = next
            upper = lower
        }
    }

    /// A sun the panel keeps: the whole disc, or the part of it on the
    /// panel's side of an edge that cuts it, closed along that edge.
    private func drawSun(_ center: Vector2, _ radius: Double, _ left: Double, _ right: Double) {
        if center.x - radius >= left && center.x + radius <= right {
            drawCircle(center: center, radius: radius)
        } else if center.x + radius <= right {
            let a = acos(min(max((left - center.x) / radius, -1), 1))
            drawArc(Arc(center: center, radius: radius, start: -a, stop: a), mode: .chord)
        } else if center.x - radius >= left {
            let a = acos(min(max((right - center.x) / radius, -1), 1))
            drawArc(Arc(center: center, radius: radius, start: a, stop: 2 * .pi - a), mode: .chord)
        }
    }
}
