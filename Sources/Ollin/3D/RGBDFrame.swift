import Foundation

/// A per-pixel depth confidence: how much to trust a depth sample. Used as the
/// floor when building a point cloud, so noisy edges can be dropped. (ARKit's
/// scene-depth confidence is the canonical producer; any depth source that grades
/// its samples can use the same three levels.)
public enum DepthConfidence: Int, Sendable, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (a: DepthConfidence, b: DepthConfidence) -> Bool {
        a.rawValue < b.rawValue
    }
}

/// One RGBD frame: a color image, a metric depth map, an optional per-pixel
/// confidence map, and the depth-map intrinsics that tie them together — the
/// source-agnostic shape every depth feed produces (a recorded depth clip, a
/// tethered phone's live stream, a webcam paired with a depth model).
///
/// It carries everything needed to lift the 2D picture into 3D: `pointCloud(...)`
/// unprojects the whole depth map into a `PointCloud`, and `unproject(normalized:)`
/// lifts a single image point (a tracked joint, a tapped pixel) into a metric 3D
/// position. Both land in the camera's right-handed, y-up space — the same space
/// `drawPointCloud` draws through — so a cloud and a depth-lifted skeleton share
/// one coordinate frame.
///
/// Depth and confidence are row-major from the top-left, `depthWidth ×
/// depthHeight`, and depth is in **meters**. The color image is usually a higher
/// resolution than the depth map; the unprojection samples it per depth pixel.
public struct RGBDFrame {

    /// The decoded color frame (typically higher resolution than the depth map).
    public let color: Image
    /// Metric depth in meters, row-major from the top-left, `depthWidth × depthHeight`.
    public let depth: [Float]
    /// Per-pixel confidence (`0`/`1`/`2`), row-major, matching the depth grid —
    /// or `nil` when the frame carries none (or its size didn't match).
    public let confidence: [UInt8]?
    /// The number of depth columns.
    public let depthWidth: Int
    /// The number of depth rows.
    public let depthHeight: Int
    /// Intrinsics already scaled to the depth-map resolution, ready to unproject.
    public let intrinsics: CameraIntrinsics

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
    ///   - minConfidence: drop depth samples below this confidence (default
    ///     `.high`). Ignored when the frame has no confidence map.
    ///   - depthRange: keep only samples whose depth (meters) falls in this range;
    ///     `nil` keeps every positive depth.
    ///   - step: sample every `step`-th pixel in each axis (`1` = full density;
    ///     a 256×192 LiDAR map is ~49k points at full density, comfortable per frame).
    ///   - pointSize: the splat diameter in world units (meters); perspective
    ///     shrinks distant points.
    public func pointCloud(minConfidence: DepthConfidence = .high,
                           depthRange: ClosedRange<Double>? = nil,
                           step: Int = 1,
                           pointSize: Double = 0.012) -> PointCloud {
        var cloud = PointCloud()
        guard depthWidth > 0, depthHeight > 0, depth.count >= depthWidth * depthHeight else {
            return cloud
        }
        let stride = max(1, step)
        let floor = minConfidence.rawValue
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

    /// The metric depth (meters) at a **Vision-normalized** image point — `0…1`
    /// across the frame with the origin at the **lower-left**, y pointing up, the
    /// convention `Body`/`VisionSpace` and the other trackers report points in.
    ///
    /// A single depth pixel is often a hole (zero/invalid), especially at a
    /// silhouette edge where limbs sit, so this samples a small `radius`-pixel
    /// window and returns the **median** of the valid samples there — robust to
    /// the odd dropout. Returns `nil` when no valid sample is found nearby (or the
    /// frame has no depth).
    public func depth(atNormalizedX x: Double, y: Double, radius: Int = 2) -> Double? {
        guard depthWidth > 0, depthHeight > 0, depth.count >= depthWidth * depthHeight else {
            return nil
        }
        // Vision-normalized (lower-left, y-up) → top-left depth pixel grid.
        let col = Int((x * Double(depthWidth)).rounded(.down))
        let row = Int(((1 - y) * Double(depthHeight)).rounded(.down))
        let r = max(0, radius)

        var samples: [Double] = []
        samples.reserveCapacity((2 * r + 1) * (2 * r + 1))
        var ry = row - r
        while ry <= row + r {
            defer { ry += 1 }
            guard ry >= 0, ry < depthHeight else { continue }
            var rx = col - r
            while rx <= col + r {
                defer { rx += 1 }
                guard rx >= 0, rx < depthWidth else { continue }
                let d = Double(depth[ry * depthWidth + rx])
                if d > 0, d.isFinite { samples.append(d) }
            }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }

    /// Lift a **Vision-normalized** image point (`0…1`, lower-left origin) into a
    /// metric 3D position in the camera's right-handed, y-up space — the same space
    /// `pointCloud(...)` and `Camera3D` use, so a lifted point lands inside the
    /// frame's own cloud.
    ///
    /// This is the source-agnostic seam behind depth-lifted perception: hand it
    /// any 2D image point (a tracked body joint, a hand tip, a tapped pixel) and a
    /// depth source, and get a true 3D position back — `Body.lifted(through:)` is
    /// the per-joint sugar over it. Returns `nil` when no valid depth is found near
    /// the point.
    public func unproject(normalizedX x: Double, y: Double, radius: Int = 2) -> Vector3? {
        guard let d = depth(atNormalizedX: x, y: y, radius: radius) else { return nil }
        let col = (x * Double(depthWidth)).rounded(.down)
        let row = ((1 - y) * Double(depthHeight)).rounded(.down)
        return intrinsics.unproject(col: col, row: row, depth: d)
    }

    /// Lift a `Vector2` Vision-normalized point (`0…1`, lower-left origin) into
    /// metric 3D — see `unproject(normalizedX:y:radius:)`.
    public func unproject(normalized point: Vector2, radius: Int = 2) -> Vector3? {
        unproject(normalizedX: point.x, y: point.y, radius: radius)
    }
}
