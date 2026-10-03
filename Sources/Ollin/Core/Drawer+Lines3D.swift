// Drawer, lines through the 3D camera: a polyline of world points is projected
// onto the canvas, expanded there by the stroke expander every 2D stroke goes
// through (so its joins, caps, and anti-aliasing fringe are the 2D stroke's), and
// recorded with the world point each vertex was laid out around, which is what
// gives every vertex its depth when the renderer projects it again.

import Foundation
import simd
import COllinShaders
import OllinExpander

extension Drawer {

    /// One point of a line in 3D on its way to the expander: where it is in the
    /// world (the model matrix applied), where the camera puts it, and its color.
    private struct LinePoint {
        var world: SIMD3<Double>
        var clip: SIMD4<Double>
        var color: SIMD4<Float>

        /// The point a fraction `t` of the way to `other`. Clip space is linear in
        /// the world point, so one fraction serves both, and the color follows.
        func lerp(_ other: LinePoint, _ t: Double) -> LinePoint {
            LinePoint(world: world + (other.world - world) * t,
                      clip: clip + (other.clip - clip) * t,
                      color: color + (other.color - color) * Float(t))
        }
    }

    /// Every line vertex recorded this frame, core and fringe: the length of
    /// the buffer they upload into.
    var lineVertexCount: Int { lineCoreVertices.count + lineFringeVertices.count }

    /// How far inside the near plane a cut is placed, as a share of the cut
    /// point's clip w, so the cut end never lands on the plane the rasterizer
    /// clips at.
    private static let nearMargin = 1e-6

    /// Stroke `points` through the active camera: a polyline, or a closed loop
    /// with `closed`. `colors`, when it has one color per point, colors the line
    /// point by point and replaces the stroke paint; otherwise the stroke paint
    /// colors it. `canvas` is the canvas size in points, the viewport the main
    /// pass projects into (a layer projects into its own size instead).
    func drawPolyline3D(_ points: [Vector3], colors: [Color]? = nil, closed: Bool,
                        canvas: SIMD2<Float>) {
        guard points.count >= 2, let stroke = strokePaint, strokeWidth > 0 else { return }
        if isRecordingBatch {
            noteBatchRecording("lines with 3D points inside makeBatch { } are not recorded (a recording has no camera to project them through); draw them where the batch is drawn.")
            return
        }
        guard let camera = camera3D else {
            noteOnce("drawLine and drawPolyline with 3D points draw through the 3D camera, and this frame has none yet; set one with camera(_:), perspective, or ortho before drawing them.")
            return
        }
        if let spatialRecorder { spatialRecorder.skip("a line with 3D points"); return }
        var perPoint = colors
        if let given = colors, given.count != points.count {
            noteOnce("drawPolyline(_:colors:) takes one color per point (got \(given.count) for \(points.count) points); drawing the line in the stroke color.")
            perPoint = nil
        }
        if strokeDashPattern != nil || strokeBrushShape != nil
            || !strokeProfileShape.isUniform {
            noteOnce("strokeDash, strokeBrush, and strokeProfile shape 2D strokes; a line with 3D points draws whole, at one weight.")
        }

        let viewport = currentTarget.map { SIMD2<Float>(Float($0.width), Float($0.height)) } ?? canvas
        guard viewport.x > 0, viewport.y > 0 else { return }
        let aspect = Double(viewport.x / viewport.y)
        let projection = camera.projectionMatrix(aspect: aspect)
        let viewProjection = SIMD4x4(projection * camera.viewMatrix)

        // The paint for each point, read where the point lands on the canvas, or
        // by its distance along the line for an along-path gradient.
        let paint = perPoint == nil ? vertexPaint(stroke, anchor: Vector2(Double(viewport.x) / 2,
                                                                          Double(viewport.y) / 2)) : nil
        let model = modelMatrix
        let identity = modelIsIdentity
        var line: [LinePoint] = []
        line.reserveCapacity(points.count)
        for (k, p) in points.enumerated() {
            let w = identity ? p : model.transforming(p)
            let world = SIMD3<Double>(w.x, w.y, w.z)
            let clip = viewProjection * SIMD4<Double>(world, 1)
            line.append(LinePoint(world: world, clip: clip, color: perPoint?[k].simd4 ?? .zero))
        }

        // Cut what lies behind the near plane away, which can split the line into
        // several runs. A closed loop that crosses the plane is opened at a point
        // behind it first, so its pieces come out in order with nothing to rejoin.
        let runs = Drawer.nearClipped(line, closed: closed)

        let worldWidth = strokeUnitsMode == .world
        let widthScale = worldWidth ? (identity ? 1 : Double(Drawer.averageScale(model))) : 1
        // Canvas points per world unit at view distance 1, read off the projection's
        // vertical scale (the horizontal one agrees once the aspect is divided out).
        let pointsPerUnit = Double(projection.columns.1.y) * Double(viewport.y) / 2

        for run in runs {
            var screen: [Vector2] = []
            var kept: [LinePoint] = []
            screen.reserveCapacity(run.points.count)
            for point in run.points {
                let s = Vector2((point.clip.x / point.clip.w + 1) / 2 * Double(viewport.x),
                                (1 - point.clip.y / point.clip.w) / 2 * Double(viewport.y))
                // Two points the camera stacks on one spot leave a segment with no
                // direction on the canvas; the expander wants it gone.
                if let last = screen.last, (s - last).length <= 1e-9 { continue }
                screen.append(s)
                kept.append(point)
            }
            var isClosed = run.closed
            if isClosed, screen.count > 1, (screen[0] - screen[screen.count - 1]).length <= 1e-9 {
                screen.removeLast()
                kept.removeLast()
            }
            if screen.count < 2 { continue }
            if screen.count < 3 { isClosed = false }

            let halfWidths: [Double] = kept.map { point in
                worldWidth ? strokeWidth / 2 * widthScale * pointsPerUnit / max(point.clip.w, 1e-9)
                           : strokeWidth / 2
            }
            var cols = kept.map(\.color)
            if let paint {
                // Distance along the line in the world, for an along-path gradient.
                var along = [Double](repeating: 0, count: kept.count)
                for i in 1..<kept.count {
                    along[i] = along[i - 1] + simd_length(kept[i].world - kept[i - 1].world)
                }
                var total = along[kept.count - 1]
                if isClosed { total += simd_length(kept[0].world - kept[kept.count - 1].world) }
                for i in kept.indices {
                    cols[i] = paint.color(at: screen[i], pathT: total > 0 ? along[i] / total : 0)
                }
            }
            if svgRecorder != nil {
                recordProjectedLine(screen, closed: isClosed, halfWidths: halfWidths)
                continue
            }
            appendLine3D(screen: screen, points: kept.map(\.world), colors: cols,
                         halfWidths: halfWidths, closed: isClosed)
        }
    }

