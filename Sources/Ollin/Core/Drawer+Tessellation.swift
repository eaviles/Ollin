// Drawer, the tessellation half: the CPU triangle emitters behind the
// non-SDF paths (polygon fans, stroked-path expansion, the fringe builder,
// arc fans) and the affine / 3D model-matrix builders.

import Foundation
import simd
import COllinShaders

extension Drawer {
    // MARK: Tessellation helpers

    /// A paint resolved for CPU-side, per-vertex evaluation on the tessellated
    /// path. A solid paint returns its constant; a gradient samples its baked
    /// LUT row at the vertex position (linear/radial) or path parameter
    /// (along-path), so the tessellated path paints the same colors the SDF
    /// fragment derives analytically.
    enum VertexPaint {
        case solid(SIMD4<Float>)
        case linear(origin: Vector2, dir: Vector2, invLen2: Double, baked: BakedGradient)
        case radial(center: Vector2, invRadius: Double, baked: BakedGradient)
        /// Along-path paint: stroked paths pass their arc-length fraction; fills
        /// (no path parameter) sweep once around `center`, matching the SDF
        /// fragment's conic fallback.
        case along(center: Vector2, baked: BakedGradient)

        var isGradient: Bool {
            if case .solid = self { return false }
            return true
        }

        /// The paint color at a vertex position.
        func color(at p: Vector2) -> SIMD4<Float> {
            switch self {
            case .solid(let c):
                return c
            case .linear(let origin, let dir, let invLen2, let baked):
                return baked.sample(((p.x - origin.x) * dir.x + (p.y - origin.y) * dir.y) * invLen2)
            case .radial(let center, let invRadius, let baked):
                return baked.sample((p - center).length * invRadius)
            case .along(let center, let baked):
                // Conic sweep: 0 at 12 o'clock, increasing clockwise (y-down) —
                // the same wrap the SDF fragment computes.
                let raw = atan2(p.x - center.x, -(p.y - center.y)) / Double.tau
                return baked.sample(raw - raw.rounded(.down))
            }
        }

        /// The paint color for a stroked-path vertex: along-path paint reads the
        /// arc-length fraction `t`; the others read the position like a fill.
        func color(at p: Vector2, pathT t: Double) -> SIMD4<Float> {
            if case .along(_, let baked) = self { return baked.sample(t) }
            return color(at: p)
        }
    }

    /// Resolve `paint` for per-vertex evaluation. `anchor` is the center an
    /// along-path gradient sweeps around when the geometry has no path parameter
    /// (a fill's conic fallback); it's only evaluated in that case.
    func vertexPaint(_ paint: Paint, anchor: @autoclosure () -> Vector2) -> VertexPaint {
        switch paint {
        case .color(let c):
            return .solid(c.simd4)
        case .gradient(let g):
            let baked = gradientRow(for: g.ramp).baked
            switch g.geometry {
            case .linear(let start, let end):
                let d = end - start
                let len2 = max(d.x * d.x + d.y * d.y, 1e-12)
                return .linear(origin: start, dir: d, invLen2: 1 / len2, baked: baked)
            case .radial(let center, let radius):
                return .radial(center: center, invRadius: 1 / max(radius, 1e-6), baked: baked)
            case .alongPath:
                return .along(center: anchor(), baked: baked)
            }
        }
    }

    /// The center of `points`' bounding box — the conic anchor for an
    /// along-path fill on tessellated geometry.
    static func boundsCenter(_ points: [Vector2]) -> Vector2 {
        guard let first = points.first else { return .zero }
        var lo = first, hi = first
        for p in points.dropFirst() {
            lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
            hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
        }
        return (lo + hi) / 2
    }

    /// Append one tessellated vertex, transformed by the current CTM. Every
    /// triangle primitive funnels through here, so the transform applies
    /// uniformly and the vertex joins the current triangle batch. `aa` is left
    /// zero — the triangle pipeline ignores it (only the fringe pipeline reads it).
    func emit(_ position: SIMD2<Float>, color: SIMD4<Float>) {
        ensureBatch(.triangles)
        guard !transformIsIdentity else {
            vertices.append(OllinVertex(position: position, color: color))
            return
        }
        let p = transform * SIMD3<Float>(position.x, position.y, 1)
        vertices.append(OllinVertex(position: SIMD2<Float>(p.x, p.y), color: color))
    }

