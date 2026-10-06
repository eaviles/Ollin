import Ollin
import OllinSamplePhotos

/// A profile drawn with one line in the order of a space-filling curve.
///
/// The picture is stippled (dots packed by darkness, the bright ground left
/// empty), and the dots are sorted by their place along a Hilbert curve laid
/// over them (`hilbertSorted`), so one line visits every dot with each step
/// near the last. It is a single sort where `singleLine` runs a tour, so it
/// is ready the moment the stipple is, and the line reads as the picture
/// with the curve's own square turns showing through in the shading.
///
/// `level` is how fine the curve is. At 16 it is finer than a pixel and the
/// order is the dots' own. At a low level the curve is drawn faintly under
/// the line to show the order it imposes: the dots in one of its cells keep
/// their given order, so the line scribbles through each cell before moving
/// to the next, and the scribble shrinks as the level rises.
///
/// The drawing plays out as a reveal. `--export-svg out.svg --frame 720`
/// writes the whole line for a plotter.
@main
final class HilbertLine: Sketch {
    @Param(1 ... 16, icon: "square.grid.3x3") var level = 16

    override var loopDuration: Double? { 24 }

    private var dots: [Vector2] = []
    private var box = Rectangle(x: 0, y: 0, width: 1, height: 1)
    private var line: [Vector2] = []
    private var curve: [Vector2] = []
    private var sortedAt = -1

    override func setup() {
        seed(4)
        let frame = canvasRectangle.inset(by: 96)
        let picture = SamplePhoto.profile.load().resized(width: 340, height: 340)
        // Dots by darkness, and none where the plain ground is lighter than
        // the cutoff, so the backdrop stays bare.
        let cutoff = Color(white: 0.62).luminance
        dots = stipple(count: 3600, in: frame, iterations: 45) { p in
            let px = min(max(Int((p.x - frame.x) / frame.width * Double(picture.width)), 0), picture.width - 1)
            let py = min(max(Int((p.y - frame.y) / frame.height * Double(picture.height)), 0), picture.height - 1)
            let tone = picture[px, py].luminance
            return tone < cutoff ? 1 - tone : 0
        }
        box = Shape(dots, closed: false).bounds ?? frame
    }

    override func draw() {
        if level != sortedAt { sort() }
        background(Color(hex: 0xF5F2EA))
        guard line.count > 2 else { return }

        noFill()
        strokeJoin(.round)
        if !curve.isEmpty {
            stroke(Color(hex: 0xC9B9A2).withAlpha(0.6))
            strokeWeight(1.2 * scale)
            drawPolyline(curve)
        }

        // Draw in, hold, unwind: an eased out-and-back sweep over the loop.
        let sweep = Easing.smoothstep(pingPong(over: 24))
        let visible = max(2, Int(Double(line.count) * sweep))
        stroke(Color(hex: 0x1A1B26))
        strokeWeight(1.7 * scale)
        drawPolyline(Array(line.prefix(visible)))

        drawCaption(level == 16 ? "3,600 stipples, one line in Hilbert order"
                                : "3,600 stipples in Hilbert order, level \(level) of 16")
    }

    /// The dots in curve order, and the curve itself through the cells of
    /// the grid over the dots' bounds when it is coarse enough to see.
    private func sort() {
        sortedAt = level
        line = hilbertSorted(dots, level: level)
        curve = []
        guard level <= 6 else { return }
        let n = 1 << level
        var centers: [Vector2] = []
        for row in 0 ..< n {
            for column in 0 ..< n {
                centers.append(Vector2(box.x + (Double(column) + 0.5) / Double(n) * box.width,
                                       box.y + (Double(row) + 0.5) / Double(n) * box.height))
            }
        }
        curve = hilbertSorted(centers, level: level)
    }
}
