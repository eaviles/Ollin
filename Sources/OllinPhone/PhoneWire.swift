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

    /// Wire version. Bumped if the header or any payload layout changes.
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
    /// An ARKit body skeleton (named 3D joints in model space).
    case bodyPose = 2
    /// An ARKit face — the deforming mesh, the 52 expression blendshapes, and the
    /// head pose. The phone runs face tracking on its front TrueDepth camera, so it's
    /// mutually exclusive with body pose (which uses the rear camera).
    case face = 3
    /// A world-facing RGBD frame from the rear LiDAR — a metric depth map, a color
    /// image, the depth-grid intrinsics, optional per-pixel confidence, and the 6DoF
    /// camera pose, which unproject into a point cloud. The heaviest payload (hundreds
    /// of KB; depth is raw float32 — LZFSE compression is a later optimization), so it
    /// streams only while the app is in World mode (LiDAR rear camera).
    case depth = 4
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

/// One ARKit body-pose sample: every reported joint as a 3D position in **meters**,
/// model space (the pelvis root at the origin, x right, y up, z toward the camera —
/// ARKit's convention), plus whether ARKit currently has tracking.
public struct PhonePoseSample: Sendable, Equatable {
    public var tracked: Bool
    public var timestamp: Double
    public var joints: [PhoneJoint: SIMD3<Float>]

    public init(tracked: Bool, timestamp: Double, joints: [PhoneJoint: SIMD3<Float>]) {
        self.tracked = tracked
        self.timestamp = timestamp
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
/// `blendShapes` (positional, in `PhoneBlendShape` order), and the deforming
/// `meshVertices` in **face-local** space (centered on the face, meters) — ready to
/// draw as a point cloud, since 3D mode has no mesh primitive yet.
public struct PhoneFaceSample: Sendable, Equatable {
    public var tracked: Bool
    public var timestamp: Double
    public var headOrientation: SIMD4<Float>
    public var headPosition: SIMD3<Float>
    public var blendShapes: [Float]
    public var meshVertices: [SIMD3<Float>]

    public init(tracked: Bool, timestamp: Double, headOrientation: SIMD4<Float>,
                headPosition: SIMD3<Float>, blendShapes: [Float], meshVertices: [SIMD3<Float>]) {
        self.tracked = tracked
        self.timestamp = timestamp
        self.headOrientation = headOrientation
        self.headPosition = headPosition
        self.blendShapes = blendShapes
        self.meshVertices = meshVertices
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

/// A decoded message of any kind — the unit tests round-trip this.
public enum PhoneMessage: Sendable, Equatable {
    case motion(PhoneMotionSample)
    case pose(PhonePoseSample)
    case face(PhoneFaceSample)
    case depth(PhoneDepthSample)

    public var kind: PhoneMessageKind {
        switch self {
        case .motion: return .deviceMotion
        case .pose: return .bodyPose
        case .face: return .face
        case .depth: return .depth
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
        case .face(let f): payload = encodeFacePayload(f)
        case .depth(let d): payload = encodeDepthPayload(d)
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

    private static func encodePosePayload(_ pose: PhonePoseSample) -> Data {
        var p = Data()
        p.append(pose.tracked ? 1 : 0)
        appendF64(&p, pose.timestamp)
        appendU16(&p, UInt16(pose.joints.count))
        // Sorted by joint id so the encoding is deterministic (round-trip stable).
        for joint in pose.joints.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            let pos = pose.joints[joint]!
            p.append(joint.rawValue)
            appendF32(&p, pos.x); appendF32(&p, pos.y); appendF32(&p, pos.z)
        }
        return p
    }

    private static func encodeFacePayload(_ face: PhoneFaceSample) -> Data {
        var p = Data()
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
        return p
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

    private static func decodePose(_ data: Data) -> PhonePoseSample? {
        guard data.count >= 1 + 8 + 2 else { return nil }
        let s = data.startIndex
        let tracked = data[s] != 0
        let timestamp = readF64(data, s + 1)
        let count = Int(UInt16(data[s + 9]) | (UInt16(data[s + 10]) << 8))
        var o = 11
        guard data.count >= o + count * 13 else { return nil }
        var joints: [PhoneJoint: SIMD3<Float>] = [:]
        joints.reserveCapacity(count)
        for _ in 0..<count {
            let raw = data[s + o]; o += 1
            let x = readF32(data, s + o); o += 4
            let y = readF32(data, s + o); o += 4
            let z = readF32(data, s + o); o += 4
            if let joint = PhoneJoint(rawValue: raw) { joints[joint] = SIMD3<Float>(x, y, z) }
        }
        return PhonePoseSample(tracked: tracked, timestamp: timestamp, joints: joints)
    }

    private static func decodeFace(_ data: Data) -> PhoneFaceSample? {
        // Fixed prefix: tracked(1) + timestamp(8) + headOrientation(16) + headPosition(12) + bsCount(1).
        guard data.count >= 1 + 8 + 16 + 12 + 1 else { return nil }
        let s = data.startIndex
        let tracked = data[s] != 0
        var o = 1
        func f32() -> Float { defer { o += 4 }; return readF32(data, s + o) }
        let timestamp = readF64(data, s + o); o += 8
        let headOrientation = SIMD4<Float>(f32(), f32(), f32(), f32())
        let headPosition = SIMD3<Float>(f32(), f32(), f32())

        let bsCount = Int(data[s + o]); o += 1
        guard data.count >= o + bsCount * 4 + 2 else { return nil }
        var blendShapes = [Float](); blendShapes.reserveCapacity(bsCount)
        for _ in 0..<bsCount { blendShapes.append(f32()) }

        let vCount = Int(UInt16(data[s + o]) | (UInt16(data[s + o + 1]) << 8)); o += 2
        guard data.count >= o + vCount * 12 else { return nil }
        var meshVertices = [SIMD3<Float>](); meshVertices.reserveCapacity(vCount)
        for _ in 0..<vCount { meshVertices.append(SIMD3<Float>(f32(), f32(), f32())) }

        return PhoneFaceSample(tracked: tracked, timestamp: timestamp, headOrientation: headOrientation,
                               headPosition: headPosition, blendShapes: blendShapes, meshVertices: meshVertices)
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
