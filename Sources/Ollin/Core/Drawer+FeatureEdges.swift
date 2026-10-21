// Drawer, a mesh's feature edges (`featureEdges(creaseAngle:)`): the faces draw
// as they always do, and the edges where two faces meet at an angle, where the
// surface ends, or where it turns away from the eye draw over them in the
// stroke. A mesh's edges are found once and kept on the GPU; each frame a draw
// records only a batch that points at them and at the copies the solid draw
// placed, and the vertex shader (`ollin_edge_vertex`) does the rest per copy.

import Foundation
import os
import Metal
import simd
import COllinShaders

/// The feature edges of one mesh at one crease angle, kept for every frame
/// that draws the mesh again, with the GPU buffer made from them the first
/// time a frame needs it. Nothing in it changes once it is made, so a frame
/// still in flight can go on reading the buffer while a later one draws.
///
/// The edges sit in page-aligned memory the buffer wraps rather than copies:
/// a mesh rebuilt every frame finds its edges anew each frame, and a million
/// vertices make a few hundred megabytes of them, which a copy would write
/// twice. The memory outlives the set for as long as the buffer does, so a
/// frame the GPU is still reading keeps it.
final class FeatureEdgeSet {
    /// Page-aligned memory holding the edges, freed with the last of the set
    /// and its buffer.
    private final class Rows: @unchecked Sendable {
        let base: UnsafeMutablePointer<OllinMeshEdge>
        let count: Int
        /// The allocation's length: the edges rounded up to whole pages.
        let length: Int

        init(count: Int, _ write: (UnsafeMutablePointer<OllinMeshEdge>) -> Void) {
            let page = Int(getpagesize())
            let bytes = Swift.max(count * MemoryLayout<OllinMeshEdge>.stride, 1)
            length = (bytes + page - 1) / page * page
            var raw: UnsafeMutableRawPointer?
            guard posix_memalign(&raw, page, length) == 0, let raw else {
                fatalError("Ollin: could not set aside \(length) bytes for a mesh's feature edges")
            }
            base = raw.bindMemory(to: OllinMeshEdge.self, capacity: count)
            self.count = count
            write(base)
        }

        deinit { free(base) }
    }

    private let rows: Rows
    /// Whether every edge has a face on both sides: on a closed mesh, a crease
    /// whose faces both turn away is behind the mesh's own front, and is skipped.
    let isClosed: Bool
    private var buffer: MTLBuffer?

    /// `count` edges, each written once by `write` into the memory the set keeps.
    init(count: Int, isClosed: Bool, _ write: (UnsafeMutablePointer<OllinMeshEdge>) -> Void) {
        rows = Rows(count: count, write)
        self.isClosed = isClosed
    }

    /// The edges, valid for as long as the set is.
    var edges: UnsafeBufferPointer<OllinMeshEdge> {
        UnsafeBufferPointer(start: rows.base, count: rows.count)
    }

    func metalBuffer(for device: MTLDevice) -> MTLBuffer? {
        if let buffer, buffer.device === device { return buffer }
        guard rows.count > 0 else { return nil }
        let rows = self.rows
        buffer = device.makeBuffer(bytesNoCopy: rows.base, length: rows.length,
                                   options: .storageModeShared,
                                   deallocator: { _, _ in withExtendedLifetime(rows) {} })
        return buffer
    }

    /// The edges of `mesh` worth drawing at `creaseAngle` (radians): each one
    /// once, its two ends in the mesh's own space and the normals of the faces
    /// on either side. A boundary has one face; a crease two that meet past the
    /// angle (a third face at an edge makes it a crease too, since the surface
    /// branches there); every other shared edge is smooth, kept because it may
    /// be the silhouette from wherever a copy is seen. The faces and how they
    /// meet are `FeatureEdgeTopology`'s; this is its search followed by the
    /// crease test at the mesh's own positions.
    static func find(in mesh: Mesh, creaseAngle: Double) -> FeatureEdgeSet {
        FeatureEdgeTopology.search(mesh).edges(at: mesh.positions, creaseAngle: creaseAngle)!
    }
}

