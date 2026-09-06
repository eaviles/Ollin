// The fringe stroke expander's geometry: a polyline and the style it was
// stroked with become edge-expanded triangles plus a screen-space
// anti-aliasing fringe, with the joins, the caps, and the shared inner
// crossing that keeps translucent ink to one coat. The renderer calls this
// for every stroke a sketch draws, and the web page's player part calls the
// same function, compiled to WebAssembly, on the points and styles a page
// carries, which is what lets a stroke travel as its points and still land
// vertex for vertex where the Mac put it.
//
// Nothing here reads the framework's state: the caller measures the stroke
// (the fringe width in local units, the half-width and the color at each
// point) and this emits the triangles in the stroke's own space. The caller
// applies the transform.

#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#elseif canImport(Glibc)
import Glibc
#endif

/// How a stroke's corners turn.
package enum StrokeExpanderJoin: UInt8 {
    case miter = 0
    case bevel = 1
    case round = 2
}

/// How a stroke's open ends finish.
package enum StrokeExpanderCap: UInt8 {
    case butt = 0
    case square = 1
    case round = 2
}

/// One emitted vertex: the position in the stroke's own space, the
/// anti-aliasing coverage, and the paint color with its own alpha.
package typealias StrokeVertex = (position: SIMD2<Float>, coverage: Float, color: SIMD4<Float>)

