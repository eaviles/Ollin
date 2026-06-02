import Foundation
import Ollin

/// The full easing catalog at a glance: all thirty named `Easing` curves plotted
/// in a grid, each with a dot riding its shape as a shared phase sweeps `0→1→0`,
/// back and forth. The back, elastic, and bounce rows visibly overshoot their
/// cells — that's the point of them.
///
/// Each curve is sampled into a polyline (`x = u`, `y = curve(u)`), so the plot
/// is the curve itself; the dot sits on it at the current phase.
@main
final class EasingGallery: Sketch {
    let curves: [Easing] = [
        .easeInSine, .easeOutSine, .easeInOutSine,
        .easeInQuad, .easeOutQuad, .easeInOutQuad,
        .easeInCubic, .easeOutCubic, .easeInOutCubic,
        .easeInQuart, .easeOutQuart, .easeInOutQuart,
        .easeInQuint, .easeOutQuint, .easeInOutQuint,
        .easeInExpo, .easeOutExpo, .easeInOutExpo,
        .easeInCirc, .easeOutCirc, .easeInOutCirc,
        .easeInBack, .easeOutBack, .easeInOutBack,
        .easeInElastic, .easeOutElastic, .easeInOutElastic,
        .easeInBounce, .easeOutBounce, .easeInOutBounce,
    ]

    override func draw() {
        background(Color(white: 0.08))

        let cols = 6, rows = 5
        let margin = width * 0.045
        let cellW = (width - margin * 2) / Double(cols)
        let cellH = (height - margin * 2) / Double(rows)
        let inset = cellW * 0.18
        // Ping-pong 0→1→0 (triangle wave) so the dot rides each curve forward,
        // then back, instead of snapping to the start.
        let sweep = (time * 0.45).truncatingRemainder(dividingBy: 2)    // 0...2
        let phase = sweep < 1 ? sweep : 2 - sweep                       // 0→1→0

        for (i, curve) in curves.enumerated() {
            let col = i % cols, row = i / cols
            let ox = margin + Double(col) * cellW
            let oy = margin + Double(row) * cellH
            let x0 = ox + inset
            let baseline = oy + cellH - inset          // curve == 0 sits here
            let plotW = cellW - inset * 2
            let plotH = cellH - inset * 2

            func point(_ u: Double) -> Vector2 {
                Vector2(x0 + u * plotW, baseline - curve(u) * plotH)
            }

            let tint = Colormap.turbo.color(at: Double(i) / Double(curves.count - 1))

            // Faint frame and the 0/1 guide lines.
            stroke(Color(white: 0.18)); strokeWeight(1.5 * scale); noFill()
            drawLine(x0, baseline, x0 + plotW, baseline)
            drawLine(x0, baseline - plotH, x0 + plotW, baseline - plotH)

            // The curve.
            noFill(); stroke(tint); strokeWeight(3 * scale)
            drawPolyline((0...48).map { point(Double($0) / 48) })

            // The dot riding it at the current phase.
            noStroke(); fill(tint)
            drawCircle(center: point(phase), radius: 8 * scale)
        }
    }
}
