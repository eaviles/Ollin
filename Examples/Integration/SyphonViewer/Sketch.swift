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
        textFont(OutlineFont.system)
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
            drawImage(frame, in: aspectFit(imageWidth: frame.width, imageHeight: frame.height))
            fill(Color(white: 0.7))
            textSize(22 * scale)
            let title = [feed.serverName, feed.appName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — ")
            drawText("◉ \(title.isEmpty ? "Syphon source" : title)", 30 * scale, 50 * scale)
        } else {
            drawWaiting()
        }
    }

    /// The rect that fits an `imageWidth`×`imageHeight` frame inside the canvas
    /// without distortion (letterbox), centered.
    private func aspectFit(imageWidth: Int, imageHeight: Int) -> Rectangle {
        guard imageWidth > 0, imageHeight > 0 else {
            return Rectangle(x: 0, y: 0, width: width, height: height)
        }
        let imageAspect = Double(imageWidth) / Double(imageHeight)
        let canvasAspect = width / height
        let w = imageAspect > canvasAspect ? width : height * imageAspect
        let h = imageAspect > canvasAspect ? width / imageAspect : height
        return Rectangle(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
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
