// figure: frame=0 themed
//
// Guide diagram (Chapter 1): the layout of the examples gallery, so a reader
// opening it for the first time knows what the three panes are and where the
// keyboard focus lives. A drawn diagram rather than a screenshot, because every
// image in this guide has to be reproducible from committed code.
import Ollin

final class Gallery: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x232020) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.45) }
    var faint: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.13) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }
    var wash: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.05) }
    var track: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.16) }

    override func draw() {
        background(paper)

        let window = Rectangle(x: 60, y: 78, width: 760, height: 322)
        let sidebar = Rectangle(x: window.x, y: window.y, width: 196, height: window.height)
        let inspector = Rectangle(x: window.x + window.width - 156, y: window.y,
                                  width: 156, height: window.height)
        let stage = Rectangle(x: sidebar.x + sidebar.width, y: window.y,
                              width: window.width - sidebar.width - inspector.width,
                              height: window.height)

        // The window shell, with a title bar so it reads as an app.
        noStroke()
        fill(faint)
        drawRect(window.x, window.y - 18, window.width, 18)
        fill(soft)
        for dot in 0 ..< 3 { drawCircle(window.x + 11 + Double(dot) * 11, window.y - 9, 3.2) }

        // The example list: a tree of groups, one expanded.
        fill(wash)
        drawRect(sidebar)
        let rows = ["Basic", "Color", "Motion", "  Breathing", "  Springs", "Patterns", "3D"]
        for (index, row) in rows.enumerated() {
            let y = sidebar.y + 16 + Double(index) * 26
            if row == "  Springs" {
                fill(accent.withAlpha(0.16))
                drawRect(sidebar.x + 6, y - 4, sidebar.width - 12, 22, cornerRadius: 4)
            }
            noStroke()
            fill(row.hasPrefix("  ") ? soft : ink)
            textSize(14)
            textAlign(.left, .top)
            // Motion is the expanded group, so it gets the open disclosure mark.
            let mark = row == "Motion" ? "▾ " : "▸ "
            drawText(row.hasPrefix("  ") ? row : mark + row, sidebar.x + 12, y)
        }
        // The filter bar along the bottom of the list.
        fill(Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.08))
        drawRect(sidebar.x, sidebar.y + sidebar.height - 28, sidebar.width, 28)
        fill(soft)
        textSize(13)
        drawText("filter", sidebar.x + 12, sidebar.y + sidebar.height - 22)

        // The stage: the selected sketch, running.
        fill(Color(hex: 0x141821))
        drawRect(stage)
        fill(Color(hex: 0xE4572E))
        drawCircle(center: stage.point(u: 0.5, v: 0.46), radius: 44)
        fill(Color(hex: 0xF2CC8F))
        drawCircle(center: stage.point(u: 0.66, v: 0.66), radius: 20)

        // The inspector: knobs and stats.
        fill(wash)
        drawRect(inspector)
        for index in 0 ..< 4 {
            let y = inspector.y + 26 + Double(index) * 34
            noStroke()
            fill(soft)
            textSize(12)
            textAlign(.left, .top)
            drawText(["bounce", "damping", "count", "tint"][index], inspector.x + 14, y - 14)
            fill(track)
            drawRect(inspector.x + 14, y + 4, inspector.width - 28, 5, cornerRadius: 2.5)
            fill(accent)
            drawCircle(inspector.x + 14 + (inspector.width - 28) * [0.6, 0.3, 0.8, 0.45][index],
                       y + 6.5, 6)
        }

        noFill()
        stroke(ink)
        strokeWeight(2)
        drawRect(window)
        stroke(soft)
        strokeWeight(1)
        drawLine(stage.x, window.y, stage.x, window.y + window.height)
        drawLine(inspector.x, window.y, inspector.x, window.y + window.height)

        // Labels beneath, each under its pane.
        noStroke()
        fill(ink)
        textSize(15)
        textAlign(.center, .top)
        drawText("every example, by folder", sidebar.x + sidebar.width / 2, window.y + window.height + 14)
        drawText("the sketch, running", stage.x + stage.width / 2, window.y + window.height + 14)
        drawText("its knobs", inspector.x + inspector.width / 2, window.y + window.height + 14)

        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        drawText("arrow keys move through the list, because the canvas takes the keyboard only when you click it",
                 width / 2, window.y + window.height + 48)
        drawText("hide the knobs with ⌘/ · type in the filter to find an example by name",
                 width / 2, window.y + window.height + 72)
    }
}
