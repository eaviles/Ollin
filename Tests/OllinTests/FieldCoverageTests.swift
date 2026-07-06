import Testing
import Metal
import simd
import COllinShaders
@testable import Ollin

/// The projected screen coverage behind the coverage-adaptive raymarch scale
/// (`MetalRenderer.fieldScreenCoverage`): the resolved quality fraction is a marched-pixel
/// budget at full coverage, so the estimate must shrink with a dollied-out field (that's what
/// lets it trace denser), cap at 1, and fall back to full coverage wherever the projected-corner
/// bound can't be trusted (an unbounded plane, a camera inside or behind the box).
@MainActor
struct FieldCoverageTests {

    private func makeRenderer() throws -> MetalRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                 sampleCount: ollinPreferredSampleCount(device))
    }

    private func viewProjection(eyeZ: Double) -> simd_float4x4 {
        let camera = Camera3D(eye: Vector3(0, 0, eyeZ), target: .zero)
        return camera.projectionMatrix(aspect: 1) * camera.viewMatrix
    }

    private func box(min lo: SIMD3<Float>, max hi: SIMD3<Float>) -> SDF3DGroupInstance {
        var g = SDF3DGroupInstance()
        g.boundsMin = SIMD4<Float>(lo, 0)
        g.boundsMax = SIMD4<Float>(hi, 0)
        g.unbounded = 0
        return g
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func coverageShrinksAsTheCameraDolliesOut() throws {
        guard let renderer = try makeRenderer() else { return }
        let unit = box(min: SIMD3(-1, -1, -1), max: SIMD3(1, 1, 1))
        let near = renderer.fieldScreenCoverage([unit], viewProjection: viewProjection(eyeZ: 4))
        let far = renderer.fieldScreenCoverage([unit], viewProjection: viewProjection(eyeZ: 20))
        #expect(near > far)
        #expect(far > 0)                 // on screen, so it still contributes
        #expect(far < 0.05)              // a dollied-out box covers little of the screen
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func untrustedProjectionsCountAsFullCoverage() throws {
        guard let renderer = try makeRenderer() else { return }
        // Camera inside the box: a corner lands at/behind the camera plane.
        let room = box(min: SIMD3(-5, -5, -5), max: SIMD3(5, 5, 5))
        #expect(renderer.fieldScreenCoverage([room], viewProjection: viewProjection(eyeZ: 0.5)) == 1.0)
        // An unbounded field (a plane) spans the screen.
        var plane = box(min: SIMD3(repeating: 0), max: SIMD3(repeating: 0))
        plane.unbounded = 1
        #expect(renderer.fieldScreenCoverage([plane], viewProjection: viewProjection(eyeZ: 10)) == 1.0)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func offscreenFieldsContributeNothingAndSumsCapAtOne() throws {
        guard let renderer = try makeRenderer() else { return }
        let vp = viewProjection(eyeZ: 10)
        // Far off to the side, in front of the camera: clipped to zero area.
        let aside = box(min: SIMD3(99, -1, -1), max: SIMD3(101, 1, 1))
        #expect(renderer.fieldScreenCoverage([aside], viewProjection: vp) == 0)
        // Many screen-filling fields: the sum caps at 1.
        let big = box(min: SIMD3(-8, -8, -1), max: SIMD3(8, 8, 1))
        #expect(renderer.fieldScreenCoverage([big, big, big], viewProjection: vp) == 1.0)
    }
}
