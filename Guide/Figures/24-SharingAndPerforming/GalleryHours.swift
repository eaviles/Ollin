// figure: frame=1
//
// Guide diagram (Chapter 24): a schedule as the day it describes. The named
// parts a sketch reads, the stretch with nothing on screen (which crosses
// midnight, because the last part of the day runs round to the first), and the
// sketch clock underneath, which stops with the frames rather than skipping.
import Ollin

final class GalleryHours: Sketch {
    override var canvasSize: CanvasSize { .size(880, 392) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.55)
    let accent = Color(hex: 0xE4572E)

    let left = 92.0, right = 836.0

    /// The day, each part from its own start to the next. Nothing starts at
    /// midnight, so the small hours belong to the last part of the day: the
    /// dark stretch runs from eleven at night to six in the morning.
    let parts: [(start: Double, name: String, sky: Color)] = [
        (6,  "dawn",  Color(hex: 0xC98A6B)),
        (10, "day",   Color(hex: 0x6B9EC7)),
        (18, "dusk",  Color(hex: 0x8A6A96)),
        (20, "night", Color(hex: 0x2A3352)),
        (23, "",      Color(hex: 0x151519)),   // nothing on screen
    ]

    /// Where the piece is dark, which is also where the clock lies flat.
    var opens: Double { 6 }
    var closes: Double { 23 }

    override func draw() {
        background(paper)
        noStroke()
        strip(y: 96)
        clockLine(y: 244)
        caption()
    }

    /// The day as one bar, each part labelled with the name the sketch reads.
    func strip(y: Double) {
        let height = 54.0
        fill(ink)
        textSize(17)
        textAlign(.left, .bottom)
        drawText("the day", left, y - 16)

        // The stretch before the first part belongs to the last one.
        var spans: [(from: Double, to: Double, part: Int)] = [(0, parts[0].start, parts.count - 1)]
        for (index, part) in parts.enumerated() {
            let end = index + 1 < parts.count ? parts[index + 1].start : 24
            spans.append((part.start, end, index))
        }

        for span in spans {
            let part = parts[span.part]
            fill(part.sky)
            drawRect(x(span.from), y, x(span.to) - x(span.from), height)

            let middle = (x(span.from) + x(span.to)) / 2
            guard span.to - span.from > 1.6 else { continue }   // no room for a word
            textSize(15)
            textAlign(.center, .middle)
            if part.name.isEmpty {
                fill(Color(white: 0.58))
                drawText("dark", middle, y + height / 2 + 4)
            } else {
                fill(Color(white: 0.98))
                drawText(part.name, middle, y + height / 2 + 4)
            }
        }

        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        for hour in stride(from: 0.0, through: 24.0, by: 4) {
            drawText(String(format: "%02d:00", Int(hour) % 24), x(hour), y + height + 10)
        }
    }

    /// The sketch clock across the same day: it climbs while the piece draws
    /// and lies flat while it does not.
    func clockLine(y: Double) {
        fill(ink)
        textSize(17)
        textAlign(.left, .bottom)
        drawText("the sketch clock", left, y - 16)

        let rise = 58.0
        stroke(accent)
        strokeWeight(2.5)
        noFill()
        drawLine(Vector2(x(0), y + rise), Vector2(x(opens), y + rise))
        drawLine(Vector2(x(opens), y + rise), Vector2(x(closes), y))
        drawLine(Vector2(x(closes), y), Vector2(x(24), y))

        noStroke()
        fill(soft)
        textSize(14)
        textAlign(.center, .top)
        drawText("stopped, not skipped", (x(0) + x(opens)) / 2, y + rise + 12)
        drawText("counting while it draws", (x(opens) + x(closes)) / 2, y + rise + 12)
    }

    func caption() {
        fill(soft)
        textSize(16)
        textAlign(.center, .top)
        drawText("so the morning carries on from where the night stopped, rather than from where the day got to",
                 width / 2, 352)
    }

    func x(_ hour: Double) -> Double { left + (right - left) * hour / 24 }
}
