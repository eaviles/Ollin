import Testing
import Foundation
import simd
import CoreGraphics
import Ollin
import OllinPhone
import OllinUSBMux
#if canImport(Darwin)
import Darwin
#endif

/// Exercises the phone sensor-stream wire format — the framing header plus the
/// motion, body-pose, face, depth, and segmentation payload codecs — with encode/decode
/// round-trips (GPU-free, CI-safe), plus a live-device test that soft-skips when no
/// phone is streaming.
@Suite struct PhoneWireTests {

    // MARK: Round-trips

    @Test func roundTripsMotion() {
        let message = PhoneMessage.motion(PhoneMotionSample(
            attitude: SIMD4<Float>(0.1, 0.2, 0.3, 0.9),
            gravity: SIMD3<Float>(0, -1, 0),
            rotationRate: SIMD3<Float>(0.01, -0.02, 0.03),
            userAcceleration: SIMD3<Float>(0.12, 0, -0.04),
            timestamp: 12.5))
        #expect(roundTrip(message) == message)
    }

    @Test func roundTripsPose() {
        let joints: [PhoneJoint: SIMD3<Float>] = [
            .root: SIMD3<Float>(0, 0, 0),
            .head: SIMD3<Float>(0, 1.62, 0),
            .leftHand: SIMD3<Float>(-0.55, 1.0, 0.1),
            .rightAnkle: SIMD3<Float>(0.18, -0.9, 0.02),
        ]
        let message = PhoneMessage.pose(PhonePoseSample(tracked: true, timestamp: 3.25, joints: joints))
        #expect(roundTrip(message) == message)
    }

    @Test func roundTripsEmptyPose() {
        // No body in view: tracked is false and there are zero joints.
        let message = PhoneMessage.pose(PhonePoseSample(tracked: false, timestamp: 1, joints: [:]))
        #expect(roundTrip(message) == message)
    }

