import Ollin
import OllinOSC

/// A full OSC round-trip, on screen. The sketch runs *both* ends: every frame an
/// `OSCSender` sends an animated position and level to `127.0.0.1`, and an
/// `OSCReceiver` listening on the same port reads them back. The glowing dot is
/// drawn from the *received* values — so what you see is the message making the
/// trip out over UDP and back, not the local variables.
///
/// It's self-contained on purpose (like the audio `Spectrum` example): no second
/// app, no hardware. To drive it from a real controller instead, point a phone
/// running TouchOSC — or any OSC source — at this Mac's IP on `port`, sending
/// `/ollin/x`, `/ollin/y` (0…1) and `/ollin/level`. To watch what it emits, aim a
/// monitor like Protokol at the same port.
@main
final class OSCLoopback: Sketch {

    let port = 5005
    var sender: OSCSender!
    let receiver = OSCReceiver(port: 5005)
    let palette = CosinePalette.neon

    override func setup() {
        sender = OSCSender(host: "127.0.0.1", port: port)
        try? receiver.start()
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.06))

        // Send a Lissajous path and a breathing level out to ourselves.
        let tx = Float(0.5 + 0.42 * sin(time * 0.7))
        let ty = Float(0.5 + 0.42 * sin(time * 0.9 + 1.3))
        let level = Float(unipolar(sin(time * 2.1)))
        sender.send("/ollin/x", .float(tx))
        sender.send("/ollin/y", .float(ty))
        sender.send("/ollin/level", .float(level))

        // Read back whatever has arrived (the previous frame's send, after its
        // trip through the kernel's loopback). Defaults cover the first frame.
        let x = Double(receiver.float("/ollin/x", default: 0.5)) * width
        let y = Double(receiver.float("/ollin/y", default: 0.5)) * height
        let lvl = Double(receiver.float("/ollin/level", default: 0))

        let center = Vector2(x, y)
        let radius = (40 + lvl * 160) * scale

        withState {
            fill(Color(white: 1, alpha: 0.12))
            drawCircle(center: center, radius: radius * 2.1)
            fill(palette.color(at: 0.2 + lvl * 0.6))
            drawCircle(center: center, radius: radius)
        }

        // A label, in screen space, in the system font.
        fill(Color(white: 0.6))
        textSize(22 * scale)
        drawText("OSC ↺ 127.0.0.1:\(port)", 30 * scale, 50 * scale)
    }
}
