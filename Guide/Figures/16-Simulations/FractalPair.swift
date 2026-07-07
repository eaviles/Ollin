// figure: frame=0
//
// Guide figure (Chapter 16): iteration without memory. The Mandelbrot set
// and a Julia set, each pixel running its whole z = z^2 + c orbit inside a
// single frame.
import Ollin

final class FractalPair: Sketch {
    override var canvasSize: CanvasSize { .size(880, 470) }

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let w = 405, h = 380
        drawImage(generate(.mandelbrot(phase: 0.15), width: w, height: h).image,
                  in: Rectangle(x: 22, y: 20, width: Double(w), height: Double(h)))
        drawImage(generate(.julia(c: Vector2(-0.79, 0.15), phase: 0.55), width: w, height: h).image,
                  in: Rectangle(x: 453, y: 20, width: Double(w), height: Double(h)))

        noStroke()
        fill(Color(hex: 0x2B2B2B, alpha: 0.6))
        textSize(16)
        textAlign(.center, .top)
        drawText(".mandelbrot(...)", 22 + Double(w) / 2, 412)
        drawText(".julia(c: Vector2(-0.79, 0.15))", 453 + Double(w) / 2, 412)
    }
}
