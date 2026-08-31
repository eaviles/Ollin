// figure: frame=0 probe themed
//
// Guide diagram (Chapter 28): what a network tempo session shares. Every
// participant keeps its own running beat count, so the whole numbers differ,
// but all of them sit at the same place inside the bar. The phase is the
// shared thing; the downbeat lands together.
import Ollin
import OllinDiagram

final class SharedDownbeat: Sketch {
    override var canvasSize: CanvasSize { .size(880, 420) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.4) }
    var faint: Color { theme.ink(0.16) }
    var accent: Color { theme.accent }

    override func draw() {
        background(paper)

        // Three participants, each with its own beat count. The fraction is
        // the same on every machine; the whole part is each one's own.
        let names = ["the DAW", "a phone app", "your sketch"]
        let counts = ["1042.62", "88.62", "6.62"]
        let cardWidth = 218.0, cardHeight = 96.0, gap = 42.0
        let rowWidth = cardWidth * 3 + gap * 2
        let left = (880 - rowWidth) / 2
        let top = 64.0

        fill(soft)
        noStroke()
        textSize(14)
        textAlign(.left, .bottom)
        drawText("one session on the network: each machine counts its own beats", left, top - 16)

        for (i, name) in names.enumerated() {
            let x = left + Double(i) * (cardWidth + gap)
            stroke(faint)
            strokeWeight(1.5)
            noFill()
            drawRect(x, top, cardWidth, cardHeight, cornerRadius: 10)
            noStroke()
            fill(ink)
            textSize(16)
            textAlign(.center, .top)
            drawText(name, x + cardWidth / 2, top + 14)
            // The whole part is the machine's own; the fraction is shared, so
            // the two halves hang off one pivot and the fraction is accented.
            let value = counts[i]
            let dot = value.firstIndex(of: ".")!
            let pivot = x + cardWidth - 64
            textSize(20)
            fill(soft)
            textAlign(.left, .top)
            drawText("beats", x + 22, top + 48)
            fill(ink)
            textAlign(.right, .top)
            drawText(String(value[..<dot]), pivot, top + 48)
            fill(accent)
            textAlign(.left, .top)
            drawText(String(value[dot...]), pivot, top + 48)
        }

        // Lines from all three onto the one shared playhead below.
        let barTop = 250.0
        let barLeftEdge = 120.0, barRightEdge = 760.0
        let playheadX = barLeftEdge + (barRightEdge - barLeftEdge) * (2.0 + 0.62) / 4
        stroke(faint)
        strokeWeight(1.5)
        for i in 0 ..< 3 {
            let x = left + Double(i) * (cardWidth + gap) + cardWidth / 2
            drawLine(x, top + cardHeight + 10, playheadX, barTop - 44)
        }
        noStroke()

        // The shared bar: four beats of quantum, one playhead for everyone.
        let barLeft = 120.0, barRight = 760.0
        let span = barRight - barLeft
        let y = barTop
        for b in 0 ... 4 {
            let x = barLeft + span * Double(b) / 4
            stroke(b == 0 || b == 4 ? accent : ink)
            strokeWeight(b == 0 || b == 4 ? 3 : 2)
            drawLine(x, y, x, y + 44)
            noStroke()
            fill(soft)
            textSize(13)
            textAlign(.center, .top)
            if b < 4 { drawText("beat \(b)", barLeft + span * (Double(b) + 0.5) / 4, y + 52) }
        }
        stroke(faint)
        strokeWeight(1.5)
        drawLine(barLeft, y + 22, barRight, y + 22)
        noStroke()

        // The playhead all three share: 0.62 of the way through beat 2.
        let phase = (2.0 + 0.62) / 4
        let px = barLeft + span * phase
        fill(accent)
        drawCircle(px, y + 22, 9)
        stroke(accent)
        strokeWeight(2)
        drawLine(px, y - 12, px, y + 44)
        noStroke()
        fill(accent)
        textSize(14)
        textAlign(.center, .bottom)
        drawText("barPhase 0.66  on every machine at this instant", px, y - 20)

        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        drawText("beats is your own count; the phase inside the bar is the room's", 440, y + 84)
        fill(ink)
        drawText("same beatsPerBar, same downbeat", 440, y + 106)
    }
}
