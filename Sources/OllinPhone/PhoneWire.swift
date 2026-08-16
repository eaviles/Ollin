// PhoneWire — the sensor-stream wire format shared by the Ollin iPhone capture
// app (Apps/OllinPhoneApp) and the Mac satellite (OllinPhone).
//
// LOAD-BEARING: this file is compiled *verbatim into both ends*. The iOS app
// includes it directly in its xcodegen sources, and it must not pull in Ollin or
// Metal — so this file imports only Foundation + simd. Everything Ollin-specific
// (Vector3, PointCloud, the device) lives in the other OllinPhone files, which
// the iOS app never sees. Keep this file dependency-free.
//
// The framing is a usbmuxd-tunnelled stream of tagged messages: a fixed
// little-endian header, then a payload the reader decodes by kind.

import Foundation
import simd

/// The framing + payload codec for the phone sensor stream. A frame is a
/// 12-byte header (`magic`, `version`, `kind`, reserved, `payloadLength`) followed
/// by the payload bytes; the reader parses the header to learn the payload length
/// and kind, reads the payload, and decodes it.
public enum PhoneWire {

    /// Frame marker — "OLN1" as a little-endian `UInt32`. A desynchronized stream
    /// fails this check and the reader drops the connection to resync.
    public static let magic: UInt32 = 0x4F4C_4E31

    /// Wire version. Pre-1.0 both ends are always rebuilt and shipped together (the
    /// app and the satellite share this file), so this is **not** bumped per payload
    /// change — just rebuild both. It becomes a real compatibility contract worth
    /// versioning at Ollin 1.0+, when an installed app might outlive a Mac update.
    public static let version: UInt8 = 1

    /// Header size: magic(4) + version(1) + kind(1) + reserved(2) + payloadLength(4).
    public static let headerByteCount = 12

    /// The TCP port the capture app listens on, tunnelled to the Mac via usbmuxd.
    /// Shared by both ends (this file compiles into the iOS app too), so the port
    /// can't drift between them.
    public static let streamPort: UInt16 = 1338

    /// Defensive upper bound on a single payload, so a garbage header can't steer
    /// a huge read (a body pose is well under a kilobyte; motion is 60 bytes).
    static let maxPayloadBytes = 1 << 20
}

/// Which sensor a frame carries.
public enum PhoneMessageKind: UInt8, Sendable, CaseIterable {
    /// CoreMotion device motion (attitude, gravity, rates) — the cheap transport
    /// smoke-test: if these numbers move on the Mac, the wire works.
    case deviceMotion = 1
    /// The ARKit bodies in view, bundled per frame (the tracker follows one today;
    /// the wire carries a list so more cost nothing later). Each body is a set of
    /// named joints, each a position and an orientation in model space with a flag
    /// saying whether the camera observed that joint, plus the anchor transform
    /// that stands the whole skeleton in ARKit world space and the person's
    /// estimated size as a scale factor.
    case bodyPose = 2
    /// The ARKit faces in view (up to 3 on TrueDepth) — each a deforming mesh, the
    /// 52 expression blendshapes, and a head pose, bundled per frame. The phone runs
    /// face tracking on its front TrueDepth camera, so it's mutually exclusive with
    /// body pose (which uses the rear camera).
    case face = 3
    /// A world-facing RGBD frame from the rear LiDAR — a metric depth map, a color
    /// image, the depth-grid intrinsics, optional per-pixel confidence, and the 6DoF
    /// camera pose, which unproject into a point cloud. The heaviest payload (hundreds
    /// of KB; depth is raw float32 — LZFSE compression is a later optimization), so it
    /// streams only while the app is in World mode (LiDAR rear camera).
    case depth = 4
    /// A person-segmentation matte computed on the phone: a grayscale alpha matte
    /// (0 = background … 255 = person) of the people in the scene, plus the
    /// matching color frame, which the Mac turns into a tintable silhouette and a
    /// person cutout. Two modes send it, one kind either way: **Segment** (rear
    /// camera, ARKit's on-device segmentation, its own session, so it shares the
    /// rear camera with body/depth) and **Selfie** (front camera, a Vision pass
    /// over a plain capture session, mirrored like the front-camera preview).
    case segmentation = 5
    /// One chunk of the reconstructed room surface from the rear LiDAR: a triangle
    /// mesh the phone builds and keeps improving as you walk around. ARKit divides
    /// the room into blocks and reports each as its own anchor, so this message
    /// carries **one block**, identified by a stable `id`. The Mac keeps a set of
    /// them, replaces a block when a better version arrives, and drops one the
    /// phone retires, which keeps each payload small while the room builds up
    /// piece by piece. Streams only in Room mode (LiDAR rear camera).
    case sceneMesh = 6
    /// One flat surface the phone has found: a floor, a wall, a table top. ARKit
    /// reports each as its own anchor and keeps growing it as you look around, so
    /// this message carries **one plane**, identified by a stable `id`, the same way
    /// a mesh block is. Streams in Room mode, and unlike the mesh it needs no LiDAR.
    case plane = 7
    /// What the room's light is doing: how bright it is and how warm. The phone
    /// measures this from the camera image, so it arrives in **every** mode, a few
    /// times a second. In Face mode it also carries a direction for the strongest
    /// light, which ARKit works out from the face itself.
    case light = 8
}

/// The named joints the stream carries — a practical subset of ARKit's ~91-joint
/// skeleton, enough to draw a recognizable figure. The iOS app maps ARKit's joint
/// names onto these; the Mac side draws bones between them (`PhoneBody.skeleton`).
public enum PhoneJoint: UInt8, CaseIterable, Sendable {
    case root = 0
    case hips
    case spine
    case chest
    case neck
    case head
    case leftShoulder, leftElbow, leftWrist, leftHand
    case rightShoulder, rightElbow, rightWrist, rightHand
    case leftHip, leftKnee, leftAnkle, leftFoot
    case rightHip, rightKnee, rightAnkle, rightFoot
}

/// One CoreMotion sample, in the phone's reference frame. Quaternion is `(x,y,z,w)`;
/// gravity and acceleration are in g, rotation rate in rad/s.
public struct PhoneMotionSample: Sendable, Equatable {
    public var attitude: SIMD4<Float>
    public var gravity: SIMD3<Float>
    public var rotationRate: SIMD3<Float>
    public var userAcceleration: SIMD3<Float>
    public var timestamp: Double

    public init(attitude: SIMD4<Float>, gravity: SIMD3<Float>, rotationRate: SIMD3<Float>,
                userAcceleration: SIMD3<Float>, timestamp: Double) {
        self.attitude = attitude
        self.gravity = gravity
        self.rotationRate = rotationRate
        self.userAcceleration = userAcceleration
        self.timestamp = timestamp
    }
}

