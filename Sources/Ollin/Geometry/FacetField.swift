import Foundation

/// One flat face of a `FacetField`: a triangle lifted by a height at each
/// corner, with the geometry a facet painter asks of it next. The `normal`
/// points toward the viewer (`z` positive), `tilt` is the way the face leans,
/// and `facing(_:)` is how squarely it meets a light.
public struct Facet: Equatable, Sendable {
    /// The three corners, on the canvas.
    public let triangle: Triangle
    /// The height of each corner, in `triangle`'s order (`a`, `b`, `c`).
    public let heights: SIMD3<Double>
    /// The unit normal of the lifted face, pointing toward the viewer, so its
    /// `z` is positive. A flat face reads `(0, 0, 1)`.
    public let normal: Vector3

    /// A facet from its corners and their heights.
    public init(_ triangle: Triangle, heights: SIMD3<Double>) {
        self.triangle = triangle
        self.heights = heights
        self.normal = Facet.normal(of: triangle, heights: heights)
    }

    /// The average of the three corners, on the canvas.
    public var centroid: Vector2 { triangle.centroid }
    /// The area on the canvas (the footprint, not the lifted face).
    public var area: Double { triangle.area }
    /// The facet as a fillable shape.
    public var shape: Shape { triangle.shape }
    /// The facet as a closed contour.
    public var contour: Contour { triangle.contour }
    /// The three creases around it, `a` to `b`, `b` to `c`, and `c` back to `a`.
    public var edges: [LineSegment] { triangle.edges }

    /// The way the face leans: the normal's part in the canvas plane, which
    /// points downhill and is as long as the sine of the slope. A flat face
    /// reads `.zero`.
    public var tilt: Vector2 { normal.xy }

    /// How squarely the face meets a light shining along `light` (the direction
    /// from the face toward the light, as `FacetField.lightDirection(angle:elevation:)`
    /// builds one): the cosine of the angle between them, 1 when the light hits
    /// it head on, 0 when it grazes or comes from behind.
    public func facing(_ light: Vector3) -> Double {
        let length = light.length
        guard length > 0 else { return 0 }
        return max(0, normal.dot(light) / length)
    }

    /// `facing(_:)` for a light at `angle` in the canvas plane and `elevation`
    /// above it, in radians.
    public func facing(lightAngle angle: Double, elevation: Double) -> Double {
        facing(FacetField.lightDirection(angle: angle, elevation: elevation))
    }

    /// Where the facet sits along bands that run across the canvas at `angle`,
    /// read at its centroid and moved by its tilt: `shift` canvas units for a
    /// face leaning all the way over, read a little off the band direction so
    /// that nearly every crease moves the bands. This is the coordinate the
    /// holographic foil filter reads, so two facets of different tilt under the
    /// same band land in different stripes, which is what breaks a rainbow at a
    /// crease.
    public func bandCoordinate(angle: Double, shift: Double) -> Double {
        centroid.dot(Vector2(angle: angle)) + shift * tilt.dot(Vector2(angle: angle + FacetField.bandShiftTurn))
    }

    /// The unit normal of a triangle lifted by `heights`, with its `z` made
    /// positive. A triangle with no area reads flat.
    static func normal(of triangle: Triangle, heights: SIMD3<Double>) -> Vector3 {
        let e1 = Vector3(triangle.b.x - triangle.a.x, triangle.b.y - triangle.a.y, heights[1] - heights[0])
        let e2 = Vector3(triangle.c.x - triangle.a.x, triangle.c.y - triangle.a.y, heights[2] - heights[0])
        var n = e1.cross(e2)
        if n.z < 0 { n = -n }
        let length = n.length
        guard length > 0 else { return .unitZ }
        return n / length
    }
}

/// A sheet of facets: a region covered by triangles that each know their
/// normal, their center, and how squarely they face a light, built by lifting a
/// `Delaunay` triangulation with a height function. It is the geometry under
/// crumpled foil, a low-poly ground, or folded paper. A sketch paints each
/// facet with its own fill, hatch, or brush, and a plotter gets the creases as
/// lines through `edges`.
///
/// ```swift
/// let sheet = FacetField.grid(in: canvasRectangle, spacing: 60, seed: 3) { p in
///     noise(p.x * 0.01, p.y * 0.01) * 50
/// }
/// let light = FacetField.lightDirection(angle: -2.2, elevation: 0.9)
/// noStroke()
/// for facet in sheet.facets {
///     fill(Color(white: 0.3 + 0.7 * facet.facing(light)))
///     drawShape(facet.shape)
/// }
/// ```
///
/// The points are the sheet's own choice: `grid(in:spacing:jitter:seed:height:)`
/// jitters a lattice, and `init(points:height:)` takes any scatter (a Poisson
/// disk, your own). The same triangulation lifts again by another height
/// through `lifted(by:)`, which is how a sheet breathes frame to frame without
/// triangulating twice. `crumpled(in:spacing:crinkle:seed:)` is the sheet the
/// `Filter.holographicFoil` filter builds for itself, so a sketch that builds
/// the same one can draw its creases in geometry over the filter's fill.
public struct FacetField: Equatable, Sendable {
    /// The triangulation the facets are lifted from.
    public let delaunay: Delaunay
    /// The height of each point of `delaunay`, in its order.
    public let heights: [Double]
    /// The facets, one per triangle of `delaunay`, in its order.
    public let facets: [Facet]

