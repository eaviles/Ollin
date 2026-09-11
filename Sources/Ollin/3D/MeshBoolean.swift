import Foundation

/// Boolean set operations on solid meshes: the same four operations `Shape`
/// offers on a filled 2D region, carried into space.
///
/// ```swift
/// let slab = Mesh.box(width: 2, height: 0.4, depth: 1)
/// let hole = Mesh.cylinder(radius: 0.3, height: 2, segments: 48)
/// let drilled = slab.subtracting(hole)
/// drawMesh(drilled)
/// ```
///
/// These make real geometry. The result is a `Mesh` like any other, so it can
/// be drawn, exported for a printer, broken with `fractured(into:)`, or handed
/// to the solver as a collider. That is the difference from the
/// `union { }` / `subtract { }` blocks, which merge distance fields on the GPU
/// while the frame is drawn and leave no triangles behind.
///
/// **A boolean needs solids.** Each side has to be a closed surface, or there
/// is no inside for the operation to reason about, and what comes back is
/// meaningless rather than wrong-looking. `printCheck()` is the examination
/// that tells you whether a mesh closes. The generators all do.
///
/// **Do the work once.** Cutting one solid with another is CPU geometry, not a
/// draw call, so build the result in `setup()` (or when a parameter changes)
/// and draw the mesh you kept, rather than cutting every frame.
public extension Mesh {

    /// The solid covered by this mesh, the other, or both.
    ///
    /// Overlapping material is merged rather than doubled, so the seam between
    /// the two disappears and the result encloses their combined volume once.
    ///
    /// The result keeps this mesh's `material`. Texture coordinates and vertex
    /// colors survive when *both* meshes carry a full set, since half a set
    /// would be ignored by the renderer anyway. Tangents are dropped, so call
    /// `generatingTangents()` afterward if a normal map reads from them.
    func union(_ other: Mesh) -> Mesh {
        guard !isEmpty else { return other }
        guard !other.isEmpty else { return self }
        return MeshCSG.combine(self, other, as: .union)
    }

    /// The solid covered by both this mesh and the other: the overlap alone.
    ///
    /// Two solids that do not touch intersect in nothing, and the result is an
    /// empty mesh.
    func intersection(_ other: Mesh) -> Mesh {
        guard !isEmpty, !other.isEmpty else { return Mesh(positions: [], indices: []) }
        return MeshCSG.combine(self, other, as: .intersection)
    }

    /// This solid with the other cut out of it.
    ///
    /// The cut leaves the other mesh's surface behind as the wall of the cavity,
    /// facing inward, which is what makes a drilled hole look drilled. A cutter
    /// that misses entirely leaves this mesh alone.
    func subtracting(_ other: Mesh) -> Mesh {
        guard !isEmpty else { return Mesh(positions: [], indices: []) }
        guard !other.isEmpty else { return self }
        return MeshCSG.combine(self, other, as: .difference)
    }

    /// The solid covered by exactly one of the two meshes: their union with the
    /// overlap taken back out.
    ///
    /// Where they overlap, nothing is left, so two crossing bars come back as
    /// four stumps and a hole where they met.
    func symmetricDifference(_ other: Mesh) -> Mesh {
        guard !isEmpty else { return other }
        guard !other.isEmpty else { return self }
        return subtracting(other).union(other.subtracting(self))
    }
}

// MARK: - The cut itself

/// Cutting one solid with another by merging their binary space partitions.
///
/// The technique is Naylor, Amanatides and Thibault's ("Merging BSP Trees
/// Yields Polyhedral Set Operations", SIGGRAPH 1990), written from the method:
/// each solid becomes a tree of planes taken from its own faces, which sorts
/// any polygon into the part of space that is inside the solid and the part
/// that is outside. Clipping one solid's faces against the other's tree then
/// throws away exactly the half of each surface the operation does not want,
/// and the two surviving surfaces are joined into one tree at the end.
///
/// The whole of each operation is which halves are kept, which is what
/// `invert` decides: inverting a tree turns its solid inside out, so the same
/// clip that keeps what is outside now keeps what is inside.
enum MeshCSG {

    enum Operation {
        case union, intersection, difference
    }

