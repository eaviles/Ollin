import Foundation
import Ollin
import OllinLink

/// One beat for the whole room. A `LinkClock` joins the local network's
/// shared tempo session (the Link protocol most music apps speak), and
/// musical time drives everything that moves: the center disk throbs on each
/// beat, the dots step around the bar, and the comet rides a ramp that takes
/// eight beats per lap. Every app in the session lands the same downbeat, so
/// run this beside a DAW, a drum machine app on a phone, or a second copy of
/// this sketch on another Mac, and they pulse together.
///
///   swift run Example-Integration-LinkTempo
///
/// Alone, the sketch free-runs at its own tempo, so it moves the same with
/// nothing to join; `peers` in the status line says which is happening. Turn
/// the BPM knob and the whole session follows the proposal; the session's
/// latest change wins, whoever makes it. See `Docs/Integration/Link.md`.
@main
final class LinkTempo: Sketch {

    let link = LinkClock(tempo: 120)

    @Param(60...180) var bpm = 120.0
    @Param var playing = false

    // Last values pushed to the session, so knob moves apply once and a
    // change arriving from a peer is not immediately overwritten.
    var sentBPM = 0.0
    var sentPlaying: Bool?

    override func setup() {
        link.start()
        sentBPM = bpm
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.08))
        applyKnobs()

        let accent = Color(red: 0.2, green: 0.75, blue: 0.7)
        let center = Vector2(width / 2, height / 2 + 40 * scale)

        // The heartbeat: snaps up on each beat and eases back down.
        fill(accent)
        drawCircle(center: center, radius: (120 + 55 * link.beat) * scale)

        // One dot per beat of the bar; the beat we're on burns bright. Bar
        // phase is the session's shared grid, so two machines light the same
        // dot at the same moment.
        let perBar = link.beatsPerBar
        let litBeat = Int(link.barPhase * Double(perBar)) % max(1, perBar)
        for i in 0..<perBar {
            let angle = Double(i) / Double(perBar) * .tau - .tau / 4
            let spot = center + Vector2(angle: angle) * 260 * scale
            let lit = i == litBeat
            fill(lit ? Color(white: 0.98) : Color(white: 0.3))
            drawCircle(center: spot, radius: (lit ? 26 : 14) * scale)
        }

        // The bar hand: sweeps once around per bar, in step across the session.
        let sweep = link.barPhase * .tau - .tau / 4
        stroke(Color(white: 0.5))
        strokeWeight(4 * scale)
        drawLine(center, center + Vector2(angle: sweep) * 210 * scale)
        noStroke()

        // The comet: one lap every eight beats, with a trail hung on earlier
        // points of the same ramp.
        for i in 0..<10 {
            let lag = Double(i) * 0.12
            let lap = link.progress(over: 8, phase: -lag / 8)
            let angle = lap * .tau - .tau / 4
            let spot = center + Vector2(angle: angle) * 380 * scale
            fill(accent.withAlpha(1 - Double(i) / 10))
            drawCircle(center: spot, radius: (16 - Double(i)) * scale)
        }

        // Labels.
        fill(Color(white: 0.95))
        textSize(30 * scale)
        drawText("Tempo sync: one beat for the whole network", 40 * scale, 70 * scale)
        fill(Color(white: 0.55))
        textSize(20 * scale)
        let status: String
        if link.peerCount > 0 {
            status = String(format: "%.1f BPM   %d peer%@   bar %d%@",
                            link.tempo, link.peerCount, link.peerCount == 1 ? "" : "s",
                            link.bar + 1,
                            link.isPlaying ? "   playing" : "")
        } else {
            status = String(format: "%.1f BPM   alone, free-running: start a Link app on this network to lock in",
                            link.tempo)
        }
        drawText(status, 40 * scale, 105 * scale)
    }

    /// Applies the knobs to the session, once per change: a BPM move proposes
    /// the new tempo, and `playing` flips the shared transport flag.
    func applyKnobs() {
        if bpm != sentBPM {
            sentBPM = bpm
            link.tempo = bpm
        }
        if playing != sentPlaying {
            sentPlaying = playing
            link.isPlaying = playing
        }
    }
}
