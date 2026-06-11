import Foundation
import Ollin
import OllinVideo
import OllinVision

/// Vision over recorded footage: a `ContourDetector` attached to a `VideoPlayer`
/// exactly the way one attaches to a live `Camera`, tracing each frame into
/// vector `Shape`s as the clip plays — black line art fills the canvas while
/// the footage itself plays in a small inset, so it's clear what the trace is
/// following. By default it loops a bundled clip — *Voladores de Papantla
/// México* by José Millán (Jmillan325), 2018, via Wikimedia Commons, CC BY-SA
/// 4.0; trimmed and re-encoded for bundling
/// (https://commons.wikimedia.org/wiki/File:Voladores_de_Papantla_México.webm)
/// — so it runs out of the box. Pass a path on launch to trace your own video:
///
/// ```
/// swift run Example-VideoTrace /path/to/your/clip.mp4
/// ```
@main
final class VideoTrace: Sketch {
    var player: VideoPlayer?
    var contours: ContourDetector?

    override func setup() {
        textFont(OutlineFont.system)
        let player = makePlayer()
        player?.loops = true
        player?.isMuted = true
        player?.play()
        contours = player.map { ContourDetector($0, contrastAdjustment: 3) }
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
        background(.white)

        let margin = 40 * scale
        let container = Rectangle(x: margin, y: margin, width: width - 2 * margin, height: height - 2 * margin)
        guard let player, let contours, let rect = player.fittedRect(in: container) else {
            fill(Color(white: 0.5))
            textAlign(.center, .middle)
            textSize(22 * scale)
            drawText("Waiting for video…", width / 2, height / 2)
            return
        }

        // The traced contours as black line work — each is an Ollin Shape.
        noFill()
        stroke(Color(white: 0.1))
        strokeWeight(1.5 * scale)
        for shape in contours.shapes(in: rect) {
            drawShape(shape)
        }

        // The clip itself in a corner inset — the reference monitor the
        // full-canvas trace is following.
        if let frame = player.frame {
            let inset = Rectangle(
                x: rect.x + rect.width * 0.72,
                y: rect.y + rect.height - rect.height * 0.26 - 12 * scale,
                width: rect.width * 0.26,
                height: rect.height * 0.26
            )
            drawImage(frame, in: inset)
            noFill()
            stroke(Color(white: 0.1))
            strokeWeight(1 * scale)
            drawRect(inset)
        }

        // Screen-space label with the live contour count.
        fill(Color(white: 0.1))
        noStroke()
        textAlign(.center, .bottom)
        textSize(15 * scale)
        drawText("VideoTrace — \(contours.count) contours", width / 2, height - 28 * scale)
    }
}