    /// The points the sheet is built on, in their original order.
    public var points: [Vector2] { delaunay.points }

    /// Lift `delaunay` by `height`, read once at every point.
    public init(_ delaunay: Delaunay, height: (Vector2) -> Double) {
        self.init(delaunay, heights: delaunay.points.map(height))
    }

    /// Triangulate `points` and lift the triangles by `height`.
    public init(points: [Vector2], height: (Vector2) -> Double) {
        self.init(Delaunay(points), height: height)
    }

    /// Lift `delaunay` by one height per point, in its order.
    public init(_ delaunay: Delaunay, heights: [Double]) {
        precondition(heights.count == delaunay.points.count,
                     "FacetField needs one height per point")
        self.delaunay = delaunay
        self.heights = heights
        var facets: [Facet] = []
        facets.reserveCapacity(delaunay.indices.count / 3)
        let points = delaunay.points
        var i = 0
        while i + 2 < delaunay.indices.count {
            let a = delaunay.indices[i], b = delaunay.indices[i + 1], c = delaunay.indices[i + 2]
            facets.append(Facet(Triangle(points[a], points[b], points[c]),
                                heights: SIMD3(heights[a], heights[b], heights[c])))
            i += 3
        }
        self.facets = facets
    }

    /// The same triangulation lifted by another height: what a sheet that
    /// moves every frame calls, since the points and the triangles stay.
    public func lifted(by height: (Vector2) -> Double) -> FacetField {
        FacetField(delaunay, height: height)
    }

    /// Two sheets are equal when they stand on the same points at the same heights.
    public static func == (lhs: FacetField, rhs: FacetField) -> Bool {
        lhs.delaunay.points == rhs.delaunay.points && lhs.heights == rhs.heights
    }

    // MARK: Lattices

    /// A sheet over `region` on a jittered lattice: points every `spacing`
    /// canvas units, each moved by up to `jitter` times the spacing (half of it
    /// by default, which keeps every triangle well shaped), from the seed, and
    /// one ring of points past the region's edge so every point inside it lies
    /// on a facet. The lattice is anchored at the canvas origin, so two sheets
    /// over overlapping regions share their points. The hair-thin triangles a
    /// triangulation closes its jittered outline with are dropped, so every
    /// facet is a face and every crease a crease.
    public static func grid(in region: Rectangle, spacing: Double, jitter: Double = 0.5,
                            seed: Int = 1, height: (Vector2) -> Double) -> FacetField {
        let full = Delaunay(latticePoints(in: region, spacing: spacing, jitter: jitter, seed: seed))
        return FacetField(trimmed(full, minAngle: 0.08), height: height)
    }

    /// `delaunay` without the triangles whose smallest angle is under
    /// `minAngle` radians: the slivers along the hull of a jittered lattice,
    /// whose lifted normal is noise.
    static func trimmed(_ delaunay: Delaunay, minAngle: Double) -> Delaunay {
        let points = delaunay.points
        var kept: [Int] = []
        kept.reserveCapacity(delaunay.indices.count)
        var i = 0
        while i + 2 < delaunay.indices.count {
            let a = points[delaunay.indices[i]], b = points[delaunay.indices[i + 1]], c = points[delaunay.indices[i + 2]]
            if smallestAngle(a, b, c) >= minAngle {
                kept.append(contentsOf: delaunay.indices[i ..< i + 3])
            }
            i += 3
        }
        return Delaunay(points: points, indices: kept)
    }

    private static func smallestAngle(_ a: Vector2, _ b: Vector2, _ c: Vector2) -> Double {
        func angle(_ p: Vector2, _ q: Vector2, _ r: Vector2) -> Double {
            let u = q - p, v = r - p
            let lengths = u.length * v.length
            guard lengths > 0 else { return 0 }
            return acos(min(max(u.dot(v) / lengths, -1), 1))
        }
        return min(angle(a, b, c), min(angle(b, c, a), angle(c, a, b)))
    }

