// figure: frame=0
//
// Guide figure (Chapter 27): the phone's screen as a control surface, and how a
// landing is found.
//
// Left: the glass at one instant, with the fingers on it drawn as discs sized by
// how wide each contact is, and the rings left by the landings so far. Right:
// the same two seconds as a timeline, one row per finger, a bar while it is
// down and a warm dot where it landed, with the draw marks along the top. The
// third finger lands and leaves between two of those marks, so it is never in
// `down` when a sketch looks, and its ring is there all the same.
//
// The readings are staged rather than felt, the way this chapter's other
// figures stage a phone: the same object a phone feeds, fed by hand, and the
// landings read back off it rather than guessed.
import Foundation
import Ollin
import OllinPhone

final class GlassAsPad: Sketch {
    override var canvasSize: CanvasSize { .size(880, 560) }

    let paper = Color(hex: 0x0D1017)
    let ink = Color(hex: 0xF2EBDD)
    let warm = Color(hex: 0xFFB84D)
    let cool = Color(hex: 0x7FE0D4)

    static let seconds = 2.0
    /// How often this sketch is drawing, for the marks along the top: slow
    /// enough to see, and the reason the quick tap falls between two of them.
    static let drawEvery = 0.25

    /// What the phone sent: a reading each time the set of fingers changed.
    /// One finger presses and slides, a second joins wide and stays, and a
    /// third taps once, in and out inside a quarter of a second.
    static let readings: [(time: Double, touches: [PhoneTouch])] = [
        (0.30, [PhoneTouch(id: 1, position: Vector2(-0.62, 0.45), radius: 0.055)]),
        (0.62, [PhoneTouch(id: 1, position: Vector2(-0.52, 0.30), radius: 0.06),
                PhoneTouch(id: 2, position: Vector2(0.36, 0.05), radius: 0.115)]),
        (0.95, [PhoneTouch(id: 1, position: Vector2(-0.44, 0.12), radius: 0.06),
                PhoneTouch(id: 2, position: Vector2(0.38, 0.04), radius: 0.115)]),
        (1.28, [PhoneTouch(id: 2, position: Vector2(0.35, 0.02), radius: 0.11)]),
        (1.55, [PhoneTouch(id: 2, position: Vector2(0.35, 0.02), radius: 0.11),
                PhoneTouch(id: 3, position: Vector2(-0.10, -0.55), radius: 0.035)]),
        (1.66, [PhoneTouch(id: 2, position: Vector2(0.35, 0.02), radius: 0.11)]),
        (1.95, [PhoneTouch(id: 2, position: Vector2(0.37, 0.00), radius: 0.11)]),
    ]

    /// The instant the glass is drawn at: two fingers down, so the widths can
    /// be compared, and both of their landings still ringing.
    static let shown = 0.95

    /// The taps, read off the real surface rather than assumed.
    var taps: [PhoneTap] = []
    /// When each finger was down, for the timeline.
    var lives: [(id: Int, from: Double, to: Double)] = []

    let surface = PhoneTouches()

    override func setup() {
        noLoop()
        var seen: [Int: (from: Double, to: Double)] = [:]
        var down: Set<Int> = []
        for reading in Self.readings {
            surface.feel(reading.touches, at: reading.time)
            taps.append(contentsOf: surface.taps())
            let now = Set(reading.touches.map(\.id))
            // A finger is down until the reading that drops it, which is the
            // only moment the wire says it left.
            for id in down where !now.contains(id) { seen[id]?.to = reading.time }
            for id in now { seen[id] = (seen[id]?.from ?? reading.time, reading.time) }
            down = now
        }
        // The glass is drawn at `shown`, so wind the surface back to it.
        surface.reset()
        for reading in Self.readings where reading.time <= Self.shown {
            surface.feel(reading.touches, at: reading.time)
        }
        lives = seen.keys.sorted().map { (id: $0, from: seen[$0]!.from, to: seen[$0]!.to) }
    }

    override func draw() {
        background(paper)
        drawGlass()
        drawTimeline()
        withState {
            noStroke()
            fill(ink.withAlpha(0.55))
            textFont(OutlineFont.system)
            textSize(17)
            textAlign(.center)
            drawText("a finger keeps its number from landing to leaving, so a number the Mac has not seen is a tap",
                     at: Vector2(width * 0.5, height - 24))
        }
    }

