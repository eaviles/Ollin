import Foundation
import simd

extension Drawer {

    /// Stamp `points` if a brush is set, and report whether it took the stroke
    /// over. Every public stroking call asks this *before* it short-circuits into
    /// the vector recorder, so an exported document carries the stamps the screen
    /// shows rather than the bare path running under them.
    func strokedAsBrush(_ points: [Vector2], closed: Bool) -> Bool {
        guard let brush = strokeBrushShape, strokePaint != nil, strokeWidth > 0,
              !points.isEmpty else { return false }
        appendBrushStamps(points, closed: closed, brush: brush)
        return true
    }

    /// Stamp a brush along `points` in place of stroking them.
    ///
    /// Each stamp is drawn through the ordinary draw methods rather than pushed
    /// into the vertex buffers directly, which is what makes a brush cost so
    /// little to support: vector export writes real shapes a plotter can follow,
    /// kaleidoscope symmetry replicates the stamps, a clip block clips them, and a
    /// retained batch records them, all without any of those knowing a brush
    /// exists.
    ///
    /// The style is swapped for the duration: a stamp is a *filled* shape in the
    /// stroke's color, and the brush is cleared inside the block so a stamp whose
    /// tip is itself stroked cannot recurse.
    func appendBrushStamps(_ points: [Vector2], closed: Bool, brush: Brush) {
        guard let paint = strokePaint, strokeWidth > 0 else { return }
        let stamps = Brush.stamps(
            along: points, closed: closed, brush: brush,
            width: { t in
                self.strokeProfileShape.isUniform
                    ? self.strokeWidth
                    : self.strokeWidth * max(self.strokeProfileShape(t), 0)
            },
            opacity: { t in
                self.strokeOpacityShape.isUniform ? 1 : max(self.strokeOpacityShape(t), 0)
            })
        guard !stamps.isEmpty else { return }

        let savedFill = fillPaint
        let savedStroke = strokePaint
        let savedBrush = strokeBrushShape
        let savedProfile = strokeProfileShape
        let savedOpacity = strokeOpacityShape
        defer {
            fillPaint = savedFill
            strokePaint = savedStroke
            strokeBrushShape = savedBrush
            strokeProfileShape = savedProfile
            strokeOpacityShape = savedOpacity
        }
        strokePaint = nil
        strokeBrushShape = nil
        strokeProfileShape = .uniform
        strokeOpacityShape = .uniform

        // A stamp's own alpha multiplies the stroke's, so a translucent brush and a
        // faint moment compound the way a second pass of ink would. A gradient
        // paints each stamp in drawing space, so it already reads the right color
        // where the stamp lands; what it cannot do is take the opacity, which would
        // mean rewriting its ramp.
        var warnedAboutGradientOpacity = false
        func inked(_ opacity: Double) -> Paint {
            guard opacity < 1 else { return paint }
            guard case .color(let c) = paint else {
                if !warnedAboutGradientOpacity {
                    warnedAboutGradientOpacity = true
                    noteOnce("A brush varies opacity only over a solid stroke color; a gradient stroke stamps at the ramp's own alpha.")
                }
                return paint
            }
            return .color(c.withAlpha(c.alpha * opacity))
        }

        for stamp in stamps {
            fillPaint = inked(stamp.opacity)
            let half = stamp.size / 2
            switch brush.tip {
            case .circle:
                drawCircle(stamp.center.x, stamp.center.y, half)
            case .square:
                // An oriented box is a rotated rectangle for free: give it a
                // centerline the length of the square and a matching thickness.
                let along = Vector2(cos(stamp.angle), sin(stamp.angle)) * half
                drawOrientedBox(stamp.center - along, stamp.center + along,
                                thickness: stamp.size)
            case .shape(let shape):
                drawShape(placed(shape, at: stamp))
            case .image(let image):
                drawStampImage(image, stamp)
            }
        }
    }

    /// A tip shape moved onto one stamp: scaled so its longest side is the stamp's
    /// size, turned to the stamp's angle, and centered on it. Scaling the *points*
    /// rather than the transform matters here as it does everywhere else, since the
    /// transform would also scale the outline of a stroked tip.
    private func placed(_ shape: Shape, at stamp: Brush.Stamp) -> Shape {
        var lo = Vector2(.infinity, .infinity), hi = Vector2(-.infinity, -.infinity)
        for contour in shape.contours {
            for p in contour.points {
                lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
                hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
            }
        }
        let extent = max(hi.x - lo.x, hi.y - lo.y)
        guard extent.isFinite, extent > 1e-9 else { return shape }
        let scale = stamp.size / extent
        let pivot = (lo + hi) / 2
        let c = cos(stamp.angle), s = sin(stamp.angle)
        return shape.mapPoints { p in
            let local = (p - pivot) * scale
            return stamp.center + Vector2(local.x * c - local.y * s,
                                          local.x * s + local.y * c)
        }
    }

    /// One image stamp, square to its longest side and turned to the stamp's
    /// angle. The rotation rides the transform stack, which is the only way an
    /// image quad can turn.
    private func drawStampImage(_ image: Image, _ stamp: Brush.Stamp) {
        let w = Double(image.width), h = Double(image.height)
        guard w > 0, h > 0 else { return }
        let scale = stamp.size / max(w, h)
        let size = Vector2(w * scale, h * scale)
        let saved = transform
        let move = Drawer.translation(Float(stamp.center.x), Float(stamp.center.y))
        let turn = Drawer.rotation(Float(stamp.angle))
        transform = saved * move * turn
        // The stamp's alpha is the tint, since an image quad carries no fill.
        let savedTint = tintColor
        if case .color(let c) = fillPaint { tintColor = c }
        drawImage(image, in: Rectangle(x: -size.x / 2, y: -size.y / 2,
                                       width: size.x, height: size.y))
        tintColor = savedTint
        transform = saved
    }
}
