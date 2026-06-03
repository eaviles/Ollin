import Foundation
import simd
import COllinShaders

// `OllinVertex`, `Uniforms`, and `SDFInstance` are imported from the
// `COllinShaders` C module: one definition shared with `Shaders.metal`, so their
// CPU/GPU memory layout can't drift. See Sources/Ollin/Renderer/OllinShaderTypes.h.

/// Which analytic shape an `SDFInstance` carries. The fragment shader switches
/// on this tag and evaluates the matching signed-distance field, so one pipeline
/// and one instance buffer serve every SDF primitive. Raw values must match the
/// `shape` codes the fragment in `Shaders.metal` tests.
enum SDFShape: UInt32 {
    case ellipse  = 0   // size = (rx, ry); circle is rx == ry
    case box      = 1   // size = (w/2, h/2); extra = corner radius
    case capsule  = 2   // a line: param0 = (b-a)/2; extra = half-width; fill = line color
    case arcOpen  = 3   // circular arc, open: size = (ra, ra)
    case arcChord = 4   // circular arc, chord-closed
    case arcPie   = 5   // circular arc, pie-closed
    case triangle = 6   // isosceles: apex at center, size = (base/2, height), opens +y
    case star     = 7   // regular n-gon / star: size = (R, R); param0/param1/extra = fold angles
    case marker   = 8   // point marker: size = (h, h); extra = kind (0 square,1 diamond,2 cross,3 x); param0.x = arm half-width
    case rhombus  = 9   // diamond: size = (w/2, h/2); extra = corner radius
    case vesica   = 10  // pointed lens: param0 = (circle radius, offset); param1.x = horizontal flag; extra = corner radius
    case moon     = 11  // crescent: param0 = (outer radius, inner radius); param1.x = offset; extra = corner radius
    case cross    = 12  // plus: size.x = arm half-length; param0.x = arm half-width; extra = corner radius
    case ring     = 13  // filled annulus: param0 = (mid radius, half thickness); fill only
    case trapezoid     = 14  // isosceles: param0 = (top half-width, bottom half-width); size.y = half-height
    case parallelogram = 15  // param0.x = base half-width; size.y = half-height; extra = skew
    case egg           = 16  // param0 = (bottom radius, top radius); points up
    case heart         = 17  // param0.x = unit->local scale; lobes up
    case cutDisk       = 18  // param0 = (radius, cut height); flat edge down
    case unevenCapsule = 19  // tapered capsule: param0 = (r1, r2); param1 = (cos, sin) axis; extra = length
    case horseshoe     = 20  // thick open arc: param0 = (cos, sin) half-gap; param1 = (cap half-len, half-thick); extra = mid radius
    case parabola      = 21  // filled parabolic arch: param0 = (top half-width, height); opens up
    case roundedX      = 22  // an X with round arms: param0.x = arm reach; extra = arm half-width
    case blobbyCross   = 23  // 4-fold concave cross: param0 = (scale, blobbiness)
    case tunnel        = 24  // archway (rounded top, flat base): param0 = (half-width, wall height)
    case stairs        = 25  // staircase: param0 = (step width, step height); extra = step count
    case coolS         = 26  // the iconic "S": param0.x = scale
    case triangle3     = 27  // general triangle: param0/param1/param2 = the three corners (rel. center)
    case bezier        = 28  // quadratic Bézier stroke: param0/param1/param2 = (start, control, end); extra = half-width
}

extension SDFShape {
    /// Whether this shape honors `hollow` mode — a closed region whose interior
    /// can be turned into a constant-width band (opOnion). Point markers, lines,
    /// and arcs aren't closed regions; the ring is already a band; so they ignore
    /// it. (The disk/`ellipse` honors it, becoming an elliptical ring; the
    /// round-dot point path opts out separately, since it shares the tag.)
    var honorsHollow: Bool {
        switch self {
        case .capsule, .marker, .arcOpen, .arcChord, .arcPie, .ring, .bezier:
            return false
        default:
            return true
        }
    }
}

/// Which pipeline a run of recorded geometry needs. Primitives are recorded in
/// call order; a `Batch` starts wherever the kind changes, so SDF shapes and
/// tessellated triangles still composite front-to-back in the order the sketch
/// drew them (a later shape paints over an earlier one).
enum GeometryKind {
    case triangles   // tessellated fills/strokes in `vertices`
    case sdf         // instanced SDF shapes in `sdfInstances`
}

struct GeometryBatch {
    var kind: GeometryKind
    var vertexStart: Int     // first vertex (triangle batches)
    var instanceStart: Int   // first instance (sdf batches)
}

/// The drawing state machine and per-frame geometry recorder.
///
/// `Drawer` is a state machine: you set *state* (fill, stroke, weight,
/// background) and then call *primitives* (circle, …). Each primitive is
/// tessellated on the CPU into triangles and appended to `vertices`, which the
/// renderer uploads and draws in a single pass.
///
/// State (fill/stroke/weight/background) persists across frames.
/// Geometry does not: the runner calls `beginFrame()` each frame to clear it.
final class Drawer {
    // MARK: Drawing state (persists across frames)

    /// The clear color for the frame. `nil`-fill / `nil`-stroke mean "don't draw".
    private(set) var backgroundColor: Color = .black
    private var fillColor: Color? = .white     // default: white fill
    private var strokeColor: Color? = .black    // default: black stroke
    private var strokeWidth: Double = 1         // default: 1px
    private var pointDiameter: Double = 1       // default: 1px dot (see pointSize / drawPoint)
    private var marker: PointMarker = .circle   // default: round dot (see pointMarker / drawPoint)
    private var hollowWidth: Double = 0         // 0 = solid fill; > 0 = hollow band (see hollow / solid)
    private var strokeAlignment: StrokeAlign = .center   // where the stroke sits on the outline (see strokeAlign)
    private var strokeJoinStyle: StrokeJoin = .miter     // how stroked-path corners turn (see strokeJoin)
    private var strokeCapStyle: StrokeCap = .butt        // how open stroked-path ends finish (see strokeCap)
    private var currentFont: ActiveFont = .bitmap(.builtin)   // active text font (see textFont / drawText)
    private var textPixelSize: Double = 24               // rendered glyph height in points (see textSize)
    private var textAlignH: TextAlignH = .left           // horizontal text anchor (see textAlign)
    private var textAlignV: TextAlignV = .baseline       // vertical text anchor (see textAlign)

    // MARK: Per-frame geometry (reset every frame)

    private(set) var vertices: [OllinVertex] = []

    /// Instanced SDF shapes recorded this frame (see `SDFInstance`).
    private(set) var sdfInstances: [SDFInstance] = []

    /// Recorded geometry split into call-ordered runs, so triangles and SDF
    /// shapes composite in draw order rather than in two unordered passes.
    private(set) var batches: [GeometryBatch] = []
    private var currentKind: GeometryKind?

    /// Open a new batch when the geometry kind changes; a no-op while the kind
    /// is unchanged, so it's cheap to call per primitive.
    private func ensureBatch(_ kind: GeometryKind) {
        guard currentKind != kind else { return }
        currentKind = kind
        batches.append(GeometryBatch(kind: kind, vertexStart: vertices.count,
                                     instanceStart: sdfInstances.count))
    }

