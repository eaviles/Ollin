import Foundation
import Ollin

/// A piece that keeps the building's hours, and changes with the day inside
/// them.
///
/// A piece on a wall is in a building, and buildings have hours. A schedule is
/// both halves of that. It names the parts of the day, which the sketch reads
/// to decide what to draw, and it says which parts have nothing on screen at
/// all, which takes the picture away and lets the display sleep until the doors
/// open again.
///
/// The sky here is one pair of colors per part of the day, and the piece slides
/// from one pair into the next over the last stretch of each, so the change
/// arrives the way light does rather than as a switch. `scheduledPeriod` gives
/// the name and `scheduledProgress` gives how far through it the day has got.
///
/// Both reads work at a desk as much as on a wall, so this can be worked on at
/// any hour. Going dark is the half that needs the installation: only a piece
/// that owns its window can take the screen away. See
/// `Docs/Output/Installation.md`.
@main
final class Hours: Sketch {

    /// The day, in order: when each part starts, and the sky it brings. The
    /// schedule below is built from this, so the two can never disagree.
    private let day: [(name: String, start: Installation.Schedule.Time,
                       high: Color, low: Color)] = [
        ("dawn",  .at(6),  Color(red: 0.24, green: 0.28, blue: 0.48), Color(red: 0.94, green: 0.62, blue: 0.44)),
        ("day",   .at(9),  Color(red: 0.32, green: 0.56, blue: 0.86), Color(red: 0.88, green: 0.93, blue: 0.97)),
        ("dusk",  .at(17), Color(red: 0.30, green: 0.22, blue: 0.44), Color(red: 0.96, green: 0.48, blue: 0.30)),
        ("night", .at(21), Color(red: 0.04, green: 0.05, blue: 0.12), Color(red: 0.12, green: 0.18, blue: 0.34)),
    ]

    override var installation: Installation {
        // Four parts with the piece on screen, and the hours after eleven with
        // nothing on it. The dark stretch runs to the first part of tomorrow.
        Installation(schedule: Installation.Schedule(
            day.map { .from($0.start, $0.name) } + [.dark(from: 23)]))
    }

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func draw() {
        let (high, low) = sky()
        noStroke()

        // A plain graded sky: enough bands that the steps disappear.
        let bands = 96.0
        for band in 0 ..< Int(bands) {
            let t = Double(band) / (bands - 1)
            fill(Color.mix(high, low, t))
            drawRect(0, t * height, width, height / bands + 1)
        }

        // The sun, or the moon, riding the part of the day it belongs to.
        let across = scheduledProgress
        let disc = Vector2(width * (0.12 + 0.76 * across),
                           height * (0.62 - 0.34 * sin(across * .pi)))
        fill(scheduledPeriod == "night" ? Color(white: 0.88) : Color(red: 1, green: 0.96, blue: 0.86))
        drawCircle(center: disc, radius: shortSide * 0.055)

        label()
    }

    /// The two sky colors for now: this part of the day, slid into the next
    /// over its last quarter so nothing jumps at the hour.
    private func sky() -> (high: Color, low: Color) {
        guard let index = day.firstIndex(where: { $0.name == scheduledPeriod }) else {
            return (day[0].high, day[0].low)
        }
        let here = day[index], next = day[(index + 1) % day.count]
        let turn = max(0, (scheduledProgress - 0.75) / 0.25)
        return (Color.mix(here.high, next.high, turn),
                Color.mix(here.low, next.low, turn))
    }

    private func label() {
        textAlign(.center, .middle)
        fill(Color(white: 0.16, alpha: 0.7))
        textSize(shortSide * 0.038)
        drawText(scheduledPeriod ?? "no hours kept", center.x, height * 0.88)
        textSize(shortSide * 0.022)
        fill(Color(white: 0.16, alpha: 0.45))
        let next = installation.schedule.nextChange(at: Date())?.text ?? ""
        drawText("until \(next)", center.x, height * 0.93)
    }
}