    /// The current CTM's average linear scale (canvas units → post-transform units),
    /// used to keep the AA fringe ~1px on screen regardless of zoom: a fringe of
    /// `1/ctmScale` local units becomes ~1px after the transform. Exact for
    /// uniform scale + rotation (the common case); approximate under non-uniform
    /// scale/skew (documented limitation).
    private var ctmScale: Double {
        guard !transformIsIdentity else { return 1 }
        let c0 = transform.columns.0, c1 = transform.columns.1
        let sx = (c0.x * c0.x + c0.y * c0.y).squareRoot()
        let sy = (c1.x * c1.x + c1.y * c1.y).squareRoot()
        return max(Double(sx + sy) / 2, 1e-6)
    }

    /// Append one fringe-stroke vertex (CTM-transformed) into `vertices` under a
    /// `.fringe` batch. The AA coverage rides in `aa.x` (its own interpolant the
    /// fringe fragment remaps to perceptual alpha), while `color` carries the
    /// stroke's rgb and its own paint alpha — the two kept separate so a translucent
    /// stroke composites at its true opacity.
    private func emitFringe(_ position: SIMD2<Float>, cov: Float, color: SIMD4<Float>) {
        ensureBatch(.fringe)
        let aa = SIMD2<Float>(cov, 0)
        if transformIsIdentity {
            vertices.append(OllinVertex(position: position, aa: aa, color: color))
        } else {
            let p = transform * SIMD3<Float>(position.x, position.y, 1)
            vertices.append(OllinVertex(position: SIMD2<Float>(p.x, p.y), aa: aa, color: color))
        }
    }

    /// Stroke a polyline (or closed loop) as edge-expanded triangles plus a
    /// screen-space ~1px anti-aliasing fringe — the technique behind the smooth
    /// `drawLine`/`drawBezier`/polyline lines (no SDF/fwidth, no supersampling: the
    /// AA is carried in the geometry). Each segment is its own butt-ended quad with
    /// a fringe band on each long edge whose coverage ramps 1→0, GPU-interpolated so
    /// the edge stays smooth at any angle. The fringe straddles the true edge so
    /// perceived width = `strokeWidth`, and is ~1px in screen space (`fw = 1/ctmScale`).
    /// Interior vertices fill the outer gap per `strokeJoin` (`.miter` — bevelling past
    /// the miter limit — / `.bevel` / `.round`); the inner side is covered by the
    /// segments' overlap. Open ends take the `strokeCap` style.
    ///
    /// The whole stroke path runs through here — solid, translucent, and gradient. The
    /// paint is sampled per path vertex (`cols[i]`) exactly like the tessellated path
    /// (along-path reads the arc-length fraction, the rest read position) and rides in
    /// each vertex's `color` (rgb + paint alpha), constant across the stroke width; a
    /// gradient first splits long segments so the baked LUT is tracked. The AA coverage
    /// rides separately in `aa.x`, so the fragment can keep the paint alpha linear while
    /// remapping only the coverage perceptually.
    func appendFringeStroke(_ points: [Vector2], closed: Bool, paint: VertexPaint) {
        // Emits only fringe vertices into one `.fringe` batch, so symmetry can
        // replicate the whole expansion as a range copy (see `replicated`).
        replicated { appendFringeStrokeSingle(points, closed: closed, paint: paint) }
    }

    private func appendFringeStrokeSingle(_ points: [Vector2], closed: Bool, paint: VertexPaint) {
        // Drop repeated points (a zero-length segment has no direction) and a
        // closed loop's closing duplicate, so every join is well-defined.
        var pts: [Vector2] = []
        for p in points where (pts.last.map { ($0 - p).length > 1e-9 } ?? true) { pts.append(p) }
        if closed, pts.count > 1, (pts[0] - pts[pts.count - 1]).length <= 1e-9 { pts.removeLast() }
        // A gradient varies along the run, so split long segments first (like the
        // tessellated path) — the per-vertex color samples the baked LUT densely
        // instead of interpolating straight through its stops. Solid strokes are
        // untouched, so their geometry is unchanged.
        if paint.isGradient { pts = Drawer.subdivided(pts, closed: closed, maxLength: 12) }
        let n = pts.count
        guard n >= 2 else { return }

        let hw = strokeWidth / 2
        let fw = 1.0 / ctmScale                 // ~1px AA fringe in screen space
        let outerHalf = hw + fw / 2
        let coreHalf = max(0, hw - fw / 2)
        let miterLimit = 8.0

        // Per-vertex paint color (rgb + the paint's own alpha). Along-path reads the
        // arc-length fraction; the rest read the position — matching the tessellated
        // path. Constant across the stroke width (a stroke's gradient runs along it).
        var cols = [SIMD4<Float>](repeating: .zero, count: n)
        if case .solid(let c) = paint {
            for i in 0..<n { cols[i] = c }
        } else {
            var cum = [Double](repeating: 0, count: n)
            for i in 1..<n { cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).length }
            var total = cum[n - 1]
            if closed { total += (pts[0] - pts[n - 1]).length }
            for i in 0..<n {
                cols[i] = paint.color(at: pts[i], pathT: total > 0 ? cum[i] / total : 0)
            }
        }

