import Foundation
import Ollin
import OllinVideo

/// Plays a video file as a live image. By default it loops a bundled clip —
/// *Voladores de Papantla México* by José Millán (Jmillan325), 2018, via
/// Wikimedia Commons, CC BY-SA 4.0; trimmed and re-encoded for bundling
/// (https://commons.wikimedia.org/wiki/File:Voladores_de_Papantla_México.webm)
/// — so it runs out of the box. Pass a path on launch to play your own video:
///
/// ```
/// swift run Example-Video-VideoPlayback /path/to/your/clip.mp4
/// ```
///
/// Each decoded frame arrives as a GPU texture wrapped in an `Image`, drawn
/// letterboxed with `drawFrame`; the thin line along the bottom is playback
/// progress (`currentTime` over `duration`).
@main
final class VideoPlayback: Sketch {
    var player: VideoPlayer?

    override func setup() {
        noStroke()
        let player = makePlayer()
        player?.loops = true
        player?.play()
        self.player = player
    }

    /// A readable file path passed on launch overrides the bundled clip.
    private func makePlayer() -> VideoPlayer? {
        if let path = CommandLine.arguments.dropFirst().first(where: {
            !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0)
        }) {
            return try? VideoPlayer(path: path)
        }
        return try? VideoPlayer(resource: "voladores", withExtension: "mp4", in: .module)
    }

    override func draw() {
        background(Color(white: 0.06))
        guard let player else { return }

        drawFrame(player)

        // Playback progress along the bottom edge.
        if let duration = player.duration, duration > 0 {
            let progress = min(1, player.currentTime / duration)
            fill(Color(white: 0.92))
            drawRect(0, height - 5 * scale, width * progress, 5 * scale)
        }

        drawCaption("Voladores de Papantla · José Millán (CC BY-SA)", edge: .top)
    }
}
