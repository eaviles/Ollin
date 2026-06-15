import Foundation
import Ollin

/// Which iPhone depth camera produced a frame, inferred from the depth grid:
/// the front **TrueDepth** camera streams a dense 640×480 map (~307k samples),
/// the rear **LiDAR** camera a sparse 256×192 one (~49k). No iPhone pairs a
/// front LiDAR or a rear TrueDepth, so the depth resolution identifies the camera
/// — orientation doesn't matter (portrait and landscape share the sample count).
/// A sketch reads it to tune for the situation: the front camera is short-range
/// and noisy past a meter (a face up close), the rear LiDAR reaches across a room.
public enum Record3DCamera: Sendable, Equatable {
    /// The front TrueDepth camera — a dense, short-range depth map.
    case trueDepth
    /// The rear LiDAR camera — a sparse, longer-range depth map.
    case lidar
    /// An unrecognized depth grid (no depth, or a resolution we don't classify).
    case unknown

    /// Classify by depth sample count: LiDAR's 256×192 (49,152) is far sparser
    /// than TrueDepth's 640×480 (307,200), so a midpoint threshold separates them
    /// and tolerates minor resolution variants.
    public static func classify(depthWidth: Int, depthHeight: Int) -> Record3DCamera {
        let count = depthWidth * depthHeight
        if count <= 0 { return .unknown }
        return count < 100_000 ? .lidar : .trueDepth
    }
}

/// ARKit's per-pixel depth confidence: how much to trust a depth sample. Used
/// as the floor when building a point cloud, so noisy edges can be dropped.
public enum DepthConfidence: Int, Sendable, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (a: DepthConfidence, b: DepthConfidence) -> Bool {
        a.rawValue < b.rawValue
    }
}

/// One decoded RGBD frame: a color image, a metric depth map, an optional
/// per-pixel confidence map, and the depth-map intrinsics that tie them
/// together. The unit of a `Record3DRecording`.
///
/// Depth and confidence are row-major from the top-left, `depthWidth ×
/// depthHeight`, and depth is in **meters**. The color image is usually a higher
/// resolution than the depth map; `pointCloud(...)` samples it per depth pixel.
public struct RGBDFrame {

    /// The decoded color frame (typically higher resolution than the depth map).
    public let color: Image
    /// Metric depth in meters, row-major from the top-left, `depthWidth × depthHeight`.
    public let depth: [Float]
    /// Per-pixel confidence (`0`/`1`/`2`), row-major, matching the depth grid —
    /// or `nil` when the recording carries none (or its size didn't match).
    public let confidence: [UInt8]?
    /// The number of depth columns.
    public let depthWidth: Int
    /// The number of depth rows.
    public let depthHeight: Int
    /// Intrinsics already scaled to the depth-map resolution, ready to unproject.
    public let intrinsics: CameraIntrinsics

    /// Which iPhone camera produced this frame, inferred from the depth grid (see
    /// `Record3DCamera`). Drives situation-specific tuning (close-up front vs.
    /// room-scale rear).
    public var camera: Record3DCamera {
        Record3DCamera.classify(depthWidth: depthWidth, depthHeight: depthHeight)
    }

    public init(color: Image, depth: [Float], confidence: [UInt8]?,
                depthWidth: Int, depthHeight: Int, intrinsics: CameraIntrinsics) {
        self.color = color
        self.depth = depth
        self.confidence = confidence
        self.depthWidth = depthWidth
        self.depthHeight = depthHeight
        self.intrinsics = intrinsics
    }

    /// Build a `PointCloud` by unprojecting every depth pixel into the camera's
    /// 3D space (ARKit-style: +x right, +y up, looking down −z), colored from the
    /// matching spot in the color frame.
    ///
    /// - Parameters:
    ///   - minimumConfidence: drop depth samples below this confidence (default
    ///     `.high`). Ignored when the frame has no confidence map.
    ///   - depthRange: keep only samples whose depth (meters) falls in this range;
    ///     `nil` keeps every positive depth.
    ///   - step: sample every `step`-th pixel in each axis (`1` = full density;
    ///     a 256×192 LiDAR map is ~49k points at full density, comfortable per frame).
    ///   - pointSize: the splat diameter in world units (meters); perspective
    ///     shrinks distant points.
    public func pointCloud(minimumConfidence: DepthConfidence = .high,
                           depthRange: ClosedRange<Double>? = nil,
                           step: Int = 1,
                           pointSize: Double = 0.012) -> PointCloud {
        var cloud = PointCloud()
        guard depthWidth > 0, depthHeight > 0, depth.count >= depthWidth * depthHeight else {
            return cloud
        }
        let stride = max(1, step)
        let floor = minimumConfidence.rawValue
        let conf = (confidence?.count == depth.count) ? confidence : nil
        // Map a depth pixel to the (higher-res) color frame by the ratio of grids.
        let colorW = color.width, colorH = color.height
        let sx = Double(colorW) / Double(depthWidth)
        let sy = Double(colorH) / Double(depthHeight)
        cloud.points.reserveCapacity((depthWidth / stride) * (depthHeight / stride))

        var row = 0
        while row < depthHeight {
            var col = 0
            while col < depthWidth {
                let i = row * depthWidth + col
                let d = Double(depth[i])
                defer { col += stride }
                guard d > 0, d.isFinite else { continue }
                if let depthRange, !depthRange.contains(d) { continue }
                if let conf, Int(conf[i]) < floor { continue }

                let position = intrinsics.unproject(col: Double(col), row: Double(row), depth: d)
                let px = min(colorW - 1, Int((Double(col) + 0.5) * sx))
                let py = min(colorH - 1, Int((Double(row) + 0.5) * sy))
                cloud.add(position, color: color[px, py], size: pointSize)
            }
            row += stride
        }
        return cloud
    }
}
