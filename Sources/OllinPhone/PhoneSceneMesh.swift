import Foundation
import simd
import Ollin

/// One block of the room the phone has reconstructed, already placed in ARKit's
/// fixed world space (meters). ARKit divides a scan into blocks and keeps improving
/// each one as you walk around, so a block arrives again and again under the same
/// `id` with a better mesh; `PhoneSceneMesh` keeps the newest of each.
///
/// `surfaces` carries one label per triangle (a wall, the floor, a table), so a
/// sketch can treat parts of the room differently. It is empty when the phone is
/// scanning without classification, and most triangles read `unclassified` early in
/// a scan, before ARKit has decided what it is looking at.
public struct PhoneSceneChunk: Sendable, Identifiable {

    /// The block's stable identity, so a better version replaces it in place.
    public let id: UUID
    /// Vertex positions in ARKit's world space, meters.
    public let positions: [Vector3]
    /// Unit surface normals, paired with `positions` by index.
    public let normals: [Vector3]
    /// A triangle list: three indices into `positions` per triangle.
    public let indices: [UInt32]
    /// What the phone thinks each triangle is, one per triangle. Empty when the
    /// scan carries no classification.
    public let surfaces: [PhoneSurface]

    /// The box this block fills, worked out once when it is built. A room holds a
    /// few hundred blocks and several hundred thousand vertices, so framing a camera
    /// on the whole scan folds these boxes rather than walking the vertices again.
    public let bounds: Box3

    /// A block built by hand, in world space. The phone fills these in, and this
    /// is here so a room can also come from somewhere else: a scan you saved and
    /// reloaded, a stand-in room to develop a sketch against with no phone
    /// attached, or a test.
    public init(id: UUID, positions: [Vector3], normals: [Vector3],
                indices: [UInt32], surfaces: [PhoneSurface]) {
        self.id = id
        self.positions = positions
        self.normals = normals
        self.indices = indices
        self.surfaces = surfaces

        var lo = positions.first ?? .zero, hi = positions.first ?? .zero
        for p in positions {
            lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        bounds = Box3(min: lo, max: hi)
    }

    /// The number of triangles in this block.
    public var triangleCount: Int { indices.count / 3 }

    /// This block on its own as a drawable `Mesh`. Reach for `PhoneSceneMesh.mesh`
    /// to draw the whole room at once.
    public var mesh: Mesh {
        Mesh(positions: positions, normals: normals, indices: indices)
    }
}

/// The room the phone has scanned so far: a set of reconstructed blocks that grows
/// and sharpens as you carry the phone around, ready to draw as one `Mesh`.
///
/// A depth frame is a single slice of what the lens can see, and `WorldCloud` fuses
/// a sweep of those slices into points. This is the other half of the same idea, but
/// the phone does the work: ARKit builds a real triangle surface of the room on the
/// device and streams it block by block, so what arrives is already a mesh with
/// normals, and already labeled by what each triangle is.
///
/// ```swift
/// let device = PhoneDevice()
/// var room = Mesh(positions: [], indices: [])
/// var built: Int?
///
/// override func draw() {
///     // Rebuild only when a block actually changed; the mesh is large.
///     if device.sceneMeshVersion != built {
///         built = device.sceneMeshVersion
///         room = device.sceneMesh.mesh
///     }
///     drawMesh(room)
/// }
/// ```
///
/// Blocks keep their arrival order, so the combined mesh is stable frame to frame
/// and only changes where the scan changed.
public struct PhoneSceneMesh: Sendable {

    /// Every block scanned so far, in the order the phone first reported them.
    public private(set) var chunks: [PhoneSceneChunk] = []

    /// Where each block sits in `chunks`, so a repeat report overwrites in place.
    private var index: [UUID: Int] = [:]

    /// An empty room, before any block arrives.
    public init() {}

    // MARK: Accumulating

    /// Take a block: replace the one with the same `id`, or add it if it is new.
    public mutating func apply(_ chunk: PhoneSceneChunk) {
        if let at = index[chunk.id] {
            chunks[at] = chunk
        } else {
            index[chunk.id] = chunks.count
            chunks.append(chunk)
        }
    }

    /// Drop the block with this `id`, if it is here. The phone retires a block when
    /// it merges it into a neighbor or decides it was wrong.
    public mutating func remove(_ id: UUID) {
        guard let at = index.removeValue(forKey: id) else { return }
        chunks.remove(at: at)
        // Every later block shifted down by one, so the map is rebuilt. Removals are
        // rare next to updates, and a room holds a few hundred blocks at most.
        for i in at..<chunks.count { index[chunks[i].id] = i }
    }

