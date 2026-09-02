// figure: frame=1 themed
//
// Guide diagram (Chapter 31): the same motion said two ways. The left panel is
// a keyed Automation.Track, sampled, with a dot at each key. The right panel is
// the same track filled by a Formula instead, sampled the same way, with the
// text that made it underneath. Both read the shipped types, so the shapes are
// the real ones rather than a drawing of them.
import Ollin
import OllinDiagram

final class ParameterAsARule: Sketch {
    override var canvasSize: CanvasSize { .size(880, 430) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.6) }
    var faint: Color { theme.ink(0.22) }
    var mark: Color { theme.accent }

    /// One pass, in seconds, and the range the parameter covers.
    let span = 6.0
    let low = 92.0
    let high = 288.0

    let keyed = Automation.Track(name: "radius", keys: [
        .init(at: 0, .number(190), curve: .easeInOut),
        .init(at: 1.5, .number(270), curve: .easeInOut),
        .init(at: 3, .number(190), curve: .easeInOut),
        .init(at: 4.5, .number(110), curve: .easeInOut),
        .init(at: 6, .number(190)),
    ])

    lazy var ruled = Automation.Track(
        name: "radius", formula: try! Formula("190 + sin(time * tau / 6) * 80"))

    override func draw() {
        background(paper)

        panel(0, title: "keys", caption: "five moments, and the curves between",
              track: keyed, showKeys: true)
        panel(1, title: "a rule", caption: "190 + sin(time * tau / 6) * 80",
              track: ruled, showKeys: false)

        noStroke()
        fill(soft)
        textSize(19)
        textAlign(.center, .top)
        drawText("the same motion, said two ways", width / 2, 376)
    }

    func panel(_ index: Int, title: String, caption: String,
               track: Automation.Track, showKeys: Bool) {
        let w = 366.0
        let x = 48 + Double(index) * (w + 52)
        let box = Rectangle(x: x, y: 108, width: w, height: 190)

        // The title.
        noStroke()
        fill(ink)
        textSize(24)
        textAlign(.left, .top)
        drawText(title, x, 56)

        // The middle line, so both panels read against the same rest value.
        stroke(faint)
        strokeWeight(1.5)
        drawLine(box.x, box.y + box.height / 2, box.x + box.width, box.y + box.height / 2)

        // The track itself, sampled across the panel.
        var points: [Vector2] = []
        for step in 0...180 {
            let at = span * Double(step) / 180
            guard case .number(let held)? = track.value(at: at) else { continue }
            points.append(Vector2(box.x + box.width * at / span,
                                  box.y + box.height * (1 - (held - low) / (high - low))))
        }
        noFill()
        stroke(ink)
        strokeWeight(2.5)
        drawPolyline(points)

        // A dot at every key, which is what the right panel has none of.
        if showKeys {
            noStroke()
            fill(mark)
            for key in track.keys {
                guard case .number(let held) = key.value else { continue }
                drawCircle(box.x + box.width * key.time / span,
                           box.y + box.height * (1 - (held - low) / (high - low)), 5.5)
            }
        }

        // The panel's outline and its caption.
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(corner: Vector2(box.x, box.y), width: box.width, height: box.height)

        noStroke()
        fill(soft)
        textSize(18)
        textAlign(.left, .top)
        drawText(caption, box.x, box.y + box.height + 16)
    }
}
