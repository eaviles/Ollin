import Foundation
import Ollin
import OllinAudio

/// Reacts to a playing audio file. By default it loops a bundled CC0 clip — a
/// short excerpt of Bach's *Open Goldberg Variations* (Kimiko Ishizaka, public
/// domain) — so it runs out of the box. Pass a path on launch to play your own
/// track instead:
///
/// ```
/// swift run Example-FilePlayer /path/to/your/track.mp3
/// ```
///
/// Solo piano spreads energy across the spectrum: the bars along the bottom are
/// the frequency `spectrum`, and the line through the middle is the raw
/// `waveform` (an oscilloscope), both straight from `AudioPlayer`.
@main
final class FilePlayer: Sketch {
    var player: AudioPlayer?
    let bars = 96

    override func setup() {
        noStroke()
        textFont(OutlineFont.system)
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
        return try? AudioPlayer(resource: "goldberg", withExtension: "m4a", in: .module)
    }

    override func draw() {
        background(Color(white: 0.06))

        let spectrum = player?.spectrum ?? []
        let waveform = player?.waveform ?? []

        // Frequency spectrum: bars rising from the bottom.
        let barWidth = width / Double(bars)
        for i in 0..<min(bars, spectrum.count) {
            let mag = Double(spectrum[i])
            let h = min(sqrt(mag) * 1500 * scale, height * 0.55)
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

        // Title in screen space.
        fill(.white)
        textAlign(.center, .top)
        textSize(15 * scale)
        drawText("Bach · Open Goldberg Variations (CC0)", width / 2, 34 * scale)
    }
}
