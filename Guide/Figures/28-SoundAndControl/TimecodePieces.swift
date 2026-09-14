// figure: frame=0 themed
//
// Guide diagram (Chapter 28): how a position arrives over a MIDI cable. The
// eight quarter-frame messages that spell one timecode, four to a frame, with
// the nibble each one carries read from the shipped encoder rather than typed
// out here, so the figure cannot disagree with the wire. Below, the locate:
// the same position whole, in one exclusive message, its bytes read the same
// way. The point of the figure: a position takes two frames to arrive, so the
// set that lands names a time 1.75 frames back, which is why the clock steps
// rather than jumps.
import Ollin
import OllinDiagram
import OllinMIDI

final class TimecodePieces: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The position being spelled. Every number in the figure comes off it.
    let code = Timecode(hours: 1, minutes: 23, seconds: 45, frames: 12, frameRate: .fps25)

    /// What each of the eight pieces carries, in the order the sender runs.
    let carried = ["frames\nlow", "frames\nhigh", "seconds\nlow", "seconds\nhigh",
                   "minutes\nlow", "minutes\nhigh", "hours\nlow", "hours high\n+ the rate"]

    override func draw() {
        let theme = self.theme
        background(theme.paper)
        noStroke()
        textFont(.system)

        textAlign(.left, .top)
        drawText("MIDI clock says how fast. Timecode says where.",
                 40, 26, size: 17, color: theme.ink, align: .left, .top)
        drawText("one position, spelled in eight small messages, four to a frame",
                 40, 52, size: 12, color: theme.muted, align: .left, .top)

        messages()
        assembled()
        locate()

        drawText("A whole position takes two frames to arrive, so the set that lands names a",
                 40, 482, size: 14, color: theme.ink, align: .left, .top)
        drawText("time 1.75 frames back. The clock steps to it and glides on at the frame rate.",
                 40, 504, size: 14, color: theme.ink, align: .left, .top)
        drawText("Stop the deck and the position holds where it was.",
                 40, 528, size: 14, color: theme.muted, align: .left, .top)
    }

    // MARK: The eight messages

    /// The wire, as a stalk per message along a two-frame baseline.
    func messages() {
        let theme = self.theme
        let left = 46.0
        let right = 834.0
        let baseline = 268.0
        let step = (right - left) / 8

        // The two frames the set spans, as the ground under the messages.
        for half in 0 ..< 2 {
            let box = Rectangle(x: left + Double(half) * step * 4, y: baseline,
                                width: step * 4, height: 30)
            if half == 0 {
                fill(theme.card)
                drawRect(box)
            }
            drawText(half == 0 ? "one frame" : "the next frame",
                     box.center.x, box.center.y,
                     size: 12, color: theme.muted, align: .center, .middle)
        }
        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(Rectangle(x: left, y: baseline, width: step * 8, height: 30))
        drawLine(Vector2(left + step * 4, baseline), Vector2(left + step * 4, baseline + 30))
        noStroke()

        for piece in 0 ..< 8 {
            let x = left + step * (Double(piece) + 0.5)
            let card = Rectangle(x: x - step / 2 + 5, y: 96, width: step - 10, height: 142)

            fill(theme.card)
            drawRect(card)
            stroke(theme.border)
            strokeWeight(1)
            noFill()
            drawRect(card)
            noStroke()

            drawText("piece \(piece)", card.center.x, card.y + 12,
                     size: 11, color: theme.muted, align: .center, .top)

            let lines = carried[piece].split(separator: "\n").map(String.init)
            for (index, line) in lines.enumerated() {
                drawText(line, card.center.x, card.y + 38 + Double(index) * 17,
                         size: 13, color: theme.ink, align: .center, .top)
            }

            // The nibble the shipped encoder puts on the wire for this piece.
            let value = code.quarterFrameValue(piece: piece)
            textFont(.systemMono)
            drawText(nibble(value), card.center.x, card.y + card.height - 34,
                     size: 15, color: theme.accent, align: .center, .top)
            textFont(.system)
            drawText("= \(value)", card.center.x, card.y + card.height - 16,
                     size: 11, color: theme.muted, align: .center, .top)

            // The stalk down to the moment it was sent.
            stroke(theme.ink(0.3))
            strokeWeight(1.5)
            drawLine(Vector2(x, card.y + card.height), Vector2(x, baseline))
            noStroke()
            fill(theme.ink)
            drawCircle(x, baseline, 4)
        }

        drawText("four bits each, so eight of them carry the whole position",
                 width / 2, baseline + 40, size: 12, color: theme.muted, align: .center, .top)
    }

    // MARK: What the eight of them spell

    func assembled() {
        let theme = self.theme
        let panel = Rectangle(x: 46, y: 338, width: 460, height: 118)
        fill(theme.card)
        drawRect(panel)
        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(panel)
        noStroke()

        drawText("what the eight of them spell", panel.x + 18, panel.y + 14,
                 size: 12, color: theme.muted, align: .left, .top)

        // Decoded the way the clock decodes it: from the nibbles, not from the
        // timecode the figure started with.
        let nibbles = (0 ..< 8).map { code.quarterFrameValue(piece: $0) }
        let spelled = Timecode(quarterFrameValues: nibbles)
        textFont(.systemMono)
        drawText("\(spelled)", panel.x + 18, panel.y + 40,
                 size: 30, color: theme.ink, align: .left, .top)
        textFont(.system)
        drawText("at \(spelled.frameRate.name) frames a second, which piece 7 carries too",
                 panel.x + 18, panel.y + 82, size: 12, color: theme.muted, align: .left, .top)
    }

    // MARK: The locate

    func locate() {
        let theme = self.theme
        let panel = Rectangle(x: 522, y: 338, width: 312, height: 118)
        fill(theme.card)
        drawRect(panel)
        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(panel)
        noStroke()

        drawText("press locate, and it arrives whole", panel.x + 18, panel.y + 14,
                 size: 12, color: theme.muted, align: .left, .top)

        // The full-frame exclusive's own bytes, from the shipped encoder.
        let bytes = code.fullFrameSysEx
        textFont(.systemMono)
        let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        drawText(hex, panel.x + 18, panel.y + 42, size: 14, color: theme.accent, align: .left, .top)
        textFont(.system)
        drawText("one message, \(bytes.count) bytes, no waiting",
                 panel.x + 18, panel.y + 68, size: 12, color: theme.ink, align: .left, .top)
        drawText("a stopped deck sends this and holds",
                 panel.x + 18, panel.y + 88, size: 12, color: theme.muted, align: .left, .top)
    }

    // MARK: The line under everything

    /// The four bits of a nibble, written out, so a piece's payload is visible
    /// as the small thing it is.
    func nibble(_ value: Int) -> String {
        let bits = String(value, radix: 2)
        return String(String(repeating: "0", count: 4) + bits).suffix(4).description
    }
}
