// figure: frame=0
//
// Guide diagram (Chapter 15): a plate drawn for a mirrored cylinder, beside
// what the eye standing in the one right place receives. The right-hand panel
// is worked out from the finished plate rather than from the word that made
// it, so the two panels are a round trip. Nothing here uses randomness.
import Ollin

final class MirrorReads: Sketch {
    override var canvasSize: CanvasSize { .size(880, 470) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x232020)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(paper)

        // A low eye, the way you would actually look across a table at a
        // cylinder standing on a sheet. The lower it is, the farther the plate
        // has to run to reach it.
        let mirror = Anamorphosis(
            center: Vector2(232, 205), radius: 60,
            eye: Vector3(232, 415, 125),
            picture: Rectangle(center: Vector2(232, 205), width: 130, height: 26),
            lift: 30
        )

        textSize(96)
        let word = textToShapes("MIRROR", at: .zero)
        let picture = fitted(word, in: mirror.picture)
        let plate = picture.map { mirror.plate(of: $0, spacing: 0.6) }

        // Left: the page. The circle is where the cylinder stands.
        noFill()
        stroke(soft)
        strokeWeight(1.5)
        drawCircle(mirror.footprint)
        noStroke()
        fill(ink)
        for shape in plate { drawShape(shape) }

        // Right: the one place it reads from.
        let panel = Rectangle(x: 486, y: 96, width: 352, height: 250)
        noFill()
        stroke(soft)
        strokeWeight(1.5)
        drawRect(corner: panel.corner, width: panel.width, height: panel.height)
        noStroke()
        fill(accent)
        for shape in seen(plate, of: mirror, in: panel.inset(by: 26)) { drawShape(shape) }

        textSize(15)
        textAlign(.center)
        fill(ink)
        drawText("the plate, and the circle the mirror stands on", 232, 424)
        drawText("what one eye receives, read off that plate", 662, 424)
        fill(ink.withAlpha(0.55))
        textSize(13)
        drawText("nothing is undone in software: the reflection does the reading", 440, 452)
    }

    // MARK: - helpers

    func bounds(of shapes: [Shape]) -> Rectangle {
        var low = Vector2(.infinity, .infinity), high = Vector2(-.infinity, -.infinity)
        for shape in shapes {
            for contour in shape.contours {
                for point in contour.points {
                    low = Vector2(min(low.x, point.x), min(low.y, point.y))
                    high = Vector2(max(high.x, point.x), max(high.y, point.y))
                }
            }
        }
        return Rectangle(corner: low, width: high.x - low.x, height: high.y - low.y)
    }

    func fitted(_ shapes: [Shape], in box: Rectangle) -> [Shape] {
        let size = bounds(of: shapes)
        guard size.width > 0, size.height > 0 else { return shapes }
        let scale = min(box.width / size.width, box.height / size.height)
        let offset = box.center - size.center * scale
        return shapes.map { $0.mapPoints { $0 * scale + offset } }
    }

    /// Every point of the plate, followed back up its own light path to the
    /// glass, and the glass drawn as the viewer sees it.
    func seen(_ plate: [Shape], of mirror: Anamorphosis, in box: Rectangle) -> [Shape] {
        guard let aim = mirror.mirrorPoint(of: mirror.picture.center) else { return [] }
        let forward = (aim - mirror.eye).normalized
        let right = Vector3(0, 0, 1).cross(forward).normalized
        let up = forward.cross(right).normalized

        let view = plate.map { shape in
            Shape(contours: shape.contours.compactMap { contour in
                let points = contour.resampled(spacing: 1.5).points.compactMap { mark -> Vector2? in
                    guard let glass = mirror.mirrorPoint(of: mark, asSeenBy: mirror.eye) else { return nil }
                    let offset = glass - mirror.eye
                    let depth = offset.dot(forward)
                    guard depth > 1e-6 else { return nil }
                    return Vector2(offset.dot(right) / depth, -offset.dot(up) / depth)
                }
                return points.count >= 3 ? Contour(points, closed: true) : nil
            }, winding: shape.winding)
        }
        return fitted(view, in: box)
    }
}
