import Ollin
import OllinDMX

/// The canvas leaving the screen as LEDs, round trip. An `LEDMap` lays a
/// 48-LED strip along a wave and a 12×8 matrix over the animated picture; every
/// frame the map samples the rendered pixels under them on the GPU and sends
/// the bytes as sACN to `127.0.0.1`. A `DMXReceiver` on the same port reads the
/// universes back, and the "hardware" drawn along the bottom (the strip laid
/// out straight, in wire order, and the panel beside it) is lit from what
/// actually arrived, not from local values.
///
/// To feed a real wall, point the sender at your pixel controller
/// (`DMXSender(sACN: "192.168.1.40")`, or plain `DMXSender()` to multicast)
/// and patch the controller to the universes the map reports. The thin rings
/// over the picture are the sample points, drawn just outside each LED's
/// sample patch so the overlay stays out of its own reading.
@main
final class LEDMapping: Sketch {

    let sender = DMXSender(sACN: "127.0.0.1")
    let receiver = DMXReceiver()
    lazy var leds = LEDMap(sender: sender)

    @Param(0 ... 1, icon: "sun.max") var master = 1.0

    /// The picture region the map reads (the rig below it holds no sample
    /// points, so lighting it from received data can't feed back).
    let art = Rectangle(x: 60, y: 60, width: 960, height: 460)

    var strip: LEDMap.Fixture?
    var panel: LEDMap.Fixture?

    override func setup() {
        // The strip rides a wave across the picture on universe 1; the matrix
        // reads a panel of it on universe 2. Explicit sample radii keep the
        // ring overlay outside each LED's patch.
        let wave = (0...96).map { i -> Vector2 in
            let t = Double(i) / 96
            return Vector2(art.x + t * art.width,
                           art.y + art.height * (0.28 + 0.13 * sin(t * .pi * 3)))
        }
        strip = leds.addStrip(along: wave, leds: 48, universe: 1, sampleRadius: 6)
        panel = leds.addMatrix(in: Rectangle(x: art.x + 250, y: art.y + 210,
                                             width: 460, height: 210),
                               columns: 12, rows: 8, universe: 2, sampleRadius: 10)
        extend(leds)
        try? receiver.start()
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.05))
        leds.brightness = master

        drawPicture()
        drawSamplePoints()
        drawRig()

        fill(Color(white: 0.6))
        textSize(22 * scale)
        drawText("sACN ↺ 127.0.0.1   universes \(leds.universes.map(String.init).joined(separator: ", "))",
                 30 * scale, 50 * scale)
    }

    /// The material the LEDs read: drifting color fields over a dark ground.
    func drawPicture() {
        withClip(art) {
            fill(Color(hex: 0x101018))
            drawRect(art)
            for i in 0..<5 {
                let n = Double(i)
                let x = art.x + art.width * (0.5 + 0.42 * sin(time * (0.23 + n * 0.06) + n * 1.7))
                let y = art.y + art.height * (0.5 + 0.42 * cos(time * (0.31 + n * 0.05) + n * 2.4))
                let hue = fract(n / 5 + time * 0.03)
                fill(Color(hue: hue, saturation: 0.85, brightness: 1).withAlpha(0.55))
                drawCircle(x, y, art.height * (0.28 + 0.1 * sin(time * 0.5 + n)))
            }
        }
        stroke(Color(white: 0.25))
        strokeWeight(1)
        noFill()
        drawRect(art)
        noStroke()
    }

    /// The map, made visible: a ring just outside each LED's sample patch.
    func drawSamplePoints() {
        noFill()
        strokeWeight(1)
        for fixture in leds.fixtures {
            stroke(Color(white: 0.9).withAlpha(0.35))
            for point in fixture.positions {
                drawCircle(center: point, radius: fixture.sampleRadius + 5)
            }
        }
        noStroke()
    }

    /// The "hardware", lit from what the receiver got back off the wire: the
    /// strip laid out straight in wire order, the panel beside its mapped
    /// shape. Every lamp reads its own channels through `address(ofLED:)`.
    func drawRig() {
        guard let strip, let panel else { return }

        let stripY = height * 0.62
        let inset = 80 * scale
        let stripSpacing = (width - inset * 2) / Double(strip.ledCount - 1)
        for i in 0..<strip.ledCount {
            guard let slot = strip.address(ofLED: i) else { continue }
            let color = receiver.color(slot.channel, universe: slot.universe)
            drawLED(at: Vector2(inset + Double(i) * stripSpacing, stripY),
                    color: color, radius: 7 * scale)
        }
        fill(Color(white: 0.45))
        textSize(16 * scale)
        drawText("the strip, in wire order (universe 1)", inset, stripY + 30 * scale)

        let cell = 34 * scale
        let panelOrigin = Vector2(width / 2 - cell * 6, height * 0.70)
        fill(Color(white: 0.45))
        drawText("the panel (universe 2)", panelOrigin.x, panelOrigin.y - 14 * scale)
        for row in 0..<8 {
            for column in 0..<12 {
                guard let slot = panel.address(ofLED: row * 12 + column) else { continue }
                let color = receiver.color(slot.channel, universe: slot.universe)
                drawLED(at: panelOrigin + Vector2((Double(column) + 0.5) * cell,
                                                  (Double(row) + 0.5) * cell),
                        color: color, radius: 9 * scale)
            }
        }
    }

    /// One lamp: a lit dot with a soft throw, dark when its channels are.
    func drawLED(at position: Vector2, color: Color, radius: Double) {
        let brightness = max(color.red, max(color.green, color.blue))
        fill(color.withAlpha(0.16 * brightness))
        drawCircle(center: position, radius: radius * 3.2)
        fill(color.withAlpha(0.45 * brightness))
        drawCircle(center: position, radius: radius * 1.7)
        fill(Color(white: 0.16))
        drawCircle(center: position, radius: radius * 1.05)
        fill(color.withAlpha(0.25 + 0.75 * brightness))
        drawCircle(center: position, radius: radius)
    }
}
