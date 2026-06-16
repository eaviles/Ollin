@testable import Ollin
import Testing
import simd
import COllinShaders

/// CPU checks on the 3D model-matrix stack (`translate`/`rotateX/Y/Z`/`rotate(_:axis:)`/
/// `scale` and `pushState`/`popState`), exercised end to end through `Drawer`: a
/// transform is applied, a one-point cloud is recorded, and the baked world-space
/// position the renderer would draw is read back from `Drawer.points`. World space is
/// right-handed, y-up; rotations are right-handed. No Metal device, so these run in CI.
@Suite
struct TransformStackTests {

    private func close(_ a: Float, _ b: Float, _ eps: Float = 1e-5) -> Bool { abs(a - b) <= eps }

    /// Record a single point at `local` through `drawer` (a camera must be set) and
    /// return the baked world-space position.
    private func baked(_ drawer: Drawer, at local: Vector3 = .zero) -> SIMD4<Float> {
        var cloud = PointCloud()
        cloud.add(local, color: .white, size: 1)
        drawer.drawPointCloud(cloud)
        return drawer.points.last!.position
    }

    private func freshDrawer() -> Drawer {
        let d = Drawer()
        d.beginFrame()
        // Any camera puts the frame into 3D so drawPointCloud records.
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        return d
    }

    @Test func identityLeavesPointUntouched() {
        let d = freshDrawer()
        let p = baked(d, at: Vector3(1, 2, 3))
        #expect(close(p.x, 1) && close(p.y, 2) && close(p.z, 3))
    }

    @Test func translateMovesTheOrigin() {
        let d = freshDrawer()
        d.translate(2, 3, -1)
        let p = baked(d)          // a point at the local origin lands at the translation
        #expect(close(p.x, 2) && close(p.y, 3) && close(p.z, -1))
    }

    @Test func rotateYIsRightHanded() {
        // +90° about y takes +x to −z (right-handed: ccw looking down from +y).
        let d = freshDrawer()
        d.rotateY(.pi / 2)
        let p = baked(d, at: Vector3(1, 0, 0))
        #expect(close(p.x, 0) && close(p.y, 0) && close(p.z, -1))
    }

    @Test func rotateXIsRightHanded() {
        // +90° about x takes +y to +z.
        let d = freshDrawer()
        d.rotateX(.pi / 2)
        let p = baked(d, at: Vector3(0, 1, 0))
        #expect(close(p.x, 0) && close(p.y, 0) && close(p.z, 1))
    }

    @Test func rotateZIsRightHanded() {
        // +90° about z takes +x to +y.
        let d = freshDrawer()
        d.rotateZ(.pi / 2)
        let p = baked(d, at: Vector3(1, 0, 0))
        #expect(close(p.x, 0) && close(p.y, 1) && close(p.z, 0))
    }

    @Test func arbitraryAxisMatchesAxisAligned() {
        // rotate(_:axis: .unitY) must equal rotateY by the same angle.
        let a = freshDrawer(); a.rotate(.pi / 3, axis: .unitY)
        let b = freshDrawer(); b.rotateY(.pi / 3)
        let pa = baked(a, at: Vector3(1, 0.5, -2)), pb = baked(b, at: Vector3(1, 0.5, -2))
        #expect(close(pa.x, pb.x) && close(pa.y, pb.y) && close(pa.z, pb.z))
    }

    @Test func scalePerAxis() {
        let d = freshDrawer()
        d.scale(2, 3, 4)
        let p = baked(d, at: Vector3(1, 1, 1))
        #expect(close(p.x, 2) && close(p.y, 3) && close(p.z, 4))
    }

    @Test func scaleGrowsSplatSize() {
        // A uniform scale 3× should multiply a point's world-unit splat size by 3
        // (mean of the three basis-column lengths); a rigid move leaves it alone.
        let scaled = freshDrawer(); scaled.scale(3, 3, 3)
        let rigid = freshDrawer(); rigid.translate(5, 0, 0); rigid.rotateY(.pi / 4)
        #expect(close(baked2(scaled).size, 3))
        #expect(close(baked2(rigid).size, 1))
    }

    private func baked2(_ drawer: Drawer) -> OllinPoint {
        var cloud = PointCloud()
        cloud.add(.zero, color: .white, size: 1)
        drawer.drawPointCloud(cloud)
        return drawer.points.last!
    }

    @Test func compositionIsPostMultiplied() {
        // translate then rotate: the rotation happens in the translated frame, so a
        // point at the local origin still lands at the translation (rotation about the
        // origin doesn't move it), while an offset point swings around that translation.
        let d = freshDrawer()
        d.translate(4, 0, 0)
        d.rotateY(.pi / 2)        // +x_local -> -z_local
        let p = baked(d, at: Vector3(1, 0, 0))
        // local (1,0,0) -> rotateY -> (0,0,-1) -> translate(4,0,0) -> (4,0,-1)
        #expect(close(p.x, 4) && close(p.y, 0) && close(p.z, -1))
    }

    @Test func pushPopRestoresTheModelMatrix() {
        let d = freshDrawer()
        d.translate(1, 0, 0)
        d.pushState()
        d.translate(0, 5, 0)
        d.rotateZ(.pi / 2)
        _ = baked(d)              // (inside the saved scope)
        d.popState()
        let p = baked(d)          // back to just translate(1,0,0)
        #expect(close(p.x, 1) && close(p.y, 0) && close(p.z, 0))
    }

    @Test func modelMatrixResetsEachFrame() {
        let d = freshDrawer()
        d.translate(9, 9, 9)
        d.beginFrame()            // a new frame clears the model matrix
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        let p = baked(d, at: Vector3(1, 2, 3))
        #expect(close(p.x, 1) && close(p.y, 2) && close(p.z, 3))
    }
}
