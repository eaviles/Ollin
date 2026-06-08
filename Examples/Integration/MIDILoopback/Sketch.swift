import Ollin
import OllinMIDI

/// A self-contained MIDI round trip — no hardware needed. The sketch opens a
/// *virtual source* and sends control-change messages to itself; a `MIDIInput`
/// connected to that source reads them back, and the picture is what it receives.
///
///   swift run Example-MIDILoopback
///
/// It also shows the softening a `@Param` can carry: the incoming value steps
/// (like a knob jumped to a new position every so often), but `radius` is bound to
/// a smoothed param, so the filled circle *glides* toward each new step while the
/// thin ring marks the raw target it's chasing. The companion `MIDIMonitor`
/// example is the one for real gear. See `Docs/MIDI.md`.
@main
final class MIDILoopback: Sketch {

    let out = MIDIOutput()
    lazy var midi = MIDIInput()

    // Bound to incoming CC 1. The smoothing is what makes the stepped input glide.
    @Param(40...400, smoothing: .eased(0.45)) var radius = 120.0

    var rawValue = 64        // last value sent/received, 0…127
    var nextStepFrame = 0

    override func setup() {
        // Open the virtual source first, then connect the input to it.
        do {
            try out.openVirtual(named: "Ollin Loopback")
            try midi.start()
        } catch {
            print("could not open MIDI loopback: \(error)")
        }
        midi.bind(controlChange: 1, to: $radius)   // CC 0…127 → 40…400, glided
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.08))

        // Every ~0.75s, "turn the knob" to a new spot and send it to ourselves.
        if frameCount >= nextStepFrame {
            rawValue = Int(random(0, 127))
            out.controlChange(1, value: rawValue)
            nextStepFrame = frameCount + 45
        }

        // What the input actually received (drives the cache + the bound param).
        let received = midi.controlValue(1, default: rawValue)
        let targetRadius = map(Double(received), 0, 127, 40, 400) * scale

        // The thin ring is the raw target; the filled circle is the smoothed param
        // gliding toward it — the gap between them is the softening in flight.
        let center = Vector2(width / 2, height / 2)
        stroke(Color(white: 0.35))
        strokeWeight(2 * scale)
        noFill()
        drawCircle(center: center, radius: targetRadius)

        noStroke()
        fill(Color(red: 0.55, green: 0.5, blue: 0.95))
        drawCircle(center: center, radius: radius * scale)

        // Labels.
        fill(Color(white: 0.95))
        textFont(OutlineFont.system)
        textSize(30 * scale)
        drawText("MIDI loopback — sending CC 1 to myself", 40 * scale, 70 * scale)
        fill(Color(white: 0.55))
        textSize(20 * scale)
        drawText("raw \(received)   →   radius \(Int(radius)) (smoothed)", 40 * scale, 105 * scale)
    }
}
