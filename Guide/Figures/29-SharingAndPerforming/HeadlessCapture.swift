// figure: frame=0
//
// Guide figure (Chapter 29): headless capture, demonstrating itself. This sketch
// renders another sketch four times through OllinApp.image(of:frame:), at four
// frames, and lays the results out as a strip. Nothing here opens a window, and
// the same call is what produced every image in this guide.
//
// HeadlessCapture is declared first on purpose: the sketch loader compiles the
// first `class …: Sketch` it finds in the file, so a helper sketch declared above
// it would be the one that runs.
import Ollin

final class HeadlessCapture: Sketch {
    override var canvasSize: CanvasSize { .size(880, 300) }

    override func setup() { noLoop() }

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let frames = [0, 30, 60, 90]
        let tile = 196.0, gap = 18.0
        let left = (width - tile * Double(frames.count) - gap * Double(frames.count - 1)) / 2

        textFont(.system)
        for (index, frame) in frames.enumerated() {
            let x = left + Double(index) * (tile + gap)
            // A fresh sketch per capture, so each render starts from setup().
            if let captured = OllinApp.image(of: Pulse(), frame: frame) {
                drawImage(Image(cgImage: captured),
                          in: Rectangle(x: x, y: 34, width: tile, height: tile))
            }
            noStroke()
            fill(Color(hex: 0x2B2B2B, alpha: 0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText("frame: \(frame)", x + tile / 2, 34 + tile + 9)
        }

        fill(Color(hex: 0x2B2B2B))
        textSize(19)
        textAlign(.center, .top)
        drawText("OllinApp.image(of: Pulse(), frame:), four renders, no window",
                 width / 2, 262)
    }
}

/// The sketch being captured: a small piece with obvious motion, so four frames
/// of it read as four different moments.
final class Pulse: Sketch {
    override var canvasSize: CanvasSize { .square(240) }

    override func setup() { seed(3) }

    override func draw() {
        background(Color(hex: 0x141821))
        noStroke()
        for index in 0 ..< 7 {
            let phase = time * 0.9 + Double(index) * 0.42
            let radius = 26 + sin(phase) * 17
            fill(Color(hue: 0.08 + Double(index) * 0.03, saturation: 0.72, brightness: 1,
                       alpha: 0.9))
            drawCircle(center: uv(0.5 + cos(phase * 0.6) * 0.3, 0.5 + sin(phase) * 0.28),
                       radius: radius)
        }
    }
}
