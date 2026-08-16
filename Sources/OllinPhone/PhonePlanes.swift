import Foundation
import simd
import Ollin

/// One flat surface the phone has found, already placed in ARKit's world space
/// (meters): a floor, a wall, a table top, a seat.
///
/// A plane grows. ARKit reports a small patch as soon as it is sure of one, then
/// sends the same `id` again and again with a wider outline as you look around, so a
/// sketch reads the newest shape rather than a fixed one.
///
/// `boundary` is the real outline, a convex polygon around everything the phone has
/// seen of the surface. `width` and `height` are the tidier reading: the size of the
/// smallest upright box around that outline, which is what to use when a rectangle
/// is enough.
public struct PhonePlane: Sendable, Identifiable {

    /// The surface's stable identity, so a better reading replaces it in place.
    public let id: UUID
    /// What the phone thinks this surface is. `unclassified` until it decides.
    public let surface: PhoneSurface
    /// Flat like a floor, or upright like a wall.
    public let alignment: PhonePlaneAlignment
    /// The middle of the surface, in world space.
    public let center: Vector3
    /// The direction the surface faces, a unit vector in world space. A floor's
    /// normal points at the ceiling, a table top's away from the table.
    public let normal: Vector3
    /// The width of the smallest upright box around the outline, in meters.
    public let width: Double
    /// The depth of that same box, in meters. It is called a height because ARKit
    /// measures the surface as if you were looking straight at it.
    public let height: Double
    /// The outline, in world space: a convex polygon, in order around the edge.
    /// Never empty, because a surface with no reported outline falls back to the
    /// four corners of its box.
    public let boundary: [Vector3]

    /// The box this surface fills, worked out once when it is built.
    public let bounds: (min: Vector3, max: Vector3)

    /// A surface built by hand, in world space. The phone fills these in, and this
    /// is here so a room can also come from somewhere else: a room you saved and
    /// reloaded, a stand-in room to develop a sketch against with no phone attached,
    /// or a test.
    public init(id: UUID, surface: PhoneSurface, alignment: PhonePlaneAlignment,
                center: Vector3, normal: Vector3, width: Double, height: Double,
                boundary: [Vector3]) {
        self.id = id
        self.surface = surface
        self.alignment = alignment
        self.center = center
        self.normal = normal.lengthSquared > 1e-12 ? normal.normalized : Vector3.unitY
        self.width = width
        self.height = height
        self.boundary = boundary

        var lo = boundary.first ?? center, hi = boundary.first ?? center
        for p in boundary {
            lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        bounds = (lo, hi)
    }

    /// How much surface this really is, in square meters, measured on the outline
    /// rather than on the box around it. A round table reads as its own area, not as
    /// the square it sits in, which is what makes this the fair way to pick the
    /// biggest surface in the room.
    public var area: Double {
        guard boundary.count >= 3 else { return width * height }
        // The cross products of a fan from the first point add up to twice the area,
        // as a vector along the normal. This holds for any flat polygon.
        var sum = Vector3.zero
        let origin = boundary[0]
        for i in 1..<(boundary.count - 1) {
            sum += (boundary[i] - origin).cross(boundary[i + 1] - origin)
        }
        return sum.length * 0.5
    }

    /// This surface as a drawable `Mesh`, filled in. The outline is convex, so the
    /// triangles fan out from its first point.
    public var mesh: Mesh {
        guard boundary.count >= 3 else { return Mesh(positions: [], indices: []) }
        var indices: [UInt32] = []
        indices.reserveCapacity((boundary.count - 2) * 3)
        for i in 1..<(boundary.count - 1) {
            indices.append(0); indices.append(UInt32(i)); indices.append(UInt32(i + 1))
        }
        return Mesh(positions: boundary,
                    normals: [Vector3](repeating: normal, count: boundary.count),
                    indices: indices)
    }

    /// The outline as a closed loop of points, the first point repeated at the end,
    /// ready to draw as a line around the edge.
    ///
    /// ```swift
    /// for plane in device.planes.flat { drawTube(plane.outline, radius: 0.006) }
    /// ```
    public var outline: [Vector3] {
        guard let first = boundary.first else { return [] }
        return boundary + [first]
    }
}

/// Every flat surface the phone has found so far, growing and sharpening as you
/// carry the phone around.
///
/// The room mesh is the whole shape of the space, down to the clutter. This is the
/// short summary of it: the handful of flat surfaces worth putting something on or
/// hanging something from, each with a label and an outline. It needs no LiDAR,
/// so it works on any phone that runs the capture app.
///
/// ```swift
/// let device = PhoneDevice()
///
/// override func draw() {
///     guard let table = device.planes.largest(of: .table, .floor) else { return }
///     camera(.orbiting(target: table.center, radius: 2))
///     drawMesh(table.mesh)
///     withState {
///         translate(table.center + table.normal * 0.15)
///         drawSphere(radius: 0.15)
///     }
/// }
/// ```
///
/// Surfaces keep their arrival order, so what you draw stays put frame to frame and
/// only changes where the room changed.
public struct PhonePlanes: Sendable {

