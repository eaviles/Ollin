// figure: frame=0 themed
//
// Guide diagram (Chapter 32): what one line of extend puts in your hand. The
// declarations on the left are this figure's own parameters, and the controls
// on the right are drawn from what the shipped wire says each one becomes, so
// the figure cannot promise a control the phone would not show. The point of
// the figure: the sketch declares values, the page builds the controls, and
// the two stay in step in both directions.
import Ollin
import OllinDiagram
import OllinRemote

final class TuningFromTheFloor: Sketch {
    override var canvasSize: CanvasSize { .size(880, 680) }

    /// A sketch's own menu of names, which the page renders as a menu.
    enum Mood: String, CaseIterable, ParamOption { case dawn, dusk, noir }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    // The parameters the figure both prints and draws. Their declarations are
    // the listing on the left; their controls are whatever the wire says.
    @Param(0.1 ... 4.0, group: "Motion") var speed = 1.4
    @Param(group: "Motion") var trails = true
    @Param(group: "Look") var accent = Color(red: 0.75, green: 0.35, blue: 0.95)
    @Param(group: "Look") var mood = Mood.dusk
    @Param(x: 0 ... 1, y: 0 ... 1, style: .pad, group: "Field") var focus = Vector2(0.62, 0.4)
    @Param(1 ... 12, group: "Field") var layers = 6

    /// The declaration each parameter is written with, for the listing.
    let declarations: [(name: String, text: String)] = [
        ("speed", "@Param(0.1...4.0, group: \"Motion\")\nvar speed = 1.4"),
        ("trails", "@Param(group: \"Motion\")\nvar trails = true"),
        ("accent", "@Param(group: \"Look\")\nvar accent = Color(...)"),
        ("mood", "@Param(group: \"Look\")\nvar mood = Mood.dusk"),
        ("focus", "@Param(x: 0...1, y: 0...1, style: .pad,\n       group: \"Field\") var focus = ..."),
        ("layers", "@Param(1...12, group: \"Field\")\nvar layers = 6")
    ]

    /// The phone's page is dark whatever the figure's own theme is: it depicts a
    /// screen rather than the page the figure sits on, and these are the page's
    /// own colors.
    let screenBack = Color(hex: 0x1C1C1E)
    let field = Color.white.withAlpha(0.08)
    let cardFill = Color.white.withAlpha(0.055)
    let text1 = Color.white.withAlpha(0.92)
    let text2 = Color.white.withAlpha(0.56)
    let text3 = Color.white.withAlpha(0.34)
    let pagePurple = Color(hex: 0xBF5AF2)
    let pageGreen = Color(hex: 0x30D158)

    override func draw() {
        let theme = self.theme
        background(theme.paper)
        noStroke()
        textFont(.system)

        drawText("One line, and every parameter is in your hand.",
                 40, 26, size: 17, color: theme.ink, align: .left, .top)
        drawText("extend(RemoteInspector()) prints an address; the phone's browser builds the controls",
                 40, 52, size: 12, color: theme.muted, align: .left, .top)

        listing()
        phone()
        bothWays()

        drawText("Anyone on the network who has the address can move these, so keep it to a network you trust.",
                 40, 640, size: 13, color: theme.accent, align: .left, .top)
    }

    // MARK: What the sketch says

    func listing() {
        let theme = self.theme
        let panel = Rectangle(x: 40, y: 88, width: 350, height: 406)
        fill(theme.card)
        drawRect(panel)
        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(panel)
        noStroke()

        drawText("the sketch", panel.x + 16, panel.y + 14,
                 size: 12, color: theme.muted, align: .left, .top)

        textFont(.systemMono)
        drawText("extend(RemoteInspector())", panel.x + 16, panel.y + 38,
                 size: 12, color: theme.accent, align: .left, .top)
        var y = panel.y + 74.0
        for declaration in declarations {
            for line in declaration.text.split(separator: "\n") {
                drawText(String(line), panel.x + 16, y, size: 11, color: theme.ink, align: .left, .top)
                y += 16
            }
            y += 20
        }
        textFont(.system)
    }

    // MARK: What the phone shows

