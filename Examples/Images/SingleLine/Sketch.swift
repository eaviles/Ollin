import Ollin
import OllinSamplePhotos

/// A profile drawn with one unbroken line.
///
/// `singleLine(of:points:)` stipples an image (dots packed by darkness) and
/// then tours the dots into a single continuous path, the traveling-salesman
/// rendering: shadow pulls the line into tight meanders, light lets it
/// stride, and the one line reads as the picture. `cutoff` rounds the bright
/// ground up to empty, so the plain backdrop stays genuinely blank instead of
/// collecting a thin wandering thread.
///
/// The tour is computed once in `setup()` and the drawing plays out as a
/// reveal: the line draws itself forward, holds, and unwinds. Because the
/// output is a plain `Contour`, the same sketch exports clean vector line
/// work: try `--export-svg out.svg --frame 900` (the reveal's full-line
/// moment), the friendliest thing a pen plotter can be handed.
///
/// The picture is one of the bundled sample photographs, a woman in profile
/// on a plain ground, handed over as a small copy: the stipple reads density,
/// not detail.
@main
final class SingleLine: Sketch {
    override var loopDuration: Double? { 30 }

    private var line: Contour = Contour([], closed: false)

    override func setup() {
        seed(4)
        let frame = canvasRectangle.inset(by: 96)
        let picture = SamplePhoto.profile.load().resized(width: 340, height: 340)
        line = singleLine(of: picture, points: 3600, in: frame,
                          iterations: 45, cutoff: 0.62)
    }

    override func draw() {
        background(Color(hex: 0xF5F2EA))
        guard line.points.count > 2 else { return }

        // Draw in, hold, unwind: an eased out-and-back sweep over the loop.
        let sweep = Easing.smoothstep(pingPong(over: 30))
        let visible = max(2, Int(Double(line.points.count) * sweep))

        noFill()
        stroke(Color(hex: 0x1A1B26))
        strokeWeight(1.7 * scale)
        strokeJoin(.round)
        drawPolyline(Array(line.points.prefix(visible)),
                     closed: visible == line.points.count)

        drawCaption("3,600 stipples, one continuous line")
    }
}
