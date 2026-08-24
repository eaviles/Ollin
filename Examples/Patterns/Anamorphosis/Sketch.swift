import Ollin

/// **Anamorphosis**: a drawing that says nothing until a mirror reads it.
///
/// The big shape on the page is the plate. It is a real drawing, drawn once and
/// never corrected, and it is unreadable on purpose. Stand a mirrored cylinder
/// on the circle, put your eye where the map was told you would be, and the
/// smear gathers itself into a word standing upright on the glass.
///
/// The panel at the top is what that eye receives, worked out the long way
/// round: every point of the finished plate is sent back up its own light path
/// to the place on the mirror it bounces off, and those places are drawn as the
/// viewer sees them. So the panel is not the word that went in. It is the word
/// coming back out of the plate.
///
/// Try it: pull `eyeDistance` in. The eye sees less of the curve as it gets
/// closer, so the arc the picture can use narrows and the plate has to swing
/// wider to say the same thing. `eyeHeight` is the other half of the same
/// bargain: a low eye stretches the plate away across the page, and there is a
/// height above which a mark simply never comes down.
@main
final class AnamorphosisSketch: Sketch {
    @Param(280 ... 640, icon: "eye") var eyeDistance = 430.0
    @Param(170 ... 460, icon: "arrow.up.and.down") var eyeHeight = 250.0
    @Param(80 ... 175, icon: "cylinder") var mirrorRadius = 132.0
    @Param(0 ... 90, icon: "arrow.up.to.line") var lift = 40.0

    private let paper = Color(hex: 0x11131A)
    private let chalk = Color(hex: 0xF2ECDD)
    private let warm = Color(hex: 0xE0724A)
    private let cool = Color(hex: 0x5A8FC7)

    private var word: [Shape] = []
    private var wordAspect = 0.25
    private var plate: [Shape] = []
    private var seen: [Shape] = []
    private var cacheKey = ""

    override func setup() {
        textSize(130)
        word = textToShapes("OLLIN", at: Vector2(0, 0))
        let box = bounds(of: word)
        if box.width > 0 { wordAspect = box.height / box.width }
    }

    override func draw() {
        background(paper)
        rebuildIfNeeded()

        let mirror = setupMirror()
        drawPlate(mirror)
        drawPanel(mirror)
        drawCaptions(mirror)
    }

    // MARK: - The setup on the page

    private var mirrorCenter: Vector2 { Vector2(width / 2, height * 0.46) }

    private var panel: Rectangle {
        Rectangle(center: Vector2(width / 2, height * 0.11), width: width * 0.62, height: height * 0.16)
    }

    private func setupMirror() -> Anamorphosis {
        let eye = Vector3(mirrorCenter.x, mirrorCenter.y + eyeDistance, eyeHeight)
        let probe = Anamorphosis(center: mirrorCenter, radius: mirrorRadius, eye: eye,
                                 picture: Rectangle(x: 0, y: 0, width: 1, height: 1))
        // Use most of the arc this eye can actually see, and give the box the
        // word's own shape so the letters ride the glass at full height. The
        // taller the label, the shallower its bounce, and the farther the plate
        // has to run to catch it.
        let pictureWidth = probe.widestPicture * 0.84
        let pictureHeight = pictureWidth * wordAspect
        return Anamorphosis(
            center: mirrorCenter, radius: mirrorRadius, eye: eye,
            picture: Rectangle(center: mirrorCenter, width: pictureWidth, height: pictureHeight),
            lift: lift
        )
    }

    /// The plate is static for a given setup, and the way back is a search, so
    /// both are worked out only when a knob moves.
    private func rebuildIfNeeded() {
        let key = "\(eyeDistance)|\(eyeHeight)|\(mirrorRadius)|\(lift)|\(width)"
        guard key != cacheKey else { return }
        cacheKey = key

        let mirror = setupMirror()
        let picture = fitted(word, in: mirror.picture)
        plate = picture.map { mirror.plate(of: $0, spacing: 1.5) }
        seen = perceived(plate, of: mirror)
    }

    // MARK: - Drawing

