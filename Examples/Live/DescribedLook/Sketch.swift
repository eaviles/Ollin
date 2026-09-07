import Foundation
import Ollin
import OllinAssist

// DescribedLook: a look asked for in words. Type a phrase over the picture
// ("warmer", "fewer rings", "as big as it goes", "a dark paper") and press
// Return. The sketch hands its own parameters and your words to this Mac's
// language model, and the parameters the words concern move; the line at the
// bottom says which. Delete takes a letter back, Escape clears the phrase, and
// ⌘Z puts the last move back.
//
// The same field lives in the live host's inspector and the gallery's sidebar,
// above the save button. This is the sketch-side form of that row, one call:
// `tuneParameters(toward:)`. It needs Apple Intelligence on; when it is off,
// the caption says so and the picture still runs.
//
//   swift run Example-Live-DescribedLook

final class DescribedLook: Sketch {
    @Param(20...480) var radius = 220.0
    @Param(1...24, group: "Layout") var rings = 8
    @Param(1...16, group: "Layout") var weight = 3.0
    @Param(0.1...4) var speed = 1.0
    @Param var tint: Color = Color(red: 0.5, green: 0.1, blue: 0.9)
    @Param var paper: Color = Color(red: 0.98, green: 0.97, blue: 0.94)
    @Param var filled = false

    /// The words typed so far, what the last ask said, and its way back.
    private var phrase = ""
    private var caption = ""
    private var lastTuning: Tuning?
    private var isAsking = false

    override func setup() {
        if case .unavailable(let reason) = ParameterTuner.availability {
            caption = reason
        } else {
            caption = "Type a look and press Return."
        }
    }

    override func draw() {
        background(paper)
        let center = Vector2(width / 2, height / 2 - 40)
        let ink = Color(red: tint.red, green: tint.green, blue: tint.blue, alpha: filled ? 0.18 : 1)
        for i in 0..<rings {
            let fraction = Double(i + 1) / Double(rings)
            let breath = sin(time * speed + fraction * 3) * radius * 0.06
            withState {
                if filled {
                    noStroke()
                    fill(ink)
                } else {
                    noFill()
                    stroke(ink)
                    strokeWeight(weight)
                }
                drawCircle(center: center, radius: radius * fraction + breath)
            }
        }

        // The phrase being typed, and the last answer under it.
        textFont(.system)
        let field = phrase.isEmpty ? (isAsking ? "asking…" : "type a look") : phrase + (frameCount / 30 % 2 == 0 ? "|" : "")
        drawText(field, width / 2, height - 130, size: 30,
                 color: Color(red: tint.red, green: tint.green, blue: tint.blue, alpha: phrase.isEmpty ? 0.45 : 1),
                 align: .center, .middle)
        drawText(caption, width / 2, height - 72, size: 17,
                 color: Color(red: 0.35, green: 0.33, blue: 0.3), align: .center, .middle)
    }

    override func keyPressed() {
        guard !isAsking else { return }
        if let keyCode {
            switch keyCode {
            case .return, .enter: ask()
            case .delete: _ = phrase.popLast()
            case .escape: phrase = ""
            default: break
            }
            return
        }
        guard let key else { return }
        if modifiers.contains(.command) {
            if key == "z", let tuning = lastTuning {
                tuning.revert()
                lastTuning = nil
                caption = "Put back where they were."
            }
            return
        }
        phrase.append(key)
    }

    /// Hand the phrase over. The wait is the model's; the picture keeps moving.
    private func ask() {
        let words = phrase.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return }
        isAsking = true
        caption = "asking…"
        Task { @MainActor in
            do {
                let tuning = try await tuneParameters(toward: words)
                lastTuning = tuning.moves.isEmpty ? nil : tuning
                caption = tuning.summary
            } catch {
                caption = error.localizedDescription
            }
            phrase = ""
            isAsking = false
        }
    }
}
