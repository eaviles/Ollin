import Foundation
import ARKit
import simd

/// Runs ARKit world tracking with **scene reconstruction** (the rear LiDAR) and
/// turns the room it builds into `PhoneSceneMeshSample` blocks: a triangle surface
/// with normals, placed by its anchor, and labelled by what each triangle is.
///
/// ARKit does not hand over one mesh of the room. It divides the space into blocks,
/// reports each as its own anchor, and keeps improving a block as you look at it
/// again, so this streamer sends one block per message and the Mac keeps the newest
/// of each. A block the session retires is sent as a removal notice.
///
/// Scene reconstruction needs a LiDAR sensor (Pro-tier iPhones), so this is gated on
/// `ARWorldTrackingConfiguration.supportsSceneReconstruction`. It uses the rear
/// camera in its own session, so it is mutually exclusive with the other modes.
///
/// Two rules shape the code. The geometry is read **inside** the delegate callback,
/// because ARKit gives it as Metal buffers owned by the session and nothing promises
/// they outlive the call. And the **sending** is throttled rather than the reading:
/// a block changes far more often than it needs to travel, so each block waits its
/// turn in a queue and none is dropped.
///
/// `@unchecked Sendable`: every member is touched on the main thread only. ARKit
/// delivers its delegate callbacks there, and the flush timer runs on the main run
/// loop, which is what the annotation is asserting.
final class SceneMeshStreamer: NSObject, ARSessionDelegate, @unchecked Sendable {

    /// Fired (on the main thread) for each block that goes out, including removals.
    var onChunk: ((PhoneSceneMeshSample) -> Void)?

    /// Fired when a block is too big to carry in one payload, so the app can say so
    /// rather than dropping it in silence. Carries the running count.
    var onOversized: ((Int) -> Void)?

    /// Whether this device can reconstruct the scene at all.
    var isSupported: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
            || ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    /// How often the queue is emptied a little, and how many blocks go out each time.
    /// Together they cap the wire at 15 blocks a second, which keeps up with a walking
    /// scan without flooding the Mac.
    private let flushInterval = 0.2
    private let chunksPerFlush = 3

    private let session = ARSession()

    /// Blocks read but not yet sent: the newest reading of each, plus the order they
    /// became due, so a block that stops changing still gets its turn.
    private var pending: [UUID: PhoneSceneMeshSample] = [:]
    private var queue: [UUID] = []
    private var flushTimer: Timer?

    /// The latest frame's clock and tracking state, kept so a block carries the same
    /// timestamp the other payloads do. An anchor has no clock of its own.
    private var frameTime: TimeInterval = 0
    private var tracking = false
    private var oversized = 0

    /// Which run of the scanner these blocks belong to. Starting the session resets
    /// the world origin, so a fresh number is what tells the Mac to drop the room it
    /// was holding instead of mixing two coordinate spaces.
    private var scan: UInt32 = 0

    func start() {
        guard isSupported else { return }
        scan = UInt32.random(in: 1 ... .max)
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        // Classification is the whole point of the mode (a floor a sketch can find),
        // so take it when the device offers it and fall back to bare geometry.
        config.sceneReconstruction =
            ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
            ? .meshWithClassification : .mesh
        session.run(config, options: [.resetTracking, .removeExistingAnchors])

        flushTimer?.invalidate()
        let timer = Timer(timeInterval: flushInterval, repeats: true) { [weak self] _ in
            self?.flush()
        }
        RunLoop.main.add(timer, forMode: .common)
        flushTimer = timer
    }

    func stop() {
        session.pause()
        flushTimer?.invalidate()
        flushTimer = nil
        pending.removeAll()
        queue.removeAll()
        oversized = 0
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameTime = frame.timestamp
        if case .normal = frame.camera.trackingState { tracking = true } else { tracking = false }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { read(anchors) }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { read(anchors) }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors.compactMap({ $0 as? ARMeshAnchor }) {
            // A retirement is a few bytes, so it goes straight out, and it drops any
            // reading of the same block still waiting in the queue.
            pending.removeValue(forKey: anchor.identifier)
            queue.removeAll { $0 == anchor.identifier }
            onChunk?(PhoneSceneMeshSample(tracked: tracking, timestamp: frameTime,
                                          id: anchor.identifier, scan: scan,
                                          removed: true, transform: anchor.transform))
        }
    }

    // MARK: Reading and sending

    /// Read every mesh anchor in `anchors` now, while ARKit's buffers are certainly
    /// alive, and put each reading in the queue.
    private func read(_ anchors: [ARAnchor]) {
        for anchor in anchors.compactMap({ $0 as? ARMeshAnchor }) {
            guard let sample = sample(from: anchor) else { continue }
            // A block already waiting keeps its place in line and takes the newer
            // reading, so a busy block cannot push a quiet one down the queue.
            if pending.updateValue(sample, forKey: anchor.identifier) == nil {
                queue.append(anchor.identifier)
            }
        }
    }

