import Foundation
import simd

/// One vertex of stroked/filled geometry, as consumed by the Metal pipeline.
///
/// The memory layout of this struct must match `Vertex` in `Shaders.metal`:
///   - `position` (float2) at offset 0
///   - `color`    (float4) at offset 16 (float4 has 16-byte alignment)
/// Both sides therefore have a stride of 32 bytes. Keep them in sync if you
/// add fields.
struct OllinVertex {
    var position: SIMD2<Float>   // sketch-space, points, top-left origin, y-down
    var color: SIMD4<Float>      // straight (non-premultiplied) RGBA, 0...1
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

    // MARK: Per-frame geometry (reset every frame)

    private(set) var vertices: [OllinVertex] = []

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
    }

    // MARK: State setters (mirrors the bare API on `Sketch`)

    /// Set the background/clear color. This also wipes anything drawn
    /// so far this frame (background paints over everything).
    func background(_ color: Color) {
        backgroundColor = color
        vertices.removeAll(keepingCapacity: true)
    }

    func fill(_ color: Color) { fillColor = color }
    func noFill() { fillColor = nil }
    func stroke(_ color: Color) { strokeColor = color }
    func noStroke() { strokeColor = nil }
    func strokeWeight(_ weight: Double) { strokeWidth = max(0, weight) }

    // MARK: Frame lifecycle

    /// Drop last frame's geometry but keep drawing state. Called once per frame
    /// by the runner before `Sketch.draw()`.
    func beginFrame() {
        vertices.removeAll(keepingCapacity: true)
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
                                     fillColor: fillColor, strokeColor: strokeColor, strokeWidth: strokeWidth))
    }

    /// Restore the most recently pushed transform and style. No-op if unbalanced.
    func popState() {
        guard let s = stateStack.popLast() else { return }
        transform = s.transform
        transformIsIdentity = s.transformIsIdentity
        fillColor = s.fillColor
        strokeColor = s.strokeColor
        strokeWidth = s.strokeWidth
    }

    // MARK: Primitives

    /// A circle centered at `(x, y)` with the given `radius` (points).
    ///
    /// If a fill is set, the disk is emitted as a triangle fan. If a stroke is
    /// set, the outline is emitted as a triangle-strip annulus (a ring of width
    /// `strokeWeight`). Both go through the same solid-color pipeline; the
    /// MTKView's 4× MSAA gives us the anti-aliased edge for free.
    func drawCircle(_ x: Double, _ y: Double, _ radius: Double) {
        guard radius > 0 else { return }
        let segments = circleSegments(for: radius)
        if let fill = fillColor {
            appendDisk(cx: x, cy: y, radius: radius, segments: segments, color: fill)
        }
        if let stroke = strokeColor, strokeWidth > 0 {
            appendRing(cx: x, cy: y, radius: radius, weight: strokeWidth,
                       segments: segments, color: stroke)
        }
    }

    /// An axis-aligned ellipse centered at `(x, y)` with horizontal radius `rx`
    /// and vertical radius `ry` (points). Like `drawCircle`, the arguments are
    /// *radii*, not diameters — `drawEllipse(x, y, r, r)` is a circle.
    ///
    /// A fill is emitted as a triangle fan; a stroke as a uniform-width outline
    /// whose offset follows the ellipse's true normal (so the ring keeps an even
    /// thickness even when squashed), both through the solid-color pipeline.
    func drawEllipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
        guard rx > 0, ry > 0 else { return }
        let segments = circleSegments(for: max(rx, ry))
        if let fill = fillColor {
            appendEllipseDisk(cx: x, cy: y, rx: rx, ry: ry, segments: segments, color: fill)
        }
        if let stroke = strokeColor, strokeWidth > 0 {
            appendEllipseRing(cx: x, cy: y, rx: rx, ry: ry, weight: strokeWidth,
                              segments: segments, color: stroke)
        }
    }

    /// An elliptical arc centered at `(x, y)` with radii `rx`/`ry`, sweeping from
    /// `start` to `stop` (radians, clockwise). `mode` decides how the ends close:
    /// `.open` leaves the curve open, `.chord` joins them with a straight line,
    /// `.pie` joins them through the center. A fill paints the enclosed region
    /// (segment for open/chord, wedge for pie); a stroke traces the outline.
    func drawArc(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double,
                 start: Double, stop: Double, mode: ArcMode) {
        guard rx > 0, ry > 0 else { return }
        let sweep = stop - start
        guard abs(sweep) > 1e-9 else { return }

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

    /// A connected open path through `points`, stroked with the current stroke
    /// color and weight.
    ///
    /// Open (the last point is not joined back to the first) and stroke-only —
    /// fills belong to closed shapes (a future `Shape`/`Contour`). Segments are
    /// butt-jointed, so at the default thin weights the joins look seamless;
    /// fat strokes will want real joins later. Needs at least two points and a
    /// stroke to draw anything.
    func drawPolyline(_ points: [Vector2]) {
        guard points.count >= 2, let stroke = strokeColor, strokeWidth > 0 else { return }
        let color = stroke.simd4
        let half = strokeWidth / 2
        for k in 1..<points.count {
            appendSegment(from: points[k - 1], to: points[k], half: half, color: color)
        }
    }

    /// An axis-aligned `Rectangle`. Filled as two triangles if a fill is set;
    /// the outline is stroked as a mitered frame of width `strokeWeight`
    /// straddling the edges, if a stroke is set. Both feed the same solid-color
    /// pipeline, so the MTKView's 4× MSAA gives the anti-aliased edge.
    func drawRect(_ rect: Rectangle) {
        guard rect.width > 0, rect.height > 0 else { return }
        if let fill = fillColor {
            appendQuad(rect.topLeft.simd2, rect.topRight.simd2,
                       rect.bottomRight.simd2, rect.bottomLeft.simd2, color: fill.simd4)
        }
        if let stroke = strokeColor, strokeWidth > 0 {
            appendRectFrame(rect, weight: strokeWidth, color: stroke.simd4)
        }
    }

    /// A straight line segment from `a` to `b`, stroked with the current stroke
    /// color and weight. A single-segment `polyline`; needs a stroke to draw.
    func drawLine(_ a: Vector2, _ b: Vector2) {
        guard let stroke = strokeColor, strokeWidth > 0 else { return }
        appendSegment(from: a, to: b, half: strokeWidth / 2, color: stroke.simd4)
    }

    /// A filled, **convex** polygon through `points` (triangle fan), plus a
    /// stroked closed outline if a stroke is set. Concave shapes render wrong
    /// until a real `Shape`/triangulator arrives (see CLAUDE.md) — keep inputs
    /// convex (triangles, quads, regular n-gons, or convex pieces of a shape).
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
            let c = stroke.simd4
            let half = strokeWidth / 2
            for k in 0..<points.count {
                appendSegment(from: points[k], to: points[(k + 1) % points.count], half: half, color: c)
            }
        }
    }

    // MARK: Tessellation helpers

    /// Append one tessellated vertex, shifted by the current translation. Every
    /// primitive funnels through here, so the transform applies uniformly.
    private func emit(_ position: SIMD2<Float>, color: SIMD4<Float>) {
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

    private func point(cx: Double, cy: Double, radius: Double, angle: Double) -> SIMD2<Float> {
        SIMD2<Float>(Float(cx + cos(angle) * radius),
                     Float(cy + sin(angle) * radius))
    }

    private func ellipsePoint(cx: Double, cy: Double, rx: Double, ry: Double, angle: Double) -> SIMD2<Float> {
        SIMD2<Float>(Float(cx + cos(angle) * rx),
                     Float(cy + sin(angle) * ry))
    }

    /// Filled disk as a triangle fan, expanded into explicit triangles so the
    /// whole frame can be one `.triangle` draw call.
    private func appendDisk(cx: Double, cy: Double, radius: Double,
                            segments: Int, color: Color) {
        let c = color.simd4
        let center = SIMD2<Float>(Float(cx), Float(cy))
        for i in 0..<segments {
            let a0 = Double(i)     / Double(segments) * 2.0 * .pi
            let a1 = Double(i + 1) / Double(segments) * 2.0 * .pi
            let p0 = point(cx: cx, cy: cy, radius: radius, angle: a0)
            let p1 = point(cx: cx, cy: cy, radius: radius, angle: a1)
            emit(center, color: c)
            emit(p0, color: c)
            emit(p1, color: c)
        }
    }

    /// Stroked outline as an annulus (ring) between an inner and outer radius,
    /// expanded into triangles. The stroke straddles the geometric radius.
    private func appendRing(cx: Double, cy: Double, radius: Double, weight: Double,
                            segments: Int, color: Color) {
        let c = color.simd4
        let inner = max(0, radius - weight / 2)
        let outer = radius + weight / 2
        for i in 0..<segments {
            let a0 = Double(i)     / Double(segments) * 2.0 * .pi
            let a1 = Double(i + 1) / Double(segments) * 2.0 * .pi
            let i0 = point(cx: cx, cy: cy, radius: inner, angle: a0)
            let o0 = point(cx: cx, cy: cy, radius: outer, angle: a0)
            let i1 = point(cx: cx, cy: cy, radius: inner, angle: a1)
            let o1 = point(cx: cx, cy: cy, radius: outer, angle: a1)
            // Quad (i0, o0, o1, i1) -> two triangles.
            emit(i0, color: c)
            emit(o0, color: c)
            emit(o1, color: c)
            emit(i0, color: c)
            emit(o1, color: c)
            emit(i1, color: c)
        }
    }

    /// Filled ellipse as a triangle fan, expanded into explicit triangles. Same
    /// shape as `appendDisk` with separate horizontal/vertical radii.
    private func appendEllipseDisk(cx: Double, cy: Double, rx: Double, ry: Double,
                                   segments: Int, color: Color) {
        let c = color.simd4
        let center = SIMD2<Float>(Float(cx), Float(cy))
        for i in 0..<segments {
            let a0 = Double(i)     / Double(segments) * 2.0 * .pi
            let a1 = Double(i + 1) / Double(segments) * 2.0 * .pi
            let p0 = ellipsePoint(cx: cx, cy: cy, rx: rx, ry: ry, angle: a0)
            let p1 = ellipsePoint(cx: cx, cy: cy, rx: rx, ry: ry, angle: a1)
            emit(center, color: c)
            emit(p0, color: c)
            emit(p1, color: c)
        }
    }

    /// Stroked ellipse outline as a triangle strip between an inner and outer
    /// boundary. Unlike a circle's radial offset, each boundary point is pushed
    /// along the ellipse's outward normal `(ry·cosθ, rx·sinθ)`, so the stroke
    /// keeps a uniform width instead of bunching at the flatter ends.
    private func appendEllipseRing(cx: Double, cy: Double, rx: Double, ry: Double,
                                   weight: Double, segments: Int, color: Color) {
        let c = color.simd4
        let half = weight / 2

        func boundary(_ a: Double) -> (inner: SIMD2<Float>, outer: SIMD2<Float>) {
            let px = cx + cos(a) * rx
            let py = cy + sin(a) * ry
            var nx = cos(a) * ry
            var ny = sin(a) * rx
            let len = (nx * nx + ny * ny).squareRoot()
            if len > 0 { nx /= len; ny /= len }
            let inner = SIMD2<Float>(Float(px - nx * half), Float(py - ny * half))
            let outer = SIMD2<Float>(Float(px + nx * half), Float(py + ny * half))
            return (inner, outer)
        }

        for i in 0..<segments {
            let a0 = Double(i)     / Double(segments) * 2.0 * .pi
            let a1 = Double(i + 1) / Double(segments) * 2.0 * .pi
            let (i0, o0) = boundary(a0)
            let (i1, o1) = boundary(a1)
            // Quad (i0, o0, o1, i1) -> two triangles.
            emit(i0, color: c)
            emit(o0, color: c)
            emit(o1, color: c)
            emit(i0, color: c)
            emit(o1, color: c)
            emit(i1, color: c)
        }
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

    /// A quad with corners `a→b→c→d` (in order, either winding) as two triangles.
    private func appendQuad(_ a: SIMD2<Float>, _ b: SIMD2<Float>,
                            _ c: SIMD2<Float>, _ d: SIMD2<Float>, color: SIMD4<Float>) {
        emit(a, color: color)
        emit(b, color: color)
        emit(c, color: color)
        emit(a, color: color)
        emit(c, color: color)
        emit(d, color: color)
    }

    /// A rectangular outline as four bands between an outer rect (expanded by
    /// half the weight) and an inner rect (shrunk by half), giving clean mitered
    /// corners. If the stroke is thicker than the rect, the inner edges collapse
    /// to the center so the frame fills solid instead of inverting.
    private func appendRectFrame(_ r: Rectangle, weight: Double, color: SIMD4<Float>) {
        let half = weight / 2
        let oL = r.corner.x - half, oR = r.corner.x + r.width + half
        let oT = r.corner.y - half, oB = r.corner.y + r.height + half
        var iL = r.corner.x + half, iR = r.corner.x + r.width - half
        var iT = r.corner.y + half, iB = r.corner.y + r.height - half
        if iL > iR { iL = r.center.x; iR = r.center.x }
        if iT > iB { iT = r.center.y; iB = r.center.y }
        func v(_ x: Double, _ y: Double) -> SIMD2<Float> { SIMD2<Float>(Float(x), Float(y)) }
        appendQuad(v(oL, oT), v(oR, oT), v(oR, iT), v(oL, iT), color: color)  // top
        appendQuad(v(oL, iB), v(oR, iB), v(oR, oB), v(oL, oB), color: color)  // bottom
        appendQuad(v(oL, iT), v(iL, iT), v(iL, iB), v(oL, iB), color: color)  // left
        appendQuad(v(iR, iT), v(oR, iT), v(oR, iB), v(iR, iB), color: color)  // right
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