    /// Forget the whole scan, keeping the allocation. Start a fresh room.
    public mutating func reset() {
        chunks.removeAll(keepingCapacity: true)
        index.removeAll(keepingCapacity: true)
    }

    // MARK: Reading

    /// The number of blocks scanned so far.
    public var chunkCount: Int { chunks.count }
    /// Whether anything has been scanned yet.
    public var isEmpty: Bool { chunks.isEmpty }
    /// The total number of vertices across every block.
    public var vertexCount: Int { chunks.reduce(0) { $0 + $1.positions.count } }
    /// The total number of triangles across every block.
    public var triangleCount: Int { chunks.reduce(0) { $0 + $1.triangleCount } }

    /// Which labels the scan has actually produced, in `PhoneSurface` order. Useful
    /// for a legend, or to see whether classification is running at all.
    public var foundSurfaces: Set<PhoneSurface> {
        var found = Set<PhoneSurface>()
        for chunk in chunks { found.formUnion(chunk.surfaces) }
        return found
    }

    /// The axis-aligned box the whole scan fills, as `min` and `max` corners
    /// (`.zero` before anything arrives). The room's own extent, so a
    /// camera can frame it. Each block already knows its own box, so this folds a
    /// few hundred boxes rather than walking every vertex, and is cheap to read
    /// every frame.
    public var bounds: Box3 {
        var box: Box3?
        for chunk in chunks where !chunk.positions.isEmpty {
            box = box.map { $0.union(chunk.bounds) } ?? chunk.bounds
        }
        return box ?? .zero
    }

    /// The middle of `bounds`, the point to aim a camera at.
    public var center: Vector3 { let b = bounds; return (b.min + b.max) * 0.5 }

    // MARK: Drawing

    /// The whole scan as one `Mesh`, in ARKit's world space (meters). Building it
    /// walks every block, so rebuild it when `PhoneDevice.sceneMeshVersion` changes
    /// rather than once per frame.
    public var mesh: Mesh {
        var positions: [Vector3] = [], normals: [Vector3] = [], indices: [UInt32] = []
        positions.reserveCapacity(vertexCount)
        normals.reserveCapacity(vertexCount)
        indices.reserveCapacity(triangleCount * 3)
        for chunk in chunks {
            let base = UInt32(positions.count)
            positions.append(contentsOf: chunk.positions)
            normals.append(contentsOf: chunk.normals)
            for i in chunk.indices { indices.append(base + i) }
        }
        // Normals pair with positions by index, so a block that arrived without them
        // would shift every later block's. It is all or nothing.
        return Mesh(positions: positions,
                    normals: normals.count == positions.count ? normals : [],
                    indices: indices)
    }

    /// Just the parts of the room the phone labeled as one of `wanted`: the floor
    /// on its own, or every seat, or the walls and the ceiling together. A triangle
    /// keeps its vertices, and a vertex no kept triangle uses is dropped, so the
    /// result is as small as the selection.
    ///
    /// ```swift
    /// drawMesh(device.sceneMesh.mesh(of: .floor, .table))
    /// ```
    ///
    /// A scan with no classification has no labels to match, so this returns an
    /// empty mesh; check `foundSurfaces` when nothing shows up.
    public func mesh(of wanted: PhoneSurface...) -> Mesh {
        mesh(of: Set(wanted))
    }

    /// Just the parts of the room labeled as one of `wanted`, taking a set (the
    /// variadic `mesh(of:)` is the everyday form).
    public func mesh(of wanted: Set<PhoneSurface>) -> Mesh {
        var positions: [Vector3] = [], normals: [Vector3] = [], indices: [UInt32] = []
        for chunk in chunks {
            guard !chunk.surfaces.isEmpty else { continue }
            // Only the vertices a kept triangle reaches travel, so a selection of a
            // few triangles carries a few vertices rather than the whole block.
            var moved: [UInt32: UInt32] = [:]
            for triangle in 0..<chunk.triangleCount where wanted.contains(surface(chunk, triangle)) {
                for corner in 0..<3 {
                    let source = chunk.indices[triangle * 3 + corner]
                    if let already = moved[source] {
                        indices.append(already)
                    } else {
                        let at = UInt32(positions.count)
                        moved[source] = at
                        positions.append(chunk.positions[Int(source)])
                        if Int(source) < chunk.normals.count { normals.append(chunk.normals[Int(source)]) }
                        indices.append(at)
                    }
                }
            }
        }
        // A partial normal set would pair wrongly by index, so it is all or nothing.
        return Mesh(positions: positions,
                    normals: normals.count == positions.count ? normals : [],
                    indices: indices)
    }

