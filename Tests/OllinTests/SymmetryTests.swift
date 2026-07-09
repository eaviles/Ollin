@testable import Ollin
import Testing
import simd
import COllinShaders

/// CPU checks on the symmetry fold state (`symmetry`/`noSymmetry`): the
/// CTM-conjugated fold matrices, the per-path replication, and the state-stack
/// scoping, exercised end to end through `Drawer`. No Metal device, so these
/// run in CI.
@Suite
struct SymmetryTests {

    private func close(_ a: Float, _ b: Float, _ eps: Float = 1e-4) -> Bool { abs(a - b) <= eps }

    private func freshDrawer() -> Drawer {
        let d = Drawer()
        d.beginFrame()
        return d
    }

    /// The canvas-space point an SDF instance's local center lands on.
    private func canvasPoint(_ instance: SDFInstance) -> SIMD2<Float> {
        let p = instance.transform * SIMD3<Float>(instance.center.x, instance.center.y, 1)
        return SIMD2<Float>(p.x, p.y)
    }

    @Test func foldsRotateAroundTheCurrentOrigin() {
        let d = freshDrawer()
        d.translate(Vector2(100, 100))
        d.symmetry(4)
        d.drawCircle(50, 0, 10)
        #expect(d.sdfInstances.count == 4)
        // The folds pivot on the translated origin: (150,100) rotated in quarter
        // turns around (100,100). The first instance is the untouched primary.
        let expected: [SIMD2<Float>] = [
            SIMD2(150, 100), SIMD2(100, 150), SIMD2(50, 100), SIMD2(100, 50),
        ]
        for (instance, want) in zip(d.sdfInstances, expected) {
            let got = canvasPoint(instance)
            #expect(close(got.x, want.x) && close(got.y, want.y))
        }
    }

    @Test func mirroredAddsAReflectedCopyPerFold() {
        let d = freshDrawer()
        d.translate(Vector2(100, 100))
        d.symmetry(3, mirrored: true)
        d.drawCircle(50, 20, 10)
        #expect(d.sdfInstances.count == 6)
        // The first mirror reflects across the local x-axis: (50,20) -> (50,-20),
        // i.e. canvas (150,80). Fold order interleaves rotation, then its mirror.
        let mirrored = canvasPoint(d.sdfInstances[1])
        #expect(close(mirrored.x, 150) && close(mirrored.y, 80))
    }

    @Test func strokeVerticesReplicateAsRotatedCopies() {
        let d = freshDrawer()
        d.symmetry(2)   // identity CTM: folds about the canvas origin
        d.drawPolyline([Vector2(10, 0), Vector2(40, 12), Vector2(80, -4)])
        let n = d.vertices.count
        #expect(n > 0 && n % 2 == 0)
        // The second half is the first rotated a half turn: (x, y) -> (-x, -y).
        for i in 0..<(n / 2) {
            let a = d.vertices[i], b = d.vertices[i + n / 2]
            #expect(close(b.position.x, -a.position.x) && close(b.position.y, -a.position.y))
            #expect(a.color == b.color && a.aa == b.aa)
        }
    }

    @Test func combinatorGroupsShareTheirNodeProgram() {
        let d = freshDrawer()
        d.symmetry(5)
        d.drawSDF(SDF.circle(radius: 20).smoothUnion(SDF.circle(radius: 12).at(x: 15, y: 0), k: 6))
        #expect(d.sdfGroups.count == 5)
        let first = d.sdfGroups[0]
        for group in d.sdfGroups.dropFirst() {
            #expect(group.nodeStart == first.nodeStart && group.nodeCount == first.nodeCount)
        }
        // One flattened program, not five.
        #expect(d.sdfNodes.count == Int(first.nodeCount))
    }

    @Test func stateStackRestoresTheFolds() {
        let d = freshDrawer()
        d.symmetry(4)
        d.pushState()
        d.noSymmetry()
        d.drawCircle(10, 0, 5)
        #expect(d.sdfInstances.count == 1)
        d.popState()
        d.drawCircle(10, 0, 5)
        #expect(d.sdfInstances.count == 5)   // 1 + the 4 restored folds
    }

    @Test func singleFoldWithoutMirrorTurnsSymmetryOff() {
        let d = freshDrawer()
        d.symmetry(6)
        d.symmetry(1)
        d.drawCircle(10, 0, 5)
        #expect(d.sdfInstances.count == 1)
    }

    @Test func svgExportReplicatesCommands() {
        let d = freshDrawer()
        let recorder = SVGRecorder()
        d.svgRecorder = recorder
        d.symmetry(4)
        d.drawCircle(50, 0, 10)
        #expect(recorder.commands.count == 4)
        d.svgRecorder = nil
    }
}
