// figure: frame=0 probe themed
//
// Guide diagram (Chapter 9): a file as material. Left, the bytes of a small
// CSV, shown as they sit on disk. Right, what `Table` makes of them: one bar
// per row, sized by a number column and painted with a color the file itself
// carries. The third row is the one to look at, in both panels.
import Ollin
import OllinDiagram

final class DataAsMaterial: Sketch {
    override var canvasSize: CanvasSize { .size(880, 430) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }

    /// The file, written out here so the figure needs no asset. In a sketch
    /// this is `loadTable(resource:withExtension:in:)` instead, and everything
    /// below is unchanged.
    let source = """
        city,visits,tint
        Oslo,54,#E8590C
        "Bath, Maine",47,#0CA678
        Kyoto,68,#7048E8
        Lima,39,#D6336C
        """

    var table: Table?

    override func setup() {
        table = Table(text: source)
    }

    override func draw() {
        background(paper)
        guard let table else { return }

        drawFile()
        drawChart(table)
        drawArrow()
    }

    /// The bytes, in the pixel font, so the quotes and commas are countable.
    private func drawFile() {
        noStroke()
        fill(faint)
        textFont(OutlineFont.systemMedium)
        textSize(13)
        textAlign(.left, .baseline)
        drawText("the file", 60, 84)

        textFont(BitmapFont.builtin)
        textSize(16)
        for (index, line) in source.split(separator: "\n").enumerated() {
            let y = 130 + Double(index) * 30
            // The header, and the row whose first cell is quoted.
            let notable = index == 0 || line.hasPrefix("\"")
            fill(notable ? ink : faint)
            drawText(String(line), 60, y)
        }

        fill(faint)
        textFont(OutlineFont.systemMedium)
        textSize(12)
        drawText("the quotes hold a comma inside one cell", 60, 358)
    }

    /// What the table makes of it: a bar per row, read by column name.
    private func drawChart(_ table: Table) {
        noStroke()
        fill(faint)
        textFont(OutlineFont.systemMedium)
        textSize(13)
        textAlign(.left, .baseline)
        drawText("the drawing", 500, 84)

        // The scale comes from the column, not from a number typed here.
        let visits = table.numbers("visits")
        guard let most = visits.max(), most > 0 else { return }

        for (index, row) in table.enumerated() {
            let y = 118 + Double(index) * 52
            let value = row.number("visits") ?? 0
            let length = value / most * 250

            fill(row.color("tint") ?? faint)
            drawRect(corner: Vector2(500, y), width: length, height: 22)

            fill(ink)
            textFont(OutlineFont.systemMedium)
            textSize(13)
            textAlign(.left, .middle)
            // The label arrives without its quotes, comma intact.
            drawText(row["city"] ?? "", 500, y + 36)

            fill(faint)
            textAlign(.left, .middle)
            drawText("\(Int(value))", 500 + length + 10, y + 11)
        }

        fill(faint)
        textSize(12)
        textAlign(.left, .baseline)
        drawText("number(\"visits\") sizes it, color(\"tint\") paints it", 500, 358)
    }

    /// The one turns into the other.
    private func drawArrow() {
        stroke(faint)
        strokeWeight(1.5)
        drawLine(420, 220, 470, 220)
        drawLine(462, 214, 470, 220)
        drawLine(462, 226, 470, 220)

        noStroke()
        fill(faint)
        textFont(OutlineFont.systemMedium)
        textSize(12)
        textAlign(.center, .baseline)
        drawText("Table", 445, 208)
    }
}
