import Ollin
import OllinSyphon

/// A full Syphon round-trip, on screen. The sketch runs *both* ends: it publishes
/// its own rendered frames as a Syphon source, and a `SyphonClient` subscribes to
/// that same source and draws what it receives back as an inset. The inset is the
/// frame making the trip out to Syphon and back — and because the inset is itself
/// part of the next published frame, you get an infinite-mirror video-feedback
/// tunnel, which is the round-trip made visible.
///
/// It's self-contained on purpose (like the `OSCLoopback` example): no second app
/// needed. To prove the *cross-app* path, run it and open Syphon's Simple Client
/// (or an `ofxSyphon` sketch, Resolume, MadMapper, …) — "Ollin Loopback" appears
/// as a source. To go the other way, run `SyphonViewer` and point it here.
@main
final class SyphonLoopback: Sketch {

    let sourceName = "Ollin Loopback"
    var feed: SyphonClient!
    let palette = CosinePalette.neon

    override func setup() {
        publishSyphon(name: sourceName)        // share every frame
        feed = SyphonClient(named: sourceName) // … and subscribe to ourselves
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.05))

        // A lively main element so the picture isn't only mirrors: an orbiting
        // ring of dots plus a breathing core.
        let center = Vector2(width * 0.5, height * 0.5)
        let count = 12
        for i in 0..<count {
            let a = time * 0.6 + Double(i) / Double(count) * .tau
            let r = (180 + sin(time * 1.3 + Double(i)) * 60) * scale
            let p = center + Vector2(angle: a) * r
            fill(palette.color(at: Double(i) / Double(count)))
            drawCircle(center: p, radius: (10 + 8 * sin(time * 2 + Double(i))) * scale)
        }
        fill(Color(white: 1, alpha: 0.9))
        drawCircle(center: center, radius: (24 + 10 * sin(time * 2)) * scale)

        // Reconnect to our own source once it's been announced (the server starts
        // on the first published frame, so the client connects a frame or two in).
        if !feed.isActive { feed.reconnect(named: sourceName) }

        // Draw the received frame as a slightly inset, slightly rotated panel — the
        // recursion makes a feedback tunnel that proves the loop is live.
        if let frame = feed.newFrame() {
            withState {
                translate(center)
                rotate(0.04 * sin(time * 0.5))
                scale(0.82)
                translate(Vector2(-center.x, -center.y))
                drawImage(frame, in: Rectangle(x: 0, y: 0, width: width, height: height))
            }
        }

        fill(Color(white: 0.6))
        textSize(22 * scale)
        let status = feed.isActive ? "live" : "connecting…"
        drawText("Syphon ↺ \"\(sourceName)\" — \(status)", 30 * scale, 50 * scale)
    }
}