    /// Send the next few blocks in turn.
    private func flush() {
        var sent = 0
        while sent < chunksPerFlush, !queue.isEmpty {
            let id = queue.removeFirst()
            guard let sample = pending.removeValue(forKey: id) else { continue }
            onChunk?(sample)
            sent += 1
        }
    }

    /// One anchor read into a wire sample, or `nil` when it holds no triangles or is
    /// too big to carry.
    private func sample(from anchor: ARMeshAnchor) -> PhoneSceneMeshSample? {
        let geometry = anchor.geometry
        let vertices = Self.vectors(geometry.vertices)
        let normals = Self.vectors(geometry.normals)
        let indices = Self.indices(geometry.faces)
        let surfaces = Self.surfaces(geometry.classification)
        guard !vertices.isEmpty, indices.count >= 3 else { return nil }

        let size = PhoneWire.sceneMeshPayloadSize(vertexCount: vertices.count,
                                                  indexCount: indices.count,
                                                  surfaceCount: surfaces.count)
        guard size <= PhoneWire.maxPayloadBytes else {
            oversized += 1
            onOversized?(oversized)
            NSLog("Ollin capture: skipped a %d-vertex mesh block, %d bytes is over the payload limit",
                  vertices.count, size)
            return nil
        }

        return PhoneSceneMeshSample(tracked: tracking, timestamp: frameTime,
                                    id: anchor.identifier, scan: scan, removed: false,
                                    transform: anchor.transform, vertices: vertices,
                                    normals: normals, triangleIndices: indices,
                                    surfaces: surfaces)
    }

    // MARK: Reading ARKit's buffers

    /// The three-float entries of a geometry source. Each entry is read as three
    /// separate floats and stepped by the source's own `stride`, because the buffer
    /// packs twelve bytes per entry while a `SIMD3<Float>` occupies sixteen, and
    /// reading it as one would run past the last entry.
    private static func vectors(_ source: ARGeometrySource) -> [SIMD3<Float>] {
        guard source.format == .float3, source.count > 0 else { return [] }
        let base = source.buffer.contents().advanced(by: source.offset)
        var out = [SIMD3<Float>](); out.reserveCapacity(source.count)
        for i in 0..<source.count {
            let entry = base.advanced(by: i * source.stride).assumingMemoryBound(to: Float.self)
            out.append(SIMD3<Float>(entry[0], entry[1], entry[2]))
        }
        return out
    }

    /// A triangle list from a geometry element, widened to the 32-bit indices the
    /// wire and the Mac's mesh both use.
    private static func indices(_ element: ARGeometryElement) -> [UInt32] {
        guard element.primitiveType == .triangle, element.indexCountPerPrimitive == 3,
              element.count > 0 else { return [] }
        let total = element.count * 3
        var out = [UInt32](); out.reserveCapacity(total)
        switch element.bytesPerIndex {
        case 4:
            let p = element.buffer.contents().assumingMemoryBound(to: UInt32.self)
            for i in 0..<total { out.append(p[i]) }
        case 2:
            let p = element.buffer.contents().assumingMemoryBound(to: UInt16.self)
            for i in 0..<total { out.append(UInt32(p[i])) }
        default:
            return []
        }
        return out
    }

    /// One label per triangle, mapped onto the wire's own names. A session running
    /// without classification has none, and the Mac then treats every triangle as
    /// unclassified.
    private static func surfaces(_ source: ARGeometrySource?) -> [UInt8] {
        guard let source, source.format == .uchar, source.count > 0 else { return [] }
        let base = source.buffer.contents().advanced(by: source.offset)
        var out = [UInt8](); out.reserveCapacity(source.count)
        for i in 0..<source.count {
            let raw = base.advanced(by: i * source.stride)
                .assumingMemoryBound(to: UInt8.self).pointee
            let label = ARMeshClassification(rawValue: Int(raw)) ?? ARMeshClassification.none
            out.append(surface(label).rawValue)
        }
        return out
    }

    /// ARKit's label for a triangle, as the wire's own case. Mapped one by one rather
    /// than by raw value, so a change on either side is a compile error and not a
    /// silently wrong label.
    private static func surface(_ label: ARMeshClassification) -> PhoneSurface {
        switch label {
        case .none:    return .unclassified
        case .wall:    return .wall
        case .floor:   return .floor
        case .ceiling: return .ceiling
        case .table:   return .table
        case .seat:    return .seat
        case .window:  return .window
        case .door:    return .door
        @unknown default: return .unclassified
        }
    }
}
