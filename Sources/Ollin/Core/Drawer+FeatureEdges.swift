// Drawer, a mesh's feature edges (`featureEdges(creaseAngle:)`): the faces draw
// as they always do, and the edges where two faces meet at an angle, where the
// surface ends, or where it turns away from the eye draw over them in the
// stroke. A mesh's edges are found once and kept on the GPU; each frame a draw
// records only a batch that points at them and at the copies the solid draw
// placed, and the vertex shader (`ollin_edge_vertex`) does the rest per copy.

import Foundation
import Metal
import simd
import COllinShaders

/// The feature edges of one mesh at one crease angle, kept for every frame
/// that draws the mesh again, with the GPU buffer made from them the first
/// time a frame needs it. Nothing in it changes once it is made, so a frame
/// still in flight can go on reading the buffer while a later one draws.
final class FeatureEdgeSet {
    let edges: [OllinMeshEdge]
    /// Whether every edge has a face on both sides: on a closed mesh, a crease
    /// whose faces both turn away is behind the mesh's own front, and is skipped.
    let isClosed: Bool
    private var buffer: MTLBuffer?

    init(edges: [OllinMeshEdge], isClosed: Bool) {
        self.edges = edges
        self.isClosed = isClosed
    }

    func metalBuffer(for device: MTLDevice) -> MTLBuffer? {
        if let buffer, buffer.device === device { return buffer }
        guard !edges.isEmpty else { return nil }
        buffer = edges.withUnsafeBytes { raw in
            device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
        }
        return buffer
    }

    /// The edges of `mesh` worth drawing at `creaseAngle` (radians): each one
    /// once, its two ends in the mesh's own space and the normals of the faces
    /// on either side. A boundary has one face; a crease two that meet past the
    /// angle (a third face at an edge makes it a crease too, since the surface
    /// branches there); every other shared edge is smooth, kept because it may
    /// be the silhouette from wherever a copy is seen. Corners a mesh holds once
    /// per face (hard edges) are welded first, or every edge would be a boundary,
    /// and a face whose corners weld into fewer than three points (a sphere's
    /// pole, collapsed to a point the arithmetic leaves a hair apart) has no
    /// direction and is left out, as is any face with no area.
    static func find(in mesh: Mesh, creaseAngle: Double) -> FeatureEdgeSet {
        let positions = mesh.positions
        let welded = LineDrawing.weld(positions)
        struct Face { var a: Int, b: Int, c: Int, normal: Vector3 }
        var faces: [Face] = []
        faces.reserveCapacity(mesh.indices.count / 3)
        var index = 0
        while index + 2 < mesh.indices.count {
            let a = Int(mesh.indices[index]), b = Int(mesh.indices[index + 1]), c = Int(mesh.indices[index + 2])
            index += 3
            guard a < positions.count, b < positions.count, c < positions.count else { continue }
            guard welded[a] != welded[b], welded[b] != welded[c], welded[c] != welded[a] else { continue }
            let cross = (positions[b] - positions[a]).cross(positions[c] - positions[a])
            let area = cross.length
            guard area > 1e-20 else { continue }
            faces.append(Face(a: a, b: b, c: c, normal: cross / area))
        }

        struct Sides { var first: Int; var second: Int?; var branches = false }
        var shared: [SIMD2<Int32>: Sides] = [:]
        shared.reserveCapacity(faces.count * 3 / 2)
        var order: [(key: SIMD2<Int32>, u: Int, v: Int)] = []
        order.reserveCapacity(faces.count * 3 / 2)
        for (f, face) in faces.enumerated() {
            for (u, v) in [(face.a, face.b), (face.b, face.c), (face.c, face.a)] {
                let wu = welded[u], wv = welded[v]
                guard wu != wv else { continue }
                let key = SIMD2<Int32>(Int32(min(wu, wv)), Int32(max(wu, wv)))
                if var sides = shared[key] {
                    if sides.second == nil { sides.second = f } else { sides.branches = true }
                    shared[key] = sides
                } else {
                    shared[key] = Sides(first: f)
                    order.append((key, u, v))
                }
            }
        }

        let creaseLimit = cos(min(max(creaseAngle, 0), .pi))
        var edges: [OllinMeshEdge] = []
        edges.reserveCapacity(order.count)
        var closed = true
        func row(_ v: Vector3, _ w: Float = 0) -> SIMD4<Float> {
            SIMD4<Float>(Float(v.x), Float(v.y), Float(v.z), w)
        }
        for (key, u, v) in order {
            guard let sides = shared[key] else { continue }
            let first = faces[sides.first].normal
            let kind: Float
            let second: Vector3
            if let s = sides.second {
                second = faces[s].normal
                kind = sides.branches || creaseAngle <= 0 || first.dot(second) < creaseLimit ? 1 : 2
            } else {
                second = first
                kind = 0
                closed = false
            }
            edges.append(OllinMeshEdge(a: row(positions[u], kind), b: row(positions[v]),
                                       normal0: row(first), normal1: row(second)))
        }
        return FeatureEdgeSet(edges: edges, isClosed: closed)
    }
}

