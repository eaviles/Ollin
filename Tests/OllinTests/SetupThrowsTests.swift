import Foundation
import Metal
import MetalKit
@testable import Ollin
import Testing

/// `setup()` may throw. A loader that cannot read its file lets its `FileError`
/// out with a bare `try`, and what happens next depends on who asked for the
/// frame: a headless export fails with the sketch's own error, and a window
/// holds the sketch rather than drawing it half built, with the sentence on
/// stderr and in the runner's `setupError` for a host's error strip, cleared
/// again by the next `setup()` that runs through.
@Suite(.serialized)
@MainActor
struct SetupThrowsTests {

    struct Planted: Error, CustomStringConvertible {
        var description: String { "the planted failure" }
    }

    /// Refuses in `setup()` while `fails` holds; counts the frames it drew.
    final class Refuses: Sketch {
        var fails = true
        var drew = 0
        override var canvasSize: CanvasSize { .square(64) }
        override func setup() throws {
            if fails { throw Planted() }
        }
        override func draw() {
            drew += 1
            background(.white)
        }
    }

    /// The shape a sketch writes: a bare `try` on a loader, in `setup()`.
    final class Loads: Sketch {
        var photo: Image!
        override var canvasSize: CanvasSize { .square(64) }
        override func setup() throws {
            photo = try loadImage("/no/such/folder/picture.png")
        }
        override func draw() { drawImage(photo, 0, 0) }
    }

    @Test func aVectorExportFailsWithTheLoadersOwnError() {
        #expect(throws: FileError.self) { try OllinApp.svg(of: Loads()) }
        #expect(throws: Planted.self) { try OllinApp.pdf(of: Refuses()) }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aStillFailsWithTheSketchsOwnError() {
        #expect(throws: Planted.self) { try OllinApp.image(of: Refuses(), frame: 0) }
    }

    /// A still whose `setup()` runs through is unaffected: an override may
    /// leave `throws` off, and one that keeps it and throws nothing draws.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSetupThatRunsThroughDraws() throws {
        let sketch = Refuses()
        sketch.fails = false
        _ = try OllinApp.image(of: sketch, frame: 0)
        #expect(sketch.drew == 1)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theWindowHoldsTheSketchAndSaysWhy() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Refuses()
        let view = makeView(device, side: 64, for: sketch)
        sketch.setCanvasSize(width: 64, height: 64)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)
        var reported: [String?] = []
        runner.onSetupError = { reported.append($0) }

        runner.draw(in: view)
        runner.draw(in: view)
        #expect(sketch.drew == 0, "a sketch whose setup() threw was drawn")
        #expect(runner.setupError?.contains("the planted failure") == true, "\(String(describing: runner.setupError))")
        #expect(reported.count == 1 && reported.first == runner.setupError, "reported \(reported)")

        // A reload whose setup() runs through clears the sentence and draws.
        let healthy = Refuses()
        healthy.fails = false
        runner.reload(to: healthy)
        runner.draw(in: view)
        #expect(healthy.drew == 1)
        #expect(runner.setupError == nil)
        #expect(reported.count == 2 && reported[1] == nil, "reported \(reported)")
    }

    private func makeView(_ device: MTLDevice, side: Int, for sketch: Sketch) -> MTKView {
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: side, height: side), device: device)
        view.drawableSize = CGSize(width: side, height: side)
        view.colorPixelFormat = sketch.colorOutput.drawablePixelFormat
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return view
    }
}
