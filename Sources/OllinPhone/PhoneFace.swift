import Ollin
import simd

/// One face streamed from the phone's ARKit face tracker (front TrueDepth camera):
/// the 52 expression **blendshapes**, the deforming **mesh**, and the **head pose**.
///
/// Where `PhoneBody` carries a skeleton from the rear camera, this carries the face
/// from the front camera — the two are mutually exclusive on the phone (different
/// cameras), selected by the capture app's Body / Face toggle. The mesh is in
/// face-local space (centered on the face, meters); draw it as a `mesh()` (solid,
/// textured, or `wireframe()` — the AR face net) or a `cloud()` of points, while the
/// blendshapes drive expression.
///
/// ```swift
/// if let face = device.latestFace {
///     camera(.orbiting(target: .zero, radius: 0.4, azimuth: time * 0.4))
///     wireframe(); drawMesh(face.mesh())
///     let smile = face.blendShape(.mouthSmileLeft)   // 0…1
/// }
/// ```
public struct PhoneFace: Sendable {

    /// Whether ARKit currently has the face (vs. extrapolating from the last frame).
    public let isTracked: Bool

    /// The capture timestamp of the frame, in the phone's clock (seconds).
    public let timestamp: Double

    /// The head's orientation in world space, as a quaternion `(x, y, z, w)`.
    public let headOrientation: SIMD4<Float>

    /// The head's position in world space, in meters.
    public let headPosition: Vector3

    let shapes: [PhoneBlendShape: Double]
    let vertices: [Vector3]
    let indices: [UInt32]

    /// Wrap a decoded wire sample, mapping the positional blendshape array onto the
    /// `PhoneBlendShape` cases and the mesh vertices into `Vector3`.
    init(_ sample: PhoneFaceSample) {
        isTracked = sample.tracked
        timestamp = sample.timestamp
        headOrientation = sample.headOrientation
        headPosition = Vector3(Double(sample.headPosition.x), Double(sample.headPosition.y),
                               Double(sample.headPosition.z))
        var shapes: [PhoneBlendShape: Double] = [:]
        shapes.reserveCapacity(sample.blendShapes.count)
        for (i, v) in sample.blendShapes.enumerated() {
            if let shape = PhoneBlendShape(rawValue: UInt8(i)) { shapes[shape] = Double(v) }
        }
        self.shapes = shapes
        vertices = sample.meshVertices.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) }
        indices = sample.triangleIndices.map(UInt32.init)
    }

    /// One expression coefficient, `0` (neutral) … `1` (fully expressed). Returns `0`
    /// for a shape this frame didn't carry.
    public func blendShape(_ shape: PhoneBlendShape) -> Double { shapes[shape] ?? 0 }

    /// Every reported blendshape coefficient, keyed by shape.
    public var blendShapes: [PhoneBlendShape: Double] { shapes }

    /// The blendshapes sorted strongest-first — the few that are actually firing this
    /// frame (a handy readout: the top of this list names the current expression).
    public func strongestBlendShapes(count: Int = 5, above threshold: Double = 0.05)
        -> [(shape: PhoneBlendShape, value: Double)] {
        shapes.filter { $0.value > threshold }
            .sorted { $0.value > $1.value }
            .prefix(count)
            .map { (shape: $0.key, value: $0.value) }
    }

    /// The deforming face mesh as vertices in face-local space (meters, centered on
    /// the face). Draw them with `mesh()` (a solid or wireframe surface) or `cloud()`.
    public var meshPoints: [Vector3] { vertices }

    /// The centroid of the mesh vertices — the origin when no mesh was reported. The
    /// mesh is already centered on the face, so this is near `.zero`.
    public var center: Vector3 {
        guard !vertices.isEmpty else { return .zero }
        var sum = Vector3.zero
        for p in vertices { sum += p }
        return sum / Double(vertices.count)
    }

    /// The deforming face as a `Mesh` in face-local space, with the ARKit topology and
    /// computed smooth normals. Draw it solid, textured, or as a `wireframe()` (the
    /// recognizable AR face net). Empty-indexed (a point-cloud-only fallback) if the
    /// stream carried no topology.
    public func mesh() -> Mesh {
        Mesh(positions: vertices, indices: indices).withSmoothNormals()
    }

    /// The face mesh as a `PointCloud` for drawing in its own space — one splat per
    /// vertex, the sibling of `PhoneBody.cloud`. (`mesh()` is the surface form.)
    public func cloud(pointSize: Double = 0.004, color: Color = .white) -> PointCloud {
        var cloud = PointCloud()
        for p in vertices { cloud.add(p, color: color, size: pointSize) }
        return cloud
    }
}