    static func combine(_ a: Mesh, _ b: Mesh, as operation: Operation) -> Mesh {
        // One scale for both solids: the plane thickness that decides whether a
        // corner is on a plane or across it has to mean the same thing in both
        // trees, or a face lands on one side in one tree and the other side in
        // the other, which is how a closed surface opens.
        let bounds = a.bounds.union(b.bounds)
        let scale = Swift.max(bounds.longestSide, 1e-12)
        let epsilon = scale * 1e-9
        let areaFloor = scale * scale * 1e-18

        // Both sides must carry a full set, or the renderer ignores what comes
        // out. Half a set of texture coordinates is worse than none: it reads as
        // a mesh that should map and does not.
        let uvs = a.uvs.count == a.positions.count && b.uvs.count == b.positions.count
        let colors = a.colors.count == a.positions.count && b.colors.count == b.positions.count

        // Two solids whose boxes miss cannot meet, and the answer is one of
        // them, both of them, or neither. Worth its own branch rather than its
        // own tree: planes are unbounded, so a cutter on the far side of the
        // room still runs its six planes through everything, and a surface
        // comes back carved into pieces along seams that were never a cut.
        if apart(a.bounds, b.bounds, by: scale * 1e-6) {
            switch operation {
            case .union: return both(a, b, uvs: uvs, colors: colors)
            case .intersection: return Mesh(positions: [], indices: [])
            case .difference: return a
            }
        }

        var solidA = CSGTree(epsilon: epsilon)
        solidA.build(polygons(of: a, uvs: uvs, colors: colors, areaFloor: areaFloor))
        var solidB = CSGTree(epsilon: epsilon)
        solidB.build(polygons(of: b, uvs: uvs, colors: colors, areaFloor: areaFloor))

        switch operation {
        case .union:
            // Each surface loses the part buried inside the other. The second
            // clip runs against the inverted solid so the faces that merely
            // touch (coincident walls) are kept once rather than twice.
            solidA.clip(to: solidB)
            solidB.clip(to: solidA)
            solidB.invert()
            solidB.clip(to: solidA)
            solidB.invert()
        case .intersection:
            // Keep what each surface has inside the other, which is the same
            // clip with both solids turned inside out around it.
            solidA.invert()
            solidB.clip(to: solidA)
            solidB.invert()
            solidA.clip(to: solidB)
            solidB.clip(to: solidA)
        case .difference:
            // The cutter's surface is kept facing inward, so it becomes the
            // wall of the cavity rather than a second skin over it.
            solidA.invert()
            solidA.clip(to: solidB)
            solidB.clip(to: solidA)
            solidB.invert()
            solidB.clip(to: solidA)
            solidB.invert()
        }

        solidA.build(solidB.allPolygons())
        if operation != .union { solidA.invert() }

        // The cut is geometrically complete here and topologically is not: a
        // corner one face gained from a plane lands in the middle of the
        // neighboring face's edge, which is a crack to everything that reads a
        // mesh as a connected surface. Sewing those up is what makes the result
        // a solid rather than a bag of triangles that happens to look shut.
        let cut = triangles(of: solidA.allPolygons())
        return CSGSeam.sealed(cut, tolerance: scale * 1e-6, like: a, uvs: uvs, colors: colors)
    }

    /// Whether the two boxes are clear of each other by more than `margin`.
    ///
    /// Solids that merely touch are not apart: two boxes sharing a wall have to
    /// go through the cut, or the shared wall survives on both of them and the
    /// pair reads as a surface meeting itself.
    private static func apart(_ a: Box3, _ b: Box3, by margin: Double) -> Bool {
        a.max.x < b.min.x - margin || b.max.x < a.min.x - margin
            || a.max.y < b.min.y - margin || b.max.y < a.min.y - margin
            || a.max.z < b.min.z - margin || b.max.z < a.min.z - margin
    }

    /// Two solids side by side in one mesh, each keeping its own surface.
    private static func both(_ a: Mesh, _ b: Mesh, uvs: Bool, colors: Bool) -> Mesh {
        let shift = UInt32(a.positions.count)
        let normals = a.normals.count == a.positions.count && b.normals.count == b.positions.count
        return Mesh(positions: a.positions + b.positions,
                    normals: normals ? a.normals + b.normals : [],
                    indices: a.indices + b.indices.map { $0 + shift },
                    uvs: uvs ? a.uvs + b.uvs : [],
                    colors: colors ? a.colors + b.colors : [],
                    material: a.material)
    }