    func phone() {
        let body = Rectangle(x: 556, y: 84, width: 284, height: 530)
        fill(theme.ink(0.35))
        drawRect(body, cornerRadius: 30)
        fill(screenBack)
        let screen = Rectangle(x: body.x + 8, y: body.y + 8,
                               width: body.width - 16, height: body.height - 16)
        drawRect(screen, cornerRadius: 23)

        let left = screen.x + 14
        let contentWidth = screen.width - 28

        // The strip that makes the piece's health readable from the floor.
        textFont(.systemMono)
        drawText("your-mac.local:9330", left, screen.y + 18,
                 size: 10, color: text3, align: .left, .top)
        textFont(.system)
        fill(field)
        let chip = Rectangle(x: screen.x + screen.width - 74, y: screen.y + 14, width: 60, height: 22)
        drawRect(chip, cornerRadius: 11)
        fill(pageGreen)
        drawCircle(chip.x + 13, chip.center.y, 3.5)
        drawText("live", chip.x + 24, chip.center.y, size: 11, color: text2, align: .left, .middle)

        fill(cardFill)
        let stats = Rectangle(x: left, y: screen.y + 46, width: contentWidth, height: 42)
        drawRect(stats, cornerRadius: 9)
        let cells: [(String, String, Color)] = [("59.9", "FPS", pageGreen),
                                                ("12.4s", "CLOCK", text1),
                                                ("745", "FRAME", text1)]
        for (index, cell) in cells.enumerated() {
            let x = stats.x + stats.width * (Double(index) + 0.5) / 3
            drawText(cell.0, x, stats.y + 8, size: 14, color: cell.2, align: .center, .top)
            drawText(cell.1, x, stats.y + 26, size: 8, color: text3, align: .center, .top)
        }

        // One row per parameter, each drawn as the kind the wire reports.
        var y = stats.y + stats.height + 10
        var lastGroup: String?
        for handle in parameters() where handle.name != "darkTheme" {
            let descriptor = RemoteWire.descriptor(for: handle)
            if descriptor.group != lastGroup, let group = descriptor.group {
                drawText(group.uppercased(), left + 4, y, size: 10, color: text3, align: .left, .top)
                y += 16
                lastGroup = descriptor.group
            }
            y += row(descriptor, at: Rectangle(x: left, y: y, width: contentWidth, height: 44)) + 6
        }
    }

    /// Draws one control the way the page lays it out, and answers its height.
    func row(_ descriptor: RemoteParamDescriptor, at box: Rectangle) -> Double {
        switch descriptor.kind {
        case .slider:
            fill(field)
            drawRect(box, cornerRadius: 7)
            let fraction = fraction(of: descriptor)
            fill(pagePurple.withAlpha(0.22))
            drawRect(Rectangle(x: box.x, y: box.y, width: box.width * fraction, height: box.height),
                     cornerRadius: 7)
            stroke(pagePurple)
            strokeWeight(2)
            drawLine(Vector2(box.x + box.width * fraction, box.y),
                     Vector2(box.x + box.width * fraction, box.y + box.height))
            noStroke()
            fill(Color(hex: 0xF6F6F8))
            drawCircle(box.x + box.width * fraction, box.center.y, 11)
            drawText(descriptor.label, box.x + 14, box.center.y,
                     size: 14, color: text1, align: .left, .middle)
            drawText(numberText(descriptor), box.x + box.width - 14, box.center.y,
                     size: 14, color: text2, align: .right, .middle)
            return box.height

        case .toggle:
            fill(cardFill)
            drawRect(box, cornerRadius: 7)
            drawText(descriptor.label, box.x + 14, box.center.y,
                     size: 14, color: text1, align: .left, .middle)
            let on = descriptor.value == .boolean(true)
            let track = Rectangle(x: box.x + box.width - 65, y: box.center.y - 15, width: 51, height: 30)
            fill(on ? pagePurple : Color.white.withAlpha(0.16))
            drawRect(track, cornerRadius: 15)
            fill(.white)
            drawCircle(on ? track.x + track.width - 15 : track.x + 15, track.center.y, 13)
            return box.height

        case .color:
            fill(cardFill)
            drawRect(box, cornerRadius: 7)
            drawText(descriptor.label, box.x + 14, box.center.y,
                     size: 14, color: text1, align: .left, .middle)
            if case .color(let r, let g, let b, let a) = descriptor.value {
                fill(Color(red: r, green: g, blue: b, alpha: a))
                drawRect(Rectangle(x: box.x + box.width - 76, y: box.center.y - 14,
                                   width: 62, height: 28), cornerRadius: 7)
            }
            return box.height

        case .menu:
            fill(cardFill)
            drawRect(box, cornerRadius: 7)
            drawText(descriptor.label, box.x + 14, box.center.y,
                     size: 14, color: text1, align: .left, .middle)
            // A menu travels as an index into the options the wire carries.
            if case .number(let index) = descriptor.value,
               let options = descriptor.options,
               let chosen = options.indices.contains(Int(index)) ? options[Int(index)] : nil {
                let menu = Rectangle(x: box.x + box.width - 106, y: box.center.y - 15,
                                     width: 92, height: 30)
                fill(field)
                drawRect(menu, cornerRadius: 7)
                drawText(chosen, menu.x + 13, menu.center.y,
                         size: 13, color: text1, align: .left, .middle)
                fill(text3)
                drawTriangle(Vector2(menu.x + menu.width - 20, menu.center.y - 2),
                             Vector2(menu.x + menu.width - 12, menu.center.y - 2),
                             Vector2(menu.x + menu.width - 16, menu.center.y + 3))
            }
            return box.height

        case .vector:
            let pad = Rectangle(x: box.x, y: box.y, width: box.width, height: 92)
            fill(cardFill)
            drawRect(pad, cornerRadius: 7)
            drawText(descriptor.label + (descriptor.isPad == true ? "   XY pad" : ""),
                     pad.x + 14, pad.y + 8, size: 12, color: text2, align: .left, .top)
            let area = Rectangle(x: pad.x + 14, y: pad.y + 26, width: 56, height: 56)
            fill(field)
            drawRect(area, cornerRadius: 6)
            if case .vector(let x, let y) = descriptor.value {
                let px = area.x + area.width * fraction(x, descriptor.xLower, descriptor.xUpper)
                let py = area.y + area.height * (1 - fraction(y, descriptor.yLower, descriptor.yUpper))
                stroke(pagePurple.withAlpha(0.5))
                strokeWeight(1)
                drawLine(Vector2(area.x, py), Vector2(area.x + area.width, py))
                drawLine(Vector2(px, area.y), Vector2(px, area.y + area.height))
                noStroke()
                fill(pagePurple)
                drawCircle(px, py, 6)
                drawText(String(format: "%.2f, %.2f", x, y), area.x + area.width + 14, area.center.y,
                         size: 13, color: text2, align: .left, .middle)
            }
            return pad.height

        case .stepper:
            fill(cardFill)
            drawRect(box, cornerRadius: 7)
            drawText(descriptor.label, box.x + 14, box.center.y,
                     size: 14, color: text1, align: .left, .middle)
            let group = Rectangle(x: box.x + box.width - 112, y: box.center.y - 15, width: 98, height: 30)
            fill(field)
            drawRect(group, cornerRadius: 7)
            drawText("−", group.x + 16, group.center.y, size: 16, color: text1, align: .center, .middle)
            drawText(numberText(descriptor), group.center.x, group.center.y,
                     size: 14, color: text1, align: .center, .middle)
            drawText("+", group.x + group.width - 16, group.center.y,
                     size: 16, color: text1, align: .center, .middle)
            return box.height

        default:
            fill(cardFill)
            drawRect(box, cornerRadius: 7)
            drawText("\(descriptor.label)   \(descriptor.kind.rawValue)", box.x + 14, box.center.y,
                     size: 13, color: text2, align: .left, .middle)
            return box.height
        }
    }

