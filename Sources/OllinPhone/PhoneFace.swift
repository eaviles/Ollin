import Ollin
import simd

/// One face streamed from the phone's ARKit face tracker (front TrueDepth camera):
/// the 52 expression **blendshapes**, the deforming **mesh**, and the **head pose**.
///
/// Where `PhoneBody` carries a skeleton from the rear camera, this carries the face
/// from the front camera — the two are mutually exclusive on the phone (different
/// cameras), selected by the capture app's Body / Face toggle. The mesh is in
/// face-local space (centered on the face, meters), so it draws as an orbiting
/// `PointCloud` exactly like the skeleton, while the blendshapes drive expression.
///
/// ```swift
/// if let face = device.latestFace {
///     camera(.orbiting(target: .zero, radius: 0.4, azimuth: time * 0.4))
///     drawPointCloud(face.cloud())
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
    let mesh: [Vector3]

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
        mesh = sample.meshVertices.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) }
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
    /// the face). 3D mode has no mesh primitive yet, so draw them with `cloud()`.
    public var meshPoints: [Vector3] { mesh }

    /// The centroid of the mesh vertices — the origin when no mesh was reported. The
    /// mesh is already centered on the face, so this is near `.zero`.
    public var center: Vector3 {
        guard !mesh.isEmpty else { return .zero }
        var sum = Vector3.zero
        for p in mesh { sum += p }
        return sum / Double(mesh.count)
    }

    /// The face mesh as a `PointCloud` for drawing in its own space — one splat per
    /// vertex. The one shipped way to draw the face today (3D mode has no mesh
    /// primitive yet), the sibling of `PhoneBody.cloud`.
    public func cloud(pointSize: Double = 0.004, color: Color = .white) -> PointCloud {
        var cloud = PointCloud()
        for p in mesh { cloud.add(p, color: color, size: pointSize) }
        return cloud
    }
}