    /// Every triangle of a mesh as a polygon carrying its own plane.
    ///
    /// A triangle with no area has no plane, so it is dropped here rather than
    /// handing the tree a normal made of rounding error.
    private static func polygons(of mesh: Mesh, uvs: Bool, colors: Bool,
                                 areaFloor: Double) -> [CSGPolygon] {
        let smoothed = mesh.normals.count == mesh.positions.count
        var built: [CSGPolygon] = []
        built.reserveCapacity(mesh.triangleCount)
        var i = 0
        while i + 2 < mesh.indices.count {
            let corner = (Int(mesh.indices[i]), Int(mesh.indices[i + 1]), Int(mesh.indices[i + 2]))
            let a = mesh.positions[corner.0], b = mesh.positions[corner.1], c = mesh.positions[corner.2]
            let cross = (b - a).cross(c - a)
            i += 3
            guard cross.lengthSquared > areaFloor * areaFloor else { continue }
            let face = cross.normalized
            let vertices = [corner.0, corner.1, corner.2].map { index in
                CSGVertex(position: mesh.positions[index],
                          normal: smoothed ? mesh.normals[index] : face,
                          uv: uvs ? mesh.uvs[index] : .zero,
                          color: colors ? mesh.colors[index] : .white)
            }
            built.append(CSGPolygon(vertices: vertices,
                                    plane: CSGPlane(normal: face, offset: face.dot(a))))
        }
        return built
    }

    /// The surviving polygons as triangles, each polygon fanned from its first
    /// corner.
    ///
    /// Every polygon a cut leaves is convex (it is a face trimmed by planes), so
    /// a fan from one corner covers it exactly.
    private static func triangles(of polygons: [CSGPolygon]) -> [CSGTriangle] {
        var built: [CSGTriangle] = []
        built.reserveCapacity(polygons.count)
        for polygon in polygons where polygon.vertices.count >= 3 {
            let first = polygon.vertices[0]
            for corner in 1 ..< polygon.vertices.count - 1 {
                built.append(CSGTriangle(a: first,
                                         b: polygon.vertices[corner],
                                         c: polygon.vertices[corner + 1]))
            }
        }
        return built
    }
}

// MARK: - Pieces of surface

/// A corner of a polygon, carrying everything the renderer interpolates across
/// a face, so a cut through the middle of one keeps its shading, its texture
/// and its color.
private struct CSGVertex {
    var position: Vector3
    var normal: Vector3
    var uv: Vector2
    var color: Color

    /// The same corner on a surface facing the other way.
    var flipped: CSGVertex {
        CSGVertex(position: position, normal: -normal, uv: uv, color: color)
    }

    /// The corner `t` of the way to `other`, every attribute carried along.
    /// Colors are mixed component by component, which is what the rasterizer
    /// does between two vertices of the same face.
    func lerp(to other: CSGVertex, _ t: Double) -> CSGVertex {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return CSGVertex(position: position.lerp(to: other.position, t),
                         normal: normal.lerp(to: other.normal, t),
                         uv: uv.lerp(to: other.uv, t),
                         color: Color(red: mix(color.red, other.color.red),
                                      green: mix(color.green, other.color.green),
                                      blue: mix(color.blue, other.color.blue),
                                      alpha: mix(color.alpha, other.color.alpha)))
    }
}

/// An unbounded plane, as `normal · p = offset`, with the solid it bounds on
/// the negative side of it.
private struct CSGPlane {
    var normal: Vector3
    var offset: Double

    /// Where a polygon falls relative to the plane. The whole polygon's answer
    /// is the union of its corners' answers, so a polygon with corners on both
    /// sides reads as `spanning` and nothing else has to be worked out.
    private struct Side: OptionSet {
        let rawValue: Int
        static let coplanar = Side([])
        static let front = Side(rawValue: 1)
        static let back = Side(rawValue: 2)
        static let spanning: Side = [.front, .back]
    }

