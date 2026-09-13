import Ollin

/// A night street as a film still. A row of lamps over dark facades and a
/// moon, drawn plainly, then passed through the two things a film stock does
/// to a picture that a sensor does not. `.halation` puts a warm fringe around
/// each lamp: light that got through the emulsion, came back off the base,
/// and exposed the red-sensitive layer again around the point it entered.
/// `.filmGrain` lays the stock's grain over everything, fresh every frame and
/// heaviest in the mid-tones, so the walls carry more of it than the sky and
/// the lamps' white cores carry none.
///
/// Every dial is a parameter. **Compare** draws the raw frame over the left
/// half, so the look can be read against nothing.
@main
final class FilmLook_Example: Sketch {

    @Param("Threshold", 0.3 ... 1, icon: "sun.max", group: "Halation") var threshold = 0.8
    @Param("Radius", 2 ... 60, icon: "circle.dotted", group: "Halation") var radius = 24.0
    @Param("Amount", 0 ... 2, icon: "flame", group: "Halation") var halation = 1.0
    @Param("Tint", icon: "paintpalette", group: "Halation") var tint = Color(red: 1, green: 0.35, blue: 0.1)
    @Param("Amount", 0 ... 0.2, icon: "circle.grid.3x3", group: "Grain") var grain = 0.06
    @Param("Size", 1 ... 6, icon: "circle.grid.2x1", group: "Grain") var grainSize = 2.0
    @Param("Compare", icon: "rectangle.split.2x1") var compare = false

    override func setup() {
        seed(7)
    }

    override func draw() {
        let scene = makeRenderTarget()
        withTarget(scene) { drawStreet() }

        let filmed = scene
            .filtered(.halation(threshold: threshold, radius: radius, tint: tint, amount: halation))
            .filtered(.filmGrain(amount: grain, size: grainSize, seed: Double(frameCount)))
        drawImage(filmed.image, 0, 0)

        if compare {
            withClip(Rectangle(x: 0, y: 0, width: width / 2, height: height)) {
                drawImage(scene.image, 0, 0)
            }
            stroke(Color(white: 0.9, alpha: 0.6))
            strokeWeight(2)
            drawLine(width / 2, 0, width / 2, height)
        }
    }

    /// The street: a sky ramp, a moon, facades with a few lit windows, and
    /// five lamps whose pools of light breathe a little.
    private func drawStreet() {
        noStroke()
        for y in stride(from: 0.0, to: height, by: 2) {
            let t = y / height
            fill(Color(red: 0.02 + 0.03 * t, green: 0.03 + 0.04 * t, blue: 0.08 + 0.14 * t))
            drawRect(0, y, width, 2)
        }
        fill(Color(white: 0.96))
        drawCircle(width * 0.78, height * 0.17, 42)

        // Facades, the same every frame, in a warm dark stone that grain shows on.
        seed(7)
        var x = 0.0
        let ground = height * 0.72
        while x < width {
            let w = random(90, 190), h = random(120, 320)
            fill(Color(red: random(0.14, 0.2), green: random(0.12, 0.17), blue: random(0.11, 0.15)))
            drawRect(x, ground - h, w, h)
            for row in stride(from: ground - h + 26, to: ground - 30, by: 52) {
                for col in stride(from: x + 18, to: x + w - 30, by: 40) where random() < 0.35 {
                    fill(Color(red: 0.55, green: 0.42, blue: 0.24))
                    drawRect(col, row, 14, 22)
                }
            }
            x += w + random(6, 20)
        }
        fill(Color(red: 0.24, green: 0.22, blue: 0.21))
        drawRect(0, ground, width, height - ground)

        // Lamps: a post, a pool of light on the pavement, and a white core.
        for i in 0 ..< 5 {
            let lx = width * (0.1 + 0.2 * Double(i)), ly = height * 0.5
            let breath = 0.85 + 0.15 * sin(time * 1.7 + Double(i) * 1.3)
            fill(Color(red: 0.12, green: 0.11, blue: 0.1))
            drawRect(lx - 3, ly, 6, ground - ly)
            for ring in 1 ... 10 {
                fill(Color(red: 0.9, green: 0.7, blue: 0.4, alpha: 0.045 * breath))
                drawCircle(lx, ground + 10, 20 + Double(ring) * 16)
            }
            fill(Color(red: 1, green: 0.96, blue: 0.85))
            drawCircle(lx, ly, 13)
        }
    }
}
