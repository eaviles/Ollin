import Foundation
import CoreGraphics
import ImageIO
import simd
import Ollin

/// One decoded world-facing RGBD frame from the phone's rear LiDAR, boxed for the
/// hand-off from the reader thread to the main thread. Holds the color frame as a
/// `CGImage` (not an `Image`, which isn't `Sendable`); the main thread wraps it.
/// The box is the promise that its contents are only read after the lock hands
/// them over, the way `Camera` boxes its frames.
struct PhoneDepthFrameBox: @unchecked Sendable {
    let sequence: Int
    let color: CGImage
    let depth: [Float]
    let confidence: [UInt8]?
    let depthWidth: Int
    let depthHeight: Int
    let intrinsics: CameraIntrinsics
    let transform: simd_float4x4
}

/// Decode a `PhoneDepthSample` into a boxed RGBD frame: JPEG-decode the color image
/// and build the depth-grid `CameraIntrinsics`. The sample's intrinsics already
/// sit on the depth grid (the phone scales them before sending), so they tie to
/// `depthWidth × depthHeight` directly. Returns `nil` if the color won't decode or
/// the depth is empty.
///
/// Free function (not a method) so the reader thread calls it without main-actor
/// isolation — the executor-assertion lesson the audio/camera code documents.
func decodePhoneDepth(_ sample: PhoneDepthSample, sequence: Int) -> PhoneDepthFrameBox? {
    guard sample.depthWidth > 0, sample.depthHeight > 0,
          sample.depth.count >= sample.depthWidth * sample.depthHeight else { return nil }

    guard let source = CGImageSourceCreateWithData(sample.colorJPEG as CFData, nil),
          let color = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

    // A confidence map only counts if it matches the depth grid; otherwise drop it
    // (the cloud builder would ignore a mismatched one anyway).
    let confidence = sample.confidence?.count == sample.depth.count ? sample.confidence : nil

    let intrinsics = CameraIntrinsics(fx: Double(sample.fx), fy: Double(sample.fy),
                                      cx: Double(sample.cx), cy: Double(sample.cy),
                                      width: sample.depthWidth, height: sample.depthHeight)

    return PhoneDepthFrameBox(sequence: sequence, color: color, depth: sample.depth,
                              confidence: confidence, depthWidth: sample.depthWidth,
                              depthHeight: sample.depthHeight, intrinsics: intrinsics,
                              transform: sample.cameraTransform)
}