/// One joint of a streamed skeleton: where it is and which way it points, both in
/// model space (the pelvis root at the origin), plus whether the camera actually
/// observed it this frame. ARKit's full rig carries joints the model does not see
/// (they interpolate between tracked neighbors so a rigged mesh maps cleanly);
/// `tracked` is false for those.
public struct PhoneJointSample: Sendable, Equatable {
    /// The joint's position in meters, model space.
    public var position: SIMD3<Float>
    /// The joint's orientation as a quaternion `(x, y, z, w)`, model space.
    public var orientation: SIMD4<Float>
    /// Whether the camera observed this joint (vs. the rig filling it in).
    public var tracked: Bool

    public init(position: SIMD3<Float>, orientation: SIMD4<Float> = SIMD4<Float>(0, 0, 0, 1),
                tracked: Bool = true) {
        self.position = position
        self.orientation = orientation
        self.tracked = tracked
    }
}

/// One ARKit body-pose sample: every reported joint in **meters**, model space
/// (the pelvis root at the origin, x right, y up, z toward the camera, ARKit's
/// convention), the anchor transform that places that model space in ARKit world
/// space, the person's estimated size, and whether ARKit currently has tracking.
public struct PhonePoseSample: Sendable, Equatable {
    public var tracked: Bool
    public var timestamp: Double
    /// Model space → ARKit world space (meters, y up, the origin where the
    /// session started). Multiply a model-space joint through this to stand the
    /// skeleton where the person stands.
    public var anchor: simd_float4x4
    /// How the person's size relates to the default rig height (1 = the default
    /// rig; smaller people give smaller factors).
    public var scaleFactor: Float
    public var joints: [PhoneJoint: PhoneJointSample]

    public init(tracked: Bool, timestamp: Double, anchor: simd_float4x4 = matrix_identity_float4x4,
                scaleFactor: Float = 1, joints: [PhoneJoint: PhoneJointSample]) {
        self.tracked = tracked
        self.timestamp = timestamp
        self.anchor = anchor
        self.scaleFactor = scaleFactor
        self.joints = joints
    }
}

/// The 52 ARKit face blendshapes, in a fixed order so the wire can carry them as a
/// bare positional array (the index *is* the shape) with no keys. The iOS app maps
/// each onto ARKit's `ARFaceAnchor.BlendShapeLocation`; the Mac side reads them by
/// case off `PhoneFace`. A coefficient is `0` (neutral) … `1` (fully expressed).
public enum PhoneBlendShape: UInt8, CaseIterable, Sendable {
    // Eyes — left
    case eyeBlinkLeft = 0, eyeLookDownLeft, eyeLookInLeft, eyeLookOutLeft
    case eyeLookUpLeft, eyeSquintLeft, eyeWideLeft
    // Eyes — right
    case eyeBlinkRight, eyeLookDownRight, eyeLookInRight, eyeLookOutRight
    case eyeLookUpRight, eyeSquintRight, eyeWideRight
    // Jaw
    case jawForward, jawLeft, jawRight, jawOpen
    // Mouth
    case mouthClose, mouthFunnel, mouthPucker, mouthLeft, mouthRight
    case mouthSmileLeft, mouthSmileRight, mouthFrownLeft, mouthFrownRight
    case mouthDimpleLeft, mouthDimpleRight, mouthStretchLeft, mouthStretchRight
    case mouthRollLower, mouthRollUpper, mouthShrugLower, mouthShrugUpper
    case mouthPressLeft, mouthPressRight, mouthLowerDownLeft, mouthLowerDownRight
    case mouthUpperUpLeft, mouthUpperUpRight
    // Brows
    case browDownLeft, browDownRight, browInnerUp, browOuterUpLeft, browOuterUpRight
    // Cheeks
    case cheekPuff, cheekSquintLeft, cheekSquintRight
    // Nose
    case noseSneerLeft, noseSneerRight
    // Tongue
    case tongueOut
}

/// One ARKit face sample: whether ARKit has the face, the capture timestamp, the
/// head's world pose (rotation `(x,y,z,w)` + position in meters), the 52 expression
/// `blendShapes` (positional, in `PhoneBlendShape` order), the deforming
/// `meshVertices` in **face-local** space (centered on the face, meters), and the
/// `triangleIndices` (the mesh topology — constant per device, three indices per
/// triangle) so the Mac can draw a real mesh, not just a point cloud.
public struct PhoneFaceSample: Sendable, Equatable {
    public var tracked: Bool
    public var timestamp: Double
    public var headOrientation: SIMD4<Float>
    public var headPosition: SIMD3<Float>
    public var blendShapes: [Float]
    public var meshVertices: [SIMD3<Float>]
    public var triangleIndices: [UInt16]

    public init(tracked: Bool, timestamp: Double, headOrientation: SIMD4<Float>,
                headPosition: SIMD3<Float>, blendShapes: [Float], meshVertices: [SIMD3<Float>],
                triangleIndices: [UInt16] = []) {
        self.tracked = tracked
        self.timestamp = timestamp
        self.headOrientation = headOrientation
        self.headPosition = headPosition
        self.blendShapes = blendShapes
        self.meshVertices = meshVertices
        self.triangleIndices = triangleIndices
    }
}

/// One world-facing RGBD frame from the phone's rear LiDAR: a metric depth map
/// (`depth`, meters, row-major from the top-left, `depthWidth × depthHeight`), the
/// matching JPEG color image (`colorJPEG`, decoded on the Mac side so this file
/// stays free of ImageIO), the camera intrinsics **already scaled to the depth
/// grid** (`fx`/`fy`/`cx`/`cy`, so the Mac builds a `CameraIntrinsics` straight
/// against `depthWidth × depthHeight`), optional per-pixel `confidence` (`0`/`1`/`2`,
/// matching the depth grid), and the camera's 6DoF pose (`cameraTransform`,
/// camera→world, ARKit's column-major `simd_float4x4`) for the multi-frame world
/// fusion to come.
///
/// Depth is carried **raw** (not compressed) — a 256×192 LiDAR map is ~196 KB,
/// comfortable over USB; LZFSE compression is a documented later optimization. The
/// color JPEG keeps the payload well under `PhoneWire.maxPayloadBytes`.
public struct PhoneDepthSample: Sendable, Equatable {
    public var tracked: Bool
    public var timestamp: Double
    public var depthWidth: Int
    public var depthHeight: Int
    public var fx: Float
    public var fy: Float
    public var cx: Float
    public var cy: Float
    public var cameraTransform: simd_float4x4
    public var colorJPEG: Data
    public var depth: [Float]
    public var confidence: [UInt8]?

