import Ollin
import OllinSamplePhotos
import OllinVision

/// Text, read out of the live feed. A `TextRecognizer` runs Apple's OCR — the
/// same engine behind Live Text — and returns each line with its position and
/// what it says. The sketch boxes each line and prints the recognized text above
/// it. Point the camera at a sign, a label, a book, or a screen.
///
/// `quality` is the dial that matters. `.fast` keeps up with a camera and reads
/// what a camera is usually pointed at, which is large type held close.
/// `.accurate` reads small print, which is what the bundled photograph has: a
/// book held open with shadow falling across it, sixty lines of it. Once warm
/// it costs about 140 ms a frame here, but the *first* accurate pass on a Mac
/// prepares the system's reader and can take the better part of a minute, so
/// the first run of this sketch sits empty for a while and every run after it
/// is quick.
///
/// Half the page is in shadow and the reader still gets it, which is worth
/// knowing before you reach for a threshold: the recognizer does its own work
/// on contrast and does not want the picture cleaned up first.
@main
final class TextScan: Sketch {
    // A camera where this Mac has one, and a bundled photograph where it does
    // not, so there is always print to read. `--photo` takes the picture even
    // where a camera would have worked, which is how a still of this sketch is made.
    let feed = Camera.orStill(SamplePhoto.page.load())
    // Small print needs the slower reading. A live camera pointed at a sign
    // reads fine at `.fast`, which is the default.
    lazy var reader = TextRecognizer(feed, quality: .accurate)

    override func draw() {
        background(Color(white: 0.06))

        guard let rect = drawFrame(feed) else { return }

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
        drawCaption(n == 0
            ? "TextScan: nothing read yet; the first accurate pass prepares the system reader"
            : "TextScan: \(n) line\(n == 1 ? "" : "s") read")
    }
}