    /// Sort `polygon` into the four lists, splitting it in two when it crosses.
    ///
    /// A polygon lying *on* the plane goes to the list its own facing chooses,
    /// which is what keeps two coincident walls from being kept twice.
    func split(_ polygon: CSGPolygon, epsilon: Double, into sorted: inout CSGSplit) {
        var whole: Side = .coplanar
        var sides: [Side] = []
        sides.reserveCapacity(polygon.vertices.count)
        for vertex in polygon.vertices {
            let distance = normal.dot(vertex.position) - offset
            let side: Side = distance < -epsilon ? .back : (distance > epsilon ? .front : .coplanar)
            whole.formUnion(side)
            sides.append(side)
        }

        switch whole {
        case .coplanar:
            if normal.dot(polygon.plane.normal) > 0 {
                sorted.coplanarFront.append(polygon)
            } else {
                sorted.coplanarBack.append(polygon)
            }
        case .front:
            sorted.front.append(polygon)
        case .back:
            sorted.back.append(polygon)
        default:
            var ahead: [CSGVertex] = []
            var behind: [CSGVertex] = []
            for i in polygon.vertices.indices {
                let j = (i + 1) % polygon.vertices.count
                let here = polygon.vertices[i], next = polygon.vertices[j]
                if sides[i] != .back { ahead.append(here) }
                if sides[i] != .front { behind.append(here) }
                // Only an edge running from one side to the other crosses; an
                // edge with a corner *on* the plane already contributed that
                // corner to both halves above.
                if sides[i].union(sides[j]) == .spanning {
                    let from = normal.dot(here.position) - offset
                    let to = normal.dot(next.position) - offset
                    let crossing = here.lerp(to: next, from / (from - to))
                    ahead.append(crossing)
                    behind.append(crossing)
                }
            }
            // Both halves keep the polygon's own plane: a cut face is still part
            // of the face it was cut from.
            if ahead.count >= 3 {
                sorted.front.append(CSGPolygon(vertices: ahead, plane: polygon.plane))
            }
            if behind.count >= 3 {
                sorted.back.append(CSGPolygon(vertices: behind, plane: polygon.plane))
            }
        }
    }
}

/// Three corners of surface: what a polygon becomes on the way out, and the
/// form the seam is sewn in.
private struct CSGTriangle {
    var a: CSGVertex
    var b: CSGVertex
    var c: CSGVertex
}

/// Where a plane put each polygon it was asked about. Four lists rather than
/// two, because a face lying in the plane belongs to one side when the tree is
/// being grown and to the other when a solid is being clipped, and only the
/// caller knows which.
private struct CSGSplit {
    var coplanarFront: [CSGPolygon] = []
    var coplanarBack: [CSGPolygon] = []
    var front: [CSGPolygon] = []
    var back: [CSGPolygon] = []
}

/// A convex piece of surface, wound counterclockwise seen from outside, with
/// the plane it lies in.
private struct CSGPolygon {
    var vertices: [CSGVertex]
    var plane: CSGPlane

    /// The same piece of surface facing the other way.
    var flipped: CSGPolygon {
        CSGPolygon(vertices: vertices.reversed().map(\.flipped),
                   plane: CSGPlane(normal: -plane.normal, offset: -plane.offset))
    }
}

// MARK: - The tree

/// A solid held as a binary space partition: each node owns a plane taken from
/// one of the solid's own faces, the faces lying in that plane, and the two
/// subtrees of what is in front of it and what is behind it.
///
/// The nodes live in one array rather than as linked objects, and every walk
/// over the tree carries its own stack. A tree deep enough to be interesting is
/// deep enough to overflow the call stack on a mesh somebody generated, and a
/// mesh boolean is exactly the call that gets handed a hundred thousand
/// triangles without warning.
private struct CSGTree {

    struct Node {
        var plane: CSGPlane?
        var polygons: [CSGPolygon] = []
        var front: Int?
        var back: Int?
    }

    var nodes: [Node] = [Node()]
    let epsilon: Double

    init(epsilon: Double) {
        self.epsilon = epsilon
    }

