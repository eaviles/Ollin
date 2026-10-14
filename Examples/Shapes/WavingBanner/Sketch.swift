import Ollin

/// A banner waving on its pole. The banner is drawn flat, in a plain
/// rectangle: three stripes and a word. Then every outline is bent from that
/// rectangle into a four-sided patch whose top and bottom edges are waves
/// traveling away from the pole (`CoonsPatch`, `Shape.warped(from:into:)`).
/// A point a third of the way across the flat banner and halfway down lands
/// a third of the way along the waving top and bottom, halfway between them,
/// so the stripes and the letters ride the cloth together, and their
/// straight edges bend, since the warp adds points along them first.
///
/// The cloth is cut into narrow upright strips, each lit by how the wave
/// faces at its place along the banner, so the folds read as light and
/// shade. The far edge flutters more than the near one, which is held by the
/// pole. Hold the mouse down to take the far edge in your hand: the right
/// side of the patch becomes a curve through the mouse, and the whole
/// banner, word and all, follows it.
///
/// ```sh
/// swift run Example-Shapes-WavingBanner --export-loop /tmp/waving-banner.gif
/// ```
///
/// Every stripe and letter is a plain `Shape` on the way out, so
/// `--export-svg` writes the waving banner as outlines.
@main
final class WavingBanner: Sketch {
    @Param(0 ... 120, icon: "wind") var wind = 70.0
    @Param(1 ... 3, icon: "water.waves") var folds = 1.5
    @Param(0 ... 1, icon: "sun.max") var shading = 0.6

    private let face = OutlineFont(name: "AvenirNext-Heavy") ?? .systemBold
    private let word = "OLLIN"
    /// The flat banner, the rectangle everything is set in before it waves.
    private var flat = Rectangle(x: 0, y: 0, width: 1, height: 1)
    private var glyphs: [Shape] = []
    private let period = 6.0
    override var loopDuration: Double? { period }

    private let stripes = [Color(hex: 0x2B4C7E), Color(hex: 0xF2E6CF), Color(hex: 0xE3A13B)]

    override func setup() {
        flat = Rectangle(x: 200 * scale, y: 300 * scale, width: 760 * scale, height: 420 * scale)
        textFont(face)
        textAlign(.center, .middle)
        textSize(170 * scale)
        glyphs = textToShapes(word, flat.center.x, flat.center.y)
    }

    override func draw() {
        background(Color(hex: 0x14161C))
        let phase = loopProgress(over: period) * .tau

        // One edge of the cloth: a wave that travels away from the pole,
        // growing from nothing at the pole to the full wind at the far end.
        // The bottom lags the top a little, so the cloth twists.
        func edge(y: Double, lag: Double) -> Contour {
            Contour((0 ... 48).map { i -> Vector2 in
                let s = Double(i) / 48
                let swing = wind * scale * pow(s, 1.2)
                let wave = sin(s * folds * .tau - phase - lag)
                // The cloth shortens a little where it folds deepest.
                let x = flat.x + s * flat.width * (1 - 0.04 * wind / 120 * (1 + wave) * s)
                return Vector2(x, y + swing * wave)
            }, closed: false)
        }
        let top = edge(y: flat.y, lag: 0)
        let bottom = edge(y: flat.y + flat.height, lag: 0.5)
        let pole = Contour([flat.topLeft, flat.bottomLeft], closed: false)
        let topEnd = top.points[top.points.count - 1], bottomEnd = bottom.points[bottom.points.count - 1]
        let far = mouseIsPressed
            ? Contour(curveThrough: [topEnd, mouse, bottomEnd], closed: false)
            : Contour([topEnd, bottomEnd], closed: false)
        let cloth = CoonsPatch(top: top, right: far, bottom: bottom, left: pole)

        // The pole.
        noStroke()
        fill(Color(hex: 0x8A7A66))
        drawRect(flat.x - 22 * scale, flat.y - 80 * scale, 14 * scale, flat.height + 560 * scale)
        fill(Color(hex: 0xC9B79C))
        drawCircle(flat.x - 15 * scale, flat.y - 84 * scale, 13 * scale)

        // The stripes, cut into upright strips, each lit by the slope of
        // the wave at its place along the banner.
        let strips = 36
        for (k, color) in stripes.enumerated() {
            let band = flat.height / Double(stripes.count)
            for j in 0 ..< strips {
                let s0 = Double(j) / Double(strips), s1 = Double(j + 1) / Double(strips)
                let piece = Rectangle(x: flat.x + s0 * flat.width, y: flat.y + Double(k) * band,
                                      width: (s1 - s0) * flat.width + 0.5, height: band + 0.5)
                let s = (s0 + s1) / 2
                let slope = cos(s * folds * .tau - phase - 0.25) * pow(s, 0.6)
                let light = 1 + shading * 0.35 * slope
                fill(Color.mix(color, light >= 1 ? .white : .black, abs(light - 1)))
                drawShape(Shape(piece.contour.points).warped(from: flat, into: cloth, spacing: 6 * scale))
            }
        }

        // The word, set flat in the middle of the banner, rides the cloth.
        fill(Color(hex: 0x14161C))
        for glyph in glyphs {
            drawShape(glyph.warped(from: flat, into: cloth, spacing: 3 * scale))
        }

        // The cloth's edge, and the hand while it holds the far side.
        noFill()
        stroke(Color(hex: 0x14161C).withAlpha(0.5))
        strokeWeight(2 * scale)
        drawPolyline(cloth.contour.points, closed: true)
        if mouseIsPressed {
            noStroke()
            fill(Color(hex: 0xF4EAD6).withAlpha(0.9))
            drawCircle(center: mouse, radius: 9 * scale)
        }
    }
}
