// figure: frame=0 themed
//
// Guide diagram (Chapter 31): what a take writes down. Four lanes over
// twenty-four frames of a run: the seed, rolled once at frame 0; one clock
// sample per frame, jitter and all; every pointer move and key press, stamped
// with the frame it preceded; the parameter values at the start and each
// change after, on its frame. Under the lanes, five frames of the run and
// the same five replayed. The small picture is a function of the four lanes
// and nothing else, so the two rows are identical by construction, which is
// the claim a take makes: frame N again is frame N.
import Ollin
import OllinDiagram

final class TheTake: Sketch {
    override var canvasSize: CanvasSize { .size(880, 640) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let frames = 24
    let left = 200.0, right = 826.0, labelX = 150.0

    func x(_ frame: Int) -> Double {
        left + Double(frame) * (right - left) / Double(frames - 1)
    }

    // The run, as fixed data. Nothing here rolls dice: the figure has to draw
    // the same picture on every render, the way a take does.
    let firstDrag = 3...9, secondDrag = 14...19
    let keyFrame = 12
    let radiusChange = 7, hueChange = 16

    /// Where the pointer stood on a frame, in unit coordinates of the canvas.
    func pointer(at frame: Int) -> Vector2 {
        let a = Vector2(0.3, 0.66), b = Vector2(0.72, 0.3), c = Vector2(0.48, 0.7)
        if frame < firstDrag.lowerBound { return a }
        if frame <= firstDrag.upperBound {
            return a + (b - a) * (Double(frame - firstDrag.lowerBound) / 6)
        }
        if frame < secondDrag.lowerBound { return b }
        if frame <= secondDrag.upperBound {
            return b + (c - b) * (Double(frame - secondDrag.lowerBound) / 5)
        }
        return c
    }

    func radius(at frame: Int) -> Double { frame >= radiusChange ? 200 : 120 }
    func hue(at frame: Int) -> Double { frame >= hueChange ? 0.31 : 0.58 }

    /// The clock sample a frame carried, in milliseconds: sixty a second, with
    /// the jitter a live display has, written as a fixed wobble.
    func delta(at frame: Int) -> Double {
        16.7 + sin(Double(frame) * 2.1) * 1.6 + cos(Double(frame) * 0.7) * 0.9
    }

    override func draw() {
        background(theme.paper)
        textFont(.system)

        let seedY = 66.0, clockY = 142.0, pointerY = 222.0, paramY = 300.0, axisY = 352.0

        // The frame grid, faint, so every lane reads against the same frames.
        stroke(theme.ink(0.08))
        strokeWeight(1)
        for k in 0..<frames { drawLine(x(k), seedY - 22, x(k), axisY) }

        // The seed: one number, once.
        laneLabel("seed", at: seedY)
        chip("variation 48213", at: x(0), y: seedY)
        note("rolled once, at frame 0, and written once", at: x(0) + 150, y: seedY, middle: true)

        // The clock: a sample per frame, each a little different.
        laneLabel("clock", at: clockY)
        for k in 0..<frames {
            let h = delta(at: k) * 2.4
            noStroke()
            fill(theme.ink(0.35))
            drawRect(x(k) - 3, clockY + 22 - h, 6, h)
        }
        note("one sample per frame: time, deltaTime, and the rate, jitter included",
             at: x(0), y: clockY + 34, middle: false)

        // The pointer: two drags, and a key press between them.
        laneLabel("pointer", at: pointerY)
        var previous: Vector2?
        for k in 0..<frames {
            let moved = firstDrag.contains(k) || secondDrag.contains(k)
            let p = Vector2(x(k), pointerY + (pointer(at: k).y - 0.5) * 36)
            if moved {
                if let previous {
                    stroke(theme.accent(0.5))
                    strokeWeight(1.5)
                    drawLine(previous, p)
                }
                noStroke()
                fill(theme.accent)
                drawCircle(p.x, p.y, 4)
                previous = p
            } else {
                previous = nil
            }
        }
        noFill()
        stroke(theme.ink)
        strokeWeight(1.5)
        drawRect(x(keyFrame) - 9, pointerY - 9, 18, 18, cornerRadius: 3)
        noStroke()
        drawText("r", x(keyFrame), pointerY + 1, size: 12, color: theme.ink, align: .center, .middle)
        note("every pointer move and key press, stamped with the frame it preceded",
             at: x(0), y: pointerY + 34, middle: false)

        // The parameters: where they started, and each change on its frame.
        laneLabel("parameters", at: paramY)
        chip("radius 120 · hue 0.58", at: x(0), y: paramY)
        chip("radius → 200", at: x(radiusChange), y: paramY)
        chip("hue → 0.31", at: x(hueChange), y: paramY)
        note("the values at the start, and every change after, on its frame",
             at: x(0), y: paramY + 34, middle: false)

        // The axis of frames.
        stroke(theme.ink(0.5))
        strokeWeight(1)
        drawLine(x(0), axisY, x(frames - 1), axisY)
        for k in 0..<frames { drawLine(x(k), axisY - 4, x(k), axisY + 4) }
        drawText("frame 0", x(0), axisY + 8, size: 12, color: theme.muted, align: .center, .top)
        drawText("23", x(frames - 1), axisY + 8, size: 12, color: theme.muted, align: .center, .top)
        drawText("twenty-four frames of the run, one per refresh", (x(0) + x(frames - 1)) / 2,
                 axisY + 8, size: 12, color: theme.muted, align: .center, .top)

        // The run and its replay: the same five frames, twice.
        let shown = [0, 6, 12, 18, 23]
        let nightY = 404.0, againY = 484.0, side = 64.0
        laneLabel("the night", at: nightY + side / 2)
        laneLabel("again", at: againY + side / 2)
        for k in shown {
            thumbnail(frame: k, at: Vector2(x(k) - side / 2, nightY), side: side)
            thumbnail(frame: k, at: Vector2(x(k) - side / 2, againY), side: side)
            drawText("frame \(k)", x(k), againY + side + 6, size: 12, color: theme.muted,
                     align: .center, .top)
        }

        diagramCaption("frame N of the replay is frame N of the night, pixel for pixel",
                       at: 580, theme: theme)
        drawText("a camera, a microphone, OSC, MIDI, and the wall clock stay live: a take drives the sketch, not the room",
                 width / 2, 608, size: 13, color: theme.muted, align: .center, .top)
    }

    /// One frame of the run, drawn from the lanes alone: the pointer's place,
    /// the radius and hue the parameters held.
    private func thumbnail(frame k: Int, at origin: Vector2, side: Double) {
        noStroke()
        fill(Color(hex: 0x14131A))
        drawRect(origin.x, origin.y, side, side, cornerRadius: 6)
        let p = origin + pointer(at: k) * side
        fill(Color(hue: hue(at: k), saturation: 0.7, brightness: 0.95))
        drawCircle(p.x, p.y, radius(at: k) / 12)
        noFill()
        stroke(theme.border)
        strokeWeight(1)
        drawRect(origin.x, origin.y, side, side, cornerRadius: 6)
    }

    private func laneLabel(_ text: String, at y: Double) {
        noStroke()
        drawText(text, labelX, y, size: 16, color: theme.ink, align: .right, .middle)
    }

    private func note(_ text: String, at x: Double, y: Double, middle: Bool) {
        noStroke()
        drawText(text, x, y, size: 12, color: theme.muted, align: .left, middle ? .middle : .top)
    }

    private func chip(_ text: String, at x: Double, y: Double) {
        textSize(13)
        let w = textWidth(text) + 16
        fill(theme.accent(0.12))
        stroke(theme.accent)
        strokeWeight(1.5)
        drawRect(x - 8, y - 12, w, 24, cornerRadius: 6)
        noStroke()
        drawText(text, x, y + 1, size: 13, color: theme.ink, align: .left, .middle)
    }
}