    public init(tracked: Bool, timestamp: Double, depthWidth: Int, depthHeight: Int,
                fx: Float, fy: Float, cx: Float, cy: Float, cameraTransform: simd_float4x4,
                colorJPEG: Data, depth: [Float], confidence: [UInt8]?) {
        self.tracked = tracked
        self.timestamp = timestamp
        self.depthWidth = depthWidth
        self.depthHeight = depthHeight
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.cameraTransform = cameraTransform
        self.colorJPEG = colorJPEG
        self.depth = depth
        self.confidence = confidence
    }
}

/// One person-segmentation frame from the phone's camera: a grayscale alpha
/// `matte` (`matteWidth × matteHeight`, row-major from the top-left, 0 = background
/// … 255 = person), and the matching JPEG color frame
/// (`colorJPEG`, decoded on the Mac side so this file stays free of ImageIO). The
/// matte is downscaled on the phone to a bounded size: it's a soft mask, and the
/// Mac rescales it onto the color when it builds the cutout, so the payload stays
/// small.
///
/// Both arrive aligned with each other. `orientation` is the number of 90°
/// **clockwise** turns the Mac applies to both to stand them upright for how the
/// phone was held (0…3). Segment mode sends camera-native (sensor-landscape)
/// buffers with the turn count that fixes them; Selfie mode rotates on the phone
/// and always sends 0. Rotating both by the same amount keeps them aligned.
public struct PhoneSegmentationSample: Sendable, Equatable {
    public var tracked: Bool
    public var timestamp: Double
    public var matteWidth: Int
    public var matteHeight: Int
    public var orientation: UInt8
    public var matte: [UInt8]
    public var colorJPEG: Data

    public init(tracked: Bool, timestamp: Double, matteWidth: Int, matteHeight: Int,
                orientation: UInt8 = 0, matte: [UInt8], colorJPEG: Data) {
        self.tracked = tracked
        self.timestamp = timestamp
        self.matteWidth = matteWidth
        self.matteHeight = matteHeight
        self.orientation = orientation
        self.matte = matte
        self.colorJPEG = colorJPEG
    }
}

/// What the phone thinks a piece of the room is. ARKit labels every triangle of
/// the reconstructed mesh with one of these while it scans, and labels each flat
/// surface it finds the same way, so a sketch can treat the floor differently from
/// a wall, or keep only the tables. A part the phone is unsure about stays
/// `unclassified`, which is most of them early in a scan.
///
/// The raw values are contiguous from `0`, and the iOS app maps ARKit's own
/// labels onto them, so the wire carries one byte per triangle. A test pins the
/// contiguity, the same way the blendshape order is pinned.
public enum PhoneSurface: UInt8, CaseIterable, Sendable {
    case unclassified = 0
    case wall, floor, ceiling, table, seat, window, door
}

/// One block of the reconstructed room surface, in the coordinate space of its own
/// anchor: `vertices` and `normals` are anchor-local meters, and `transform` places
/// the block in ARKit's fixed world (the same world `PhoneDepthSample.cameraTransform`
/// reports). `triangleIndices` is a triangle list, three indices per triangle, and
/// `surfaces` carries one `PhoneSurface` raw value per triangle (empty when the
/// device scans without classification).
///
/// `id` is the block's stable identity: the phone sends the same `id` again with a
/// better mesh as the scan improves, so the Mac replaces that block in place rather
/// than piling up copies. `removed` is the retirement notice, and the payload then
/// carries no geometry, so the Mac drops the block.
///
/// `scan` says which run of the scanner the block belongs to. Starting a scan resets
/// the phone's world origin, so blocks from an earlier run are in a coordinate space
/// that no longer exists. The number changes with every run, and the Mac drops the
/// old room the moment it sees a new one.
///
/// Geometry is carried raw, which makes a block tens of kilobytes. The phone sends
/// only a few blocks per second, and skips a block too big for one payload, so the
/// wire stays quiet while a whole room accumulates.
public struct PhoneSceneMeshSample: Sendable, Equatable {
    public var tracked: Bool
    public var timestamp: Double
    public var id: UUID
    public var scan: UInt32
    public var removed: Bool
    public var transform: simd_float4x4
    public var vertices: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var triangleIndices: [UInt32]
    public var surfaces: [UInt8]

    public init(tracked: Bool, timestamp: Double, id: UUID, scan: UInt32 = 0,
                removed: Bool = false, transform: simd_float4x4,
                vertices: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [],
                triangleIndices: [UInt32] = [], surfaces: [UInt8] = []) {
        self.tracked = tracked
        self.timestamp = timestamp
        self.id = id
        self.scan = scan
        self.removed = removed
        self.transform = transform
        self.vertices = vertices
        self.normals = normals
        self.triangleIndices = triangleIndices
        self.surfaces = surfaces
    }
}

/// Which way a found surface faces: flat like a floor or a table top, or upright
/// like a wall. ARKit sorts every plane into one of the two, and a sketch that
/// wants somewhere to stand an object asks for the flat ones.
public enum PhonePlaneAlignment: UInt8, CaseIterable, Sendable {
    case horizontal = 0
    case vertical
}

/// One flat surface the phone has found, in the coordinate space of its own anchor:
/// `center` and `boundary` are anchor-local meters, and `transform` places that
/// origin in ARKit's fixed world (the same world `PhoneDepthSample.cameraTransform`
/// and the room mesh report). The surface always lies in the anchor's own XZ plane,
/// so its normal is the anchor's up axis whichever way it faces.
///
/// `width` and `height` are the size of the smallest upright box around it, turned
/// by `rotationOnYAxis` so a table at an angle still measures as a table rather than
/// as the bigger box holding it. `boundary` is the real outline, a **convex** polygon
/// ARKit fits around everything it has seen of the surface, which is what a sketch
/// draws when a rectangle is too coarse.
///
/// `id`, `scan`, and `removed` work exactly as they do for a mesh block: the same
/// `id` arrives again with a better shape, a new `scan` number means the phone
/// restarted and the old world is gone, and a removal carries no geometry (ARKit
/// retires a plane when it merges it into a bigger one).
public struct PhonePlaneSample: Sendable, Equatable {
    public var tracked: Bool
    public var timestamp: Double
    public var id: UUID
    public var scan: UInt32
    public var removed: Bool
    public var transform: simd_float4x4
    public var center: SIMD3<Float>
    public var width: Float
    public var height: Float
    public var rotationOnYAxis: Float
    public var alignment: PhonePlaneAlignment
    public var surface: UInt8
    public var boundary: [SIMD3<Float>]