    /// The glass: the fingers on it now, and the rings the landings left.
    private func drawGlass() {
        let pad = Rectangle(x: 48, y: 44, width: 210, height: 396)
        withState {
            noFill()
            stroke(ink.withAlpha(0.3))
            strokeWeight(1.5)
            drawRect(corner: pad.corner, width: pad.width, height: pad.height, cornerRadius: 22)

            // The rings, opened out by how long ago the finger landed. Only the
            // landings the glass has seen by this instant are in the picture.
            for tap in taps where tap.time <= Self.shown {
                let age = Self.shown - tap.time
                stroke(warm.withAlpha(max(0.2, 0.85 - age * 0.35)))
                strokeWeight(2)
                // A ring leaves the edge of the finger that made it, so it is
                // never a circle drawn inside a disc.
                drawCircle(center: tap.point(in: pad),
                           radius: 10 + tap.radius * 300 + age * 40)
            }

            // The fingers themselves, sized by how wide the contact is.
            noStroke()
            textFont(OutlineFont.system)
            textAlign(.center)
            for touch in surface.down {
                let center = touch.point(in: pad)
                let radius = 10 + touch.radius * 300
                fill(cool.withAlpha(0.35))
                drawCircle(center: center, radius: radius)
                fill(ink)
                drawCircle(center: center, radius: 3.5)
                fill(ink.withAlpha(0.6))
                textSize(15)
                drawText("\(touch.id)", at: center + Vector2(0, radius + 19))
            }

            fill(ink.withAlpha(0.5))
            textSize(16)
            drawText("the glass at 0.95 s", at: Vector2(pad.center.x, pad.bottomLeft.y + 26))
            fill(ink.withAlpha(0.4))
            textSize(15)
            drawText("the disc is how wide the contact is",
                     at: Vector2(pad.center.x, pad.bottomLeft.y + 48))
        }
    }

    /// The same two seconds as rows: a bar while each finger is down, a dot
    /// where it landed, and the draw marks along the top.
    private func drawTimeline() {
        let left = 340.0, right = width - 44
        let top = 96.0, rowHeight = 74.0
        func x(_ t: Double) -> Double { left + (right - left) * t / Self.seconds }

        withState {
            textFont(OutlineFont.system)

            // The draw marks: where a sketch looked.
            stroke(ink.withAlpha(0.22))
            strokeWeight(1)
            var t = 0.0
            while t <= Self.seconds + 1e-9 {
                drawLine(x(t), top - 24, x(t), top + rowHeight * Double(lives.count) - 18)
                t += Self.drawEvery
            }
            noStroke()
            fill(ink.withAlpha(0.55))
            textSize(16)
            textAlign(.left)
            drawText("every draw()", at: Vector2(left, top - 36))

            // Where the glass on the left was drawn.
            stroke(ink.withAlpha(0.5))
            strokeWeight(1.5)
            drawLine(x(Self.shown), top - 24, x(Self.shown),
                     top + rowHeight * Double(lives.count) - 18)
            noStroke()
            fill(ink.withAlpha(0.55))
            textSize(15)
            textAlign(.center)
            drawText("the glass, left", at: Vector2(x(Self.shown), top - 36))

            for (row, life) in lives.enumerated() {
                let y = top + rowHeight * Double(row) + 16
                // The bar: while the finger was on the glass.
                noStroke()
                fill(cool.withAlpha(0.3))
                drawRect(corner: Vector2(x(life.from), y - 9),
                         width: max(4, x(life.to) - x(life.from)), height: 18, cornerRadius: 9)
                fill(ink.withAlpha(0.7))
                textSize(16)
                textAlign(.right)
                drawText("id \(life.id)", at: Vector2(left - 14, y + 6))
            }

            // The landing, on its own row, with the ring that answers it.
            for tap in taps {
                guard let row = lives.firstIndex(where: { $0.id == tap.id }) else { continue }
                let y = top + rowHeight * Double(row) + 16
                noStroke()
                fill(warm)
                drawCircle(center: Vector2(x(tap.time), y), radius: 7)
                noFill()
                stroke(warm.withAlpha(0.5))
                strokeWeight(1.5)
                drawCircle(center: Vector2(x(tap.time), y), radius: 14)
                noStroke()
                fill(warm.withAlpha(0.85))
                textSize(15)
                textAlign(.center)
                drawText("taps()", at: Vector2(x(tap.time), y - 24))
            }

            // The point of the third row, said once.
            if let quick = lives.first(where: { $0.id == 3 }) {
                let y = top + rowHeight * 2 + 16
                noStroke()
                fill(ink.withAlpha(0.55))
                textSize(15)
                textAlign(.right)
                drawText("down and gone between two draws", at: Vector2(right, y + 36))
            }

            // The clock.
            fill(ink.withAlpha(0.5))
            textSize(15)
            textAlign(.center)
            let axis = top + rowHeight * Double(lives.count) + 6
            for s in stride(from: 0.0, through: Self.seconds, by: 0.5) {
                drawText(String(format: "%.1f s", s), at: Vector2(x(s), axis))
            }
        }
    }
}
