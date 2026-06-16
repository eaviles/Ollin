import Foundation
import ARKit
import simd
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Runs ARKit world tracking with scene depth (the rear **LiDAR** camera) and turns
/// each frame into a `PhoneDepthSample` — a metric depth map, the matching JPEG
/// color image, the depth-grid camera intrinsics, per-pixel confidence, and the
/// 6DoF camera pose, which the Mac unprojects into a point cloud.
///
/// Scene depth needs a LiDAR sensor (Pro-tier iPhones), so this is gated on
/// `ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)`. World
/// tracking uses the rear camera, so it's mutually exclusive with face tracking;
/// it shares the rear camera with body tracking but runs its own session.
///
/// ARKit delivers its delegate callbacks on the main thread, so `onDepth` fires on
/// main; the depth-map copy, intrinsics scaling, and JPEG encode all run there.
final class DepthStreamer: NSObject, ARSessionDelegate {

    /// Fired (on the main thread) for each frame that carries scene depth.
    var onDepth: ((PhoneDepthSample) -> Void)?

    /// Whether this device has a LiDAR sensor for scene depth.
    var isSupported: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    /// The longest color dimension sent over the wire — the captured image is
    /// downscaled to this so the JPEG stays small (the cloud's color resolution
    /// only feeds a 256×192 depth grid, so full capture resolution is wasted bytes).
    private let maxColorDimension = 960

    private let session = ARSession()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func start() {
        guard isSupported else { return }
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        // Smoothed depth is steadier frame-to-frame (kinder to a cloud); fall back to
        // raw scene depth if the device only offers that.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else {
            config.frameSemantics.insert(.sceneDepth)
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() { session.pause() }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }

        guard let (depthW, depthH, depth) = Self.floatPixels(sceneDepth.depthMap) else { return }
        let confidence = sceneDepth.confidenceMap.flatMap { Self.bytePixels($0) }?.data

        guard let jpeg = colorJPEG(from: frame.capturedImage) else { return }

        // Intrinsics arrive at the captured-image resolution; bring them onto the
        // depth grid so the Mac builds a `CameraIntrinsics` against depthW×depthH.
        let res = frame.camera.imageResolution
        let k = frame.camera.intrinsics
        let sx = Float(depthW) / Float(res.width)
        let sy = Float(depthH) / Float(res.height)

        let normal: Bool = if case .normal = frame.camera.trackingState { true } else { false }
        onDepth?(PhoneDepthSample(
            tracked: normal,
            timestamp: frame.timestamp,
            depthWidth: depthW, depthHeight: depthH,
            fx: k.columns.0.x * sx, fy: k.columns.1.y * sy,
            cx: k.columns.2.x * sx, cy: k.columns.2.y * sy,
            cameraTransform: frame.camera.transform,
            colorJPEG: jpeg, depth: depth,
            confidence: (confidence?.count == depth.count) ? confidence : nil))
    }

    // MARK: Pixel-buffer + JPEG helpers

    /// Copy a `DepthFloat32` pixel buffer into a row-major `[Float]`, honoring the
    /// buffer's row stride (which is usually padded past `width × 4`).
    private static func floatPixels(_ buffer: CVPixelBuffer) -> (w: Int, h: Int, data: [Float])? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var out = [Float](repeating: 0, count: w * h)
        out.withUnsafeMutableBytes { dst in
            guard let dstBase = dst.baseAddress else { return }
            for row in 0..<h {
                memcpy(dstBase.advanced(by: row * w * 4), base.advanced(by: row * stride), w * 4)
            }
        }
        return (w, h, out)
    }

    /// Copy a `OneComponent8` pixel buffer (the confidence map) into a row-major
    /// `[UInt8]`, honoring the row stride.
    private static func bytePixels(_ buffer: CVPixelBuffer) -> (w: Int, h: Int, data: [UInt8])? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var out = [UInt8](repeating: 0, count: w * h)
        out.withUnsafeMutableBytes { dst in
            guard let dstBase = dst.baseAddress else { return }
            for row in 0..<h {
                memcpy(dstBase.advanced(by: row * w), base.advanced(by: row * stride), w)
            }
        }
        return (w, h, out)
    }

    /// Convert the captured YCbCr frame to a downscaled JPEG, in the camera-native
    /// orientation (no rotation — depth, intrinsics, and color must share one frame
    /// so the unprojection lines up).
    private func colorJPEG(from pixelBuffer: CVPixelBuffer) -> Data? {
        var ci = CIImage(cvPixelBuffer: pixelBuffer)
        let longest = max(ci.extent.width, ci.extent.height)
        if longest > CGFloat(maxColorDimension) {
            let s = CGFloat(maxColorDimension) / longest
            ci = ci.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
