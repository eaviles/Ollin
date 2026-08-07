import Foundation
import Ollin
import OllinVision

/// A model reading *your drawing* — no camera anywhere: you sketch a digit on a
/// pixel-authored `Image` with the mouse, and a `ModelTracker` bound to no
/// frame source classifies it through the still `detect(in:)` path each time
/// the mouse lifts. Every other vision example points a model at the world;
/// this one points it at the canvas, which is the more creative-coding
/// direction — a sketch can read its *own* output. The weights aren't in the
/// repo — run `Scripts/fetch-models.sh` once and relaunch (the sketch says so
/// on the canvas until then).
///
/// Model: MNISTClassifier — Apple's Turi Create-trained handwritten-digit
/// classifier from the Core ML gallery (MIT) — downloaded by the fetch script,
/// never bundled. Provenance in THIRD-PARTY-NOTICES.md.
/// The fetched weights live in `Models/` at the repo root. This sketch runs both
/// from there (the gallery compiles it where it sits) and from `Examples/` (a
/// direct `swift run`), so the folder is found by walking up from this file
/// instead of trusting whatever the working directory happens to be.
private func modelsPath(_ name: String) -> String {
    var dir = (#filePath as NSString).deletingLastPathComponent
    while dir.count > 1 {
        let models = (dir as NSString).appendingPathComponent("Models")
        if FileManager.default.fileExists(atPath: models) {
            return (models as NSString).appendingPathComponent(name)
        }
        dir = (dir as NSString).deletingLastPathComponent
    }
    return ("Models" as NSString).appendingPathComponent(name)
}

@main
final class DigitReader: Sketch {
    static let modelPath = modelsPath("MNISTClassifier.mlmodel")

    lazy var reader = ModelTracker(modelAt: URL(fileURLWithPath: Self.modelPath))

    /// The drawing pad: white strokes on black, the form the model was trained
    /// on. A tenth of the displayed size is plenty — the model reads 28×28.
    var pad = Image(width: 280, height: 280, color: .black)

    /// Where the pen last touched the pad (in pad pixels), `nil` between strokes.
    var lastTouch: Vector2?

    /// What the model said about the current drawing, strongest first.
    var guesses: [Classification] = []

    /// Classifies in flight — at most one at a time; the mouse lifting again
    /// just queues the freshest drawing.
    var isReading = false

    var padRect: Rectangle {
        Rectangle(x: 70 * scale, y: 250 * scale, width: 560 * scale, height: 560 * scale)
    }

    override func draw() {
        background(Color(white: 0.04))

        guard FileManager.default.fileExists(atPath: Self.modelPath) else {
            return drawStatus("The digit model isn't downloaded yet.\n" +
                              "Run Scripts/fetch-models.sh, then relaunch.",
                              style: .warning)
        }
        if let reason = reader.unavailableReason {
            return drawStatus(reason, style: .warning)
        }

        paintWhileMouseIsDown()

        // The pad, with a thin frame.
        drawImage(pad, in: padRect)
        noFill()
        stroke(Color(white: 0.3))
        strokeWeight(2 * scale)
        drawRect(padRect)

        // Headline and hint.
        noStroke()
        fill(.white)
        textAlign(.left, .baseline)
        textSize(40 * scale)
        drawText("Draw a digit", padRect.x, padRect.y - 60 * scale)
        fill(Color(white: 0.55))
        textSize(19 * scale)
        drawText("big, in the box — any key clears", padRect.x, padRect.y - 24 * scale)

        drawGuesses()
        drawCaption("DigitReader — a model reading the sketch's own pixels")
    }

    /// While the button is down inside the pad, stamp the stroke into the
    /// image's pixels — `mouseIsPressed` is the held state, so drawing is just
    /// polling it every frame.
    private func paintWhileMouseIsDown() {
        guard mouseIsPressed,
              padRect.contains(Vector2(mouseX, mouseY)) else {
            lastTouch = nil
            return
        }
        let touch = Vector2((mouseX - padRect.x) / padRect.width * Double(pad.width),
                            (mouseY - padRect.y) / padRect.height * Double(pad.height))
        stamp(from: lastTouch ?? touch, to: touch)
        lastTouch = touch
    }

    /// A round pen dragged from `a` to `b`: disks stamped densely along the
    /// segment, written straight into the pad's pixel buffer.
    private func stamp(from a: Vector2, to b: Vector2) {
        let penRadius = 13.0
        let steps = max(1, Int((b - a).length / 2))
        for i in 0...steps {
            let p = a + (b - a) * (Double(i) / Double(steps))
            let r = Int(penRadius)
            for dy in -r...r {
                for dx in -r...r where dx * dx + dy * dy <= r * r {
                    pad[Int(p.x) + dx, Int(p.y) + dy] = .white
                }
            }
        }
    }

    /// The verdict: the strongest digit writ large, the full 0…9 confidence
    /// ladder beside it.
    private func drawGuesses() {
        let panelX = 700 * scale
        noStroke()

        if let top = guesses.first {
            fill(.white)
            textAlign(.center, .middle)
            textSize(230 * scale)
            drawText(top.label, panelX + 150 * scale, 360 * scale)
            fill(Color(white: 0.55))
            textSize(19 * scale)
            drawText("\(Int(top.confidence * 100))% sure", panelX + 150 * scale, 500 * scale)
        } else {
            fill(Color(white: 0.45))
            textAlign(.center, .middle)
            textSize(19 * scale)
            drawText("waiting for a drawing…", panelX + 150 * scale, 360 * scale)
        }

        // One thin row per digit, in digit order, so the ladder holds still
        // while the confidences move.
        let rowsTop = 560 * scale, rowHeight = 26 * scale, rowGap = 9 * scale
        let barX = panelX + 40 * scale, barWidth = 240 * scale
        textSize(16 * scale)
        for digit in 0...9 {
            let y = rowsTop + Double(digit) * (rowHeight + rowGap)
            let value = guesses.first { $0.label == "\(digit)" }?.confidence ?? 0

            fill(Color(white: 0.65))
            textAlign(.left, .middle)
            drawText("\(digit)", panelX, y + rowHeight / 2)

            fill(Color(white: 0.12))
            drawRect(barX, y, barWidth, rowHeight, cornerRadius: rowHeight / 2)
            if value > 0.005 {
                fill(Colormap.turbo.color(at: 0.15 + value * 0.7))
                drawRect(barX, y, max(rowHeight, value * barWidth), rowHeight,
                         cornerRadius: rowHeight / 2)
            }
        }
    }

    /// The mouse lifted — the stroke is finished, so hand the drawing to the
    /// model. A snapshot goes, not the pad itself: the model reads the drawing
    /// as it was at lift time while later strokes keep landing on the pad.
    override func mouseReleased() {
        lastTouch = nil
        guard !isReading, FileManager.default.fileExists(atPath: Self.modelPath) else { return }
        isReading = true
        let snapshot = pad.currentCGImage()
        Task { [weak self] in
            guard let self else { return }
            let output = try? await self.reader.detect(in: Image(cgImage: snapshot))
            self.guesses = output?.labels ?? []
            self.isReading = false
        }
    }

    /// Any key wipes the pad for the next digit.
    override func keyPressed() {
        pad = Image(width: 280, height: 280, color: .black)
        guesses = []
    }
}
