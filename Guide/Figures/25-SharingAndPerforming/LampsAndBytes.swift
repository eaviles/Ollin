// figure: frame=0
//
// Guide diagram (Chapter 25): one DMX universe seen twice. Six RGB pars hang
// over a dark stage, lit by the fixture sugar; below them, the same universe's
// first eighteen channels as labeled meter bars, bracketed by fixture. The
// point of the figure: the rig is a picture of the bytes.
import Ollin
import OllinDMX

final class LampsAndBytes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 600) }

    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        noStroke()

        // Patch six RGB pars back to back (channels 1-18) and light them:
        // a hue per par, with the fourth held low so a level reads in both views.
        var pars: [DMXFixture] = []
        var address = 1
        for _ in 0..<6 {
            let par = DMXFixture.rgb(at: address)
            pars.append(par)
            address = par.nextAddress
        }
        var universe = DMXUniverse()
        for (index, par) in pars.enumerated() {
            let hue = Double(index) / 6 * 0.85
            let dimmer = index == 3 ? 0.35 : 1.0
            universe.set(par, color: Color(hue: hue, saturation: 0.9, brightness: 1), dimmer: dimmer)
        }

        // The stage: pars hanging from a truss, each throwing its light.
        let stage = Rectangle(x: 60, y: 56, width: 760, height: 250)
        fill(Color(hex: 0x0C0C10))
        drawRect(stage, cornerRadius: 14)
        fill(Color(white: 0.28))
        drawRect(stage.x + 20, stage.y + 34, stage.width - 40, 6)

        let spacing = stage.width / Double(pars.count + 1)
        withClip(stage.inset(by: 4)) {
            for (index, par) in pars.enumerated() {
                let x = stage.x + spacing * Double(index + 1)
                let color = universe.color(at: par.address)
                let brightness = max(color.red, max(color.green, color.blue))
                let lamp = Vector2(x, stage.y + 52)
                // The thrown light, then the fixture body over it.
                fill(color.withAlpha(0.12 * brightness))
                drawCircle(center: lamp + Vector2(0, 118), radius: 80)
                fill(color.withAlpha(0.30 * brightness))
                drawCircle(center: lamp + Vector2(0, 108), radius: 48)
                fill(color.withAlpha(0.65 * brightness))
                drawCircle(center: lamp + Vector2(0, 94), radius: 21)
                fill(Color(white: 0.22))
                drawRect(center: lamp, width: 30, height: 38)
                fill(color.withAlpha(0.3 + 0.7 * brightness))
                drawCircle(center: lamp + Vector2(0, 15), radius: 10)
            }
        }

        // The bytes: channels 1-18 as meters, bracketed into fixtures.
        let meters = Rectangle(x: 60, y: 340, width: 760, height: 120)
        let barWidth = meters.width / 18
        textAlign(.center, .top)
        for channel in 1...18 {
            let level = universe.level(channel)
            let x = meters.x + barWidth * Double(channel - 1)
            fill(Color(hex: 0x2B2B2B, alpha: 0.08))
            drawRect(x + barWidth * 0.18, meters.y, barWidth * 0.64, meters.height)
            fill(ink.withAlpha(0.25 + 0.75 * level))
            drawRect(
                x + barWidth * 0.18, meters.y + meters.height * (1 - level),
                barWidth * 0.64, meters.height * level
            )
            fill(soft)
            textSize(11)
            drawText("\(channel)", x + barWidth / 2, meters.y + meters.height + 6)
        }

        // Brackets grouping each fixture's three channels, the patch made visible.
        stroke(ink)
        strokeWeight(1.2)
        textAlign(.center, .top)
        for (index, par) in pars.enumerated() {
            let left = meters.x + barWidth * (Double(par.address - 1) + 0.18)
            let right = meters.x + barWidth * (Double(par.address + 1) + 0.82)
            let y = meters.y + meters.height + 24
            drawLine(left, y, right, y)
            drawLine(left, y, left, y - 5)
            drawLine(right, y, right, y - 5)
            noStroke()
            fill(index == 3 ? accent : soft)
            textSize(12)
            drawText("par \(index + 1)", (left + right) / 2, y + 5)
            stroke(ink)
        }
        noStroke()

        // Callouts: what the code did, and what travels.
        textAlign(.left, .top)
        fill(ink)
        textSize(15)
        drawText("rig.set(par, color:)  lights the lamp …", 60, 16)
        textAlign(.right, .top)
        drawText("… dmx.send(rig)  ships the bytes", 820, 16)
        textAlign(.left, .top)
        fill(accent)
        textSize(13)
        drawText("par 4 at dimmer 0.35: the low lamp is the low bytes", 60, 532)
        fill(soft)
        drawText("one universe = 512 channels; a fixture is an address plus what its channels mean", 60, 556)
    }
}