package enum StrokeExpander {
    /// Past this ratio of miter length to half-width a mitered corner bevels.
    package static let miterLimit = 8.0

    /// A turn whose sine is under this is a straight run: no join, no inner
    /// crossing. It is a hundredth of a degree, well above what a point
    /// carried in single precision can bend a straight run by (a point of a
    /// few hundred units rounds by about a hundred-thousandth, which over a
    /// segment of a dozen units reads as a sine near a millionth), so a
    /// stroke whose points travel as floats to a web page makes the joins the
    /// Mac's doubles made and expands to the same vertices; the gap a turn
    /// that small leaves on the outer side is under a thousandth of a pixel.
    package static let collinear = 1e-4

    /// A vertex count that keeps each edge of a circle of `radius` no longer
    /// than about eight points, and never fewer than 24 edges.
    package static func circleSegments(for radius: Double) -> Int {
        let targetEdgeLength = 8.0
        let circumference = 2.0 * .pi * radius
        return max(24, Int((circumference / targetEdgeLength).rounded(.up)))
    }

    /// Where consecutive segments of a stroked path cross on the inside of each
    /// turn, as a direction per path vertex (`nil` where there is no usable
    /// crossing and the ends stay square).
    ///
    /// A stroke is expanded segment by segment, and if each segment ends on its
    /// own perpendicular it runs past the point where its inner edge meets its
    /// neighbor's, so both quads cover the wedge between the two perpendiculars.
    /// Opaque ink hides that. Ink that is not opaque composites the wedge twice:
    /// a hard darker patch at every corner (a full second coat at a right angle),
    /// a graded dark band down the inside of a dense curve, a comb of dark radial
    /// spokes along a spiral. Ending both segments on the shared crossing instead
    /// draws the turn once, with no gap opened in exchange.
    ///
    /// The returned vector is scaled so that `pts[v] + result[v] * off` sits
    /// exactly `off` from *both* centerlines, which is what lets a caller keep
    /// using its own offsets (and any coverage ramp derived from them) unchanged.
    /// `halfWidth` reports the outermost offset the caller will apply at a vertex,
    /// since that is what has to stay inside the neighboring segments.
    package static func innerCrossings(_ pts: [Point2D], closed: Bool,
                                       halfWidth: (Int) -> Double) -> [Point2D?] {
        let n = pts.count
        var crossings = [Point2D?](repeating: nil, count: n)
        guard n >= 3 else { return crossings }
        func dir(_ a: Point2D, _ b: Point2D) -> Point2D {
            let d = b - a; let l = d.length
            return l > 1e-9 ? d / l : Point2D(1, 0)
        }
        for v in closed ? 0..<n : 1..<(n - 1) {
            let prev = pts[(v - 1 + n) % n], curr = pts[v], next = pts[(v + 1) % n]
            let d0 = dir(prev, curr), d1 = dir(curr, next)
            let cross = d0.x * d1.y - d0.y * d1.x
            guard abs(cross) > collinear else { continue }   // collinear: nothing crosses
            let bisector = Point2D(-d0.y - d1.y, d0.x + d1.x) * 0.5   // of the two normals
            let dmr2 = bisector.x * bisector.x + bisector.y * bisector.y
            guard dmr2 > 1e-6 else { continue }         // a hairpin has no crossing
            let scale = 1 / dmr2                        // |bisector| is cos(half the turn)
            guard scale <= 600 else { continue }        // near enough to a hairpin
            // The crossing has to fall inside both neighboring segments, or the
            // stroke turns itself inside out. Where it does not the ends stay
            // square: a corner that sharp folds over itself whatever we do, and an
            // overlap is a kinder failure than a crack. Clamping the crossing to a
            // maximum distance instead of bailing out would pull both ends short of
            // each other and open exactly that crack.
            let w = halfWidth(v)
            let shorter = min((curr - prev).length, (next - curr).length)
            let limit = max(1.01, w > 0 ? shorter / w : 1.01)
            guard dmr2 * limit * limit >= 1 else { continue }
            let inward: Double = cross >= 0 ? 1 : -1    // toward the inside of the turn
            crossings[v] = bisector * (scale * inward)
        }
        return crossings
    }

    /// Split a segment's left normal into the two directions its cross-section
    /// spreads along at one end: both perpendiculars, unless a join at that vertex
    /// offers a shared inner crossing, which replaces whichever side faces the
    /// inside of the turn. The outer side always keeps its perpendicular, so a
    /// join filler still meets the segment exactly where it used to.
    package static func spread(_ crossing: Point2D?, about perp: Point2D) -> (Point2D, Point2D) {
        guard let m = crossing else { return (perp, perp * -1) }
        return m.x * perp.x + m.y * perp.y >= 0 ? (m, perp * -1) : (perp, m)
    }

    /// Expand one stroke into its triangles, three `emit` calls per triangle.
    ///
    /// `pts` are the path's vertices with repeats already dropped (and a closed
    /// loop's closing duplicate removed), `n` of them; `halfWidths` and
    /// `colors` give the half-width and the paint color at each. `fringe` is
    /// the anti-aliasing band's width in the stroke's own units (about one
    /// screen pixel), and `ctmScale` the transform's scale, which sizes a round
    /// cap's arc in screen pixels. The fringe straddles the true edge, so the
    /// perceived width is the stroke's own.
    ///
    /// Each segment is a butt-ended ribbon of four bands (fringe, core, core,
    /// fringe) between two five-point cross-sections. The centerline point is
    /// load-bearing: every join fans from the path vertex, and without a point
    /// at offset zero that apex would land in the middle of the core band's end
    /// edge, a T-junction whose hairline swallows the odd sample and leaves a
    /// lighter pixel inside solid ink. Interior joins fill the outer gap per the
    /// join style (a miter bevels past the limit); the inner side ends on the
    /// shared crossing. Open ends take the cap style, fading over the fringe.
    package static func expand(_ pts: [Point2D], closed: Bool,
                               halfWidths hws: [Double], colors cols: [SIMD4<Float>],
                               fringe fw: Double, ctmScale: Double,
                               join: StrokeExpanderJoin, cap: StrokeExpanderCap,
                               emit: (StrokeVertex) -> Void) {
        let n = pts.count
        guard n >= 2, hws.count == n, cols.count == n else { return }
        let miterLimit = Self.miterLimit

        // Per-vertex band radii: the solid core, and the outer edge the fringe fades
        // to. The fringe straddles the true edge, so perceived width is the stroke's.
        func outerHalf(_ i: Int) -> Double { hws[i] + fw / 2 }
        func coreHalf(_ i: Int) -> Double { max(0, hws[i] - fw / 2) }

        // Coverage vs. distance from the centerline at vertex `i`: 1 in the solid
        // core, ramping to 0 across the outer fringe (and < 1 at the center for a
        // sub-pixel stroke, so thin lines fade by width instead of snapping to a
        // 1px floor). A profile reaches sub-pixel widths far more often than a
        // constant weight does, since that is what a taper is for, but the ramp is
        // the shipped one either way: profiled and unprofiled strokes of the same
        // width lay down the same ink.
        func covU(_ i: Int, _ off: Double) -> Float {
            Float(min(max((outerHalf(i) - abs(off)) / fw, 0), 1))
        }
        func centerCov(_ i: Int) -> Float { covU(i, 0) }
        func coreCov(_ i: Int) -> Float { covU(i, coreHalf(i)) }

        func segDir(_ a: Point2D, _ b: Point2D) -> Point2D {
            let d = b - a; let l = d.length
            return l > 1e-9 ? d / l : Point2D(1, 0)
        }
        func leftNormal(_ d: Point2D) -> Point2D { Point2D(-d.y, d.x) }

        let innerMiter = innerCrossings(pts, closed: closed, halfWidth: outerHalf)

        // A fringe vertex: position, AA coverage, and the path color at this point.
        typealias FV = StrokeVertex
        func tri(_ a: FV, _ b: FV, _ d: FV) {
            emit(a)
            emit(b)
            emit(d)
        }
        func quad(_ a: FV, _ b: FV, _ d: FV, _ e: FV) { tri(a, b, d); tri(a, d, e) }
        // The five points across the stroke at one path vertex, outer edge to outer
        // edge. It is a value with a fixed shape rather than an array, so a cross
        // section costs no allocation: the expander builds two per segment, and this
        // path runs over every stroke in a frame.
        struct Cross { var outA, coreA, center, coreB, outB: FV }
        // A cross-section at `p` at path vertex `i`'s width and color, spreading
        // along `dirA` on one side and `dirB` on the other, coverage scaled by `s`
        // (1 on the line, 0 at a length-fringe tip so butt/square ends fade out
        // across the fringe). The two directions are a segment's own perpendicular
        // and its opposite, except on the inner side of a join, where the shared
        // crossing direction takes over.
        func crossAt(_ i: Int, _ p: Point2D, _ dirA: Point2D, _ dirB: Point2D,
                     _ s: Float, _ col: SIMD4<Float>) -> Cross {
            func at(_ d: Point2D, _ off: Double) -> FV {
                ((p + d * off).simd2, covU(i, off) * s, col)
            }
            let outer = outerHalf(i), core = coreHalf(i)
            return Cross(outA: at(dirA, outer), coreA: at(dirA, core), center: at(dirA, 0),
                         coreB: at(dirB, core), outB: at(dirB, outer))
        }
        func spreadAt(_ v: Int, _ perp: Point2D) -> (Point2D, Point2D) {
            spread(innerMiter[v], about: perp)
        }
        // Connect two cross-sections into four quad bands (fringe | core | core |
        // fringe). Coverage is equal across the two core bands, so splitting the
        // core costs two triangles and changes nothing it draws.
        func ribbon(_ a: Cross, _ b: Cross) {
            quad(a.outA,   b.outA,   b.coreA,  a.coreA)
            quad(a.coreA,  b.coreA,  b.center, a.center)
            quad(a.center, b.center, b.coreB,  a.coreB)
            quad(a.coreB,  b.coreB,  b.outB,   a.outB)
        }

        // Body: each segment is its own butt-ended fringe quad along its perpendicular,
        // its two ends carrying their path vertices' colors (the GPU interpolates).
        // Under a width profile the quad is a trapezoid, which is exact: the offset of
        // a linearly varying width along a straight run is itself a straight edge.
        let segCount = closed ? n : n - 1
        for i in 0..<segCount {
            let j = (i + 1) % n
            let perp = leftNormal(segDir(pts[i], pts[j]))
            let (a0, b0) = spreadAt(i, perp), (a1, b1) = spreadAt(j, perp)
            ribbon(crossAt(i, pts[i], a0, b0, 1, cols[i]),
                   crossAt(j, pts[j], a1, b1, 1, cols[j]))
        }

        // Interior joins: fill the outer gap between the two segment quads at each
        // shared vertex (the inner side is covered by their overlap). The join style
        // honors the join; `.miter` bevels past the miter limit so an acute corner
        // doesn't spike. The whole join takes the corner vertex's color.
        let joins = closed ? Array(0..<n) : Array(1..<(n - 1))
        for v in joins {
            let prev = pts[(v - 1 + n) % n], curr = pts[v], next = pts[(v + 1) % n]
            let d0 = segDir(prev, curr), d1 = segDir(curr, next)
            let cross = d0.x * d1.y - d0.y * d1.x
            guard abs(cross) > collinear else { continue }  // collinear: no gap to fill
            let p0 = leftNormal(d0), p1 = leftNormal(d1)
            let side: Double = cross >= 0 ? -1 : 1          // outer side of the turn
            let col = cols[v]
            // Both segments meeting here were expanded at this vertex's width, so the
            // join is the constant-width join solved at that one local width.
            let coreHalf = coreHalf(v), outerHalf = outerHalf(v), coreCov = coreCov(v)
            let center:  FV = (curr.simd2, centerCov(v), col)
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
                    let curD = Point2D(cos(ang), sin(ang))
                    let inA: FV = ((curr + prevD * coreHalf).simd2, coreCov, col)
                    let inB: FV = ((curr + curD  * coreHalf).simd2, coreCov, col)
                    let edA: FV = ((curr + prevD * outerHalf).simd2, 0, col)
                    let edB: FV = ((curr + curD  * outerHalf).simd2, 0, col)
                    tri(center, inA, inB)                   // core fan wedge
                    quad(inA, edA, edB, inB)                // fringe band along the arc
                    prevD = curD
                }
            }
            switch join {
            case .round: roundJoin()
            case .bevel: bevel()
            case .miter: if !miter() { bevel() }
            }
        }

        // Caps on the two open ends (honor the cap style; ends fade over the fringe).
        // A cap takes its end vertex's width, so a tapered stroke's cap shrinks with
        // it and a tip tapered to nothing has no cap left to draw.
        guard !closed else { return }
        func capAt(_ i: Int, _ p: Point2D, perp: Point2D, outward: Point2D, _ col: SIMD4<Float>) {
            let hw = hws[i], outerHalf = outerHalf(i), coreHalf = coreHalf(i)
            let centerCov = centerCov(i), coreCov = coreCov(i)
            // An end vertex is never a join, so a cap expands along the plain
            // perpendicular on both sides.
            let back = perp * -1
            switch cap {
            case .butt:
                ribbon(crossAt(i, p, perp, back, 1, col),
                       crossAt(i, p + outward * fw, perp, back, 0, col))
            case .square:
                let tip = p + outward * hw
                ribbon(crossAt(i, p, perp, back, 1, col), crossAt(i, tip, perp, back, 1, col))
                ribbon(crossAt(i, tip, perp, back, 1, col),
                       crossAt(i, tip + outward * fw, perp, back, 0, col))
            case .round:
                let steps = max(4, Int((outerHalf * ctmScale).rounded()))
                let base = atan2(perp.y, perp.x)
                let rot90 = Point2D(-perp.y, perp.x)
                let sweep: Double = (outward.x * rot90.x + outward.y * rot90.y) >= 0 ? 1 : -1
                for s in 0..<steps {
                    let aθ = base + .pi * (Double(s) / Double(steps)) * sweep
                    let bθ = base + .pi * (Double(s + 1) / Double(steps)) * sweep
                    let da = Point2D(cos(aθ), sin(aθ)), db = Point2D(cos(bθ), sin(bθ))
                    let inA: FV = ((p + da * coreHalf).simd2, coreCov, col), inB: FV = ((p + db * coreHalf).simd2, coreCov, col)
                    let edA: FV = ((p + da * outerHalf).simd2, 0, col), edB: FV = ((p + db * outerHalf).simd2, 0, col)
                    tri((p.simd2, centerCov, col), inA, inB)
                    quad(inA, edA, edB, inB)
                }
            }
        }
        let d0 = segDir(pts[0], pts[1]), dL = segDir(pts[n - 2], pts[n - 1])
        capAt(0, pts[0], perp: leftNormal(d0), outward: d0 * -1, cols[0])
        capAt(n - 1, pts[n - 1], perp: leftNormal(dL), outward: dL, cols[n - 1])
    }
}
