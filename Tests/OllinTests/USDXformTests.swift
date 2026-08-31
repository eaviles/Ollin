import Testing
import Foundation
import simd
@testable import Ollin
#if canImport(ModelIO)
import ModelIO
#endif

/// The xformOp evaluator over the raw OllinUSD tree: op composition order
/// (first listed = outermost), the row-vector matrix convention, three-axis
/// rotate orderings, real-first `orient` quaternions, the `!invert!` pivot
/// idiom, `!resetXformStack!`, and agreement with Model I/O's own composition
/// of the example stage's camera.
struct USDXformTests {

    private func stage(_ usda: String) throws -> USDStage {
        try USDStage.load(data: Data(usda.utf8))
    }

    private func apply(_ m: simd_double4x4, _ p: SIMD3<Double>) -> SIMD3<Double> {
        let v = m * SIMD4(p.x, p.y, p.z, 1)
        return SIMD3(v.x, v.y, v.z)
    }

    @Test func firstListedOpIsOutermost() throws {
        // The camera pattern: rotate about the prim's own origin, then place it.
        let s = try stage("""
        #usda 1.0

        def Xform "cam"
        {
            double3 xformOp:translate = (0, 2.5, 7)
            float3 xformOp:rotateXYZ = (-12, 0, 0)
            uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:rotateXYZ"]
        }
        """)
        let m = s.prims[0].localXform().matrix
        let c = cos(-12.0 * .pi / 180), sn = sin(-12.0 * .pi / 180)
        let p = apply(m, SIMD3(0, 0, -1))
        #expect(abs(p.x) < 1e-9)
        #expect(abs(p.y - (2.5 + sn)) < 1e-9)
        #expect(abs(p.z - (7 - c)) < 1e-9)
        #expect(simd_length(apply(m, .zero) - SIMD3(0, 2.5, 7)) < 1e-12)
    }

    @Test func threeAxisRotateAppliesNamedAxesInNameOrder() throws {
        // The value is always (x, y, z) angles; only the name changes the order.
        let s = try stage("""
        #usda 1.0

        def Xform "xyz"
        {
            float3 xformOp:rotateXYZ = (90, 0, 90)
            uniform token[] xformOpOrder = ["xformOp:rotateXYZ"]
        }

        def Xform "zyx"
        {
            float3 xformOp:rotateZYX = (90, 0, 90)
            uniform token[] xformOpOrder = ["xformOp:rotateZYX"]
        }
        """)
        // x first: (0,1,0) rotates onto +z, which the z rotation leaves alone.
        let xyz = apply(s.prims[0].localXform().matrix, SIMD3(0, 1, 0))
        #expect(simd_length(xyz - SIMD3(0, 0, 1)) < 1e-9)
        // z first: (0,1,0) rotates onto -x, which the x rotation leaves alone.
        let zyx = apply(s.prims[1].localXform().matrix, SIMD3(0, 1, 0))
        #expect(simd_length(zyx - SIMD3(-1, 0, 0)) < 1e-9)
    }

    @Test func matrixOpReadsTheRowVectorConvention() throws {
        // A z quarter-turn with translation in the fourth *row*.
        let s = try stage("""
        #usda 1.0

        def Xform "m"
        {
            matrix4d xformOp:transform = ((0, 1, 0, 0), (-1, 0, 0, 0), (0, 0, 1, 0), (3, 4, 5, 1))
            uniform token[] xformOpOrder = ["xformOp:transform"]
        }
        """)
        let m = s.prims[0].localXform().matrix
        #expect(simd_length(apply(m, SIMD3(1, 0, 0)) - SIMD3(3, 5, 5)) < 1e-12)
        #expect(simd_length(apply(m, .zero) - SIMD3(3, 4, 5)) < 1e-12)
    }

    @Test func orientQuaternionIsRealFirst() throws {
        // (w, x, y, z) with w = y = sqrt(2)/2: a +90 degree turn about y.
        let s = try stage("""
        #usda 1.0

        def Xform "o"
        {
            quatf xformOp:orient = (0.7071068, 0, 0.7071068, 0)
            uniform token[] xformOpOrder = ["xformOp:orient"]
        }
        """)
        let m = s.prims[0].localXform().matrix
        #expect(simd_length(apply(m, SIMD3(0, 0, -1)) - SIMD3(-1, 0, 0)) < 1e-6)
        #expect(simd_length(apply(m, SIMD3(1, 0, 0)) - SIMD3(0, 0, -1)) < 1e-6)
    }

