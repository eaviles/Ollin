// figure: frame=0 themed
//
// Guide figure (Chapter 9): one bundled picture, three shapes. The city as
// SamplePhoto.city.load() hands it over, 1600 pixels square, with the credit
// it carries; the 300-pixel working copy resized(width:height:) makes, drawn
// at the same scale and then up close; and the widest 3:2 piece
// cropped(toAspect:) takes out of it, scaling nothing, over the square it
// came from. The pictures keep their own colors in both themes; only the
// paper and the ink around them change.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class WorkingCopy: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    private var full = Image(width: 1, height: 1)
    private var small = Image(width: 1, height: 1)
    private var wide = Image(width: 1, height: 1)
    private var credit = ""

    override func setup() {
        full = SamplePhoto.city.load()
        small = full.resized(width: 300, height: 300)
        wide = full.cropped(toAspect: 3.0 / 2)
        credit = SamplePhoto.city.credit.line
    }

    override func draw() {
        background(theme.paper)
        textFont(.system)
        let top = 70.0

        // As loaded, with the credit it carries.
        let a = Rectangle(x: 40, y: top, width: 300, height: 300)
        drawImage(full, in: a)
        frame(a)
        heading("SamplePhoto.city.load()", over: a)
        label("\(full.width) × \(full.height), as loaded", under: a, line: 0)
        label("with the credit it carries", under: a, line: 1)

        // The working copy, at the same scale and then up close.
        let scale = a.width / Double(full.width)
        let column = Rectangle(x: 390, y: top, width: 150, height: 300)
        let tiny = Rectangle(x: column.x, y: top,
                             width: Double(small.width) * scale, height: Double(small.height) * scale)
        drawImage(small, in: tiny)
        frame(tiny)
        noStroke()
        drawText("at the same scale", column.center.x, tiny.y + tiny.height + 12, size: 12,
                 color: theme.muted, align: .center, .middle)
        let close = Rectangle(x: column.x, y: top + tiny.height + 34, width: 150, height: 150)
        drawImage(small, in: close)
        frame(close)
        noStroke()
        drawText("up close", column.center.x, close.y + close.height + 12, size: 12,
                 color: theme.muted, align: .center, .middle)
        heading(".resized(width: 300, height: 300)", over: column)
        label("\(small.width) × \(small.height), the working copy", under: column, line: 0)
        let fewer = (full.width * full.height) / (small.width * small.height)
        label("\(fewer) times fewer pixels to read", under: column, line: 1)

        // The wide piece, over the square it was cut from.
        let c = Rectangle(x: 560, y: top, width: 300, height: 300)
        withState {
            tint(Color(white: 1, alpha: 0.28))
            drawImage(full, in: c)
        }
        let bandH = c.width * Double(wide.height) / Double(wide.width)
        let band = Rectangle(x: c.x, y: c.y + (c.height - bandH) / 2, width: c.width, height: bandH)
        drawImage(wide, in: band)
        noFill()
        stroke(theme.accent)
        strokeWeight(2)
        drawRect(band)
        frame(c)
        heading(".cropped(toAspect: 3.0 / 2)", over: c)
        label("\(wide.width) × \(wide.height), the largest 3:2 piece", under: c, line: 0)
        label("scaling nothing", under: c, line: 1)

        diagramCaption("one picture, three shapes: as loaded, the small copy, and the wide piece",
                       at: 494, theme: theme)
        noStroke()
        drawText("the credit, read from the value: " + credit,
                 width / 2, 522, size: 13, color: theme.muted, align: .center, .top)
    }

    private func frame(_ rect: Rectangle) {
        noFill()
        stroke(theme.border)
        strokeWeight(1.5)
        drawRect(rect)
    }

    private func heading(_ text: String, over rect: Rectangle) {
        noStroke()
        drawText(text, rect.center.x, rect.y - 18, size: 13, color: theme.ink, align: .center, .middle)
    }

    private func label(_ text: String, under rect: Rectangle, line: Int) {
        noStroke()
        drawText(text, rect.center.x, rect.y + rect.height + 18 + Double(line) * 20,
                 size: line == 0 ? 14 : 12, color: line == 0 ? theme.ink : theme.muted,
                 align: .center, .middle)
    }
}
