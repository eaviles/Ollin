// figure: frame=0 themed
//
// Guide diagram (Chapter 29): a room is what it does to a click, and a room
// drawn from a rule is as much a room as a recorded one. Three panels, each
// a room's answer to one click drawn as a waveform: fading noise three
// seconds long with its top end going first, the same noise run backward so
// it swells toward the end, and a dropped ball, a burst on every bounce with
// the gaps closing by a fixed ratio. Every waveform is read from the shipped
// value, so the picture is what the reverb convolves with.
import Ollin
import OllinDiagram
import OllinAudio

final class Rooms: Sketch {
    override var canvasSize: CanvasSize { .size(880, 620) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.5) }
    var faint: Color { theme.ink(0.16) }
    var accent: Color { theme.accent }

    /// The three rooms, drawn once.
    lazy var rooms: [(title: String, room: ImpulseResponse, accented: Bool)] = {
        let hall = ImpulseResponse.decay(seconds: 3, damping: 0.6, seed: 2)
        let ball = ImpulseResponse(seconds: 1.8, seed: 5) { time, noise in
            var sum = 0.0
            var at = 0.0, gap = 0.42
            for bounce in 0..<14 where time >= at {
                sum += exp(-(time - at) / 0.02) * pow(0.72, Double(bounce))
                at += gap
                gap *= 0.72
            }
            return sum * (0.5 + 0.5 * noise)
        }
        return [
            ("fading noise: a hall three seconds long, its top end going first", hall, false),
            ("the same noise run backward: the room swells toward the end", hall.reversed(), true),
            ("a dropped ball: a burst on every bounce, the gaps closing in", ball, false),
        ]
    }()

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let left = 60.0, panelWidth = 760.0, panelHeight = 140.0, gap = 34.0
        for (index, entry) in rooms.enumerated() {
            let panel = Rectangle(x: left, y: 36 + Double(index) * (panelHeight + gap),
                                  width: panelWidth, height: panelHeight)
            diagramFrame(panel, title: entry.title, theme: theme)
            drawRoom(entry.room, in: panel, color: entry.accented ? accent : ink)

            // The times sit inside the panel's bottom corners, clear of the
            // next panel's title.
            noStroke()
            fill(soft)
            textSize(11)
            textAlign(.left, .bottom)
            drawText("0 s", panel.x + 8, panel.bottomRight.y - 5)
            textAlign(.right, .bottom)
            drawText(String(format: "%.1f s", entry.room.duration), panel.topRight.x - 8, panel.bottomRight.y - 5)
        }

        diagramCaption("three rooms, each drawn as its answer to one click", at: 588, theme: theme)
    }

    /// The room's answer to a click: the peak of one side over each column.
    private func drawRoom(_ room: ImpulseResponse, in panel: Rectangle, color: Color) {
        let side = room.channels[0]
        let count = 380
        var columns = (0..<count).map { column -> Double in
            let from = side.count * column / count
            let to = max(from + 1, side.count * (column + 1) / count)
            return Double(side[from..<to].reduce(Float(0)) { max($0, abs($1)) })
        }
        let peak = columns.max() ?? 1
        if peak > 0 { columns = columns.map { $0 / peak } }

        let inset = 14.0
        let middle = panel.center.y + 6
        let span = panel.width - inset * 2
        stroke(faint)
        strokeWeight(1)
        drawLine(panel.x + inset, middle, panel.topRight.x - inset, middle)

        stroke(color)
        strokeWeight(span / Double(count) * 0.7)
        for (index, value) in columns.enumerated() {
            let x = panel.x + inset + span * (Double(index) + 0.5) / Double(count)
            let reach = value * (panel.height * 0.5 - 22)
            drawLine(x, middle - reach, x, middle + reach)
        }
    }
}
