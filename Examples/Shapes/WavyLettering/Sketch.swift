import Ollin

/// Lettering that follows a wave. The glyph outlines of a word are taken out
/// as shapes (`textToShapes`) and bent from the straight baseline they were
/// set on along a wave that travels (`Shape.warped(from:along:)`): every
/// point of a letter is read as how far along the baseline it sits and how
/// far above or below it, and put back at the same place along the wave.
/// Tall letters stay tall, counters bend with their outlines, and the
/// straight edges bend too, since the warp adds points along them first.
///
/// A hand tugs the letters as well (`pulled(toward:amount:radius:)`): the
/// part of every outline within `reach` of the hand is drawn toward it,
/// fading smoothly to nothing at the edge of the reach, so the word bulges
/// where the hand is. Hold the mouse down to be the hand; otherwise it
/// circles on its own.
///
/// ```sh
/// swift run Example-Shapes-WavyLettering --export-loop /tmp/wavy-lettering.gif
/// ```
///
/// Every letter is a plain `Shape` on the way out, so `--export-svg` writes
/// the bent word as outlines.
@main
final class WavyLettering: Sketch {
    @Param(0 ... 160, icon: "water.waves") var amplitude = 80.0
    @Param(300 ... 1400, icon: "ruler") var wavelength = 760.0
    @Param(0 ... 1, icon: "hand.point.up.left") var tug = 0.55
    @Param(60 ... 500, icon: "circle.dashed") var reach = 240.0

    private let face = OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold
    private let word = "bending"
    private var glyphs: [Shape] = []
    private var baseline = Contour([], closed: false)
    private let period = 12.0
    override var loopDuration: Double? { period }

    override func setup() {
        textFont(face)
        textAlign(.center, .middle)
        textSize(196 * scale)
        glyphs = textToShapes(word, width / 2, height / 2)
        baseline = Contour([Vector2(0, height / 2), Vector2(width, height / 2)], closed: false)
    }

    override func draw() {
        background(Color(hex: 0x14161C))
        let phase = loopProgress(over: period) * .tau

        // The wave the baseline becomes: one lap of the loop slides it one
        // whole wavelength, so the clip repeats seamlessly.
        let ripple = Contour((0 ... 60).map { i -> Vector2 in
            let x = Double(i) / 60 * width
            let y = height / 2 + amplitude * scale * sin(x / (wavelength * scale) * .tau - phase)
            return Vector2(x, y)
        }, closed: false)

        // The hand: the mouse while it is held, otherwise a point that
        // swings round the outside of the word twice a lap, so the letters
        // it passes bulge toward it.
        let hand = mouseIsPressed
            ? mouse
            : Vector2(width / 2 + cos(phase * 2) * 470 * scale, height / 2 + sin(phase * 2) * 250 * scale)

        noStroke()
        for (i, glyph) in glyphs.enumerated() {
            let bent = glyph.warped(from: baseline, along: ripple)
                .pulled(toward: hand, amount: tug, radius: reach * scale)
            fill(Color(hue: 0.08 + Double(i) / Double(glyphs.count) * 0.5, saturation: 0.55, brightness: 0.96))
            drawShape(bent)
        }

        // The wave itself, faint, and the hand.
        noFill()
        stroke(Color(hex: 0xF4EAD6).withAlpha(0.18))
        strokeWeight(2 * scale)
        drawPolyline(ripple.points)
        noStroke()
        fill(Color(hex: 0xF4EAD6).withAlpha(mouseIsPressed ? 0.9 : 0.6))
        drawCircle(center: hand, radius: 9 * scale)
    }
}