    /// A projected run into the vector export, as the 2D polyline the camera
    /// made of it: a file has no depth, so nothing hides it, and one weight, so a
    /// line measured in world units takes the mean of its projected widths. The
    /// 2D transform and the dash, brush, and profile are held off for the record,
    /// so the file draws what the screen does.
    private func recordProjectedLine(_ screen: [Vector2], closed: Bool, halfWidths: [Double]) {
        let saved = (transform, transformIsIdentity, strokeWidth,
                     strokeDashPattern, strokeBrushShape, strokeProfileShape)
        defer {
            (transform, transformIsIdentity, strokeWidth,
             strokeDashPattern, strokeBrushShape, strokeProfileShape) = saved
        }
        transform = matrix_identity_float3x3
        transformIsIdentity = true
        strokeWidth = 2 * halfWidths.reduce(0, +) / Double(halfWidths.count)
        strokeDashPattern = nil
        strokeBrushShape = nil
        strokeProfileShape = .uniform
        svgRecord(closed ? .polygon(screen) : .polyline(screen), fill: nil, stroke: strokePaint)
    }

    /// Expand one projected run and record its triangles, each vertex holding
    /// the world point it was laid out around and its offset from that point on
    /// the canvas. A triangle whose three corners are fully covered joins the
    /// core, which writes depth; the rest join the fringe, which only tests it.
    private func appendLine3D(screen: [Vector2], points: [SIMD3<Double>], colors: [SIMD4<Float>],
                              halfWidths: [Double], closed: Bool) {
        currentTarget?.needsDepth = true   // 3D in a target → that pass carries depth
        let before = batches.count
        ensureBatch(.lines3D)
        if batches.last?.kind != .lines3D {
            // A batch kind that opened without telling `ensureBatch`: start fresh.
            currentKind = nil
            ensureBatch(.lines3D)
        }
        let index = batches.count - 1
        if batches.count > before {
            batches[index].lineCoreStart = lineCoreVertices.count
            batches[index].lineFringeStart = lineFringeVertices.count
        }
        let join: StrokeExpanderJoin
        switch strokeJoinStyle {
        case .miter: join = .miter
        case .bevel: join = .bevel
        case .round: join = .round
        }
        let cap: StrokeExpanderCap
        switch strokeCapStyle {
        case .butt: cap = .butt
        case .square: cap = .square
        case .round: cap = .round
        }
        let anchors = screen.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
        let worlds = points.map { SIMD4<Float>(Float($0.x), Float($0.y), Float($0.z), 1) }
        var triangle: [OllinLineVertex] = []
        triangle.reserveCapacity(3)
        var coreAdded = 0, fringeAdded = 0
        StrokeExpander.expand(screen.map { Point2D($0.x, $0.y) }, closed: closed,
                              halfWidths: halfWidths, colors: colors, fringe: 1, ctmScale: 1,
                              join: join, cap: cap) { vertex, source in
            triangle.append(OllinLineVertex(position: worlds[source],
                                            offset: vertex.position - anchors[source],
                                            coverage: vertex.coverage, _pad0: 0,
                                            color: vertex.color))
            guard triangle.count == 3 else { return }
            if triangle.allSatisfy({ $0.coverage >= 1 }) {
                lineCoreVertices.append(contentsOf: triangle)
                coreAdded += 3
            } else {
                lineFringeVertices.append(contentsOf: triangle)
                fringeAdded += 3
            }
            triangle.removeAll(keepingCapacity: true)
        }
        batches[index].lineCoreCount += coreAdded
        batches[index].lineFringeCount += fringeAdded
    }