    /// Add polygons to the tree, growing it where they do not fit an existing
    /// plane. A node with no plane yet takes one from the polygons that reach
    /// it.
    mutating func build(_ polygons: [CSGPolygon]) {
        guard !polygons.isEmpty else { return }
        var pending: [(Int, [CSGPolygon])] = [(0, polygons)]
        while let (index, list) = pending.popLast() {
            guard !list.isEmpty else { continue }
            if nodes[index].plane == nil {
                nodes[index].plane = CSGTree.splitter(of: list, epsilon: epsilon)
            }
            guard let plane = nodes[index].plane else { continue }

            var sorted = CSGSplit()
            for polygon in list {
                plane.split(polygon, epsilon: epsilon, into: &sorted)
            }
            // A face lying in this node's own plane is held here, whichever way
            // it faces: that is what the node is for.
            nodes[index].polygons.append(contentsOf: sorted.coplanarFront)
            nodes[index].polygons.append(contentsOf: sorted.coplanarBack)

            if !sorted.front.isEmpty {
                let child = nodes[index].front ?? addNode()
                nodes[index].front = child
                pending.append((child, sorted.front))
            }
            if !sorted.back.isEmpty {
                let child = nodes[index].back ?? addNode()
                nodes[index].back = child
                pending.append((child, sorted.back))
            }
        }
    }

    /// The parts of `polygons` that lie outside this solid.
    ///
    /// A polygon that reaches a node with no subtree behind it has arrived in
    /// solid space and is dropped; one that reaches a node with nothing in
    /// front of it has arrived in empty space and is kept.
    func clip(_ polygons: [CSGPolygon]) -> [CSGPolygon] {
        var kept: [CSGPolygon] = []
        var pending: [(Int, [CSGPolygon])] = [(0, polygons)]
        while let (index, list) = pending.popLast() {
            guard !list.isEmpty else { continue }
            guard let plane = nodes[index].plane else {
                kept.append(contentsOf: list)
                continue
            }
            var sorted = CSGSplit()
            for polygon in list {
                plane.split(polygon, epsilon: epsilon, into: &sorted)
            }
            // Here a face lying in the plane goes with the side it faces: a wall
            // the two solids share reads as outside for one of them and inside
            // for the other, so it survives exactly once.
            var front = sorted.front
            front.append(contentsOf: sorted.coplanarFront)
            var back = sorted.back
            back.append(contentsOf: sorted.coplanarBack)

            if let child = nodes[index].front {
                pending.append((child, front))
            } else {
                kept.append(contentsOf: front)
            }
            if let child = nodes[index].back {
                pending.append((child, back))
            }
        }
        return kept
    }

    /// Cut this solid's own surface down to the part lying outside `other`.
    mutating func clip(to other: CSGTree) {
        for index in nodes.indices {
            nodes[index].polygons = other.clip(nodes[index].polygons)
        }
    }

    /// Turn the solid inside out: every face flips, and the space in front of
    /// each plane trades places with the space behind it.
    mutating func invert() {
        for index in nodes.indices {
            nodes[index].polygons = nodes[index].polygons.map(\.flipped)
            if let plane = nodes[index].plane {
                nodes[index].plane = CSGPlane(normal: -plane.normal, offset: -plane.offset)
            }
            let front = nodes[index].front
            nodes[index].front = nodes[index].back
            nodes[index].back = front
        }
    }

    /// Every face still held anywhere in the tree.
    func allPolygons() -> [CSGPolygon] {
        nodes.flatMap(\.polygons)
    }

    private mutating func addNode() -> Int {
        nodes.append(Node())
        return nodes.count - 1
    }

    /// The plane to sort a list of polygons by.
    ///
    /// Taking the first polygon's plane is enough to be correct, and it is what
    /// makes a long thin solid cut itself into a chain of splits. Scoring a
    /// handful of candidates by how many polygons each one would cut, and how
    /// evenly it divides the rest, keeps the tree shallow and the polygon count
    /// down, which is the whole cost of the operation.
    private static func splitter(of polygons: [CSGPolygon], epsilon: Double) -> CSGPlane? {
        guard let first = polygons.first else { return nil }
        guard polygons.count > 2 else { return first.plane }

        // Both walks are samples on purpose. Scoring every candidate against
        // every polygon is what turns a solid with no dividing plane in it (a
        // sphere, where every face plane leaves all the others behind it) from
        // slow into unusable: the tree is a chain of one node per face, so the
        // scoring alone costs a pass over the whole surface per face. A sample
        // picks nearly as well for a constant price.
        let candidates = Swift.max(polygons.count / Swift.min(polygons.count, 8), 1)
        let judges = Swift.max(polygons.count / Swift.min(polygons.count, 32), 1)
        var best = first.plane
        var bestScore = Double.infinity
        for candidate in Swift.stride(from: 0, to: polygons.count, by: candidates) {
            let plane = polygons[candidate].plane
            var front = 0, back = 0, split = 0
            for polygon in Swift.stride(from: 0, to: polygons.count, by: judges).map({ polygons[$0] }) {
                var ahead = false, behind = false
                for vertex in polygon.vertices {
                    let distance = plane.normal.dot(vertex.position) - plane.offset
                    if distance > epsilon { ahead = true }
                    if distance < -epsilon { behind = true }
                }
                if ahead && behind { split += 1 } else if ahead { front += 1 } else if behind { back += 1 }
            }
            // A split costs a new polygon for ever after; an uneven division
            // only costs depth, so it weighs less.
            let score = Double(split) * 8 + Double(abs(front - back))
            if score < bestScore {
                bestScore = score
                best = plane
            }
        }
        return best
    }
}

