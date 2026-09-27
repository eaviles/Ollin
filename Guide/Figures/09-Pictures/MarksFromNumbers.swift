// figure: frame=0 themed
//
// Guide diagram (Chapter 9): one small table drawn three ways. Twelve rows of
// monthly readings, rain and a daily high, written out here so the figure needs
// no asset. Left, one bar per row, its length mapped from zero to the column's
// largest value. Middle, one dot per row placed by two columns at once. Right,
// one line through the rows in their own order, its height mapped from the
// column's smallest value to its largest. The same `Table`, the same `map`
// call from Chapter 3, and three different marks.
import Ollin
import OllinDiagram

final class MarksFromNumbers: Sketch {
    override var canvasSize: CanvasSize { .size(880, 430) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }
    var soft: Color { theme.ink(0.12) }
    var accent: Color { theme.accent }

    /// A year of readings. In a sketch this is
    /// `loadTable(resource:withExtension:in:)` instead, and the drawing code
    /// is unchanged.
    let source = """
        month,rain,high
        Jan,78,9
        Feb,64,10
        Mar,52,13
        Apr,41,17
        May,33,21
        Jun,18,26
        Jul,9,29
        Aug,12,29
        Sep,30,25
        Oct,55,19
        Nov,80,13
        Dec,86,10
        """

    var table: Table?

    override func setup() {
        table = try? Table(text: source)
    }

    override func draw() {
        background(paper)
        guard let table else { return }

        let left = Rectangle(x: 40, y: 70, width: 250, height: 250)
        let middle = Rectangle(x: 315, y: 70, width: 250, height: 250)
        let right = Rectangle(x: 590, y: 70, width: 250, height: 250)

        drawBars(table, in: left)
        drawDots(table, in: middle)
        drawLine(table, in: right)

        label("one number, one bar: the length starts at zero", at: left)
        label("two numbers, one dot: the columns place it", at: middle)
        label("the rows in order, one line: the height is the number", at: right)

        noStroke()
        fill(ink)
        textFont(OutlineFont.systemMedium)
        textSize(19)
        textAlign(.center, .top)
        drawText("the range comes from the column, and the mark is yours", width / 2, 386)
    }

    /// One bar per row. A bar's length is mapped from zero, so bars compare.
    private func drawBars(_ table: Table, in area: Rectangle) {
        panel(area, title: "rain, mm")
        let rain = table.numbers("rain")
        guard let most = rain.max() else { return }
        let slot = area.width / Double(table.count)

        noStroke()
        for (index, row) in table.enumerated() {
            let value = row.number("rain") ?? 0
            let height = map(value, 0, most, 0, area.height - 30)
            let x = area.x + Double(index) * slot + slot * 0.2
            fill(accent)
            drawRect(corner: Vector2(x: x, y: area.y + area.height - height),
                     width: slot * 0.6, height: height)
        }
    }

    /// One dot per row, placed by two columns at once.
    private func drawDots(_ table: Table, in area: Rectangle) {
        panel(area, title: "rain across, high up")
        let rain = table.numbers("rain")
        let high = table.numbers("high")
        guard let mostRain = rain.max(), let lowest = high.min(), let highest = high.max() else { return }

        noStroke()
        for row in table {
            guard let r = row.number("rain"), let h = row.number("high") else { continue }
            let x = map(r, 0, mostRain, area.x + 20, area.x + area.width - 20)
            let y = map(h, lowest, highest, area.y + area.height - 20, area.y + 20)
            fill(accent)
            drawCircle(center: Vector2(x: x, y: y), radius: 7)
            fill(faint)
            textFont(OutlineFont.systemMedium)
            textSize(11)
            textAlign(.left, .middle)
            drawText(row["month"] ?? "", x + 11, y)
        }
    }

    /// One line through the rows in their own order.
    private func drawLine(_ table: Table, in area: Rectangle) {
        panel(area, title: "high, °C, month by month")
        let high = table.numbers("high")
        guard let lowest = high.min(), let highest = high.max() else { return }
        let step = area.width / Double(max(table.count - 1, 1))

        var points: [Vector2] = []
        for (index, row) in table.enumerated() {
            let value = row.number("high") ?? lowest
            let x = area.x + Double(index) * step
            let y = map(value, lowest, highest, area.y + area.height - 20, area.y + 20)
            points.append(Vector2(x: x, y: y))
        }

        noFill()
        stroke(accent)
        strokeWeight(3)
        strokeJoin(.round)
        drawPolyline(points)

        noStroke()
        fill(accent)
        for point in points { drawCircle(center: point, radius: 4) }
    }

    private func panel(_ area: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(1.5)
        drawRect(area)
        noStroke()
        fill(faint)
        textFont(OutlineFont.systemMedium)
        textSize(13)
        textAlign(.left, .bottom)
        drawText(title, area.x, area.y - 10)
    }

    private func label(_ text: String, at area: Rectangle) {
        noStroke()
        fill(faint)
        textFont(OutlineFont.systemMedium)
        textSize(12)
        textAlign(.left, .top)
        drawText(text, area.x, area.y + area.height + 12)
    }
}