    public init(tracked: Bool, timestamp: Double, id: UUID, scan: UInt32 = 0,
                removed: Bool = false, transform: simd_float4x4,
                center: SIMD3<Float> = .zero, width: Float = 0, height: Float = 0,
                rotationOnYAxis: Float = 0, alignment: PhonePlaneAlignment = .horizontal,
                surface: UInt8 = 0, boundary: [SIMD3<Float>] = []) {
        self.tracked = tracked
        self.timestamp = timestamp
        self.id = id
        self.scan = scan
        self.removed = removed
        self.transform = transform
        self.center = center
        self.width = width
        self.height = height
        self.rotationOnYAxis = rotationOnYAxis
        self.alignment = alignment
        self.surface = surface
        self.boundary = boundary
    }
}

/// What the phone measures of the light around it, read off the camera image.
///
/// `ambientIntensity` is in lumens, where **1000 is ordinary indoor light**, and
/// `colorTemperature` is in kelvin, where **6500 is neutral white**. Lower is the
/// warm yellow of a lamp, higher the cool blue of a window or an overcast sky.
///
/// The rest arrives only in Face mode. Watching a face gives ARKit enough to say
/// where the light comes from, so `hasDirection` turns on and brings `direction`
/// (the way the strongest light travels, in world space), `directionalIntensity`
/// (lumens), and the 27 `sphericalHarmonics` coefficients (nine per color channel,
/// the compact description of light arriving from every direction at once). A
/// world-facing session has no face to read, so it sends the two ambient numbers
/// on their own.
public struct PhoneLightSample: Sendable, Equatable {
    public var timestamp: Double
    public var ambientIntensity: Float
    public var colorTemperature: Float
    public var hasDirection: Bool
    public var direction: SIMD3<Float>
    public var directionalIntensity: Float
    public var sphericalHarmonics: [Float]

    public init(timestamp: Double, ambientIntensity: Float, colorTemperature: Float,
                hasDirection: Bool = false, direction: SIMD3<Float> = .zero,
                directionalIntensity: Float = 0, sphericalHarmonics: [Float] = []) {
        self.timestamp = timestamp
        self.ambientIntensity = ambientIntensity
        self.colorTemperature = colorTemperature
        self.hasDirection = hasDirection
        self.direction = direction
        self.directionalIntensity = directionalIntensity
        self.sphericalHarmonics = sphericalHarmonics
    }
}

/// A decoded message of any kind, which the unit tests round-trip.
public enum PhoneMessage: Sendable, Equatable {
    case motion(PhoneMotionSample)
    /// Every body ARKit currently tracks, bundled into one frame (the tracker
    /// follows one today). The list is the complete current set, empty when no
    /// body is in view, so the reader swaps it in wholesale and a person leaving
    /// clears themselves.
    case pose([PhonePoseSample])
    /// Every face ARKit currently tracks, bundled into one frame (TrueDepth tracks
    /// up to 3). The list is the complete current set — empty when no face is in
    /// view — so the reader swaps it in wholesale and a face leaving clears itself.
    case face([PhoneFaceSample])
    case depth(PhoneDepthSample)
    case segmentation(PhoneSegmentationSample)
    /// One block of the reconstructed room surface, keyed by its own id. Blocks
    /// arrive one at a time and keep arriving as the scan improves.
    case sceneMesh(PhoneSceneMeshSample)
    /// One flat surface, keyed by its own id, arriving and growing the same way a
    /// mesh block does.
    case plane(PhonePlaneSample)
    /// How bright and how warm the room is, a few times a second.
    case light(PhoneLightSample)

    public var kind: PhoneMessageKind {
        switch self {
        case .motion: return .deviceMotion
        case .pose: return .bodyPose
        case .face: return .face
        case .depth: return .depth
        case .segmentation: return .segmentation
        case .sceneMesh: return .sceneMesh
        case .plane: return .plane
        case .light: return .light
        }
    }
}

/// The parsed frame header — the kind and the payload length that follows it.
public struct PhoneHeader: Sendable, Equatable {
    public var kind: PhoneMessageKind
    public var payloadLength: Int

    public init(kind: PhoneMessageKind, payloadLength: Int) {
        self.kind = kind
        self.payloadLength = payloadLength
    }

    /// Parse a 12-byte header. Returns `nil` if the buffer is short, the magic or
    /// version mismatch (a desynchronized stream), the kind is unknown, or the
    /// payload length is implausible — any of which means drop and resync.
    public static func parse(_ data: Data) -> PhoneHeader? {
        guard data.count >= PhoneWire.headerByteCount else { return nil }
        let s = data.startIndex
        func u32(_ off: Int) -> UInt32 {
            UInt32(data[s + off]) | (UInt32(data[s + off + 1]) << 8)
                | (UInt32(data[s + off + 2]) << 16) | (UInt32(data[s + off + 3]) << 24)
        }
        guard u32(0) == PhoneWire.magic else { return nil }
        guard data[s + 4] == PhoneWire.version else { return nil }
        guard let kind = PhoneMessageKind(rawValue: data[s + 5]) else { return nil }
        let length = Int(u32(8))
        guard length >= 0, length <= PhoneWire.maxPayloadBytes else { return nil }
        return PhoneHeader(kind: kind, payloadLength: length)
    }
}

// MARK: - Encoding

public extension PhoneWire {

    /// Encode a full frame (header + payload) ready to write to the socket.
    static func encode(_ message: PhoneMessage) -> Data {
        let payload: Data
        switch message {
        case .motion(let m): payload = encodeMotionPayload(m)
        case .pose(let p): payload = encodePosePayload(p)
        case .face(let faces): payload = encodeFacePayload(faces)
        case .depth(let d): payload = encodeDepthPayload(d)
        case .segmentation(let seg): payload = encodeSegmentationPayload(seg)
        case .sceneMesh(let chunk): payload = encodeSceneMeshPayload(chunk)
        case .plane(let plane): payload = encodePlanePayload(plane)
        case .light(let light): payload = encodeLightPayload(light)
        }
        var out = Data()
        appendU32(&out, magic)
        out.append(version)
        out.append(message.kind.rawValue)
        out.append(0); out.append(0)             // reserved
        appendU32(&out, UInt32(payload.count))
        out.append(payload)
        return out
    }

    private static func encodeMotionPayload(_ m: PhoneMotionSample) -> Data {
        var p = Data()
        for v in [m.attitude.x, m.attitude.y, m.attitude.z, m.attitude.w] { appendF32(&p, v) }
        for v in [m.gravity.x, m.gravity.y, m.gravity.z] { appendF32(&p, v) }
        for v in [m.rotationRate.x, m.rotationRate.y, m.rotationRate.z] { appendF32(&p, v) }
        for v in [m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z] { appendF32(&p, v) }
        appendF64(&p, m.timestamp)
        return p
    }