    /// Current affine transform (2D homogeneous), applied to every emitted
    /// vertex. Reset to identity each frame.
    private var transform = matrix_identity_float3x3

    /// Tracks whether `transform` is still the identity, so `emit` can skip the
    /// per-vertex matrix multiply for the common case of a sketch that never
    /// translates/rotates/scales (the matmul runs hundreds of thousands of times
    /// a frame otherwise).
    private var transformIsIdentity = true

    /// Saved (transform + style) snapshots for `pushState()`/`popState()` / `withState`.
    private var stateStack: [SavedState] = []

    private struct SavedState {
        var transform: matrix_float3x3
        var transformIsIdentity: Bool
        var fillColor: Color?
        var strokeColor: Color?
        var strokeWidth: Double
        var pointDiameter: Double
        var marker: PointMarker
        var hollowWidth: Double
        var strokeAlignment: StrokeAlign
        var strokeJoinStyle: StrokeJoin
        var strokeCapStyle: StrokeCap
        var currentFont: ActiveFont
        var textPixelSize: Double
        var textAlignH: TextAlignH
        var textAlignV: TextAlignV
    }

    // MARK: State setters (mirrors the bare API on `Sketch`)

    /// Set the background/clear color. This also wipes anything drawn
    /// so far this frame (background paints over everything).
    func background(_ color: Color) {
        backgroundColor = color
        vertices.removeAll(keepingCapacity: true)
        sdfInstances.removeAll(keepingCapacity: true)
        batches.removeAll(keepingCapacity: true)
        currentKind = nil
    }

    func fill(_ color: Color) { fillColor = color }
    func noFill() { fillColor = nil }
    func stroke(_ color: Color) { strokeColor = color }
    func noStroke() { strokeColor = nil }
    func strokeWeight(_ weight: Double) { strokeWidth = max(0, weight) }
    func pointSize(_ size: Double) { pointDiameter = max(0, size) }
    func pointMarker(_ marker: PointMarker) { self.marker = marker }

    /// Draw region shapes as a constant-width band hugging their outline instead
    /// of a solid interior: the `fill` color paints the band, and an active
    /// `stroke` borders both of its edges (the way `drawRing` can be stroked).
    /// `width` is the band thickness, centered on the shape's edge.
    func hollow(_ width: Double) { hollowWidth = max(0, width) }

    /// Return to solid fills (the default).
    func solid() { hollowWidth = 0 }

    /// Set where a shape's stroke sits relative to its outline (see `StrokeAlign`):
    /// `.center` (default), `.inside`, or `.outside`. Affects the analytic SDF
    /// shapes; lines, point markers, and the tessellated paths stay centered.
    func strokeAlign(_ align: StrokeAlign) { strokeAlignment = align }

    /// Set how a stroked path turns its corners (see `StrokeJoin`): `.miter`
    /// (default), `.bevel`, or `.round`. Affects the tessellated stroked paths
    /// (`drawPolyline`, the `drawPolygon` outline, `drawShape` contours).
    func strokeJoin(_ join: StrokeJoin) { strokeJoinStyle = join }

    /// Set how the open ends of a stroked path finish (see `StrokeCap`): `.butt`
    /// (default), `.round`, or `.square`. Affects open tessellated paths
    /// (`drawPolyline`, open `drawShape` contours); closed outlines have no ends.
    func strokeCap(_ cap: StrokeCap) { strokeCapStyle = cap }

    /// Set the active text font to a bitmap (pixel-grid) font. Defaults to
    /// `.builtin`.
    func textFont(_ font: BitmapFont) { currentFont = .bitmap(font) }

    /// Set the active text font to an outline (vector `.ttf`/`.otf`) font.
    func textFont(_ font: OutlineFont) { currentFont = .outline(font) }

    /// Set the rendered text height in points — the height one line of glyphs
    /// occupies on screen (`drawText`). Defaults to 24.
    func textSize(_ size: Double) { textPixelSize = max(0, size) }

    /// Set the text anchor relative to the `drawText` position (see `TextAlignH` /
    /// `TextAlignV`): horizontal `.left`/`.center`/`.right`, vertical
    /// `.top`/`.middle`/`.baseline`/`.bottom`.
    func textAlign(_ horizontal: TextAlignH, _ vertical: TextAlignV = .baseline) {
        textAlignH = horizontal
        textAlignV = vertical
    }

    // MARK: Frame lifecycle

    /// Drop last frame's geometry but keep drawing state. Called once per frame
    /// by the runner before `Sketch.draw()`.
    func beginFrame() {
        vertices.removeAll(keepingCapacity: true)
        sdfInstances.removeAll(keepingCapacity: true)
        batches.removeAll(keepingCapacity: true)
        currentKind = nil
        transform = matrix_identity_float3x3
        transformIsIdentity = true
        stateStack.removeAll(keepingCapacity: true)
    }

    // MARK: Transforms & state stack

    /// Shift the origin by `offset` (points). Composes with the current
    /// transform; reset each frame.
    func translate(_ offset: Vector2) {
        transform = transform * Drawer.translation(Float(offset.x), Float(offset.y))
        transformIsIdentity = false
    }

    /// Rotate subsequent drawing by `radians` (clockwise, in Ollin's y-down space).
    func rotate(_ radians: Double) {
        transform = transform * Drawer.rotation(Float(radians))
        transformIsIdentity = false
    }

    /// Scale subsequent drawing by `(sx, sy)`.
    func scale(_ sx: Double, _ sy: Double) {
        transform = transform * Drawer.scaling(Float(sx), Float(sy))
        transformIsIdentity = false
    }

    /// Save the current transform and style (fill/stroke/weight).
    func pushState() {
        stateStack.append(SavedState(transform: transform, transformIsIdentity: transformIsIdentity,
                                     fillColor: fillColor, strokeColor: strokeColor,
                                     strokeWidth: strokeWidth, pointDiameter: pointDiameter,
                                     marker: marker, hollowWidth: hollowWidth,
                                     strokeAlignment: strokeAlignment,
                                     strokeJoinStyle: strokeJoinStyle,
                                     strokeCapStyle: strokeCapStyle,
                                     currentFont: currentFont, textPixelSize: textPixelSize,
                                     textAlignH: textAlignH, textAlignV: textAlignV))
    }

    /// Restore the most recently pushed transform and style. No-op if unbalanced.
    func popState() {
        guard let s = stateStack.popLast() else { return }
        transform = s.transform
        transformIsIdentity = s.transformIsIdentity
        fillColor = s.fillColor
        strokeColor = s.strokeColor
        strokeWidth = s.strokeWidth
        pointDiameter = s.pointDiameter
        marker = s.marker
        hollowWidth = s.hollowWidth
        strokeAlignment = s.strokeAlignment
        strokeJoinStyle = s.strokeJoinStyle
        strokeCapStyle = s.strokeCapStyle
        currentFont = s.currentFont
        textPixelSize = s.textPixelSize
        textAlignH = s.textAlignH
        textAlignV = s.textAlignV
    }

    // MARK: Primitives

