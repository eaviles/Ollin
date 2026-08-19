// figure: frame=0
//
// Guide diagram (Chapter 23): what a tempo clock counts. MIDI clock sends
// twenty-four ticks per beat and nothing else; everything musical is derived
// from counting them. The strip shows ticks, the beats they group into, the
// bar those beats fill, and which reader gives you what.
import Ollin

final class MusicalTime: Sketch {
    override var canvasSize: CanvasSize { .size(880, 396) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.4)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.16)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)

        let left = 70.0, right = 810.0
        let span = right - left
        let beats = 4
        let ticksPerBeat = 24
        let y = 118.0

        // The raw wire: one small mark per clock tick.
        noStroke()
        fill(faint)
        for t in 0 ... beats * ticksPerBeat {
            let x = left + span * Double(t) / Double(beats * ticksPerBeat)
            drawRect(x - 0.7, y - 12, 1.4, 24)
        }
        fill(soft)
        textSize(14)
        textAlign(.left, .bottom)
        drawText("24 ticks per beat, and that is all the wire carries", left, y - 24)

        // The beats those ticks group into.
        for b in 0 ... beats {
            let x = left + span * Double(b) / Double(beats)
            stroke(b == beats ? faint : ink)
            strokeWeight(b.isMultiple(of: beats) ? 3 : 2)
            drawLine(x, y - 20, x, y + 34)
            if b < beats {
                noStroke()
                fill(ink)
                textSize(15)
                textAlign(.center, .top)
                drawText("beat \(b)", x + span / Double(beats) / 2, y + 40)
            }
            noStroke()
        }

        // One bar, spanning the four beats.
        stroke(accent)
        strokeWeight(2)
        noFill()
        drawLine(left, y + 78, right, y + 78)
        drawLine(left, y + 72, left, y + 84)
        drawLine(right, y + 72, right, y + 84)
        noStroke()
        fill(accent)
        textSize(15)
        textAlign(.center, .top)
        drawText("one bar (beatsPerBar = 4)", (left + right) / 2, y + 88)

        // What each reader hands you.
        fill(ink)
        textSize(16)
        textAlign(.left, .top)
        let notes = [
            "clock.beats     2.5      beats since the transport started, fractional",
            "clock.phase     0.5      where you are inside the current beat",
            "clock.bar       0        which bar, counted in beatsPerBar",
            "clock.barPhase  0.625    where you are inside the bar",
            "clock.beat      a pulse that snaps to 1 on the beat and decays",
        ]
        for (i, note) in notes.enumerated() {
            drawText(note, left, y + 128 + Double(i) * 22)
        }

        // Mark the example position the readings describe.
        let markX = left + span * 2.5 / Double(beats)
        stroke(accent)
        strokeWeight(2)
        drawLine(markX, y - 26, markX, y + 40)
        noStroke()
        fill(accent)
        textSize(14)
        textAlign(.center, .bottom)
        drawText("here", markX, y - 30)
    }
}
