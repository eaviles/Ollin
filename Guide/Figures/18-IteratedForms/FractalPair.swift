// figure: frame=0
//
// Guide figure (Chapter 18): escape-time fractals. The whole Mandelbrot set with
// one c marked, the Julia set that same c produces, and a deep zoom into the
// Mandelbrot boundary with the iteration cap raised to match. The same loop runs
// in all three; only what is held fixed changes.
import Ollin

final class FractalPair: Sketch {
    override var canvasSize: CanvasSize { .size(880, 386) }

    /// The c whose Julia set the middle panel shows, marked in the first panel.
    let pick = Vector2(-0.79, 0.15)

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let tile = 268, gap = 12.0
        let left = (width - Double(tile) * 3 - gap * 2) / 2
        let mandelCenter = Vector2(-0.6, 0)

        let panels: [(String, Generator)] = [
            ("z = z² + c, one c per pixel",
             .mandelbrot(center: mandelCenter, zoom: 1, phase: 0.4)),
            ("the same loop, c held at the mark",
             .julia(c: pick, zoom: 1.2, phase: 0.4)),
            ("zoom 900, iterations 400",
             .mandelbrot(center: Vector2(-0.7463, 0.1102), zoom: 900,
                         iterations: 400, phase: 0.4)),
        ]

        textFont(.system)
        for (index, panel) in panels.enumerated() {
            let x = left + Double(index) * (Double(tile) + gap)
            let rect = Rectangle(x: x, y: 20, width: Double(tile), height: Double(tile))
            drawImage(generate(panel.1, width: tile, height: tile).image, in: rect)

            // The marker on the first panel. Zoom 1 shows about 3 units of the
            // complex plane across the tile, and the plane's y runs up while the
            // canvas runs down.
            if index == 0 {
                let span = 3.0
                let mark = Vector2(
                    rect.x + rect.width / 2 + (pick.x - mandelCenter.x) / span * rect.width,
                    rect.y + rect.height / 2 - (pick.y - mandelCenter.y) / span * rect.height)
                noFill()
                stroke(Color(hex: 0xF25F5C))
                strokeWeight(2.5)
                drawCircle(center: mark, radius: 9)
            }

            noStroke()
            fill(Color(hex: 0x2B2B2B, alpha: 0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(panel.0, rect.x + rect.width / 2, rect.y + rect.height + 8)
        }
    }
}