    /// The jittered lattice `grid(in:spacing:jitter:seed:height:)` stands on.
    public static func latticePoints(in region: Rectangle, spacing: Double, jitter: Double = 0.5,
                                     seed: Int = 1) -> [Vector2] {
        let spacing = max(spacing, 1e-6)
        let jitter = min(max(jitter, 0), 1) * spacing
        let i0 = Int((region.x / spacing).rounded(.down)) - 1
        let i1 = Int(((region.x + region.width) / spacing).rounded(.up)) + 1
        let j0 = Int((region.y / spacing).rounded(.down)) - 1
        let j1 = Int(((region.y + region.height) / spacing).rounded(.up)) + 1
        guard i1 >= i0, j1 >= j0 else { return [] }
        var points: [Vector2] = []
        points.reserveCapacity((i1 - i0 + 1) * (j1 - j0 + 1))
        for j in j0 ... j1 {
            for i in i0 ... i1 {
                // Each node draws from its own stream, keyed by its lattice
                // position, so the point is the same whatever region asked.
                var node = SplitMix64(seed: nodeSeed(seed, i, j))
                let dx = (Double.random(in: 0 ..< 1, using: &node) - 0.5) * jitter
                let dy = (Double.random(in: 0 ..< 1, using: &node) - 0.5) * jitter
                points.append(Vector2(Double(i) * spacing + dx, Double(j) * spacing + dy))
            }
        }
        return points
    }

    /// A crumpled sheet over `region`: the jittered lattice at `spacing`, lifted
    /// by two octaves of the seeded noise with a swing of about `crinkle` times
    /// the spacing, so `crinkle` 0 is flat and 1 is deeply creased. The sheet
    /// `Filter.holographicFoil` builds when it is handed none, so a sketch that
    /// builds the same one draws creases that land on the filter's.
    public static func crumpled(in region: Rectangle, spacing: Double = 56,
                                crinkle: Double = 0.6, seed: Int = 1) -> FacetField {
        let fields = NoiseFields(seed: seed)
        let swing = crinkle * spacing
        let broad = spacing * 2.8, fine = spacing * 0.9
        return grid(in: region, spacing: spacing, seed: seed) { p in
            let low = (fields.noise(p.x / broad, p.y / broad) - 0.5) * 2
            let high = (fields.noise(p.x / fine + 31, p.y / fine + 17) - 0.5) * 2
            return swing * (1.1 * low + 0.45 * high)
        }
    }

    private static func nodeSeed(_ seed: Int, _ i: Int, _ j: Int) -> UInt64 {
        var h = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(bitPattern: Int64(i)) &* 0xBF58_476D_1CE4_E5B9
        h = (h ^ (h >> 31)) &* 0x94D0_49BB_1331_11EB
        h ^= UInt64(bitPattern: Int64(j)) &* 0xD6E8_FEB8_6659_FD93
        return h ^ (h >> 29)
    }

    // MARK: Reading the sheet

    /// Every crease once: the edges the triangles share, each as one segment
    /// from the lower-indexed point to the higher, in a fixed order. The lines a
    /// plotter draws, and what a sketch strokes over the foil filter's fill.
    public var edges: [LineSegment] {
        var seen = Set<[Int]>()
        var result: [LineSegment] = []
        let points = delaunay.points
        var i = 0
        while i + 2 < delaunay.indices.count {
            let corners = [delaunay.indices[i], delaunay.indices[i + 1], delaunay.indices[i + 2]]
            for k in 0 ..< 3 {
                let a = corners[k], b = corners[(k + 1) % 3]
                let key = a < b ? [a, b] : [b, a]
                if seen.insert(key).inserted {
                    result.append(LineSegment(points[key[0]], points[key[1]]))
                }
            }
            i += 3
        }
        return result
    }

    /// The facet under `point`, or `nil` off the sheet. A point on a crease
    /// belongs to the first facet that holds it.
    public func facet(containing point: Vector2) -> Facet? {
        facets.first { FacetField.contains($0.triangle, point) }
    }

    /// The direction from a face toward a light at `angle` in the canvas plane
    /// (as `Vector2(angle:)` reads it) and `elevation` above the sheet, in
    /// radians: `π / 2` is straight at the viewer, 0 grazes the sheet.
    public static func lightDirection(angle: Double, elevation: Double) -> Vector3 {
        Vector3(cos(angle) * cos(elevation), sin(angle) * cos(elevation), sin(elevation))
    }

    /// How far off the band direction a facet's tilt is read when it moves the
    /// bands (`Facet.bandCoordinate(angle:shift:)`), in radians. Read straight
    /// along the bands, a crease running across them would leave them whole.
    static let bandShiftTurn = 0.65

    /// Whether `p` lies in `t` (its edges included), by the three same-side tests.
    static func contains(_ t: Triangle, _ p: Vector2) -> Bool {
        let d1 = (t.b - t.a).cross(p - t.a)
        let d2 = (t.c - t.b).cross(p - t.b)
        let d3 = (t.a - t.c).cross(p - t.c)
        let negative = d1 < 0 || d2 < 0 || d3 < 0
        let positive = d1 > 0 || d2 > 0 || d3 > 0
        return !(negative && positive)
    }
}