        // Coverage vs. distance from the centerline: 1 in the solid core, ramping to
        // 0 across the outer fringe (and < 1 at the center for a sub-pixel stroke, so
        // thin lines fade by width instead of snapping to a 1px floor).
        func covU(_ off: Double) -> Float { Float(min(max((outerHalf - abs(off)) / fw, 0), 1)) }
        let offs = [outerHalf, coreHalf, -coreHalf, -outerHalf]
        let centerCov = covU(0), coreCov = covU(coreHalf)

        func segDir(_ a: Vector2, _ b: Vector2) -> Vector2 {
            let d = b - a; let l = d.length
            return l > 1e-9 ? d / l : Vector2(1, 0)
        }
        func leftNormal(_ d: Vector2) -> Vector2 { Vector2(-d.y, d.x) }

        // A fringe vertex: position, AA coverage, and the path color at this point.
        typealias FV = (SIMD2<Float>, Float, SIMD4<Float>)
        func tri(_ a: FV, _ b: FV, _ d: FV) {
            emitFringe(a.0, cov: a.1, color: a.2)
            emitFringe(b.0, cov: b.1, color: b.2)
            emitFringe(d.0, cov: d.1, color: d.2)
        }
        func quad(_ a: FV, _ b: FV, _ d: FV, _ e: FV) { tri(a, b, d); tri(a, d, e) }
        // A cross-section at `p` along `perp` in path vertex `i`'s color, coverage
        // scaled by `s` (1 on the line, 0 at a length-fringe tip so butt/square ends
        // fade out across the fringe).
        func crossAt(_ p: Vector2, _ perp: Vector2, _ s: Float, _ col: SIMD4<Float>) -> [FV] {
            offs.map { ((p + perp * $0).simd2, covU($0) * s, col) }
        }
        // Connect two cross-sections into 3 quad bands (outer-fringe | core | outer-fringe).
        func ribbon(_ a: [FV], _ b: [FV]) { for k in 0..<3 { quad(a[k], b[k], b[k + 1], a[k + 1]) } }

        // Body: each segment is its own butt-ended fringe quad along its perpendicular,
        // its two ends carrying their path vertices' colors (the GPU interpolates).
        let segCount = closed ? n : n - 1
        for i in 0..<segCount {
            let j = (i + 1) % n
            let perp = leftNormal(segDir(pts[i], pts[j]))
            ribbon(crossAt(pts[i], perp, 1, cols[i]), crossAt(pts[j], perp, 1, cols[j]))
        }

