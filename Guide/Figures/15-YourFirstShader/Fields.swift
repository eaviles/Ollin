// figure: frame=0
//
// Guide figure (Chapter 15): two of the built-in pattern fields, each a
// closed-form shader like the ones this chapter writes: a quasicrystal wave
// sum and a gyroid slice.
import Ollin

final class Fields: Sketch {
    override var canvasSize: CanvasSize { .size(880, 470) }

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let w = 405, h = 380
        drawImage(generate(.quasicrystal(phase: 2.0), width: w, height: h).image,
                  in: Rectangle(x: 22, y: 20, width: Double(w), height: Double(h)))
        drawImage(generate(.gyroid(phase: 1.2), width: w, height: h).image,
                  in: Rectangle(x: 453, y: 20, width: Double(w), height: Double(h)))

        noStroke()
        fill(Color(hex: 0x2B2B2B, alpha: 0.6))
        textSize(16)
        textAlign(.center, .top)
        drawText(".quasicrystal(phase: time)", 22 + Double(w) / 2, 412)
        drawText(".gyroid(phase: time)", 453 + Double(w) / 2, 412)
    }
}