/// The edge sets of the meshes a sketch has drawn lately, so a mesh drawn
/// every frame is searched once. A mesh is a value with no identity, so an
/// entry keeps the mesh's own position and index arrays and is found by
/// comparing them: the same arrays answer at once (an array compares its
/// storage before its elements), an equal rebuilt mesh answers after one pass
/// over them, and a mesh changed in place no longer shares the kept storage,
/// so it compares unequal and is searched again.
struct FeatureEdgeCache {
    private struct Entry {
        var positions: [Vector3]
        var indices: [UInt32]
        var creaseAngle: Double
        var set: FeatureEdgeSet
    }
    private var entries: [Entry] = []
    /// How many meshes are kept; the least recently drawn goes first.
    static let capacity = 16

    mutating func edges(of mesh: Mesh, creaseAngle: Double) -> FeatureEdgeSet {
        if let i = entries.lastIndex(where: { $0.creaseAngle == creaseAngle
                && $0.positions.count == mesh.positions.count && $0.indices.count == mesh.indices.count
                && $0.positions == mesh.positions && $0.indices == mesh.indices }) {
            let entry = entries.remove(at: i)
            entries.append(entry)
            return entry.set
        }
        let set = FeatureEdgeSet.find(in: mesh, creaseAngle: creaseAngle)
        entries.append(Entry(positions: mesh.positions, indices: mesh.indices,
                             creaseAngle: creaseAngle, set: set))
        if entries.count > FeatureEdgeCache.capacity { entries.removeFirst() }
        return set
    }

    /// How many meshes have their edges kept (for the tests).
    var count: Int { entries.count }
}

extension Drawer {

    /// The copies a mesh's edges ride: a run of the frame's placements, or a
    /// buffer of them a compute kernel writes.
    enum EdgeCopies {
        case list(start: Int, count: Int)
        case buffer(ComputeBindable, count: Int)
    }

    func featureEdges(creaseAngle: Double) {
        featureEdgeAngle = creaseAngle.isFinite ? creaseAngle : .pi / 6
    }

    func noFeatureEdges() { featureEdgeAngle = nil }

    /// Record the feature edges of `mesh` over the copies the solid draw just
    /// placed, as a `.lines3D` batch right after it. Nothing is recorded when
    /// the state is off, the stroke is off, or the mesh has no edge to draw.
    func recordFeatureEdges(of mesh: Mesh, copies: EdgeCopies, bounds: Box3?) {
        guard let angle = featureEdgeAngle, let stroke = strokePaint, strokeWidth > 0 else { return }
        let color: Color
        switch stroke {
        case .color(let c): color = c
        case .gradient(let g):
            noteOnce("feature edges take one color; a gradient stroke draws them in the color at the middle of its ramp.")
            color = g.ramp.color(at: 0.5)
        }
        if strokeDashPattern != nil || strokeBrushShape != nil || !strokeProfileShape.isUniform {
            noteOnce("strokeDash, strokeBrush, and strokeProfile shape 2D strokes; a mesh's feature edges draw whole, at one weight.")
        }
        let set = featureEdgeCache.edges(of: mesh, creaseAngle: angle)
        guard !set.edges.isEmpty else { return }
        var style = OllinEdgeStyle()
        style.color = color.simd4
        style.halfWidth = Float(strokeWidth / 2)
        style.worldUnits = strokeUnitsMode == .world ? 1 : 0
        style.closed = set.isClosed ? 1 : 0
        var batch = GeometryBatch(kind: .lines3D, vertexStart: vertices.count,
                                  instanceStart: sdfInstances.count,
                                  imageStart: imageVertices.count,
                                  glyphStart: glyphVertices.count,
                                  pointStart: points.count,
                                  meshStart: meshVertices.count,
                                  sdfGroupStart: sdfGroups.count,
                                  sdf3DGroupStart: sdf3DGroups.count,
                                  blendMode: currentBlend,
                                  target: currentTarget, clipLevel: activeClipLevel)
        switch copies {
        case .list(let start, let count):
            guard count > 0 else { return }
            batch.meshInstanceStart = start
            batch.meshInstanceCount = count
        case .buffer(let buffer, let count):
            guard count > 0 else { return }
            batch.particleBuffer = buffer
            batch.particleCount = count
        }
        batch.edgeSet = set
        batch.edgeStyle = style
        batch.worldBounds = bounds
        batches.append(batch)
        currentKind = nil
    }
}