        // Interior joins: fill the outer gap between the two segment quads at each
        // shared vertex (the inner side is covered by their overlap). The join style
        // honors `strokeJoin`; `.miter` bevels past the miter limit so an acute corner
        // doesn't spike. The whole join takes the corner vertex's color.
        let joins = closed ? Array(0..<n) : Array(1..<(n - 1))
        for v in joins {
            let prev = pts[(v - 1 + n) % n], curr = pts[v], next = pts[(v + 1) % n]
            let d0 = segDir(prev, curr), d1 = segDir(curr, next)
            let cross = d0.x * d1.y - d0.y * d1.x
            guard abs(cross) > 1e-6 else { continue }       // collinear: no gap to fill
            let p0 = leftNormal(d0), p1 = leftNormal(d1)
            let side: Double = cross >= 0 ? -1 : 1          // outer side of the turn
            let col = cols[v]
            let center:  FV = (curr.simd2, centerCov, col)
            let inCore:  FV = ((curr + p0 * (side * coreHalf)).simd2, coreCov, col)
            let inEdge:  FV = ((curr + p0 * (side * outerHalf)).simd2, 0, col)
            let outCore: FV = ((curr + p1 * (side * coreHalf)).simd2, coreCov, col)
            let outEdge: FV = ((curr + p1 * (side * outerHalf)).simd2, 0, col)
            func bevel() {
                tri(center, inCore, outCore)                // inner core wedge
                quad(inCore, inEdge, outEdge, outCore)      // fringe band across the bevel
            }
            func miter() -> Bool {
                let b = p0 + p1, bl = b.length
                let cosHalf = bl > 1e-6 ? (b.x * p0.x + b.y * p0.y) / bl : 0
                guard cosHalf > 1e-4, 1 / cosHalf <= miterLimit else { return false }
                let m = b / bl                              // unit bisector of the normals
                let miterCore: FV = ((curr + m * (side * coreHalf / cosHalf)).simd2, coreCov, col)
                let miterEdge: FV = ((curr + m * (side * outerHalf / cosHalf)).simd2, 0, col)
                tri(center, inCore, miterCore); tri(center, miterCore, outCore)
                quad(inCore, inEdge, miterEdge, miterCore)
                quad(miterCore, miterEdge, outEdge, outCore)
                return true
            }
            func roundJoin() {
                let oa = p0 * side, ob = p1 * side          // unit outward dirs to the corners
                let a0 = atan2(oa.y, oa.x)
                let sweep = atan2(oa.x * ob.y - oa.y * ob.x, oa.x * ob.x + oa.y * ob.y)
                let steps = max(1, Int((abs(sweep) / (2 * .pi)
                                        * Double(circleSegments(for: outerHalf))).rounded(.up)))
                var prevD = oa
                for s in 1...steps {
                    let ang = a0 + sweep * Double(s) / Double(steps)
                    let curD = Vector2(cos(ang), sin(ang))
                    let inA: FV = ((curr + prevD * coreHalf).simd2, coreCov, col)
                    let inB: FV = ((curr + curD  * coreHalf).simd2, coreCov, col)
                    let edA: FV = ((curr + prevD * outerHalf).simd2, 0, col)
                    let edB: FV = ((curr + curD  * outerHalf).simd2, 0, col)
                    tri(center, inA, inB)                   // core fan wedge
                    quad(inA, edA, edB, inB)                // fringe band along the arc
                    prevD = curD
                }
            }
            switch strokeJoinStyle {
            case .round: roundJoin()
            case .bevel: bevel()
            case .miter: if !miter() { bevel() }
            }
        }

