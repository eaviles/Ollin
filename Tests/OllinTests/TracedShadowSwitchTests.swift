@testable import Ollin
import CoreGraphics
import Foundation
import Metal
import Testing

/// Traced shadows switched off on a device that would trace them. A machine
/// whose GPU cannot be trusted with traced shadows sets
/// `OLLIN_NO_TRACED_SHADOWS=1`, and a point or area caster then casts through
/// its rasterized map, as on a device without ray tracing, while the frame is
/// counted so a drive that needs the traced picture knows it did not get it.
///
/// Every render here has the switch off on a renderer of its own, so nothing
/// in this suite traces a shadow, which is what lets it run on that machine.
@Suite
@MainActor
struct TracedShadowSwitchTests {
    /// A lamp over a block on a floor: one point light, casting or not.
    final class LampOverBlock: Sketch {
        var casts = true
        override var canvasSize: CanvasSize { .size(240, 160) }
        let block = Mesh.box(width: 1.2, height: 1.2, depth: 1.2)
        let floor = Mesh.plane(width: 12, depth: 12)
        override func draw() {
            background(Color(white: 0.1))
            camera(.perspective(eye: Vector3(0, 4, 6), target: Vector3(0, 0.4, 0),
                                fieldOfView: .pi / 4))
            pointLight(.white, at: Vector3(-2.5, 3.5, 1.5), intensity: 1.5)
            ambientLight(Color(white: 0.2))
            if casts { castShadows() }
            fill(Color(white: 0.8))
            material(.matte)
            drawMesh(floor)
            withState { translate(0, 0.6, 0); drawMesh(block) }
        }
    }

    /// One frame with traced shadows off, and how many frames the renderer
    /// counted as cast through a map in its place.
    private func render(casts: Bool) throws -> (image: CGImage, counted: Int) {
        let sketch = LampOverBlock()
        sketch.casts = casts
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        renderer.tracesShadows = false
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        let before = MetalRenderer.tracedShadowFallbacks
        let image = try #require(try OllinApp.renderImage(of: sketch, frame: 0, fps: 60, renderer: renderer))
        return (image, MetalRenderer.tracedShadowFallbacks - before)
    }

    @Test(.enabled(if: Snapshot.hasMetal && Snapshot.hasRaytracing))
    func aSwitchedOffPointCasterCastsThroughItsMapAndIsCounted() throws {
        let shadowed = try render(casts: true)
        #expect(shadowed.counted >= 1, "the frame that would have traced was not counted")

        // The map did cast: the same scene with no caster is a different picture.
        let plain = try render(casts: false)
        #expect(plain.counted == 0, "a frame with nothing to trace was counted")
        let difference = try #require(imageDifference(shadowed.image, plain.image))
        #expect(difference.max > 24, "no shadow was drawn through the map")
    }

    /// The switch is the environment's, read where the device is asked.
    @Test func theSwitchReadsTheEnvironment() {
        let off = ProcessInfo.processInfo.environment["OLLIN_NO_TRACED_SHADOWS"] == "1"
        #expect(MetalRenderer.tracedShadowsWanted() == !off)
    }
}
