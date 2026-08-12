import Ollin
import OllinDMX

/// A full DMX round-trip, on screen. The sketch runs *both* ends: every frame
/// a `DMXSender` fills universe 1 with a color chase for a row of RGB pars and
/// sends it to `127.0.0.1` as sACN, and a `DMXReceiver` on the same port reads
/// it back. The stage is lit from the *received* channels, so what you see is
/// the universe making the trip out over UDP and back, not the local values.
///
/// It's self-contained on purpose (like `OSCLoopback`): no console, no
/// hardware. To light a real rig instead, point the sender at a node's IP
/// (`DMXSender(sACN: "192.168.1.20")` or `DMXSender(artNet: …)`), or use plain
/// `DMXSender()` to multicast so any listening sACN node picks it up. To drive
/// the stage from a real console, aim it at this Mac on universe 1 and drop
/// the local send.
@main
final class DMXLoopback: Sketch {

    let sender = DMXSender(sACN: "127.0.0.1")
    let receiver = DMXReceiver()

    /// Eight RGB pars patched back to back: channels 1-3, 4-6, ... 22-24.
    var pars: [DMXFixture] = []

    override func setup() {
        var address = 1
        for _ in 0..<8 {
            let par = DMXFixture.rgb(at: address)
            pars.append(par)
            address = par.nextAddress
        }
        try? receiver.start()
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.05))

        // The console half: fill universe 1 with a slow color chase and a
        // breathing master level, and put it on the wire.
        var universe = DMXUniverse()
        let master = 0.6 + 0.4 * sin(time * 0.8)
        for (index, par) in pars.enumerated() {
            let phase = time * 0.35 + Double(index) / Double(pars.count)
            let color = Color(hue: phase.truncatingRemainder(dividingBy: 1), saturation: 0.9, brightness: 1)
            universe.set(par, color: color, dimmer: master)
        }
        sender.send(universe)

        // The rig half: light the drawn pars from what actually arrived.
        let hangY = height * 0.22
        let spacing = width / Double(pars.count + 1)
        for (index, par) in pars.enumerated() {
            let x = spacing * Double(index + 1)
            let color = receiver.color(at: par.address)
            drawPar(at: Vector2(x, hangY), color: color)
        }

        drawChannelMeters(universe: receiver.universe() ?? DMXUniverse())

        fill(Color(white: 0.6))
        textSize(22 * scale)
        drawText("sACN ↺ 127.0.0.1:\(SACNDataPacket.port)   universe 1", 30 * scale, 50 * scale)
    }

    /// A hanging par: a small body on the truss and its thrown light below.
    func drawPar(at position: Vector2, color: Color) {
        let brightness = max(color.red, max(color.green, color.blue))
        withState {
            // The beam, as soft stacked glows reaching down the stage.
            let throwCenter = position + Vector2(0, height * 0.34)
            fill(color.withAlpha(0.10 * brightness))
            drawCircle(center: throwCenter, radius: 170 * scale)
            fill(color.withAlpha(0.22 * brightness))
            drawCircle(center: throwCenter, radius: 110 * scale)
            fill(color.withAlpha(0.5 * brightness))
            drawCircle(center: throwCenter, radius: 55 * scale)
            // The fixture body and its lens.
            fill(Color(white: 0.22))
            drawRect(center: position, width: 46 * scale, height: 60 * scale)
            fill(color.withAlpha(0.3 + 0.7 * brightness))
            drawCircle(center: position + Vector2(0, 22 * scale), radius: 16 * scale)
        }
        // The truss line.
        withState {
            fill(Color(white: 0.16))
            drawRect(0, position.y - 38 * scale, width, 8 * scale)
        }
    }

    /// The first 24 channels of the received universe as meter bars, the raw
    /// bytes behind the light.
    func drawChannelMeters(universe: DMXUniverse) {
        let channels = 24
        let barWidth = width * 0.72 / Double(channels)
        let left = (width - barWidth * Double(channels)) / 2
        let baseline = height * 0.88
        let maxBar = height * 0.14
        for channel in 1...channels {
            let level = universe.level(channel)
            let x = left + barWidth * Double(channel - 1)
            withState {
                fill(Color(white: 0.14))
                drawRect(x + barWidth * 0.15, baseline - maxBar, barWidth * 0.7, maxBar)
                fill(Color(white: 0.85).withAlpha(0.25 + 0.75 * level))
                drawRect(x + barWidth * 0.15, baseline - maxBar * level, barWidth * 0.7, maxBar * level)
            }
        }
        fill(Color(white: 0.45))
        textSize(16 * scale)
        drawText("channels 1-\(channels)", left, baseline + 34 * scale)
    }
}