    /// `line` with everything behind the camera's near plane cut away, as runs
    /// in order. Clip space is linear along a segment, so a crossing is found by
    /// the fraction where clip z reaches the plane (Metal's depth runs 0 at the
    /// near plane to 1 at the far one, in units of w).
    private static func nearClipped(_ line: [LinePoint], closed: Bool) -> [(points: [LinePoint], closed: Bool)] {
        func inside(_ p: LinePoint) -> Double { p.clip.z - nearMargin * abs(p.clip.w) }
        guard line.contains(where: { inside($0) < 0 }) else { return [(line, closed)] }
        var path = line
        if closed, let behind = line.firstIndex(where: { inside($0) < 0 }) {
            // Start at a point behind the plane and walk the whole loop back to it.
            path = Array(line[behind...]) + Array(line[...behind])
        }
        var runs: [(points: [LinePoint], closed: Bool)] = []
        var current: [LinePoint] = []
        if inside(path[0]) >= 0 { current.append(path[0]) }
        for i in 1..<path.count {
            let a = path[i - 1], b = path[i]
            let fa = inside(a), fb = inside(b)
            if fa >= 0, fb >= 0 {
                current.append(b)
            } else if fa >= 0 {
                current.append(a.lerp(b, fa / (fa - fb)))
                runs.append((current, false))
                current = []
            } else if fb >= 0 {
                current = [a.lerp(b, fa / (fa - fb)), b]
            }
        }
        if current.count >= 2 { runs.append((current, false)) }
        return runs.filter { $0.points.count >= 2 }
    }
}

/// A double-precision copy of a camera matrix, so a point far from the origin
/// projects without the error single precision would add to its offset.
private struct SIMD4x4 {
    var columns: (SIMD4<Double>, SIMD4<Double>, SIMD4<Double>, SIMD4<Double>)
    init(_ m: simd_float4x4) {
        columns = (SIMD4<Double>(m.columns.0), SIMD4<Double>(m.columns.1),
                   SIMD4<Double>(m.columns.2), SIMD4<Double>(m.columns.3))
    }
    static func * (m: SIMD4x4, v: SIMD4<Double>) -> SIMD4<Double> {
        m.columns.0 * v.x + m.columns.1 * v.y + m.columns.2 * v.z + m.columns.3 * v.w
    }
}

extension Drawer {

    /// The axis colors, the hues the live window's ground grid marks its axes in.
    static let axisColors: [Color] = [Color(red: 0.80, green: 0.30, blue: 0.32),
                                      Color(red: 0.38, green: 0.70, blue: 0.34),
                                      Color(red: 0.30, green: 0.50, blue: 0.85)]

    /// The three axes from the model origin, each `length` long in its own color.
    func drawAxes(length: Double, canvas: SIMD2<Float>) {
        let ends = [Vector3(length, 0, 0), Vector3(0, length, 0), Vector3(0, 0, length)]
        for (end, color) in zip(ends, Drawer.axisColors) {
            drawPolyline3D([.zero, end], colors: [color, color], closed: false, canvas: canvas)
        }
    }

    /// A grid of `divisions` cells a side, `size` across, on the plane y = 0
    /// around the model origin: `divisions + 1` lines each way.
    func drawGrid(size: Double, divisions: Int, canvas: SIMD2<Float>) {
        guard divisions > 0, size > 0 else { return }
        let half = size / 2
        for i in 0...divisions {
            let t = -half + size * Double(i) / Double(divisions)
            drawPolyline3D([Vector3(t, 0, -half), Vector3(t, 0, half)], closed: false, canvas: canvas)
            drawPolyline3D([Vector3(-half, 0, t), Vector3(half, 0, t)], closed: false, canvas: canvas)
        }
    }
}
