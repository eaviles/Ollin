import Ollin

/// A shaded sphere rebuilt out of nothing but dots.
///
/// `stipple(_:count:in:)` places a fixed budget of points so their local
/// density follows a picture's darkness: shadow packs them tight, highlight
/// spreads them out, and from arm's length the scatter *is* the picture. The
/// image here is painted in `setup()` (a lit sphere with a mottled surface),
/// so the sketch carries no asset, and the stipple is computed once and held;
/// the relaxation that evens out the spacing is per-pixel CPU work, not
/// something to redo every frame.
///
/// Each dot is also sized a little by the darkness under it, the classic
/// stippling move: density carries the tone, size sharpens the shadows.
/// What animates is only a gentle shimmer; the points never move, so the
/// image holds still the way an ink drawing does.
@main
final class Stippling: Sketch {
    private var dots: [(point: Vector2, darkness: Double)] = []

    override func setup() {
        seed(21)
        let picture = paint()
        let frame = canvasRectangle.inset(by: 80)
        let points = stipple(picture, count: 5200, in: frame, iterations: 45)

        // Sample the darkness back under every dot, for the size pass.
        dots = points.map { p in
            let x = Int((p.x - frame.x) / frame.width * Double(picture.width))
            let y = Int((p.y - frame.y) / frame.height * Double(picture.height))
            let c = picture[clamp(x, 0, picture.width - 1),
                            clamp(y, 0, picture.height - 1)]
            return (p, 1 - c.luminance)
        }
    }

    override func draw() {
        background(Color(hex: 0xF5F2EA))

        noStroke()
        fill(Color(hex: 0x1A1B26))
        for (p, darkness) in dots {
            // A slow shimmer in the dot sizes; the positions stay put.
            let breathe = 1 + signedNoise(p.x * 0.004, p.y * 0.004, time * 0.35) * 0.18
            drawCircle(center: p, radius: (1.1 + darkness * 2.6) * breathe * scale)
        }

        drawCaption("5,200 dots; darkness sets how tightly they pack")
    }

    /// The picture the dots reproduce: a sphere lit from the upper left, its
    /// surface mottled by fbm, on a paper-white ground the stipple leaves
    /// empty. Painted small; the stipple's working grid does the refining.
    private func paint() -> Image {
        let n = 360
        let image = Image(width: n, height: n, color: .white)
        let light = Vector3(-0.5, -0.55, 0.67).normalized
        let radius = 0.82
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n) * 2 - 1
                let v = (Double(y) + 0.5) / Double(n) * 2 - 1
                let d2 = u * u + v * v
                guard d2 < radius * radius else { continue }
                let normal = Vector3(u / radius, v / radius,
                                     (1 - d2 / (radius * radius)).squareRoot())
                let diffuse = max(normal.dot(light), 0)
                let mottle = signedNoise(u * 2.6 + 5, v * 2.6 + 5) * 0.16
                let tone = clamp(0.08 + diffuse * 0.92 + mottle * diffuse, 0, 1)
                image[x, y] = Color(white: tone)
            }
        }
        return image
    }
}
