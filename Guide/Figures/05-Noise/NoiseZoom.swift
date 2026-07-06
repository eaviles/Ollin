// figure: frame=0
//
// Guide diagram: the multiplier on noise's input is a zoom knob. Three panels
// sample the same field with steps of three different sizes: tiny steps read
// one hillside, bigger steps cross whole hills, big steps skim a mountain
// range's worth of terrain into the same frame.
import Ollin

final class NoiseZoom: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func setup() {
        noiseSeed(6)
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)

        drawPanel(x: 70, multiplier: 0.004, note: "gentle")
        drawPanel(x: 340, multiplier: 0.015, note: "rolling")
        drawPanel(x: 610, multiplier: 0.06, note: "busy")

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("the same field, walked with three step sizes", width / 2, 440)
    }

    func drawPanel(x: Double, multiplier: Double, note: String) {
        let size = 200.0
        let top = 110.0, bottom = top + size

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(x, top, size, size)

        var points: [Vector2] = []
        for i in 0...200 {
            let n = noise(Double(i) * size / 200 * multiplier)
            points.append(Vector2(x + Double(i), bottom - n * size))
        }
        stroke(accent)
        strokeWeight(3)
        drawPolyline(points)

        noStroke()
        fill(ink)
        textAlign(.center, .bottom)
        drawText("noise(x * \(multiplier))", x + size / 2, top - 40)
        fill(Color(hex: 0x2B2B2B, alpha: 0.6))
        drawText(note, x + size / 2, top - 14)
    }
}
