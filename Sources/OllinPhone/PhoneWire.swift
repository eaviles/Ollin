// PhoneWire — the sensor-stream wire format shared by the Ollin iPhone capture
// app (Apps/OllinPhoneApp) and the Mac satellite (OllinPhone).
//
// LOAD-BEARING: this file is compiled *verbatim into both ends*. The iOS app
// includes it directly in its xcodegen sources, and it must not pull in Ollin or
// Metal — so this file imports only Foundation + simd. Everything Ollin-specific
// (Vector3, PointCloud, the device) lives in the other OllinPhone files, which
// the iOS app never sees. Keep this file dependency-free.
//
// The framing mirrors the usbmuxd-tunnelled stream the Record3D reader uses: a
// fixed little-endian header, then a tagged payload the reader decodes by kind.

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
    /// Distinct from Record3D's 1337. Shared by both ends (this file compiles into
    /// the iOS app too), so the port can't drift between them.
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

/// A decoded message of either kind — the unit tests round-trip this.
public enum PhoneMessage: Sendable, Equatable {
    case motion(PhoneMotionSample)
    case pose(PhonePoseSample)

    public var kind: PhoneMessageKind {
        switch self {
        case .motion: return .deviceMotion
        case .pose: return .bodyPose
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
}

// MARK: - Decoding

public extension PhoneWire {

    /// Decode a payload of the given kind into a message. Returns `nil` on a short
    /// or malformed payload (the reader treats that as a skipped frame, not a desync).
    static func decode(header: PhoneHeader, payload: Data) -> PhoneMessage? {
        switch header.kind {
        case .deviceMotion: return decodeMotion(payload).map(PhoneMessage.motion)
        case .bodyPose: return decodePose(payload).map(PhoneMessage.pose)
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