    private func drawPlate(_ mirror: Anamorphosis) {
        // Where the cylinder stands. Its own circle is the one place a mark
        // never moves to, so the plate always clears it.
        noFill()
        stroke(cool.withAlpha(0.5))
        strokeWeight(2)
        drawCircle(mirror.footprint)
        fill(cool.withAlpha(0.08))
        noStroke()
        drawCircle(mirror.footprint)

        noStroke()
        fill(chalk)
        for shape in plate { drawShape(shape) }
    }

    private func drawPanel(_ mirror: Anamorphosis) {
        guard !seen.isEmpty else { return }
        let panel = self.panel
        fill(Color(hex: 0x1B1F2B))
        noStroke()
        drawRect(corner: panel.corner, width: panel.width, height: panel.height)

        withClip(panel) {
            fill(warm)
            noStroke()
            for shape in seen { drawShape(shape) }
        }
        noFill()
        stroke(chalk.withAlpha(0.22))
        strokeWeight(1.5)
        drawRect(corner: panel.corner, width: panel.width, height: panel.height)
    }

    private func drawCaptions(_ mirror: Anamorphosis) {
        textSize(17)
        textAlign(.center)
        fill(chalk.withAlpha(0.55))
        drawText("what the eye receives", width / 2, height * 0.225)
        fill(mirror.fits ? chalk.withAlpha(0.4) : warm)
        drawText(mirror.fits
                 ? "stand the mirror on the circle, eye \(Int(eyeDistance)) away and \(Int(eyeHeight)) up"
                 : "the picture is wider than this eye can see",
                 width / 2, height * 0.955)
    }

    // MARK: - The word, and the way back

    /// The box a set of shapes occupies.
    private func bounds(of shapes: [Shape]) -> Rectangle {
        var low = Vector2(.infinity, .infinity), high = Vector2(-.infinity, -.infinity)
        for shape in shapes {
            for contour in shape.contours {
                for point in contour.points {
                    low = Vector2(min(low.x, point.x), min(low.y, point.y))
                    high = Vector2(max(high.x, point.x), max(high.y, point.y))
                }
            }
        }
        guard high.x > low.x, high.y > low.y else { return Rectangle(x: 0, y: 0, width: 0, height: 0) }
        return Rectangle(corner: low, width: high.x - low.x, height: high.y - low.y)
    }

    /// The word scaled and centered into a box, keeping its shape.
    private func fitted(_ shapes: [Shape], in box: Rectangle) -> [Shape] {
        let size = bounds(of: shapes)
        guard size.width > 0, size.height > 0 else { return shapes }
        let scale = min(box.width / size.width, box.height / size.height)
        let offset = box.center - size.center * scale
        return shapes.map { $0.mapPoints { $0 * scale + offset } }
    }

    /// What the viewer receives, read off the finished plate rather than off
    /// the word that made it: each mark is followed back up to the glass, and
    /// the glass is drawn as it is seen.
    private func perceived(_ plate: [Shape], of mirror: Anamorphosis) -> [Shape] {
        // Aim at the middle of the picture where it sits on the glass, not at
        // the axis behind it. The eye looks down, so a nearer point at the same
        // height sits lower in the view, and aiming through the cylinder drops
        // the whole word out of the frame.
        guard let aim = mirror.mirrorPoint(of: mirror.picture.center) else { return [] }
        let forward = (aim - mirror.eye).normalized
        let right = Vector3(0, 0, 1).cross(forward).normalized
        let up = forward.cross(right).normalized

        func seenBy(_ mark: Vector2) -> Vector2? {
            guard let glass = mirror.mirrorPoint(of: mark, asSeenBy: mirror.eye) else { return nil }
            let offset = glass - mirror.eye
            let depth = offset.dot(forward)
            guard depth > 1e-6 else { return nil }
            return Vector2(offset.dot(right) / depth, -offset.dot(up) / depth)
        }

        let view = plate.map { shape in
            Shape(contours: shape.contours.compactMap { contour in
                let points = contour.resampled(spacing: 5).points.compactMap(seenBy)
                return points.count >= 3 ? Contour(points, closed: true) : nil
            }, winding: shape.winding)
        }
        // The angles are the picture; framing them is only where the panel's
        // edges fall, so the panel is the view scaled to fit inside it.
        return fitted(view, in: Rectangle(center: panel.center,
                                          width: panel.width * 0.9, height: panel.height * 0.78))
    }
}