    // MARK: The two directions

    func bothWays() {
        let theme = self.theme
        let left = 404.0
        let right = 548.0

        // Up the page: what the phone sends.
        drawText("a drag lands before", left, 268, size: 11, color: theme.ink, align: .left, .top)
        drawText("the next frame", left, 284, size: 11, color: theme.ink, align: .left, .top)
        arrow(from: Vector2(right, 310), to: Vector2(left, 310), color: theme.accent)

        // Down the page: what the Mac sends.
        arrow(from: Vector2(left, 356), to: Vector2(right, 356), color: theme.muted)
        drawText("an edit on the Mac", left, 366, size: 11, color: theme.muted, align: .left, .top)
        drawText("appears here", left, 382, size: 11, color: theme.muted, align: .left, .top)
    }

    /// A plain arrow along a horizontal run.
    func arrow(from start: Vector2, to end: Vector2, color: Color) {
        stroke(color)
        strokeWeight(2)
        drawLine(start, end)
        noStroke()
        fill(color)
        let direction = end.x > start.x ? 1.0 : -1.0
        drawTriangle(end,
                     Vector2(end.x - direction * 9, end.y - 5),
                     Vector2(end.x - direction * 9, end.y + 5))
    }

    // MARK: Reading a descriptor

    func fraction(of descriptor: RemoteParamDescriptor) -> Double {
        guard case .number(let value) = descriptor.value else { return 0 }
        return fraction(value, descriptor.lower, descriptor.upper)
    }

    func fraction(_ value: Double, _ lower: Double?, _ upper: Double?) -> Double {
        guard let lower, let upper, upper > lower else { return 0 }
        return clamp((value - lower) / (upper - lower), to: 0 ... 1)
    }

    func numberText(_ descriptor: RemoteParamDescriptor) -> String {
        guard case .number(let value) = descriptor.value else { return "" }
        return value == value.rounded() ? "\(Int(value))" : String(format: "%.2f", value)
    }
}
