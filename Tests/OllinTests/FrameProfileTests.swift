import CoreGraphics
import Metal
import Testing
import simd
@testable import Ollin

/// The per-frame profiler. The counts are taken in the encode loop, so the test
/// that matters renders a frame on the real device and reads back what the
/// renderer acted on. A profile that merely walks the batch list would pass
/// while the renderer drew something else.
@Suite
@MainActor
struct FrameProfileTests {

    private func makeRenderer() throws -> MetalRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        return try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                 sampleCount: ollinPreferredSampleCount(device))
    }

    /// Render a drawer off-screen at 120 square, the size the counts are
    /// independent of.
    @discardableResult
    private func render(_ drawer: Drawer, with renderer: MetalRenderer) -> CGImage? {
        renderer.image(of: drawer, viewport: SIMD2<Float>(120, 120), width: 120, height: 120)
    }

    // MARK: The mapping (pure, no device)

    @Test func eachPathCountsUnderItsOwnName() {
        var p = FrameProfile()
        p.countDraw(.triangles, 12)
        p.countDraw(.fringe, 30)
        p.countDraw(.sdf, 3)
        p.countDraw(.glyphAtlas, 24)
        p.countDraw(.clipPop, 0)
        #expect(p.triangleVertices == 12)
        #expect(p.fringeVertices == 30)
        #expect(p.sdfInstances == 3)
        #expect(p.glyphVertices == 24)
        #expect(p.drawCalls == 5)          // the stencil pop draws too
        #expect(p.tessellatedVertices == 66)
        // A fill and a stroke are both tessellated; an SDF instance is not, which
        // is the whole point of the split.
        #expect(p.sdfInstances > 0 && p.tessellatedVertices == 12 + 30 + 24)
    }

    @Test func theTimeSplitAddsUpTheWayItReads() {
        var p = FrameProfile()
        p.cpuDrawMS = 2
        p.cpuEncodeMS = 0.5
        p.gpuMS = 3
        p.waitMS = 11
        // The CPU cost is the work, so the wait stays out of it: it is the
        // display's pace and counting it would pin the number to the frame.
        #expect(p.cpuMS == 2.5)
    }

    @Test func resetClearsTheCountsAndKeepsTheTimes() {
        var p = FrameProfile()
        p.countDraw(.sdf, 5)
        p.batches = 4
        p.passes = 3
        p.gpuMS = 1.25
        p.resetCounts()
        #expect(p.drawCalls == 0)
        #expect(p.sdfInstances == 0)
        #expect(p.batches == 0)
        #expect(p.passes == 0)
        #expect(p.gpuMS == 1.25)   // written whole at the end of a frame
        #expect(p.hasData == false)
    }

    // MARK: What the renderer really drew (device)

    @Test(.enabled(if: Snapshot.hasMetal))
    func aRenderedFrameCountsWhatEachPathDrew() throws {
        guard let renderer = try makeRenderer() else { return }
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.strokePaint = nil
        drawer.drawCircle(30, 30, 10)
        drawer.drawCircle(60, 30, 10)
        drawer.drawCircle(90, 30, 10)          // three instances, one run
        drawer.fillPaint = .color(.white)
        drawer.drawPolygon([Vector2(10, 60), Vector2(110, 60), Vector2(60, 110)])
        drawer.fillPaint = nil
        drawer.strokePaint = .color(.black)
        drawer.strokeWidth = 3
        drawer.drawPolyline([Vector2(10, 100), Vector2(60, 80), Vector2(110, 100)])
        render(drawer, with: renderer)

        let p = renderer.profile
        #expect(p.sdfInstances == 3)           // the three circles, instanced
        #expect(p.triangleVertices > 0)        // the filled triangle, tessellated
        #expect(p.fringeVertices > 0)          // the stroke, edge-expanded
        #expect(p.meshVertices == 0)           // a 2D frame touches no 3D path
        #expect(p.particles == 0)
        #expect(p.drawCalls >= 3)              // at least one per path
        #expect(p.batches == drawer.batches.count)
        // The canvas pass and the present pass at least, both counted at the one
        // place an encoder is made.
        #expect(p.passes >= 2)
        #expect(p.tessellatedVertices == p.triangleVertices + p.fringeVertices)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theCountsAreThisFramesAlone() throws {
        guard let renderer = try makeRenderer() else { return }
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.strokePaint = nil
        for i in 0..<4 { drawer.drawCircle(Double(20 + i * 20), 60, 8) }
        render(drawer, with: renderer)   // warm up: see the one-time-setup test
        render(drawer, with: renderer)
        let first = renderer.profile

        // The same frame again reports the same numbers: nothing accumulates.
        render(drawer, with: renderer)
        #expect(renderer.profile.sdfInstances == first.sdfInstances)
        #expect(renderer.profile.drawCalls == first.drawCalls)
        #expect(renderer.profile.passes == first.passes)

        // A lighter frame reports less, rather than keeping the high-water mark.
        let lighter = Drawer()
        lighter.beginFrame()
        lighter.strokePaint = nil
        lighter.drawCircle(60, 60, 20)
        render(lighter, with: renderer)
        #expect(renderer.profile.sdfInstances == 1)
        #expect(renderer.profile.sdfInstances < first.sdfInstances)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aBatchThatCannotDrawIsNotCounted() throws {
        guard let renderer = try makeRenderer() else { return }
        // An image batch whose texture never builds is skipped in the encode
        // loop, so the count follows the draw rather than the recording. This is
        // why the counters live beside the draw calls.
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.strokePaint = nil
        drawer.drawCircle(60, 60, 20)
        render(drawer, with: renderer)
        #expect(renderer.profile.imageVertices == 0)
        #expect(renderer.profile.drawCalls == 1)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func stateChangesShowUpAsBatches() throws {
        guard let renderer = try makeRenderer() else { return }
        // Ten circles in one blend mode are one run; alternating the blend mode
        // breaks a run per shape. Same shapes, same instance count, ten times the
        // draw calls, which is exactly the reading the profile exists to give.
        let plain = Drawer()
        plain.beginFrame()
        plain.strokePaint = nil
        for i in 0..<10 { plain.drawCircle(Double(10 + i * 10), 60, 4) }
        render(plain, with: renderer)
        let plainProfile = renderer.profile

        let switching = Drawer()
        switching.beginFrame()
        switching.strokePaint = nil
        for i in 0..<10 {
            switching.blendMode(i.isMultiple(of: 2) ? .normal : .add)
            switching.drawCircle(Double(10 + i * 10), 60, 4)
        }
        render(switching, with: renderer)
        let switchingProfile = renderer.profile

        #expect(plainProfile.sdfInstances == switchingProfile.sdfInstances)
        #expect(plainProfile.drawCalls == 1)
        #expect(switchingProfile.drawCalls == 10)
        #expect(switchingProfile.batches > plainProfile.batches)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFirstFrameCarriesItsOneTimeSetup() throws {
        guard let renderer = try makeRenderer() else { return }
        let drawer = Drawer()
        drawer.beginFrame()
        drawer.strokePaint = nil
        drawer.drawCircle(60, 60, 20)

        // A first frame clears the stand-in shadow textures, which are cached for
        // the life of the renderer. The profile says so rather than hiding it:
        // these are real passes on that frame, and a sketch's first frame being
        // dearer than its second is worth being able to see.
        render(drawer, with: renderer)
        let first = renderer.profile.passes
        render(drawer, with: renderer)
        let settled = renderer.profile.passes
        #expect(first > settled)
        #expect(settled == 2)              // the canvas and the present
        render(drawer, with: renderer)
        #expect(renderer.profile.passes == settled)   // and it stays there
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anEffectsTargetCostsItsOwnPass() throws {
        guard let renderer = try makeRenderer() else { return }
        let plain = Drawer()
        plain.beginFrame()
        plain.strokePaint = nil
        plain.drawCircle(60, 60, 20)
        render(plain, with: renderer)   // warm up: see the one-time-setup test
        render(plain, with: renderer)
        let plainPasses = renderer.profile.passes

        // The same circle drawn into an off-screen layer, then composited: the
        // layer is a pass of its own, which is the cost a filter chain adds.
        let sketch = Sketch()
        sketch.drawer.beginFrame()
        sketch.noStroke()
        let target = sketch.renderTarget(width: 120, height: 120)
        sketch.withTarget(target) {
            sketch.drawCircle(60, 60, 20)
        }
        sketch.drawImage(target.image, 0, 0)
        render(sketch.drawer, with: renderer)
        #expect(renderer.profile.passes > plainPasses)
        #expect(renderer.profile.imageVertices > 0)   // the composite quad
    }
}
