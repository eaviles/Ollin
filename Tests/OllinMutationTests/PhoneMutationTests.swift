import Foundation
import simd
import Testing
import Ollin
import OllinMutation
@testable import OllinPhone

/// The phone wire in both directions under the mutation harness: every sensor
/// message kind the phone sends, read through the converters a sketch reads it
/// with (a scene chunk, a plane), and every request the Mac sends the phone,
/// the picture and its parameter sets handed to the framing the phone builds
/// a decoder from (CoreMedia's description and sample buffer, never the
/// hardware decoder).
@Suite struct PhoneMutationTests {

    static let transform = simd_float4x4(SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, 1, 0, 0),
                                         SIMD4<Float>(0, 0, 1, 0), SIMD4<Float>(0.4, 0.9, -2.5, 1))
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])

    static func messages() -> [PhoneMessage] {
        let joints: [PhoneJoint: PhoneJointSample] = [
            .root: PhoneJointSample(position: SIMD3<Float>(0, 0, 0)),
            .head: PhoneJointSample(position: SIMD3<Float>(0, 1.62, 0), orientation: SIMD4<Float>(0, 0.383, 0, 0.924)),
            .leftHand: PhoneJointSample(position: SIMD3<Float>(-0.55, 1, 0.1), isTracked: false),
        ]
        let hand: [PhoneHandJoint: PhoneHandJointSample] = [
            .wrist: PhoneHandJointSample(point: SIMD2<Float>(0.5, 0.5)),
            .indexTip: PhoneHandJointSample(point: SIMD2<Float>(0.6, 0.4), confidence: 0.9,
                                            hasWorldPosition: true, worldPosition: SIMD3<Float>(0.1, 0.2, 0.3)),
        ]
        let square: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(1, 1, 0)]
        return [
            .motion(PhoneMotionSample(attitude: SIMD4<Float>(0.1, 0.2, 0.3, 0.9), gravity: SIMD3<Float>(0, -1, 0),
                                      rotationRate: SIMD3<Float>(0.01, -0.02, 0.03),
                                      userAcceleration: SIMD3<Float>(0.12, 0, -0.04), timestamp: 12.5)),
            .pose([PhonePoseSample(isTracked: true, timestamp: 3.25, anchor: transform, scaleFactor: 0.93, joints: joints)]),
            .face([PhoneFaceSample(isTracked: true, timestamp: 1, headOrientation: SIMD4<Float>(0, 0, 0, 1),
                                   headPosition: SIMD3<Float>(0, 0, -0.5), blendShapes: [Float](repeating: 0.25, count: 52),
                                   meshVertices: Array(square.prefix(3)), triangleIndices: [0, 1, 2],
                                   textureCoordinates: [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 1)])]),
            .depth(PhoneDepthSample(isTracked: true, timestamp: 5.5, depthWidth: 4, depthHeight: 2,
                                    fx: 211.5, fy: 211.5, cx: 128.25, cy: 96.5, cameraTransform: transform,
                                    colorJPEG: jpeg, depth: [0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2],
                                    confidence: [2, 2, 1, 0, 2, 1, 2, 2])),
            .segmentation(PhoneSegmentationSample(isTracked: true, timestamp: 7, matteWidth: 3, matteHeight: 2,
                                                  orientation: 1, matte: [0, 64, 128, 192, 255, 32], colorJPEG: jpeg)),
            .sceneMesh(PhoneSceneMeshSample(isTracked: true, timestamp: 2, id: UUID(), scan: 3, isRemoved: false,
                                            transform: transform, vertices: square,
                                            normals: [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 1), count: 4),
                                            triangleIndices: [0, 1, 2, 2, 1, 3], surfaces: [.wall, .floor])),
            .sceneMesh(PhoneSceneMeshSample(isTracked: true, timestamp: 2, id: UUID(), scan: 4, isRemoved: true,
                                            transform: transform)),
            .plane(PhonePlaneSample(isTracked: true, timestamp: 2, id: UUID(), scan: 1, isRemoved: false,
                                    transform: transform, center: .zero, width: 1.2, height: 0.8,
                                    rotationOnYAxis: 0.3, alignment: .horizontal, surface: .table,
                                    boundary: [SIMD3<Float>(-0.6, 0, -0.4), SIMD3<Float>(0.6, 0, -0.4),
                                               SIMD3<Float>(0.6, 0, 0.4), SIMD3<Float>(-0.6, 0, 0.4)])),
            .plane(PhonePlaneSample(isTracked: true, timestamp: 2, id: UUID(), transform: transform,
                                    width: 1, height: 1, alignment: .vertical, surface: .wall)),
            .light(PhoneLightSample(timestamp: 1, ambientIntensity: 800, colorTemperature: 5600, hasDirection: true,
                                    direction: SIMD3<Float>(0, -1, 0), directionalIntensity: 900,
                                    sphericalHarmonics: [Float](repeating: 0.1, count: 27))),
            .hands([PhoneHandSample(isTracked: true, timestamp: 1, chirality: .left, confidence: 0.8, joints: hand)]),
            .texts([PhoneTextSample(isTracked: true, timestamp: 1, text: "EXIT", confidence: 0.9,
                                    corners: [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1)],
                                    hasWorldCorners: true, worldCorners: square)]),
            .markers([PhoneMarkerSample(isTracked: true, timestamp: 1, id: UUID(), name: "poster", kind: .image,
                                        transform: transform, size: SIMD3<Float>(0.3, 0.4, 0))]),
            .wand(PhoneWandSample(isTracked: true, timestamp: 1, transform: transform, quarterTurnsCW: 1,
                                  isPressed: true, pressCount: 3, hasTouch: true, touch: SIMD2<Float>(0.2, 0.7))),
            .saliency(PhoneSaliencySample(isTracked: true, timestamp: 1, heatWidth: 2, heatHeight: 2,
                                          heat: [0, 128, 255, 64], colorJPEG: jpeg,
                                          regions: [PhoneSalientRegionSample(x: 0.1, y: 0.2, width: 0.3, height: 0.4,
                                                                             confidence: 0.9, hasWorldCenter: true,
                                                                             worldCenter: SIMD3<Float>(0, 0, -1))])),
            .sound(PhoneSoundSample(timestamp: 1, duration: 0.5,
                                    classifications: [PhoneSoundClassification(label: "speech", confidence: 0.8),
                                                      PhoneSoundClassification(label: "music", confidence: 0.1)])),
            .flow(PhoneFlowSample(isTracked: true, timestamp: 1, interval: 0.033, flowWidth: 2, flowHeight: 2,
                                  flow: [SIMD2<Float>](repeating: SIMD2<Float>(0.5, -0.5), count: 4), colorJPEG: jpeg)),
            .touch(PhoneTouchSample(timestamp: 1, touches: [PhoneTouchPoint(id: 7, position: SIMD2<Float>(0.1, -0.2),
                                                                             hasForce: true, force: 0.5, radius: 0.02, age: 0.3)])),
            .air(PhoneAirSample(timestamp: 1, pressure: 101.3, altitude: 12.5)),
            .state(PhoneStateSample(timestamp: 1, mode: .room, isSupported: true, referenceCount: 2,
                                    referencesAreDeclared: true, status: "scanning", notes: ["a", "b"])),
        ]
    }

    /// What a sketch does with a decoded message, as far as it is a pure function
    /// of the sample: the room's chunks and planes are built and asked for
    /// their meshes, everything else is at least read.
    static func read(_ message: PhoneMessage, room: inout PhoneSceneMesh, planes: inout PhonePlanes) {
        switch message {
        case .sceneMesh(let sample):
            if let chunk = phoneSceneChunk(from: sample) {
                room.apply(chunk)
                _ = room.mesh
                _ = room.mesh(of: .wall, .floor)
                _ = room.mesh(colored: { _ in .white })
                _ = room.bounds
                _ = room.foundSurfaces
            } else if sample.isRemoved {
                room.remove(sample.id)
            }
        case .plane(let sample):
            if let plane = phonePlane(from: sample) {
                planes.apply(plane)
                _ = plane.area
                _ = plane.mesh
                _ = planes.largest
                _ = planes.planes(of: .table)
                _ = planes.mesh(colored: { _ in .white })
            } else if sample.isRemoved {
                planes.remove(sample.id)
            }
        case .pose(let bodies):
            for body in bodies { _ = body.joints.count }
        case .face(let faces):
            for face in faces { _ = face.meshVertices.count + face.triangleIndices.count }
        case .depth(let sample):
            _ = sample.depth.count == sample.depthWidth * sample.depthHeight
        case .segmentation(let sample):
            _ = sample.matte.count == sample.matteWidth * sample.matteHeight
        case .saliency(let sample):
            _ = sample.heat.count == sample.heatWidth * sample.heatHeight
        case .flow(let sample):
            _ = sample.flow.count == sample.flowWidth * sample.flowHeight
        default:
            break
        }
    }

    @Test func everySensorMessage() {
        let seeds = Self.messages().map { [UInt8](PhoneWire.encode($0)) }
        let report = MutationRun.run("phone-sensor", seeds: seeds, count: 300) { bytes in
            // A room and a set of planes of this case's own: a mutated block
            // carries a mutated identity, and a room that kept every one of
            // them would rebuild a mesh of thousands of blocks every case.
            var room = PhoneSceneMesh()
            var planes = PhonePlanes()
            let data = Data(bytes)
            guard let header = PhoneHeader.parse(data) else { return false }
            let rest = data.count > PhoneWire.headerByteCount ? Data(data.dropFirst(PhoneWire.headerByteCount)) : Data()
            // As the reader reads it: exactly the payload the header announces.
            if rest.count >= header.payloadLength,
               let message = PhoneWire.decode(header: header, payload: rest.prefix(header.payloadLength)) {
                Self.read(message, room: &room, planes: &planes)
            }
            // And wider than the wire ever is: the whole rest, whatever the header said.
            guard let message = PhoneWire.decode(header: header, payload: rest) else { return false }
            Self.read(message, room: &room, planes: &planes)
            _ = PhoneWire.encode(message)
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }

    static func requests() -> [PhoneRequest] {
        let sets = [Data([0x40, 0x01, 0x0C]), Data([0x42, 0x01, 0x01, 0x01]), Data([0x44, 0x01])]
        return [
            .mode(.sketch), .mode(.body), .library(count: 3),
            .reference(PhoneReference(name: "poster", kind: .image, printedWidth: 0.3,
                                      contents: Data(repeating: 0xAB, count: 300))),
            .picture(PhonePicture(width: 1080, height: 1920, isKeyframe: true, parameterSets: sets,
                                  data: Data((0..<3000).map { UInt8($0 & 0xFF) }))),
            .picture(PhonePicture(width: 640, height: 360, isKeyframe: false, data: Data([0, 0, 0, 1, 0x02]))),
        ]
    }

    @Test func everyRequestAndThePictureFraming() {
        let seeds = Self.requests().map { [UInt8](PhoneWire.encode($0)) }
        let trailer = PhoneWire.encode(.mode(.sketch))
        var format: PhonePictureFormat?
        let report = MutationRun.run("phone-request", seeds: seeds, count: 300) { bytes in
            let data = Data(bytes)
            if let header = PhoneRequestHeader.parse(data) {
                let rest = data.count > PhoneWire.headerByteCount ? data.dropFirst(PhoneWire.headerByteCount) : Data()
                _ = PhoneWire.decode(header: header, payload: rest)
            }
            var buffer = data + trailer
            guard let requests = PhoneWire.takeRequests(from: &buffer) else { return false }
            for request in requests {
                if case .picture(let picture) = request {
                    _ = PhonePictureFormat(parameterSets: picture.parameterSets)
                    _ = picture.sampleBuffer(reusing: &format)
                }
                _ = PhoneWire.encode(request)
            }
            return requests.count > 1
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }
}
