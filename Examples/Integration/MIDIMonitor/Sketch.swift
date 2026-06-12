import Ollin
import OllinMIDI

/// A live MIDI monitor. It listens to every connected MIDI device and shows
/// everything that arrives, so you can plug in a controller and discover what each
/// knob, pad, and key sends just by touching it.
///
///   swift run Example-MIDIMonitor
///
/// Devices plugged in while it's running connect automatically. The companion
/// `MIDILoopback` example needs no hardware; this one is for real gear. See
/// `Docs/MIDI.md` for the full walkthrough.
@main
final class MIDIMonitor: Sketch {

    lazy var midi = MIDIInput()

    var log: [String] = []          // recent messages, newest last
    var lastValue: Double = 0       // last scalar seen (0…1), for the pulse
    var lastSeenFrame = -999

    override func setup() {
        do { try midi.start() }
        catch { print("could not start MIDI input: \(error)") }
        let names = midi.sources.map(\.name).joined(separator: ", ")
        print("Listening to MIDI sources: \(names.isEmpty ? "(none yet — plug one in)" : names)")
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.08))

        // Drain everything received since the last frame: print it and keep a
        // rolling on-canvas log.
        for message in midi.messages() {
            let line = message.description
            print(line)
            log.append(line)
            if log.count > 22 { log.removeFirst(log.count - 22) }
            if let value = message.value { lastValue = Double(value) / 127 }
            else if let velocity = message.velocity { lastValue = Double(velocity) / 127 }
            lastSeenFrame = frameCount
        }

        // A pulse, so motion is obvious when you wiggle a knob or hit a pad.
        let live = frameCount - lastSeenFrame < 30
        fill(live ? Color(red: 0.55, green: 0.5, blue: 0.95) : Color(white: 0.3))
        drawCircle(width - 120 * scale, 90 * scale, (18 + lastValue * 70) * scale)

        // Header.
        let names = midi.sources.map(\.name).joined(separator: ", ")
        fill(Color(white: 0.95))
        textSize(30 * scale)
        drawText("MIDI monitor", 40 * scale, 70 * scale)
        fill(Color(white: 0.5))
        textSize(20 * scale)
        drawText(names.isEmpty ? "no devices yet — plug one in" : names, 40 * scale, 105 * scale)

        // The rolling message log.
        textSize(22 * scale)
        var y = 170.0 * scale
        if log.isEmpty {
            fill(Color(white: 0.4))
            drawText("waiting for MIDI… turn a knob or press a key", 40 * scale, y)
        }
        fill(Color(white: 0.8))
        for line in log {
            drawText(line, 40 * scale, y)
            y += 30 * scale
        }
    }
}
