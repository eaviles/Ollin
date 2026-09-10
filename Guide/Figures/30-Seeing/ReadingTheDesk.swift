// figure: frame=0 themed unstable
//
// Unstable: the detections are live Vision requests, and the system's own
// models answer with slightly different boxes from run to run (two lossless
// back-to-back renders moved; the same cause as the other ML-driven figures).
//
// Guide diagram (Chapter 30): two classical detectors reading a real desk.
// Left: a bundled photograph, a laptop, a cup, a plant and a notebook seen
// from above. Right: the quads RectangleDetector found, each with its four
// corners in perspective, and the boxes TextRecognizer put around the lines it
// read off the notebook's cover. Both captions are written from what came
// back, so the figure states its own result rather than a remembered one.
import Ollin
import OllinDiagram
import OllinSamplePhotos
import OllinVision

final class ReadingTheDesk: Sketch {
    override var canvasSize: CanvasSize { .size(880, 580) }

    var scene: Image?
    var quads: [[Vector2]] = []
    var lines: [(text: String, box: Rectangle)] = []

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var soft: Color { theme.ink(0.6) }
    var accent: Color { theme.accent }

    let leftPanel = Rectangle(x: 60, y: 100, width: 360, height: 360)
    let rightPanel = Rectangle(x: 460, y: 100, width: 360, height: 360)

    override func setup() {
        let picture = SamplePhoto.desk.load()
        scene = picture

        // One detector finds the flat things, the other reads what is printed
        // on them. Small print wants the slower reading; the first accurate
        // pass on a Mac prepares the system's reader and can take the better
        // part of a minute, so a cold machine renders this figure slowly.
        let found = (try? waitFor(picture) { try await RectangleDetector.detect(in: $0) }) ?? []
        quads = found.map { $0.corners(in: rightPanel) }

        let read = (try? waitFor(picture) {
            try await TextRecognizer.detect(in: $0, quality: .accurate)
        }) ?? []
        lines = read
            .map { ($0.text, $0.bounds(in: rightPanel)) }
            .sorted { $0.box.y < $1.box.y }
    }

    override func draw() {
        background(paper)
        textFont(.systemMedium)
        textSize(19)

        if let scene {
            drawImage(scene, in: leftPanel)
            drawImage(scene, in: rightPanel)
        }

        // Each quad in the perspective the detector reported, corners and all.
        noFill()
        stroke(accent)
        strokeWeight(2)
        for quad in quads { drawPolygon(quad) }
        noStroke()
        fill(accent)
        for quad in quads {
            for corner in quad { drawCircle(center: corner, radius: 3.5) }
        }

        // A box around each line of text it read.
        noFill()
        stroke(ink.withAlpha(0.75))
        strokeWeight(1.5)
        for line in lines { drawRect(line.box) }

        stroke(faint)
        strokeWeight(1.5)
        drawRect(leftPanel)
        drawRect(rightPanel)

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("a desk, seen from above", leftPanel.center.x, 472)
        drawText(counted(), rightPanel.center.x, 472)
        fill(soft)
        textSize(16)
        drawText(readBack(), width / 2, 508)
        textSize(19)
        drawText("one detector found the flat things, another read the words printed on them",
                 width / 2, 540)
    }

    /// The right-hand label, counting what the two requests actually returned.
    private func counted() -> String {
        "\(quads.count) rectangles, \(lines.count) lines of type"
    }

    /// The words themselves, so the figure cannot claim a reading it did not get.
    private func readBack() -> String {
        guard !lines.isEmpty else { return "nothing read" }
        return lines.map { "\"\($0.text)\"" }.joined(separator: "   ")
    }
}
