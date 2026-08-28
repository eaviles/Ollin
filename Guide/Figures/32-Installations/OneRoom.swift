// figure: frame=1 themed
//
// Guide diagram (Chapter 32): what a room fixes. Two machines run the same
// piece. In the top row each keeps its own clock, so the bead sits in a
// different place on each screen and the piece reads as two. In the bottom row
// both read the room's clock, so the beads agree. The timelines under each row
// carry the whole argument: the second machine started later, and only the
// room's clock puts that difference somewhere the audience cannot see.
import Ollin
import OllinDiagram

final class OneRoom: Sketch {
    override var canvasSize: CanvasSize { .size(880, 700) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.55) }
    var accent: Color { theme.accent }

    /// Seconds between the two machines being switched on.
    let lateBy = 2.4
    /// The moment the figure is drawn at, on the machine that started first.
    let now = 7.0

    override func draw() {
        background(paper)

        drawText("two machines running one piece", 56, 30,
                 size: 20, color: ink, align: .left, .top)

        row(top: 82, title: "each machine's own clock",
            angles: (now, now - lateBy), agreed: false)
        row(top: 376, title: "the room's clock",
            angles: (now, now), agreed: true)

        diagramCaption("room.time is the same number on both machines", at: 656, theme: theme)
    }

    /// One row: two screens side by side, the timeline underneath that says
    /// which clock they are reading, and a line saying what that costs.
    private func row(top: Double, title: String, angles: (Double, Double), agreed: Bool) {
        drawText(title, 56, top, size: 17, color: ink, align: .left, .top)

        let screens = [
            Rectangle(x: 56, y: top + 30, width: 292, height: 128),
            Rectangle(x: 372, y: top + 30, width: 292, height: 128)
        ]
        screen(screens[0], angle: angles.0, label: "started first")
        screen(screens[1], angle: angles.1, label: "started \(seconds(lateBy)) later")

        drawText(agreed ? "in step" : "out of step", 824, top + 94,
                 size: 17, color: agreed ? accent : theme.ink(0.75), align: .right, .middle)

        timeline(y: top + 222, agreed: agreed)
        drawText(agreed
                 ? "both count from the room's own start, so joining late costs nothing"
                 : "each counts from its own start, so the two never agree",
                 56, top + 254, size: 14, color: soft, align: .left, .top)
    }

    /// One screen: the piece, which is a bead going round a ring once every four
    /// seconds. Where the bead sits is the whole tell.
    private func screen(_ frame: Rectangle, angle seconds: Double, label: String) {
        diagramFrame(frame, theme: theme)
        withState {
            withClip(frame) {
                let center = Vector2(frame.center.x, frame.center.y)
                let radius = 42.0
                noFill()
                stroke(theme.ink(0.18))
                strokeWeight(1.5)
                drawCircle(center: center, radius: radius)

                let angle = seconds * (.pi / 2)
                let bead = center + Vector2(cos(angle), sin(angle)) * radius
                stroke(theme.ink(0.3))
                drawLine(center, bead)
                noStroke()
                fill(accent)
                drawCircle(center: bead, radius: 9)
            }
        }
        drawText(label, frame.center.x, frame.y + frame.height + 10,
                 size: 13, color: soft, align: .center, .top)
    }

    /// The clocks themselves: one bar per machine when each keeps its own, and
    /// one shared bar when they read the room's.
    private func timeline(y: Double, agreed: Bool) {
        let left = 150.0
        let right = 700.0
        let span = right - left
        let scale = 10.0
        func x(_ time: Double) -> Double { left + span * time / scale }

        if agreed {
            withState {
                stroke(accent)
                strokeWeight(2)
                drawLine(left, y, x(now), y)
            }
            tick(at: left, y: y, strong: true)
            tick(at: x(lateBy), y: y, strong: false)
            tick(at: x(now), y: y, strong: true)
            drawText("both machines", 132, y, size: 13, color: soft, align: .right, .middle)
            drawText("0", left, y + 12, size: 12, color: soft, align: .center, .top)
            drawText("the second machine joins", x(lateBy), y + 12,
                     size: 12, color: soft, align: .center, .top)
            drawText("now, \(seconds(now)) on both", x(now) + 12, y,
                     size: 13, color: ink, align: .left, .middle)
        } else {
            withState {
                stroke(theme.ink(0.5))
                strokeWeight(2)
                drawLine(left, y - 16, x(now), y - 16)
                drawLine(x(lateBy), y + 16, x(now), y + 16)
            }
            tick(at: left, y: y - 16, strong: false)
            tick(at: x(lateBy), y: y + 16, strong: false)
            drawText("machine 1", 132, y - 16, size: 13, color: soft, align: .right, .middle)
            drawText("machine 2", 132, y + 16, size: 13, color: soft, align: .right, .middle)
            drawText(seconds(now), x(now) + 12, y - 16, size: 13, color: ink, align: .left, .middle)
            drawText(seconds(now - lateBy), x(now) + 12, y + 16, size: 13, color: ink, align: .left, .middle)
        }
    }

    private func tick(at x: Double, y: Double, strong: Bool) {
        withState {
            stroke(strong ? accent : theme.ink(0.5))
            strokeWeight(1.5)
            drawLine(x, y - 7, x, y + 7)
        }
    }

    private func seconds(_ value: Double) -> String {
        String(format: "%.1f s", value)
    }
}
