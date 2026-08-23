// figure: frame=1
//
// Guide diagram (Chapter 31): one knob that holds four numbers, two of them
// under a rule and two left alone. The three outlines are the same rectangle
// knob at three moments, all drawn from the corner the rules never touch. The
// shapes come from the shipped track, so the picture is the real answer rather
// than a drawing of it.
import Ollin

final class KnobParts: Sketch {
    override var canvasSize: CanvasSize { .size(880, 430) }

    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.22)
    let mark = Color(hex: 0xE2603F)

    let wide = "300 + sin(time) * 120"
    let tall = "150 + cos(time) * 60"

    /// Where the hand put the rectangle. Only its size is ever worked out.
    let placed = ParamStored.rect(x: 62, y: 108, width: 300, height: 150)

    lazy var track = Automation.Track(name: "frame", parts: [
        "width": try! Formula(wide),
        "height": try! Formula(tall),
    ])

    let moments = [0.0, 2.0, 4.0]

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        noStroke()
        fill(ink)
        textSize(24)
        textAlign(.left, .top)
        drawText("one knob, four parts", 62, 52)

        for (index, at) in moments.enumerated() {
            guard case .rect(let x, let y, let w, let h) =
                    Automation.applying(track.partValues(at: at), to: placed) else { continue }
            noFill()
            stroke(index == 0 ? ink : faint)
            strokeWeight(index == 0 ? 2.5 : 1.5)
            drawRect(corner: Vector2(x, y), width: w, height: h)

            // The label rides inside its own edge, so a wide moment never
            // reaches the listing beside it.
            noStroke()
            fill(index == 0 ? soft : faint)
            textSize(15)
            textAlign(.right, .bottom)
            drawText("\(Int(at)) s", x + w - 10, y + h - 8)
        }

        // The corner the rules never name, marked so it reads as held.
        noStroke()
        fill(mark)
        drawCircle(62, 108, 5.5)
        fill(soft)
        textSize(15)
        textAlign(.left, .bottom)
        drawText("x, y: where the hand left them", 74, 104)

        listing()

        noStroke()
        fill(soft)
        textSize(18)
        textAlign(.left, .top)
        drawText("a part with a rule moves; a part without one is yours to move",
                 62, 376)
    }

    /// The four parts of the knob, each with its rule or a dash.
    func listing() {
        let rows = [("x", ""), ("y", ""), ("width", wide), ("height", tall)]
        var top = 108.0
        for (part, rule) in rows {
            noStroke()
            fill(soft)
            textSize(16)
            textAlign(.right, .top)
            drawText("frame.\(part)", 612, top)

            fill(rule.isEmpty ? faint : ink)
            textAlign(.left, .top)
            drawText(rule.isEmpty ? "no rule" : rule, 628, top)
            top += 34
        }
    }
}
