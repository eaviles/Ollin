import Ollin
import simd

/// Which of the face's two eyes to read, for the per-eye accessors on `PhoneFace`.
/// Left and right are the face's own left and right.
public enum PhoneEye: Sendable, CaseIterable {
    case left, right

    var index: Int { self == .left ? 0 : 1 }
}

/// One face streamed from the phone's ARKit face tracker (front TrueDepth camera):
/// the 52 expression **blendshapes**, the deforming **mesh** (with the texture
/// coordinates a mask maps through), the **head pose**, the two **eye poses**, and
/// the **look-at point** the eyes converge on.
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

    /// Where the eyes converge, in **face-local** space (meters). The stream's read
    /// of the gaze target: a point out in front of the face, moving as the eyes do.
    /// `worldLookAtPoint` is the same point stood in world space.
    public let lookAtPoint: Vector3

    let shapes: [PhoneBlendShape: Double]
    let vertices: [Vector3]
    let indices: [UInt32]
    let uvs: [Vector2]
    let eyeOrientations: [SIMD4<Float>]   // [left, right], face-local quaternions
    let eyePositions: [Vector3]           // [left, right], face-local meters

    /// Wrap a decoded wire sample, mapping the positional blendshape array onto the
    /// `PhoneBlendShape` cases and the mesh vertices into `Vector3`.
    init(_ sample: PhoneFaceSample) {
        isTracked = sample.tracked
        timestamp = sample.timestamp
        headOrientation = sample.headOrientation
        headPosition = PhoneFace.vector(sample.headPosition)
        lookAtPoint = PhoneFace.vector(sample.lookAtPoint)
        var shapes: [PhoneBlendShape: Double] = [:]
        shapes.reserveCapacity(sample.blendShapes.count)
        for (i, v) in sample.blendShapes.enumerated() {
            if let shape = PhoneBlendShape(rawValue: UInt8(i)) { shapes[shape] = Double(v) }
        }
        self.shapes = shapes
        vertices = sample.meshVertices.map(PhoneFace.vector)
        indices = sample.triangleIndices.map(UInt32.init)
        uvs = sample.textureCoordinates.map { Vector2(Double($0.x), Double($0.y)) }
        eyeOrientations = [sample.leftEyeOrientation, sample.rightEyeOrientation]
        eyePositions = [PhoneFace.vector(sample.leftEyePosition),
                        PhoneFace.vector(sample.rightEyePosition)]
    }

    /// Stage a face with no phone: place a head, a mesh, eyes, and a gaze by hand,
    /// so a sketch, a test, or a figure can exercise the whole drawing path. Every
    /// field defaults to a neutral value; supply only what the scene needs.
    public init(tracked: Bool = true, timestamp: Double = 0,
                headOrientation: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
                headPosition: Vector3 = .zero,
                blendShapes: [PhoneBlendShape: Double] = [:],
                meshPoints: [Vector3] = [], triangleIndices: [UInt32] = [],
                textureCoordinates: [Vector2] = [],
                leftEyeOrientation: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
                leftEyePosition: Vector3 = .zero,
                rightEyeOrientation: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
                rightEyePosition: Vector3 = .zero,
                lookAtPoint: Vector3 = .zero) {
        isTracked = tracked
        self.timestamp = timestamp
        self.headOrientation = headOrientation
        self.headPosition = headPosition
        self.lookAtPoint = lookAtPoint
        shapes = blendShapes
        vertices = meshPoints
        indices = triangleIndices
        uvs = textureCoordinates
        eyeOrientations = [leftEyeOrientation, rightEyeOrientation]
        eyePositions = [leftEyePosition, rightEyePosition]
    }

    private static func vector(_ v: SIMD3<Float>) -> Vector3 {
        Vector3(Double(v.x), Double(v.y), Double(v.z))
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

    /// The deforming face as a `Mesh` in face-local space, with the ARKit topology,
    /// computed smooth normals, and the per-vertex texture coordinates (so
    /// `.textured(_:)` maps a mask image onto the face). Draw it solid, textured, or
    /// as a `wireframe()` (the recognizable AR face net). Empty-indexed (a
    /// point-cloud-only fallback) if the stream carried no topology.
    public func mesh() -> Mesh {
        Mesh(positions: vertices, indices: indices,
             uvs: uvs.count == vertices.count ? uvs : []).withSmoothNormals()
    }

    /// The per-vertex texture coordinates, aligned with `meshPoints`. Constant frame
    /// to frame (only the vertex positions deform), and the mapping every face shares,
    /// so a mask image drawn for one face fits every face. Empty when the stream
    /// carried none.
    public var meshUVs: [Vector2] { uvs }

    /// The head's full world pose (orientation and position composed), ready for
    /// `transform(_:)`: draw the face-local `mesh()` under it and it stands where
    /// the head is, turned the way the head turns, with the eyes inside it.
    public var headTransform: simd_float4x4 {
        var m = simd_float4x4(simd_quatf(vector: headOrientation))
        m.columns.3 = SIMD4<Float>(Float(headPosition.x), Float(headPosition.y),
                                   Float(headPosition.z), 1)
        return m
    }

    // MARK: The eyes and the gaze

    /// One eye's position, in **face-local** space (meters, relative to the head).
    public func eyePosition(_ eye: PhoneEye) -> Vector3 { eyePositions[eye.index] }

    /// One eye's position stood in world space, through the head pose.
    public func worldEyePosition(_ eye: PhoneEye) -> Vector3 {
        toWorld(eyePositions[eye.index])
    }

    /// One eye's orientation as a quaternion `(x, y, z, w)`, **face-local** (relative
    /// to the head). Identity when the eye looks straight ahead.
    public func eyeOrientation(_ eye: PhoneEye) -> SIMD4<Float> { eyeOrientations[eye.index] }

    /// The direction one eye looks, as a **face-local** unit vector: the eye's own z
    /// axis, pointing out of the face. Turn it with the head (`worldGazeDirection`)
    /// to aim it in the room.
    public func gazeDirection(_ eye: PhoneEye) -> Vector3 {
        let q = simd_quatf(vector: eyeOrientations[eye.index])
        let d = q.act(SIMD3<Float>(0, 0, 1))
        return Vector3(Double(d.x), Double(d.y), Double(d.z))
    }

    /// The direction one eye looks, as a world-space unit vector.
    public func worldGazeDirection(_ eye: PhoneEye) -> Vector3 {
        let head = simd_quatf(vector: headOrientation)
        let q = head * simd_quatf(vector: eyeOrientations[eye.index])
        let d = q.act(SIMD3<Float>(0, 0, 1))
        return Vector3(Double(d.x), Double(d.y), Double(d.z))
    }

    /// Where the eyes converge, stood in world space through the head pose. Draw a
    /// bead here and a beam from each `worldEyePosition` to it: the gaze made visible.
    public var worldLookAtPoint: Vector3 { toWorld(lookAtPoint) }

    /// A face-local point stood in world space: turned by the head's orientation,
    /// then moved to the head's position.
    private func toWorld(_ p: Vector3) -> Vector3 {
        let q = simd_quatf(vector: headOrientation)
        let r = q.act(SIMD3<Float>(Float(p.x), Float(p.y), Float(p.z)))
        return Vector3(Double(r.x), Double(r.y), Double(r.z)) + headPosition
    }

    /// The face mesh as a `PointCloud` for drawing in its own space — one splat per
    /// vertex, the sibling of `PhoneBody.cloud`. (`mesh()` is the surface form.)
    public func cloud(pointSize: Double = 0.004, color: Color = .white) -> PointCloud {
        var cloud = PointCloud()
        for p in vertices { cloud.add(p, color: color, size: pointSize) }
        return cloud
    }
}