// MARK: - Sewing the seam

/// Sewing a cut surface into a connected one.
///
/// Cutting with planes leaves a surface that is geometrically right and
/// topologically torn. A plane crossing one face puts a new corner on its edge,
/// and the face on the other side of that edge, having been sorted down a
/// different branch of the tree, never hears about it. The two faces then meet
/// along the same line while sharing no edge, which is a T-junction: the solid
/// looks shut, encloses the right volume, and reads as full of holes to
/// anything that walks the surface, a slicer above all.
///
/// The repair is the standard one. Merge the corners that landed in the same
/// place, find the edges no second triangle uses, and where one of them runs
/// through a corner in its middle, cut it there. Only an unused edge can hide a
/// T-junction, which is what keeps the search small: the tear is always already
/// visible in the edge count.
private enum CSGSeam {

    /// One corner of a face: which welded point it sits on, and everything the
    /// renderer carries across the face from it.
    struct Corner {
        var point: Int
        var vertex: CSGVertex
    }

    struct Face {
        var a: Corner
        var b: Corner
        var c: Corner
    }

    /// How many rounds of cutting to try. Cutting one edge can expose the next,
    /// but each round can only find tears the round before left, so this
    /// converges in two or three on real work. The count is a stop, not a plan.
    static let rounds = 8

    static func sealed(_ triangles: [CSGTriangle], tolerance: Double,
                       like source: Mesh, uvs: Bool, colors: Bool) -> Mesh {
        var (points, faces) = welded(triangles, tolerance: tolerance)

        for _ in 0 ..< rounds {
            let lonely = unsharedEdges(of: faces)
            guard !lonely.isEmpty else { break }

            // Only a corner that already ends an unused edge can sit in the
            // middle of another one, so these are the only points worth testing.
            var candidates: [Int] = []
            var seen = Set<Int>()
            for edge in lonely where seen.insert(edge.x).inserted { candidates.append(edge.x) }
            for edge in lonely where seen.insert(edge.y).inserted { candidates.append(edge.y) }
            let grid = PointGrid(indices: candidates, points: points, tolerance: tolerance)

            var mended: [Face] = []
            mended.reserveCapacity(faces.count)
            var changed = false
            for face in faces {
                if let pieces = cut(face, along: lonely, points: points,
                                    grid: grid, tolerance: tolerance) {
                    mended.append(contentsOf: pieces)
                    changed = true
                } else {
                    mended.append(face)
                }
            }
            faces = mended
            if !changed { break }
        }

        return mesh(of: faces, points: points, like: source, uvs: uvs, colors: colors)
    }

    // MARK: Merging what landed in the same place

