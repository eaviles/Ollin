// figure: frame=0 themed
//
// Guide diagram (Chapter 32): a sketch as a widget. Along the top, the same
// piece at four moments a quarter of an hour apart, with the gaps between them
// marked as what they are: nothing runs there. Below, the clock the piece is
// drawn on, and the one thing that follows from a run being thrown away and
// asked for again.
import Ollin
import OllinDiagram

final class AQuarterHourApart: Sketch {
    override var canvasSize: CanvasSize { .size(880, 430) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The four moments of one run, as seconds since midnight.
    let moments: [(label: String, time: Double)] = [
        ("14:00", 14 * 3600),
        ("14:15", 14 * 3600 + 15 * 60),
        ("14:30", 14 * 3600 + 30 * 60),
        ("14:45", 14 * 3600 + 45 * 60),
    ]

    override func draw() {
        let theme = self.theme
        background(theme.paper)
        noStroke()
        textFont(.system)

        drawText("A piece that changes, not one that moves.",
                 40, 26, size: 17, color: theme.ink, align: .left, .top)
        drawText("ollin new Ripple --kind widget", 40, 52,
                 size: 12, color: theme.accent, align: .left, .top)

        run()
        clock()
        oneRunAtATime()
    }

    // MARK: The four pictures of one run

    func run() {
        let theme = self.theme
        let tile = 118.0
        let gap = 76.0
        let top = 96.0

        for (index, moment) in moments.enumerated() {
            let box = Rectangle(x: 40 + Double(index) * (tile + gap), y: top,
                                width: tile, height: tile)
            piece(in: box, at: moment.time)
            stroke(theme.border)
            strokeWeight(1)
            noFill()
            drawRect(box, cornerRadius: 12)
            noStroke()
            drawText(moment.label, box.center.x, box.y + box.height + 8,
                     size: 12, color: theme.ink, align: .center, .top)

            // The gap is the point: the system keeps the picture and nothing
            // draws until the next moment comes.
            guard index < moments.count - 1 else { continue }
            let from = Vector2(box.x + box.width + 8, box.center.y)
            let to = Vector2(box.x + box.width + gap - 8, box.center.y)
            stroke(theme.muted)
            strokeWeight(1)
            drawLine(from, to)
            noStroke()
            fill(theme.muted)
            drawTriangle(to, to + Vector2(-7, -4), to + Vector2(-7, 4))
            drawText("15 min", (from.x + to.x) / 2, box.center.y - 14,
                     size: 11, color: theme.muted, align: .center, .bottom)
            drawText("nothing", (from.x + to.x) / 2, box.center.y + 10,
                     size: 11, color: theme.muted, align: .center, .top)
            drawText("runs here", (from.x + to.x) / 2, box.center.y + 24,
                     size: 11, color: theme.muted, align: .center, .top)
        }

        drawText("One run: four pictures, drawn now, shown one at a time as their moments come.",
                 40, top + tile + 34, size: 13, color: theme.ink, align: .left, .top)
    }

    /// The piece itself: a ring that fills through the hour, tinted by the time
    /// of day. Deliberately something that reads at a glance, since a glance is
    /// all a picture a quarter of an hour apart gets.
    func piece(in box: Rectangle, at time: Double) {
        let day = time / 86_400
        let hour = (time.truncatingRemainder(dividingBy: 3600)) / 3600
        fill(Color(hex: 0x14161A))
        drawRect(box, cornerRadius: 12)

        let center = box.center
        let radius = box.width * 0.3
        stroke(Color(hex: 0x2A2F38))
        strokeWeight(6)
        noFill()
        drawCircle(center: center, radius: radius)

        let tint = Color(hue: 0.52 + day * 0.28, saturation: 0.55, brightness: 1)
        stroke(tint)
        strokeWeight(6)
        if hour > 0 {
            drawArc(center: center, radiusX: radius, radiusY: radius,
                    start: -.pi / 2, stop: -.pi / 2 + hour * .tau)
        }

        let angle = -.pi / 2 + hour * .tau
        strokeWeight(2)
        drawLine(center, center + Vector2(cos(angle), sin(angle)) * (radius - 10))
        noStroke()
        fill(tint)
        drawCircle(center: center + Vector2(cos(angle), sin(angle)) * radius, radius: 5)
        fill(Color(white: 0.9))
        drawCircle(center: center, radius: 3)
    }

    // MARK: The clock a picture is drawn on

    func clock() {
        let theme = self.theme
        let box = Rectangle(x: 40, y: 282, width: 420, height: 136)
        card(at: box, title: "the clock is the time of day")

        drawText("override var widgetTimeline: WidgetTimeline {",
                 box.x + 16, box.y + 34, size: 11, color: theme.accent, align: .left, .top)
        drawText("    .every(minutes: 15, count: 4)",
                 box.x + 16, box.y + 48, size: 11, color: theme.accent, align: .left, .top)
        drawText("}", box.x + 16, box.y + 62, size: 11, color: theme.accent, align: .left, .top)
        drawText("time     seconds since midnight of this picture's moment",
                 box.x + 16, box.y + 82, size: 12, color: theme.ink, align: .left, .top)
        drawText("deltaTime     the spacing: what really passed since the last one",
                 box.x + 16, box.y + 100, size: 12, color: theme.ink, align: .left, .top)
        drawText("date     the moment itself, which has not come yet",
                 box.x + 16, box.y + 118, size: 12, color: theme.ink, align: .left, .top)
    }

    func oneRunAtATime() {
        let theme = self.theme
        let box = Rectangle(x: 484, y: 282, width: 356, height: 136)
        card(at: box, title: "so the day, and not a stopwatch")

        drawText("The system throws a run away and asks for",
                 box.x + 16, box.y + 40, size: 12, color: theme.ink, align: .left, .top)
        drawText("another whenever it likes. A piece counting",
                 box.x + 16, box.y + 58, size: 12, color: theme.ink, align: .left, .top)
        drawText("from zero would jump back every time.",
                 box.x + 16, box.y + 76, size: 12, color: theme.ink, align: .left, .top)
        drawText("Reading the day, 14:15 draws the same picture today and tomorrow.",
                 box.x + 16, box.y + 96, size: 11, color: theme.muted, align: .left, .top)
    }

    func card(at box: Rectangle, title: String) {
        let theme = self.theme
        fill(theme.card)
        drawRect(box, cornerRadius: 8)
        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(box, cornerRadius: 8)
        noStroke()
        drawText(title, box.x + 16, box.y + 12, size: 12, color: theme.accent, align: .left, .top)
    }
}