/// How a mesh's faces meet, which is what the edge search spends its time on
/// and what the positions barely touch: the faces it keeps, each edge once with
/// the faces on either side, and whether every edge has two. Corners a mesh
/// holds once per face (hard edges) are welded first, or every edge would be a
/// boundary, and a face whose corners weld into fewer than three points (a
/// sphere's pole, collapsed to a point the arithmetic leaves a hair apart) has
/// no direction and is left out, as is any face with no area.
///
/// The positions decide only each edge's kind, through the normals of its
/// faces, so a mesh rebuilt every frame with its index buffer unchanged (a
/// trail, a surface displaced in place) keeps this and redoes the crease test
/// alone: `edges(at:creaseAngle:validating:)` takes new positions and gives
/// the edges the full search would give, or nil when they would come out
/// otherwise, because two corners welded together came apart, the two ends
/// of an edge came to weld, or a face gained or lost its area. Two parts of
/// the surface that come to touch away from any shared face are not welded
/// until the index buffer changes, where a search from scratch would weld them.
final class FeatureEdgeTopology {
    struct Edge {
        /// The edge's ends, as the first face along it names them.
        var u: Int32
        var v: Int32
        /// The faces on either side (indices into `faces`); `second` is -1 at
        /// a boundary.
        var first: Int32
        var second: Int32
        /// Whether a third face meets the edge, so the surface branches there.
        var branches: Bool
    }

    /// The vertex count the search read.
    let vertexCount: Int
    /// Each corner welded into an earlier one, beside the corner it became.
    let welds: [SIMD2<Int32>]
    /// The faces kept, by their corners.
    let faces: [SIMD3<Int32>]
    /// The faces left out for having no area while their corners weld apart.
    let flat: [SIMD3<Int32>]
    let edges: [Edge]
    let isClosed: Bool

    private init(vertexCount: Int, welds: [SIMD2<Int32>], faces: [SIMD3<Int32>],
                 flat: [SIMD3<Int32>], edges: [Edge], isClosed: Bool) {
        self.vertexCount = vertexCount
        self.welds = welds
        self.faces = faces
        self.flat = flat
        self.edges = edges
        self.isClosed = isClosed
    }

    /// The face's unnormalized normal: its two edges from the first corner, crossed.
    @inline(__always)
    private static func cross(_ face: SIMD3<Int32>, _ positions: UnsafeBufferPointer<Vector3>) -> Vector3 {
        let a = positions[Int(face.x)]
        return (positions[Int(face.y)] - a).cross(positions[Int(face.z)] - a)
    }

