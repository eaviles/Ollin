// figure: frame=0 themed
//
// Guide diagram (Chapter 37): the pitch primer. Two octaves of a keyboard,
// C3 to C5, every key carrying its MIDI number, with the octave from C3 to
// C4 bracketed as twelve semitones. Under it, four rows lined up with the
// keys: C major from C4 and A minor pentatonic from A3 as dots numbered by
// degree, with the semitones between neighbors written between them; then a
// C major triad and an A minor triad, their two steps and the fifth they
// span. Every dot is read off Scale and Chord, so the rows are what the
// types hand back.
import Ollin
import OllinDiagram
import OllinAudio

final class Keyboard: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let low = 48                 // C3
    let high = 72                // C5
    let left = 190.0
    let keyTop = 62.0
    let whiteWidth = 44.0
    let whiteHeight = 116.0
    let blackWidth = 26.0
    let blackHeight = 72.0
    let whiteClasses = [0, 2, 4, 5, 7, 9, 11]

    func isWhite(_ midi: Int) -> Bool { whiteClasses.contains(((midi % 12) + 12) % 12) }

    /// How many white keys lie left of this one, counted from C3.
    func whiteIndex(_ midi: Int) -> Int {
        (low ..< midi).filter { isWhite($0) }.count
    }

    /// The middle of a key, left to right.
    func keyX(_ midi: Int) -> Double {
        isWhite(midi)
            ? left + (Double(whiteIndex(midi)) + 0.5) * whiteWidth
            : left + Double(whiteIndex(midi)) * whiteWidth
    }

    override func draw() {
        background(theme.paper)
        drawKeyboard()

        let major = Scale(.major, root: "C4")
        let pentatonic = Scale(.minorPentatonic, root: "A3")
        drawRow("C major, from C4", (0 ... 7).map { major[$0] }, y: 232,
                color: theme.accent, labels: (0 ... 7).map { "\($0)" })
        drawRow("A minor pentatonic, from A3", (0 ... 5).map { pentatonic[$0] }, y: 300,
                color: theme.accent, labels: (0 ... 5).map { "\($0)" })

        let bright = Chord("C4", .major).pitches
        let dark = Chord("A3", .minor).pitches
        drawRow("C major triad", bright, y: 368, color: theme.accent,
                labels: bright.map { "\($0)" }, fifth: true)
        drawRow("A minor triad", dark, y: 446, color: theme.ink(0.8),
                labels: dark.map { "\($0)" }, fifth: true)

        diagramCaption("a scale is a pattern of steps; a triad takes every other note of one",
                       at: 510, theme: theme)
    }

    func drawKeyboard() {
        // White keys first, then the black keys over them.
        stroke(theme.ink(0.7))
        strokeWeight(1.5)
        for midi in low ... high where isWhite(midi) {
            fill(theme.paper)
            drawRect(keyX(midi) - whiteWidth / 2, keyTop, whiteWidth, whiteHeight)
        }
        for midi in low ... high where !isWhite(midi) {
            fill(theme.ink(0.85))
            drawRect(keyX(midi) - blackWidth / 2, keyTop, blackWidth, blackHeight)
        }

        // Each key's MIDI number, and the white keys' names under them.
        noStroke()
        textAlign(.center, .middle)
        for midi in low ... high {
            if isWhite(midi) {
                fill(theme.muted)
                textSize(12)
                drawText("\(midi)", keyX(midi), keyTop + whiteHeight - 14)
                fill(theme.ink)
                textSize(13)
                drawText("\(Pitch(Double(midi)))", keyX(midi), keyTop + whiteHeight + 14)
            } else {
                fill(theme.paper)
                textSize(10)
                drawText("\(midi)", keyX(midi), keyTop + blackHeight - 11)
            }
        }

        // The octave from C3 to C4, bracketed above the keys.
        let from = keyX(low) - whiteWidth / 2
        let to = keyX(low + 12) - whiteWidth / 2
        stroke(theme.accent)
        strokeWeight(2)
        drawLine(from, keyTop - 12, to, keyTop - 12)
        drawLine(from, keyTop - 18, from, keyTop - 6)
        drawLine(to, keyTop - 18, to, keyTop - 6)
        noStroke()
        fill(theme.accent)
        textSize(15)
        textAlign(.center, .bottom)
        drawText("an octave: twelve semitones, C3 (48) to C4 (60)", (from + to) / 2, keyTop - 20)

        fill(theme.ink)
        textSize(15)
        textAlign(.left, .middle)
        drawText("each key is one", 40, keyTop + 34)
        drawText("semitone above", 40, keyTop + 54)
        drawText("the key to its left", 40, keyTop + 74)
    }

    /// A row of dots lined up with their keys, each labeled, with the
    /// semitones between neighbors written between them.
    func drawRow(_ title: String, _ pitches: [Pitch], y: Double, color: Color,
                 labels: [String], fifth: Bool = false) {
        noStroke()
        fill(theme.ink)
        textSize(15)
        textAlign(.left, .middle)
        drawText(title, 40, y)

        let xs = pitches.map { keyX(Int($0.midi.rounded())) }
        stroke(color.withAlpha(0.45))
        strokeWeight(2)
        for i in 1 ..< xs.count {
            drawLine(xs[i - 1], y, xs[i], y)
        }

        noStroke()
        for (i, x) in xs.enumerated() {
            fill(color)
            drawCircle(x, y, 14)
            fill(theme.paper)
            textSize(labels[i].count > 1 ? 11 : 13)
            textAlign(.center, .middle)
            drawText(labels[i], x, y)
        }

        // The steps between neighbors, in semitones.
        fill(theme.muted)
        textSize(13)
        textAlign(.center, .top)
        for i in 1 ..< pitches.count {
            let step = Int((pitches[i].midi - pitches[i - 1].midi).rounded())
            drawText("\(step)", (xs[i - 1] + xs[i]) / 2, y + 8)
        }

        // Root to fifth, bracketed under the triad.
        if fifth, let first = xs.first, let last = xs.last {
            let span = Int((pitches[pitches.count - 1].midi - pitches[0].midi).rounded())
            stroke(theme.ink(0.5))
            strokeWeight(1.5)
            drawLine(first, y + 34, last, y + 34)
            drawLine(first, y + 28, first, y + 40)
            drawLine(last, y + 28, last, y + 40)
            noStroke()
            fill(theme.ink)
            textSize(13)
            textAlign(.left, .middle)
            drawText("\(span) semitones: a fifth", last + 14, y + 34)
        }
    }
}
