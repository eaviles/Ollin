// figure: frame=0
//
// Guide diagram (Chapter 28): what a scale does to numbers, and what chords
// are made of. Left: A minor pentatonic as a ladder over the semitone grid;
// a wandering whole-number sequence fed through key[step] can only ever land
// on rungs. Right: triads built from C major by taking every other rung, the
// quality (major, minor, diminished) following from the degree you start on.
import Ollin
import OllinAudio

final class ScaleLadder: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)
    let cool = Color(hex: 0x17A398)

    override func draw() {
        background(paper)

        let left = Rectangle(x: 70, y: 66, width: 330, height: 300)
        let right = Rectangle(x: 480, y: 66, width: 330, height: 300)

        drawLadder(in: left)
        drawChords(in: right)

        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText("a wandering number cannot leave the key", left.x, left.y - 18)
        drawText("every other rung makes the chords", right.x, right.y - 18)

        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("the ladder decides which notes exist; where you stand on it decides the chord",
                 width / 2, 402)
    }

    func drawLadder(in panel: Rectangle) {
        let key = Scale(.minorPentatonic, root: "A3")
        let wander = [0, 1, 3, 2, 4, 6, 5, 7, 8, 6, 9, 8]
        let lo = key[0].midi - 3, hi = key[9].midi + 3

        func y(_ midi: Double) -> Double {
            panel.y + panel.height - (midi - lo) / (hi - lo) * panel.height
        }

        // Every semitone as a faint line, every scale note as a solid rung.
        stroke(soft)
        strokeWeight(1)
        for m in stride(from: lo, through: hi, by: 1) {
            drawLine(panel.x, y(m), panel.x + panel.width, y(m))
        }
        stroke(ink.withAlpha(0.55))
        strokeWeight(2)
        for degree in 0 ... 9 {
            drawLine(panel.x, y(key[degree].midi), panel.x + panel.width, y(key[degree].midi))
        }

        // The wandering sequence, landing only on rungs.
        let xs = wander.indices.map { panel.x + 24 + Double($0) / Double(wander.count - 1) * (panel.width - 48) }
        noFill()
        stroke(accent.withAlpha(0.5))
        strokeWeight(1.6)
        drawPolyline(zip(xs, wander).map { Vector2($0, y(key[$1].midi)) }, closed: false)
        noStroke()
        for (x, w) in zip(xs, wander) {
            fill(accent)
            drawCircle(x, y(key[w].midi), 7)
            fill(paper)
            textSize(9)
            textAlign(.center, .middle)
            drawText("\(w)", x, y(key[w].midi))
        }
    }

    func drawChords(in panel: Rectangle) {
        let key = Scale(.major, root: "C3")
        let lo = key[0].midi - 1, hi = key[10].midi + 2

        func y(_ midi: Double) -> Double {
            panel.y + panel.height - (midi - lo) / (hi - lo) * panel.height
        }

        stroke(soft)
        strokeWeight(1)
        for degree in 0 ... 10 {
            drawLine(panel.x, y(key[degree].midi), panel.x + panel.width, y(key[degree].midi))
        }

        let names = ["I", "ii", "iii", "IV", "V", "vi", "vii°"]
        let cell = panel.width / 7
        for degree in 0 ..< 7 {
            let notes = key.chord(on: degree)
            let third = notes[1].midi - notes[0].midi
            let fifth = notes[2].midi - notes[0].midi
            let tone = fifth < 6.5 ? ink.withAlpha(0.45)      // diminished
                     : third > 3.5 ? accent                    // major third
                     : cool                                    // minor third
            let x = panel.x + (Double(degree) + 0.5) * cell
            noStroke()
            for note in notes {
                fill(tone)
                drawRect(center: Vector2(x, y(note.midi)), width: cell * 0.62, height: 9)
            }
            fill(ink)
            textSize(13)
            textAlign(.center, .top)
            drawText(names[degree], x, panel.y + panel.height + 8)
        }
    }
}
