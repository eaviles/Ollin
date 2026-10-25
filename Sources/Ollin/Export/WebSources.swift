// A stroke or a fill as the points and the style the sketch gave, kept beside
// the vertices it expanded to while a web recording is on. The page carries
// the points and expands them itself through the same expander compiled to
// WebAssembly, which is what brings a dense line drawing under the page's
// weight: a stroke's bands run to a few dozen vertices per point.

import simd
import OllinExpander

/// One stroke or fill the triangle paths expanded this frame, as what it was
/// expanded from: the points, the style, and the transform, plus the vertices
/// it became in the drawer's `vertices`, so the recorder can hand the page the
/// points in the vertices' place and leave everything else as it was.
struct WebSource {
    enum Kind {
        /// A stroke through the fringe expander: closed or open, its join and
        /// cap, the anti-aliasing band in the stroke's own units and the
        /// transform's scale, one half-width or one per point, and one color
        /// or one per point (a gradient, or an opacity that varies).
        case stroke(closed: Bool, join: StrokeExpanderJoin, cap: StrokeExpanderCap,
                    fringe: Double, ctmScale: Double,
                    halfWidths: [Double]?, halfWidth: Double,
                    colors: [SIMD4<Float>]?, color: SIMD4<Float>)
        /// A convex fill as the fan from its first point.
        case fan(color: SIMD4<Float>)
        /// A fill through the tessellator: its closed contours' lengths, the
        /// winding rule, and its color.
        case tessellated(lengths: [Int], nonZero: Bool, color: SIMD4<Float>)
        /// A stroke under a medium as its runs (the whole path, or its
        /// dashes), each with its own points, half-widths, colors, and
        /// fractions along the whole path; the source's `points` stay empty.
        case ribbons(runs: [WebRibbonRun], join: StrokeExpanderJoin, cap: StrokeExpanderCap,
                     fringe: Double, ctmScale: Double, wholeLength: Double?, seed: Float)
    }

    var kind: Kind
    /// A stroke's or a fan's points, or a tessellated fill's contours back to
    /// back, in the space `transform` places.
    var points: [Point2D]
    /// The transform the vertices were placed by; `nil` is the identity.
    var transform: matrix_float3x3?
    /// The vertices it expanded to.
    var vertexRange: Range<Int>

    /// The floats the record takes on the wire.
    var floats: Int {
        switch kind {
        case let .stroke(_, _, _, _, _, halfWidths, _, colors, _):
            return WebSourceLayout.strokeFloats(points: points.count, widthsPerPoint: halfWidths != nil,
                                                colorsPerPoint: colors != nil)
        case .fan:
            return WebSourceLayout.fanFloats(points: points.count)
        case let .tessellated(lengths, _, _):
            return WebSourceLayout.tessellatedFloats(contours: lengths)
        case let .ribbons(runs, _, _, _, _, _, _):
            return runs.reduce(0) { total, run in
                total + WebSourceLayout.ribbonFloats(points: run.points.count,
                                                     widthsPerPoint: run.halfWidths.count > 1,
                                                     colorsPerPoint: run.colors.count > 1,
                                                     fractions: run.fractions != nil)
            }
        }
    }

