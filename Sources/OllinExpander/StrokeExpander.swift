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
/// anti-aliasing coverage as two edge distances, the paint color with its own
/// alpha, and the signed offset from the centerline in the path's units
/// (positive on the side the left normal `(-d.y, d.x)` of the direction of
/// travel points to, zero on the line; a join or cap vertex carries the
/// distance it sits from the centerline on its side). A shader paint reads it
/// as the pixel's distance to the stroke.
///
/// `coverage` is how far inside the stroke's nearer edge the vertex sits, in
/// fringe widths, counted from half a fringe outside that edge: one half on
/// the edge itself, 1 where the solid core begins, more than 1 inside it, and
/// below zero on the rim the geometry carries past the edge (see
/// `StrokeExpander.expand`). `far` is the same distance to the opposite edge
/// on a vertex of a segment's body. Each is one flat ramp across the whole
/// width of a segment, so every triangle of the ribbon hands a pixel the same
/// pair, and a fragment that reads both knows where each edge runs through
/// its pixel. On a vertex of a join, a round cap, or a flat end's fade, where
/// the coverage falls off in one direction only, `far` is negative. Both
/// numbers are scaled by the stroke's thinness there (its width over the
/// footprint a hairline is held at, 1 for any stroke a fringe wide or more),
/// which a negative `far` carries as its size. A consumer with room for one
/// number reads `coverage` alone and holds it to 0...1: the ramp a fringe wide
/// that straddles the edge.
package typealias StrokeVertex = (position: SIMD2<Float>, coverage: Float, far: Float, color: SIMD4<Float>, offset: Float)

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
    ///
    /// Three things keep a stroke's ink at its width wherever it falls on the
    /// pixel grid. The stroke is drawn under a multisample mask, which cuts a
    /// pixel's coverage to the samples the geometry reaches, so the outer edge
    /// of the geometry (the rim) runs a fringe past the line the ramp reaches
    /// zero on, a fringe and a half past the stroke's own edge, carrying the
    /// ramp on below zero: every pixel the stroke touches, at any angle, is then
    /// whole under the mask. The coverage a vertex carries is not held to 0...1
    /// here (see `StrokeVertex`), so the ramp is one flat slope from rim to rim
    /// and a pixel straddling two bands reads one value from both. And a stroke
    /// thinner than the fringe keeps the fringe's width as its footprint and
    /// scales its coverage by its own width over that, so a hairline lays the
    /// ink of its width.
    package static func expand(_ pts: [Point2D], closed: Bool,
                               halfWidths hws: [Double], colors cols: [SIMD4<Float>],
                               fringe fw: Double, ctmScale: Double,
                               join: StrokeExpanderJoin, cap: StrokeExpanderCap,
                               emit: (StrokeVertex) -> Void) {
        expand(pts, closed: closed, halfWidths: hws, colors: cols, fringe: fw, ctmScale: ctmScale,
               join: join, cap: cap) { vertex, _ in emit(vertex) }
    }

    /// `expand`, also handing over the path vertex each emitted vertex was built
    /// from: every cross-section, join, and cap is laid out around one point of
    /// the path, so each emitted vertex belongs to exactly one. A caller that
    /// expanded a projection of the path uses it to give each vertex the depth of
    /// the point it came from.
    package static func expand(_ pts: [Point2D], closed: Bool,
                               halfWidths hws: [Double], colors cols: [SIMD4<Float>],
                               fringe fw: Double, ctmScale: Double,
                               join: StrokeExpanderJoin, cap: StrokeExpanderCap,
                               emit: (StrokeVertex, Int) -> Void) {
        let n = pts.count
        guard n >= 2, hws.count == n, cols.count == n else { return }
        let miterLimit = Self.miterLimit

        // Per-vertex band radii. A stroke thinner than the fringe is drawn at the
        // fringe's width (`bodyHalf`) with its coverage scaled by `thin`, its own
        // width over that, so it fades by width instead of snapping to a floor or
        // laying a pixel's worth of ink. The solid core ends half a fringe inside
        // the body's edge and the coverage reaches zero half a fringe outside it
        // (the fringe straddles the true edge, so perceived width is the
        // stroke's); the geometry itself runs on to the rim, `pad` further out.
        let pad = fw
        func bodyHalf(_ i: Int) -> Double { max(hws[i], fw / 2) }
        func thin(_ i: Int) -> Double { max(hws[i], 0) / bodyHalf(i) }
        func coreHalf(_ i: Int) -> Double { bodyHalf(i) - fw / 2 }
        func outerHalf(_ i: Int) -> Double { bodyHalf(i) + fw / 2 }
        func rimHalf(_ i: Int) -> Double { outerHalf(i) + pad }

        // Coverage at vertex `i`, in fringe widths inside the line where it
        // reaches zero: the core begins at exactly `thin` (1 for any stroke a
        // fringe wide or more), the centerline is further in, and the rim is
        // below zero. None of it is held to 0...1; the fragment does that. A
        // profile reaches sub-pixel widths far more often than a constant weight
        // does, since that is what a taper is for, but the ramp is the same one
        // either way: profiled and unprofiled strokes of the same width lay down
        // the same ink.
        func centerCov(_ i: Int) -> Float { Float(outerHalf(i) / fw * thin(i)) }
        func coreCov(_ i: Int) -> Float { Float(thin(i)) }
        func rimCov(_ i: Int) -> Float { Float(-pad / fw * thin(i)) }

        func segDir(_ a: Point2D, _ b: Point2D) -> Point2D {
            let d = b - a; let l = d.length
            return l > 1e-9 ? d / l : Point2D(1, 0)
        }
        func leftNormal(_ d: Point2D) -> Point2D { Point2D(-d.y, d.x) }

        // A shared crossing has to hold the visible stroke, out to where its
        // coverage ends. The rim past that carries no ink, so on the inner side
        // of a turn it runs only as far along the crossing as stays inside both
        // neighboring segments (`innerRim`), rather than costing a turn its
        // crossing: a rim cut short there loses at most a sliver of a pixel's
        // coverage to the mask, where a lost crossing lays a second coat.
        let innerMiter = innerCrossings(pts, closed: closed, halfWidth: outerHalf)
        func innerRim(_ v: Int) -> Double {
            let rim = rimHalf(v)
            guard innerMiter[v] != nil else { return rim }
            let prev = pts[(v - 1 + n) % n], curr = pts[v], next = pts[(v + 1) % n]
            let d0 = segDir(prev, curr), d1 = segDir(curr, next)
            let bx = (-d0.y - d1.y) * 0.5, by = (d0.x + d1.x) * 0.5
            let dmr2 = bx * bx + by * by                 // the cosine of half the turn, squared
            if dmr2 * 1.0201 >= 1 { return rim }         // near enough straight: any offset holds
            let shorter = min((curr - prev).length, (next - curr).length)
            return min(rim, max(outerHalf(v), shorter * dmr2.squareRoot()))
        }

        // A fringe vertex: position, the coverage toward its own edge and toward
        // the opposite one, the path color at this point, its signed offset from
        // the centerline, and the path vertex it was laid out around.
        typealias FV = (position: SIMD2<Float>, coverage: Float, far: Float, color: SIMD4<Float>, offset: Float, source: Int)
        func tri(_ a: FV, _ b: FV, _ d: FV) {
            emit((a.position, a.coverage, a.far, a.color, a.offset), a.source)
            emit((b.position, b.coverage, b.far, b.color, b.offset), b.source)
            emit((d.position, d.coverage, d.far, d.color, d.offset), d.source)
        }
        func quad(_ a: FV, _ b: FV, _ d: FV, _ e: FV) { tri(a, b, d); tri(a, d, e) }
        // A vertex of a join or a round cap, where the coverage falls off around
        // the path vertex rather than across a segment: one distance, and the
        // stroke's thinness, negative, where a body vertex has its other edge.
        func spoke(_ position: Point2D, _ cov: Float, _ col: SIMD4<Float>, _ offset: Float, _ source: Int) -> FV {
            (position.simd2, cov, Float(-thin(source)), col, offset, source)
        }
        // The five points across the stroke at one path vertex, rim to rim. It is
        // a value with a fixed shape rather than an array, so a cross section costs
        // no allocation: the expander builds two per segment, and this path runs
        // over every stroke in a frame.
        struct Cross { var outA, coreA, center, coreB, outB: FV }
        // A cross-section of a segment's body at `p`, at path vertex `i`'s width
        // and color, spreading along `dirA` on one side and `dirB` on the other.
        // The two directions are a segment's own perpendicular and its opposite,
        // except on the inner side of a join, where the shared crossing direction
        // takes over. Each point carries the ramp toward its own edge and the
        // ramp toward the other, both flat across the whole width. `rimA` and
        // `rimB` are how far out each side's rim sits.
        func crossAt(_ i: Int, _ p: Point2D, _ dirA: Point2D, _ dirB: Point2D,
                     rimA: Double, rimB: Double, _ col: SIMD4<Float>) -> Cross {
            let core = coreHalf(i), outer = outerHalf(i), k = thin(i) / fw
            // `side` signs the offset: +1 along `dirA` (the left normal's side), -1 along `dirB`.
            func at(_ d: Point2D, _ off: Double, _ near: Float, _ side: Float) -> FV {
                ((p + d * off).simd2, near, Float((outer + off) * k), col, Float(off) * side, i)
            }
            let c = centerCov(i), inner = coreCov(i)
            return Cross(outA: at(dirA, rimA, Float((outer - rimA) * k), 1), coreA: at(dirA, core, inner, 1),
                         center: at(dirA, 0, c, 1),
                         coreB: at(dirB, core, inner, -1), outB: at(dirB, rimB, Float((outer - rimB) * k), -1))
        }
        // A body cross-section away from any join, both rims at their full reach.
        func crossAt(_ i: Int, _ p: Point2D, _ dirA: Point2D, _ dirB: Point2D, _ col: SIMD4<Float>) -> Cross {
            crossAt(i, p, dirA, dirB, rimA: rimHalf(i), rimB: rimHalf(i), col)
        }
        // A cross-section of a butt or square end's fade, `along` fringe widths
        // past the end line: the body's ramp held to its core value, less
        // `along`, which is one flat slope over the whole fade, carried on below
        // zero to a rim past the tip as the sides' is.
        func fadeAt(_ i: Int, _ p: Point2D, _ dirA: Point2D, _ dirB: Point2D,
                    along: Double, _ col: SIMD4<Float>) -> Cross {
            let rim = rimHalf(i), core = coreHalf(i), t = thin(i)
            func at(_ d: Point2D, _ off: Double, _ held: Double, _ side: Float) -> FV {
                ((p + d * off).simd2, Float((held - along) * t), Float(-t), col, Float(off) * side, i)
            }
            return Cross(outA: at(dirA, rim, -pad / fw, 1), coreA: at(dirA, core, 1, 1), center: at(dirA, 0, 1, 1),
                         coreB: at(dirB, core, 1, -1), outB: at(dirB, rim, -pad / fw, -1))
        }
        // A segment's cross-section at path vertex `v`: its two directions (see
        // `spread`), with the rim of whichever side faces the inside of a turn
        // held to what the crossing allows.
        func bodyCross(_ v: Int, _ perp: Point2D) -> Cross {
            let (dirA, dirB) = spread(innerMiter[v], about: perp)
            var rimA = rimHalf(v), rimB = rimA
            if let m = innerMiter[v] {
                if m.x * perp.x + m.y * perp.y >= 0 { rimA = innerRim(v) } else { rimB = innerRim(v) }
            }
            return crossAt(v, pts[v], dirA, dirB, rimA: rimA, rimB: rimB, cols[v])
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
            ribbon(bodyCross(i, perp), bodyCross(j, perp))
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
            let coreHalf = coreHalf(v), rimHalf = rimHalf(v), coreCov = coreCov(v), rimCov = rimCov(v)
            // The join's vertices sit on the outer side, `side` of the left normal.
            let coreOff = Float(side * coreHalf), rimOff = Float(side * rimHalf)
            let center  = spoke(curr, centerCov(v), col, 0, v)
            let inCore  = spoke(curr + p0 * (side * coreHalf), coreCov, col, coreOff, v)
            let inEdge  = spoke(curr + p0 * (side * rimHalf), rimCov, col, rimOff, v)
            let outCore = spoke(curr + p1 * (side * coreHalf), coreCov, col, coreOff, v)
            let outEdge = spoke(curr + p1 * (side * rimHalf), rimCov, col, rimOff, v)
            func bevel() {
                tri(center, inCore, outCore)                // inner core wedge
                quad(inCore, inEdge, outEdge, outCore)      // fringe band across the bevel
            }
            func miter() -> Bool {
                let b = p0 + p1, bl = b.length
                let cosHalf = bl > 1e-6 ? (b.x * p0.x + b.y * p0.y) / bl : 0
                guard cosHalf > 1e-4, 1 / cosHalf <= miterLimit else { return false }
                let m = b / bl                              // unit bisector of the normals
                // A miter tip sits its band's distance from both centerlines.
                let miterCore = spoke(curr + m * (side * coreHalf / cosHalf), coreCov, col, coreOff, v)
                let miterEdge = spoke(curr + m * (side * rimHalf / cosHalf), rimCov, col, rimOff, v)
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
                                        * Double(circleSegments(for: outerHalf(v)))).rounded(.up)))
                var prevD = oa
                for s in 1...steps {
                    let ang = a0 + sweep * Double(s) / Double(steps)
                    let curD = Point2D(cos(ang), sin(ang))
                    let inA = spoke(curr + prevD * coreHalf, coreCov, col, coreOff, v)
                    let inB = spoke(curr + curD  * coreHalf, coreCov, col, coreOff, v)
                    let edA = spoke(curr + prevD * rimHalf, rimCov, col, rimOff, v)
                    let edB = spoke(curr + curD  * rimHalf, rimCov, col, rimOff, v)
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
            let hw = hws[i], outerHalf = outerHalf(i), coreHalf = coreHalf(i), rimHalf = rimHalf(i)
            let centerCov = centerCov(i), coreCov = coreCov(i), rimCov = rimCov(i)
            // An end vertex is never a join, so a cap expands along the plain
            // perpendicular on both sides. A flat end fades over one fringe past
            // the end line and its geometry runs `pad` past that, as the sides do.
            let back = perp * -1
            let past = (fw + pad) / fw
            switch cap {
            case .butt:
                ribbon(fadeAt(i, p, perp, back, along: 0, col),
                       fadeAt(i, p + outward * (fw + pad), perp, back, along: past, col))
            case .square:
                let tip = p + outward * hw
                ribbon(crossAt(i, p, perp, back, col), crossAt(i, tip, perp, back, col))
                ribbon(fadeAt(i, tip, perp, back, along: 0, col),
                       fadeAt(i, tip + outward * (fw + pad), perp, back, along: past, col))
            case .round:
                let steps = max(4, Int((outerHalf * ctmScale).rounded()))
                let base = atan2(perp.y, perp.x)
                let rot90 = Point2D(-perp.y, perp.x)
                let sweep: Double = (outward.x * rot90.x + outward.y * rot90.y) >= 0 ? 1 : -1
                for s in 0..<steps {
                    let aθ = base + .pi * (Double(s) / Double(steps)) * sweep
                    let bθ = base + .pi * (Double(s + 1) / Double(steps)) * sweep
                    let da = Point2D(cos(aθ), sin(aθ)), db = Point2D(cos(bθ), sin(bθ))
                    // A cap wedge's offsets take one sign, the side of the left normal
                    // its bisector leans to: a wedge whose two arc vertices carried
                    // opposite signs would interpolate the offset through zero across
                    // its face, and a paint reading |offset| would find the centerline
                    // there, a hairline across the cap.
                    let mid = da + db
                    let side: Float = (mid.x * perp.x + mid.y * perp.y) >= 0 ? 1 : -1
                    let inA = spoke(p + da * coreHalf, coreCov, col, Float(coreHalf) * side, i)
                    let inB = spoke(p + db * coreHalf, coreCov, col, Float(coreHalf) * side, i)
                    let edA = spoke(p + da * rimHalf, rimCov, col, Float(rimHalf) * side, i)
                    let edB = spoke(p + db * rimHalf, rimCov, col, Float(rimHalf) * side, i)
                    tri(spoke(p, centerCov, col, 0, i), inA, inB)
                    quad(inA, edA, edB, inB)
                }
            }
        }
        let d0 = segDir(pts[0], pts[1]), dL = segDir(pts[n - 2], pts[n - 1])
        capAt(0, pts[0], perp: leftNormal(d0), outward: d0 * -1, cols[0])
        capAt(n - 1, pts[n - 1], perp: leftNormal(dL), outward: dL, cols[n - 1])
    }
}
