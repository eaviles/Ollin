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

public extension RGBDFrame {
    /// Which iPhone camera produced this frame, inferred from the depth grid (see
    /// `Record3DCamera`). Drives situation-specific tuning (close-up front vs.
    /// room-scale rear). Record3D-specific reading of the core RGBD frame.
    var camera: Record3DCamera {
        Record3DCamera.classify(depthWidth: depthWidth, depthHeight: depthHeight)
    }
}
