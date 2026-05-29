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

/// One circle/ellipse, drawn as a single instanced quad whose fragment computes
/// fill + stroke + anti-aliasing from a signed-distance field — no CPU
/// tessellation. The renderer draws a whole batch of these in one
/// `drawPrimitives(instanceCount:)`.
///
/// The memory layout must match `SDFInstance` in `Shaders.metal` (stride 112):
/// a `float3x3` (48 bytes, three 16-byte columns) followed by the rest under
/// simd alignment. Keep them in sync if you add fields.
struct SDFInstance {
    var transform: matrix_float3x3   // local sketch space -> sketch space (the CTM)
    var center: SIMD2<Float>
    var radii: SIMD2<Float>          // (rx, ry); circle is rx == ry
    var fillColor: SIMD4<Float>      // straight RGBA; alpha 0 = no fill
    var strokeColor: SIMD4<Float>    // straight RGBA; alpha 0 = no stroke
    var strokeWidth: Float           // points; 0 = no stroke
}

/// Which pipeline a run of recorded geometry needs. Primitives are recorded in
/// call order; a `Batch` starts wherever the kind changes, so SDF shapes and
/// tessellated triangles still composite front-to-back in the order the sketch
/// drew them (a later shape paints over an earlier one).
enum GeometryKind {
    case triangles   // tessellated fills/strokes in `vertices`
    case sdf         // instanced circles/ellipses in `sdfInstances`
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

    // MARK: Per-frame geometry (reset every frame)

    private(set) var vertices: [OllinVertex] = []

    /// Instanced circles/ellipses recorded this frame (see `SDFInstance`).
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
    /// Recorded as a single SDF instance, not tessellated: the fragment shader
    /// computes fill, stroke (width `strokeWeight`), and anti-aliasing
    /// analytically. Crisp at any size and effectively free per circle, which is
    /// what makes thousands of them cheap.
    func drawCircle(_ x: Double, _ y: Double, _ radius: Double) {
        guard radius > 0 else { return }
        appendSDF(center: Vector2(x, y), rx: radius, ry: radius)
    }

    /// An axis-aligned ellipse centered at `(x, y)` with horizontal radius `rx`
    /// and vertical radius `ry` (points). Like `drawCircle`, the arguments are
    /// *radii*, not diameters — `drawEllipse(x, y, r, r)` is a circle.
    ///
    /// Recorded as a single SDF instance (see `drawCircle`); fill and a
    /// uniform-width stroke are derived analytically in the fragment shader.
    func drawEllipse(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
        guard rx > 0, ry > 0 else { return }
        appendSDF(center: Vector2(x, y), rx: rx, ry: ry)
    }

    /// Record one circle/ellipse as an SDF instance, carrying the current fill,
    /// stroke, and transform. A `nil` fill/stroke becomes a zero-alpha color the
    /// shader treats as "skip". No-op when there's nothing to draw.
    private func appendSDF(center: Vector2, rx: Double, ry: Double) {
        let hasStroke = strokeColor != nil && strokeWidth > 0
        guard fillColor != nil || hasStroke else { return }
        ensureBatch(.sdf)
        sdfInstances.append(SDFInstance(
            transform: transform,
            center: center.simd2,
            radii: SIMD2<Float>(Float(rx), Float(ry)),
            fillColor: fillColor?.simd4 ?? SIMD4<Float>(repeating: 0),
            strokeColor: hasStroke ? strokeColor!.simd4 : SIMD4<Float>(repeating: 0),
            strokeWidth: hasStroke ? Float(strokeWidth) : 0))
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