    /// The distinct corner positions, and the faces rewritten to point at them.
    ///
    /// Two faces that meet computed their shared corner along their own edges,
    /// in their own directions, so the two answers differ in the last bits.
    /// After this they are the same `Vector3`, bit for bit, which is what makes
    /// every later merge (the exporter's, the solver's) agree with this one.
    private static func welded(_ triangles: [CSGTriangle],
                               tolerance: Double) -> ([Vector3], [Face]) {
        var points: [Vector3] = []
        var buckets: [SIMD3<Int>: [Int]] = [:]
        let cell = Swift.max(tolerance * 2, 1e-30)

        func index(of position: Vector3) -> Int {
            let scaled = Vector3(position.x / cell, position.y / cell, position.z / cell)
            let base = SIMD3<Int>(Int(scaled.x.rounded(.down)),
                                  Int(scaled.y.rounded(.down)),
                                  Int(scaled.z.rounded(.down)))
            // A point within `tolerance` is half a cell away at most, so it
            // lies in this cell or in the neighbor on the side this one leans.
            let lean = SIMD3<Int>(scaled.x - Double(base.x) > 0.5 ? 1 : -1,
                                  scaled.y - Double(base.y) > 0.5 ? 1 : -1,
                                  scaled.z - Double(base.z) > 0.5 ? 1 : -1)
            for dx in [0, lean.x] {
                for dy in [0, lean.y] {
                    for dz in [0, lean.z] {
                        let key = SIMD3<Int>(base.x + dx, base.y + dy, base.z + dz)
                        for candidate in buckets[key] ?? [] where points[candidate].distance(to: position) <= tolerance {
                            return candidate
                        }
                    }
                }
            }
            points.append(position)
            buckets[base, default: []].append(points.count - 1)
            return points.count - 1
        }

        var faces: [Face] = []
        faces.reserveCapacity(triangles.count)
        for triangle in triangles {
            let a = Corner(point: index(of: triangle.a.position), vertex: triangle.a)
            let b = Corner(point: index(of: triangle.b.position), vertex: triangle.b)
            let c = Corner(point: index(of: triangle.c.position), vertex: triangle.c)
            // A face whose corners merged has no area left. Dropping it here
            // rather than on the way out is what lets the edge count below read
            // the surface's real shape.
            guard a.point != b.point, b.point != c.point, a.point != c.point else { continue }
            faces.append(Face(a: a, b: b, c: c))
        }
        return (points, faces)
    }

    // MARK: Finding and cutting the tears

    /// The edges exactly one face uses. A closed surface has none.
    private static func unsharedEdges(of faces: [Face]) -> Set<SIMD2<Int>> {
        var uses: [SIMD2<Int>: Int] = [:]
        uses.reserveCapacity(faces.count * 3)
        for face in faces {
            for edge in edges(of: face) { uses[edge, default: 0] += 1 }
        }
        var lonely = Set<SIMD2<Int>>()
        for (edge, count) in uses where count == 1 { lonely.insert(edge) }
        return lonely
    }

    private static func edges(of face: Face) -> [SIMD2<Int>] {
        [key(face.a.point, face.b.point), key(face.b.point, face.c.point), key(face.c.point, face.a.point)]
    }

    private static func key(_ a: Int, _ b: Int) -> SIMD2<Int> {
        SIMD2<Int>(Swift.min(a, b), Swift.max(a, b))
    }

    /// The face cut along the first of its unused edges that runs through other
    /// corners, or `nil` when it is whole.
    ///
    /// The pieces fan from the corner opposite that edge, so every one of them
    /// keeps real area however many corners the edge picked up.
    private static func cut(_ face: Face, along lonely: Set<SIMD2<Int>>, points: [Vector3],
                            grid: PointGrid, tolerance: Double) -> [Face]? {
        let sides = [(face.a, face.b, face.c), (face.b, face.c, face.a), (face.c, face.a, face.b)]
        for (from, to, apex) in sides {
            guard lonely.contains(key(from.point, to.point)) else { continue }
            let found = grid.onSegment(from: points[from.point], to: points[to.point],
                                       points: points, tolerance: tolerance,
                                       excluding: [from.point, to.point, apex.point])
            guard !found.isEmpty else { continue }

            var chain: [Corner] = [from]
            for (_, index) in found {
                let position = points[index]
                let along = points[to.point] - points[from.point]
                let t = along.lengthSquared > 0
                    ? (position - points[from.point]).dot(along) / along.lengthSquared : 0
                chain.append(Corner(point: index, vertex: from.vertex.lerp(to: to.vertex, t)))
            }
            chain.append(to)

            var pieces: [Face] = []
            for i in 0 ..< chain.count - 1 {
                pieces.append(Face(a: chain[i], b: chain[i + 1], c: apex))
            }
            return pieces
        }
        return nil
    }

    // MARK: What comes out

