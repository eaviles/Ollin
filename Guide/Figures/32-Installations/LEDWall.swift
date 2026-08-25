// figure: frame=0 themed
//
// Guide diagram (Chapter 32): the canvas leaving the screen as LEDs. A strip
// rides a wave over a colorful field and a matrix reads a panel of it (the
// rings are the sample points, straight off `LEDMap`'s own geometry); below,
// the same LEDs lit: the strip laid out straight in wire order, the panel
// beside it, each labeled with the universe it lands on. The point of the
// figure: the wall is just the canvas, somewhere else.
import Ollin
import OllinDMX

final class LEDWall: Sketch {
    override var canvasSize: CanvasSize { .size(880, 600) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.6) }
    let picture = Rectangle(x: 60, y: 56, width: 760, height: 236)

    /// The picture as a function of position, so the lit lamps below can read
    /// the same field the rings sit on.
    func fieldColor(_ p: Vector2) -> Color {
        let u = (p.x - picture.x) / picture.width
        let v = (p.y - picture.y) / picture.height
        let hue = fract(u * 0.9 + 0.1 * sin(v * .pi * 2))
        let brightness = 0.55 + 0.45 * sin((u * 2.1 + v * 0.7 + 0.15) * .pi * 2)
        return Color(hue: hue, saturation: 0.8, brightness: max(0.12, brightness))
    }

    override func draw() {
        background(paper)
        noStroke()

        // The map, built with the real API: its positions are what's drawn.
        let leds = LEDMap(sender: DMXSender(sACN: "127.0.0.1"))
        let wave = (0...96).map { i -> Vector2 in
            let t = Double(i) / 96
            return Vector2(picture.x + 30 + t * (picture.width - 60),
                           picture.y + picture.height * (0.3 + 0.14 * sin(t * .pi * 2.4)))
        }
        let strip = leds.addStrip(along: wave, leds: 28, universe: 1, sampleRadius: 5)
        let panelRect = Rectangle(x: picture.x + 470, y: picture.y + 118,
                                  width: 240, height: 100)
        let panel = leds.addMatrix(in: panelRect, columns: 8, rows: 4,
                                   universe: 2, sampleRadius: 7)

        // The picture, painted from the field.
        let cell = 4.0
        var y = picture.y
        while y < picture.y + picture.height {
            var x = picture.x
            while x < picture.x + picture.width {
                fill(fieldColor(Vector2(x + cell / 2, y + cell / 2)))
                drawRect(x, y, cell, cell)
                x += cell
            }
            y += cell
        }

        // The sample points: a ring just outside each LED's patch.
        noFill()
        stroke(Color(white: 1).withAlpha(0.85))
        strokeWeight(1.2)
        for fixture in leds.fixtures {
            for point in fixture.positions {
                drawCircle(center: point, radius: fixture.sampleRadius + 4)
            }
        }
        stroke(ink.withAlpha(0.5))
        drawRect(panelRect.inset(by: -8))
        noStroke()

        // The lamps, lit from the same field the rings stand on.
        let stripY = 372.0
        let spacing = (width - 160) / Double(strip.ledCount - 1)
        for i in 0..<strip.ledCount {
            drawLED(at: Vector2(80 + Double(i) * spacing, stripY),
                    color: fieldColor(strip.positions[i]), radius: 8)
        }
        let panelCell = 30.0
        let panelOrigin = Vector2(160, 442)
        for row in 0..<4 {
            for column in 0..<8 {
                let index = row * 8 + column
                drawLED(at: panelOrigin + Vector2((Double(column) + 0.5) * panelCell,
                                                  (Double(row) + 0.5) * panelCell),
                        color: fieldColor(panel.positions[index]), radius: 9)
            }
        }

        // Callouts: what the code did, and where the bytes land.
        textAlign(.left, .top)
        fill(ink)
        textSize(15)
        drawText("addStrip / addMatrix  lay LEDs over the picture …", 60, 16)
        textAlign(.right, .top)
        drawText("… extend(leds)  sends what's under them", 820, 16)

        textAlign(.left, .top)
        fill(soft)
        textSize(13)
        let lastStrip = strip.address(ofLED: strip.ledCount - 1)!
        drawText("the strip, in wire order · universe 1, channels 1-\(lastStrip.channel + 2)",
                 80, stripY + 22)
        let panelWire = panel.address(ofLED: 0)!
        drawText("the panel · universe \(panelWire.universe) · \(panel.ledCount) LEDs",
                 panelOrigin.x + panelCell * 8 + 24, panelOrigin.y + 8)
        drawText("each LED averages the patch it stands for (the rings);",
                 panelOrigin.x + panelCell * 8 + 24, panelOrigin.y + 30)
        drawText("universes pack whole LEDs, 170 RGB each, then continue",
                 panelOrigin.x + panelCell * 8 + 24, panelOrigin.y + 52)
        drawText("on the next number up.",
                 panelOrigin.x + panelCell * 8 + 24, panelOrigin.y + 74)
    }

    /// One lamp: a soft throw around a lit core, dark when its pixel is.
    func drawLED(at position: Vector2, color: Color, radius: Double) {
        let brightness = max(color.red, max(color.green, color.blue))
        fill(color.withAlpha(0.14 * brightness))
        drawCircle(center: position, radius: radius * 3)
        fill(color.withAlpha(0.4 * brightness))
        drawCircle(center: position, radius: radius * 1.6)
        fill(Color(white: 0.2))
        drawCircle(center: position, radius: radius * 1.08)
        fill(color)
        drawCircle(center: position, radius: radius)
    }
}