    private static func encodePosePayload(_ bodies: [PhonePoseSample]) -> Data {
        var p = Data()
        // A body count, then that many self-contained body records (the count is
        // capped at 255 defensively; ARKit follows one body today).
        p.append(UInt8(min(bodies.count, 255)))
        for body in bodies.prefix(255) { appendPoseRecord(&p, body) }
        return p
    }

    /// One body record: tracked, timestamp, the world anchor, the scale factor,
    /// and the joints. Self-contained so the list decoder reads records back to back.
    private static func appendPoseRecord(_ p: inout Data, _ pose: PhonePoseSample) {
        p.append(pose.tracked ? 1 : 0)
        appendF64(&p, pose.timestamp)
        appendMatrix(&p, pose.anchor)
        appendF32(&p, pose.scaleFactor)
        appendU16(&p, UInt16(pose.joints.count))
        // Sorted by joint id so the encoding is deterministic (round-trip stable).
        for joint in pose.joints.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            let j = pose.joints[joint]!
            p.append(joint.rawValue)
            appendF32(&p, j.position.x); appendF32(&p, j.position.y); appendF32(&p, j.position.z)
            for v in [j.orientation.x, j.orientation.y, j.orientation.z, j.orientation.w] {
                appendF32(&p, v)
            }
            p.append(j.tracked ? 1 : 0)
        }
    }

    private static func encodeFacePayload(_ faces: [PhoneFaceSample]) -> Data {
        var p = Data()
        // A face count, then that many self-contained face records (ARKit tracks up
        // to 3; the count is capped at 255 defensively).
        p.append(UInt8(min(faces.count, 255)))
        for face in faces.prefix(255) { appendFaceRecord(&p, face) }
        return p
    }

    /// One face record — tracked, timestamp, head pose, the positional blendshapes,
    /// and the face-local mesh. Self-contained so the list decoder reads records back
    /// to back.
    private static func appendFaceRecord(_ p: inout Data, _ face: PhoneFaceSample) {
        p.append(face.tracked ? 1 : 0)
        appendF64(&p, face.timestamp)
        for v in [face.headOrientation.x, face.headOrientation.y,
                  face.headOrientation.z, face.headOrientation.w] { appendF32(&p, v) }
        for v in [face.headPosition.x, face.headPosition.y, face.headPosition.z] { appendF32(&p, v) }
        // Blendshapes: a count, then that many floats (positional, PhoneBlendShape order).
        p.append(UInt8(min(face.blendShapes.count, 255)))
        for v in face.blendShapes.prefix(255) { appendF32(&p, v) }
        // Mesh: a vertex count, then xyz per vertex (face-local space).
        appendU16(&p, UInt16(min(face.meshVertices.count, Int(UInt16.max))))
        for v in face.meshVertices.prefix(Int(UInt16.max)) {
            appendF32(&p, v.x); appendF32(&p, v.y); appendF32(&p, v.z)
        }
        // Topology: an index count, then three vertex indices per triangle. Constant
        // per device, but small (~7k indices), so it's sent each frame for simplicity.
        appendU32(&p, UInt32(face.triangleIndices.count))
        for i in face.triangleIndices { appendU16(&p, i) }
    }

    private static func encodeDepthPayload(_ d: PhoneDepthSample) -> Data {
        var p = Data()
        p.append(d.tracked ? 1 : 0)
        appendF64(&p, d.timestamp)
        appendU32(&p, UInt32(max(0, d.depthWidth)))
        appendU32(&p, UInt32(max(0, d.depthHeight)))
        for v in [d.fx, d.fy, d.cx, d.cy] { appendF32(&p, v) }
        appendMatrix(&p, d.cameraTransform)
        // Color: a JPEG byte count, then the JPEG bytes (decoded on the Mac side).
        appendU32(&p, UInt32(d.colorJPEG.count))
        p.append(d.colorJPEG)
        // Depth: a sample count, then raw little-endian float32 meters.
        appendU32(&p, UInt32(d.depth.count))
        for v in d.depth { appendF32(&p, v) }
        // Confidence: a present flag, then (if present) a count + the raw bytes.
        if let conf = d.confidence {
            p.append(1)
            appendU32(&p, UInt32(conf.count))
            p.append(contentsOf: conf)
        } else {
            p.append(0)
        }
        return p
    }

    private static func encodeSegmentationPayload(_ s: PhoneSegmentationSample) -> Data {
        var p = Data()
        p.append(s.tracked ? 1 : 0)
        appendF64(&p, s.timestamp)
        appendU32(&p, UInt32(max(0, s.matteWidth)))
        appendU32(&p, UInt32(max(0, s.matteHeight)))
        p.append(s.orientation)
        // Color: a JPEG byte count, then the JPEG bytes (decoded on the Mac side).
        appendU32(&p, UInt32(s.colorJPEG.count))
        p.append(s.colorJPEG)
        // Matte: a sample count, then the raw grayscale bytes (one per pixel).
        appendU32(&p, UInt32(s.matte.count))
        p.append(contentsOf: s.matte)
        return p
    }

    private static func encodeSceneMeshPayload(_ c: PhoneSceneMeshSample) -> Data {
        var p = Data()
        p.append(c.tracked ? 1 : 0)
        appendF64(&p, c.timestamp)
        appendUUID(&p, c.id)
        appendU32(&p, c.scan)
        p.append(c.removed ? 1 : 0)
        appendMatrix(&p, c.transform)
        // A retirement notice carries no geometry, so the counts stop here.
        guard !c.removed else { return p }
        // Vertices and normals: a count each, then xyz per entry (anchor-local).
        appendU32(&p, UInt32(c.vertices.count))
        for v in c.vertices { appendF32(&p, v.x); appendF32(&p, v.y); appendF32(&p, v.z) }
        appendU32(&p, UInt32(c.normals.count))
        for n in c.normals { appendF32(&p, n.x); appendF32(&p, n.y); appendF32(&p, n.z) }
        // Topology: an index count, then a vertex index each (three per triangle).
        appendU32(&p, UInt32(c.triangleIndices.count))
        for i in c.triangleIndices { appendU32(&p, i) }
        // Classification: a count, then one PhoneSurface raw value per triangle.
        appendU32(&p, UInt32(c.surfaces.count))
        p.append(contentsOf: c.surfaces)
        return p
    }

    private static func encodePlanePayload(_ p0: PhonePlaneSample) -> Data {
        var p = Data()
        p.append(p0.tracked ? 1 : 0)
        appendF64(&p, p0.timestamp)
        appendUUID(&p, p0.id)
        appendU32(&p, p0.scan)
        p.append(p0.removed ? 1 : 0)
        appendMatrix(&p, p0.transform)
        // A retirement notice carries no shape, so the rest stops here.
        guard !p0.removed else { return p }
        for v in [p0.center.x, p0.center.y, p0.center.z] { appendF32(&p, v) }
        for v in [p0.width, p0.height, p0.rotationOnYAxis] { appendF32(&p, v) }
        p.append(p0.alignment.rawValue)
        p.append(p0.surface)
        // The outline: a point count, then xyz per point (anchor-local).
        appendU32(&p, UInt32(p0.boundary.count))
        for v in p0.boundary { appendF32(&p, v.x); appendF32(&p, v.y); appendF32(&p, v.z) }
        return p
    }

    private static func encodeLightPayload(_ l: PhoneLightSample) -> Data {
        var p = Data()
        appendF64(&p, l.timestamp)
        appendF32(&p, l.ambientIntensity)
        appendF32(&p, l.colorTemperature)
        p.append(l.hasDirection ? 1 : 0)
        // Only a face session knows a direction, so the rest is there or it is not.
        guard l.hasDirection else { return p }
        for v in [l.direction.x, l.direction.y, l.direction.z] { appendF32(&p, v) }
        appendF32(&p, l.directionalIntensity)
        p.append(UInt8(min(l.sphericalHarmonics.count, 255)))
        for v in l.sphericalHarmonics.prefix(255) { appendF32(&p, v) }
        return p
    }

    /// The size the payload for `chunk` will take, so the phone can skip a block
    /// too big for one frame before it pays to encode it.
    static func sceneMeshPayloadSize(vertexCount: Int, indexCount: Int,
                                     surfaceCount: Int) -> Int {
        // tracked(1) + timestamp(8) + id(16) + scan(4) + removed(1) + transform(64),
        // then the four counts, then the positions and normals at 12 bytes each.
        94 + 16 + vertexCount * 24 + indexCount * 4 + surfaceCount
    }
}

