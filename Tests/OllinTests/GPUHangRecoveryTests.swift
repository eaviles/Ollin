@testable import Ollin
import CoreGraphics
import Foundation
import Metal
import MetalKit
import QuartzCore
import Testing

/// The live window after a GPU hang. A hang the system blames on one of the
/// window's frames resets the GPU and refuses every later submission on the
/// queue that carried it, so a window that kept drawing showed its last
/// finished frame for good. The completed handler marks the queue spent, the
/// next live frame takes a new one before it draws, and the stats carry the
/// sentence for the panel.
@Suite
@MainActor
struct GPUHangRecoveryTests {
    final class Dots: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
        override func draw() {
            background(.white)
            noStroke()
            fill(.black)
            drawCircle(32, 32, 12)
        }
    }

    /// The scene that hung this machine's GPU on the day this was written: a
    /// shadow-casting point light beside a shadow-casting key, the route the
    /// Chapter 27 figure takes. Two frames of it, then a plain mark.
    final class LampAndKey: Sketch {
        override var canvasSize: CanvasSize { .size(880, 550) }
        let block = Mesh.box(width: 1.3, height: 1.9, depth: 1.3)
        let post = Mesh.cylinder(radius: 0.42, height: 2.4)
        let floor = Mesh.plane(width: 20, depth: 14)
        override func draw() {
            if frameCount < 2 {
                background(Color(hex: 0x141821))
                camera(.perspective(eye: Vector3(-0.6, 4.4, 7.2), target: Vector3(0.4, 0.8, 0),
                                    fieldOfView: .pi / 4.2))
                directionalLight(Color(hex: 0xC9DBFF), direction: Vector3(-0.62, -0.78, -0.20),
                                 intensity: 0.95)
                pointLight(Color(hex: 0xFFC079), at: Vector3(-4.6, 3.2, 2.2), intensity: 1.5)
                directionalLight(Color(white: 0.75), direction: Vector3(0, -0.5, -1),
                                 intensity: 0.22, castsShadow: false)
                ambientLight(Color(white: 0.13))
                castShadows()
                shadowSoftness(0.45)
                fill(Color(hex: 0x93A0B4))
                material(.matte)
                withState { translate(0, -0.02, 0); drawMesh(floor) }
                material(.plastic)
                fill(Color(hex: 0xD8664A))
                withState { translate(-0.9, 0.95, 0.4); rotateY(0.3); drawMesh(block) }
                fill(Color(hex: 0x5FA9A0))
                withState { translate(1.9, 1.2, -0.6); drawMesh(post) }
            } else {
                background(.white)
                noStroke()
                fill(.black)
                drawCircle(width / 2, height / 2, 20)
            }
        }
    }

    /// The frames the loop handed over.
    final class Sink: SketchExtension {
        var images: [CGImage] = []
        var wantsRenderedFrame: Bool { true }
        func frameRendered(_ sketch: Sketch, image: CGImage) { images.append(image) }
    }

    /// A headless view with the drawable format the canvas gives a window.
    private func makeView(_ device: MTLDevice, width: Int, height: Int, for sketch: Sketch) -> MTKView {
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: width, height: height), device: device)
        view.drawableSize = CGSize(width: width, height: height)
        view.colorPixelFormat = sketch.colorOutput.drawablePixelFormat
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return view
    }

    /// Turn the main loop until `done` or the seconds pass; the probe comes
    /// before the clock, so a late wakeup still finds what it waited for.
    private func spin(seconds: Double = 10, until done: () -> Bool) {
        let deadline = CACurrentMediaTime() + seconds
        while !done() {
            if CACurrentMediaTime() > deadline { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    /// The mean of the color bytes at the picture's center.
    private func inkAtCenter(_ image: CGImage) throws -> Int {
        let bytes = [UInt8](try #require(image.dataProvider?.data as Data?))
        let i = (image.height / 2) * image.bytesPerRow + (image.width / 2) * 4
        return (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aPlantedHangSpendsTheQueueAndTheNextFrameTakesANewOne() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Dots()
        let view = makeView(device, width: 64, height: 64, for: sketch)
        sketch.setCanvasSize(width: 64, height: 64)
        let sink = Sink()
        sketch.extend(sink)
        let stats = FrameStats()
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        runner.observeStats(into: stats)
        let renderer = runner.renderer
        let first = renderer.commandQueue
        renderer.plantedLiveHang = 1

        // Frame 0 runs clean; frame 1 runs too but its completion is read as
        // a hang, which marks the queue spent and moves nothing else: the
        // handler runs off the thread that draws.
        runner.draw(in: view)
        spin { sink.images.count >= 1 }
        runner.draw(in: view)
        spin { renderer.gpuFailures.queueIsSpent }
        #expect(renderer.gpuFailures.queueIsSpent)
        #expect(renderer.gpuFailures.spendings == 1)
        #expect(renderer.commandQueue === first)
        #expect(renderer.queueReplacements == 0)

        // The next frame takes a new queue before it draws, and comes back
        // drawn on it; the sentence reaches the stats on the main queue.
        sink.images.removeAll()
        runner.draw(in: view)
        spin { !sink.images.isEmpty }
        #expect(renderer.commandQueue !== first)
        #expect(renderer.queueReplacements == 1)
        #expect(!renderer.gpuFailures.queueIsSpent)
        let drawn = try #require(sink.images.last)
        #expect(try inkAtCenter(drawn) < 20, "the frame after the replacement drew no mark")
        spin { stats.gpuNotice != nil }
        #expect(stats.gpuNotice?.contains("new one") == true)

        // A frame that runs clean replaces nothing more.
        runner.draw(in: view)
        spin { sink.images.count >= 2 }
        #expect(renderer.queueReplacements == 1)
    }

    /// Opt in with `OLLIN_REAL_HANG=1`, on a quiet machine: a GPU reset makes
    /// every other process drawing a victim. Two frames of the scene that hung
    /// the GPU here, then the plain mark; when the machine does not hang on
    /// the scene, nothing is recovered from and the test says so.
    @Test(.enabled(if: Snapshot.hasMetal && ProcessInfo.processInfo.environment["OLLIN_REAL_HANG"] == "1"))
    func aRealHangIsSurvivedOnThisMachine() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = LampAndKey()
        let view = makeView(device, width: 880, height: 550, for: sketch)
        sketch.setCanvasSize(width: 880, height: 550)
        let sink = Sink()
        sketch.extend(sink)
        let stats = FrameStats()
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        runner.observeStats(into: stats)
        let renderer = runner.renderer
        let first = renderer.commandQueue

        // The scene's frames, each waited for: a hang takes the system seconds
        // to report, and a refresh the ring has no room for is dropped.
        var scenePasses = 0
        while sketch.frameCount < 2, scenePasses < 8 {
            runner.draw(in: view)
            spin(seconds: 40) { renderer.inFlightFrames == 0 }
            scenePasses += 1
        }
        guard renderer.gpuFailures.spendings > 0 else {
            print("GPUHangRecoveryTests: the scene did not hang this GPU, so there was nothing to recover from")
            return
        }

        // The plain frame takes the new queue and comes back drawn.
        sink.images.removeAll()
        var plainPasses = 0
        while sink.images.isEmpty, plainPasses < 8 {
            runner.draw(in: view)
            spin(seconds: 40) { renderer.inFlightFrames == 0 }
            plainPasses += 1
        }
        spin { !sink.images.isEmpty }
        #expect(renderer.commandQueue !== first)
        #expect(renderer.queueReplacements >= 1)
        let drawn = try #require(sink.images.last)
        #expect(try inkAtCenter(drawn) < 20, "the frame after the real hang drew no mark")
        print("GPUHangRecoveryTests: the GPU hung \(renderer.gpuFailures.spendings) time(s) on the scene; "
              + "\(renderer.queueReplacements) queue replacement(s); the plain frame drew")
    }
}
