import Foundation
import Ollin
import OllinAudio

/// Reacts to a playing audio file. By default it loops a bundled clip — a
/// recording of *El Fandanguito*, a traditional Mexican *son huasteco* for solo
/// violin (performed by Cynthia Molina, CC BY-SA) — so it runs out of the box.
/// Pass a path on launch to play your own track instead:
///
/// ```
/// swift run Example-Audio-FilePlayer /path/to/your/track.mp3
/// ```
///
/// The violin spreads energy across the spectrum: the bars along the bottom are
/// the frequency `spectrum`, and the line through the middle is the raw
/// `waveform` (an oscilloscope), both straight from `AudioPlayer`.
@main
final class FilePlayer: Sketch {
    var player: AudioPlayer?
    let bars = 64

    override func setup() {
        noStroke()
        let player = makePlayer()
        player?.loops = true
        player?.play()
        self.player = player
    }

    /// A readable file path passed on launch overrides the bundled clip.
    private func makePlayer() -> AudioPlayer? {
        if let path = CommandLine.arguments.dropFirst().first(where: {
            !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0)
        }) {
            return try? AudioPlayer(path: path)
        }
        return try? AudioPlayer(resource: "fandanguito", withExtension: "m4a", in: .module)
    }

    override func draw() {
        // Whole-canvas flash on each detected beat (the violin's bowed onsets).
        let pulse = Double(player?.beat ?? 0)
        background(Color(white: 0.06 + 0.10 * pulse))

        let levels = player?.bands(bars) ?? []
        let waveform = player?.waveform ?? []

        // Frequency spectrum: normalized bands as bars rising from the bottom.
        let barWidth = width / Double(bars)
        for i in 0..<levels.count {
            let h = Double(levels[i]) * height * 0.55
            fill(Colormap.viridis.color(at: Double(i) / Double(bars - 1)))
            drawRect(Double(i) * barWidth, height - h, barWidth * 0.82, h)
        }

        // Waveform: an oscilloscope line through the upper third.
        if waveform.count > 1 {
            let midY = height * 0.38
            let step = width / Double(waveform.count - 1)
            let points = waveform.enumerated().map { i, s in
                Vector2(Double(i) * step, midY + Double(s) * height * 0.22)
            }
            noFill()
            stroke(Color(white: 0.92))
            strokeWeight(1.5 * scale)
            drawPolyline(points)
        }

        drawCaption("El Fandanguito · son huasteco (CC BY-SA)", edge: .top)
    }
}