// MARK: - Decoding

public extension PhoneWire {

    /// Decode a payload of the given kind into a message. Returns `nil` on a short
    /// or malformed payload (the reader treats that as a skipped frame, not a desync).
    static func decode(header: PhoneHeader, payload: Data) -> PhoneMessage? {
        switch header.kind {
        case .deviceMotion: return decodeMotion(payload).map(PhoneMessage.motion)
        case .bodyPose: return decodePose(payload).map(PhoneMessage.pose)
        case .face: return decodeFace(payload).map(PhoneMessage.face)
        case .depth: return decodeDepth(payload).map(PhoneMessage.depth)
        case .segmentation: return decodeSegmentation(payload).map(PhoneMessage.segmentation)
        case .sceneMesh: return decodeSceneMesh(payload).map(PhoneMessage.sceneMesh)
        case .plane: return decodePlane(payload).map(PhoneMessage.plane)
        case .light: return decodeLight(payload).map(PhoneMessage.light)
        }
    }

    private static func decodeMotion(_ data: Data) -> PhoneMotionSample? {
        // 13 floats + 1 double.
        guard data.count >= 13 * 4 + 8 else { return nil }
        let s = data.startIndex
        var o = 0
        func f32() -> Float { defer { o += 4 }; return readF32(data, s + o) }
        let attitude = SIMD4<Float>(f32(), f32(), f32(), f32())
        let gravity = SIMD3<Float>(f32(), f32(), f32())
        let rotationRate = SIMD3<Float>(f32(), f32(), f32())
        let userAcceleration = SIMD3<Float>(f32(), f32(), f32())
        let timestamp = readF64(data, s + o)
        return PhoneMotionSample(attitude: attitude, gravity: gravity, rotationRate: rotationRate,
                                 userAcceleration: userAcceleration, timestamp: timestamp)
    }

    private static func decodePose(_ data: Data) -> [PhonePoseSample]? {
        // A body count, then that many records. An empty set (count 0) is valid;
        // it means no body is in view this frame.
        guard !data.isEmpty else { return nil }
        let count = Int(data[data.startIndex])
        var o = 1
        var bodies = [PhonePoseSample](); bodies.reserveCapacity(count)
        for _ in 0..<count {
            guard let body = readPoseRecord(data, &o) else { return nil }
            bodies.append(body)
        }
        return bodies
    }

    /// Read one body record starting at offset `o` (advanced past the record on
    /// success), or `nil` if the buffer is short.
    private static func readPoseRecord(_ data: Data, _ o: inout Int) -> PhonePoseSample? {
        // Fixed prefix: tracked(1) + timestamp(8) + anchor(64) + scale(4) + jointCount(2).
        guard data.count >= o + 1 + 8 + 64 + 4 + 2 else { return nil }
        let s = data.startIndex
        let tracked = data[s + o] != 0; o += 1
        let timestamp = readF64(data, s + o); o += 8
        let anchor = readMatrix(data, s + o); o += 64
        let scaleFactor = readF32(data, s + o); o += 4
        let count = Int(UInt16(data[s + o]) | (UInt16(data[s + o + 1]) << 8)); o += 2
        // Per joint: id(1) + position(12) + orientation(16) + tracked(1).
        guard data.count >= o + count * 30 else { return nil }
        var joints: [PhoneJoint: PhoneJointSample] = [:]
        joints.reserveCapacity(count)
        for _ in 0..<count {
            let raw = data[s + o]; o += 1
            func f32() -> Float { defer { o += 4 }; return readF32(data, s + o) }
            let position = SIMD3<Float>(f32(), f32(), f32())
            let orientation = SIMD4<Float>(f32(), f32(), f32(), f32())
            let jointTracked = data[s + o] != 0; o += 1
            if let joint = PhoneJoint(rawValue: raw) {
                joints[joint] = PhoneJointSample(position: position, orientation: orientation,
                                                 tracked: jointTracked)
            }
        }
        return PhonePoseSample(tracked: tracked, timestamp: timestamp, anchor: anchor,
                               scaleFactor: scaleFactor, joints: joints)
    }

    private static func decodeFace(_ data: Data) -> [PhoneFaceSample]? {
        // A face count, then that many records. An empty set (count 0) is valid —
        // it means no face is in view this frame.
        guard !data.isEmpty else { return nil }
        let count = Int(data[data.startIndex])
        var o = 1
        var faces = [PhoneFaceSample](); faces.reserveCapacity(count)
        for _ in 0..<count {
            guard let face = readFaceRecord(data, &o) else { return nil }
            faces.append(face)
        }
        return faces
    }

