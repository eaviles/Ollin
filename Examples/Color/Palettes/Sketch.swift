import Ollin

/// A cosine-gradient `Palette` swept across the canvas as vertical bars, the
/// whole gradient scrolling over time. The top band uses Ollin's built-in
/// `.rainbow`; the bottom uses a custom `Palette` built from four `(r, g, b)`
/// coefficients — the same formula, retuned to a warmer cycle.
@main
final class Palettes: Sketch {
    let warm = Palette(a: (0.5, 0.5, 0.5),
                       b: (0.5, 0.5, 0.5),
                       c: (1.0, 1.0, 1.0),
                       d: (0.0, 0.10, 0.20))

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        let bars = 120
        let barWidth = width / Double(bars)
        for i in 0..<bars {
            let t = Double(i) / Double(bars) + time * 0.1
            let x = Double(i) * barWidth
            fill(Palette.rainbow.color(at: t))
            rect(x: x, y: 0, width: barWidth + 1, height: height / 2)
            fill(warm.color(at: t))
            rect(x: x, y: height / 2, width: barWidth + 1, height: height / 2)
        }
    }
}
