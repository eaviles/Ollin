import CClipper2
import Foundation

// Boolean set operations and offsetting on `Shape`, backed by the vendored
// Clipper2 library (External/CClipper2) the same way concave fills are backed
// by libtess2 — wrapped here so the C symbols stay off the public surface.

extension Shape {
    /// The region covered by this shape, the other, or both.
    ///
    /// Like all the set operations, it works on the *filled region*: each
    /// side resolves under its own `winding` rule first (so self-overlaps and
    /// holes mean what they mean when the shape draws), closed contours with
    /// at least three points participate, and open contours are ignored. The
    /// result is a fresh `Shape` whose outer boundaries and holes are
    /// oppositely wound, marked `.nonZero`.
    public func union(_ other: Shape) -> Shape {
        clipped(CC2ClipTypeUnion, with: other)
    }

    /// The region covered by both this shape and the other.
    public func intersection(_ other: Shape) -> Shape {
        clipped(CC2ClipTypeIntersection, with: other)
    }

    /// The region covered by this shape but not the other — `other` is cut
    /// away, leaving holes where it overlapped the inside.
    public func subtracting(_ other: Shape) -> Shape {
        clipped(CC2ClipTypeDifference, with: other)
    }

    /// The region covered by exactly one of the two shapes (the union minus
    /// the overlap).
    public func symmetricDifference(_ other: Shape) -> Shape {
        clipped(CC2ClipTypeXor, with: other)
    }

    /// A copy of the filled region grown (positive `delta`) or shrunk
    /// (negative) by a uniform distance, in points. Holes move the opposite
    /// way, so a ring offset outward gets thicker on both edges. Shrinking
    /// past a region's narrowest waist splits or removes it — offsetting a
    /// 100-point-wide blob by −60 leaves nothing, which is what makes
    /// repeated insets read as topographic contour lines.
    ///
    /// `join` decides what happens at corners, with the same vocabulary as
    /// `strokeJoin(_:)`: `.miter` keeps them sharp (beveling past the same
    /// limit the stroked path uses, so an acute spike can't run away),
    /// `.bevel` always cuts them flat, and `.round` arcs around them. Open
    /// contours are ignored — this offsets a region, not a stroke.
    public func offset(by delta: Double, join: StrokeJoin = .miter) -> Shape {
        let flat = FlatPaths(self)
        let solution = flat.withUnsafePointers { xy, counts, pathCount in
            cc2_offset(xy, counts, pathCount, winding.clipperFill,
                       delta, join.clipperJoin, strokeMiterLimit)
        }
        return Shape(solution: solution)
    }

    private func clipped(_ op: CC2ClipType, with other: Shape) -> Shape {
        let subject = FlatPaths(self)
        let clip = FlatPaths(other)
        let solution = subject.withUnsafePointers { sxy, scounts, scount in
            clip.withUnsafePointers { cxy, ccounts, ccount in
                cc2_boolean(op, sxy, scounts, scount, winding.clipperFill,
                            cxy, ccounts, ccount, other.winding.clipperFill)
            }
        }
        return Shape(solution: solution)
    }

    /// Decodes a clipper solution into contours; a failed (nil) solution
    /// becomes an empty shape.
    fileprivate init(solution: OpaquePointer?) {
        guard let solution else {
            self.init(contours: [], winding: .nonZero)
            return
        }
        defer { cc2_solution_destroy(solution) }
        var contours: [Contour] = []
        for pathIndex in 0..<cc2_solution_path_count(solution) {
            let pointCount = Int(cc2_solution_path_size(solution, pathIndex))
            guard pointCount >= 3 else { continue }
            var xy = [Double](repeating: 0, count: 2 * pointCount)
            cc2_solution_path_points(solution, pathIndex, &xy)
            var points: [Vector2] = []
            points.reserveCapacity(pointCount)
            for i in 0..<pointCount {
                points.append(Vector2(xy[2 * i], xy[2 * i + 1]))
            }
            contours.append(Contour(points, closed: true))
        }
        self.init(contours: contours, winding: .nonZero)
    }
}

/// The corner-spike cap shared with the tessellated stroke path (see
/// `Drawer.appendStrokedPath`), so a mitered offset and a mitered stroke
/// bevel at the same sharpness.
private let strokeMiterLimit = 8.0

/// A shape's fillable contours (closed, three or more points — the same set
/// the fill uses) flattened to the interleaved buffer the C shim reads.
private struct FlatPaths {
    var xy: [Double] = []
    var counts: [Int32] = []

    init(_ shape: Shape) {
        for contour in shape.contours where contour.isClosed && contour.points.count >= 3 {
            counts.append(Int32(contour.points.count))
            for point in contour.points {
                xy.append(point.x)
                xy.append(point.y)
            }
        }
    }

    func withUnsafePointers<R>(
        _ body: (UnsafePointer<Double>?, UnsafePointer<Int32>?, Int32) -> R
    ) -> R {
        xy.withUnsafeBufferPointer { xyBuffer in
            counts.withUnsafeBufferPointer { countsBuffer in
                body(xyBuffer.baseAddress, countsBuffer.baseAddress, Int32(counts.count))
            }
        }
    }
}

private extension FillWinding {
    var clipperFill: CC2FillRule {
        self == .nonZero ? CC2FillRuleNonZero : CC2FillRuleEvenOdd
    }
}

private extension StrokeJoin {
    var clipperJoin: CC2JoinType {
        switch self {
        case .miter: CC2JoinTypeMiter
        case .bevel: CC2JoinTypeBevel
        case .round: CC2JoinTypeRound
        }
    }
}
