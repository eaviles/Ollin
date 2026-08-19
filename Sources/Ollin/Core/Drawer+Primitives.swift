// Drawer, the primitives half: every draw* geometry emitter (the SDF instance
// builders, the fringe-stroked and tessellated paths, arcs and polygons) plus
// the SDF-combinator scoped blocks. One extension of the recorder; the state
// it appends into lives with the type in Drawer.swift.

import Foundation
import simd
import COllinShaders

extension Drawer {
    // MARK: Primitives

    /// A circle centered at `(x, y)` with the given `radius` (points).
    ///
    /// Recorded as a single SDF instance, not tessellated: the fragment shader
    /// computes fill, stroke (width `strokeWeight`), and anti-aliasing
    /// analytically. Crisp at any size and effectively free per circle, which is
    /// what makes thousands of them cheap.
    func drawCircle(_ x: Double, _ y: Double, _ radius: Double) {
        guard radius > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.ellipse(center: Vector2(x, y), rx: radius, ry: radius), fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .ellipse, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(radius), Float(radius)),
                  fill: fillPaint, stroke: strokePaint)
    }

    /// The same circle, given as a `Circle` value.
    func drawCircle(_ c: Circle) { drawCircle(c.center.x, c.center.y, c.radius) }

    /// An axis-aligned ellipse centered at `(x, y)` with horizontal radius `rx`
    /// and vertical radius `ry` (points). Like `drawCircle`, the arguments are
    /// *radii*, not diameters — `drawEllipse(x, y, r, r)` is a circle.
    ///
    /// Recorded as a single SDF instance (see `drawCircle`); fill and a
    /// uniform-width stroke are derived analytically in the fragment shader.
    func drawEllipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
        guard rx > 0, ry > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.ellipse(center: Vector2(x, y), rx: rx, ry: ry), fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .ellipse, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(rx), Float(ry)),
                  fill: fillPaint, stroke: strokePaint)
    }

    /// A filled marker at `(x, y)`. `size` is the on-screen *diameter* (points); the
    /// no-`size` form uses the current `pointSize`. The glyph is the current
    /// `pointMarker` (a round dot by default). A point takes the current `fill`
    /// color (not stroke) and ignores `strokeWeight`, so `noFill()` draws nothing.
    /// Recorded as one SDF instance, so it's crisp and effectively free per point.
    /// The round `.circle` marker also stays smooth down to sub-pixel sizes, fading
    /// by area instead of popping or snapping to 1px.
    func drawPoint(_ x: Double, _ y: Double, _ size: Double) {
        guard size > 0, let fill = fillPaint else { return }
        if svgRecorder != nil {
            let r = size / 2, c = Vector2(x, y), arm = (size / 2) * 0.28
            switch marker {
            case .circle:  svgRecord(.ellipse(center: c, rx: r, ry: r), fill: fill, stroke: nil)
            case .square:  svgRecord(.polygon(svgOffset(SDFOutline.markerSquare(r), c)), fill: fill, stroke: nil)
            case .diamond: svgRecord(.polygon(svgOffset(SDFOutline.markerDiamond(r), c)), fill: fill, stroke: nil)
            case .cross:   svgRecord(.polygon(svgOffset(SDFOutline.markerCross(r, arm), c)), fill: fill, stroke: nil)
            case .x:       svgRecord(.polygon(svgOffset(SDFOutline.markerX(r, arm), c)), fill: fill, stroke: nil)
            }
            return
        }
        let h = Float(size / 2)
        // Marker kind code, as the fragment reads it from `extra` (see SDFShape).
        let kind: Float
        switch marker {
        case .circle:
            // The disk path: its own SDF shape, with sub-pixel area conservation.
            // A point is a point — opt out of hollow mode (it shares `.ellipse`).
            appendSDF(shape: .ellipse, center: Vector2(x, y),
                      size: SIMD2<Float>(h, h), fill: fill, stroke: nil, applyHollow: false)
            return
        case .square:  kind = 0
        case .diamond: kind = 1
        case .cross:   kind = 2
        case .x:       kind = 3
        }
        // cross / x are filled bars; their arm half-width is a fixed fraction of
        // the radius (unused by the solid square / diamond).
        let armHalfWidth = h * 0.28
        appendSDF(shape: .marker, center: Vector2(x, y),
                  size: SIMD2<Float>(h, h), fill: fill, stroke: nil,
                  extra: kind, param0: SIMD2<Float>(armHalfWidth, 0))
    }

    func drawPoint(_ x: Double, _ y: Double) { drawPoint(x, y, pointDiameter) }

    /// An equilateral triangle centered at `(x, y)`, point-up, with circumradius
    /// `radius` (center-to-vertex distance, like `drawCircle`'s radius). Recorded
    /// as a single SDF instance — analytic fill + stroke + anti-aliasing — so it's
    /// crisp at any size and effectively free per triangle. Rotate via the
    /// transform stack to aim it; rotation pivots on the center.
    func drawTriangle(_ x: Double, _ y: Double, _ radius: Double) {
        guard radius > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.triangleEquilateral(radius: radius), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        let height = radius * 1.5                          // apex-to-base distance
        let halfBase = radius * 0.8660254037844386         // radius * √3/2
        // Anchor the centroid at (x, y); the apex (the SDF origin) sits `radius`
        // above it (the centroid is ⅓ of the height up from the base).
        appendSDF(shape: .triangle, center: Vector2(x, y - radius),
                  size: SIMD2<Float>(Float(halfBase), Float(height)),
                  fill: fillPaint, stroke: strokePaint)
    }

    /// An isosceles triangle whose apex (tip) is at `(x, y)`, opening toward +y
    /// (downward, in Ollin's y-down space) by `height`, with the given `base`
    /// width. Recorded as a single SDF instance (see `drawTriangle(_:_:_:)`):
    /// analytic, crisp at any size, effectively free. Rotate via the transform
    /// stack to aim it; rotation pivots on the apex — so to spin a wedge about its
    /// tip, `translate` to the tip, `rotate`, then draw with the apex at the
    /// origin.
    func drawTriangle(_ x: Double, _ y: Double, _ base: Double, _ height: Double) {
        guard base > 0, height > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.triangleIsosceles(base: base, height: height), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .triangle, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(base / 2), Float(height)),
                  fill: fillPaint, stroke: strokePaint)
    }

    /// A triangle through three arbitrary corners `a`, `b`, `c` (any winding). Unlike
    /// the equilateral `drawTriangle(_:_:_:)` (circumradius) and isosceles
    /// `drawTriangle(_:_:_:_:)` (apex + base + height) forms, this places the corners
    /// directly, so any triangle is one call. Recorded as a single SDF instance —
    /// analytic fill + stroke + anti-aliasing, crisp at any size and effectively free.
    /// Honors `strokeAlign` and `hollow`. A degenerate (zero-area) triangle draws
    /// nothing.
    func drawTriangle(_ a: Vector2, _ b: Vector2, _ c: Vector2) {
        let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        guard abs(area) > 1e-9 else { return }
        let lo = Vector2(min(a.x, min(b.x, c.x)), min(a.y, min(b.y, c.y)))
        let hi = Vector2(max(a.x, max(b.x, c.x)), max(a.y, max(b.y, c.y)))
        if svgRecorder != nil {
            svgRecord(.polygon([a, b, c]), fill: fillPaint, stroke: strokePaint)
            return
        }
        let center = (lo + hi) / 2
        let half = (hi - lo) / 2
        appendSDF(shape: .triangle3, center: center,
                  size: SIMD2<Float>(Float(half.x), Float(half.y)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: (a - center).simd2, param1: (b - center).simd2, param2: (c - center).simd2)
    }

    /// A triangle through three corners given as scalar coordinates — the positional
    /// form of `drawTriangle(_:_:_:)`.
    func drawTriangle(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                      _ x3: Double, _ y3: Double) {
        drawTriangle(Vector2(x1, y1), Vector2(x2, y2), Vector2(x3, y3))
    }

    /// A regular polygon centered at `(x, y)` with `sides` equal-length edges and
    /// circumradius `radius` (center-to-vertex, like `drawCircle`'s radius), one
    /// vertex pointing up. `sides` is 3 (a triangle) or more. Recorded as a single
    /// SDF instance — analytic fill + stroke + anti-aliasing, crisp at any size and
    /// effectively free per shape. Rotate via the transform stack; rotation pivots
    /// on the center.
    func drawNgon(_ x: Double, _ y: Double, _ radius: Double, sides: Int) {
        guard radius > 0, sides >= 3 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.ngon(radius: radius, sides: sides), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        // A regular polygon is the special case of a star whose inner radius is the
        // apothem (the edge midpoints), which straightens the points into edges.
        appendStar(center: Vector2(x, y), outer: radius,
                   inner: radius * cos(.pi / Double(sides)), points: sides)
    }

    /// Named regular polygons — sugar over `drawNgon` with a fixed side count, the
    /// way `drawCircle` reads better than an equal-radii `drawEllipse`. Same
    /// arguments and behavior: circumradius `radius`, one vertex up, the same
    /// analytic SDF shape. For other side counts, call `drawNgon` directly.
    func drawPentagon(_ x: Double, _ y: Double, _ radius: Double) { drawNgon(x, y, radius, sides: 5) }
    func drawHexagon(_ x: Double, _ y: Double, _ radius: Double)  { drawNgon(x, y, radius, sides: 6) }
    func drawHeptagon(_ x: Double, _ y: Double, _ radius: Double) { drawNgon(x, y, radius, sides: 7) }
    func drawOctagon(_ x: Double, _ y: Double, _ radius: Double)  { drawNgon(x, y, radius, sides: 8) }

    /// A star centered at `(x, y)` with `points` outer points, alternating between
    /// `outerRadius` (the tips) and `innerRadius` (the valleys), one tip pointing
    /// up. `points` is 3 or more, and `innerRadius` is `0...outerRadius` (smaller is
    /// spikier). Recorded as a single SDF instance — analytic fill + stroke +
    /// anti-aliasing, crisp at any size. Rotate via the transform stack; rotation
    /// pivots on the center.
    func drawStar(_ x: Double, _ y: Double, _ outerRadius: Double, _ innerRadius: Double, points: Int) {
        guard outerRadius > 0, innerRadius > 0, innerRadius <= outerRadius, points >= 3 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.star(outer: outerRadius, inner: innerRadius, points: points), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendStar(center: Vector2(x, y), outer: outerRadius, inner: innerRadius, points: points)
    }

    /// A rhombus (diamond) centered at `(x, y)`, `width` wide and `height` tall
    /// (the full diagonals), with vertices at the four points of those diagonals.
    /// `cornerRadius` rounds the corners while keeping the `width`×`height`
    /// footprint. Recorded as a single SDF instance — analytic fill + stroke +
    /// anti-aliasing, crisp at any size. Rotate via the transform stack.
    func drawRhombus(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0) {
        guard width > 0, height > 0 else { return }
        let r = max(0, min(cornerRadius, min(width, height) / 2))
        if svgRecorder != nil {
            let loops = r > 0 ? SDFOutline.rhombusRounded(width: width, height: height, cornerRadius: r)
                              : [SDFOutline.rhombus(width: width, height: height)]
            svgRecordTraced(loops, at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .rhombus, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2), Float(height / 2)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(r))
    }

    /// A vesica (a pointed lens / two-circle intersection) centered at `(x, y)`,
    /// `width` by `height`; the tips lie along the longer axis. `cornerRadius`
    /// rounds the tips (and slightly enlarges the lens, like `drawMoon`).
    /// Recorded as a single SDF instance. Rotate via the transform stack.
    func drawVesica(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0) {
        guard width > 0, height > 0 else { return }
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.vesica(width: width, height: height, cornerRadius: max(0, cornerRadius)),
                            at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        let horizontal = width > height
        let a = (horizontal ? width : height) / 2     // half-length toward the tips
        let w = max((horizontal ? height : width) / 2, 1e-4)   // waist half-width
        let rr = max(0, cornerRadius)
        // Map the (along, across) half-extents to the vesica's circle radius + center
        // offset:  r = (w + a²/w) / 2,  d = (a² − w²) / (2w)  (a ≥ w; a == w is a
        // circle). Derived from the *full* footprint, not an inset one, so r/d stay
        // well-conditioned for any rounding (insetting toward a zero waist sends
        // them to ~1e7 and the shader's sqrt(r²−d²) loses all precision). opRound
        // (− rr) rounds the tips and grows the lens by rr, which the AABB accounts
        // for.
        let rCircle = (w + a * a / w) / 2
        let dOff = (a * a - w * w) / (2 * w)
        appendSDF(shape: .vesica, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2 + rr), Float(height / 2 + rr)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(rr),
                  param0: SIMD2<Float>(Float(rCircle), Float(dOff)),
                  param1: SIMD2<Float>(horizontal ? 1 : 0, 0))
    }

    /// A crescent moon centered at `(x, y)`: the disk of `outerRadius` with a disk
    /// of `innerRadius` subtracted, the cut disk's center `offset` away (toward
    /// +x). For a classic crescent keep `innerRadius` near `outerRadius` with a
    /// modest `offset`. `cornerRadius` rounds the cusps (and slightly enlarges).
    /// Recorded as a single SDF instance. Rotate via the transform stack to aim it.
    func drawMoon(_ x: Double, _ y: Double, _ outerRadius: Double, _ innerRadius: Double,
                  _ offset: Double, cornerRadius: Double = 0) {
        guard outerRadius > 0, innerRadius > 0, offset > 0 else { return }
        let rr = max(0, cornerRadius)
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.moon(outerRadius: outerRadius, innerRadius: innerRadius, offset: offset, cornerRadius: rr),
                            at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .moon, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(outerRadius + rr), Float(outerRadius + rr)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(rr),
                  param0: SIMD2<Float>(Float(outerRadius), Float(innerRadius)),
                  param1: SIMD2<Float>(Float(offset), 0))
    }

    /// A plus-sign cross centered at `(x, y)`, spanning `length` tip-to-tip on both
    /// axes with arms `thickness` wide. `cornerRadius` rounds the outer corners
    /// (the inner notches stay sharp). Recorded as a single SDF instance — analytic
    /// fill + stroke + anti-aliasing. Rotate 45° via the transform stack for an ✕.
    func drawCross(_ x: Double, _ y: Double, _ length: Double, _ thickness: Double, cornerRadius: Double = 0) {
        guard length > 0, thickness > 0 else { return }
        let armHalfLength = length / 2
        let armHalfWidth = min(thickness, length) / 2
        let r = max(0, min(cornerRadius, armHalfWidth))
        if svgRecorder != nil {
            let loops = r > 0 ? SDFOutline.crossRounded(length: length, thickness: thickness, cornerRadius: r)
                              : [SDFOutline.cross(length: length, thickness: thickness)]
            svgRecordTraced(loops, at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .cross, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(armHalfLength), Float(armHalfLength)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(r),
                  param0: SIMD2<Float>(Float(armHalfWidth), 0))
    }

    /// A filled ring (annulus) centered at `(x, y)` between `innerRadius` and
    /// `outerRadius`. Takes the current `fill` (not stroke); for two outlined
    /// circles instead, draw `drawCircle` twice with `noFill`. Recorded as a single
    /// SDF instance.
    func drawRing(_ x: Double, _ y: Double, _ innerRadius: Double, _ outerRadius: Double) {
        guard outerRadius > 0, innerRadius >= 0, innerRadius < outerRadius else { return }
        if svgRecorder != nil {
            let c = Vector2(x, y)
            var contours = [Contour(svgOffset(SDFOutline.circle(radius: outerRadius), c), closed: true)]
            if innerRadius > 0 {
                contours.append(Contour(svgOffset(SDFOutline.circle(radius: innerRadius), c), closed: true))
            }
            svgRecord(.path(Shape(contours: contours, winding: .evenOdd)), fill: fillPaint, stroke: nil)
            return
        }
        let mid = (outerRadius + innerRadius) / 2
        let half = (outerRadius - innerRadius) / 2
        appendSDF(shape: .ring, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(outerRadius), Float(outerRadius)),
                  fill: fillPaint, stroke: nil,
                  param0: SIMD2<Float>(Float(mid), Float(half)))
    }

    /// An isosceles trapezoid centered at `(x, y)`, `topWidth` across the top edge
    /// and `bottomWidth` across the bottom, `height` tall. A rectangle when the two
    /// widths match, a triangle when one is `0`. Recorded as a single SDF instance —
    /// analytic fill + stroke + anti-aliasing. Rotate via the transform stack.
    func drawTrapezoid(_ x: Double, _ y: Double, _ topWidth: Double, _ bottomWidth: Double, _ height: Double) {
        guard height > 0, topWidth >= 0, bottomWidth >= 0, topWidth + bottomWidth > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.trapezoid(topWidth: topWidth, bottomWidth: bottomWidth, height: height), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        let halfMax = max(topWidth, bottomWidth) / 2
        appendSDF(shape: .trapezoid, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(halfMax), Float(height / 2)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(topWidth / 2), Float(bottomWidth / 2)))
    }

    /// A parallelogram centered at `(x, y)`, `width` wide and `height` tall, with the
    /// top edge sheared `skew` points along +x relative to the bottom (`0` is a
    /// rectangle). Recorded as a single SDF instance. Rotate via the transform stack.
    func drawParallelogram(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ skew: Double) {
        guard width > 0, height > 0 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.parallelogram(width: width, height: height, skew: skew), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .parallelogram, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2 + abs(skew)), Float(height / 2)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(skew),
                  param0: SIMD2<Float>(Float(width / 2), 0))
    }

    /// An egg centered at `(x, y)`: a circle of `bottomRadius` at the fat lower end
    /// tapering to a rounded tip of `topRadius` at the top, pointing up.
    /// `bottomRadius` must be ≥ `topRadius` (equal is a circle). Recorded as a single
    /// SDF instance. Rotate via the transform stack.
    func drawEgg(_ x: Double, _ y: Double, _ bottomRadius: Double, _ topRadius: Double) {
        guard bottomRadius > 0, topRadius > 0, topRadius <= bottomRadius else { return }
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.egg(bottomRadius: bottomRadius, topRadius: topRadius),
                            at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        // Native span is y in [-bottomRadius, apex]; the fragment recenters on the
        // quad, so size.y carries the symmetric half-height around that center.
        let apex = 1.7320508075688772 * (bottomRadius - topRadius) + topRadius
        let halfHeight = (apex + bottomRadius) / 2
        appendSDF(shape: .egg, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(bottomRadius), Float(halfHeight)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(bottomRadius), Float(topRadius)))
    }

    /// A heart centered at `(x, y)`, `size` points wide (a touch shorter than wide),
    /// lobes up and point down. Recorded as a single SDF instance. Rotate via the
    /// transform stack (45° spins it like a playing-card suit, 180° points it up).
    func drawHeart(_ x: Double, _ y: Double, _ size: Double) {
        guard size > 0 else { return }
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.heart(size: size), at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        // The unit heart spans width 1.2036, height 1.0985 (lobes up); scale so the
        // width matches `size`. The fragment flips Y and recenters.
        let s = size / 1.2036
        appendSDF(shape: .heart, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(0.6018 * s), Float(0.54925 * s)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(s), 0))
    }

    /// A disk of `radius` centered at `(x, y)` with a straight horizontal slice
    /// removed — a dome, flat edge down and bulge up. `cut` is the signed offset of
    /// the flat edge from the center (`-radius...radius`): `0` is a half disk,
    /// positive raises the cut and keeps a smaller cap, negative keeps more than
    /// half. Recorded as a single SDF instance. Rotate via the transform stack to
    /// aim the flat edge.
    func drawCutDisk(_ x: Double, _ y: Double, _ radius: Double, _ cut: Double) {
        guard radius > 0, abs(cut) < radius else { return }
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.cutDisk(radius: radius, cut: cut),
                            at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .cutDisk, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(radius), Float(radius)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(radius), Float(cut)))
    }

    /// A tapered capsule (a rounded bar with unequal end radii) from `a` (radius
    /// `ra`) to `b` (radius `rb`) — `drawLine` with mismatched round caps, taking
    /// fill + stroke like a shape. The end-to-end distance must be at least
    /// `|ra − rb|` (otherwise one cap swallows the other). Recorded as a single SDF
    /// instance.
    func drawUnevenCapsule(_ a: Vector2, _ b: Vector2, _ ra: Double, _ rb: Double) {
        guard ra > 0, rb > 0 else { return }
        let d = b - a
        let len = d.length
        guard len > 1e-6, len >= abs(ra - rb) else { return }
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.unevenCapsule(a: a, b: b, ra: ra, rb: rb),
                            at: (a + b) / 2, fill: fillPaint, stroke: strokePaint)
            return
        }
        let dir = d / len
        let bound = len / 2 + max(ra, rb)
        appendSDF(shape: .unevenCapsule, center: (a + b) / 2,
                  size: SIMD2<Float>(Float(bound), Float(bound)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(len),
                  param0: SIMD2<Float>(Float(ra), Float(rb)),
                  param1: SIMD2<Float>(Float(dir.y), Float(dir.x)))
    }

    /// A horseshoe (a thick arc with a gap) centered at `(x, y)`: a band at mid-
    /// radius `radius`, `thickness` thick, open across an arc of `gap` radians at
    /// the bottom (a smaller `gap` is more nearly closed; `0` is a full ring with a
    /// pinhole, `.pi` is a half-ring). Recorded as a single SDF instance — analytic
    /// fill + stroke + anti-aliasing. Rotate via the transform stack to aim the
    /// opening; rotation pivots on the center.
    func drawHorseshoe(_ x: Double, _ y: Double, _ radius: Double, _ thickness: Double, gap: Double) {
        guard radius > 0, thickness > 0 else { return }
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.horseshoe(radius: radius, thickness: thickness, gap: gap),
                            at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        // `c` is the (cos, sin) of half the opening angle: the band then wraps
        // the remaining 2·(π − gap/2), so `gap` is the full angular opening.
        let an = min(max(gap / 2, 1e-3), Double.pi - 1e-3)
        let w = Float(thickness / 2)
        let bound = Float(radius + thickness)
        appendSDF(shape: .horseshoe, center: Vector2(x, y),
                  size: SIMD2<Float>(bound, bound),
                  fill: fillPaint, stroke: strokePaint, extra: Float(radius),
                  param0: SIMD2<Float>(Float(cos(an)), Float(sin(an))),
                  param1: SIMD2<Float>(w, w))
    }

    /// A filled parabolic arch centered at `(x, y)`, `width` across the flat base
    /// and `height` tall, the curve peaking at the top (a parabola capping a
    /// straight base). Recorded as a single SDF instance — analytic fill + stroke +
    /// anti-aliasing. Rotate via the transform stack.
    func drawParabola(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        guard width > 0, height > 0 else { return }
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.parabola(width: width, height: height),
                            at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .parabola, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2), Float(height / 2)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(width / 2), Float(height)))
    }

    /// An X (saltire) centered at `(x, y)`, `length` tip-to-tip along each axis,
    /// drawn with round-capped arms `thickness` wide. Like `drawCross` rotated 45°
    /// but with rounded ends. Recorded as a single SDF instance — analytic fill +
    /// stroke + anti-aliasing. Rotate via the transform stack.
    func drawRoundedX(_ x: Double, _ y: Double, _ length: Double, _ thickness: Double) {
        guard length > 0, thickness > 0 else { return }
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.roundedX(length: length, thickness: thickness),
                            at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        let r = thickness / 2
        // The diagonal tips reach `w/2 + r/√2` per axis; invert to hit `length/2`.
        let w = max(length - thickness * 0.7071067811865476, 0)
        appendSDF(shape: .roundedX, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(length / 2 + r), Float(length / 2 + r)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(r),
                  param0: SIMD2<Float>(Float(w), 0))
    }

    /// A blobby cross centered at `(x, y)`: a four-armed cross with concave,
    /// inward-curving sides, its tips reaching `radius` along each axis.
    /// `blobbiness` (`0...1`, default `0.5`) sets how pinched the waist is — larger
    /// is more bulbous. Recorded as a single SDF instance. Rotate via the transform
    /// stack (45° gives a diagonal four-point pinwheel).
    func drawBlobbyCross(_ x: Double, _ y: Double, _ radius: Double, blobbiness: Double = 0.5) {
        guard radius > 0 else { return }
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.blobbyCross(radius: radius, blobbiness: blobbiness),
                            at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        let he = min(max(blobbiness, 0.3), 0.6)
        // The unit cross's tip lands at `tipUnit` along each axis; scale so it
        // reaches `radius`. (Larger `he` → shorter tips / fatter arms, so `tipUnit`
        // shrinks and the scale grows — the shape just gets blobbier at fixed reach.)
        let tipUnit = 1 / (he * 2.0.squareRoot()) - 1
        let s = radius / tipUnit
        appendSDF(shape: .blobbyCross, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(radius * 1.08), Float(radius * 1.08)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(s), Float(he)))
    }

    /// A tunnel / archway centered at `(x, y)`: vertical walls and a flat base under
    /// a semicircular top, `width` wide and `height` tall overall (the arch radius is
    /// half the width, so `height` must be at least `width / 2`). Recorded as a
    /// single SDF instance. Rotate via the transform stack to aim the opening.
    func drawTunnel(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        guard width > 0, height >= width / 2 else { return }
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.tunnel(width: width, height: height),
                            at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            return
        }
        let whx = width / 2                 // half-width = arch radius
        let why = height - whx              // straight-wall height
        appendSDF(shape: .tunnel, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2), Float(height / 2)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(whx), Float(why)))
    }

    /// A staircase centered at `(x, y)`: `steps` steps, each `stepWidth` wide and
    /// `stepHeight` tall, ascending to the right. The whole flight spans
    /// `stepWidth · steps` by `stepHeight · steps`. Recorded as a single SDF
    /// instance. Rotate via the transform stack.
    func drawStairs(_ x: Double, _ y: Double, _ stepWidth: Double, _ stepHeight: Double, steps: Int) {
        guard stepWidth > 0, stepHeight > 0, steps >= 1 else { return }
        if svgRecorder != nil {
            svgRecord(.polygon(svgOffset(SDFOutline.stairs(stepWidth: stepWidth, stepHeight: stepHeight, steps: steps), Vector2(x, y))),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        let n = Double(steps)
        appendSDF(shape: .stairs, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(stepWidth * n / 2), Float(stepHeight * n / 2)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(steps),
                  param0: SIMD2<Float>(Float(stepWidth), Float(stepHeight)))
    }

    /// The iconic hand-drawn "S" centered at `(x, y)`, `size` points tall.
    /// Recorded as a single SDF instance — analytic fill + stroke + anti-aliasing.
    /// Rotate via the transform stack.
    func drawCoolS(_ x: Double, _ y: Double, _ size: Double) {
        guard size > 0 else { return }
        if svgRecorder != nil {
            svgRecordTraced(SDFOutline.coolS(size: size), at: Vector2(x, y), fill: fillPaint, stroke: strokePaint)
            if strokePaint != nil {
                for line in SDFOutline.coolSInteriorLines(size: size) {
                    svgRecord(.polyline(svgOffset(line, Vector2(x, y))), fill: nil, stroke: strokePaint)
                }
            }
            return
        }
        // The unit "S" spans about y in [-1.05, 1.05]; scale so `size` is its height.
        let s = size / 2.1
        appendSDF(shape: .coolS, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(size / 2 + s * 0.1), Float(size / 2 + s * 0.1)),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(s), 0))
    }

    /// Shared builder for `drawNgon`/`drawStar`. Encodes the star into the SDF
    /// slots the way `sdStar` (in `ShaderShapes.metal`) reads them: `size = (R, R)` (R is
    /// both the outer radius and the bounding half-extent), `param0 = (cos, sin)` of
    /// the half-sector angle `an = π/points`, `param1 = (cos, sin)` of the edge angle
    /// `en`, and `extra = an`. The inner radius sets `en` via
    /// `inner = R·(cos an − sin an / tan en)`, inverted here to
    /// `en = atan2(sin an, cos an − inner/R)` (a regular polygon's apothem gives
    /// `en = π/2`, i.e. straight edges).
    private func appendStar(center: Vector2, outer: Double, inner: Double, points n: Int) {
        let an = Double.pi / Double(n)
        let acs = SIMD2<Float>(Float(cos(an)), Float(sin(an)))
        let en = atan2(sin(an), cos(an) - inner / outer)
        let ecs = SIMD2<Float>(Float(cos(en)), Float(sin(en)))
        appendSDF(shape: .star, center: center,
                  size: SIMD2<Float>(Float(outer), Float(outer)),
                  fill: fillPaint, stroke: strokePaint,
                  extra: Float(an), param0: acs, param1: ecs)
    }

    /// One paint encoded for an `SDFInstance` color slot: a solid color as-is
    /// (kind 0), or a gradient's geometry — made relative to the shape center, so
    /// the fragment evaluates it against `in.local` and it rides the CTM — with
    /// the paint kind for the shape-tag bits and the ramp's strip row.
    private struct EncodedPaint {
        var slot: SIMD4<Float>
        var kind: UInt32      // 0 solid, 1 linear, 2 radial, 3 along-path
        var row: Float

        static let none = EncodedPaint(slot: SIMD4<Float>(repeating: 0), kind: 0, row: 0)
    }

    private func encodePaint(_ paint: Paint, center: Vector2) -> EncodedPaint {
        switch paint {
        case .color(let c):
            return EncodedPaint(slot: c.simd4, kind: 0, row: 0)
        case .gradient(let g):
            let row = Float(gradientRow(for: g.ramp).index)
            switch g.geometry {
            case .linear(let start, let end):
                let s = start - center
                let e = end - center
                return EncodedPaint(slot: SIMD4<Float>(Float(s.x), Float(s.y), Float(e.x), Float(e.y)),
                                    kind: 1, row: row)
            case .radial(let c, let r):
                let cc = c - center
                return EncodedPaint(slot: SIMD4<Float>(Float(cc.x), Float(cc.y), Float(max(r, 1e-6)), 0),
                                    kind: 2, row: row)
            case .alongPath:
                return EncodedPaint(slot: SIMD4<Float>(repeating: 0), kind: 3, row: row)
            }
        }
    }

    /// Record one analytic shape as an SDF instance, carrying the current
    /// transform plus the given fill, stroke, and shape-specific slots. A `nil`
    /// fill/stroke becomes a zero-alpha color the shader treats as "skip"; a
    /// caller passes explicit paints (e.g. a line passes its stroke as `fill`).
    /// No-op when there's nothing to draw.
    func appendSDF(shape: SDFShape, center: Vector2, size: SIMD2<Float>,
                           fill: Paint?, stroke: Paint?, strokeWidth: Double? = nil,
                           extra: Float = 0,
                           param0: SIMD2<Float> = .zero, param1: SIMD2<Float> = .zero,
                           param2: SIMD2<Float> = .zero,
                           applyHollow: Bool = true) {
        // Inside a scoped-combine block, capture this shape as an SDF leaf instead of
        // drawing it (it merges with its siblings when the block closes).
        if !combineStack.isEmpty {
            captureCombineLeaf(shape: shape, center: center, size: size, fill: fill,
                               extra: extra, param0: param0, param1: param1, param2: param2)
            return
        }
        // SVG export safety net: the only SDF that still funnels here while
        // recording is the bitmap-text pixel (a `.box`); every other shape is
        // intercepted at its public draw method. Emit it as a `<rect>`.
        if svgRecorder != nil {
            if shape == .box {
                let corner = Vector2(center.x - Double(size.x), center.y - Double(size.y))
                svgRecord(.rect(corner: corner, width: Double(size.x) * 2, height: Double(size.y) * 2,
                                cornerRadius: Double(extra)), fill: fill, stroke: stroke)
            }
            return
        }
        let weight = strokeWidth ?? self.strokeWidth
        let hasStroke = stroke != nil && weight > 0
        guard fill != nil || hasStroke else { return }
        // An analytic shape carries one width in its instance, so a width profile
        // has nowhere to live: it draws at the plain weight and says so once.
        if hasStroke, !strokeProfileShape.isUniform {
            noteOnce("strokeProfile(_:) applies to stroked paths (drawLine / drawBezier / drawPolyline / drawCurve / drawShape outlines); \(shape) draws its outline at strokeWeight.")
        }
        // Same story for a brush: an analytic shape's outline is one continuous
        // band the fragment evaluates, with no path to walk laying stamps along.
        if hasStroke, strokeBrushShape != nil {
            noteOnce("strokeBrush(_:) applies to stroked paths (drawLine / drawBezier / drawPolyline / drawCurve / drawShape outlines); \(shape) draws its outline as a continuous stroke.")
        }
        // Hollow mode applies only to region shapes the fragment can onion; the
        // round-dot point path shares the `.ellipse` tag, so it opts out here.
        let band = (applyHollow && shape.honorsHollow) ? Float(hollowWidth) : 0
        ensureBatch(.sdf)
        let fillEnc = fill.map { encodePaint($0, center: center) } ?? .none
        let strokeEnc = hasStroke ? encodePaint(stroke!, center: center) : .none
        var instance = SDFInstance(
            transform: transform,
            center: center.simd2,
            size: size,
            fillColor: fillEnc.slot,
            strokeColor: strokeEnc.slot,
            param0: param0,
            param1: param1,
            param2: param2,
            strokeWidth: hasStroke ? Float(weight) : 0,
            extra: extra,
            bandWidth: band,
            // Stroke alignment and the two paint kinds ride in the shape tag's
            // high bits (the tag itself is < 256), so they cost no instance room.
            shape: shape.rawValue | (strokeAlignment.shaderCode << 8)
                 | (fillEnc.kind << 10) | (strokeEnc.kind << 12),
            fillGradient: fillEnc.row,
            strokeGradient: strokeEnc.row)
        sdfInstances.append(instance)
        // Symmetry: one more instance per remaining fold, the fold left-composed
        // onto the CTM. The rest of the instance (shape, paint, stroke, the
        // local-space gradient geometry) copies through, so replicas match exactly.
        if let folds = symmetryFolds, !isReplicating {
            for fold in folds.dropFirst() {
                instance.transform = fold * transform
                sdfInstances.append(instance)
            }
        }
    }

    /// Draw a composed signed-distance field (`SDF`): its shapes merge into one
    /// region, filled with the current `fill` (or each leaf's `.colored`) and
    /// stroked along the *merged* outline with the current `stroke`/`strokeWeight`.
    /// The tree is flattened to an instruction program the fragment evaluates per
    /// pixel (see ShaderCombinator.metal). A solid `fill` colors leaves individually
    /// (`.colored` per leaf, melted at smooth seams); a linear/radial gradient `fill`
    /// or `stroke` paints the whole merged region/outline by field position instead
    /// (along-path has no single path on a merged field, so it isn't supported there).
    func drawSDF(_ sdf: SDF) {
        // A field has no polygonal outline to serialize; SVG export of one would need
        // marching-squares contouring (a follow-up), so for now it records nothing.
        if svgRecorder != nil { return }

        let defaultFill: Color = {
            if case .some(.color(let c)) = fillPaint { return c }
            return .white
        }()
        let nodeStart = sdfNodes.count
        var nodes: [SDFNode] = []
        let bounds = sdf.flatten(defaultFill: defaultFill, into: &nodes)
        guard !nodes.isEmpty else { return }
        // Bound the work: skip (loudly) a field too large or too deeply nested for the
        // shader's fixed stacks, rather than mis-drawing it silently.
        if nodes.count > SDF.maxNodes {
            print("Ollin: drawSDF — field has \(nodes.count) nodes (max \(SDF.maxNodes)); skipping.")
            return
        }
        if bounds.valueDepth > SDF.maxValueDepth || bounds.pointDepth > SDF.maxPointDepth {
            print("Ollin: drawSDF — field nests too deep (combine \(bounds.valueDepth)/\(SDF.maxValueDepth), transform \(bounds.pointDepth)/\(SDF.maxPointDepth)); skipping.")
            return
        }

        // Covering quad = the whole-tree AABB, grown by half the stroke + a small AA
        // margin. The field origin is the CTM origin; `center` offsets the quad onto
        // the AABB while the VM still evaluates in field coordinates.
        let center = (bounds.lo + bounds.hi) * 0.5

        // Fill: the leaves' own (melted) colors by default, or — when the current `fill` is a
        // linear/radial gradient — that gradient painting the whole merged region by field
        // position (the leaf colors bypassed). Geometry is in field coords (`center: .zero`,
        // sampled at `in.field`); along-path has no single path on a merged field, so it's skipped.
        var fillGeo = SIMD4<Float>(repeating: 0)
        var fillKind: Float = 0
        var fillRow: Float = 0
        if let fillPaint, case .gradient = fillPaint {
            let enc = encodePaint(fillPaint, center: .zero)
            if enc.kind == 1 || enc.kind == 2 {
                fillGeo = enc.slot; fillKind = Float(enc.kind); fillRow = enc.row
            }
        }

        // Stroke: a solid color, or a linear/radial gradient traced along the merged outline
        // (its geometry rides the `strokeColor` slot, as `SDFInstance` reuses its color slots).
        // An along-path gradient has no single path on a merged outline, so it draws no stroke.
        var strokeSlot = SIMD4<Float>(repeating: 0)
        var strokeKind: Float = 0
        var strokeRow: Float = 0
        var strokeOn = false
        if strokeWidth > 0, let strokePaint {
            let enc = encodePaint(strokePaint, center: .zero)
            if enc.kind <= 2 {            // 0 solid, 1 linear, 2 radial (3 along-path: unsupported)
                strokeSlot = enc.slot
                strokeKind = Float(enc.kind)
                strokeRow = enc.row
                strokeOn = true
            }
        }
        let weight: Float = strokeOn ? Float(strokeWidth) : 0
        let hw = strokeOn ? Float(strokeWidth) * 0.5 : 0
        let ext = (bounds.hi - bounds.lo) * 0.5 + SIMD2<Float>(repeating: hw + 2)

        sdfNodes.append(contentsOf: nodes)
        ensureBatch(.sdfGroup)
        var group = SDFGroupInstance(
            transform: transform, center: center, size: ext,
            strokeColor: strokeSlot, strokeWidth: weight,
            bandWidth: 0, nodeStart: UInt32(nodeStart), nodeCount: UInt32(nodes.count),
            fillGradientGeo: fillGeo, fillGradientKind: fillKind, fillGradientRow: fillRow,
            strokeGradientKind: strokeKind, strokeGradientRow: strokeRow)
        sdfGroups.append(group)
        // Symmetry: one more group per remaining fold, sharing the flattened node
        // program (nodeStart/nodeCount copy through; only the transform changes).
        if let folds = symmetryFolds, !isReplicating {
            for fold in folds.dropFirst() {
                group.transform = fold * transform
                sdfGroups.append(group)
            }
        }
    }

    /// Draw a composed 3D signed-distance field: sphere-traced through the active
    /// camera, lit by the scene's lights, and depth-composited with the rasterized
    /// meshes (see SDF3D / ShaderRaymarch.metal). Requires a camera (3D only). A solid
    /// `fill` colors leaves individually (`.colored` per leaf, melted at smooth seams);
    /// a gradient `fill` paints the whole merged surface by screen position instead.
    func drawSDF3D(_ sdf: SDF3D) {
        // Raymarched fields interlock with the frame's shadow/lighting passes the
        // way meshes do, so they stay per-frame too.
        if isRecordingBatch {
            noteBatchRecording("drawSDF3D inside makeBatch { } is not recorded; draw 3D fields where the batch is drawn.")
            return
        }
        guard camera3D != nil else { return }   // 3D only — needs an active camera
        // SVG export is 2D vector only; a sphere-traced surface has no vector outline.
        if svgRecorder != nil { return }
        // A field is an equation rather than a surface; `isosurface(at:in:_:)`
        // turns one into a mesh a file can hold.
        if let spatialRecorder { spatialRecorder.skip("a raymarched field"); return }
        currentTarget?.needsDepth = true        // 3D in a target → that pass carries depth

        let defaultFill: Color = {
            if case .some(.color(let c)) = fillPaint { return c }
            return .white
        }()
        let nodeStart = sdf3DNodes.count
        var nodes: [SDFNode3D] = []
        let bounds = sdf.flatten(defaultFill: defaultFill, into: &nodes)
        guard !nodes.isEmpty else { return }
        // Bound the work to the shader's fixed stacks: skip (loudly) a field too large
        // or too deeply nested rather than mis-drawing it.
        if nodes.count > SDF3D.maxNodes {
            print("Ollin: drawSDF3D — field has \(nodes.count) nodes (max \(SDF3D.maxNodes)); skipping.")
            return
        }
        if bounds.valueDepth > SDF3D.maxValueDepth || bounds.pointDepth > SDF3D.maxPointDepth {
            print("Ollin: drawSDF3D — field nests too deep (combine \(bounds.valueDepth)/\(SDF3D.maxValueDepth), transform \(bounds.pointDepth)/\(SDF3D.maxPointDepth)); skipping.")
            return
        }

        // Place the field in world space by the current 3D model matrix. The march runs
        // in world space and maps each sample back into the field's local frame, so the
        // group carries the inverse model + the uniform scale (local distance → world
        // distance) and the field's world-space AABB (the 8 local corners transformed,
        // padded a touch for the smooth-blend bulge + AA so the box never clips).
        let m = modelMatrix
        let inv = m.inverse
        let scale = simd_length(SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z))
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for cx in [bounds.lo.x, bounds.hi.x] {
            for cy in [bounds.lo.y, bounds.hi.y] {
                for cz in [bounds.lo.z, bounds.hi.z] {
                    let w = m * SIMD4<Float>(cx, cy, cz, 1)
                    let p = SIMD3<Float>(w.x, w.y, w.z)
                    lo = simd_min(lo, p); hi = simd_max(hi, p)
                }
            }
        }
        let pad = SIMD3<Float>(repeating: 0.05 * max(scale, 1e-4))
        lo -= pad; hi += pad

        // A gradient `fill` paints the whole merged surface by screen position (the leaves'
        // own colors are bypassed). The geometry is in absolute canvas points (center .zero),
        // since the raymarch fragment samples it at each hit's projected screen position;
        // along-path has no meaning on a field, so only linear/radial paint the surface.
        var gradientGeo = SIMD4<Float>(repeating: 0)
        var gradientKind: Float = 0
        var gradientRow: Float = 0
        if let fillPaint, case .gradient = fillPaint {
            let encoded = encodePaint(fillPaint, center: .zero)
            if encoded.kind == 1 || encoded.kind == 2 {
                gradientGeo = encoded.slot
                gradientKind = Float(encoded.kind)
                gradientRow = encoded.row
            }
        }

        sdf3DNodes.append(contentsOf: nodes)
        ensureSDF3DBatch(currentMaterial)
        sdf3DGroups.append(SDF3DGroupInstance(
            inverseModel: inv,
            boundsMin: SIMD4<Float>(lo.x, lo.y, lo.z, 0),
            boundsMax: SIMD4<Float>(hi.x, hi.y, hi.z, 0),
            fillGradientGeo: gradientGeo,
            modelScale: scale, nodeStart: UInt32(nodeStart),
            nodeCount: UInt32(nodes.count), unbounded: bounds.unbounded ? 1 : 0,
            fillGradientKind: gradientKind, fillGradientRow: gradientRow,
            _pad0: 0, _pad1: 0))
    }

    // MARK: SDF-combinator scoped blocks (sugar over the `SDF` value type)

    enum CombineFrameKind {
        case combine(SDF.Combine, Float, Float)   // fold children under this op
                                                  // (k = smoothing / joint size, 0 = hard;
                                                  //  the second value = stairs step count)
        // Union the children, then apply this domain op. Carried for both dimensions (the
        // 2D `SDF.Transform` for captured 2D shapes, the 3D `SDF3D.Transform` for 3D ones).
        case domain(SDF.Transform, SDF3D.Transform)
        // Fold each child under the mode/melt state it was captured with (the `sculpt { }`
        // block, whose `add()`/`carve()`/`blend(_:)` verbs mutate that state mid-block).
        case sculpt
    }
    final class CombineFrame {
        let kind: CombineFrameKind
        var children: [SDF] = []        // 2D region leaves captured in this block
        var children3D: [SDF3D] = []    // 3D mesh-primitive leaves captured in this block
        // The sculpt block's mutable state, snapshotted per child as it's captured
        // (read only when kind == .sculpt; the arrays parallel children/children3D).
        var sculptCarve = false
        var sculptBlend: Float = 0
        var childModes: [(carve: Bool, k: Float)] = []
        var childModes3D: [(carve: Bool, k: Float)] = []
        init(_ kind: CombineFrameKind) { self.kind = kind }
        func append(_ field: SDF) {
            children.append(field)
            childModes.append((sculptCarve, sculptBlend))
        }
        func append3D(_ field: SDF3D) {
            children3D.append(field)
            childModes3D.append((sculptCarve, sculptBlend))
        }
        /// The combine op a sculpt child folds under, from its captured mode/melt.
        static func sculptOp(carve: Bool, k: Float) -> SDF.Combine {
            carve ? (k > 0 ? .smoothSubtract : .subtract)
                  : (k > 0 ? .smoothUnion : .union)
        }
    }

    /// Open a scoped combine block (`smoothUnion(k:) { … }` etc.). Both 2D SDF region
    /// draws and 3D mesh-primitive draws (`drawSphere`/`drawBox`/…) inside are captured
    /// and folded under `op` when the block closes; one block serves both dimensions, and
    /// a sketch is in one or the other (the captured-but-empty dimension just draws nothing).
    func beginCombine(op: SDF.Combine, k: Double, extra: Double = 0) {
        if combineStack.isEmpty { combineGroupTransform = transform; combineGroupModel = modelMatrix }
        combineStack.append(CombineFrame(.combine(op, Float(k), Float(extra))))
    }
    /// Open a scoped domain block (`mirrored { … }` / `repeated(…) { … }`): the contents
    /// are unioned, then the matching domain op is applied to the whole field (the 2D op to
    /// captured 2D shapes, the 3D op to captured 3D primitives; one block serves both).
    func beginCombineDomain(_ op2D: SDF.Transform, _ op3D: SDF3D.Transform) {
        if combineStack.isEmpty { combineGroupTransform = transform; combineGroupModel = modelMatrix }
        combineStack.append(CombineFrame(.domain(op2D, op3D)))
    }
    /// Open a sculpt block: children fold in draw order, each under the mode/melt state
    /// (`add()`/`carve()`, `blend(_:)`) active when it was drawn. Opens adding, hard.
    func beginSculpt() {
        if combineStack.isEmpty { combineGroupTransform = transform; combineGroupModel = modelMatrix }
        combineStack.append(CombineFrame(.sculpt))
    }
    /// The innermost enclosing sculpt frame (the one the mode verbs address), so a verb
    /// inside a nested domain/combine block steers how that block's result lands on the
    /// sculpt. `nil` outside any sculpt block.
    private var sculptFrame: CombineFrame? {
        combineStack.last(where: { if case .sculpt = $0.kind { return true }; return false })
    }
    private func withSculptFrame(_ verb: String, _ body: (CombineFrame) -> Void) {
        guard let frame = sculptFrame else {
            if !warnedSculptVerbOutside {
                print("Ollin: \(verb) only applies inside a sculpt { } block; ignored.")
                warnedSculptVerbOutside = true
            }
            return
        }
        body(frame)
    }
    /// Switch the active sculpt block to adding: subsequent shapes union on.
    func sculptAdd() { withSculptFrame("add()") { $0.sculptCarve = false } }
    /// Switch the active sculpt block to carving: subsequent shapes subtract.
    func sculptCarve() { withSculptFrame("carve()") { $0.sculptCarve = true } }
    /// Set the active sculpt block's melt radius for subsequent combines (0 = hard).
    func sculptBlend(_ k: Double) { withSculptFrame("blend(_:)") { $0.sculptBlend = Float(max(k, 0)) } }
    /// Close the innermost combine block: fold its children into one field (per dimension),
    /// then attach to the enclosing block, or (if this was the outermost) draw it.
    func endCombine() {
        guard let frame = combineStack.popLast() else { return }
        let field = buildCombineField(frame)
        let field3D = buildCombine3DField(frame)
        if let parent = combineStack.last {
            if let field { parent.append(field) }
            if let field3D { parent.append3D(field3D) }
            return
        }
        // Outermost: draw under the group's transforms (captured when it opened), restored
        // after in case the body changed the CTM / model matrix without scoping it.
        let groupT = combineGroupTransform
        let groupM = combineGroupModel
        combineGroupTransform = nil
        combineGroupModel = nil
        warnedNonCombinable = false
        warnedMeshInCombine = false
        warnedSculptVerbOutside = false
        if let field {
            let saved = transform
            if let groupT { transform = groupT }
            drawSDF(field)
            transform = saved
        }
        if let field3D {
            let savedM = modelMatrix
            if let groupM { modelMatrix = groupM }
            drawSDF3D(field3D)
            modelMatrix = savedM
        }
    }
    private func buildCombineField(_ frame: CombineFrame) -> SDF? {
        guard var result = frame.children.first else { return nil }
        let rest = frame.children.dropFirst()
        switch frame.kind {
        case let .combine(op, k, n):
            for child in rest { result = SDF(.combine(op, result, child, k, n)) }
            return result
        case let .domain(t, _):
            for child in rest { result = SDF(.combine(.union, result, child, 0, 0)) }
            return SDF(.transformed(t, result))
        case .sculpt:
            // Each child folds under the mode/melt it was drawn with (the first child is
            // the base either way: carving from nothing leaves nothing worth drawing).
            for i in frame.children.indices.dropFirst() {
                let (carve, k) = frame.childModes[i]
                result = SDF(.combine(CombineFrame.sculptOp(carve: carve, k: k),
                                      result, frame.children[i], k, 0))
            }
            return result
        }
    }
    private func buildCombine3DField(_ frame: CombineFrame) -> SDF3D? {
        guard var result = frame.children3D.first else { return nil }
        let rest = frame.children3D.dropFirst()
        switch frame.kind {
        case let .combine(op, k, n):
            let op3 = SDF3D.Combine(rawValue: op.rawValue) ?? .union
            for child in rest { result = SDF3D(.combine(op3, result, child, k, n)) }
            return result
        case let .domain(_, t):
            for child in rest { result = SDF3D(.combine(.union, result, child, 0, 0)) }
            return SDF3D(.transformed(t, result))
        case .sculpt:
            for i in frame.children3D.indices.dropFirst() {
                let (carve, k) = frame.childModes3D[i]
                let op2 = CombineFrame.sculptOp(carve: carve, k: k)
                let op3 = SDF3D.Combine(rawValue: op2.rawValue) ?? .union
                result = SDF3D(.combine(op3, result, frame.children3D[i], k, 0))
            }
            return result
        }
    }
    /// Capture one region shape (already decoded by its draw method) as an `SDF` leaf,
    /// placed in the active group's field space via the relative CTM.
    private func captureCombineLeaf(shape: SDFShape, center: Vector2, size: SIMD2<Float>,
                                    fill: Paint?, extra: Float,
                                    param0: SIMD2<Float>, param1: SIMD2<Float>, param2: SIMD2<Float>) {
        guard let frame = combineStack.last else { return }
        guard shape.isCombinable else {
            if !warnedNonCombinable {
                print("Ollin: a non-region shape inside a combine block is ignored; a combine merges filled regions (circle/rect/ngon/star/…).")
                warnedNonCombinable = true
            }
            return
        }
        let color: Color? = { if case .some(.color(let c)) = fill { return c }; return nil }()
        var leaf = SDF(.leaf(shape: shape, size: size, p0: param0, p1: param1, p2: param2,
                             extra: extra, color: color))
        // Map the shape into the group's field space: rel = groupCTM⁻¹ · drawCTM, applied
        // to the shape center (position) and decomposed into a uniform scale + rotation.
        let groupT = combineGroupTransform ?? transform
        let rel = simd_inverse(groupT) * transform
        let cc = rel * SIMD3<Float>(Float(center.x), Float(center.y), 1)
        let col0 = SIMD2<Float>(rel.columns.0.x, rel.columns.0.y)
        let scale = simd_length(col0)
        let angle = atan2(col0.y, col0.x)
        if abs(scale - 1) > 1e-4 { leaf = leaf.scaled(Double(scale)) }
        if abs(angle) > 1e-4 { leaf = leaf.rotated(Double(angle)) }
        leaf = leaf.at(Vector2(Double(cc.x), Double(cc.y)))
        frame.append(leaf)
    }

    /// The chokepoint for the SDF-able mesh primitives (`drawSphere`/`drawBox`/…). Inside a
    /// combine block the primitive is captured as an `SDF3D` leaf (merged with the others on
    /// close); otherwise it tessellates and draws as a normal mesh. `leaf` is the matching
    /// analytic field; `mesh` is built lazily so the capture path never tessellates.
    func drawMeshPrimitive(_ leaf: SDF3D, mesh: @autoclosure () -> Mesh) {
        if !combineStack.isEmpty {
            captureCombine3DLeaf(leaf)
            return
        }
        drawMesh(mesh())
    }

    /// Capture an SDF-able primitive as an `SDF3D` leaf, placed in the active group's field
    /// space via the relative model matrix (decomposed into translate + rotate + uniform
    /// scale, the only similarity an SDF respects).
    private func captureCombine3DLeaf(_ baseLeaf: SDF3D) {
        guard let frame = combineStack.last, camera3D != nil else { return }
        var leaf = baseLeaf
        if case .some(.color(let c)) = fillPaint { leaf = leaf.colored(c) }
        // rel = groupModel⁻¹ · drawModel — where this leaf sits relative to the group origin.
        let groupM = combineGroupModel ?? modelMatrix
        let rel = simd_inverse(groupM) * modelMatrix
        let t = SIMD3<Float>(rel.columns.3.x, rel.columns.3.y, rel.columns.3.z)
        let col0 = SIMD3<Float>(rel.columns.0.x, rel.columns.0.y, rel.columns.0.z)
        let s = simd_length(col0)
        if abs(s - 1) > 1e-4 { leaf = leaf.scaled(Double(s)) }
        if s > 1e-6 {
            // Strip the uniform scale to read the pure rotation, then its axis-angle.
            let r = simd_float3x3(
                SIMD3<Float>(rel.columns.0.x, rel.columns.0.y, rel.columns.0.z) / s,
                SIMD3<Float>(rel.columns.1.x, rel.columns.1.y, rel.columns.1.z) / s,
                SIMD3<Float>(rel.columns.2.x, rel.columns.2.y, rel.columns.2.z) / s)
            let q = simd_quatf(r)
            let angle = q.angle
            if angle.isFinite && angle > 1e-4 {
                let a = q.axis
                if simd_length(a) > 1e-6 {
                    leaf = leaf.rotated(Double(angle), axis: Vector3(Double(a.x), Double(a.y), Double(a.z)))
                }
            }
        }
        leaf = leaf.at(x: Double(t.x), y: Double(t.y), z: Double(t.z))
        frame.append3D(leaf)
    }

    /// An elliptical arc centered at `(x, y)` with radii `rx`/`ry`, sweeping from
    /// `start` to `stop` (radians, clockwise). `mode` decides how the ends close:
    /// `.open` leaves the curve open, `.chord` joins them with a straight line,
    /// `.pie` joins them through the center. A fill paints the enclosed region
    /// (segment for open/chord, wedge for pie); a stroke traces the outline.
    ///
    /// A *circular* arc (`rx == ry`) under less than a full turn is recorded as a
    /// single SDF instance — analytic fill + stroke + anti-aliasing, crisp at any
    /// size and effectively free. Elliptical arcs and full sweeps fall back to
    /// CPU tessellation, which renders them exactly; both composite in draw order.
    func drawArc(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double,
                 start: Double, stop: Double, mode: ArcMode) {
        guard rx > 0, ry > 0 else { return }
        let sweep = stop - start
        guard abs(sweep) > 1e-9 else { return }

        /// The arc as points, which both the vector recorder and the tessellated
        /// path need.
        func sampled() -> [Vector2] {
            let full = circleSegments(for: max(rx, ry))
            let segments = max(2, Int((Double(full) * abs(sweep) / (2.0 * .pi)).rounded(.up)))
            return (0...segments).map { i in
                let a = start + sweep * (Double(i) / Double(segments))
                return Vector2(x + cos(a) * rx, y + sin(a) * ry)
            }
        }

        // A brush stamps the outline, and it needs the arc as points whichever
        // path would otherwise draw it, so it comes ahead of both the vector
        // recorder and the analytic circular-arc case. The fill is emitted first
        // by this same call with the stroke cleared, so the stamps land over it.
        if strokeBrushShape != nil, strokePaint != nil, strokeWidth > 0 {
            let saved = strokePaint
            strokePaint = nil
            drawArc(x, y, rx, ry, start: start, stop: stop, mode: mode)
            strokePaint = saved
            let pts = sampled()
            switch mode {
            case .open:  _ = strokedAsBrush(pts, closed: false)
            case .chord: _ = strokedAsBrush(pts, closed: true)
            case .pie:   _ = strokedAsBrush([Vector2(x, y)] + pts, closed: true)
            }
            return
        }

        if svgRecorder != nil {
            let pts = sampled()
            let center = Vector2(x, y)
            if let fill = fillPaint {
                svgRecord(.polygon(mode == .pie ? [center] + pts : pts), fill: fill, stroke: nil)
            }
            if strokePaint != nil, strokeWidth > 0 {
                switch mode {
                case .open:  svgRecord(.polyline(pts), fill: nil, stroke: strokePaint)
                case .chord: svgRecord(.polygon(pts), fill: nil, stroke: strokePaint)
                case .pie:   svgRecord(.polygon([center] + pts), fill: nil, stroke: strokePaint)
                }
            }
            return
        }

        if abs(rx - ry) < 1e-6, abs(sweep) < Double.tau - 1e-4 {
            appendArcSDF(center: Vector2(x, y), radius: rx, start: start, stop: stop, mode: mode)
            return
        }

        // Sample the arc, scaling the segment count to the swept fraction so a
        // short arc stays cheap and a near-full one stays smooth.
        let pts = sampled()
        let center = Vector2(x, y)

        if let fill = fillPaint {
            // Anchored on the arc center, so an along-path fill sweeps the same
            // conic the SDF arc evaluates.
            let vp = vertexPaint(fill, anchor: center)
            replicated {
                switch mode {
                case .open, .chord:
                    // Circular segment: convex, so a fan from the first point fills it.
                    let p0 = pts[0].simd2
                    let c0 = vp.color(at: pts[0])
                    for i in 1..<(pts.count - 1) {
                        emit(p0, color: c0)
                        emit(pts[i].simd2, color: vp.color(at: pts[i]))
                        emit(pts[i + 1].simd2, color: vp.color(at: pts[i + 1]))
                    }
                case .pie:
                    // Wedge: fan from the center.
                    let cc = center.simd2
                    let centerColor = vp.color(at: center)
                    for i in 0..<(pts.count - 1) {
                        emit(cc, color: centerColor)
                        emit(pts[i].simd2, color: vp.color(at: pts[i]))
                        emit(pts[i + 1].simd2, color: vp.color(at: pts[i + 1]))
                    }
                }
            }
        }

        // The outline is a path like any other, so it goes through the fringe
        // expander: joins where the samples meet, caps on an open arc's ends, and
        // the shared inner crossing that keeps translucent ink to one coat. The
        // shapes match what the vector recorder above writes, so a rendered arc and
        // an exported one trace the same outline.
        if let stroke = strokePaint, strokeWidth > 0 {
            let vp = vertexPaint(stroke, anchor: center)
            switch mode {
            case .open:  appendFringeStroke(pts, closed: false, paint: vp)
            case .chord: appendFringeStroke(pts, closed: true, paint: vp)
            case .pie:   appendFringeStroke([center] + pts, closed: true, paint: vp)
            }
        }
    }

    /// Record one circular arc as an SDF instance. The fragment evaluates the
    /// pie / segment / arc-band field in a canonical frame where the arc's
    /// bisector points to +Y: `param1` is `(cos, sin)` of the rotation that takes
    /// it there, `param0` is `(sin, cos)` of the half-aperture, and `size.x` is
    /// the radius. The arc spans the same angular set the tessellated path does,
    /// so the two render identically.
    private func appendArcSDF(center: Vector2, radius: Double,
                              start: Double, stop: Double, mode: ArcMode) {
        let shape: SDFShape
        switch mode {
        case .open:  shape = .arcOpen
        case .chord: shape = .arcChord
        case .pie:   shape = .arcPie
        }
        let halfAperture = abs(stop - start) / 2
        let bisector = (start + stop) / 2
        // Rotate local points by φ = π/2 − bisector so the bisector maps to +Y.
        let phi = Double.pi / 2 - bisector
        let r = Float(radius)
        appendSDF(shape: shape, center: center,
                  size: SIMD2<Float>(r, r),
                  fill: fillPaint, stroke: strokePaint,
                  param0: SIMD2<Float>(Float(sin(halfAperture)), Float(cos(halfAperture))),
                  param1: SIMD2<Float>(Float(cos(phi)), Float(sin(phi))))
    }

    /// A connected open path through `points`, stroked with the current stroke
    /// paint and weight (solid, translucent, or gradient).
    ///
    /// Stroke-only — fills belong to closed shapes (`drawShape`). Open by
    /// default (the last point is not joined back to the first); `closed: true`
    /// joins it, turning that seam with `strokeJoin` like every other corner.
    /// Corners turn per `strokeJoin` (mitered by default, so fat strokes stay
    /// clean at sharp turns) and open ends finish per `strokeCap` (butt by
    /// default). Needs at least two points and a stroke to draw anything.
    func drawPolyline(_ points: [Vector2], closed: Bool = false) {
        guard points.count >= 2, let stroke = strokePaint, strokeWidth > 0 else { return }
        if strokedAsBrush(points, closed: closed) { return }
        if svgRecorder != nil {
            svgRecord(closed ? .polygon(points) : .polyline(points), fill: nil, stroke: stroke)
            return
        }
        // The full stroke (solid / translucent / gradient) renders through the
        // high-quality fringe expander — joins per strokeJoin, smooth at any angle.
        appendFringeStroke(points, closed: closed,
                           paint: vertexPaint(stroke, anchor: points[0]))
    }

    /// Stroke a recorded `StrokeMark`: the path it traveled, drawn at the width
    /// and opacity it asked for at every point.
    ///
    /// The mark reaches the same fringe expander every other stroke goes through,
    /// by turning its per-point widths into a width profile keyed to their *real*
    /// fractions along the path rather than evenly spaced ones. That is the whole
    /// reason a mark is its own type: its points bunch where the hand slowed, so
    /// spreading the widths evenly would slide each one off the place it was
    /// measured. Opacity rides the per-vertex color the same way.
    ///
    /// A width profile already set with `strokeProfile(_:)` still applies, and the
    /// two multiply. That is how a dynamic mark also gets a clean lift-off:
    /// `strokeProfile(.taper(start: 1))` on top of the recorded widths.
    ///
    /// Needs at least two recorded points and a stroke to draw anything.
    func drawMark(_ mark: StrokeMark) {
        guard mark.samples.count >= 2, let stroke = strokePaint, strokeWidth > 0 else { return }
        let points = mark.positions
        let fractions = mark.pathFractions

        pushState()
        defer { popState() }

        if mark.variesWidth {
            let recorded = StrokeProfile.values(mark.samples.map(\.width), at: fractions)
            let ambient = strokeProfileShape
            strokeProfileShape = ambient.isUniform ? recorded
                : StrokeProfile(directional: { t, d in recorded(t) * ambient(t, direction: d) })
        }

        if mark.variesOpacity {
            // A brush stamps each moment as its own shape, so it can carry the
            // recorded opacity into a vector document too; only the single-path
            // ribbon has to flatten it.
            if svgRecorder != nil, strokeBrushShape == nil {
                // A vector document draws one fill at one alpha per path, so a
                // varying opacity has nowhere to go. Flattening it to the ink the
                // mark laid down on average keeps the exported weight right, and
                // for the plotter case (one pen, one ink) it costs nothing at all.
                noteOnce("A mark's varying opacity flattens to its average in vector export; its varying width is exported exactly.")
                if case .color(let c) = stroke {
                    strokePaint = .color(c.withAlpha(c.alpha * mark.averageOpacity))
                }
            } else {
                strokeOpacityShape = StrokeProfile.values(mark.samples.map(\.opacity), at: fractions)
            }
        }

        if strokedAsBrush(points, closed: false) { return }
        if svgRecorder != nil {
            svgRecord(.polyline(points), fill: nil, stroke: strokePaint)
            return
        }
        appendFringeStroke(points, closed: false,
                           paint: vertexPaint(strokePaint ?? stroke, anchor: points[0]))
    }

    /// An axis-aligned `Rectangle`. Recorded as a single SDF instance (a box
    /// signed-distance field), not tessellated: the fragment derives fill, a
    /// stroke straddling the edges (width `strokeWeight`), and anti-aliasing
    /// analytically. `cornerRadius` rounds the corners (clamped to half the
    /// shorter side); the default `0` is a sharp rectangle. Crisp at any size and
    /// effectively free per rect, like `drawCircle`.
    func drawRect(_ rect: Rectangle, cornerRadius: Double = 0) {
        guard rect.width > 0, rect.height > 0 else { return }
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        if svgRecorder != nil {
            svgRecord(.rect(corner: Vector2(rect.x, rect.y), width: rect.width, height: rect.height, cornerRadius: r),
                      fill: fillPaint, stroke: strokePaint)
            return
        }
        appendSDF(shape: .box, center: rect.center,
                  size: SIMD2<Float>(Float(rect.width / 2), Float(rect.height / 2)),
                  fill: fillPaint, stroke: strokePaint, extra: Float(r))
    }
}
