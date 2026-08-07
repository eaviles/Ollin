import Ollin

/// A year of readings drawn straight out of a CSV file.
///
/// `loadTable` reads the file once in `setup()`; everything the drawing needs
/// comes back out of it by column name. Each month is a bar from its low to its
/// high, painted with a color the file itself carries, over a rain dot sized by
/// the rain column. The vertical scale comes from `numbers(_:)`, which reads a
/// whole column as a series, so the chart fits whatever the file holds rather
/// than a range typed in here.
///
/// The notes are where the format earns its rules. Several hold a comma, one
/// holds quotation marks, and neither breaks a row, because a quoted cell may
/// hold the separator and a doubled quote inside one stands for a single quote.
/// Hover a month to read its note and see it come through intact.
///
/// The readings are invented. What is worth copying is the reading, not the
/// weather.
@main
final class Readings: Sketch {
    private var table: Table?

    /// The value range the bars are drawn against, padded a little so nothing
    /// touches the edge of the plot.
    private var low = 0.0
    private var high = 1.0

    /// The rain range, so the dots below the chart differ by enough to read.
    /// Sized against a fixed formula they all come out nearly the same circle,
    /// which makes a real column look like decoration.
    private var leastRain = 0.0
    private var mostRain = 1.0

    private var plot: Rectangle {
        Rectangle(x: 130, y: 250, width: width - 260, height: height - 490)
    }

    private var plotRight: Double { plot.x + plot.width }
    private var plotBottom: Double { plot.y + plot.height }

    override func setup() {
        table = loadTable(resource: "readings", withExtension: "csv", in: .module)

        // The scale is the file's, not the sketch's: read both columns as
        // series and take the extremes.
        guard let table else { return }
        let highs = table.numbers("high")
        let lows = table.numbers("low")
        guard let top = highs.max(), let bottom = lows.min(), top > bottom else { return }
        let padding = (top - bottom) * 0.18
        high = top + padding
        low = bottom - padding

        let rain = table.numbers("rain")
        if let least = rain.min(), let most = rain.max(), most > least {
            leastRain = least
            mostRain = most
        }
    }

    override func draw() {
        background(Color(hex: 0x14161C))

        guard let table, !table.isEmpty else {
            return drawStatus("readings.csv could not be read", style: .warning)
        }

        drawGuides()

        let hovered = hoveredMonth(in: table)
        for (index, row) in table.enumerated() {
            drawMonth(row, at: index, of: table.count, emphasized: index == hovered)
        }

        drawTitle()
        if let hovered { drawNote(table[hovered]) }
        drawCaption("a year of readings read from a CSV; hover a month for its note")
    }

    // MARK: One month

    private func drawMonth(_ row: Table.Row, at index: Int, of count: Int, emphasized: Bool) {
        let x = plot.x + plot.width * (Double(index) + 0.5) / Double(count)
        let tint = row.color("tint") ?? Color(white: 0.6)

        // The rain dot sits under the bar, sized by how much fell.
        if let rain = row.number("rain") {
            noStroke()
            fill(tint.withAlpha(0.16))
            drawCircle(x, plotBottom + 50, map(rain, leastRain, mostRain, 7, 24))
        }

        // The bar spans low to high. A missing number leaves the month out
        // rather than drawing it at zero, which would read as a real reading.
        guard let top = row.number("high"), let bottom = row.number("low") else { return }
        noFill()
        stroke(emphasized ? tint : tint.withAlpha(0.85))
        strokeWeight(emphasized ? 26 : 20)
        strokeCap(.round)
        drawLine(x, y(for: top), x, y(for: bottom))

        noStroke()
        fill(Color(white: emphasized ? 0.95 : 0.55))
        textFont(OutlineFont.systemMedium)
        textSize(15 * scale)
        textAlign(.center, .top)
        drawText(row["month"] ?? "", x, plotBottom + 84)

        if emphasized {
            fill(.white)
            textSize(13 * scale)
            textAlign(.center, .bottom)
            drawText(format(top), x, y(for: top) - 20)
            textAlign(.center, .top)
            drawText(format(bottom), x, y(for: bottom) + 20)
        }
    }

    // MARK: The frame around it

    /// Faint horizontal rules every five degrees, labeled at the left.
    private func drawGuides() {
        let step = 5.0
        var value = (low / step).rounded(.up) * step
        textFont(OutlineFont.systemMedium)
        textSize(12 * scale)
        while value <= high {
            let lineY = y(for: value)
            // The zero line is the one worth seeing.
            let zero = abs(value) < 0.001
            stroke(Color(white: 1, alpha: zero ? 0.24 : 0.08))
            strokeWeight(1)
            drawLine(plot.x - 40, lineY, plotRight + 20, lineY)

            noStroke()
            fill(Color(white: zero ? 0.7 : 0.4))
            textAlign(.right, .middle)
            drawText(format(value), plot.x - 54, lineY)
            value += step
        }
    }

    private func drawTitle() {
        noStroke()
        fill(.white)
        textFont(OutlineFont.system)
        textSize(30 * scale)
        textAlign(.left, .top)
        drawText("A year of readings", plot.x - 54, 96)

        fill(Color(white: 0.45))
        textFont(OutlineFont.systemMedium)
        textSize(14 * scale)
        drawText("daily high and low, with rainfall below", plot.x - 54, 142)
    }

    /// The hovered month's note, which is the cell holding the commas.
    private func drawNote(_ row: Table.Row) {
        guard let note = row["note"], !note.isEmpty else { return }
        noStroke()
        fill(row.color("tint") ?? .white)
        textFont(OutlineFont.systemMedium)
        textSize(17 * scale)
        textAlign(.right, .top)
        drawText("\u{201C}\(note)\u{201D}", plotRight + 20, 106)
    }

    // MARK: Reading the mouse

    /// Which month the pointer is over, by nearest column.
    private func hoveredMonth(in table: Table) -> Int? {
        guard mouseX >= plot.x, mouseX <= plotRight, !table.isEmpty else { return nil }
        let position = (mouseX - plot.x) / plot.width * Double(table.count)
        return min(table.count - 1, max(0, Int(position)))
    }

    // MARK: Mapping

    private func y(for value: Double) -> Double {
        map(value, low, high, plotBottom, plot.y)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.0f", value)
    }
}
