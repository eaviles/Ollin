// figure: frame=1
//
// Guide diagram (Chapter 31): the inspector's cost row, annotated. A stylized
// card drawn with Ollin itself: the frame-rate strip, the two bars scaled to one
// frame, and the counts underneath. Callouts name what each part answers.
import Ollin

final class CostRow: Sketch {
    override var canvasSize: CanvasSize { .size(880, 456) }

    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let accent = Color(hex: 0xE4572E)

    // The card's own palette, the dark inspector the host shows.
    let cardFill = Color(hex: 0x232326)
    let cardLine = Color(white: 1, alpha: 0.09)
    let label = Color(white: 1, alpha: 0.36)
    let readout = Color(hex: 0xE8E2F2)
    let cpuTint = Color(hex: 0xB07CE8)
    let gpuTint = Color(hex: 0x4ED07A)

    // One frame at 60 a second, which is what the bars are scaled against.
    let budget = 16.7
    let cpuMS = 9.8
    let gpuMS = 5.4

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let card = Rectangle(x: 250, y: 96, width: 380, height: 250)
        noStroke()
        fill(cardFill)
        drawRect(card, cornerRadius: 12)

        // The frame-rate strip the cost row sits under.
        let strip = card.y + 58
        statCell("58", "FPS", at: Vector2(card.x + 48, strip), valueColor: gpuTint)
        statCell("9.8 ms", "CPU", at: Vector2(card.x + 143, strip), valueColor: readout)
        statCell("1080²", "CANVAS", at: Vector2(card.x + 238, strip), valueColor: readout)
        statCell("8k sdf", "GEOMETRY", at: Vector2(card.x + 333, strip), valueColor: readout)

        stroke(cardLine)
        strokeWeight(1)
        drawLine(Vector2(card.x, card.y + 92), Vector2(card.x + card.width, card.y + 92))

        // The two bars, both scaled to one frame.
        bar(icon: "CPU", value: cpuMS, tint: cpuTint, y: card.y + 124, in: card)
        bar(icon: "GPU", value: gpuMS, tint: gpuTint, y: card.y + 154, in: card)

        // The counts.
        countCell("1", "DRAW", at: Vector2(card.x + 68, card.y + 200))
        countCell("2", "PASSES", at: Vector2(card.x + 190, card.y + 200))
        countCell("1", "BATCH", at: Vector2(card.x + 312, card.y + 200))

        // Callouts. Every leader ends just outside the card, so no line crosses
        // the readout it is pointing at.
        textSize(15)
        callout("the longer bar is", "the half to fix",
                at: Vector2(40, 186), to: Vector2(card.x - 8, card.y + 124), alignRight: false)
        callout("draws, passes, batches:", "the work behind the bars",
                at: Vector2(40, 300), to: Vector2(card.x - 8, card.y + 200), alignRight: false)
        callout("the GPU's half comes", "from its own clock",
                at: Vector2(845, 186), to: Vector2(card.x + card.width + 8, card.y + 154),
                alignRight: true)
        callout("hover any cell for", "the full breakdown",
                at: Vector2(845, 300), to: Vector2(card.x + card.width + 8, card.y + 200),
                alignRight: true)

        noStroke()
        fill(soft)
        textSize(19)
        textAlign(.center, .top)
        drawText("both bars are drawn to one frame, which is 16.7 ms at 60 a second",
                 width / 2, 392)
    }

    /// One cell of the frame-rate strip: a value over a small caps label.
    func statCell(_ value: String, _ name: String, at p: Vector2, valueColor: Color) {
        noStroke()
        textAlign(.center, .center)
        fill(valueColor)
        textSize(14)
        drawText(value, p.x, p.y)
        fill(label)
        textSize(10)
        drawText(name, p.x, p.y + 19)
    }

    /// One cost bar: a name, a track filled to this side's share of the frame,
    /// and the number.
    func bar(icon: String, value: Double, tint: Color, y: Double, in card: Rectangle) {
        noStroke()
        fill(label)
        textSize(11)
        textAlign(.left, .center)
        drawText(icon, card.x + 22, y)

        let trackX = card.x + 62, trackW = 218.0
        fill(Color(white: 1, alpha: 0.10))
        drawRect(trackX, y - 4, trackW, 8, cornerRadius: 4)
        fill(tint)
        drawRect(trackX, y - 4, trackW * (value / budget), 8, cornerRadius: 4)

        fill(readout)
        textSize(13)
        textAlign(.right, .center)
        drawText(String(format: "%.1f", value), card.x + card.width - 46, y)
        fill(label)
        textSize(10)
        textAlign(.left, .center)
        drawText("ms", card.x + card.width - 40, y)
    }

    /// One icon-led count under the bars.
    func countCell(_ value: String, _ name: String, at p: Vector2) {
        noStroke()
        fill(Color(white: 1, alpha: 0.30))
        drawRect(p.x - 34, p.y - 6, 11, 11, cornerRadius: 2)
        fill(readout)
        textSize(13)
        textAlign(.left, .center)
        drawText(value, p.x - 16, p.y)
        fill(label)
        textSize(10)
        drawText(name, p.x - 2, p.y)
    }

    func callout(_ line1: String, _ line2: String, at p: Vector2, to target: Vector2,
                 alignRight: Bool) {
        noStroke()
        fill(ink)
        textSize(15)
        textAlign(alignRight ? .right : .left, .top)
        drawText(line1, p.x, p.y)
        drawText(line2, p.x, p.y + 22)
        // Start the leader at the text edge facing the target, so it never
        // crosses its own words.
        let widest = max(textWidth(line1), textWidth(line2))
        let anchor = Vector2(alignRight ? p.x - widest - 10 : p.x + widest + 10, p.y + 22)
        stroke(accent)
        strokeWeight(2)
        drawLine(anchor, target)
        noStroke()
        fill(accent)
        drawCircle(target.x, target.y, 4)
    }
}