    /// Read one face record starting at offset `o` (advanced past the record on
    /// success), or `nil` if the buffer is short.
    private static func readFaceRecord(_ data: Data, _ o: inout Int) -> PhoneFaceSample? {
        // Fixed prefix: tracked(1) + timestamp(8) + headOrientation(16) + headPosition(12) + bsCount(1).
        guard data.count >= o + 1 + 8 + 16 + 12 + 1 else { return nil }
        let s = data.startIndex
        func f32() -> Float { defer { o += 4 }; return readF32(data, s + o) }
        let tracked = data[s + o] != 0; o += 1
        let timestamp = readF64(data, s + o); o += 8
        let headOrientation = SIMD4<Float>(f32(), f32(), f32(), f32())
        let headPosition = SIMD3<Float>(f32(), f32(), f32())

        let bsCount = Int(data[s + o]); o += 1
        guard data.count >= o + bsCount * 4 + 2 else { return nil }
        var blendShapes = [Float](); blendShapes.reserveCapacity(bsCount)
        for _ in 0..<bsCount { blendShapes.append(f32()) }

        let vCount = Int(UInt16(data[s + o]) | (UInt16(data[s + o + 1]) << 8)); o += 2
        guard data.count >= o + vCount * 12 + 4 else { return nil }
        var meshVertices = [SIMD3<Float>](); meshVertices.reserveCapacity(vCount)
        for _ in 0..<vCount { meshVertices.append(SIMD3<Float>(f32(), f32(), f32())) }

        // Topology: an index count, then a UInt16 vertex index each.
        let iCount = Int(readU32(data, s + o)); o += 4
        guard data.count >= o + iCount * 2 else { return nil }
        var triangleIndices = [UInt16](); triangleIndices.reserveCapacity(iCount)
        for _ in 0..<iCount {
            triangleIndices.append(UInt16(data[s + o]) | (UInt16(data[s + o + 1]) << 8)); o += 2
        }

        return PhoneFaceSample(tracked: tracked, timestamp: timestamp, headOrientation: headOrientation,
                               headPosition: headPosition, blendShapes: blendShapes,
                               meshVertices: meshVertices, triangleIndices: triangleIndices)
    }

    private static func decodeDepth(_ data: Data) -> PhoneDepthSample? {
        // Fixed prefix: tracked(1) + timestamp(8) + dims(8) + intrinsics(16) + transform(64) + jpegLen(4).
        let prefix = 1 + 8 + 8 + 16 + 64 + 4
        guard data.count >= prefix else { return nil }
        let s = data.startIndex
        let tracked = data[s] != 0
        var o = 1
        func u32() -> Int { defer { o += 4 }; return Int(readU32(data, s + o)) }
        func f32() -> Float { defer { o += 4 }; return readF32(data, s + o) }
        let timestamp = readF64(data, s + o); o += 8
        let depthWidth = u32()
        let depthHeight = u32()
        let fx = f32(), fy = f32(), cx = f32(), cy = f32()
        let transform = readMatrix(data, s + o); o += 64

        let jpegLen = u32()
        guard jpegLen >= 0, data.count >= o + jpegLen + 4 else { return nil }
        let colorJPEG = Data(data[(s + o)..<(s + o + jpegLen)]); o += jpegLen

        let depthCount = u32()
        guard depthCount >= 0, data.count >= o + depthCount * 4 + 1 else { return nil }
        var depth = [Float](); depth.reserveCapacity(depthCount)
        for _ in 0..<depthCount { depth.append(f32()) }

        let hasConfidence = data[s + o] != 0; o += 1
        var confidence: [UInt8]?
        if hasConfidence {
            guard data.count >= o + 4 else { return nil }
            let confCount = u32()
            guard confCount >= 0, data.count >= o + confCount else { return nil }
            confidence = [UInt8](data[(s + o)..<(s + o + confCount)])
        }

        return PhoneDepthSample(tracked: tracked, timestamp: timestamp,
                                depthWidth: depthWidth, depthHeight: depthHeight,
                                fx: fx, fy: fy, cx: cx, cy: cy, cameraTransform: transform,
                                colorJPEG: colorJPEG, depth: depth, confidence: confidence)
    }

    private static func decodeSegmentation(_ data: Data) -> PhoneSegmentationSample? {
        // Fixed prefix: tracked(1) + timestamp(8) + dims(8) + orientation(1) + jpegLen(4).
        let prefix = 1 + 8 + 8 + 1 + 4
        guard data.count >= prefix else { return nil }
        let s = data.startIndex
        let tracked = data[s] != 0
        var o = 1
        func u32() -> Int { defer { o += 4 }; return Int(readU32(data, s + o)) }
        let timestamp = readF64(data, s + o); o += 8
        let matteWidth = u32()
        let matteHeight = u32()
        let orientation = data[s + o]; o += 1

        let jpegLen = u32()
        guard jpegLen >= 0, data.count >= o + jpegLen + 4 else { return nil }
        let colorJPEG = Data(data[(s + o)..<(s + o + jpegLen)]); o += jpegLen

        let matteCount = u32()
        guard matteCount >= 0, data.count >= o + matteCount else { return nil }
        let matte = [UInt8](data[(s + o)..<(s + o + matteCount)])

        return PhoneSegmentationSample(tracked: tracked, timestamp: timestamp,
                                       matteWidth: matteWidth, matteHeight: matteHeight,
                                       orientation: orientation, matte: matte, colorJPEG: colorJPEG)
    }

    private static func decodeSceneMesh(_ data: Data) -> PhoneSceneMeshSample? {
        // Fixed prefix: tracked(1) + timestamp(8) + id(16) + scan(4) + removed(1) + transform(64).
        let prefix = 1 + 8 + 16 + 4 + 1 + 64
        guard data.count >= prefix else { return nil }
        let s = data.startIndex
        var o = 0
        func u32() -> Int { defer { o += 4 }; return Int(readU32(data, s + o)) }
        func f32() -> Float { defer { o += 4 }; return readF32(data, s + o) }

        let tracked = data[s] != 0; o += 1
        let timestamp = readF64(data, s + o); o += 8
        let id = readUUID(data, s + o); o += 16
        let scan = readU32(data, s + o); o += 4
        let removed = data[s + o] != 0; o += 1
        let transform = readMatrix(data, s + o); o += 64

        // A retirement notice ends here, with no geometry to read.
        guard !removed else {
            return PhoneSceneMeshSample(tracked: tracked, timestamp: timestamp, id: id,
                                        scan: scan, removed: true, transform: transform)
        }

        guard data.count >= o + 4 else { return nil }
        let vertexCount = u32()
        guard vertexCount >= 0, data.count >= o + vertexCount * 12 + 4 else { return nil }
        var vertices = [SIMD3<Float>](); vertices.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount { vertices.append(SIMD3<Float>(f32(), f32(), f32())) }

        let normalCount = u32()
        guard normalCount >= 0, data.count >= o + normalCount * 12 + 4 else { return nil }
        var normals = [SIMD3<Float>](); normals.reserveCapacity(normalCount)
        for _ in 0..<normalCount { normals.append(SIMD3<Float>(f32(), f32(), f32())) }

        let indexCount = u32()
        guard indexCount >= 0, data.count >= o + indexCount * 4 + 4 else { return nil }
        var triangleIndices = [UInt32](); triangleIndices.reserveCapacity(indexCount)
        for _ in 0..<indexCount { triangleIndices.append(UInt32(u32())) }

        let surfaceCount = u32()
        guard surfaceCount >= 0, data.count >= o + surfaceCount else { return nil }
        let surfaces = [UInt8](data[(s + o)..<(s + o + surfaceCount)])

        return PhoneSceneMeshSample(tracked: tracked, timestamp: timestamp, id: id,
                                    scan: scan, removed: false, transform: transform,
                                    vertices: vertices, normals: normals,
                                    triangleIndices: triangleIndices, surfaces: surfaces)
    }

