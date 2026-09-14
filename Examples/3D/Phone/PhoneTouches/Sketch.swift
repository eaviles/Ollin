import Foundation
import Ollin
import OllinPhone

/// The phone as something you play: every finger on its screen lands on the
/// canvas, each tap rings out where it fell, and lifting the phone off the table
/// warms the whole thing.
///
/// Setup: install **Ollin Capture** on an iPhone, launch it, tap **Touch**, and
/// connect the cable. No camera runs in that mode, so the phone stays cool.
/// Tap **Air** as well (the switch under the modes; the phone asks for motion
/// once) and the barometer joins in. The connection retries on its own, so
/// tapping either after this sketch is already running just begins the feed.
///
/// The two reads every input in Ollin has are both here. A *state* that comes
/// and goes: `device.touches.down` is the fingers on the glass right now, each
/// drawn as a disc sized by how wide the contact is, so a fingertip and a flat
/// finger are different marks. And a *trigger* that happens once:
/// `device.touches.taps()` drains the landings, so a tap between two frames
/// still rings. The ring is what proves it: tap fast enough that the finger is
/// gone before the next `draw()` and it rings all the same.
@main
final class PhoneTouches: Sketch {

    let device = PhoneDevice()

    /// How far the ring travels in a second, in canvas points.
    @Param(60...600) var ringSpeed = 260.0

    /// How much a finger's width swells its disc.
    @Param(0...1200) var widthGain = 520.0

    struct Ring {
        var center: Vector2
        var born: Double
        var lift: Double
    }
    var rings: [Ring] = []

    /// The altitude eased, so a barometer's own jitter does not shake the color.
    var lift = 0.0

    let ink = Color(hex: 0xF2EBDD)
    let warm = Color(hex: 0xFFB84D)
    let cool = Color(hex: 0x7FE0D4)

    /// Where the phone's screen lands on the canvas: the whole glass, a little
    /// inside the edges, in the phone's own portrait proportion.
    var pad: Rectangle {
        let height = self.height * 0.78
        let width = height * 9 / 19.5
        return Rectangle(center: Vector2(self.width * 0.5, self.height * 0.5),
                         width: width, height: height)
    }

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(hex: 0x0D1017))

        guard device.isRunning else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Ollin Capture on an iPhone, tap Touch, and\n" +
                              "connect the cable.", style: .info)
        }

        // The air eases toward the phone's reading, so the color drifts rather
        // than flickering. Nothing arrives until the Air switch is on.
        if let air = device.latestAir {
            lift += (air.altitude - lift) * min(1, deltaTime * 3)
        }

        // Every landing since the last frame rings, wherever it fell: a tap that
        // came and went between two draws is in here too.
        for tap in device.touches.taps() {
            rings.append(Ring(center: tap.point(in: pad), born: time, lift: lift))
        }
        rings.removeAll { time - $0.born > 2.4 }

        drawPad()
        drawRings()
        drawFingers()
        drawGauge()

        let count = device.touches.down.count
        drawCaption("PhoneTouches: \(count) on the glass · \(device.touches.tapCount) taps"
                    + (device.latestAir == nil ? " · tap Air on the phone" : ""))
    }

    /// The glass itself, so a finger has somewhere to be.
    private func drawPad() {
        withState {
            noFill()
            stroke(ink.withAlpha(device.touches.isTouching ? 0.35 : 0.15))
            strokeWeight(1.5)
            drawRect(center: pad.center, width: pad.width, height: pad.height, cornerRadius: 28)
        }
    }

    /// One ring per landing, opening out from where the finger fell. Its color
    /// carries the lift the phone was at when it landed, so a run up the stairs
    /// leaves a warming trail behind it.
    private func drawRings() {
        withState {
            noFill()
            for ring in rings {
                let age = time - ring.born
                let fade = max(0, 1 - age / 2.4)
                let tint = cool.mixed(with: warm, min(1, max(0, ring.lift * 0.5 + 0.5)))
                stroke(tint.withAlpha(fade * 0.9))
                strokeWeight(1 + 4 * fade)
                drawCircle(center: ring.center, radius: 14 + age * ringSpeed)
            }
        }
    }

    /// The fingers on the glass: a disc each, sized by how wide the contact is,
    /// and joined into a constellation when there is more than one.
    private func drawFingers() {
        let down = device.touches.down
        withState {
            if down.count > 1 {
                stroke(ink.withAlpha(0.2))
                strokeWeight(1)
                for i in 0..<(down.count - 1) {
                    drawLine(down[i].point(in: pad), down[i + 1].point(in: pad))
                }
            }
            noStroke()
            textFont(OutlineFont.system)
            textAlign(.center)
            for touch in down {
                let center = touch.point(in: pad)
                let radius = 16 + touch.radius * widthGain
                // Where the glass can weigh a press, it brightens the disc; where
                // it cannot, the disc keeps its own steady weight.
                let press = touch.force ?? 0.5
                fill(warm.withAlpha(0.18 + 0.5 * press))
                drawCircle(center: center, radius: radius)
                fill(ink.withAlpha(0.85))
                drawCircle(center: center, radius: 4)
                fill(ink.withAlpha(0.45))
                textSize(15)
                drawText("\(touch.id)", at: center + Vector2(0, radius + 20))
            }
        }
    }

    /// The air down the right edge: how far the phone has risen since it started
    /// measuring, and the pressure it is reading.
    private func drawGauge() {
        guard let air = device.latestAir else { return }
        withState {
            textFont(OutlineFont.system)
            textAlign(.right)
            let x = width - 70.0
            let top = height * 0.2, bottom = height * 0.8
            let middle = (top + bottom) * 0.5
            stroke(ink.withAlpha(0.2))
            strokeWeight(1)
            drawLine(x, top, x, bottom)
            drawLine(x - 8, middle, x + 8, middle)
            // A meter up or down fills the gauge, which is about the range a
            // hand gives it.
            let y = middle - min(max(lift, -1), 1) * (bottom - top) * 0.5
            noStroke()
            fill(cool.mixed(with: warm, min(1, max(0, lift * 0.5 + 0.5))))
            drawCircle(center: Vector2(x, y), radius: 7)
            fill(ink.withAlpha(0.7))
            textSize(17)
            drawText(String(format: "%+.2f m", air.altitude), at: Vector2(x - 18, y + 6))
            fill(ink.withAlpha(0.4))
            textSize(15)
            drawText(String(format: "%.2f kPa", air.pressure), at: Vector2(x + 10, bottom + 26))
        }
    }
}