    /// The whole scan as one `Mesh`, painted by what each triangle is: the closure
    /// is asked once per triangle and its color goes on that triangle alone.
    ///
    /// ```swift
    /// drawMesh(device.sceneMesh.mesh { surface in
    ///     switch surface {
    ///     case .floor: return Color(hex: 0x3B7D5A)
    ///     case .wall:  return Color(white: 0.7)
    ///     default:     return Color(white: 0.35)
    ///     }
    /// })
    /// ```
    ///
    /// A color belongs to a whole triangle, and Ollin's mesh colors belong to
    /// vertices, so each triangle here gets its own three vertices. That makes this
    /// mesh about three times the size of `mesh`, which is the price of a flat
    /// color per face. A scan with no classification paints everything
    /// `unclassified`.
    public func mesh(colored color: (PhoneSurface) -> Color) -> Mesh {
        var positions: [Vector3] = [], normals: [Vector3] = []
        var indices: [UInt32] = [], colors: [Color] = []
        let corners = triangleCount * 3
        positions.reserveCapacity(corners)
        normals.reserveCapacity(corners)
        indices.reserveCapacity(corners)
        colors.reserveCapacity(corners)
        for chunk in chunks {
            let hasNormals = chunk.normals.count == chunk.positions.count
            for triangle in 0..<chunk.triangleCount {
                let paint = color(surface(chunk, triangle))
                for corner in 0..<3 {
                    let source = Int(chunk.indices[triangle * 3 + corner])
                    guard source < chunk.positions.count else { continue }
                    indices.append(UInt32(positions.count))
                    positions.append(chunk.positions[source])
                    if hasNormals { normals.append(chunk.normals[source]) }
                    colors.append(paint)
                }
            }
        }
        return Mesh(positions: positions,
                    normals: normals.count == positions.count ? normals : [],
                    indices: indices, colors: colors)
    }

    /// One triangle's label, falling back to `unclassified` for a scan that carries
    /// none.
    private func surface(_ chunk: PhoneSceneChunk, _ triangle: Int) -> PhoneSurface {
        triangle < chunk.surfaces.count ? chunk.surfaces[triangle] : .unclassified
    }
}

/// Place a wire block into ARKit's world space: the anchor reports its mesh around
/// its own origin, and its `transform` says where that origin sits in the room.
///
/// The transform is rigid (a turn and a move, never a squash), so a normal takes the
/// rotation alone. Returns `nil` for a block with no triangles, which is nothing to
/// draw.
///
/// Free function (not a method) so the reader thread calls it without main-actor
/// isolation, the way the depth and segmentation decoders do.
func phoneSceneChunk(from sample: PhoneSceneMeshSample) -> PhoneSceneChunk? {
    guard !sample.isRemoved, !sample.vertices.isEmpty, sample.triangleIndices.count >= 3 else { return nil }

    let m = sample.transform
    let positions = sample.vertices.map { v -> Vector3 in
        let w = m * SIMD4<Float>(v.x, v.y, v.z, 1)
        return Vector3(Double(w.x), Double(w.y), Double(w.z))
    }
    let normals = sample.normals.map { n -> Vector3 in
        // w = 0 drops the move, so only the turn reaches a direction.
        let w = m * SIMD4<Float>(n.x, n.y, n.z, 0)
        let length = (w.x * w.x + w.y * w.y + w.z * w.z).squareRoot()
        guard length > 1e-9 else { return Vector3(0, 1, 0) }
        return Vector3(Double(w.x / length), Double(w.y / length), Double(w.z / length))
    }

    // An index past the end would read off the end of the vertex list when the mesh
    // draws, so a block that does not agree with itself is dropped whole.
    let limit = UInt32(positions.count)
    let usable = sample.triangleIndices.count - sample.triangleIndices.count % 3
    var indices = [UInt32](); indices.reserveCapacity(usable)
    for i in 0..<usable {
        guard sample.triangleIndices[i] < limit else { return nil }
        indices.append(sample.triangleIndices[i])
    }

    let surfaces = sample.surfaces
    return PhoneSceneChunk(id: sample.id, positions: positions,
                           normals: normals.count == positions.count ? normals : [],
                           indices: indices, surfaces: surfaces)
}
