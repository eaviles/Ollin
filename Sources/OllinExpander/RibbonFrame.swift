// A ribbon's own coordinates: where along a stroke's path and where across
// its width each vertex the expander builds sits. The Mac's medium strokes
// and the web page's player part both write them from this one place, so a
// pencil's tooth or a bristle's streak lands on the same point of the ribbon
// on either side.

/// The path a ribbon is built around, measured once: each path vertex's
/// distance along, its tangent (the bisector of the two segments there), and
/// which side of a closed outline is inside.
package struct RibbonFrame {
    package let points: [Point2D]
    package let halfWidths: [Double]
    /// Each path vertex's distance along: its own run's, or for a dash its
    /// place on the whole path.
    package let arc: [Double]
    package let tangent: [Point2D]
    /// The run's own length, its closing segment included.
    package let total: Double
    /// The length the fraction along divides by: the whole path's for a dash.
    package let length: Double
    /// -1 when a closed outline winds so that its inside is on the offset's
    /// positive side, else 1.
    package let inward: Double
    package let fringe: Double
    package let closed: Bool

    package init(_ pts: [Point2D], closed: Bool, halfWidths hws: [Double], fringe fw: Double,
                 fractions ts: [Double]?, wholeLength: Double?) {
        let n = pts.count
        var cum = [Double](repeating: 0, count: n)
        for i in 1..<max(n, 1) { cum[i] = cum[i - 1] + (pts[i] - pts[i - 1]).length }
        var total = n > 0 ? cum[n - 1] : 0
        if closed && n > 0 { total += (pts[0] - pts[n - 1]).length }
        let length = wholeLength ?? total
        var arc = cum
        if wholeLength != nil, let ts {
            for i in 0..<min(n, ts.count) { arc[i] = ts[i] * length }
        }
        var tangent = [Point2D](repeating: Point2D(1, 0), count: n)
        for i in 0..<n {
            var d = Point2D(0, 0)
            var forward = Point2D(1, 0)
            if i > 0 || closed {
                let e = pts[i] - pts[(i - 1 + n) % n]
                let l = e.length
                if l > 0 { d = d + e * (1 / l); forward = e * (1 / l) }
            }
            if i < n - 1 || closed {
                let e = pts[(i + 1) % n] - pts[i]
                let l = e.length
                if l > 0 { d = d + e * (1 / l); forward = e * (1 / l) }
            }
            let l = d.length
            tangent[i] = l > 1e-9 ? d * (1 / l) : forward
        }
        var area = 0.0
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % n]
            area += a.x * b.y - b.x * a.y
        }
        self.points = pts
        self.halfWidths = hws
        self.arc = arc
        self.tangent = tangent
        self.total = total
        self.length = length
        self.inward = closed && area > 0 ? -1 : 1
        self.fringe = fw
        self.closed = closed
    }

    /// Whether a triangle whose corners were built from these path vertices is
    /// the closing segment's, which ends on the first vertex at the loop's
    /// whole length along rather than at its start.
    package func wraps(_ a: Int, _ b: Int, _ c: Int) -> Bool {
        let n = points.count
        let last = n - 1
        return closed && n >= 3 && (a == last || b == last || c == last) && (a == 0 || b == 0 || c == 0)
    }

    /// A vertex's distance along, its place across the width (signed, -1 and 1
    /// at the true edges, negative inside a closed outline), and its fraction
    /// along: `position` in the path's own space, `offset` the expander's
    /// signed offset from its path vertex `source`.
    package func coordinates(_ position: Point2D, offset: Float, source src: Int,
                             wraps: Bool) -> (arc: Double, across: Float, along: Float) {
        let d = position - points[src]
        var a = arc[src] + (d.x * tangent[src].x + d.y * tangent[src].y)
        if wraps && src == 0 { a += total }
        let hw = halfWidths[src]
        let across = Float(Double(offset) * inward / max(hw, fringe / 2))
        let along = length > 0 ? Float(a / length) : 0
        return (a, across, along)
    }
}