    @Test func invertPrefixUndoesThePivot() throws {
        // The pivot idiom: scale about (1, 1, 0) instead of the origin.
        let s = try stage("""
        #usda 1.0

        def Xform "p"
        {
            double3 xformOp:translate:pivot = (1, 1, 0)
            double3 xformOp:scale = (2, 2, 2)
            uniform token[] xformOpOrder = ["xformOp:translate:pivot", "xformOp:scale", "!invert!xformOp:translate:pivot"]
        }
        """)
        let m = s.prims[0].localXform().matrix
        #expect(simd_length(apply(m, SIMD3(1, 1, 0)) - SIMD3(1, 1, 0)) < 1e-12)
        #expect(simd_length(apply(m, .zero) - SIMD3(-1, -1, 0)) < 1e-12)
    }

    @Test func singleAxisOpsCompose() throws {
        let s = try stage("""
        #usda 1.0

        def Xform "s"
        {
            double xformOp:translateX = 3
            double xformOp:rotateZ = 90
            uniform token[] xformOpOrder = ["xformOp:translateX", "xformOp:rotateZ"]
        }
        """)
        let m = s.prims[0].localXform().matrix
        #expect(simd_length(apply(m, SIMD3(1, 0, 0)) - SIMD3(3, 1, 0)) < 1e-9)
    }

    @Test func resetXformStackDropsTheInheritedTransform() throws {
        let s = try stage("""
        #usda 1.0

        def Xform "parent"
        {
            double3 xformOp:translate = (5, 0, 0)
            uniform token[] xformOpOrder = ["xformOp:translate"]

            def Xform "loose"
            {
                double3 xformOp:translate = (0, 1, 0)
                uniform token[] xformOpOrder = ["!resetXformStack!", "xformOp:translate"]
            }

            def Xform "attached"
            {
                double3 xformOp:translate = (0, 1, 0)
                uniform token[] xformOpOrder = ["xformOp:translate"]
            }
        }
        """)
        var worlds: [String: simd_double4x4] = [:]
        s.visitPrims { prim, world in worlds[prim.name] = world }
        let loose = try #require(worlds["loose"])
        let attached = try #require(worlds["attached"])
        #expect(simd_length(apply(loose, .zero) - SIMD3(0, 1, 0)) < 1e-12)
        #expect(simd_length(apply(attached, .zero) - SIMD3(5, 1, 0)) < 1e-12)
    }

    @Test func opsWithoutAnOrderDoNotApply() throws {
        let s = try stage("""
        #usda 1.0

        def Xform "bare"
        {
            double3 xformOp:translate = (5, 5, 5)
        }
        """)
        let (m, resets) = s.prims[0].localXform()
        #expect(m == matrix_identity_double4x4)
        #expect(!resets)
    }

    #if canImport(ModelIO)
    /// The cross-oracle: Model I/O composes the example stage's camera ops
    /// (translate then rotateXYZ) into its transform matrix; the evaluator
    /// must land on the same matrix.
    @Test func modelIOAgreesOnTheExampleStageCamera() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Examples/3D/Geometry/LoadedScene/stage.usda")
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let parsed = try USDStage.load(contentsOf: url)
        let court = try #require(parsed.prims.first)
        let view = try #require(court.child("view"))
        let ours = view.localXform().matrix

        let asset = MDLAsset(url: url)
        func find(_ obj: MDLObject, _ name: String) -> MDLObject? {
            if obj.name == name { return obj }
            for child in obj.children.objects {
                if let hit = find(child, name) { return hit }
            }
            return nil
        }
        var camera: MDLObject?
        for i in 0..<asset.count where camera == nil { camera = find(asset.object(at: i), "view") }
        let theirs = try #require(camera?.transform?.matrix)
        for c in 0..<4 {
            for r in 0..<4 {
                #expect(abs(Double(theirs[c][r]) - ours[c][r]) < 1e-5,
                        "column \(c) row \(r)")
            }
        }
    }
    #endif
}
