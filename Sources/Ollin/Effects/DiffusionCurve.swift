import Foundation

public extension Sketch {
    /// Lay a **diffusion curve** into the current layer: the same path drawn
    /// twice, a hair apart, carrying `left` on one side and `right` on the
    /// other. Filter the layer with [`.diffuse()`](Filter.swift) and the color
    /// runs out from both marks until it settles, so the field jumps across the
    /// curve and is smooth everywhere else.
    ///
    /// This is the form the technique is named for. A gradient needs a direction
    /// and two ends; a diffusion curve needs neither, so the shape of the field
    /// is decided by where the curves are.
    ///
    /// ```swift
    /// let marks = makeRenderTarget()
    /// withTarget(marks) {
    ///     drawDiffusionCurve(path, left: Color(hex: 0xE2544C), right: Color(hex: 0x2B6C8C))
    /// }
    /// drawImage(marks.filtered(.diffuse()).image, 0, 0)
    /// ```
    ///
    /// `width` is how thick each side's mark is, in canvas points. Two or three
    /// is plenty: the mark only has to be solid enough for the solve to read it,
    /// and a thick one starts to show as a band of flat color.
    ///
    /// Left and right are named from walking the path in the order its points
    /// are given, with the canvas y running down, so reversing the points swaps
    /// the two colors.
    func drawDiffusionCurve(_ contour: Contour, left: Color, right: Color,
                            width: Double = 3) {
        drawDiffusionCurve(contour.points, closed: contour.isClosed,
                           left: left, right: right, width: width)
    }

    /// The same, from bare points.
    func drawDiffusionCurve(_ points: [Vector2], closed: Bool = false,
                            left: Color, right: Color, width: Double = 3) {
        guard points.count >= 2, width > 0 else { return }
        let offset = width / 2
        let normals = curveNormals(points, closed: closed)
        // A band offset by half its own width sits exactly against the path, so
        // the two colors meet on it with no seam between them and no overlap.
        let leftSide = zip(points, normals).map { $0 + $1 * offset }
        let rightSide = zip(points, normals).map { $0 - $1 * offset }
        withState {
            strokeCap(.butt)
            strokeJoin(.round)
            strokeWeight(width)
            stroke(left)
            drawPolyline(leftSide, closed: closed)
            stroke(right)
            drawPolyline(rightSide, closed: closed)
        }
    }
}

/// One unit normal per point: the average of the normals of the segments
/// meeting there, so an offset copy stays parallel around a corner. An open
/// path's ends take their one segment's normal.
private func curveNormals(_ points: [Vector2], closed: Bool) -> [Vector2] {
    let count = points.count
    func normal(_ from: Vector2, _ to: Vector2) -> Vector2 {
        let along = to - from
        let length = along.length
        guard length > 0 else { return Vector2(0, 0) }
        // The left hand of someone walking the path. The canvas y runs down, so
        // that is the quarter turn the other way from the one on paper.
        return Vector2(along.y, -along.x) / length
    }

    var segments: [Vector2] = []
    segments.reserveCapacity(count)
    for i in 0 ..< (closed ? count : count - 1) {
        segments.append(normal(points[i], points[(i + 1) % count]))
    }

    return (0 ..< count).map { i in
        let ahead = closed ? segments[i % segments.count] : segments[min(i, segments.count - 1)]
        let behind = closed ? segments[(i + segments.count - 1) % segments.count]
                            : segments[max(i - 1, 0)]
        let mean = ahead + behind
        let length = mean.length
        return length > 1e-9 ? mean / length : ahead
    }
}
