import Foundation
import Ollin

/// The world's encyclopedia being edited, drawn as rain.
///
/// Where the earthquake map asks on a schedule with a `DataFeed`, this listens
/// with a `PushFeed`: one connection held open, each edit arriving the moment
/// somebody saves a page, anywhere on Earth. Every edit falls as a drop. The
/// page's title decides the column, so a busy page rains in one place; the
/// bytes added or removed decide the size; growth is green and removal is
/// ember; the tireless bots are the dim gray drizzle behind everything.
///
/// The reading worth copying is `messages()`. Dozens of edits can arrive
/// between two frames, and the drain hands over every one, oldest first, where
/// the latest-message reads would show only the last. The other half is what
/// the sketch does not do: reconnect. A dropped connection redials on its own,
/// and the status line only has to say so through `isConnected` and `problem`
/// while the rain that already fell keeps falling.
///
/// Data: the Wikimedia Foundation's public stream of recent changes, read live
/// and not redistributed here.
@main
final class Edits: Sketch {
    override var canvasSize: CanvasSize { .size(1440, 720) }

    private let feed = PushFeed("https://stream.wikimedia.org/v2/stream/recentchange")

    private struct Drop {
        var x: Double
        var born: Double
        var radius: Double
        var speed: Double
        var grew: Bool
        var bot: Bool
    }

    private var drops: [Drop] = []
    private var seen = 0

    override func setup() {
        feed.start()
    }

    override func draw() {
        background(Color(hex: 0x0B0E13))

        for message in feed.messages() { add(message) }
        drops.removeAll { y(of: $0) > height + 60 }
        for drop in drops where drop.bot { draw(drop) }
        for drop in drops where !drop.bot { draw(drop) }

        drawLegend()
        if seen == 0 {
            if let problem = feed.problem { return drawStatus(problem, style: .warning) }
            return drawStatus("Waiting for somebody, somewhere, to save an edit…")
        }
    }

    // MARK: Reading the stream

    private func add(_ message: PushFeed.Message) {
        let change = message.json
        let kind = change["type"].text ?? ""
        guard kind == "edit" || kind == "new" else { return }
        seen += 1

        let bytes = (change["length"]["new"].number ?? 0)
                  - (change["length"]["old"].number ?? 0)
        let drop = Drop(
            x: column(for: change["title"].text ?? ""),
            born: time,
            // A one-letter fix and a pasted chapter are worlds apart in bytes,
            // so the size runs on a log scale to keep both readable.
            radius: map(log10(1 + abs(bytes)), 0, 4, 1.5, 16, clamp: true),
            speed: random(70, 110),
            grew: bytes >= 0,
            bot: change["bot"].bool ?? false
        )
        drops.append(drop)
        if drops.count > 900 { drops.removeFirst(drops.count - 900) }
    }

    /// The title decides the column, deterministically, so a page being fought
    /// over rains in one visible place rather than everywhere.
    private func column(for title: String) -> Double {
        var folded: UInt64 = 1469598103934665603
        for scalar in title.unicodeScalars {
            folded = (folded ^ UInt64(scalar.value)) &* 1099511628211
        }
        return map(Double(folded % 4096), 0, 4096, 24, width - 24)
    }

    // MARK: Drawing

    private func y(of drop: Drop) -> Double {
        (time - drop.born) * drop.speed
    }

    private func draw(_ drop: Drop) {
        let y = y(of: drop)
        let entrance = min(1, (time - drop.born) * 3)
        let tint: Color = drop.bot
            ? Color(white: 0.45)
            : Color(hex: drop.grew ? 0x4CC98F : 0xE0684C)
        let alpha = entrance * (drop.bot ? 0.18 : 0.75)

        // A short streak above the drop reads as falling.
        stroke(tint.withAlpha(alpha * 0.4))
        strokeWeight(max(1, drop.radius * 0.4))
        drawLine(drop.x, y - drop.radius * 4 - 12, drop.x, y - drop.radius)

        noStroke()
        fill(tint.withAlpha(alpha))
        drawCircle(drop.x, y, drop.radius)
    }

    private func drawLegend() {
        withState {
            noStroke()
            textFont(OutlineFont.systemMedium)
            textSize(16)
            textAlign(.left, .top)
            fill(Color(white: 0.72))
            drawText(seen == 1 ? "1 edit since this window opened"
                               : "\(seen) edits since this window opened", 28, 26)

            textSize(13)
            fill(Color(white: 0.42))
            drawText(status(), 28, 50)
        }
    }

    private func status() -> String {
        if let problem = feed.problem { return "redialing: \(problem)" }
        if let since = feed.timeSinceUpdate {
            return "listening, the last edit landed \(Int(since))s ago"
        }
        return feed.isConnected ? "listening" : "connecting"
    }
}
