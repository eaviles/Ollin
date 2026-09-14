// figure: frame=0 themed
//
// Guide diagram (Chapter 31): what a web page carries. One probe, a ring of
// circles breathing over a four-second lap with a radius and two colors as
// parameters, stands in three places: the frame the Mac renders (its real
// exported pixels, through OllinApp.image(of:)), the records the exporter
// writes down instead of pixels (what is stored once, what moves and how the
// moving part is kept), and the page, drawn as a diagram of what a browser
// shows: the canvas and the controls the probe earned. The page's weight is
// measured here, by asking OllinApp.web(of:) for the page itself and counting
// its bytes. The runner has no browser, so the canvas on the page is depicted
// from the same render; what it stands for is the page drawing the records
// with the framework's own shader carried to GLSL.
//
// PageFromRecords is declared first on purpose: the loader compiles the first
// `class …: Sketch` it finds, so the probe comes after it.
import Ollin
import OllinDiagram

final class PageFromRecords: Sketch {
    override var canvasSize: CanvasSize { .size(880, 490) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The probe's frame, and the page's weight in kilobytes, made once and kept
    /// so the themed second pass draws from the same numbers.
    private var frame: Image?
    private var pageKB: Int?

    override func setup() { noLoop() }

    override func draw() {
        background(theme.paper)
        textFont(.system)
        if frame == nil {
            if let exported = OllinApp.image(of: RingProbe(), frame: 30, fps: 30) {
                frame = Image(cgImage: exported)
            }
            let frames = FrameRate(30).frames(in: RingProbe().loopDuration ?? 4)
            if let page = try? OllinApp.web(of: RingProbe(), frames: frames, fps: 30) {
                pageKB = page.utf8.count / 1024
            }
        }

        let top = 92.0, side = 200.0
        let macPanel = Rectangle(x: 40, y: top, width: side, height: side)
        let records = Rectangle(x: 300, y: top - 8, width: 250, height: 236)
        let page = Rectangle(x: 610, y: top - 26, width: 230, height: 300)

        // The frame on the Mac: the probe's real pixels.
        columnTitle("on the Mac", over: macPanel)
        if let frame { drawImage(frame, in: macPanel) }
        noFill()
        stroke(theme.border)
        strokeWeight(1.5)
        drawRect(macPanel)
        note("the frame --export writes", under: macPanel)

        // The records: what the exporter writes down instead.
        columnTitle("what the recorder writes", over: records)
        fill(theme.card)
        stroke(theme.border)
        strokeWeight(1)
        drawRect(records, cornerRadius: 8)
        noStroke()
        let x = records.x + 14
        var y = records.y + 22
        line("12 circles a frame, 30 numbers each", at: x, y: y, strong: true); y += 26
        line("stored once, the base:", at: x, y: y, strong: false); y += 18
        line("fill, stroke, weight, the transform", at: x, y: y, strong: true); y += 26
        line("moving, a column each:", at: x, y: y, strong: false); y += 18
        line("x, y, radius", at: x, y: y, strong: true)
        sineGlyph(at: Vector2(x + 96, y), width: 60)
        y += 18
        line("a lap, so fitted to its sines", at: x, y: y, strong: false); y += 26
        line("probed, and wired as controls:", at: x, y: y, strong: false); y += 18
        line("radius, ink, paper", at: x, y: y, strong: true); y += 26
        line("120 frames at 30 fps, one lap", at: x, y: y, strong: false)

        // The page: the canvas, and the controls under it.
        columnTitle("the page", over: page)
        browser(page)
        let canvas = Rectangle(x: page.x + 15, y: page.y + 34, width: side, height: side)
        if let frame { drawImage(frame, in: canvas) }
        var cy = canvas.y + canvas.height + 16
        control("radius", kind: .slider, at: Vector2(canvas.x, cy)); cy += 22
        control("ink", kind: .well(Color(hex: 0x1F2328)), at: Vector2(canvas.x, cy))
        control("paper", kind: .well(Color(hex: 0xF3EFE6)), at: Vector2(canvas.x + 100, cy))
        note("drawn from the records, in GLSL", under: page)

        // The arrows between the three, each with its two-line label above.
        let mid = top + side / 2
        arrow(from: Vector2(macPanel.x + macPanel.width + 10, mid), to: Vector2(records.x - 8, mid))
        let firstGap = (macPanel.x + macPanel.width + records.x) / 2
        drawText("records,", firstGap, mid - 26, size: 11.5, color: theme.muted, align: .center, .middle)
        drawText("not pixels", firstGap, mid - 13, size: 11.5, color: theme.muted, align: .center, .middle)
        arrow(from: Vector2(records.x + records.width + 10, mid), to: Vector2(page.x - 8, mid))
        let secondGap = (records.x + records.width + page.x) / 2
        drawText("one file,", secondGap, mid - 26, size: 11.5, color: theme.muted, align: .center, .middle)
        drawText(pageKB.map { "\($0) KB" } ?? "one page", secondGap, mid - 13, size: 11.5,
                 color: theme.muted, align: .center, .middle)

        diagramCaption("the page carries the records, fitted, and the shader that draws them",
                       at: 418, theme: theme)
        drawText("most of that weight is the player and its shaders; a shape the page cannot carry stops the export and names the call",
                 width / 2, 448, size: 13, color: theme.muted, align: .center, .top)
    }

    private enum ControlKind { case slider, well(Color) }

    private func control(_ name: String, kind: ControlKind, at p: Vector2) {
        noStroke()
        drawText(name, p.x, p.y, size: 11, color: theme.muted, align: .left, .middle)
        switch kind {
        case .slider:
            stroke(theme.border)
            strokeWeight(3)
            drawLine(p.x + 50, p.y, p.x + 200, p.y)
            noStroke()
            fill(theme.accent)
            drawCircle(p.x + 106, p.y, 5)
        case .well(let color):
            fill(color)
            stroke(theme.border)
            strokeWeight(1)
            drawRect(p.x + 38, p.y - 8, 28, 16, cornerRadius: 4)
        }
    }

    private func browser(_ r: Rectangle) {
        fill(theme.card)
        stroke(theme.border)
        strokeWeight(1.5)
        drawRect(r, cornerRadius: 10)
        stroke(theme.border)
        strokeWeight(1)
        drawLine(r.x, r.y + 22, r.x + r.width, r.y + 22)
        noStroke()
        for i in 0..<3 {
            fill(theme.ink(0.25))
            drawCircle(r.x + 14 + Double(i) * 12, r.y + 11, 3.5)
        }
    }

    private func sineGlyph(at p: Vector2, width: Double) {
        noFill()
        stroke(theme.accent)
        strokeWeight(1.5)
        var points: [Vector2] = []
        for i in 0...30 {
            let u = Double(i) / 30
            points.append(Vector2(p.x + u * width, p.y - sin(u * .tau * 2) * 5))
        }
        drawPolyline(points)
    }

    private func line(_ text: String, at x: Double, y: Double, strong: Bool) {
        drawText(text, x, y, size: strong ? 13 : 11.5, color: strong ? theme.ink : theme.muted,
                 align: .left, .middle)
    }

    private func columnTitle(_ text: String, over r: Rectangle) {
        noStroke()
        drawText(text, r.center.x, r.y - 20, size: 16, color: theme.ink, align: .center, .middle)
    }

    private func note(_ text: String, under r: Rectangle) {
        noStroke()
        drawText(text, r.center.x, r.y + r.height + 12, size: 12, color: theme.muted, align: .center, .top)
    }

    private func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(theme.accent)
        strokeWeight(2)
        drawLine(a, b - dir * 9)
        noStroke()
        fill(theme.accent)
        drawPolygon([b, b - dir * 11 + dir.perpendicular * 4.5, b - dir * 11 - dir.perpendicular * 4.5])
    }
}

/// The probe: a ring of circles breathing over one lap, with the numbers a
/// page can take hold of as parameters.
final class RingProbe: Sketch {
    override var canvasSize: CanvasSize { .square(400) }
    override var loopDuration: Double? { 4 }

    @Param("Radius", 20 ... 90) var radius = 60.0
    @Param("Ink") var ink = Color(hex: 0x1F2328)
    @Param("Paper") var paper = Color(hex: 0xF3EFE6)

    override func draw() {
        background(paper)
        noFill()
        stroke(ink)
        strokeWeight(3)
        let phase = time / (loopDuration ?? 4) * .tau
        for i in 0..<12 {
            let angle = Double(i) / 12 * .tau
            let reach = 120 + sin(phase + angle * 2) * 22
            let p = center + Vector2(cos(angle), sin(angle)) * reach
            drawCircle(center: p, radius: radius * (0.7 + 0.3 * cos(phase + angle)))
        }
    }
}
