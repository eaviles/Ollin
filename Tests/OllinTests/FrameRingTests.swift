@testable import Ollin
import Foundation
import Metal
import MetalKit
import QuartzCore
import Testing

/// What a frame the GPU cannot take yet does to the thread that starts it.
///
/// The live path draws on the main thread, which is also the thread the window
/// runs its own controls on. The frame ring gates that draw: the third frame
/// still with the GPU parks the fourth until a slot comes back, which stops the
/// window and not only the picture. A scene lit through a close camera read as
/// a hang for exactly that reason (the file camera in the scene explorer, found
/// 2026-08-25, ~70 ms a frame at 2160² against ~11 ms from the orbit camera).
/// The runner asks the ring before it draws and drops the whole refresh when it
/// is full, so the cost shows as a low frame rate and the window still answers.
@Suite
@MainActor
struct FrameRingProbes {

    /// A frame the GPU cannot finish inside one refresh: a lit scene under a
    /// camera that fills the picture with it.
    final class HeavyProbe: Sketch {
        private(set) var draws = 0
        private var scene: Scene?

        override var canvasSize: CanvasSize { .square(2160) }

        override func setup() {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()      // OllinTests
                .deletingLastPathComponent()      // Tests
                .deletingLastPathComponent()      // repo root
                .appendingPathComponent("Examples/3D/Geometry/SceneExplorer/scene.gltf")
            scene = Scene(path: url.path)
        }

        override func draw() {
            draws += 1
            background(Color(white: 0.05))
            guard let scene, let fileCamera = scene.camera else { return }
            camera(fileCamera)
            lightingPreset(.studio)
            castShadows(true)
            for l in scene.lights { light(l) }
            fill(.white)
            drawScene(scene)
        }
    }

    private func makeView(_ device: MTLDevice, side: Int) -> MTKView {
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: side, height: side), device: device)
        view.drawableSize = CGSize(width: side, height: side)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return view
    }

    /// The ring reports itself full instead of only saying so by blocking, and
    /// it empties again once the GPU is done. Without the count beside the
    /// semaphore there is nothing to ask: waiting is the only way to learn, and
    /// the wait is the defect.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theRingSaysWhenItIsFull() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = HeavyProbe()
        let view = makeView(device, side: 2160)
        sketch.setCanvasSize(width: 2160, height: 2160)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)

        #expect(runner.canStartFrame, "a renderer that has drawn nothing has room")
        for _ in 0..<8 { runner.draw(in: view) }
        #expect(!runner.canStartFrame, "eight heavy frames in a row must fill the ring")

        // Poll rather than sleep a fixed span, and poll for the state itself:
        // the GPU hands slots back on its own thread and a full machine can be
        // late. Ten seconds is a ceiling, not an expectation.
        let deadline = CACurrentMediaTime() + 10
        while !runner.canStartFrame, CACurrentMediaTime() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        #expect(runner.canStartFrame, "the ring must empty once the GPU is done")
    }

    /// The refresh the ring has no room for never reaches the sketch. This is
    /// the whole fix: the thread goes back to the run loop, where the window's
    /// events are waiting, instead of parking inside the renderer.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFullRingDropsTheRefreshInsteadOfWaiting() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = HeavyProbe()
        let view = makeView(device, side: 2160)
        sketch.setCanvasSize(width: 2160, height: 2160)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)

        let refreshes = 24
        for _ in 0..<refreshes { runner.draw(in: view) }
        #expect(sketch.draws >= 1, "the first refreshes find room and must draw")
        #expect(sketch.draws < refreshes,
                "a frame this heavy cannot keep up, so refreshes must be dropped")
    }

    /// A take is the exception, and it is what keeps a replay honest: every
    /// refresh consumes one recorded frame, so a dropped one would slide the
    /// replay off the recording it is reading.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTakeKeepsEveryRefresh() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = HeavyProbe()
        let view = makeView(device, side: 2160)
        sketch.setCanvasSize(width: 2160, height: 2160)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        sketch.takeRecorder = TakeRecorder(sketch: sketch)

        let refreshes = 8
        for _ in 0..<refreshes { runner.draw(in: view) }
        #expect(sketch.draws == refreshes, "a take recording must hold every frame it claims")
    }
}
