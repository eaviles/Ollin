// figure: frame=300
//
// Guide payoff (Chapter 32): the wall piece. A slow field declared for a room
// rather than a window: it fills the screen, keeps the display awake, writes a
// checkpoint every minute so a power cut costs a minute, restarts itself if it
// ever stalls, opens and closes with the building, and repeats exactly on a
// three minute lap. A strip of LEDs reads the bottom of the canvas, so the wall
// under it carries the same light. The committed figure pins dusk.
import Ollin
import OllinDMX

final class WallPiece: Sketch {
    override var canvasSize: CanvasSize { .size(1280, 720) }

    /// Everything the room needs to know, in one declaration.
    override var installation: Installation {
        Installation(checkpoint: .every(seconds: 60),
                     restarts: .onFailure,
                     schedule: [.from(6, "dawn"), .from(10, "day"),
                                .from(18, "dusk"), .from(21, "night")])
    }

    /// Three minutes a lap, so the piece is exactly where it was every three
    /// minutes and the shader clock never has to count a week.
    override var loopDuration: Double? { 180 }

    /// Which part of the day to draw. Leave it nil on the wall and the schedule
    /// answers; name one here to see any hour without waiting for it.
    let showing: String? = "dusk"
    var period: String { showing ?? scheduledPeriod ?? "day" }

    let palettes: [String: [Color]] = [
        "dawn":  [Color(hex: 0x1B1B2E), Color(hex: 0x5B4A78), Color(hex: 0xD98E73), Color(hex: 0xF3D9A4)],
        "day":   [Color(hex: 0x16324A), Color(hex: 0x3E7CA6), Color(hex: 0x9FD2E0), Color(hex: 0xF4F1E4)],
        "dusk":  [Color(hex: 0x140F1E), Color(hex: 0x53264A), Color(hex: 0xC7503F), Color(hex: 0xF0A860)],
        "night": [Color(hex: 0x05070F), Color(hex: 0x122744), Color(hex: 0x2E5C7A), Color(hex: 0x8FB8CE)],
    ]

    let leds = LEDMap(sender: DMXSender())

    override func setup() {
        noStroke()
        // The wall under the screen: one run of lamps reading the canvas above
        // them. After this the piece draws as if they were not there.
        leds.addStrip(from: Vector2(90, Double(height) - 54),
                      to: Vector2(Double(width) - 90, Double(height) - 54), leds: 96)
        extend(leds)
    }

    override func draw() {
        let ramp = Ramp(palettes[period] ?? palettes["day"]!)
        background(ramp.color(at: 0))

        // One lap of the loop, so nothing in the picture depends on how long the
        // machine has been switched on.
        let lap = loopProgress(over: 180) * .tau
        let columns = 96
        let step = Double(width) / Double(columns)

        for i in 0 ..< columns {
            let u = (Double(i) + 0.5) / Double(columns)
            // Three slow waves that share one lap, so their sum repeats with it.
            let swell = sin(lap + u * .tau) * 0.5
                      + sin(lap * 2 - u * .tau * 2) * 0.3
                      + sin(lap * 3 + u * .tau * 3) * 0.2
            let t = swell * 0.5 + 0.5
            let tall = Double(height) * (0.16 + t * 0.6)
            fill(ramp.color(at: 0.15 + t * 0.85))
            drawRect(corner: Vector2(Double(i) * step, Double(height) - tall - 90),
                     width: step - 1.5, height: tall)
        }

        // The band the lamps read, kept plain so a strip over it glows steadily.
        for i in 0 ..< columns {
            let u = (Double(i) + 0.5) / Double(columns)
            let t = sin(lap + u * .tau) * 0.5 + 0.5
            fill(ramp.color(at: 0.2 + t * 0.7))
            drawRect(corner: Vector2(Double(i) * step, Double(height) - 84),
                     width: step - 1.5, height: 60)
        }
    }
}