    private static func mesh(of faces: [Face], points: [Vector3], like source: Mesh,
                             uvs: Bool, colors: Bool) -> Mesh {
        var positions: [Vector3] = []
        var normals: [Vector3] = []
        var texture: [Vector2] = []
        var tints: [Color] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(faces.count * 3)
        indices.reserveCapacity(faces.count * 3)
        for face in faces {
            let base = UInt32(positions.count)
            for corner in [face.a, face.b, face.c] {
                positions.append(points[corner.point])
                normals.append(corner.vertex.normal)
                if uvs { texture.append(corner.vertex.uv) }
                if colors { tints.append(corner.vertex.color) }
            }
            indices.append(contentsOf: [base, base + 1, base + 2])
        }
        return Mesh(positions: positions, normals: normals, indices: indices,
                    uvs: texture, colors: tints, material: source.material)
    }
}

/// The candidate corners, in buckets, so asking which of them lie on an edge
/// costs a handful of lookups rather than a walk over all of them.
private struct PointGrid {

    /// A cell wide enough that an ordinary edge touches a few of them, and
    /// never narrower than the tolerance itself.
    private let cell: Double
    private var buckets: [SIMD3<Int>: [Int]] = [:]
    private let all: [Int]

    init(indices: [Int], points: [Vector3], tolerance: Double) {
        var lo = Vector3.zero, hi = Vector3.zero
        if let first = indices.first {
            lo = points[first]; hi = points[first]
            for index in indices {
                let p = points[index]
                lo = Vector3(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
                hi = Vector3(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
            }
        }
        let span = hi - lo
        cell = Swift.max(Swift.max(span.x, Swift.max(span.y, span.z)) / 32, Swift.max(tolerance, 1e-30))
        all = indices
        for index in indices {
            buckets[Self.key(points[index], cell: cell), default: []].append(index)
        }
    }

    private static func key(_ p: Vector3, cell: Double) -> SIMD3<Int> {
        SIMD3<Int>(Int((p.x / cell).rounded(.down)),
                   Int((p.y / cell).rounded(.down)),
                   Int((p.z / cell).rounded(.down)))
    }

    /// The corners lying on the open segment, in order along it, each with how
    /// far along it stands.
    ///
    /// A corner at either end is not a tear, and neither is the face's own
    /// third corner, so the caller names the ones to leave out.
    func onSegment(from: Vector3, to: Vector3, points: [Vector3], tolerance: Double,
                   excluding: [Int]) -> [(Double, Int)] {
        let along = to - from
        let lengthSquared = along.lengthSquared
        guard lengthSquared > tolerance * tolerance else { return [] }

        var found: [(Double, Int)] = []
        for index in candidates(from: from, to: to, tolerance: tolerance) {
            guard !excluding.contains(index) else { continue }
            let p = points[index]
            let t = (p - from).dot(along) / lengthSquared
            guard t > 0, t < 1 else { continue }
            guard p.distance(to: from + along * t) <= tolerance else { continue }
            // A corner within a tolerance of either end is that end, not a tear.
            guard p.distance(to: from) > tolerance, p.distance(to: to) > tolerance else { continue }
            found.append((t, index))
        }
        return found.sorted { $0.0 < $1.0 }
    }

    /// The corners in the cells the segment's box covers. A box spanning a
    /// silly number of cells (a long diagonal across the whole mesh) is cheaper
    /// to answer by looking at every candidate than by walking the grid.
    private func candidates(from: Vector3, to: Vector3, tolerance: Double) -> [Int] {
        let lo = Vector3(Swift.min(from.x, to.x) - tolerance,
                         Swift.min(from.y, to.y) - tolerance,
                         Swift.min(from.z, to.z) - tolerance)
        let hi = Vector3(Swift.max(from.x, to.x) + tolerance,
                         Swift.max(from.y, to.y) + tolerance,
                         Swift.max(from.z, to.z) + tolerance)
        let first = Self.key(lo, cell: cell)
        let last = Self.key(hi, cell: cell)
        let span = (last.x - first.x + 1) * (last.y - first.y + 1) * (last.z - first.z + 1)
        guard span > 0, span <= 512 else { return all }

        var gathered: [Int] = []
        for x in first.x ... last.x {
            for y in first.y ... last.y {
                for z in first.z ... last.z {
                    if let bucket = buckets[SIMD3<Int>(x, y, z)] { gathered.append(contentsOf: bucket) }
                }
            }
        }
        return gathered
    }
}
