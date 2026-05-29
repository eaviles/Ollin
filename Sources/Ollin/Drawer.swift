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
}

/// One analytic shape, drawn as a single instanced quad whose fragment computes
/// fill + stroke + anti-aliasing from a signed-distance field — no CPU
/// tessellation. The renderer draws a whole batch of these in one
/// `drawPrimitives(instanceCount:)`.
///
/// A tagged union: `shape` picks the SDF and decides how the generic slots
/// (`size`, `param0`, `param1`, `extra`) are read — see `SDFShape`.
///
/// The memory layout must match `SDFInstance` in `Shaders.metal` (stride 128):
/// a `float3x3` (48 bytes, three 16-byte columns) followed by the rest under
/// simd alignment. Keep them in sync if you add fields.
struct SDFInstance {
    var transform: matrix_float3x3   // local sketch space -> sketch space (the CTM)
    var center: SIMD2<Float>         // shape center, local sketch space
    var size: SIMD2<Float>           // generic half-extent (see SDFShape)
    var fillColor: SIMD4<Float>      // straight RGBA; alpha 0 = no fill
    var strokeColor: SIMD4<Float>    // straight RGBA; alpha 0 = no stroke
    var param0: SIMD2<Float>         // shape-specific (capsule half-segment / arc sin,cos)
    var param1: SIMD2<Float>         // shape-specific (arc rotation cos,sin)
    var strokeWidth: Float           // points; 0 = no stroke
    var extra: Float                 // shape-specific scalar (box corner radius / capsule half-width)
    var shape: UInt32                // SDFShape.rawValue
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

    /// Record one analytic shape as an SDF instance, carrying the current
    /// transform plus the given fill, stroke, and shape-specific slots. A `nil`
    /// fill/stroke becomes a zero-alpha color the shader treats as "skip"; a
    /// caller passes explicit colors (e.g. a line passes its stroke as `fill`).
    /// No-op when there's nothing to draw.
    private func appendSDF(shape: SDFShape, center: Vector2, size: SIMD2<Float>,
                           fill: Color?, stroke: Color?, strokeWidth: Double? = nil,
                           extra: Float = 0,
                           param0: SIMD2<Float> = .zero, param1: SIMD2<Float> = .zero) {
        let weight = strokeWidth ?? self.strokeWidth
        let hasStroke = stroke != nil && weight > 0
        guard fill != nil || hasStroke else { return }
        ensureBatch(.sdf)
        sdfInstances.append(SDFInstance(
            transform: transform,
            center: center.simd2,
            size: size,
            fillColor: fill?.simd4 ?? SIMD4<Float>(repeating: 0),
            strokeColor: hasStroke ? stroke!.simd4 : SIMD4<Float>(repeating: 0),
            param0: param0,
            param1: param1,
            strokeWidth: hasStroke ? Float(weight) : 0,
            extra: extra,
            shape: shape.rawValue))
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
            let c = stroke.simd4
            let half = strokeWidth / 2
            for k in 0..<points.count {
                appendSegment(from: points[k], to: points[(k + 1) % points.count], half: half, color: c)
            }
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
                let pts = contour.points
                for k in 1..<pts.count {
                    appendSegment(from: pts[k - 1], to: pts[k], half: half, color: c)
                }
                if contour.isClosed {
                    appendSegment(from: pts[pts.count - 1], to: pts[0], half: half, color: c)
                }
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
