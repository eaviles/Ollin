import Ollin

/// Cutout: a piece that leaves its background behind. `background(.clear)`
/// makes the canvas see-through, and every export keeps that: `--export`
/// writes a PNG with an alpha channel, `--export-sequence` a folder of them,
/// and `--export-video` a clip with an alpha channel through the two codecs
/// that carry one, so the piece lands over a camera feed or another layer in
/// a compositing or VJ program instead of over black. The window shows the
/// same frame over black; open the file to see the cut.
///
/// ```sh
/// swift run Example-Export-Cutout --export /tmp/cutout.png
/// swift run Example-Export-Cutout --export-video /tmp/cutout.mov --codec proRes4444 --seconds 4
/// swift run Example-Export-Cutout --export-video /tmp/cutout.mp4 --codec hevcWithAlpha --seconds 4
/// ```
@main
final class Cutout: Sketch {
    @Param("Lobes", 3 ... 12, icon: "circle.hexagongrid") var lobes = 7
    @Param("Spread", 0.1 ... 0.4, icon: "arrow.up.left.and.arrow.down.right") var spread = 0.24
    @Param("Opacity", 0.2 ... 1.0, icon: "circle.lefthalf.filled") var opacity = 0.7

    override func draw() {
        background(.clear)
        noStroke()
        let c = center
        let reach = min(width, height) * spread
        for i in 0..<lobes {
            let turn = Double(i) / Double(lobes)
            let angle = turn * .tau + time * 0.3
            let wobble = 1 + 0.25 * sin(time * 1.7 + turn * .tau * 2)
            let p = c + Vector2(cos(angle), sin(angle)) * (reach * wobble)
            fill(Color(hue: turn, saturation: 0.8, brightness: 0.95, alpha: opacity))
            drawCircle(center: p, radius: reach * 0.9)
        }
        // A ring around the cluster, so the piece has an edge over any backdrop.
        noFill()
        stroke(.white)
        strokeWeight(6)
        drawCircle(center: c, radius: reach * 2.2)
    }
}
