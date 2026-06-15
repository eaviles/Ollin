import Foundation
import Ollin

/// A pinhole camera's calibration — focal length and principal point in pixels,
/// at a stated image resolution — and the unprojection that turns a depth pixel
/// into a 3D point.
///
/// Kept in this satellite for now rather than the `Ollin` core: the live USB
/// tether and the broader 3D mode will both want intrinsics, and that's the
/// moment to lift a shared seam into the core — not before a second caller
/// earns it.
///
/// Intrinsics are tied to the resolution they were measured at, so they must be
/// `scaled(to:)` before being used at another resolution (a recording's color
/// frame and its smaller depth map don't share a pixel grid).
public struct CameraIntrinsics: Equatable, Sendable {

    /// Horizontal focal length, in pixels.
    public var fx: Double
    /// Vertical focal length, in pixels.
    public var fy: Double
    /// Principal point x (the optical centre), in pixels.
    public var cx: Double
    /// Principal point y, in pixels.
    public var cy: Double
    /// The image width these intrinsics are expressed at.
    public var width: Int
    /// The image height these intrinsics are expressed at.
    public var height: Int

    public init(fx: Double, fy: Double, cx: Double, cy: Double, width: Int, height: Int) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
        self.width = width
        self.height = height
    }

    /// These intrinsics rescaled to a new resolution — focal length and principal
    /// point scale linearly with the image dimensions. Used to bring color-frame
    /// intrinsics onto the depth map's smaller grid.
    public func scaled(toWidth newWidth: Int, height newHeight: Int) -> CameraIntrinsics {
        guard width > 0, height > 0 else { return self }
        let sx = Double(newWidth) / Double(width)
        let sy = Double(newHeight) / Double(height)
        return CameraIntrinsics(fx: fx * sx, fy: fy * sy, cx: cx * sx, cy: cy * sy,
                                width: newWidth, height: newHeight)
    }

    /// Back-project pixel (`col`, `row`) at metric `depth` (meters) into a 3D
    /// point in the camera's space.
    ///
    /// The result is in **ARKit's right-handed camera frame**: +x right, +y up,
    /// and the camera looks down −z (so a point in front of the lens has negative
    /// z, and metric depth maps to −z). `col`/`row` are pixel coordinates with the
    /// origin at the top-left and `row` increasing downward, which is why y is
    /// negated. This matches `Camera3D`'s right-handed, y-up world, so a cloud
    /// built here drops straight into `drawPointCloud`.
    public func unproject(col: Double, row: Double, depth: Double) -> Vector3 {
        let x = (col - cx) / fx * depth
        let y = -(row - cy) / fy * depth
        return Vector3(x, y, -depth)
    }
}
