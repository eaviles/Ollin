import Testing
import Ollin
@testable import OllinVision

/// A detectable person is hard to synthesize, so detection is a smoke test (the
/// 2D body tracker's pattern) and the skeleton model + the coordinate reads are
/// checked directly on a hand-built body.
@Suite struct BodyTracker3DTests {

    @Test func blankImageHasNoBody() async throws {
        let image = Image(width: 128, height: 128, color: .white)
        // Soft-skip: the model needs a compute device some setups lack in a
        // headless test process; a throw there isn't a code failure. It runs
        // for real where the device is available.
        guard let body = try? await BodyTracker3D.detect(in: image) else { return }
        #expect(body == nil)
    }

    @Test func skeletonSpansAllJoints() {
        // 17 joints in a tree have 16 bones, every joint appears, and the
        // chains tie into root and centerShoulder.
        #expect(Body3D.skeleton.count == 16)
        let used = Set(Body3D.skeleton.flatMap { [$0.0, $0.1] })
        #expect(used == Set(BodyJoint3D.allCases))
        #expect(used.contains(.root))
        #expect(used.contains(.centerShoulder))
    }

    @Test func emptyBodyHasNoReads() {
        let body = Body3D(confidence: 0, height: 0, heightEstimation: .reference, joints: [:])
        let rect = Rectangle(x: 0, y: 0, width: 100, height: 100)
        #expect(body.bones(in: rect).isEmpty)
        #expect(body.bones().isEmpty)
        #expect(body.points(in: rect).isEmpty)
        #expect(body.positions.isEmpty)
        #expect(body.point(.topHead, in: rect) == nil)
        #expect(body.position(.topHead) == nil)
        #expect(body.cameraRelativePosition(.topHead) == nil)
        #expect(body.distance == nil)
        #expect(!body.has(.root))
    }

    /// A loose comparison for float-derived canvas points.
    private func close(_ a: Vector2, _ b: Vector2, _ eps: Double = 1e-9) -> Bool {
        abs(a.x - b.x) <= eps && abs(a.y - b.y) <= eps
    }

    @Test func readsComeBackInTheRightSpaces() {
        // One hand-built body: root at the model origin 2 m from the camera,
        // the head 0.8 m above it, projected at the picture's upper middle.
        let joints: [BodyJoint3D: Body3D.JointRecord] = [
            .root: .init(position: .zero,
                         cameraPosition: Vector3(0, 0, 2),
                         imagePoint: Vector2(0.5, 0.5)),
            .spine: .init(position: Vector3(0, 0.3, 0),
                          cameraPosition: Vector3(0, 0.3, 2),
                          imagePoint: Vector2(0.5, 0.65)),
            .centerShoulder: .init(position: Vector3(0, 0.55, 0.1),
                                   cameraPosition: Vector3(0, 0.55, 2.1),
                                   imagePoint: Vector2(0.5, 0.8)),
        ]
        let body = Body3D(confidence: 1, height: 1.8, heightEstimation: .reference, joints: joints)
        let rect = Rectangle(x: 0, y: 0, width: 200, height: 100)

        // Canvas: normalized lower-left origin → top-left pixels (the y flip).
        #expect(body.point(.root, in: rect) == Vector2(100, 50))
        #expect(close(body.point(.centerShoulder, in: rect) ?? .zero, Vector2(100, 20)))
        // Mirrored flips x only.
        #expect(close(body.point(.spine, in: rect, mirrored: true) ?? .zero, Vector2(100, 35)))

        // Model space comes back untouched (meters, y up).
        #expect(body.position(.spine) == Vector3(0, 0.3, 0))
        #expect(body.positions.count == 3)

        // Camera space and the distance sugar (root is 2 m straight ahead).
        #expect(body.cameraRelativePosition(.root) == Vector3(0, 0, 2))
        #expect(body.distance == 2)

        // Bones: only the pairs whose both ends exist — root–spine and
        // spine–centerShoulder here, in both surfaces.
        #expect(body.bones(in: rect).count == 2)
        let bones3D = body.bones()
        #expect(bones3D.count == 2)
        #expect(bones3D[0].0 == .zero && bones3D[0].1 == Vector3(0, 0.3, 0))
    }
}