    /// A circle centered at `(x, y)` with the given `radius` (points).
    ///
    /// Recorded as a single SDF instance, not tessellated: the fragment shader
    /// computes fill, stroke (width `strokeWeight`), and anti-aliasing
    /// analytically. Crisp at any size and effectively free per circle, which is
    /// what makes thousands of them cheap.
    func drawCircle(_ x: Double, _ y: Double, _ radius: Double) {
        guard radius > 0 else { return }
        appendSDF(shape: .ellipse, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(radius), Float(radius)),
                  fill: fillColor, stroke: strokeColor)
    }

    /// An axis-aligned ellipse centered at `(x, y)` with horizontal radius `rx`
    /// and vertical radius `ry` (points). Like `drawCircle`, the arguments are
    /// *radii*, not diameters — `drawEllipse(x, y, r, r)` is a circle.
    ///
    /// Recorded as a single SDF instance (see `drawCircle`); fill and a
    /// uniform-width stroke are derived analytically in the fragment shader.
    func drawEllipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
        guard rx > 0, ry > 0 else { return }
        appendSDF(shape: .ellipse, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(rx), Float(ry)),
                  fill: fillColor, stroke: strokeColor)
    }

    /// A filled marker at `(x, y)`. `size` is the on-screen *diameter* (points); the
    /// no-`size` form uses the current `pointSize`. The glyph is the current
    /// `pointMarker` (a round dot by default). A point takes the current `fill`
    /// color (not stroke) and ignores `strokeWeight`, so `noFill()` draws nothing.
    /// Recorded as one SDF instance, so it's crisp and effectively free per point.
    /// The round `.circle` marker also stays smooth down to sub-pixel sizes, fading
    /// by area instead of popping or snapping to 1px.
    func drawPoint(_ x: Double, _ y: Double, _ size: Double) {
        guard size > 0, let fill = fillColor else { return }
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
        let height = radius * 1.5                          // apex-to-base distance
        let halfBase = radius * 0.8660254037844386         // radius * √3/2
        // Anchor the centroid at (x, y); the apex (the SDF origin) sits `radius`
        // above it (the centroid is ⅓ of the height up from the base).
        appendSDF(shape: .triangle, center: Vector2(x, y - radius),
                  size: SIMD2<Float>(Float(halfBase), Float(height)),
                  fill: fillColor, stroke: strokeColor)
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
        appendSDF(shape: .triangle, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(base / 2), Float(height)),
                  fill: fillColor, stroke: strokeColor)
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
        let center = (lo + hi) / 2
        let half = (hi - lo) / 2
        appendSDF(shape: .triangle3, center: center,
                  size: SIMD2<Float>(Float(half.x), Float(half.y)),
                  fill: fillColor, stroke: strokeColor,
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
        // A regular polygon is the special case of a star whose inner radius is the
        // apothem (the edge midpoints), which straightens the points into edges.
        appendStar(center: Vector2(x, y), outer: radius,
                   inner: radius * cos(.pi / Double(sides)), points: sides)
    }

    /// A star centered at `(x, y)` with `points` outer points, alternating between
    /// `outerRadius` (the tips) and `innerRadius` (the valleys), one tip pointing
    /// up. `points` is 3 or more, and `innerRadius` is `0...outerRadius` (smaller is
    /// spikier). Recorded as a single SDF instance — analytic fill + stroke +
    /// anti-aliasing, crisp at any size. Rotate via the transform stack; rotation
    /// pivots on the center.
    func drawStar(_ x: Double, _ y: Double, _ outerRadius: Double, _ innerRadius: Double, points: Int) {
        guard outerRadius > 0, innerRadius > 0, innerRadius <= outerRadius, points >= 3 else { return }
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
        appendSDF(shape: .rhombus, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2), Float(height / 2)),
                  fill: fillColor, stroke: strokeColor, extra: Float(r))
    }

    /// A vesica (a pointed lens / two-circle intersection) centered at `(x, y)`,
    /// `width` by `height`; the tips lie along the longer axis. `cornerRadius`
    /// rounds the tips (and slightly enlarges the lens, like `drawMoon`).
    /// Recorded as a single SDF instance. Rotate via the transform stack.
    func drawVesica(_ x: Double, _ y: Double, _ width: Double, _ height: Double, cornerRadius: Double = 0) {
        guard width > 0, height > 0 else { return }
        let horizontal = width > height
        let a = (horizontal ? width : height) / 2     // half-length toward the tips
        let w = max((horizontal ? height : width) / 2, 1e-4)   // waist half-width
        let rr = max(0, cornerRadius)
        // Map the (along, across) half-extents to iq's circle radius + center
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
                  fill: fillColor, stroke: strokeColor, extra: Float(rr),
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
        appendSDF(shape: .moon, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(outerRadius + rr), Float(outerRadius + rr)),
                  fill: fillColor, stroke: strokeColor, extra: Float(rr),
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
        appendSDF(shape: .cross, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(armHalfLength), Float(armHalfLength)),
                  fill: fillColor, stroke: strokeColor, extra: Float(r),
                  param0: SIMD2<Float>(Float(armHalfWidth), 0))
    }

    /// A filled ring (annulus) centered at `(x, y)` between `innerRadius` and
    /// `outerRadius`. Takes the current `fill` (not stroke); for two outlined
    /// circles instead, draw `drawCircle` twice with `noFill`. Recorded as a single
    /// SDF instance.
    func drawRing(_ x: Double, _ y: Double, _ innerRadius: Double, _ outerRadius: Double) {
        guard outerRadius > 0, innerRadius >= 0, innerRadius < outerRadius else { return }
        let mid = (outerRadius + innerRadius) / 2
        let half = (outerRadius - innerRadius) / 2
        appendSDF(shape: .ring, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(outerRadius), Float(outerRadius)),
                  fill: fillColor, stroke: nil,
                  param0: SIMD2<Float>(Float(mid), Float(half)))
    }

    /// An isosceles trapezoid centered at `(x, y)`, `topWidth` across the top edge
    /// and `bottomWidth` across the bottom, `height` tall. A rectangle when the two
    /// widths match, a triangle when one is `0`. Recorded as a single SDF instance —
    /// analytic fill + stroke + anti-aliasing. Rotate via the transform stack.
    func drawTrapezoid(_ x: Double, _ y: Double, _ topWidth: Double, _ bottomWidth: Double, _ height: Double) {
        guard height > 0, topWidth >= 0, bottomWidth >= 0, topWidth + bottomWidth > 0 else { return }
        let halfMax = max(topWidth, bottomWidth) / 2
        appendSDF(shape: .trapezoid, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(halfMax), Float(height / 2)),
                  fill: fillColor, stroke: strokeColor,
                  param0: SIMD2<Float>(Float(topWidth / 2), Float(bottomWidth / 2)))
    }

    /// A parallelogram centered at `(x, y)`, `width` wide and `height` tall, with the
    /// top edge sheared `skew` points along +x relative to the bottom (`0` is a
    /// rectangle). Recorded as a single SDF instance. Rotate via the transform stack.
    func drawParallelogram(_ x: Double, _ y: Double, _ width: Double, _ height: Double, _ skew: Double) {
        guard width > 0, height > 0 else { return }
        appendSDF(shape: .parallelogram, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2 + abs(skew)), Float(height / 2)),
                  fill: fillColor, stroke: strokeColor, extra: Float(skew),
                  param0: SIMD2<Float>(Float(width / 2), 0))
    }

    /// An egg centered at `(x, y)`: a circle of `bottomRadius` at the fat lower end
    /// tapering to a rounded tip of `topRadius` at the top, pointing up.
    /// `bottomRadius` must be ≥ `topRadius` (equal is a circle). Recorded as a single
    /// SDF instance. Rotate via the transform stack.
    func drawEgg(_ x: Double, _ y: Double, _ bottomRadius: Double, _ topRadius: Double) {
        guard bottomRadius > 0, topRadius > 0, topRadius <= bottomRadius else { return }
        // Native span is y in [-bottomRadius, apex]; the fragment recenters on the
        // quad, so size.y carries the symmetric half-height around that center.
        let apex = 1.7320508075688772 * (bottomRadius - topRadius) + topRadius
        let halfHeight = (apex + bottomRadius) / 2
        appendSDF(shape: .egg, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(bottomRadius), Float(halfHeight)),
                  fill: fillColor, stroke: strokeColor,
                  param0: SIMD2<Float>(Float(bottomRadius), Float(topRadius)))
    }

    /// A heart centered at `(x, y)`, `size` points wide (a touch shorter than wide),
    /// lobes up and point down. Recorded as a single SDF instance. Rotate via the
    /// transform stack (45° spins it like a playing-card suit, 180° points it up).
    func drawHeart(_ x: Double, _ y: Double, _ size: Double) {
        guard size > 0 else { return }
        // The unit heart spans width 1.2036, height 1.0985 (lobes up); scale so the
        // width matches `size`. The fragment flips Y and recenters.
        let s = size / 1.2036
        appendSDF(shape: .heart, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(0.6018 * s), Float(0.54925 * s)),
                  fill: fillColor, stroke: strokeColor,
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
        appendSDF(shape: .cutDisk, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(radius), Float(radius)),
                  fill: fillColor, stroke: strokeColor,
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
        let dir = d / len
        let bound = len / 2 + max(ra, rb)
        appendSDF(shape: .unevenCapsule, center: (a + b) / 2,
                  size: SIMD2<Float>(Float(bound), Float(bound)),
                  fill: fillColor, stroke: strokeColor, extra: Float(len),
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
        // iq's `c` is the (cos, sin) of half the opening angle: the band then wraps
        // the remaining 2·(π − gap/2), so `gap` is the full angular opening.
        let an = min(max(gap / 2, 1e-3), Double.pi - 1e-3)
        let w = Float(thickness / 2)
        let bound = Float(radius + thickness)
        appendSDF(shape: .horseshoe, center: Vector2(x, y),
                  size: SIMD2<Float>(bound, bound),
                  fill: fillColor, stroke: strokeColor, extra: Float(radius),
                  param0: SIMD2<Float>(Float(cos(an)), Float(sin(an))),
                  param1: SIMD2<Float>(w, w))
    }

    /// A filled parabolic arch centered at `(x, y)`, `width` across the flat base
    /// and `height` tall, the curve peaking at the top (a parabola capping a
    /// straight base). Recorded as a single SDF instance — analytic fill + stroke +
    /// anti-aliasing. Rotate via the transform stack.
    func drawParabola(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        guard width > 0, height > 0 else { return }
        appendSDF(shape: .parabola, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2), Float(height / 2)),
                  fill: fillColor, stroke: strokeColor,
                  param0: SIMD2<Float>(Float(width / 2), Float(height)))
    }

    /// An X (saltire) centered at `(x, y)`, `length` tip-to-tip along each axis,
    /// drawn with round-capped arms `thickness` wide. Like `drawCross` rotated 45°
    /// but with rounded ends. Recorded as a single SDF instance — analytic fill +
    /// stroke + anti-aliasing. Rotate via the transform stack.
    func drawRoundedX(_ x: Double, _ y: Double, _ length: Double, _ thickness: Double) {
        guard length > 0, thickness > 0 else { return }
        let r = thickness / 2
        // The diagonal tips reach `w/2 + r/√2` per axis; invert to hit `length/2`.
        let w = max(length - thickness * 0.7071067811865476, 0)
        appendSDF(shape: .roundedX, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(length / 2 + r), Float(length / 2 + r)),
                  fill: fillColor, stroke: strokeColor, extra: Float(r),
                  param0: SIMD2<Float>(Float(w), 0))
    }

    /// A blobby cross centered at `(x, y)`: a four-armed cross with concave,
    /// inward-curving sides, its tips reaching `radius` along each axis.
    /// `blobbiness` (`0...1`, default `0.5`) sets how pinched the waist is — larger
    /// is more bulbous. Recorded as a single SDF instance. Rotate via the transform
    /// stack (45° gives a diagonal four-point pinwheel).
    func drawBlobbyCross(_ x: Double, _ y: Double, _ radius: Double, blobbiness: Double = 0.5) {
        guard radius > 0 else { return }
        let he = min(max(blobbiness, 0.3), 0.6)
        // The unit cross's tip lands at `tipUnit` along each axis; scale so it
        // reaches `radius`. (Larger `he` → shorter tips / fatter arms, so `tipUnit`
        // shrinks and the scale grows — the shape just gets blobbier at fixed reach.)
        let tipUnit = 1 / (he * 2.0.squareRoot()) - 1
        let s = radius / tipUnit
        appendSDF(shape: .blobbyCross, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(radius * 1.08), Float(radius * 1.08)),
                  fill: fillColor, stroke: strokeColor,
                  param0: SIMD2<Float>(Float(s), Float(he)))
    }

    /// A tunnel / archway centered at `(x, y)`: vertical walls and a flat base under
    /// a semicircular top, `width` wide and `height` tall overall (the arch radius is
    /// half the width, so `height` must be at least `width / 2`). Recorded as a
    /// single SDF instance. Rotate via the transform stack to aim the opening.
    func drawTunnel(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        guard width > 0, height >= width / 2 else { return }
        let whx = width / 2                 // half-width = arch radius
        let why = height - whx              // straight-wall height
        appendSDF(shape: .tunnel, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(width / 2), Float(height / 2)),
                  fill: fillColor, stroke: strokeColor,
                  param0: SIMD2<Float>(Float(whx), Float(why)))
    }

    /// A staircase centered at `(x, y)`: `steps` steps, each `stepWidth` wide and
    /// `stepHeight` tall, ascending to the right. The whole flight spans
    /// `stepWidth · steps` by `stepHeight · steps`. Recorded as a single SDF
    /// instance. Rotate via the transform stack.
    func drawStairs(_ x: Double, _ y: Double, _ stepWidth: Double, _ stepHeight: Double, steps: Int) {
        guard stepWidth > 0, stepHeight > 0, steps >= 1 else { return }
        let n = Double(steps)
        appendSDF(shape: .stairs, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(stepWidth * n / 2), Float(stepHeight * n / 2)),
                  fill: fillColor, stroke: strokeColor, extra: Float(steps),
                  param0: SIMD2<Float>(Float(stepWidth), Float(stepHeight)))
    }

    /// The iconic hand-drawn "S" centered at `(x, y)`, `size` points tall.
    /// Recorded as a single SDF instance — analytic fill + stroke + anti-aliasing.
    /// Rotate via the transform stack.
    func drawCoolS(_ x: Double, _ y: Double, _ size: Double) {
        guard size > 0 else { return }
        // The unit "S" spans about y in [-1.05, 1.05]; scale so `size` is its height.
        let s = size / 2.1
        appendSDF(shape: .coolS, center: Vector2(x, y),
                  size: SIMD2<Float>(Float(size / 2 + s * 0.1), Float(size / 2 + s * 0.1)),
                  fill: fillColor, stroke: strokeColor,
                  param0: SIMD2<Float>(Float(s), 0))
    }

    /// Shared builder for `drawNgon`/`drawStar`. Encodes the star into the SDF
    /// slots the way `sdStar` (in `Shaders.metal`) reads them: `size = (R, R)` (R is
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
                  fill: fillColor, stroke: strokeColor,
                  extra: Float(an), param0: acs, param1: ecs)
    }

    /// Record one analytic shape as an SDF instance, carrying the current
    /// transform plus the given fill, stroke, and shape-specific slots. A `nil`
    /// fill/stroke becomes a zero-alpha color the shader treats as "skip"; a
    /// caller passes explicit colors (e.g. a line passes its stroke as `fill`).
    /// No-op when there's nothing to draw.
    private func appendSDF(shape: SDFShape, center: Vector2, size: SIMD2<Float>,
                           fill: Color?, stroke: Color?, strokeWidth: Double? = nil,
                           extra: Float = 0,
                           param0: SIMD2<Float> = .zero, param1: SIMD2<Float> = .zero,
                           param2: SIMD2<Float> = .zero,
                           applyHollow: Bool = true) {
        let weight = strokeWidth ?? self.strokeWidth
        let hasStroke = stroke != nil && weight > 0
        guard fill != nil || hasStroke else { return }
        // Hollow mode applies only to region shapes the fragment can onion; the
        // round-dot point path shares the `.ellipse` tag, so it opts out here.
        let band = (applyHollow && shape.honorsHollow) ? Float(hollowWidth) : 0
        ensureBatch(.sdf)
        sdfInstances.append(SDFInstance(
            transform: transform,
            center: center.simd2,
            size: size,
            fillColor: fill?.simd4 ?? SIMD4<Float>(repeating: 0),
            strokeColor: hasStroke ? stroke!.simd4 : SIMD4<Float>(repeating: 0),
            param0: param0,
            param1: param1,
            param2: param2,
            strokeWidth: hasStroke ? Float(weight) : 0,
            extra: extra,
            bandWidth: band,
            // Stroke alignment rides in the shape tag's high bits (the tag itself
            // is < 256), so it costs no room in the instance.
            shape: shape.rawValue | (strokeAlignment.shaderCode << 8)))
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

        if abs(rx - ry) < 1e-6, abs(sweep) < Double.tau - 1e-4 {
            appendArcSDF(center: Vector2(x, y), radius: rx, start: start, stop: stop, mode: mode)
            return
        }

        // Sample the arc, scaling the segment count to the swept fraction so a
        // short arc stays cheap and a near-full one stays smooth.
        let full = circleSegments(for: max(rx, ry))
        let segments = max(2, Int((Double(full) * abs(sweep) / (2.0 * .pi)).rounded(.up)))
        var pts: [Vector2] = []
        pts.reserveCapacity(segments + 1)
        for i in 0...segments {
            let a = start + sweep * (Double(i) / Double(segments))
            pts.append(Vector2(x + cos(a) * rx, y + sin(a) * ry))
        }
        let center = Vector2(x, y)

        if let fill = fillColor {
            let c = fill.simd4
            switch mode {
            case .open, .chord:
                // Circular segment — convex, so a fan from the first point fills it.
                let p0 = pts[0].simd2
                for i in 1..<(pts.count - 1) {
                    emit(p0, color: c)
                    emit(pts[i].simd2, color: c)
                    emit(pts[i + 1].simd2, color: c)
                }
            case .pie:
                // Wedge — fan from the center.
                let cc = center.simd2
                for i in 0..<(pts.count - 1) {
                    emit(cc, color: c)
                    emit(pts[i].simd2, color: c)
                    emit(pts[i + 1].simd2, color: c)
                }
            }
        }

        if let stroke = strokeColor, strokeWidth > 0 {
            let c = stroke.simd4
            let half = strokeWidth / 2
            for i in 1..<pts.count {
                appendSegment(from: pts[i - 1], to: pts[i], half: half, color: c)
            }
            switch mode {
            case .open:
                break
            case .chord:
                appendSegment(from: pts[pts.count - 1], to: pts[0], half: half, color: c)
            case .pie:
                appendSegment(from: center, to: pts[0], half: half, color: c)
                appendSegment(from: pts[pts.count - 1], to: center, half: half, color: c)
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
                  fill: fillColor, stroke: strokeColor,
                  param0: SIMD2<Float>(Float(sin(halfAperture)), Float(cos(halfAperture))),
                  param1: SIMD2<Float>(Float(cos(phi)), Float(sin(phi))))
    }

    /// A connected open path through `points`, stroked with the current stroke
    /// color and weight.
    ///
    /// Open (the last point is not joined back to the first) and stroke-only —
    /// fills belong to closed shapes (`drawShape`). Corners turn per `strokeJoin`
    /// (mitered by default, so fat strokes stay clean at sharp turns) and the ends
    /// finish per `strokeCap` (butt by default). Needs at least two points and a
    /// stroke to draw anything.
    func drawPolyline(_ points: [Vector2]) {
        guard points.count >= 2, let stroke = strokeColor, strokeWidth > 0 else { return }
        appendStrokedPath(points, closed: false, half: strokeWidth / 2, color: stroke.simd4)
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
        appendSDF(shape: .box, center: rect.center,
                  size: SIMD2<Float>(Float(rect.width / 2), Float(rect.height / 2)),
                  fill: fillColor, stroke: strokeColor, extra: Float(r))
    }

    // MARK: Text

    /// Draw `string` at `(x, y)` using the active `textFont` / `textSize` /
    /// `textAlign`. `\n` starts a new line; text rides the transform stack and
    /// stays crisp at any size. A **bitmap** font stamps each lit pixel as a fill
    /// color square on the SDF path; an **outline** font draws each glyph as a
    /// vector `Shape`, so — like every other shape — it takes the current `fill`
    /// *and* an active `stroke` (call `noStroke()` for plain filled text, or
    /// `noFill()` for outline-only text). Unknown characters advance the pen but
    /// draw nothing.
    func drawText(_ string: String, _ x: Double, _ y: Double) {
        guard textPixelSize > 0, !string.isEmpty else { return }
        switch currentFont {
        case .bitmap(let font):  drawBitmapText(string, x, y, font: font)
        case .outline(let font): drawOutlineText(string, x, y, font: font)
        }
    }

    /// Bitmap path: one fill color square per lit pixel (see `forEachBitmapPixel`).
    private func drawBitmapText(_ string: String, _ x: Double, _ y: Double, font: BitmapFont) {
        guard let fill = fillColor else { return }
        forEachBitmapPixel(string, x, y, font: font) { center, module in
            let half = SIMD2<Float>(Float(module / 2), Float(module / 2))
            // Fill-only square; opt out of hollow so a set band doesn't turn each
            // pixel into a ring.
            appendSDF(shape: .box, center: center, size: half,
                      fill: fill, stroke: nil, applyHollow: false)
        }
    }

    /// Outline path: each glyph is a vector `Shape`, drawn through `drawShape` so
    /// it fills, strokes, and composites exactly like any other shape.
    private func drawOutlineText(_ string: String, _ x: Double, _ y: Double, font: OutlineFont) {
        guard fillColor != nil || (strokeColor != nil && strokeWidth > 0) else { return }
        for shape in font.glyphShapes(for: string, size: textPixelSize,
                                      alignH: textAlignH, alignV: textAlignV, at: Vector2(x, y)) {
            drawShape(shape)
        }
    }

    /// Walk the lit pixels of `string`, laid out with the active text state,
    /// calling `body` with each pixel's center (canvas space) and module size (its
    /// on-screen side). Shared by `drawBitmapText` and `textToShapes` so the
    /// bitmap layout lives in one place.
    private func forEachBitmapPixel(_ string: String, _ x: Double, _ y: Double,
                                    font: BitmapFont, _ body: (Vector2, Double) -> Void) {
        guard font.pixelHeight > 0 else { return }
        let module = textPixelSize / Double(font.pixelHeight)
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false)
        let blockHeight = Double((lines.count - 1) * font.lineHeight + font.pixelHeight) * module

        // First line's top edge, from the vertical anchor.
        let topY0: Double
        switch textAlignV {
        case .top:      topY0 = y
        case .baseline: topY0 = y - Double(font.baseline) * module
        case .middle:   topY0 = y - blockHeight / 2
        case .bottom:   topY0 = y - blockHeight
        }

        for (lineIndex, line) in lines.enumerated() {
            let lineTop = topY0 + Double(lineIndex * font.lineHeight) * module
            let lineWidth = Double(font.inkWidth(of: String(line))) * module
            // Left edge of this line, from the horizontal anchor.
            var penX: Double
            switch textAlignH {
            case .left:   penX = x
            case .center: penX = x - lineWidth / 2
            case .right:  penX = x - lineWidth
            }

            var previous: Character? = nil
            for ch in line {
                if let prev = previous { penX += Double(font.kerning(between: prev, ch)) * module }
                if let glyph = font.glyph(for: ch) {
                    let cellLeft = penX + Double(glyph.xOffset) * module
                    let cellTop = lineTop + Double(glyph.yOffset) * module
                    for row in 0..<glyph.height {
                        for col in 0..<glyph.width where glyph.isSet(col, row) {
                            let cx = cellLeft + (Double(col) + 0.5) * module
                            let cy = cellTop + (Double(row) + 0.5) * module
                            body(Vector2(cx, cy), module)
                        }
                    }
                }
                penX += Double(font.advance(for: ch)) * module
                previous = ch
            }
        }
    }

    /// The glyph geometry of `string` as `Shape`s positioned at `(x, y)` with the
    /// active `textFont` / `textSize` / `textAlign` — text as first-class geometry
    /// you can fill, stroke, warp, sample, or animate. An **outline** font returns
    /// one `Shape` per glyph (a letter with a counter keeps its hole); a **bitmap**
    /// font returns its lit pixels as little squares.
    func textToShapes(_ string: String, _ x: Double, _ y: Double) -> [Shape] {
        guard textPixelSize > 0, !string.isEmpty else { return [] }
        switch currentFont {
        case .outline(let font):
            return font.glyphShapes(for: string, size: textPixelSize,
                                    alignH: textAlignH, alignV: textAlignV, at: Vector2(x, y))
        case .bitmap(let font):
            var squares: [Contour] = []
            forEachBitmapPixel(string, x, y, font: font) { center, module in
                let h = module / 2
                squares.append(Contour([
                    Vector2(center.x - h, center.y - h), Vector2(center.x + h, center.y - h),
                    Vector2(center.x + h, center.y + h), Vector2(center.x - h, center.y + h),
                ], closed: true))
            }
            return squares.isEmpty ? [] : [Shape(contours: squares)]
        }
    }

    /// The on-screen width of `string`'s widest line, in points, at the active
    /// `textFont` / `textSize` — for laying text out.
    func textWidth(_ string: String) -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            let module = textPixelSize / Double(font.pixelHeight)
            return Double(font.inkWidth(of: string)) * module
        case .outline(let font):
            return font.width(of: string, size: textPixelSize)
        }
    }

    /// Distance from the baseline up to the top of the tallest glyphs, in points,
    /// at the active font and size.
    func textAscent() -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            return Double(font.baseline) * (textPixelSize / Double(font.pixelHeight))
        case .outline(let font):
            return font.ascent * textPixelSize
        }
    }

    /// Distance from the baseline down to the bottom of the lowest descenders, in
    /// points, at the active font and size.
    func textDescent() -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            let module = textPixelSize / Double(font.pixelHeight)
            return Double(font.pixelHeight - font.baseline) * module
        case .outline(let font):
            return font.descent * textPixelSize
        }
    }

    /// The baseline-to-baseline distance for a new line, in points, at the active
    /// font and size (what `\n` advances by).
    func textLeading() -> Double {
        switch currentFont {
        case .bitmap(let font):
            guard font.pixelHeight > 0 else { return 0 }
            return Double(font.lineHeight) * (textPixelSize / Double(font.pixelHeight))
        case .outline(let font):
            return (font.ascent + font.descent + font.leading) * textPixelSize
        }
    }

    /// The bounding box `string` occupies if drawn at `(x, y)` with the active text
    /// state — width is the widest line, height spans the whole block.
    func textBounds(_ string: String, _ x: Double, _ y: Double) -> Rectangle {
        let w = textWidth(string)
        let ascent = textAscent(), descent = textDescent(), advance = textLeading()
        let lineCount = string.split(separator: "\n", omittingEmptySubsequences: false).count
        let blockHeight = Double(max(0, lineCount - 1)) * advance + ascent + descent
        let top: Double
        switch textAlignV {
        case .top:      top = y
        case .baseline: top = y - ascent
        case .middle:   top = y - blockHeight / 2
        case .bottom:   top = y - blockHeight
        }
        let left: Double
        switch textAlignH {
        case .left:   left = x
        case .center: left = x - w / 2
        case .right:  left = x - w
        }
        return Rectangle(x: left, y: top, width: w, height: blockHeight)
    }

    /// A straight line segment from `a` to `b`, stroked with the current stroke
    /// color and weight. Recorded as a single capsule SDF instance — the segment
    /// fattened to `strokeWeight` with round caps — so it's crisp at any size and
    /// effectively free per line. Needs a stroke to draw.
    func drawLine(_ a: Vector2, _ b: Vector2) {
        guard let stroke = strokeColor, strokeWidth > 0 else { return }
        let halfWidth = strokeWidth / 2
        let center = (a + b) / 2
        let e = (b - a) / 2   // half-segment vector, relative to the center
        // AABB half-extent: the segment's reach plus the cap radius on each axis.
        let bound = SIMD2<Float>(Float(abs(e.x) + halfWidth), Float(abs(e.y) + halfWidth))
        appendSDF(shape: .capsule, center: center, size: bound,
                  fill: stroke, stroke: nil,
                  extra: Float(halfWidth), param0: e.simd2)
    }

    /// A quadratic Bézier curve stroked with the current stroke color and weight:
    /// from `start` to `end`, bending toward the single control point `control`.
    /// Recorded as one SDF instance — the exact distance to the curve, fattened to
    /// `strokeWeight` with round caps — so it's crisp at any size and effectively
    /// free, with no tessellation. Stroke-only: a curve has no interior, so it takes
    /// the current stroke (not fill). For a cubic curve (two control points), sample
    /// it into a `Shape` contour. Needs a stroke to draw.
    func drawBezier(_ start: Vector2, _ control: Vector2, _ end: Vector2) {
        guard let stroke = strokeColor, strokeWidth > 0 else { return }
        let halfWidth = strokeWidth / 2
        // The curve stays within the convex hull of its control points, so their
        // AABB (grown by the stroke half-width) bounds the stroked curve — the same
        // size-folds-in-the-cap trick `drawLine` uses for the capsule.
        let lo = Vector2(min(start.x, min(control.x, end.x)), min(start.y, min(control.y, end.y)))
        let hi = Vector2(max(start.x, max(control.x, end.x)), max(start.y, max(control.y, end.y)))
        let center = (lo + hi) / 2
        let half = (hi - lo) / 2
        appendSDF(shape: .bezier, center: center,
                  size: SIMD2<Float>(Float(half.x + halfWidth), Float(half.y + halfWidth)),
                  fill: stroke, stroke: nil, extra: Float(halfWidth),
                  param0: (start - center).simd2, param1: (control - center).simd2,
                  param2: (end - center).simd2)
    }

    /// A quadratic Bézier curve through scalar coordinates — the positional form of
    /// `drawBezier(_:_:_:)`: `(x1, y1)` start, `(cx, cy)` control, `(x2, y2)` end.
    func drawBezier(_ x1: Double, _ y1: Double, _ cx: Double, _ cy: Double,
                    _ x2: Double, _ y2: Double) {
        drawBezier(Vector2(x1, y1), Vector2(cx, cy), Vector2(x2, y2))
    }

    /// A filled, **convex** polygon through `points` (triangle fan), plus a
    /// stroked closed outline if a stroke is set. The fan only fills correctly
    /// for convex inputs (triangles, quads, regular n-gons, convex pieces); for
    /// concave outlines or holes, build a `Shape` and use `drawShape`, which
    /// triangulates properly.
    func drawPolygon(_ points: [Vector2]) {
        guard points.count >= 3 else { return }
        if let fill = fillColor {
            let c = fill.simd4
            let p0 = points[0].simd2
            for i in 1..<(points.count - 1) {        // fan from the first vertex
                emit(p0, color: c)
                emit(points[i].simd2, color: c)
                emit(points[i + 1].simd2, color: c)
            }
        }
        if let stroke = strokeColor, strokeWidth > 0 {
            appendStrokedPath(points, closed: true, half: strokeWidth / 2, color: stroke.simd4)
        }
    }

    /// A vector `Shape`: a filled region that may be **concave** and may have
    /// **holes**, plus a stroked outline of each contour. The fill is
    /// triangulated (even-odd winding, so nested contours cut holes); open
    /// contours are stroke-only. Both fill and stroke go through the triangle
    /// path, so a `Shape` composites in draw order with everything else.
    func drawShape(_ shape: Shape) {
        if let fill = fillColor {
            let c = fill.simd4
            let triangles = shape.triangulatedFill()
            for i in stride(from: 0, to: triangles.count - 2, by: 3) {
                emit(triangles[i].simd2, color: c)
                emit(triangles[i + 1].simd2, color: c)
                emit(triangles[i + 2].simd2, color: c)
            }
        }
        if let stroke = strokeColor, strokeWidth > 0 {
            let c = stroke.simd4
            let half = strokeWidth / 2
            for contour in shape.contours where contour.points.count >= 2 {
                appendStrokedPath(contour.points, closed: contour.isClosed, half: half, color: c)
            }
        }
    }

    // MARK: Tessellation helpers

    /// Append one tessellated vertex, transformed by the current CTM. Every
    /// triangle primitive funnels through here, so the transform applies
    /// uniformly and the vertex joins the current triangle batch.
    private func emit(_ position: SIMD2<Float>, color: SIMD4<Float>) {
        ensureBatch(.triangles)
        guard !transformIsIdentity else {
            vertices.append(OllinVertex(position: position, color: color))
            return
        }
        let p = transform * SIMD3<Float>(position.x, position.y, 1)
        vertices.append(OllinVertex(position: SIMD2<Float>(p.x, p.y), color: color))
    }

    /// Pick a vertex count that keeps each edge segment ≲ 8 points long, so big
    /// circles stay smooth and small ones stay cheap. With 4× MSAA smoothing the
    /// edges, an 8-point chord is visually indistinguishable from a finer one at
    /// these sizes, for roughly half the tessellated vertices.
    private func circleSegments(for radius: Double) -> Int {
        let targetEdgeLength = 8.0
        let circumference = 2.0 * .pi * radius
        return max(24, Int((circumference / targetEdgeLength).rounded(.up)))
    }

    /// One straight stroke segment as a rectangle (two triangles) of width
    /// `2 * half`, offset perpendicular to the segment direction.
    private func appendSegment(from a: Vector2, to b: Vector2,
                               half: Double, color: SIMD4<Float>) {
        let d = b - a
        let len = d.length
        guard len > 0 else { return }   // skip zero-length (repeated) points
        // Perpendicular to the segment, scaled to the half-width.
        let n = Vector2(-d.y, d.x) / len * half
        let a0 = (a + n).simd2
        let a1 = (a - n).simd2
        let b0 = (b + n).simd2
        let b1 = (b - n).simd2
        // Quad (a0, b0, b1, a1) -> two triangles.
        emit(a0, color: color)
        emit(b0, color: color)
        emit(b1, color: color)
        emit(a0, color: color)
        emit(b1, color: color)
        emit(a1, color: color)
    }

    /// Stroke a polyline or closed contour as butt segment quads plus a join
    /// filler at each shared vertex, so corners close cleanly instead of leaving
    /// the gap two independent butt ends make. The join style (`strokeJoin`)
    /// decides each corner: `.miter` extends the outer edges to a point (bevel
    /// past `miterLimit` so an acute corner doesn't spike), `.bevel` always cuts
    /// it flat, `.round` fills it with an arc. Open paths finish their ends with
    /// the cap style (`strokeCap`); closed ones join every vertex and have no
    /// ends. The inner side of a turn is already covered by the overlapping
    /// segment quads, so only the outer gap is filled.
    private func appendStrokedPath(_ points: [Vector2], closed: Bool,
                                   half: Double, color: SIMD4<Float>) {
        guard half > 0 else { return }
        // Drop repeated points; a zero-length segment has no direction.
        var pts: [Vector2] = []
        for p in points where (pts.last.map { ($0 - p).length > 1e-9 } ?? true) {
            pts.append(p)
        }
        if closed, pts.count > 1, (pts[0] - pts[pts.count - 1]).length <= 1e-9 {
            pts.removeLast()
        }
        let n = pts.count
        guard n >= 2 else { return }

        let segments = closed ? n : n - 1
        for i in 0..<segments {
            appendSegment(from: pts[i], to: pts[(i + 1) % n], half: half, color: color)
        }

        let miterLimit = 8.0
        let joins = closed ? Array(0..<n) : Array(1..<(n - 1))
        for v in joins {
            let curr = pts[v]
            let d0v = curr - pts[(v - 1 + n) % n]
            let d1v = pts[(v + 1) % n] - curr
            let l0 = d0v.length, l1 = d1v.length
            guard l0 > 1e-9, l1 > 1e-9 else { continue }
            let d0 = d0v / l0, d1 = d1v / l1
            let n0 = Vector2(-d0.y, d0.x)   // unit left normals
            let n1 = Vector2(-d1.y, d1.x)
            let cross = d0.x * d1.y - d0.y * d1.x
            guard abs(cross) > 1e-6 else { continue }   // collinear: no gap to fill
            // Fill on the outer side of the turn (where the two quads diverge).
            let side: Double = cross >= 0 ? -1 : 1
            let cornerA = curr + n0 * (side * half)
            let cornerB = curr + n1 * (side * half)
            switch strokeJoinStyle {
            case .round:
                // Arc the outer gap from one corner to the other about `curr`,
                // sweeping the short (minor) way between them.
                let va = cornerA - curr, vb = cornerB - curr
                let startAngle = atan2(va.y, va.x)
                let sweep = atan2(va.x * vb.y - va.y * vb.x, va.x * vb.x + va.y * vb.y)
                appendArcFan(center: curr, radius: half,
                             startAngle: startAngle, sweep: sweep, color: color)
            case .bevel:
                emit(curr.simd2, color: color); emit(cornerA.simd2, color: color); emit(cornerB.simd2, color: color)
            case .miter:
                let bisector = n0 + n1
                let bisectorLength = bisector.length
                let cosHalf = bisectorLength > 1e-6 ? (bisector.x * n0.x + bisector.y * n0.y) / bisectorLength : 0
                if cosHalf > 1e-4, 1 / cosHalf <= miterLimit {
                    let miter = (curr + bisector / bisectorLength * (side * half / cosHalf)).simd2
                    emit(curr.simd2, color: color); emit(cornerA.simd2, color: color); emit(miter, color: color)
                    emit(curr.simd2, color: color); emit(miter, color: color); emit(cornerB.simd2, color: color)
                } else {
                    emit(curr.simd2, color: color); emit(cornerA.simd2, color: color); emit(cornerB.simd2, color: color)
                }
            }
        }

        // Cap the two open ends (closed paths have none). The cap direction points
        // outward — away from the path — along the end segment.
        guard !closed else { return }
        let dStart = pts[1] - pts[0]
        if dStart.length > 1e-9 {
            appendCap(at: pts[0], outward: dStart / dStart.length * -1, half: half, color: color)
        }
        let dEnd = pts[n - 1] - pts[n - 2]
        if dEnd.length > 1e-9 {
            appendCap(at: pts[n - 1], outward: dEnd / dEnd.length, half: half, color: color)
        }
    }

    /// Finish one open end of a stroked path per `strokeCap`. `outward` is the
    /// unit direction pointing away from the path; `.butt` adds nothing, `.round`
    /// caps with a half-disk, `.square` extends a flat quad `half` past the end.
    private func appendCap(at point: Vector2, outward: Vector2,
                           half: Double, color: SIMD4<Float>) {
        let perp = Vector2(-outward.y, outward.x)   // unit, across the stroke
        switch strokeCapStyle {
        case .butt:
            return
        case .round:
            // Half-disk: a π sweep from one edge to the other, bulging outward.
            // `perp` is 90° from `outward`, so sweeping −π routes through it.
            appendArcFan(center: point, radius: half,
                         startAngle: atan2(perp.y, perp.x), sweep: -.pi, color: color)
        case .square:
            let n = perp * half
            let ext = outward * half
            let a0 = (point + n).simd2
            let a1 = (point - n).simd2
            let b0 = (point + n + ext).simd2
            let b1 = (point - n + ext).simd2
            emit(a0, color: color); emit(b0, color: color); emit(b1, color: color)
            emit(a0, color: color); emit(b1, color: color); emit(a1, color: color)
        }
    }

    /// Triangle-fan an arc of `radius` about `center`, starting at `startAngle`
    /// and sweeping `sweep` radians (signed). The step count scales with the arc
    /// length, so round joins and caps stay smooth without over-tessellating.
    private func appendArcFan(center: Vector2, radius: Double,
                              startAngle: Double, sweep: Double, color: SIMD4<Float>) {
        guard radius > 0, abs(sweep) > 1e-6 else { return }
        let full = Double(circleSegments(for: radius))
        let steps = max(1, Int((abs(sweep) / (2 * .pi) * full).rounded(.up)))
        let c = center.simd2
        var prev = SIMD2<Float>(Float(center.x + cos(startAngle) * radius),
                                Float(center.y + sin(startAngle) * radius))
        for i in 1...steps {
            let a = startAngle + sweep * Double(i) / Double(steps)
            let curr = SIMD2<Float>(Float(center.x + cos(a) * radius),
                                    Float(center.y + sin(a) * radius))
            emit(c, color: color); emit(prev, color: color); emit(curr, color: color)
            prev = curr
        }
    }

    // MARK: Affine matrix builders (column-major, 2D homogeneous)

    private static func translation(_ tx: Float, _ ty: Float) -> matrix_float3x3 {
        matrix_float3x3(columns: (SIMD3<Float>(1, 0, 0),
                                  SIMD3<Float>(0, 1, 0),
                                  SIMD3<Float>(tx, ty, 1)))
    }
    private static func rotation(_ a: Float) -> matrix_float3x3 {
        let c = cos(a), s = sin(a)
        return matrix_float3x3(columns: (SIMD3<Float>(c, s, 0),
                                         SIMD3<Float>(-s, c, 0),
                                         SIMD3<Float>(0, 0, 1)))
    }
    private static func scaling(_ sx: Float, _ sy: Float) -> matrix_float3x3 {
        matrix_float3x3(columns: (SIMD3<Float>(sx, 0, 0),
                                  SIMD3<Float>(0, sy, 0),
                                  SIMD3<Float>(0, 0, 1)))
    }
}

extension Color {
    /// GPU vertex-color representation.
    var simd4: SIMD4<Float> {
        SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha))
    }
}

extension Vector2 {
    /// GPU-boundary representation: components narrowed to `Float`. Mirrors
    /// `Color.simd4`; the renderer's vertices are `SIMD2<Float>` positions.
    var simd2: SIMD2<Float> {
        SIMD2<Float>(Float(x), Float(y))
    }
}
