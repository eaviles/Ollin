// figure: frame=0 themed
//
// Guide diagram (Chapter 29): the same four numerals in two keys. Each chord
// is drawn as the notes a Progression actually hands back, stacked at their
// own pitches, so the point is visible rather than asserted: I vi IV V comes
// out major in a major key and minor in a minor one, with nothing changed.
import Ollin
import OllinDiagram
import OllinAudio

final class Changes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.16) }
    var accent: Color { theme.accent }

    let numerals = ["I", "vi", "IV", "V"]

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        row(Progression("I vi IV V", in: Scale(.major, root: "C3")),
            title: "C major", top: 92)
        row(Progression("I vi IV V", in: Scale(.minor, root: "C3")),
            title: "C minor", top: 300)

        noStroke()
        fill(ink)
        textSize(20)
        textAlign(.center, .top)
        drawText("the numerals stay put, and the key decides what they mean", width / 2, 498)
    }

    /// What a stack of three notes is called, worked out from the gaps between
    /// them rather than from anything the progression was told.
    func name(of pitches: [Pitch]) -> String {
        let sorted = pitches.sorted()
        guard sorted.count >= 3 else { return "" }
        let root = String(sorted[0].description.dropLast())
        let third = Int((sorted[1].midi - sorted[0].midi).rounded())
        let fifth = Int((sorted[2].midi - sorted[1].midi).rounded())
        switch (third, fifth) {
        case (4, 3): return root + " major"
        case (3, 4): return root + " minor"
        case (3, 3): return root + " diminished"
        default:     return root
        }
    }

    /// One progression drawn as four stacks of the notes it hands back.
    func row(_ changes: Progression, title: String, top: Double) {
        let lane = 168.0, left = 128.0, unit = 7.0
        let base = top + 175

        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.right, .middle)
        drawText(title, 108, top + 96)

        for i in 0 ..< 4 {
            let x = left + Double(i) * lane
            let pitches = changes.pitches(at: i)
            guard let lowest = pitches.min(), let highest = pitches.max() else { continue }

            // The stack itself: a spine through the chord, a dot at each note.
            stroke(faint)
            strokeWeight(2)
            drawLine(x, base - (lowest.midi - 48) * unit, x, base - (highest.midi - 48) * unit)
            noStroke()
            for p in pitches {
                let y = base - (p.midi - 48) * unit
                fill(accent)
                drawCircle(x, y, 7)
                fill(ink)
                textSize(14)
                textAlign(.left, .middle)
                drawText(p.description, x + 14, y)
            }

            // What it is called, and what the sketch asked for.
            fill(ink)
            textSize(22)
            textAlign(.center, .top)
            drawText(numerals[i], x, top + 4)
            textSize(15)
            fill(ink.withAlpha(0.62))
            drawText(name(of: pitches), x, top + 30)
        }
    }
}
