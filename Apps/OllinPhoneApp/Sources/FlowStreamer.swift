import Foundation
import ARKit
import Vision
import CoreImage
import CoreVideo
import simd

/// Runs ARKit world tracking on the rear camera and measures how the picture
/// moves between consecutive frames with Vision's optical flow, turning each
/// pair into a `PhoneFlowSample`: a dense field of motion vectors at a bounded
/// size, the time between the two frames, and the matching JPEG color frame.
/// World tracking runs on any device, so the mode needs no LiDAR.
///
/// The flow pass is the expensive part, so it runs on its own serial queue
/// behind a drop-if-busy gate: a frame that arrives while one is being measured
/// is skipped, never queued, and the camera never backs up. The interval the
/// wire carries is the real gap between the two frames measured, whatever the
/// gate skipped in between.
///
/// Each frame is scaled into a buffer of the streamer's own before the pass,
/// which does two things: it keeps a classical flow affordable on the phone at
/// a few readings a second, and it means ARKit's own capture buffer is never
/// held past the pass that read it (the previous frame the next pass measures
/// against is the streamer's copy). The map goes over the wire camera-native
/// with the device-hold turn count beside it; the Mac turns the grid and every
/// vector in it, so a wrong turn is a Mac rebuild rather than a phone one.
/// `@unchecked Sendable` under the usual discipline: the handler is wired on the
/// main thread before `start()`, `busy` is touched only on the main thread, and
/// everything else is touched only on the flow queue.
final class FlowStreamer: NSObject, ARSessionDelegate, LightReporting, @unchecked Sendable {

    /// Fired (on the main thread) with each measured pair's reading.
    var onFlow: ((PhoneFlowSample) -> Void)?

    let lightSampler = LightSampler()

    /// The longest side the flow is computed at. The camera frame is scaled
    /// down to this before the pass; the field is a signal a sketch samples
    /// every few canvas points, not a picture, so the detail is not missed.
    private let analysisDimension = 256

    /// The longest color dimension sent over the wire (the backdrop's resolution).
    private let maxColorDimension = 960

    private let session = ARSession()
    private let queue = DispatchQueue(label: "dev.ollin.flow")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    /// Main-thread-only: whether a flow pass is in flight (the drop-if-busy gate).
    private var busy = false

    // Flow-queue-only: the previous frame at the analysis size and when it was
    // captured, plus the two owned buffers the frames alternate between.
    private var previous: CVPixelBuffer?
    private var previousTimestamp: Double = 0
    private var owned: [CVPixelBuffer] = []
    private var ownedIndex = 0

    func start() {
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
        // Forget the last frame, so the mode coming back does not measure a
        // jump across the gap as one huge motion.
        queue.async { [weak self] in
            self?.previous = nil
            self?.previousTimestamp = 0
        }
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Before the busy gate, so the room's light keeps arriving while a
        // flow pass is in flight.
        lightSampler.report(frame)
        guard !busy else { return }
        busy = true

        // Copy what the pass needs out of the frame now, on the callback: only
        // the capture pixel buffer (which CoreVideo reference-counts) rides along,
        // and it is released the moment the pass has scaled it.
        let pixelBuffer = frame.capturedImage
        let timestamp = frame.timestamp
        let turns = captureQuarterTurns()
        let isTracked: Bool = if case .normal = frame.camera.trackingState { true } else { false }

        queue.async { [weak self] in
            guard let self else { return }
            let sample = self.measure(pixelBuffer, timestamp: timestamp,
                                      isTracked: isTracked, turns: turns)
            DispatchQueue.main.async {
                self.busy = false
                if let sample { self.onFlow?(sample) }
            }
        }
    }

    // MARK: The flow pass (on the flow queue)