    private static func decodePlane(_ data: Data) -> PhonePlaneSample? {
        // Fixed prefix: tracked(1) + timestamp(8) + id(16) + scan(4) + removed(1) + transform(64).
        let prefix = 1 + 8 + 16 + 4 + 1 + 64
        guard data.count >= prefix else { return nil }
        let s = data.startIndex
        var o = 0
        func u32() -> Int { defer { o += 4 }; return Int(readU32(data, s + o)) }
        func f32() -> Float { defer { o += 4 }; return readF32(data, s + o) }

        let tracked = data[s] != 0; o += 1
        let timestamp = readF64(data, s + o); o += 8
        let id = readUUID(data, s + o); o += 16
        let scan = readU32(data, s + o); o += 4
        let removed = data[s + o] != 0; o += 1
        let transform = readMatrix(data, s + o); o += 64

        // A retirement notice ends here, with no shape to read.
        guard !removed else {
            return PhonePlaneSample(tracked: tracked, timestamp: timestamp, id: id,
                                    scan: scan, removed: true, transform: transform)
        }

        // center(12) + width/height/rotation(12) + alignment(1) + surface(1) + count(4).
        guard data.count >= o + 12 + 12 + 1 + 1 + 4 else { return nil }
        let center = SIMD3<Float>(f32(), f32(), f32())
        let width = f32(), height = f32(), rotation = f32()
        let alignment = PhonePlaneAlignment(rawValue: data[s + o]) ?? .horizontal; o += 1
        let surface = data[s + o]; o += 1

        let pointCount = u32()
        guard pointCount >= 0, data.count >= o + pointCount * 12 else { return nil }
        var boundary = [SIMD3<Float>](); boundary.reserveCapacity(pointCount)
        for _ in 0..<pointCount { boundary.append(SIMD3<Float>(f32(), f32(), f32())) }

        return PhonePlaneSample(tracked: tracked, timestamp: timestamp, id: id, scan: scan,
                                removed: false, transform: transform, center: center,
                                width: width, height: height, rotationOnYAxis: rotation,
                                alignment: alignment, surface: surface, boundary: boundary)
    }

    private static func decodeLight(_ data: Data) -> PhoneLightSample? {
        // Fixed prefix: timestamp(8) + ambient(4) + temperature(4) + hasDirection(1).
        guard data.count >= 8 + 4 + 4 + 1 else { return nil }
        let s = data.startIndex
        var o = 0
        func f32() -> Float { defer { o += 4 }; return readF32(data, s + o) }
        let timestamp = readF64(data, s + o); o += 8
        let ambient = f32()
        let temperature = f32()
        let hasDirection = data[s + o] != 0; o += 1
        guard hasDirection else {
            return PhoneLightSample(timestamp: timestamp, ambientIntensity: ambient,
                                    colorTemperature: temperature)
        }

        // direction(12) + intensity(4) + coefficient count(1).
        guard data.count >= o + 12 + 4 + 1 else { return nil }
        let direction = SIMD3<Float>(f32(), f32(), f32())
        let intensity = f32()
        let shCount = Int(data[s + o]); o += 1
        guard data.count >= o + shCount * 4 else { return nil }
        var harmonics = [Float](); harmonics.reserveCapacity(shCount)
        for _ in 0..<shCount { harmonics.append(f32()) }

        return PhoneLightSample(timestamp: timestamp, ambientIntensity: ambient,
                                colorTemperature: temperature, hasDirection: true,
                                direction: direction, directionalIntensity: intensity,
                                sphericalHarmonics: harmonics)
    }
}

// MARK: - Little-endian byte helpers

private extension PhoneWire {
    static func appendU16(_ d: inout Data, _ v: UInt16) {
        var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }
    static func appendU32(_ d: inout Data, _ v: UInt32) {
        var le = v.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }
    static func appendF32(_ d: inout Data, _ v: Float) { appendU32(&d, v.bitPattern) }
    static func appendF64(_ d: inout Data, _ v: Double) {
        var le = v.bitPattern.littleEndian; withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
    }
    /// 16 floats, column-major (`simd` order): columns 0…3, each `(x, y, z, w)`.
    static func appendMatrix(_ d: inout Data, _ m: simd_float4x4) {
        for c in 0..<4 { let col = m[c]; for v in [col.x, col.y, col.z, col.w] { appendF32(&d, v) } }
    }
    static func readMatrix(_ d: Data, _ i: Data.Index) -> simd_float4x4 {
        var cols = [SIMD4<Float>]()
        for c in 0..<4 {
            let base = i + c * 16
            cols.append(SIMD4<Float>(readF32(d, base), readF32(d, base + 4),
                                     readF32(d, base + 8), readF32(d, base + 12)))
        }
        return simd_float4x4(cols[0], cols[1], cols[2], cols[3])
    }
    /// A UUID as its 16 raw bytes, in the order `UUID.uuid` reports them.
    static func appendUUID(_ d: inout Data, _ id: UUID) {
        withUnsafeBytes(of: id.uuid) { d.append(contentsOf: $0) }
    }
    static func readUUID(_ d: Data, _ i: Data.Index) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for k in 0..<16 { bytes[k] = d[i + k] }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    static func readU32(_ d: Data, _ i: Data.Index) -> UInt32 {
        UInt32(d[i]) | (UInt32(d[i + 1]) << 8) | (UInt32(d[i + 2]) << 16) | (UInt32(d[i + 3]) << 24)
    }
    static func readF32(_ d: Data, _ i: Data.Index) -> Float { Float(bitPattern: readU32(d, i)) }
    static func readF64(_ d: Data, _ i: Data.Index) -> Double {
        var bits: UInt64 = 0
        for k in 0..<8 { bits |= UInt64(d[i + k]) << (8 * k) }
        return Double(bitPattern: bits)
    }
}
