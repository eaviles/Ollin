// figure: frame=0 themed
//
// Guide figure (Chapter 31): transparent output, in the exported pixels. One
// probe, a cluster of translucent lobes and a white ring drawn over
// `background(.clear)`, is rendered once through OllinApp.image(of:), which is
// what `--export` writes as a PNG, and that one render is drawn three times:
// over the checkerboard an image editor shows behind a see-through file, over
// another layer the way a compositing program stacks it, and over black, which
// is what the window paints and what a codec with no alpha channel keeps. The
// panels are the real exported pixels, alpha included.
//
// LeavingTheBackground is declared first on purpose: the loader compiles the
// first `class …: Sketch` it finds, so the probe comes after it.
import Ollin
import OllinDiagram

final class LeavingTheBackground: Sketch {
    override var canvasSize: CanvasSize { .size(880, 440) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    /// The one render, kept so the themed second pass draws the same pixels.
    private var cutout: Image?

    override func setup() { noLoop() }

    override func draw() {
        background(theme.paper)
        textFont(.system)
        if cutout == nil, let exported = OllinApp.image(of: CutoutProbe()) {
            cutout = Image(cgImage: exported)
        }

        let side = 232.0, gap = 44.0, top = 66.0
        let left = (width - side * 3 - gap * 2) / 2
        let backdrops: [(title: String, note: String)] = [
            ("the PNG, in an editor", "the alpha as a checkerboard"),
            ("over another layer", "proRes4444, hevcWithAlpha"),
            ("over black", "the window; h264, hevc, proRes422"),
        ]
        for (i, backdrop) in backdrops.enumerated() {
            let panel = Rectangle(x: left + Double(i) * (side + gap), y: top, width: side, height: side)
            switch i {
            case 0: checkerboard(panel)
            case 1: layer(panel)
            default:
                noStroke()
                fill(.black)
                drawRect(panel)
            }
            if let cutout { drawImage(cutout, in: panel) }
            noFill()
            stroke(theme.border)
            strokeWeight(1.5)
            drawRect(panel)
            noStroke()
            drawText(backdrop.title, panel.center.x, top - 22, size: 16, color: theme.ink, align: .center, .middle)
            drawText(backdrop.note, panel.center.x, top + side + 12, size: 12, color: theme.muted,
                     align: .center, .top)
        }

        diagramCaption("the background left behind: the file keeps the coverage as its alpha",
                       at: 358, theme: theme)
        drawText("a half-covered edge keeps its color at half the coverage: the bytes are premultiplied, as every reader expects",
                 width / 2, 388, size: 13, color: theme.muted, align: .center, .top)
    }

    /// The editor's checkerboard: fixed grays in both themes, since it depicts
    /// what an editor shows rather than the page.
    private func checkerboard(_ r: Rectangle) {
        noStroke()
        let cell = 14.5
        let across = Int((r.width / cell).rounded(.up))
        for y in 0..<across {
            for x in 0..<across {
                fill(Color(white: (x + y) % 2 == 0 ? 0.80 : 0.96))
                let w = min(cell, r.x + r.width - (r.x + Double(x) * cell))
                let h = min(cell, r.y + r.height - (r.y + Double(y) * cell))
                drawRect(r.x + Double(x) * cell, r.y + Double(y) * cell, w, h)
            }
        }
    }

    /// Another layer for the piece to land on: a warm gradient with a few soft
    /// shapes, standing in for a camera feed or a second sketch.
    private func layer(_ r: Rectangle) {
        noStroke()
        let rows = 40
        for i in 0..<rows {
            let u = Double(i) / Double(rows - 1)
            fill(Color(hue: 0.58 - u * 0.1, saturation: 0.55, brightness: 0.35 + u * 0.45))
            drawRect(r.x, r.y + Double(i) * r.height / Double(rows), r.width, r.height / Double(rows) + 1)
        }
        fill(Color(hue: 0.12, saturation: 0.5, brightness: 1, alpha: 0.35))
        drawCircle(r.x + r.width * 0.25, r.y + r.height * 0.7, 46)
        fill(Color(hue: 0.95, saturation: 0.4, brightness: 1, alpha: 0.3))
        drawCircle(r.x + r.width * 0.78, r.y + r.height * 0.3, 60)
    }
}

/// The probe: a ring of translucent lobes and a white ring over a clear
/// canvas, the cluster `Examples/Export/Cutout` draws, held still.
final class CutoutProbe: Sketch {
    override var canvasSize: CanvasSize { .square(464) }

    override func draw() {
        background(.clear)
        noStroke()
        let reach = width * 0.22
        for i in 0..<7 {
            let turn = Double(i) / 7
            let angle = turn * .tau
            let wobble = 1 + 0.25 * sin(turn * .tau * 2)
            let p = center + Vector2(cos(angle), sin(angle)) * (reach * wobble)
            fill(Color(hue: turn, saturation: 0.8, brightness: 0.95, alpha: 0.7))
            drawCircle(center: p, radius: reach * 0.9)
        }
        noFill()
        stroke(.white)
        strokeWeight(5)
        drawCircle(center: center, radius: reach * 2.1)
    }
}
