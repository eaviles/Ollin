import Ollin

/// A shaded still life rebuilt as a print halftone screen.
///
/// `drawHalftone` lays the classic rotated dot grid over an image and sizes
/// every dot so its ink area matches the tone underneath: midtones become
/// even fields of marks, and shadows grow dots that merge into checkered
/// diamonds. The screen swings through a quarter turn over the loop, and the
/// picture never wavers, because tone lives in dot area, not dot placement.
/// A quarter turn is a whole lap: the square lattice repeats every 90
/// degrees, so the loop closes seamlessly.
///
/// The dots are real circles, so `--export-svg` writes them as vectors, the
/// pen-plotter reading of the same frame. Hold the mouse for the inverted
/// screen: light marks sized by brightness on a dark canvas.
///
/// The source is painted once in `setup()` (a lit sphere over soft paper
/// tones), so the sketch carries no asset.
@main
final class Halftone: Sketch {
    override var loopDuration: Double? { 12 }

    private var source = Image(width: 360, height: 360, color: .white)

    override func setup() {
        paint()
    }

    override func draw() {
        let angle = Double.pi / 4 + loopProgress(over: 12) * .pi / 2
        noStroke()
        if mouseIsPressed {
            background(Color(hex: 0x14161C))
            fill(Color(hex: 0xF2EDE2))
            drawHalftone(source, pitch: 13, angle: angle, inverted: true)
        } else {
            background(Color(hex: 0xF2EDE2))
            fill(Color(hex: 0x22242C))
            drawHalftone(source, pitch: 13, angle: angle)
        }
        drawCaption("area-exact dots on a turning screen; hold the mouse for the inverted reading")
    }

    /// The image the screen samples: a sphere lit from the upper left with a
    /// soft cast shadow, over gently graded paper. Smooth tonal ramps are
    /// where a halftone shines, every step of the gradient landing on its
    /// own dot size.
    private func paint() {
        let n = source.width
        // Unit light direction, toward the upper left and out of the page.
        let lightX = -0.45, lightY = -0.55
        let lightZ = (1 - lightX * lightX - lightY * lightY).squareRoot()
        for y in 0 ..< n {
            let v = (Double(y) + 0.5) / Double(n)
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n)

                // Paper: lit from above, faintly textured.
                var tone = 0.93 - 0.15 * v + signedFbm(u * 3, v * 3, octaves: 3) * 0.03

                let dx = (u - 0.45) / 0.26
                let dy = (v - 0.42) / 0.26
                let d2 = dx * dx + dy * dy
                if d2 <= 1 {
                    // On the sphere: Lambert shading plus a tight highlight.
                    let z = (1 - d2).squareRoot()
                    let lambert = max(0, dx * lightX + dy * lightY + z * lightZ)
                    let half = (lightX, lightY, lightZ + 1)
                    let hLength = (half.0 * half.0 + half.1 * half.1 + half.2 * half.2).squareRoot()
                    let specular = pow(max(0, (dx * half.0 + dy * half.1 + z * half.2) / hLength), 40)
                    tone = 0.1 + 0.72 * lambert + 0.3 * specular
                } else {
                    // Off the sphere: the soft elliptical cast shadow.
                    let sx = (u - 0.55) / 0.33
                    let sy = (v - 0.76) / 0.09
                    let s = sx * sx + sy * sy
                    if s < 1 { tone *= 0.5 + 0.5 * smoothstep(0.45, 1, s) }
                }

                tone = clamp(tone, 0, 1)
                source[x, y] = Color(red: tone, green: tone * 0.985,
                                     blue: tone * 0.955, alpha: 1)
            }
        }
    }
}