        // Caps on the two open ends (honor strokeCap; ends fade over the fringe).
        guard !closed else { return }
        func cap(at p: Vector2, perp: Vector2, outward: Vector2, _ col: SIMD4<Float>) {
            switch strokeCapStyle {
            case .butt:
                ribbon(crossAt(p, perp, 1, col), crossAt(p + outward * fw, perp, 0, col))
            case .square:
                let tip = p + outward * hw
                ribbon(crossAt(p, perp, 1, col), crossAt(tip, perp, 1, col))
                ribbon(crossAt(tip, perp, 1, col), crossAt(tip + outward * fw, perp, 0, col))
            case .round:
                let steps = max(4, Int((outerHalf * ctmScale).rounded()))
                let base = atan2(perp.y, perp.x)
                let rot90 = Vector2(-perp.y, perp.x)
                let sweep: Double = (outward.x * rot90.x + outward.y * rot90.y) >= 0 ? 1 : -1
                for s in 0..<steps {
                    let aθ = base + .pi * (Double(s) / Double(steps)) * sweep
                    let bθ = base + .pi * (Double(s + 1) / Double(steps)) * sweep
                    let da = Vector2(cos(aθ), sin(aθ)), db = Vector2(cos(bθ), sin(bθ))
                    let inA: FV = ((p + da * coreHalf).simd2, coreCov, col), inB: FV = ((p + db * coreHalf).simd2, coreCov, col)
                    let edA: FV = ((p + da * outerHalf).simd2, 0, col), edB: FV = ((p + db * outerHalf).simd2, 0, col)
                    tri((p.simd2, centerCov, col), inA, inB)
                    quad(inA, edA, edB, inB)
                }
            }
        }
        let d0 = segDir(pts[0], pts[1]), dL = segDir(pts[n - 2], pts[n - 1])
        cap(at: pts[0], perp: leftNormal(d0), outward: d0 * -1, cols[0])
        cap(at: pts[n - 1], perp: leftNormal(dL), outward: dL, cols[n - 1])
    }

    /// Pick a vertex count that keeps each edge segment ≲ 8 points long, so big
    /// circles stay smooth and small ones stay cheap. With 4× MSAA smoothing the
    /// edges, an 8-point chord is visually indistinguishable from a finer one at
    /// these sizes, for roughly half the tessellated vertices.
    func circleSegments(for radius: Double) -> Int {
        let targetEdgeLength = 8.0
        let circumference = 2.0 * .pi * radius
        return max(24, Int((circumference / targetEdgeLength).rounded(.up)))
    }

    /// One straight stroke segment as a rectangle (two triangles) of width
    /// `2 * half`, offset perpendicular to the segment direction. Each end takes
    /// its own color, so a gradient stroke shades across the quad; a solid
    /// stroke passes the same color twice.
    func appendSegment(from a: Vector2, to b: Vector2, half: Double,
                               colorA: SIMD4<Float>, colorB: SIMD4<Float>) {
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
        emit(a0, color: colorA)
        emit(b0, color: colorB)
        emit(b1, color: colorB)
        emit(a0, color: colorA)
        emit(b1, color: colorB)
        emit(a1, color: colorA)
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
    func appendStrokedPath(_ points: [Vector2], closed: Bool,
                                   half: Double, paint: VertexPaint) {
        // Emits only triangles into one batch; symmetry replicates the whole
        // stroke as a range copy (see `replicated`).
        replicated { appendStrokedPathSingle(points, closed: closed, half: half, paint: paint) }
    }

    private func appendStrokedPathSingle(_ points: [Vector2], closed: Bool,
                                         half: Double, paint: VertexPaint) {
        guard half > 0 else { return }
        // Drop repeated points; a zero-length segment has no direction.
        var pts: [Vector2] = []
        for p in points where (pts.last.map { ($0 - p).length > 1e-9 } ?? true) {
            pts.append(p)
        }
        if closed, pts.count > 1, (pts[0] - pts[pts.count - 1]).length <= 1e-9 {
            pts.removeLast()
        }
        // A segment quad carries color only at its two ends, so a gradient
        // crossing a long straight run would interpolate straight through its
        // stops (and a radial sweep would corner instead of curve) — split long
        // segments first. The inserted points are collinear, so the join filler
        // below skips them. Solid strokes keep their geometry untouched.
        if paint.isGradient {
            pts = Drawer.subdivided(pts, closed: closed, maxLength: 12)
        }
        let n = pts.count
        guard n >= 2 else { return }

        // Arc-length fraction at each vertex (0…1 over the path, the closing
        // segment included), read by along-path paint.
        var ts: [Double] = []
        var solidColor: SIMD4<Float>? = nil
        if case .solid(let c) = paint { solidColor = c }
        if solidColor == nil {
            var cumulative: [Double] = [0]
            cumulative.reserveCapacity(n)
            for i in 1..<n { cumulative.append(cumulative[i - 1] + (pts[i] - pts[i - 1]).length) }
            var total = cumulative[n - 1]
            if closed { total += (pts[0] - pts[n - 1]).length }
            ts = total > 0 ? cumulative.map { $0 / total } : Array(repeating: 0, count: n)
        }
        func colorAt(_ i: Int) -> SIMD4<Float> {
            solidColor ?? paint.color(at: pts[i], pathT: ts[i])
        }

        let segments = closed ? n : n - 1
        for i in 0..<segments {
            // The closing segment runs back to the start: its far end is the
            // path's t = 1, not the first vertex's t = 0.
            let j = (i + 1) % n
            let colorB = (closed && j == 0 && solidColor == nil)
                ? paint.color(at: pts[0], pathT: 1) : colorAt(j)
            appendSegment(from: pts[i], to: pts[j], half: half,
                          colorA: colorAt(i), colorB: colorB)
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
            // The whole join takes the corner vertex's color (it spans no length).
            let color = colorAt(v)
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
            appendCap(at: pts[0], outward: dStart / dStart.length * -1, half: half, color: colorAt(0))
        }
        let dEnd = pts[n - 1] - pts[n - 2]
        if dEnd.length > 1e-9 {
            appendCap(at: pts[n - 1], outward: dEnd / dEnd.length, half: half, color: colorAt(n - 1))
        }
    }

    /// `pts` with every segment longer than `maxLength` split into equal pieces
    /// (the closing segment of a closed path included), so per-vertex gradient
    /// color tracks the paint instead of skipping its stops.
    private static func subdivided(_ pts: [Vector2], closed: Bool, maxLength: Double) -> [Vector2] {
        guard pts.count >= 2 else { return pts }
        var out: [Vector2] = []
        out.reserveCapacity(pts.count)
        let segments = closed ? pts.count : pts.count - 1
        for i in 0..<segments {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            out.append(a)
            let pieces = Int(((b - a).length / maxLength).rounded(.up))
            if pieces > 1 {
                for k in 1..<pieces {
                    out.append(a + (b - a) * (Double(k) / Double(pieces)))
                }
            }
        }
        if !closed { out.append(pts[pts.count - 1]) }
        return out
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

    static func translation(_ tx: Float, _ ty: Float) -> matrix_float3x3 {
        matrix_float3x3(columns: (SIMD3<Float>(1, 0, 0),
                                  SIMD3<Float>(0, 1, 0),
                                  SIMD3<Float>(tx, ty, 1)))
    }
    static func rotation(_ a: Float) -> matrix_float3x3 {
        let c = cos(a), s = sin(a)
        return matrix_float3x3(columns: (SIMD3<Float>(c, s, 0),
                                         SIMD3<Float>(-s, c, 0),
                                         SIMD3<Float>(0, 0, 1)))
    }
    static func scaling(_ sx: Float, _ sy: Float) -> matrix_float3x3 {
        matrix_float3x3(columns: (SIMD3<Float>(sx, 0, 0),
                                  SIMD3<Float>(0, sy, 0),
                                  SIMD3<Float>(0, 0, 1)))
    }

    // MARK: 3D model-matrix builders (column-major, right-handed, y-up)

    static func translation3(_ t: SIMD3<Float>) -> matrix_float4x4 {
        matrix_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                  SIMD4<Float>(0, 1, 0, 0),
                                  SIMD4<Float>(0, 0, 1, 0),
                                  SIMD4<Float>(t.x, t.y, t.z, 1)))
    }
    static func scaling3(_ sx: Float, _ sy: Float, _ sz: Float) -> matrix_float4x4 {
        matrix_float4x4(columns: (SIMD4<Float>(sx, 0, 0, 0),
                                  SIMD4<Float>(0, sy, 0, 0),
                                  SIMD4<Float>(0, 0, sz, 0),
                                  SIMD4<Float>(0, 0, 0, 1)))
    }
    static func rotationX(_ a: Float) -> matrix_float4x4 {
        let c = cos(a), s = sin(a)
        return matrix_float4x4(columns: (SIMD4<Float>(1, 0, 0, 0),
                                         SIMD4<Float>(0, c, s, 0),
                                         SIMD4<Float>(0, -s, c, 0),
                                         SIMD4<Float>(0, 0, 0, 1)))
    }
    static func rotationY(_ a: Float) -> matrix_float4x4 {
        let c = cos(a), s = sin(a)
        return matrix_float4x4(columns: (SIMD4<Float>(c, 0, -s, 0),
                                         SIMD4<Float>(0, 1, 0, 0),
                                         SIMD4<Float>(s, 0, c, 0),
                                         SIMD4<Float>(0, 0, 0, 1)))
    }
    static func rotationZ(_ a: Float) -> matrix_float4x4 {
        let c = cos(a), s = sin(a)
        return matrix_float4x4(columns: (SIMD4<Float>(c, s, 0, 0),
                                         SIMD4<Float>(-s, c, 0, 0),
                                         SIMD4<Float>(0, 0, 1, 0),
                                         SIMD4<Float>(0, 0, 0, 1)))
    }
    /// Rotation about a unit `axis` by `a` radians (right-handed), via a quaternion
    /// so it stays consistent with the axis-aligned builders above.
    static func rotation3(_ a: Float, axis: SIMD3<Float>) -> matrix_float4x4 {
        matrix_float4x4(simd_quatf(angle: a, axis: axis))
    }
    /// The mean of the model matrix's three basis-column lengths — the factor a
    /// scaling transform applies to a splat's world-unit size (exact for uniform
    /// scale, a sensible average otherwise; 1 for a rigid transform).
    static func averageScale(_ m: matrix_float4x4) -> Float {
        let x = simd_length(SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z))
        let y = simd_length(SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z))
        let z = simd_length(SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z))
        return (x + y + z) / 3
    }
}