    /// Every surface found so far, in the order the phone first reported them.
    public private(set) var planes: [PhonePlane] = []

    /// Where each surface sits in `planes`, so a repeat report overwrites in place.
    private var index: [UUID: Int] = [:]

    /// An empty room, before any surface arrives.
    public init() {}

    // MARK: Accumulating

    /// Take a surface: replace the one with the same `id`, or add it if it is new.
    public mutating func apply(_ plane: PhonePlane) {
        if let at = index[plane.id] {
            planes[at] = plane
        } else {
            index[plane.id] = planes.count
            planes.append(plane)
        }
    }

    /// Drop the surface with this `id`, if it is here. The phone retires one when it
    /// merges it into a bigger surface.
    public mutating func remove(_ id: UUID) {
        guard let at = index.removeValue(forKey: id) else { return }
        planes.remove(at: at)
        // Every later surface shifted down by one, so the map is rebuilt. A room
        // holds a few dozen surfaces at most.
        for i in at..<planes.count { index[planes[i].id] = i }
    }

    /// Forget every surface, keeping the allocation. Start a fresh room.
    public mutating func reset() {
        planes.removeAll(keepingCapacity: true)
        index.removeAll(keepingCapacity: true)
    }

    // MARK: Reading

    /// How many surfaces have been found.
    public var count: Int { planes.count }
    /// Whether anything has been found yet.
    public var isEmpty: Bool { planes.isEmpty }

    /// The flat surfaces: floors, table tops, seats. The places to stand something.
    public var flat: [PhonePlane] { planes.filter { $0.alignment == .horizontal } }

    /// The upright surfaces: walls, and anything else standing on its edge. The
    /// places to hang something.
    public var upright: [PhonePlane] { planes.filter { $0.alignment == .vertical } }

    /// Only the surfaces the phone labelled as one of `wanted`.
    ///
    /// ```swift
    /// for wall in device.planes.planes(of: .wall) { drawMesh(wall.mesh) }
    /// ```
    public func planes(of wanted: PhoneSurface...) -> [PhonePlane] {
        planes(of: Set(wanted))
    }

    /// Only the surfaces labelled as one of `wanted`, taking a set (the variadic
    /// `planes(of:)` is the everyday form).
    public func planes(of wanted: Set<PhoneSurface>) -> [PhonePlane] {
        planes.filter { wanted.contains($0.surface) }
    }

    /// The biggest surface found so far, by real area, or `nil` in an empty room.
    public var largest: PhonePlane? {
        planes.max { $0.area < $1.area }
    }

    /// The biggest surface with one of these labels, or `nil` if none carries one.
    /// Early in a scan the labels are all `unclassified`, so ask for that too when
    /// you want an answer straight away.
    public func largest(of wanted: PhoneSurface...) -> PhonePlane? {
        planes(of: Set(wanted)).max { $0.area < $1.area }
    }

    /// The floor: the biggest surface the phone labelled as one, or failing that the
    /// lowest flat surface it has found. A sketch that wants a ground to stand on
    /// asks for this and gets an answer before ARKit has finished deciding.
    public var floor: PhonePlane? {
        if let labelled = largest(of: .floor) { return labelled }
        return flat.min { $0.center.y < $1.center.y }
    }

    /// Which labels the room has actually produced. Useful for a legend, or to see
    /// whether the phone has decided anything yet.
    public var foundSurfaces: Set<PhoneSurface> {
        Set(planes.map(\.surface))
    }

    /// The box every surface fits inside, as `min` and `max` corners (`(.zero,
    /// .zero)` before anything arrives). The room's own extent, so a camera can
    /// frame it.
    public var bounds: (min: Vector3, max: Vector3) {
        var lo: Vector3?, hi: Vector3?
        for plane in planes where !plane.boundary.isEmpty {
            let box = plane.bounds
            let low = lo ?? box.min, high = hi ?? box.max
            lo = Vector3(min(low.x, box.min.x), min(low.y, box.min.y), min(low.z, box.min.z))
            hi = Vector3(max(high.x, box.max.x), max(high.y, box.max.y), max(high.z, box.max.z))
        }
        guard let lo, let hi else { return (.zero, .zero) }
        return (lo, hi)
    }

