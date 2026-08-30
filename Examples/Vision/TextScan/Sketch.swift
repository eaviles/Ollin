import Ollin
import OllinVision

/// Text, read out of the live feed. A `TextRecognizer` runs Apple's OCR — the
/// same engine behind Live Text — and returns each line with its position and
/// what it says. The sketch boxes each line and prints the recognized text above
/// it. Point the camera at a sign, a label, a book, or a screen.
@main
final class TextScan: Sketch {
    let camera = Camera()
    lazy var reader = TextRecognizer(camera, quality: .fast)

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.06))

        guard let rect = drawFrame(camera) else { return }

        let accent = Color(red: 0.5, green: 0.85, blue: 1.0)
        let lines = reader.lines
        for line in lines {
            let box = line.bounds(in: rect)

            // The line's box.
            noFill()
            stroke(accent)
            strokeWeight(2 * scale)
            drawRect(box)

            // The recognized text, just above the box.
            fill(accent)
            noStroke()
            textAlign(.left, .bottom)
            textSize(16 * scale)
            drawText(line.text, box.x, box.y - 6 * scale)
        }

        let n = lines.count
        drawCaption("TextScan — \(n) line\(n == 1 ? "" : "s")")
    }
}
