import Ollin
import OllinSyphon

/// Subscribes to a **Syphon source** published by another app — openFrameworks
/// (via `ofxSyphon`), Resolume, MadMapper, VDMX, Syphon's Simple Server, or
/// another Ollin sketch (`SyphonLoopback`) — and draws its live frames,
/// letterboxed to fit. The "see what's out there" tool, mirroring `OSCMonitor` /
/// `MIDIMonitor`.
///
/// Unlike the self-contained loopback, this needs a source to view: start one of
/// the apps above, then run this. With no source it lists what (if anything) it
/// can see. It takes the first available source by default; pass a name to
/// `SyphonClient(named:)` to pick a specific one.
@main
final class SyphonViewer: Sketch {

    let feed = SyphonClient()   // first available source
    var lastSeen = -1.0

    override func setup() {
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.05))

        // Keep trying to (re)connect while there's nothing live (gently — each
        // attempt opens and drops a connection).
        if !feed.isActive, time - lastSeen > 1.5 {
            feed.reconnect()
            lastSeen = time
        }

        if let frame = feed.newFrame() {
            // Letterboxed to fit, centered — the same fit `drawFrame` does.
            drawImage(frame, in: Rectangle(fitting: Vector2(Double(frame.width), Double(frame.height)),
                                           in: bounds))
            fill(Color(white: 0.7))
            textSize(22 * scale)
            let title = [feed.serverName, feed.appName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            drawText("◉ \(title.isEmpty ? "Syphon source" : title)", 30 * scale, 50 * scale)
        } else {
            drawWaiting()
        }
    }

    private func drawWaiting() {
        fill(Color(white: 0.7))
        textSize(28 * scale)
        drawText("Waiting for a Syphon source…", 30 * scale, 60 * scale)

        let sources = SyphonClient.availableServers()
        fill(Color(white: 0.45))
        textSize(20 * scale)
        if sources.isEmpty {
            drawText("(none found — start one and it'll appear)", 30 * scale, 100 * scale)
        } else {
            for (i, source) in sources.enumerated() {
                drawText("• \(source.label)", 30 * scale, (100 + Double(i) * 28) * scale)
            }
        }
    }
}