    static func search(_ mesh: Mesh) -> FeatureEdgeTopology {
        let positions = mesh.positions
        let welded = LineDrawing.weld(positions)
        var welds: [SIMD2<Int32>] = []
        for (i, w) in welded.enumerated() where w != i { welds.append(SIMD2(Int32(i), Int32(w))) }
        var faces: [SIMD3<Int32>] = []
        var flat: [SIMD3<Int32>] = []
        faces.reserveCapacity(mesh.indices.count / 3)
        positions.withUnsafeBufferPointer { points in
            var index = 0
            while index + 2 < mesh.indices.count {
                let a = Int(mesh.indices[index]), b = Int(mesh.indices[index + 1]), c = Int(mesh.indices[index + 2])
                index += 3
                guard a < points.count, b < points.count, c < points.count else { continue }
                guard welded[a] != welded[b], welded[b] != welded[c], welded[c] != welded[a] else { continue }
                let face = SIMD3<Int32>(Int32(a), Int32(b), Int32(c))
                if cross(face, points).length > 1e-20 { faces.append(face) } else { flat.append(face) }
            }
        }

        struct Sides { var first: Int; var second: Int?; var branches = false }
        var shared: [SIMD2<Int32>: Sides] = [:]
        shared.reserveCapacity(faces.count * 3 / 2)
        var order: [(key: SIMD2<Int32>, u: Int, v: Int)] = []
        order.reserveCapacity(faces.count * 3 / 2)
        for (f, face) in faces.enumerated() {
            let a = Int(face.x), b = Int(face.y), c = Int(face.z)
            for (u, v) in [(a, b), (b, c), (c, a)] {
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

        var edges: [Edge] = []
        edges.reserveCapacity(order.count)
        var closed = true
        for (key, u, v) in order {
            guard let sides = shared[key] else { continue }
            if sides.second == nil { closed = false }
            edges.append(Edge(u: Int32(u), v: Int32(v), first: Int32(sides.first),
                              second: Int32(sides.second ?? -1), branches: sides.branches))
        }
        return FeatureEdgeTopology(vertexCount: positions.count, welds: welds, faces: faces,
                                   flat: flat, edges: edges, isClosed: closed)
    }

    /// The edges at `positions` and `creaseAngle` (radians), from these faces.
    /// `validating` first checks that the positions meet as the ones searched
    /// did (see the type's notes) and answers nil when they would not; the
    /// search's own positions need no check. Each pass is one independent
    /// step per vertex, face, or edge, so a large mesh spreads them across
    /// the cores, each core a run of its own.
    func edges(at positions: [Vector3], creaseAngle: Double,
               validating: Bool = false) -> FeatureEdgeSet? {
        guard positions.count == vertexCount else { return nil }
        return positions.withUnsafeBufferPointer { points -> FeatureEdgeSet? in
            if validating {
                let grain = LineDrawing.weldGrain(positions)
                let keys = [SIMD3<Int64>](unsafeUninitializedCapacity: points.count) { buffer, count in
                    nonisolated(unsafe) let out = buffer.baseAddress!
                    FeatureEdgeTopology.inRuns(points.count) { run in
                        for i in run { out[i] = LineDrawing.weldKey(points[i], grain: grain) }
                    }
                    count = points.count
                }
                let welded = keys.withUnsafeBufferPointer { keys in
                    FeatureEdgeTopology.allInRuns(welds.count) { run in
                        welds.withUnsafeBufferPointer { welds in
                            run.allSatisfy { keys[Int(welds[$0].x)] == keys[Int(welds[$0].y)] }
                        }
                    } && FeatureEdgeTopology.allInRuns(edges.count) { run in
                        edges.withUnsafeBufferPointer { edges in
                            run.allSatisfy { keys[Int(edges[$0].u)] != keys[Int(edges[$0].v)] }
                        }
                    }
                }
                guard welded, !flat.contains(where: { FeatureEdgeTopology.cross($0, points).length > 1e-20 })
                else { return nil }
            }
            var normals = [Vector3](repeating: .zero, count: faces.count)
            let kept = normals.withUnsafeMutableBufferPointer { buffer in
                nonisolated(unsafe) let out = buffer.baseAddress!
                return faces.withUnsafeBufferPointer { faces in
                    FeatureEdgeTopology.allInRuns(faces.count) { run in
                        for f in run {
                            let cross = FeatureEdgeTopology.cross(faces[f], points)
                            let area = cross.length
                            if !(area > 1e-20) { return false }
                            out[f] = cross / area
                        }
                        return true
                    }
                }
            }
            guard kept else { return nil }

            let creaseLimit = cos(min(max(creaseAngle, 0), .pi))
            @inline(__always) func row(_ v: Vector3, _ w: Float = 0) -> SIMD4<Float> {
                SIMD4<Float>(Float(v.x), Float(v.y), Float(v.z), w)
            }
            return normals.withUnsafeBufferPointer { normals in
                edges.withUnsafeBufferPointer { edges in
                    FeatureEdgeSet(count: edges.count, isClosed: isClosed) { buffer in
                        nonisolated(unsafe) let out = buffer
                        FeatureEdgeTopology.inRuns(edges.count) { run in
                            for i in run {
                                let edge = edges[i]
                                let first = normals[Int(edge.first)]
                                let kind: Float
                                let second: Vector3
                                if edge.second >= 0 {
                                    second = normals[Int(edge.second)]
                                    kind = edge.branches || creaseAngle <= 0 || first.dot(second) < creaseLimit ? 1 : 2
                                } else {
                                    second = first
                                    kind = 0
                                }
                                (out + i).initialize(to: OllinMeshEdge(a: row(points[Int(edge.u)], kind),
                                                                       b: row(points[Int(edge.v)]),
                                                                       normal0: row(first), normal1: row(second)))
                            }
                        }
                    }
                }
            }
        }
    }

    /// The runs a pass over `count` items splits into: one below a size where
    /// threads cost more than they save, else about two a core.
    private static func runs(_ count: Int) -> [Range<Int>] {
        let pieces = count < 1 << 16 ? 1 : min(2 * ProcessInfo.processInfo.activeProcessorCount, count >> 15)
        return (0 ..< pieces).map { count * $0 / pieces ..< count * ($0 + 1) / pieces }
    }

    /// `body` over every run of `0 ..< count`, side by side when there are several.
    private static func inRuns(_ count: Int, _ body: (Range<Int>) -> Void) {
        let pieces = runs(count)
        if pieces.count == 1 { body(pieces[0]); return }
        withoutActuallyEscaping(body) { body in
            nonisolated(unsafe) let body = body
            DispatchQueue.concurrentPerform(iterations: pieces.count) { body(pieces[$0]) }
        }
    }

    /// Whether `test` holds over every run of `0 ..< count`, the runs side by side.
    private static func allInRuns(_ count: Int, _ test: (Range<Int>) -> Bool) -> Bool {
        let pieces = runs(count)
        if pieces.count == 1 { return test(pieces[0]) }
        let failed = OSAllocatedUnfairLock(initialState: false)
        withoutActuallyEscaping(test) { test in
            nonisolated(unsafe) let test = test
            DispatchQueue.concurrentPerform(iterations: pieces.count) {
                if !test(pieces[$0]) { failed.withLock { $0 = true } }
            }
        }
        return !failed.withLock { $0 }
    }
}

/// The edge sets of the meshes a sketch has drawn lately, so a mesh drawn
/// every frame is searched once. A mesh is a value with no identity, so an
/// entry keeps the mesh's own position and index arrays and is found by
/// comparing them: the same arrays answer at once (an array compares its
/// storage before its elements), and an equal rebuilt mesh answers after one
/// pass over them. A mesh whose positions moved while its index buffer held
/// reuses the entry's `FeatureEdgeTopology` and takes the entry over, so a
/// mesh rebuilt every frame holds one entry rather than filling the cache
/// with frames past; an entry another mesh already drew from this frame is
/// left to it and a new one shares its topology. Anything else, or a mesh whose
/// corners no longer meet as they did, is searched again.
struct FeatureEdgeCache {
    private struct Entry {
        var positions: [Vector3]
        var indices: [UInt32]
        var creaseAngle: Double
        var topology: FeatureEdgeTopology
        var set: FeatureEdgeSet
        /// The frame that last drew from the entry.
        var frame: UInt64
    }
    private var entries: [Entry] = []
    private var frame: UInt64 = 0
    /// How many meshes are kept; the least recently drawn goes first.
    static let capacity = 16

    /// Start a frame, so an entry drawn from earlier can be taken over by a
    /// mesh that moved and one drawn from this frame cannot.
    mutating func beginFrame() { frame &+= 1 }

    mutating func edges(of mesh: Mesh, creaseAngle: Double) -> FeatureEdgeSet {
        if let i = entries.lastIndex(where: { $0.creaseAngle == creaseAngle
                && $0.positions.count == mesh.positions.count && $0.indices.count == mesh.indices.count
                && $0.positions == mesh.positions && $0.indices == mesh.indices }) {
            var entry = entries.remove(at: i)
            entry.frame = frame
            entries.append(entry)
            return entry.set
        }
        // The same faces with the corners moved: the newest entry over this
        // index buffer, preferring one no other mesh has drawn from this frame.
        let sameFaces = entries.indices.reversed().filter {
            entries[$0].positions.count == mesh.positions.count
                && entries[$0].indices.count == mesh.indices.count && entries[$0].indices == mesh.indices
        }
        if let i = sameFaces.first(where: { entries[$0].frame != frame }) ?? sameFaces.first,
           let set = entries[i].topology.edges(at: mesh.positions, creaseAngle: creaseAngle,
                                               validating: true) {
            var entry = entries[i]
            if entry.frame != frame { entries.remove(at: i) }   // taken over, not copied
            entry.positions = mesh.positions
            entry.creaseAngle = creaseAngle
            entry.set = set
            entry.frame = frame
            insert(entry)
            return set
        }
        let topology = FeatureEdgeTopology.search(mesh)
        searches += 1
        let set = topology.edges(at: mesh.positions, creaseAngle: creaseAngle)!
        insert(Entry(positions: mesh.positions, indices: mesh.indices, creaseAngle: creaseAngle,
                     topology: topology, set: set, frame: frame))
        return set
    }

    private mutating func insert(_ entry: Entry) {
        entries.append(entry)
        if entries.count > FeatureEdgeCache.capacity { entries.removeFirst() }
    }

    /// How many meshes have their edges kept (for the tests).
    var count: Int { entries.count }
    /// How many times a mesh's faces were searched from scratch (for the tests).
    private(set) var searches = 0
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
        case .shader:
            noteOnce("feature edges take one color; a shader stroke draws them white.")
            color = .white
        }
        if strokeDashPattern != nil || strokeBrushShape != nil || strokeMediumShape != nil
            || !strokeProfileShape.isUniform {
            noteOnce("strokeDash, strokeBrush, strokeMedium, and strokeProfile shape 2D strokes; a mesh's feature edges draw whole, plain, at one weight.")
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
