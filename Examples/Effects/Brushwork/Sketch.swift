import Ollin

/// **Brushwork** lays the picture on as paint. Each pixel becomes the average of
/// the flattest of eight overlapping sectors of a brush around it, so detail
/// flattens into patches while edges stay crisp. The brush is an ellipse drawn
/// out along whatever edge runs through the pixel, so the patches read as
/// strokes that follow the picture's own contours rather than square dabs.
///
/// A hillside under a summer sky. The grass bends in a breeze, the clouds
/// drift, and the filter paints it all, the strokes running with the blades and
/// along the crests. `Radius` is the brush size, `Stretch` how far a stroke is
/// drawn out along an edge (1 keeps the brush round, and the patches turn
/// blocky), and `Sharpness` how decisively the flattest patch wins (0 is only a
/// blur). `Compare` shows the layer itself on the left half.
@main
final class Brushwork: Sketch {

    @Param("Radius", 1 ... 12, icon: "paintbrush", group: "Brush") var radius = 6.0
    @Param("Stretch", 1 ... 16, icon: "arrow.left.and.right", group: "Brush") var stretch = 4.0
    @Param("Sharpness", 0 ... 16, icon: "bolt", group: "Brush") var sharpness = 8.0
    @Param(icon: "rectangle.split.2x1", group: "View") var compare = false

    override func draw() {
        background(.black)
        let scene = makeRenderTarget()
        withTarget(scene) { paint() }

        let painted = scene.filtered(.brushwork(radius: radius, stretch: stretch,
                                                sharpness: sharpness))
        drawImage(painted.image, 0, 0)

        if compare {
            withClip(Rectangle(x: 0, y: 0, width: width / 2, height: height)) {
                drawImage(scene.image, 0, 0)
            }
            stroke(.white)
            strokeWeight(3)
            drawLine(width / 2, 0, width / 2, height)
        }
    }

    /// Sky, sun, drifting clouds, three ridges, and a foreground of grass in a
    /// breeze, laid out from one seed so only the wind and the clouds move.
    private func paint() {
        seed(7)
        noStroke()

        let skyline = height * 0.58
        fill(.linear(from: Vector2(0, 0), to: Vector2(0, skyline),
                     Ramp([Color(hex: 0x2F63AE), Color(hex: 0xBFD9F2)])))
        drawRect(0, 0, width, skyline)

        let sun = Vector2(width * 0.76, height * 0.16)
        fill(.radial(center: sun, radius: width * 0.18,
                     Ramp([Color(hex: 0xFFF6D0), Color(hex: 0xFFF6D0, alpha: 0)])))
        drawCircle(center: sun, radius: width * 0.18)
        fill(Color(hex: 0xFFF9E4))
        drawCircle(center: sun, radius: width * 0.045)

        // Clouds: a few soft heaps of lobes, drifting across and wrapping.
        for k in 0 ..< 6 {
            let span = width + 400.0
            let x = (random(0, span) + time * (18 + Double(k) * 4)).truncatingRemainder(dividingBy: span) - 200
            let y = height * random(0.08, 0.4)
            let size = width * random(0.05, 0.1)
            for lobe in 0 ..< 5 {
                let r = size * random(0.6, 1)
                let at = Vector2(x + Double(lobe - 2) * size * 0.6, y - r * 0.4 * random(0, 1))
                fill(.radial(center: at, radius: r,
                             Ramp([Color(white: 1, alpha: 0.85), Color(white: 1, alpha: 0)])))
                drawEllipse(center: at, radiusX: r, radiusY: r * 0.7)
            }
        }

        // Three ridges, far to near, each a polygon under a noise-shaped crest.
        let ridges: [(base: Double, lift: Double, top: Color, foot: Color)] = [
            (height * 0.62, height * 0.12, Color(hex: 0x9FC58B), Color(hex: 0x5E8E52)),
            (height * 0.7, height * 0.1, Color(hex: 0x6FA85C), Color(hex: 0x3E6E38)),
            (height * 0.78, height * 0.08, Color(hex: 0x4E8C40), Color(hex: 0x2A4F26)),
        ]
        for (i, ridge) in ridges.enumerated() {
            func crestY(_ x: Double) -> Double {
                ridge.base - noise(x * 0.0022 + Double(i) * 7.3, Double(i) * 2.1) * ridge.lift
            }
            var crest: [Vector2] = []
            for x in stride(from: -20.0, through: width + 20, by: 10) {
                crest.append(Vector2(x, crestY(x)))
            }
            crest.append(Vector2(width + 20, height + 20))
            crest.append(Vector2(-20, height + 20))
            noStroke()
            fill(.linear(from: Vector2(0, ridge.base - ridge.lift), to: Vector2(0, height),
                         Ramp([ridge.top, ridge.foot])))
            drawPolygon(crest)

            // The field's own texture: short strokes that run with the slope of the
            // crest, lighter and darker than the ground, so the ridge has a grain for
            // the brush to follow.
            let floor = i + 1 < ridges.count ? ridges[i + 1].base : height * 0.8
            strokeCap(.round)
            for _ in 0 ..< 220 {
                let x = random(0, width)
                let top = crestY(x)
                let y = random(top + 6, max(top + 8, floor))
                let slope = (crestY(x + 12) - crestY(x - 12)) / 24
                let along = Vector2(1, slope).normalized * random(14, 40)
                let tone = Color.mix(ridge.top, ridge.foot, (y - top) / max(1, floor - top))
                stroke((random(0, 1) < 0.5 ? tone.lighter(by: 0.08) : tone.darker(by: 0.1)).withAlpha(0.5))
                strokeWeight(random(2, 4))
                drawLine(Vector2(x, y) - along * 0.5, Vector2(x, y) + along * 0.5)
            }
        }

        // Grass: blades rooted across the foreground, taller nearer the eye, each a
        // polyline bent by the breeze.
        let greens = Ramp([Color(hex: 0x3C7A2E), Color(hex: 0x7DBE4A), Color(hex: 0xC8D65A)])
        strokeCap(.round)
        for _ in 0 ..< 900 {
            let root = Vector2(random(-10, width + 10), random(height * 0.74, height + 4))
            let depth = (root.y - height * 0.74) / (height * 0.3)
            let tall = height * (0.03 + 0.07 * depth) * random(0.7, 1.3)
            let gust = sin(time * 1.6 + root.x * 0.008) * 0.6 + sin(time * 0.7 + root.y * 0.02) * 0.25
            let lean = random(-0.25, 0.25)
            var blade: [Vector2] = []
            for step in 0 ... 5 {
                let t = Double(step) / 5
                let bend = (gust + lean) * tall * t * t * 0.9
                blade.append(Vector2(root.x + bend, root.y - tall * t))
            }
            stroke(greens.color(at: random(0, 1)).darker(by: 0.18 * (1 - depth)))
            strokeWeight(1.5 + 2.5 * depth)
            drawPolyline(blade)
        }

        // A few flowers in the grass.
        noStroke()
        for _ in 0 ..< 40 {
            fill([Color(hex: 0xE04E4E), Color(hex: 0xFFD447), Color(hex: 0xF3F0FF)][Int(random(0, 3)) % 3])
            drawCircle(random(0, width), random(height * 0.8, height), random(3, 6))
        }
    }
}
