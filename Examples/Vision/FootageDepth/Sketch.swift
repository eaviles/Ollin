import Foundation
import Ollin
import OllinVideo
import OllinVision

/// The whole clip's depth, read ahead of time: a recording goes through the
/// video depth model's published inference once, in windows of 32 frames, and
/// every frame's map is then answered by clip time. Contour lines of that
/// depth are drawn over the footage, colored far to near, so they follow the
/// flyers down the pole and hold still where the picture does. The pass runs
/// in the background the first time (a progress bar counts it up, a second or
/// two a window) and is cached, so the next launch opens at once. Export it
/// (`--export-video`) and the lines land on the same frames every time, which
/// a live tracker over a playing clip cannot promise. Pass a path on launch to
/// read your own clip:
///
/// ```
/// swift run Example-Vision-FootageDepth /path/to/your/clip.mp4
/// ```
///
/// The bundled clip is *Voladores de Papantla México* by José Millán
/// (Jmillan325), 2018, via Wikimedia Commons, CC BY-SA 4.0; trimmed and
/// re-encoded for bundling
/// (https://commons.wikimedia.org/wiki/File:Voladores_de_Papantla_México.webm).
/// The model weights aren't in the repo: run `Scripts/fetch-models.sh` once
/// and relaunch (the sketch says so on the canvas until then).
///
/// Model: Video Depth Anything (small), converted to Core ML on this machine
/// by `Scripts/convert-video-depth.sh`, Apache-2.0. Sili Chen et al., "Video
/// Depth Anything: Consistent Depth Estimation for Super-Long Videos" (CVPR
/// 2025), https://github.com/DepthAnything/Video-Depth-Anything. The package
/// is put in place by the fetch script, never bundled.
/// The fetched weights live in `Models/` at the repo root. This sketch runs
/// from there (the gallery compiles it where it sits) and from `Examples/` (a
/// direct `swift run`), so the folder is found by walking up from this file
/// instead of trusting whatever the working directory happens to be.
private func modelsPath(_ name: String) -> String {
    sketchResource(name) ?? ("Models" as NSString).appendingPathComponent(name)
}

@main
final class FootageDepth: Sketch {
    static let modelPath = modelsPath("VideoDepthAnythingSmallClipF16.mlpackage")

    /// How many contour levels between far and near.
    @Param(3 ... 16, icon: "lines.measurement.horizontal") var levels = 8
    /// Draw the depth map itself under the lines, as a haze on the far ground.
    @Param(icon: "cloud.fog") var showsMap = false

    var player: VideoPlayer?
    var depth: DepthClip?

    override func setup() {
        noStroke()
        guard let player = makePlayer() else { return }
        player.loops = true
        player.play()
        self.player = player
        // Created here, not lazily: a headless export runs the pass before its
        // first frame, and only finds the clip if it exists by the end of setup.
        if FileManager.default.fileExists(atPath: Self.modelPath) {
            depth = DepthClip(player, modelAt: URL(fileURLWithPath: Self.modelPath))
        }
    }

    /// A readable file path passed on launch overrides the bundled clip.
    private func makePlayer() -> VideoPlayer? {
        // A flag's own value (an export path, say) is not a clip: skip each
        // flag and the argument that follows it.
        let arguments = Array(CommandLine.arguments.dropFirst())
        var isDirectory: ObjCBool = false
        for (i, argument) in arguments.enumerated() where !argument.hasPrefix("-") {
            if i > 0, arguments[i - 1].hasPrefix("-") { continue }
            if FileManager.default.fileExists(atPath: argument, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                return try? VideoPlayer(path: argument)
            }
        }
        return try? VideoPlayer(resource: "voladores", withExtension: "mp4", in: .module)
    }

    override func draw() {
        background(Color(white: 0.04))
        guard let player else { return }

        // The weights are fetched, not committed; point at the script instead
        // of failing silently when they aren't there yet.
        guard let depth else {
            drawFrame(player)
            return drawStatus("The video depth model's clip window isn't built yet.\n" +
                              "Run Scripts/fetch-models.sh, then relaunch.",
                              style: .warning)
        }

        // The footage, dimmed; the lines carry the picture.
        tint(Color(white: 0.35))
        guard let rect = drawFrame(player) else { return noTint() }
        noTint()

        if let reason = depth.unavailableReason {
            return drawStatus(reason, style: .warning)
        }
        if !depth.isReady {
            drawStatus("Reading the clip's depth ahead of time…\n" +
                       "\(Int(depth.progress * 100))%, once; the result is kept for next time.")
            fill(Color(white: 0.92))
            drawRect(0, height - 5 * scale, width * depth.progress, 5 * scale)
            return
        }

        if showsMap, let map = depth.map {
            tint(Color(white: 0.9, alpha: 0.5))
            drawImage(map, in: rect)
            noTint()
        }

        // The level curves of the depth map, far to near, each in the color
        // the depth reads at that level. The field samples the clip under
        // canvas points, so the lines land on the picture by construction.
        let steps = (1...levels).map { Double($0) / Double(levels + 1) }
        let rings = isolines(at: steps, in: rect, resolution: 120) { p in
            depth.value(at: p, in: rect)
        }
        noFill()
        strokeWeight(2 * scale)
        for (level, contours) in zip(steps, rings) {
            stroke(Colormap.turbo.color(at: level))
            for contour in contours {
                drawPolyline(contour.points, closed: contour.isClosed)
            }
        }
        noStroke()

        drawCaption("FootageDepth: the whole clip's depth, read ahead of time, so an export lands the lines on the same frames every time")
    }
}
