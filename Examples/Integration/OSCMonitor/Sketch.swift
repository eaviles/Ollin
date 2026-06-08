import Ollin
import OllinOSC

/// A live OSC monitor. It listens on a UDP port and shows everything that
/// arrives, so you can point a phone (TouchOSC, OSC/PILOT, …) or any OSC source
/// at this Mac and discover the addresses each control sends just by touching
/// them.
///
///   swift run Example-OSCMonitor
///
/// On the sender, set the destination host to this Mac's IP (find it with
/// `ipconfig getifaddr en0`) and the port to 8000, matching `listenPort` below.
/// The companion `OSCLoopback` example needs no external app; this one is for
/// talking to real gear. See `Docs/OSC.md` for the full walkthrough.
@main
final class OSCMonitor: Sketch {

    let listenPort = 8000
    lazy var osc = OSCReceiver(port: listenPort)

    var log: [String] = []          // recent messages, newest last
    var lastValue: Double = 0       // last float seen, for the pulse
    var lastSeenFrame = -999

    override func setup() {
        do { try osc.start() }
        catch { print("could not start receiver: \(error)") }
        print("Listening for OSC on :\(listenPort) — point a sender at this Mac's IP on port \(listenPort)")
        textFont(OutlineFont.system)
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.08))

        // Drain everything received since the last frame: print it and keep a
        // rolling on-canvas log.
        for message in osc.messages() {
            let line = describe(message)
            print(line)
            log.append(line)
            if log.count > 22 { log.removeFirst(log.count - 22) }
            if let value = message.float { lastValue = Double(value) }
            lastSeenFrame = frameCount
        }

        // A pulse, so motion is obvious when you wiggle a fader.
        let live = frameCount - lastSeenFrame < 30
        fill(live ? Color(red: 0.45, green: 0.85, blue: 0.6) : Color(white: 0.3))
        drawCircle(width - 120 * scale, 90 * scale, (18 + lastValue * 60) * scale)

        // Header.
        fill(Color(white: 0.95))
        textSize(30 * scale)
        drawText("OSC monitor — listening :\(listenPort)", 40 * scale, 70 * scale)
        fill(Color(white: 0.5))
        textSize(20 * scale)
        drawText("send OSC to this Mac's IP, port \(listenPort)", 40 * scale, 105 * scale)

        // The rolling message log.
        textSize(22 * scale)
        var y = 170.0 * scale
        if log.isEmpty {
            fill(Color(white: 0.4))
            drawText("waiting for messages… touch a control on the sender", 40 * scale, y)
        }
        fill(Color(white: 0.8))
        for line in log {
            drawText(line, 40 * scale, y)
            y += 30 * scale
        }
    }

    /// "/1/fader1   0.734" — the address followed by its arguments.
    func describe(_ message: OSCMessage) -> String {
        let parts = message.arguments.map { argument -> String in
            switch argument {
            case .int(let v): return "\(v)"
            case .float(let v): return String(format: "%.3f", v)
            case .double(let v): return String(format: "%.3f", v)
            case .int64(let v): return "\(v)"
            case .string(let s): return "\"\(s)\""
            case .bool(let b): return b ? "true" : "false"
            case .blob(let d): return "<\(d.count) bytes>"
            case .null: return "null"
            case .impulse: return "impulse"
            }
        }
        return message.address + "   " + parts.joined(separator: "  ")
    }
}
