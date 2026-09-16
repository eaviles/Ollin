// figure: frame=0 themed
//
// Guide diagram (Chapter 28): what OSCQuery removes. Each declared parameter
// becomes a node that carries its own type and range, and the control app
// builds its control from the node rather than from an address somebody typed.
// The tree goes out over HTTP; the values come back over OSC at the same port.
import Ollin
import OllinDiagram

final class PublishedParameters: Sketch {
    override var canvasSize: CanvasSize { .size(940, 600) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// One row per parameter: the declaration, the node it is served as, and
    /// the control an app lays out after reading that node.
    struct Row {
        var declaration: String
        var property: String
        var path: String
        var type: String
        var range: String
        var control: Control
    }

    enum Control { case fader(Double), stepper(String), menu(String), toggle(Bool), well(Color) }

    let rows: [Row] = [
        Row(declaration: "@Param(20...400, group: \"Shape\")",
            property: "var radius = 180.0",
            path: "/Shape/radius", type: "f", range: "20 ... 400",
            control: .fader(0.44)),
        Row(declaration: "@Param(3...24, group: \"Shape\")",
            property: "var count = 9",
            path: "/Shape/count", type: "i", range: "3 ... 24",
            control: .stepper("9")),
        Row(declaration: "@Param(group: \"Shape\")",
            property: "var style = Style.petals",
            path: "/Shape/style", type: "s", range: "petals, rings, spokes",
            control: .menu("petals")),
        Row(declaration: "@Param(group: \"Motion\")",
            property: "var spin = true",
            path: "/Motion/spin", type: "T", range: "",
            control: .toggle(true)),
        Row(declaration: "@Param(group: \"Color\")",
            property: "var tint = Color(hex: 0xFF9E3D)",
            path: "/Color/tint", type: "r", range: "#FF9E3DFF",
            control: .well(Color(hex: 0xFF9E3D))),
    ]

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let top = 100.0
        let step = 76.0

        drawText("what the sketch declares", 40, 48,
                 size: 17, color: theme.ink, align: .left, .middle)
        drawText("the tree it serves", 352, 48,
                 size: 17, color: theme.ink, align: .left, .middle)
        drawText("what the app lays out", 726, 48,
                 size: 17, color: theme.ink, align: .left, .middle)

        // The two hops across, said once rather than per row.
        hop(from: 290, to: 344, y: 48, label: "HTTP")
        hop(from: 690, to: 718, y: 48, label: "builds")

        for (index, row) in rows.enumerated() {
            let y = top + Double(index) * step
            declaration(row, y: y)
            node(row, y: y)
            control(row.control, y: y)
        }

        returnPath(y: 492)
        diagramCaption("nobody types an address: the node carries the range, and the control is built from it",
                       at: 552, theme: theme)
    }

    // MARK: The three columns

    private func declaration(_ row: Row, y: Double) {
        textFont(.systemMono)
        drawText(row.declaration, 40, y, size: 13, color: theme.muted, align: .left, .middle)
        drawText(row.property, 40, y + 20, size: 14, color: theme.ink, align: .left, .middle)
        textFont(.system)
    }

    private func node(_ row: Row, y: Double) {
        let card = Rectangle(x: 352, y: y - 26, width: 328, height: 52)
        withState {
            fill(theme.card)
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(card, cornerRadius: 8)
        }
        textFont(.systemMono)
        drawText(row.path, card.x + 14, card.y + 18,
                 size: 15, color: theme.ink, align: .left, .middle)
        drawText(row.type, card.x + card.width - 14, card.y + 18,
                 size: 15, color: theme.accent, align: .right, .middle)
        if !row.range.isEmpty {
            drawText(row.range, card.x + 14, card.y + 38,
                     size: 13, color: theme.muted, align: .left, .middle)
        }
        textFont(.system)
    }

    private func control(_ control: Control, y: Double) {
        switch control {
        case let .fader(fraction):
            let track = Rectangle(x: 726, y: y - 3, width: 150, height: 6)
            withState {
                noStroke()
                fill(theme.ink(0.16))
                drawRect(track, cornerRadius: 3)
                fill(theme.accent)
                drawRect(Rectangle(x: track.x, y: track.y,
                                   width: track.width * fraction, height: track.height),
                         cornerRadius: 3)
                drawCircle(center: Vector2(track.x + track.width * fraction, track.y + 3), radius: 9)
            }
            drawText("20", track.x, track.y + 22, size: 12, color: theme.muted, align: .left, .middle)
            drawText("400", track.x + track.width, track.y + 22,
                     size: 12, color: theme.muted, align: .right, .middle)

        case let .stepper(value):
            let box = Rectangle(x: 726, y: y - 15, width: 86, height: 30)
            field(box)
            drawText(value, box.x + 14, box.y + 15, size: 15, color: theme.ink, align: .left, .middle)
            drawText("- +", box.x + box.width - 12, box.y + 15,
                     size: 15, color: theme.muted, align: .right, .middle)

        case let .menu(value):
            let box = Rectangle(x: 726, y: y - 15, width: 150, height: 30)
            field(box)
            drawText(value, box.x + 14, box.y + 15, size: 15, color: theme.ink, align: .left, .middle)
            withState {
                noStroke()
                fill(theme.muted)
                let tip = Vector2(box.x + box.width - 18, box.y + 18)
                drawTriangle(Vector2(tip.x - 5, tip.y - 4), Vector2(tip.x + 5, tip.y - 4), tip)
            }

        case let .toggle(on):
            let box = Rectangle(x: 726, y: y - 13, width: 50, height: 26)
            withState {
                noStroke()
                fill(on ? theme.accent : theme.ink(0.2))
                drawRect(box, cornerRadius: 13)
                fill(.white)
                drawCircle(center: Vector2(on ? box.x + box.width - 13 : box.x + 13, box.y + 13),
                           radius: 10)
            }

        case let .well(color):
            let box = Rectangle(x: 726, y: y - 15, width: 50, height: 30)
            withState {
                fill(color)
                stroke(theme.border)
                strokeWeight(1.5)
                drawRect(box, cornerRadius: 6)
            }
        }
    }

    private func field(_ box: Rectangle) {
        withState {
            fill(theme.card)
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(box, cornerRadius: 6)
        }
    }

    // MARK: The way back

    /// The value's own direction: out of the control, over plain OSC, into the
    /// property the first column declared.
    private func returnPath(y: Double) {
        withState {
            noFill()
            stroke(theme.accent)
            strokeWeight(2)
            drawLine(876, y, 40, y)
            drawLine(876, y - 22, 876, y)
            drawLine(40, y, 40, y - 16)
            drawLine(40, y - 16, 48, y - 6)
            drawLine(40, y - 16, 32, y - 6)
        }
        textFont(.systemMono)
        drawText("/Shape/radius 240.0", width / 2, y - 16,
                 size: 16, color: theme.accent, align: .center, .middle)
        textFont(.system)
        drawText("plain OSC, the same port number, in the parameter's own units",
                 width / 2, y + 22, size: 15, color: theme.muted, align: .center, .middle)
    }

    /// A short hop between two columns, with the protocol that carries it.
    private func hop(from x1: Double, to x2: Double, y: Double, label: String) {
        withState {
            stroke(theme.ink(0.45))
            strokeWeight(1.5)
            drawLine(x1, y, x2 - 6, y)
            drawLine(x2, y, x2 - 8, y - 5)
            drawLine(x2, y, x2 - 8, y + 5)
        }
        drawText(label, (x1 + x2) / 2, y - 16, size: 12, color: theme.muted, align: .center, .middle)
    }
}
