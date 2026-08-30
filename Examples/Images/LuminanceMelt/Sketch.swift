import Ollin

/// A painted dusk seascape poured through the luminance melt.
///
/// `.melt` runs one displacement field twice: it warps a noise field's own
/// domain, and the same displacement shifts where the picture is sampled, so
/// the image smears along the field's currents while its brightness steers
/// the field back. Everything reads through a four-stop palette, which is
/// why the melt looks dyed rather than merely warped: the picture survives
/// as light and shadow, not as its own colors.
///
/// Hold the mouse to see the untouched painting; release and it pours again.
/// The field churns in place (the sway is a few slow, bounded sines), so the
/// melt drifts without ever sliding away.
///
/// The source is painted once in `setup()` (a low sun over ridged water), so
/// the sketch carries no asset.
@main
final class LuminanceMelt: Sketch {
    private var source = Image(width: 480, height: 480, color: .black)

    override func setup() {
        seed(7)
        paint()
    }

    override func draw() {
        background(.black)
        let painting = makeRenderTarget()
        withTarget(painting) {
            drawImage(source, in: canvasRectangle)
        }
        let shown = mouseIsPressed ? painting : painting.filtered(.melt(phase: time))
        drawImage(shown.image, in: canvasRectangle)
        drawCaption("one displacement warps the field and liquifies the picture; hold the mouse for the source")
    }

    /// The painting the melt liquifies: a dusk gradient, a low sun with a
    /// bright reflection column, and dark ridges of water. Strong tonal
    /// shapes matter more than color here; the melt reads brightness.
    private func paint() {
        let n = source.width
        for y in 0 ..< n {
            let v = (Double(y) + 0.5) / Double(n)
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n)

                // Sky: deep zenith warming toward the horizon line.
                let horizon = 0.55
                var tone = v < horizon
                    ? 0.2 + 0.6 * pow(v / horizon, 1.6)
                    : 0.34 - 0.22 * (v - horizon) / (1 - horizon)
                var warmth = clamp(0.4 + 0.6 * v / horizon, 0, 1)

                // The sun and its glow.
                let dx = u - 0.62, dy = (v - 0.34) * 1.1
                let sun = (dx * dx + dy * dy).squareRoot()
                if sun < 0.09 { tone = 0.98; warmth = 1 }
                else { tone += 0.3 * exp(-sun * 7) }

                if v >= horizon {
                    // Water: ridged rows, darker with depth, and a shimmer
                    // column under the sun.
                    let ridge = signedNoise(u * 26, v * 90) * 0.5
                    tone += ridge * 0.16
                    let column = exp(-abs(u - 0.62) * 9) * (1 - (v - horizon) * 1.4)
                    tone += max(0, column) * 0.42
                    warmth = 0.75
                }

                tone = clamp(tone + signedFbm(u * 7, v * 7, octaves: 3) * 0.03, 0, 1)
                let warm = Color.mix(Color(hex: 0x2A3550), Color(hex: 0xF6B36A), warmth)
                source[x, y] = Color.mix(.black, warm, tone)
            }
        }
    }
}