    /// The middle of `bounds`, the point to aim a camera at.
    public var center: Vector3 { let b = bounds; return (b.min + b.max) * 0.5 }

    // MARK: Drawing

    /// Every surface as one `Mesh`, painted by what it is: the closure is asked once
    /// per surface and its color covers that whole surface.
    ///
    /// ```swift
    /// drawMesh(device.planes.mesh { surface in
    ///     surface == .floor ? Color(hex: 0x3B7D5A) : Color(white: 0.6)
    /// })
    /// ```
    public func mesh(colored color: (PhoneSurface) -> Color) -> Mesh {
        var positions: [Vector3] = [], normals: [Vector3] = []
        var indices: [UInt32] = [], colors: [Color] = []
        for plane in planes where plane.boundary.count >= 3 {
            let base = UInt32(positions.count)
            let paint = color(plane.surface)
            for point in plane.boundary {
                positions.append(point)
                normals.append(plane.normal)
                colors.append(paint)
            }
            for i in 1..<(plane.boundary.count - 1) {
                indices.append(base); indices.append(base + UInt32(i)); indices.append(base + UInt32(i + 1))
            }
        }
        return Mesh(positions: positions, normals: normals, indices: indices, colors: colors)
    }

    /// Every surface as one plain `Mesh`.
    public var mesh: Mesh { mesh { _ in .white } }
}

/// Place a wire surface into ARKit's world space: the anchor reports its outline
/// around its own origin, and its `transform` says where that origin sits in the
/// room.
///
/// Two things happen here that the phone cannot do for us. A surface that arrived
/// with no outline gets one built from its box, so everything downstream has a
/// polygon to work with. And the outline is turned around when it winds the wrong
/// way, because a fan built the wrong way faces backwards and a filled surface then
/// disappears from one side.
///
/// Returns `nil` for a retirement notice or a surface with no shape at all.
///
/// Free function (not a method) so the reader thread calls it without main-actor
/// isolation, the way the depth and room-mesh decoders do.
func phonePlane(from sample: PhonePlaneSample) -> PhonePlane? {
    guard !sample.removed else { return nil }

    let m = sample.transform
    func world(_ v: SIMD3<Float>) -> Vector3 {
        let w = m * SIMD4<Float>(v.x, v.y, v.z, 1)
        return Vector3(Double(w.x), Double(w.y), Double(w.z))
    }

    // The surface lies in the anchor's own XZ plane, so its up axis is the normal.
    let up = m * SIMD4<Float>(0, 1, 0, 0)
    var normal = Vector3(Double(up.x), Double(up.y), Double(up.z))
    normal = normal.lengthSquared > 1e-12 ? normal.normalized : Vector3.unitY

    // A surface with no reported outline still has a box, so it becomes a rectangle
    // and every reader downstream has one shape to handle instead of two.
    var local = sample.boundary
    if local.count < 3 {
        let hw = sample.width * 0.5, hh = sample.height * 0.5
        guard hw > 0, hh > 0 else { return nil }
        let c = cos(sample.rotationOnYAxis), s = sin(sample.rotationOnYAxis)
        local = [SIMD2<Float>(-hw, -hh), SIMD2<Float>(-hw, hh),
                 SIMD2<Float>(hw, hh), SIMD2<Float>(hw, -hh)].map { corner in
            sample.center + SIMD3<Float>(corner.x * c + corner.y * s, 0,
                                         -corner.x * s + corner.y * c)
        }
    }

    var boundary = local.map(world)
    // Add up the edge cross products (the polygon's own normal). Facing away from
    // the anchor's up axis means the points run the wrong way round.
    var wound = Vector3.zero
    let origin = boundary[0]
    for i in 1..<(boundary.count - 1) {
        wound += (boundary[i] - origin).cross(boundary[i + 1] - origin)
    }
    if wound.dot(normal) < 0 { boundary.reverse() }

    return PhonePlane(id: sample.id,
                      surface: PhoneSurface(rawValue: sample.surface) ?? .unclassified,
                      alignment: sample.alignment,
                      center: world(sample.center), normal: normal,
                      width: Double(sample.width), height: Double(sample.height),
                      boundary: boundary)
}
