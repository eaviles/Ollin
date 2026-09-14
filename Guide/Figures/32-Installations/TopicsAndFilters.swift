// figure: frame=0 themed
//
// Guide diagram (Chapter 32): which topics a subscription actually gets. Five
// topics a house publishes across the top, four filters down the side, and a
// mark where the one reaches the other. Every mark is read from the shipped
// rule rather than drawn by hand, so the figure cannot disagree with the code.
// The point of the figure: the two surprises, `#` covering its own parent and
// no wildcard reaching the broker's own `$` namespace.
import Ollin
import OllinDiagram
import OllinMQTT

final class TopicsAndFilters: Sketch {
    override var canvasSize: CanvasSize { .size(880, 600) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    let topics = ["home/kitchen/temperature", "home/hall/humidity",
                  "home/porch", "home/lamp/state", "$SYS/broker/uptime"]
    let filters = ["home/+/temperature", "home/porch/#", "home/#", "#"]

    /// The note under a filter, where the row is worth a sentence.
    let notes: [String: String] = [
        "home/porch/#": "a trailing # covers its own parent",
        "#": "even everything stops at the $ namespace"
    ]

    override func draw() {
        let theme = self.theme
        background(theme.paper)
        noStroke()

        let left = 300.0
        let top = 262.0
        let columnWidth = (880.0 - left - 40) / Double(topics.count)
        let rowHeight = 74.0

        // The rule, said once, above everything.
        textAlign(.left, .top)
        textSize(15)
        fill(theme.ink)
        drawText("+ stands for one level, # for every level from there down", 40, 24)
        textSize(12)
        fill(theme.muted)
        drawText("a filled mark is a message this subscription receives", 40, 48)

        // The topics, written up the page so a long one has room.
        textSize(12)
        textAlign(.left, .middle)
        for (index, topic) in topics.enumerated() {
            let x = left + columnWidth * (Double(index) + 0.5)
            withState {
                translate(x, top - 16)
                rotate(-.pi / 2)
                fill(topic.hasPrefix("$") ? theme.accent : theme.ink)
                drawText(topic, 0, 0)
            }
        }

        // One row per filter: the filter itself, then a mark per topic.
        for (row, filter) in filters.enumerated() {
            let y = top + rowHeight * (Double(row) + 0.5)
            fill(row % 2 == 0 ? theme.card : theme.paper)
            drawRect(40, y - rowHeight / 2, 880 - 80, rowHeight)

            textAlign(.left, .middle)
            textSize(16)
            fill(theme.ink)
            drawText(filter, 56, y - (notes[filter] == nil ? 0 : 10))
            if let note = notes[filter] {
                textSize(11)
                fill(theme.muted)
                drawText(note, 56, y + 12)
            }

            for (column, topic) in topics.enumerated() {
                let x = left + columnWidth * (Double(column) + 0.5)
                // The mark is the shipped rule's own answer, not a table.
                if MQTTTopic.matches(topic, filter: filter) {
                    fill(theme.accent)
                    drawCircle(x, y, 11)
                } else {
                    stroke(theme.border)
                    strokeWeight(1.4)
                    noFill()
                    drawCircle(x, y, 8)
                    noStroke()
                }
            }
        }

        textAlign(.left, .top)
        textSize(12)
        fill(theme.accent)
        drawText("$SYS is the broker's own namespace; no wildcard reaches it, so you ask for it by name",
                 40, top + rowHeight * Double(filters.count) + 20)
    }
}
