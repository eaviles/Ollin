// figure: frame=0 probe themed
//
// Guide diagram (Chapter 38): every way a sketch leaves the machine. Files on
// one side (still, sequence, video, GIF, SVG), live feeds on the other (the
// window, fullscreen on a projector; Syphon into other apps; the virtual camera
// into anything with a webcam menu), all from the same draw() code.
import Ollin
import OllinDiagram

final class ExportMap: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }
    var soft: Color { theme.ink(0.6) }
    var accent: Color { theme.accent }

    // Wide enough for the longest detail line, the virtual camera's.
    let nodeWidth = 230.0
    let fileX = 30.0
    let feedX = 620.0

    override func draw() {
        background(paper)

        // The sketch, in the middle.
        let hub = Rectangle(x: 342, y: 220, width: 196, height: 92)
        fill(darkTheme ? Color(hex: 0x2A2724) : .white)
        stroke(accent)
        strokeWeight(2.5)
        drawRect(hub, cornerRadius: 12)
        noStroke()
        fill(ink)
        textSize(20)
        textAlign(.center, .bottom)
        drawText("your sketch", hub.center.x, hub.center.y + 2)
        fill(soft)
        textSize(13)
        textAlign(.center, .top)
        drawText("one draw(), many outputs", hub.center.x, hub.center.y + 8)

        // Files, on the left.
        columnTitle("files", x: fileX + nodeWidth / 2)
        file(y: 105, name: "still", detail: "--export frame.png")
        file(y: 175, name: "sequence", detail: "--export-sequence, for an edit")
        file(y: 245, name: "video", detail: "--export-video clip.mp4")
        file(y: 315, name: "GIF", detail: "--export-gif loop.gif")
        file(y: 385, name: "SVG", detail: "--export-svg, for a plotter")

        // Live feeds, on the right.
        columnTitle("live feeds", x: feedX + nodeWidth / 2)
        feed(y: 140, name: "the window", detail: "fullscreen on a projector")
        feed(y: 230, name: "Syphon", detail: "into VJ apps, in real time")
        feed(y: 320, name: "virtual camera", detail: "into anything with a webcam menu")

        noStroke()
        fill(soft)
        textSize(19)
        textAlign(.center, .top)
        drawText("every file export draws the sketch on the same fixed clock",
                 width / 2, 505)
    }

    func file(y: Double, name: String, detail: String) {
        node(x: fileX, y: y, name: name, detail: detail)
        arrow(from: Vector2(340, 266), to: Vector2(fileX + nodeWidth + 2, y + 26))
    }

    func feed(y: Double, name: String, detail: String) {
        node(x: feedX, y: y, name: name, detail: detail)
        arrow(from: Vector2(540, 266), to: Vector2(feedX - 2, y + 26))
    }

    func node(x: Double, y: Double, name: String, detail: String) {
        fill(darkTheme ? Color(hex: 0x2A2724) : .white)
        stroke(faint)
        strokeWeight(1.5)
        drawRect(x, y, nodeWidth, 52, cornerRadius: 9)
        noStroke()
        fill(ink)
        textSize(18)
        textAlign(.center, .bottom)
        drawText(name, x + nodeWidth / 2, y + 27)
        fill(soft)
        textSize(12)
        textAlign(.center, .top)
        drawText(detail, x + nodeWidth / 2, y + 30)
    }

    func columnTitle(_ text: String, x: Double) {
        noStroke()
        fill(soft)
        textSize(16)
        textAlign(.center, .bottom)
        drawText(text, x, 92)
    }

    func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(accent)
        strokeWeight(2.5)
        drawLine(a, b - dir * 10)
        noStroke()
        fill(accent)
        drawPolygon([b, b - dir * 13 + dir.perpendicular * 5,
                        b - dir * 13 - dir.perpendicular * 5])
    }
}
