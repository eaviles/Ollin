import Ollin
import Testing

/// Pure-CPU checks on the core RGBD frame: the back-projection math, the
/// Vision-normalized → depth-grid y-flip, and the hole-robust depth sampling. No
/// Metal (the color image is CPU-authored), so these run everywhere including CI.
@Suite struct RGBDFrameTests {

    /// A frame with a constant `depth` everywhere and centered, square intrinsics,
    /// at `w × h`. The color is a plain white image (only its size matters here).
    private func constantFrame(depth d: Float, w: Int = 8, h: Int = 8,
                               f: Double = 10) -> RGBDFrame {
        RGBDFrame(color: Image(width: w, height: h, color: .white),
                  depth: Array(repeating: d, count: w * h), confidence: nil,
                  depthWidth: w, depthHeight: h,
                  intrinsics: CameraIntrinsics(fx: f, fy: f,
                                               cx: Double(w) / 2, cy: Double(h) / 2,
                                               width: w, height: h))
    }

    @Test func centerUnprojectsOntoTheAxis() {
        // The principal point at metric depth lands on the optical axis: x = y = 0,
        // z = −depth (camera looks down −z).
        let p = constantFrame(depth: 2).unproject(normalizedX: 0.5, y: 0.5)
        #expect(p != nil)
        #expect(abs(p!.x) < 1e-9)
        #expect(abs(p!.y) < 1e-9)
        #expect(abs(p!.z - -2) < 1e-9)
    }

    @Test func upperRightOfImageIsPositiveXAndY() {
        // A point high and to the right in the image (normalized lower-left, so y
        // up) back-projects to +x, +y in the camera's y-up frame.
        let p = constantFrame(depth: 2).unproject(normalizedX: 0.9, y: 0.9)!
        #expect(p.x > 0)
        #expect(p.y > 0)
        #expect(abs(p.z - -2) < 1e-9)
    }

    @Test func normalizedYFlipsToTheDepthRow() {
        // Vision-normalized y is lower-left (up), the depth grid is top-down. So a
        // point near the bottom (y≈0) must read the *last* depth row, and one near
        // the top (y≈1) the *first*. Give each row a distinct depth and sample with
        // no window to pin the mapping exactly.
        let w = 4, h = 4
        var depth = [Float](repeating: 0, count: w * h)
        for row in 0..<h { for col in 0..<w { depth[row * w + col] = Float(row) + 1 } }
        let frame = RGBDFrame(color: Image(width: w, height: h, color: .white),
                              depth: depth, confidence: nil, depthWidth: w, depthHeight: h,
                              intrinsics: CameraIntrinsics(fx: 4, fy: 4, cx: 2, cy: 2,
                                                           width: w, height: h))
        #expect(frame.depth(atNormalizedX: 0.5, y: 0.99, radius: 0) == 1)   // top row
        #expect(frame.depth(atNormalizedX: 0.5, y: 0.01, radius: 0) == 4)   // bottom row
    }

    @Test func aDepthHoleReturnsNil() {
        // All-zero depth is a hole everywhere: no valid sample, so no lift.
        let frame = constantFrame(depth: 0)
        #expect(frame.depth(atNormalizedX: 0.5, y: 0.5, radius: 0) == nil)
        #expect(frame.unproject(normalizedX: 0.5, y: 0.5, radius: 0) == nil)
    }

    @Test func theWindowMedianIgnoresHoles() {
        // The exact pixel is a hole but neighbors are valid: a radius-1 window finds
        // the median of the valid samples rather than failing.
        let w = 4, h = 4
        var depth = [Float](repeating: 3, count: w * h)
        depth[1 * w + 1] = 0                              // hole at (col 1, row 1)
        let frame = RGBDFrame(color: Image(width: w, height: h, color: .white),
                              depth: depth, confidence: nil, depthWidth: w, depthHeight: h,
                              intrinsics: CameraIntrinsics(fx: 4, fy: 4, cx: 2, cy: 2,
                                                           width: w, height: h))
        // Normalized point over (col 1, row 1): y is flipped, so row 1 of 4 ≈ y 0.6.
        #expect(frame.depth(atNormalizedX: 0.3, y: 0.6, radius: 0) == nil)  // the hole
        #expect(frame.depth(atNormalizedX: 0.3, y: 0.6, radius: 1) == 3)    // its valid neighbors
    }

    @Test func pointCloudKeepsOnlyValidSamples() {
        // Five positive depths in a 4×4 grid, the rest holes → five points.
        let w = 4, h = 4
        var depth = [Float](repeating: 0, count: w * h)
        for i in [0, 5, 6, 10, 15] { depth[i] = 1.5 }
        let frame = RGBDFrame(color: Image(width: w, height: h, color: .white),
                              depth: depth, confidence: nil, depthWidth: w, depthHeight: h,
                              intrinsics: CameraIntrinsics(fx: 4, fy: 4, cx: 2, cy: 2,
                                                           width: w, height: h))
        #expect(frame.pointCloud().count == 5)
    }
}