    @Test func roundTripsFace() {
        // A full face: all 52 blendshapes, a small mesh, and a head pose.
        let blendShapes = (0..<PhoneBlendShape.allCases.count).map { Float($0) / 100 }
        let mesh = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(0.01, -0.02, 0.03), SIMD3<Float>(-0.04, 0.05, -0.06)]
        let message = PhoneMessage.face([PhoneFaceSample(
            tracked: true, timestamp: 8.75,
            headOrientation: SIMD4<Float>(0.1, 0.2, 0.3, 0.9),
            headPosition: SIMD3<Float>(0.05, -0.1, -0.4),
            blendShapes: blendShapes, meshVertices: mesh)])
        #expect(roundTrip(message) == message)
    }

    @Test func roundTripsFaceWithoutMesh() {
        // Blendshapes only, no mesh vertices — the lightweight case.
        let message = PhoneMessage.face([PhoneFaceSample(
            tracked: false, timestamp: 0,
            headOrientation: SIMD4<Float>(0, 0, 0, 1), headPosition: .zero,
            blendShapes: [Float](repeating: 0, count: PhoneBlendShape.allCases.count),
            meshVertices: [])])
        #expect(roundTrip(message) == message)
    }

    @Test func roundTripsMultipleFaces() {
        // Three faces at once — the TrueDepth maximum. Each carries its own pose,
        // blendshapes, and mesh, and they must come back in order.
        func face(_ i: Int) -> PhoneFaceSample {
            let f = Float(i)
            return PhoneFaceSample(
                tracked: i != 1, timestamp: Double(i),
                headOrientation: SIMD4<Float>(0.1 * f, 0.2 * f, 0.3 * f, 1),
                headPosition: SIMD3<Float>(0.2 * f - 0.2, 0, -0.5),
                blendShapes: (0..<PhoneBlendShape.allCases.count).map { Float($0 + i) / 100 },
                meshVertices: [SIMD3<Float>(f, -f, f), SIMD3<Float>(0.01 * f, 0.02, -0.03)])
        }
        let message = PhoneMessage.face([face(0), face(1), face(2)])
        #expect(roundTrip(message) == message)
    }

    @Test func roundTripsNoFaces() {
        // The empty set — sent when no face is in view, so the reader clears it (a
        // face leaving disappears) rather than holding the last one.
        let message = PhoneMessage.face([])
        #expect(roundTrip(message) == message)
    }

    @Test func roundTripsDepth() {
        // A small RGBD frame: a 4×2 depth grid, opaque JPEG-stand-in bytes, a
        // confidence map, intrinsics, and a 6DoF camera transform.
        let depth: [Float] = [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2]
        let confidence: [UInt8] = [2, 2, 1, 0, 2, 1, 2, 2]
        let transform = simd_float4x4(SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0),
                                      SIMD4<Float>(0, 0, 1, 0), SIMD4<Float>(0.1, 0.2, -0.3, 1))
        let message = PhoneMessage.depth(PhoneDepthSample(
            tracked: true, timestamp: 5.5, depthWidth: 4, depthHeight: 2,
            fx: 211.5, fy: 211.5, cx: 128.25, cy: 96.5, cameraTransform: transform,
            colorJPEG: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]), depth: depth, confidence: confidence))
        #expect(roundTrip(message) == message)
    }

    @Test func roundTripsDepthWithoutConfidence() {
        // The TrueDepth front camera (and a missing confidence map) — depth only.
        let message = PhoneMessage.depth(PhoneDepthSample(
            tracked: false, timestamp: 0, depthWidth: 2, depthHeight: 1,
            fx: 100, fy: 100, cx: 1, cy: 0.5, cameraTransform: matrix_identity_float4x4,
            colorJPEG: Data(), depth: [1.0, 2.0], confidence: nil))
        #expect(roundTrip(message) == message)
    }

    @Test func roundTripsSegmentation() {
        // A small person matte (3×2, 0…255), an upright-rotation count, plus opaque
        // JPEG-stand-in color bytes.
        let matte: [UInt8] = [0, 64, 128, 192, 255, 32]
        let message = PhoneMessage.segmentation(PhoneSegmentationSample(
            tracked: true, timestamp: 7.0, matteWidth: 3, matteHeight: 2, orientation: 1,
            matte: matte, colorJPEG: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])))
        #expect(roundTrip(message) == message)
    }

    @Test func roundTripsSegmentationEmptyColor() {
        // A matte with no color frame and no rotation — the degenerate case the codec
        // must survive.
        let message = PhoneMessage.segmentation(PhoneSegmentationSample(
            tracked: false, timestamp: 0, matteWidth: 2, matteHeight: 1, orientation: 0,
            matte: [10, 250], colorJPEG: Data()))
        #expect(roundTrip(message) == message)
    }

    @Test func rotatesCGImageClockwise() throws {
        // A 2×2 gray image (TL=10, TR=20, BL=30, BR=40). A 90° clockwise turn sends
        // the bottom-left pixel to the top-left; the matte and color rotate through
        // this same call by the same turn count, so pinning it pins their alignment.
        let plane: [UInt8] = [10, 20,
                              30, 40]
        let src = try #require(SegmentationImages.grayCGImage(fromPlane: plane, width: 2, height: 2))
        let rotated = try #require(rotatedCGImage(src, quarterTurnsCW: 1))
        #expect(rotated.width == 2 && rotated.height == 2)
        #expect(SegmentationImages.grayBytes(from: rotated, width: 2, height: 2) == [30, 10,
                                                                                     40, 20])
        // A multiple of 4 turns is the identity (the input is returned unchanged).
        let same = try #require(rotatedCGImage(src, quarterTurnsCW: 4))
        #expect(SegmentationImages.grayBytes(from: same, width: 2, height: 2) == plane)
    }

    @Test func blendShapeOrderIsContiguous() {
        // The wire carries blendshapes positionally, so the cases must be 0…51.
        let raws = PhoneBlendShape.allCases.map { Int($0.rawValue) }
        #expect(raws == Array(0..<PhoneBlendShape.allCases.count))
        #expect(PhoneBlendShape.allCases.count == 52)
    }

    // MARK: Header validation

    @Test func parsesHeader() {
        let data = PhoneWire.encode(.pose(PhonePoseSample(tracked: true, timestamp: 0, joints: [:])))
        let header = PhoneHeader.parse(data)
        #expect(header?.kind == .bodyPose)
        #expect(header?.payloadLength == data.count - PhoneWire.headerByteCount)
    }

    @Test func rejectsBadMagic() {
        var data = PhoneWire.encode(.motion(zeroMotion))
        data[0] = 0xFF                              // corrupt the magic
        #expect(PhoneHeader.parse(data) == nil)
    }

    @Test func rejectsWrongVersion() {
        var data = PhoneWire.encode(.motion(zeroMotion))
        data[4] = PhoneWire.version &+ 1            // bump the version byte
        #expect(PhoneHeader.parse(data) == nil)
    }

    @Test func rejectsUnknownKind() {
        var data = PhoneWire.encode(.motion(zeroMotion))
        data[5] = 0x7F                              // a kind byte we don't define
        #expect(PhoneHeader.parse(data) == nil)
    }

    @Test func rejectsShortHeader() {
        #expect(PhoneHeader.parse(Data([0x31, 0x4E])) == nil)
    }

    @Test func decodeRejectsTruncatedPayload() {
        // A valid header, but the pose payload is cut short — decode returns nil and
        // the reader treats it as a skipped frame (not a desync).
        let header = PhoneHeader(kind: .bodyPose, payloadLength: 4)
        #expect(PhoneWire.decode(header: header, payload: Data([1, 0, 0, 0])) == nil)
    }

    // MARK: Live device (soft-skips without a streaming phone)

    @Test func streamsFromConnectedDevice() {
        let devices = (try? USBMux.listDevices()) ?? []
        guard !devices.isEmpty else { return }     // nothing attached — skip
        let fd: Int32
        do { fd = try USBMux.connect(toPort: PhoneDevice.streamPort) }
        catch { return }                            // attached but the app isn't serving — skip
        defer { close(fd) }
        var timeout = timeval(tv_sec: 4, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let headerData = USBMux.readFully(fd, PhoneWire.headerByteCount)
        guard headerData.count == PhoneWire.headerByteCount,
              let header = PhoneHeader.parse(headerData) else {
            Issue.record("Connected to the stream but the first header didn't parse")
            return
        }
        let payload = USBMux.readFully(fd, header.payloadLength)
        #expect(payload.count == header.payloadLength)
        #expect(PhoneWire.decode(header: header, payload: payload) != nil)
    }

    // MARK: Helpers

    private let zeroMotion = PhoneMotionSample(
        attitude: SIMD4<Float>(0, 0, 0, 1), gravity: SIMD3<Float>(0, 0, -1),
        rotationRate: .zero, userAcceleration: .zero, timestamp: 0)

    /// Encode a message, split the framed bytes back into header + payload the way
    /// the reader does, and decode — the full wire trip.
    private func roundTrip(_ message: PhoneMessage) -> PhoneMessage? {
        let data = PhoneWire.encode(message)
        guard let header = PhoneHeader.parse(data) else { return nil }
        let start = data.startIndex + PhoneWire.headerByteCount
        let payload = data.subdata(in: start ..< data.endIndex)
        return PhoneWire.decode(header: header, payload: payload)
    }
}