    /// Append the record to `out`, placed by `placement` composed onto its own
    /// transform (a recording replayed under a draw-time transform).
    func encode(into out: inout [Float], under placement: matrix_float3x3? = nil) {
        var t = transform ?? matrix_identity_float3x3
        if let placement { t = placement * t }
        let identity = transform == nil && placement == nil
        let columns: [Float] = identity ? [1, 0, 0, 1, 0, 0]
            : [t.columns.0.x, t.columns.0.y, t.columns.1.x, t.columns.1.y, t.columns.2.x, t.columns.2.y]
        func header(kind: Float, flags: Int, count: Int, fringe: Double, ctmScale: Double) {
            out.append(kind)
            out.append(Float(flags))
            out.append(Float(count))
            out.append(Float(fringe))
            out.append(Float(ctmScale))
            out.append(contentsOf: columns)
            out.append(0)
        }
        func color(_ c: SIMD4<Float>) { out.append(c.x); out.append(c.y); out.append(c.z); out.append(c.w) }
        func point(_ p: Point2D) { out.append(Float(p.x)); out.append(Float(p.y)) }
        switch kind {
        case let .stroke(closed, join, cap, fringe, ctmScale, halfWidths, halfWidth, colors, single):
            var flags = closed ? WebSourceLayout.closedFlag : 0
            flags |= Int(join.rawValue) << WebSourceLayout.joinShift
            flags |= Int(cap.rawValue) << WebSourceLayout.capShift
            if halfWidths != nil { flags |= WebSourceLayout.widthsPerPointFlag }
            if colors != nil { flags |= WebSourceLayout.colorsPerPointFlag }
            header(kind: WebSourceLayout.strokeKind, flags: flags, count: points.count, fringe: fringe, ctmScale: ctmScale)
            for p in points { point(p) }
            if let halfWidths {
                for w in halfWidths { out.append(Float(w)) }
            } else {
                out.append(Float(halfWidth))
            }
            if let colors {
                for c in colors { color(c) }
            } else {
                color(single)
            }
        case let .fan(c):
            header(kind: WebSourceLayout.fanKind, flags: 0, count: points.count, fringe: 0, ctmScale: 0)
            for p in points { point(p) }
            color(c)
        case let .tessellated(lengths, nonZero, c):
            header(kind: WebSourceLayout.tessellatedKind, flags: nonZero ? WebSourceLayout.nonZeroFlag : 0,
                   count: lengths.count, fringe: 0, ctmScale: 0)
            for n in lengths { out.append(Float(n)) }
            for p in points { point(p) }
            color(c)
        case let .ribbons(runs, join, cap, fringe, ctmScale, wholeLength, seed):
            for run in runs {
                var flags = run.closed ? WebSourceLayout.closedFlag : 0
                flags |= Int(join.rawValue) << WebSourceLayout.joinShift
                flags |= Int(cap.rawValue) << WebSourceLayout.capShift
                if run.halfWidths.count > 1 { flags |= WebSourceLayout.widthsPerPointFlag }
                if run.colors.count > 1 { flags |= WebSourceLayout.colorsPerPointFlag }
                if run.fractions != nil { flags |= WebSourceLayout.fractionsFlag }
                if let paces = run.paces {
                    flags |= paces.count > 1 ? WebSourceLayout.pacesPerPointFlag : WebSourceLayout.paceFlag
                }
                header(kind: WebSourceLayout.ribbonKind, flags: flags, count: run.points.count,
                       fringe: fringe, ctmScale: ctmScale)
                for p in run.points { point(p) }
                for w in run.halfWidths { out.append(Float(w)) }
                for c in run.colors { color(c) }
                if let fractions = run.fractions { for t in fractions { out.append(Float(t)) } }
                if let paces = run.paces { out.append(contentsOf: paces) }
                out.append(wholeLength.map(Float.init) ?? -1)
                out.append(seed)
            }
        }
    }
}

/// One run of a stroke under a medium, prepared as the renderer expands it:
/// its points, one half-width or one per point, one color or one per point,
/// its fractions along the whole path when it is a dash, and under ink the
/// pen's pace, one or one per point.
struct WebRibbonRun {
    var points: [Point2D]
    var closed: Bool
    var halfWidths: [Double]
    var colors: [SIMD4<Float>]
    var fractions: [Double]?
    var paces: [Float]?

    /// A run with its per-point lists folded to one entry where every entry
    /// is the same.
    init(points: [Point2D], closed: Bool, halfWidths: [Double], colors: [SIMD4<Float>], fractions: [Double]?,
         paces: [Float]? = nil) {
        self.points = points
        self.closed = closed
        self.halfWidths = halfWidths.allSatisfy { $0 == halfWidths.first } ? Array(halfWidths.prefix(1)) : halfWidths
        self.colors = colors.allSatisfy { $0 == colors.first } ? Array(colors.prefix(1)) : colors
        self.fractions = fractions
        self.paces = paces.map { list in list.allSatisfy { $0 == list.first } ? Array(list.prefix(1)) : list }
    }
}
