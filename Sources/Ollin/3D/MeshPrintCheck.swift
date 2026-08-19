import Foundation

/// What a mesh looks like to a printer, as `printCheck()` reports it.
///
/// A printer has to work out what is inside the surface and what is outside, and
/// it can only do that if the surface actually closes. On screen an open or
/// inside-out mesh looks perfectly fine, so this is the examination that catches
/// what your eyes cannot.
///
/// Everything here describes the mesh *as it would be written*: coincident
/// vertices already merged, degenerate triangles already dropped, winding
/// already settled. So the counts will not match the mesh's own `positions` and
/// `triangleCount`, which is the point. Ollin's generators are flat-shaded, and
/// on those raw numbers every one of them would read as broken.
public struct MeshPrintCheck: Sendable {

    /// Triangles that would be written.
    public var triangleCount: Int
    /// Distinct vertices that would be written, after merging.
    public var vertexCount: Int

    /// Whether every edge is shared by exactly two triangles, so the surface
    /// encloses a solid with no holes and no loose flaps.
    public var isClosed: Bool
    /// Whether neighboring triangles agree on which side is out. Two triangles
    /// sharing an edge agree when they run along it in opposite directions.
    public var isConsistentlyOriented: Bool
    /// Whether the surface is closed but wound inward, so the solid a printer
    /// would find is the space around the model rather than the model.
    public var isInsideOut: Bool

    /// Edges belonging to only one triangle: the rim of a hole.
    public var boundaryEdgeCount: Int
    /// Edges shared by three or more triangles, where more than one surface
    /// meets and there is no answer to which side is inside.
    public var nonManifoldEdgeCount: Int
    /// Triangles with no area, dropped on the way out.
    public var degenerateTriangleCount: Int

    /// The bounding size in model units, in the orientation it would be written
    /// (so with the default `upAxis`, `size.z` is the height on the platform).
    public var size: Vector3
    /// The volume the surface encloses, in cubic model units. Only meaningful
    /// for a closed mesh, and always reported as a positive amount.
    public var volume: Double

    /// Whether the mesh is ready to build: closed, manifold, consistently
    /// wound, and the right way out.
    public var isPrintable: Bool {
        isClosed && isConsistentlyOriented && !isInsideOut && nonManifoldEdgeCount == 0
    }

    /// The reasons it is not printable, in plain words, or empty when it is.
    /// This is what the writers print when they hand out a file a printer may
    /// refuse.
    public var problems: [String] {
        var found: [String] = []
        if triangleCount == 0 {
            found.append("it has no triangles")
        }
        if boundaryEdgeCount > 0 {
            found.append("\(boundaryEdgeCount) edge\(boundaryEdgeCount == 1 ? "" : "s") border a hole rather than another triangle")
        }
        if nonManifoldEdgeCount > 0 {
            found.append("\(nonManifoldEdgeCount) edge\(nonManifoldEdgeCount == 1 ? "" : "s") join more than two triangles")
        }
        if !isConsistentlyOriented {
            found.append("neighbouring triangles disagree about which side is out")
        }
        if isInsideOut {
            found.append("the surface is wound inward, so it describes the space around the model")
        }
        return found
    }

    /// A one-line summary, handy to print while tuning a shape.
    public var summary: String {
        let state = isPrintable ? "ready to print" : problems.joined(separator: ", ")
        let dimensions = "\(rounded(size.x)) x \(rounded(size.y)) x \(rounded(size.z))"
        return "\(triangleCount) triangles, \(dimensions) units: \(state)"
    }

    private func rounded(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

public extension Mesh {

    /// Examine this mesh the way a printer will, before writing it.
    ///
    /// The mesh is prepared exactly as `write(to:)` would prepare it, so what
    /// comes back describes the file you would get rather than the arrays you
    /// are holding.
    ///
    /// ```swift
    /// let check = sculpture.printCheck()
    /// print(check.summary)
    /// if check.isPrintable { sculpture.write(to: "sculpture.3mf") }
    /// ```
    ///
    /// A mesh that fails is not necessarily wrong: an open surface is a
    /// perfectly good thing to draw, and only fabrication needs it closed. What
    /// closes one depends on how it was made, and the generators that produce
    /// closed surfaces to begin with (`Metaballs`, `isosurface`, the solid
    /// primitives) are the shortest way there.
    func printCheck(upAxis: UpAxis = .z) -> MeshPrintCheck {
        guard let prepared = FabricationMesh(self, upAxis: upAxis) else {
            return MeshPrintCheck(triangleCount: 0, vertexCount: 0, isClosed: false,
                                  isConsistentlyOriented: true, isInsideOut: false,
                                  boundaryEdgeCount: 0, nonManifoldEdgeCount: 0,
                                  degenerateTriangleCount: triangleCount,
                                  size: .zero, volume: 0)
        }

        let positions = prepared.positions
        let indices = prepared.indices

        // Count how many triangles run along each undirected edge, and how many
        // run each way, which is what settles orientation. Counts are sums, so
        // no decision here depends on the order the table happens to be in.
        var uses: [Edge: Int] = [:]
        var forward: [Edge: Int] = [:]
        uses.reserveCapacity(indices.count)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let corners = [indices[t], indices[t + 1], indices[t + 2]]
            for c in 0 ..< 3 {
                let a = corners[c], b = corners[(c + 1) % 3]
                let edge = Edge(a, b)
                uses[edge, default: 0] += 1
                if a < b { forward[edge, default: 0] += 1 }
            }
        }

        var boundary = 0
        var nonManifold = 0
        var oriented = true
        for (edge, count) in uses {
            if count == 1 { boundary += 1 }
            if count > 2 { nonManifold += 1 }
            // Two triangles agree when exactly one of them runs the edge low to
            // high; both running the same way means one of them is flipped.
            if count == 2 && forward[edge, default: 0] != 1 { oriented = false }
        }

        let closed = boundary == 0 && nonManifold == 0 && prepared.triangleCount > 0
        let signed = FabricationMesh.signedVolume(positions: positions, indices: indices)

        var lo = positions.first ?? .zero
        var hi = lo
        for p in positions {
            lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }

        return MeshPrintCheck(
            triangleCount: prepared.triangleCount,
            vertexCount: positions.count,
            isClosed: closed,
            isConsistentlyOriented: oriented,
            isInsideOut: closed && oriented && signed < 0,
            boundaryEdgeCount: boundary,
            nonManifoldEdgeCount: nonManifold,
            degenerateTriangleCount: max(0, triangleCount - prepared.triangleCount),
            size: hi - lo,
            volume: abs(signed))
    }
}

/// One undirected edge, keyed by its endpoints in a fixed order so the two
/// triangles sharing it land on the same key whichever way each runs along it.
private struct Edge: Hashable {
    let low: UInt32
    let high: UInt32
    init(_ a: UInt32, _ b: UInt32) {
        low = min(a, b)
        high = max(a, b)
    }
}