    /// Measure the motion from the previous frame to this one. Returns `nil` on
    /// the first frame (nothing to measure against yet) and when the pass
    /// itself failed (the last good reading stays put on the Mac).
    private func measure(_ pixelBuffer: CVPixelBuffer, timestamp: Double,
                         isTracked: Bool, turns: UInt8) -> PhoneFlowSample? {
        guard let current = scaled(pixelBuffer) else { return nil }
        let before = previous
        let beforeTimestamp = previousTimestamp
        previous = current
        previousTimestamp = timestamp
        guard let before, timestamp > beforeTimestamp else { return nil }

        // The handler holds the older frame and the request targets the newer:
        // Vision then reports the motion of the picture itself, in the buffer's
        // own pixels, pinned by a Mac test over this same request. (The newer
        // Vision API the Mac's tracker uses reports the opposite sign, so the
        // two are not interchangeable; `wireField` is the one place to flip if
        // a phone ever reads backward.)
        let request = VNGenerateOpticalFlowRequest(targetedCVPixelBuffer: current, options: [:])
        request.computationAccuracy = .medium
        request.outputPixelFormat = kCVPixelFormatType_TwoComponent32Float
        let handler = VNImageRequestHandler(cvPixelBuffer: before, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first as? VNPixelBufferObservation,
              let field = wireField(from: observation.pixelBuffer) else { return nil }

        let jpeg = cameraJPEG(from: pixelBuffer, context: ciContext,
                              maxDimension: maxColorDimension, quality: 0.6) ?? Data()

        return PhoneFlowSample(isTracked: isTracked, timestamp: timestamp,
                               interval: timestamp - beforeTimestamp,
                               flowWidth: field.w, flowHeight: field.h,
                               orientation: turns, confidence: Float(observation.confidence),
                               flow: field.vectors, colorJPEG: jpeg)
    }

    /// The camera frame scaled into one of the streamer's own BGRA buffers, its
    /// longest side at the analysis size and both sides even (the wire map is
    /// the field averaged two by two). The two owned buffers alternate, so the
    /// one holding the previous frame is never written while it is still the
    /// reference.
    private func scaled(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let srcW = CVPixelBufferGetWidth(pixelBuffer), srcH = CVPixelBufferGetHeight(pixelBuffer)
        guard srcW > 0, srcH > 0 else { return nil }
        let scale = Double(analysisDimension) / Double(max(srcW, srcH))
        let w = max(2, Int((Double(srcW) * scale).rounded()) & ~1)
        let h = max(2, Int((Double(srcH) * scale).rounded()) & ~1)

        if owned.count != 2 || CVPixelBufferGetWidth(owned[0]) != w || CVPixelBufferGetHeight(owned[0]) != h {
            owned = []
            for _ in 0..<2 {
                var buffer: CVPixelBuffer?
                let attributes: [CFString: Any] = [
                    kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
                    kCVPixelBufferCGImageCompatibilityKey: true,
                ]
                guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                                          attributes as CFDictionary, &buffer) == kCVReturnSuccess,
                      let buffer else { return nil }
                owned.append(buffer)
            }
            previous = nil
        }
        let target = owned[ownedIndex]
        ownedIndex = (ownedIndex + 1) % 2

        var image = CIImage(cvPixelBuffer: pixelBuffer)
        image = image.transformed(by: CGAffineTransform(scaleX: CGFloat(w) / CGFloat(srcW),
                                                        y: CGFloat(h) / CGFloat(srcH)))
        ciContext.render(image, to: target, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                         colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return target
    }

    /// The wire map: Vision's two-component float field averaged two by two,
    /// each vector the motion of the picture at that cell (x right, y down the
    /// camera-native buffer), in the wire map's own pixels.
    private func wireField(from buffer: CVPixelBuffer) -> (w: Int, h: Int, vectors: [SIMD2<Float>])? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_TwoComponent32Float else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w >= 2, h >= 2, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let outW = w / 2, outH = h / 2
        var out = [SIMD2<Float>](repeating: .zero, count: outW * outH)
        for row in 0..<outH {
            let r0 = base.advanced(by: (2 * row) * stride).assumingMemoryBound(to: Float.self)
            let r1 = base.advanced(by: (2 * row + 1) * stride).assumingMemoryBound(to: Float.self)
            for col in 0..<outW {
                let c = 4 * col
                let dx = r0[c] + r0[c + 2] + r1[c] + r1[c + 2]
                let dy = r0[c + 1] + r0[c + 3] + r1[c + 1] + r1[c + 3]
                // The sum of four is four times the mean; the map's pixels are
                // half the field's, so the mean halves again: divide by eight
                // in one step.
                out[row * outW + col] = SIMD2<Float>(dx / 8, dy / 8)
            }
        }
        return (outW, outH, out)
    }
}
