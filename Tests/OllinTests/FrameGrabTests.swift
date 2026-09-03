@testable import Ollin
import CoreGraphics
import Foundation
import Metal
import MetalKit
import QuartzCore
import Testing

/// The frame-grab seam: an extension is handed the rendered frame only when it
/// asked for it, the ask is read once per frame, and on the live path the frame
/// it gets is the one the window shows, brought to the canvas size, without the
/// sketch being drawn a second time.
@Suite
@MainActor
struct FrameGrabTests {

    // MARK: Dispatch (no GPU)

    @Test func anExtensionIsAskedOnceAndGetsTheFrameItAskedFor() {
        let sketch = Sketch()
        let recorder = Recorder()
        sketch.extend(recorder)

        // Disarmed: nobody asked, so nothing is delivered.
        recorder.armed = false
        var askers = sketch.renderedFrameAskers()
        #expect(askers.isEmpty)
        sketch.runFrameRendered(image: Self.pixel, texture: nil, to: askers)
        #expect(recorder.received == 0)

        // Armed: the ask is taken, and disarming afterwards does not lose the
        // frame, since the frame arrives after the GPU is done with it.
        recorder.armed = true
        askers = sketch.renderedFrameAskers()
        #expect(!askers.isEmpty)
        recorder.armed = false
        sketch.runFrameRendered(image: Self.pixel, texture: nil, to: askers)
        #expect(recorder.received == 1)
    }

    @Test func nonCapturingExtensionsAreSkipped() {
        let sketch = Sketch()
        let recorder = Recorder()
        recorder.armed = true
        sketch.extend(NoOpExtension())   // default wantsRenderedFrame == false
        sketch.extend(recorder)

        let askers = sketch.renderedFrameAskers()
        #expect(askers.image.count == 1)
        sketch.runFrameRendered(image: Self.pixel, texture: nil, to: askers)
        #expect(recorder.received == 1)   // only the one that asked
    }

    @Test func imageAndTextureAsksAreKeptApart() {
        let sketch = Sketch()
        let recorder = Recorder()
        recorder.armed = true
        let sharer = Sharer()
        sketch.extend(recorder)
        sketch.extend(sharer)

        let askers = sketch.renderedFrameAskers()
        #expect(askers.image.count == 1 && askers.texture.count == 1)
        // A frame with only the image ready reaches the image asker alone.
        sketch.runFrameRendered(image: Self.pixel, texture: nil, to: askers)
        #expect(recorder.received == 1)
        #expect(sharer.received == 0)
    }

    // MARK: The live path

    /// A time-free picture, so the live frame and the headless one draw the same
    /// geometry: a rosette of discs and one stroked ring.
    final class Rosette: Sketch {
        override var canvasSize: CanvasSize { .square(256) }
        override func draw() {
            background(Color(white: 0.08))
            noStroke()
            for i in 0..<6 {
                let a = Double(i) / 6 * .tau
                fill(Color(hue: Double(i) / 6, saturation: 0.8, brightness: 0.9))
                drawCircle(center: center + Vector2(angle: a) * 70, radius: 34)
            }
            noFill()
            stroke(.white)
            strokeWeight(3)
            drawCircle(center: center, radius: 110)
        }
    }

    /// One white disc per frame, at a column that names the frame.
    final class Marker: Sketch {
        var piles = false
        override var canvasSize: CanvasSize { .square(256) }
        override func setup() { if piles { noClear() } }
        override func draw() {
            if !piles || frameCount == 1 { background(.black) }
            noStroke()
            fill(.white)
            drawCircle(Self.column(of: frameCount), 128, 20)
        }
        static func column(of frame: Int) -> Double { 40 + Double((frame - 1) % 3) * 88 }
    }

    /// A lit box under a camera that asks for the ground grid, which the live
    /// runner injects as host chrome and a headless render never draws.
    final class LitBox: Sketch {
        override var canvasSize: CanvasSize { .square(256) }
        override func draw() {
            background(Color(white: 0.1))
            perspective(eye: Vector3(3, 2.5, 4), target: .zero)
            groundGrid()
            lightingPreset(.studio)
            fill(Color(red: 0.8, green: 0.5, blue: 0.3))
            drawBox(size: 1.2)
        }
    }

    /// Collects what the loop hands over, and the pass count of each frame.
    final class Sink: SketchExtension {
        var armed = false
        var images: [CGImage] = []
        var textureSizes: [(Int, Int)] = []
        var passes: [Int] = []
        var wantsRenderedFrame: Bool { armed }
        func frameRendered(_ sketch: Sketch, image: CGImage) { images.append(image) }
        var wantsRenderedTexture: Bool { armed }
        func frameRendered(_ sketch: Sketch, texture: MTLTexture) {
            textureSizes.append((texture.width, texture.height))
        }
        func afterFrame(_ sketch: Sketch, _ info: FrameInfo) { passes.append(info.profile.passes) }
    }

    /// A headless view of `side` pixels, with the drawable format the canvas
    /// gives a real window (the present pass encodes for it).
    private func makeView(_ device: MTLDevice, side: Int, for sketch: Sketch) -> MTKView {
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: side, height: side), device: device)
        view.drawableSize = CGSize(width: side, height: side)
        view.colorPixelFormat = sketch.colorOutput.drawablePixelFormat
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return view
    }

    /// Turn the main loop until `done`, or ten seconds pass. The delivery rides
    /// the main queue, so the loop has to turn for it to land; the probe comes
    /// before the clock, so a late wakeup still finds what it was waiting for.
    private func spin(until done: () -> Bool) {
        let deadline = CACurrentMediaTime() + 10
        while !done() {
            if CACurrentMediaTime() > deadline { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
    }

    /// Mean absolute difference over the color bytes of two images of one size.
    private func meanDifference(_ a: CGImage, _ b: CGImage) throws -> Double {
        let (pa, pb) = (try #require(Self.rgba(of: a)), try #require(Self.rgba(of: b)))
        try #require(pa.count == pb.count)
        var sum = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            sum += abs(Int(pa[i]) - Int(pb[i])) + abs(Int(pa[i + 1]) - Int(pb[i + 1]))
                + abs(Int(pa[i + 2]) - Int(pb[i + 2]))
        }
        return Double(sum) / Double(pa.count / 4 * 3)
    }

    private func brightness(_ image: CGImage, x: Int, y: Int) throws -> Int {
        let bytes = try #require(Self.rgba(of: image))
        let i = (y * image.width + x) * 4
        return (Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theGrabIsTheFrameOnScreenAndCostsOnePass() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Rosette()
        let view = makeView(device, side: 256, for: sketch)
        sketch.setCanvasSize(width: 256, height: 256)
        let sink = Sink()
        sketch.extend(sink)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)

        // Unarmed: the frame costs what it costs (the first one also bakes the
        // lookup tables, so the second is the steady frame), and nothing is
        // delivered.
        runner.draw(in: view)
        runner.draw(in: view)
        let plainPasses = try #require(sink.passes.last)
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        #expect(sink.images.isEmpty && sink.textureSizes.isEmpty)

        // Armed for both: one more pass (the tone-map into the grab texture),
        // and the frame arrives at the canvas size, byte for byte the headless
        // render of the same picture.
        sink.armed = true
        runner.draw(in: view)
        spin { !sink.images.isEmpty && !sink.textureSizes.isEmpty }
        let image = try #require(sink.images.first)
        #expect(image.width == 256 && image.height == 256)
        #expect(sink.textureSizes.first.map { $0 == (256, 256) } == true)
        #expect(sink.passes.last == plainPasses + 1,
                "a grab adds one present pass, never a second render")
        let reference = try #require(OllinApp.image(of: Rosette(), frame: 0))
        let mean = try meanDifference(image, reference)
        #expect(mean == 0, "the grab must be the on-screen render itself (mean \(mean))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aLargerWindowIsMinifiedToTheCanvas() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Rosette()
        let view = makeView(device, side: 640, for: sketch)
        sketch.setCanvasSize(width: 256, height: 256)
        let sink = Sink()
        sketch.extend(sink)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)

        sink.armed = true
        runner.draw(in: view)
        spin { !sink.images.isEmpty }
        let image = try #require(sink.images.first)
        #expect(image.width == 256 && image.height == 256)
        // A 2.5x picture averaged down is the same picture with softer edges,
        // not another one: close to the 1x render everywhere, and the ring's
        // stroke still lands where it was drawn.
        let reference = try #require(OllinApp.image(of: Rosette(), frame: 0))
        let mean = try meanDifference(image, reference)
        #expect(mean < 4, "a minified grab must still be the same picture (mean \(mean))")
        #expect(try brightness(image, x: 128, y: 18) > 120, "the ring's stroke survives the minification")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSmallerWindowDrawsTheFrameAtCanvasSize() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Rosette()
        let view = makeView(device, side: 96, for: sketch)
        sketch.setCanvasSize(width: 256, height: 256)
        let sink = Sink()
        sketch.extend(sink)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)

        sink.armed = true
        runner.draw(in: view)
        spin { !sink.images.isEmpty }
        let image = try #require(sink.images.first)
        #expect(image.width == 256 && image.height == 256)
        // The window is smaller than the canvas, so the frame was drawn at the
        // canvas size and the window shows it scaled: the grab is the full
        // render, not a blown-up 96-pixel picture.
        let reference = try #require(OllinApp.image(of: Rosette(), frame: 0))
        let mean = try meanDifference(image, reference)
        #expect(mean == 0, "a small window must not decide how sharp the take is (mean \(mean))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func framesArriveInOrderAndEachIsTheOneAskedFor() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Marker()
        let view = makeView(device, side: 256, for: sketch)
        sketch.setCanvasSize(width: 256, height: 256)
        let sink = Sink()
        sketch.extend(sink)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)

        sink.armed = true
        for _ in 0..<3 { runner.draw(in: view) }
        spin { sink.images.count >= 3 }
        try #require(sink.images.count == 3)
        for (k, image) in sink.images.enumerated() {
            for column in 0..<3 {
                let x = Int(Marker.column(of: column + 1))
                let lit = try brightness(image, x: x, y: 128) > 128
                #expect(lit == (column == k),
                        "frame \(k + 1)'s grab must carry frame \(k + 1)'s disc alone")
            }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anAccumulatingSketchHandsOverThePile() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Marker()
        sketch.piles = true
        let view = makeView(device, side: 400, for: sketch)   // larger than the canvas: the pile keeps its size
        sketch.setCanvasSize(width: 256, height: 256)
        let sink = Sink()
        sketch.extend(sink)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)

        runner.draw(in: view)                    // the first disc, unarmed
        sink.armed = true
        runner.draw(in: view)
        runner.draw(in: view)
        spin { sink.images.count >= 2 }
        let last = try #require(sink.images.last)
        #expect(last.width == 256 && last.height == 256)
        // The pile holds every disc so far, arming included: the first was drawn
        // before anyone asked and must not have been wiped by the ask.
        for column in 0..<3 {
            #expect(try brightness(last, x: Int(Marker.column(of: column + 1)), y: 128) > 128,
                    "disc \(column + 1) must be on the pile")
        }
        #expect(try brightness(last, x: 128, y: 30) < 20, "the background stays dark")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theGroundGridStaysOutOfTheGrab() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = LitBox()
        let view = makeView(device, side: 256, for: sketch)
        sketch.setCanvasSize(width: 256, height: 256)
        let sink = Sink()
        sketch.extend(sink)
        let runner = SketchRunner(sketch: sketch, view: view, device: device)

        // The runner bridges the sketch's `groundGrid()` into the host's own
        // preference on the first frame, so the flag is the sketch's to set and
        // the preference is put back afterwards.
        let defaults = UserDefaults.standard
        let hadGrid = defaults.object(forKey: OllinHUD.showGridKey)
        defer {
            if let hadGrid { defaults.set(hadGrid, forKey: OllinHUD.showGridKey) }
            else { defaults.removeObject(forKey: OllinHUD.showGridKey) }
        }

        runner.draw(in: view)              // the first frame bridges the flag
        sink.armed = true
        runner.draw(in: view)
        spin { !sink.images.isEmpty }
        let image = try #require(sink.images.first)
        // The grid is host chrome. With the grab armed it leaves the window, so
        // the take matches the headless render, which never had it.
        let reference = try #require(OllinApp.image(of: LitBox(), frame: 0))
        let mean = try meanDifference(image, reference)
        #expect(mean < 0.5, "the ground grid must not reach a recorded frame (mean \(mean))")
    }

    /// A 1×1 stand-in frame — the dispatch doesn't inspect the pixels.
    static let pixel: CGImage = {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }()

    static func rgba(of image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let ptr = ctx.data else { return nil }
        return Array(UnsafeRawBufferPointer(start: ptr, count: w * h * 4))
    }
}

private final class Recorder: SketchExtension {
    var armed = false
    var received = 0
    var wantsRenderedFrame: Bool { armed }
    func frameRendered(_ sketch: Sketch, image: CGImage) { received += 1 }
}

private final class Sharer: SketchExtension {
    var received = 0
    var wantsRenderedTexture: Bool { true }
    func frameRendered(_ sketch: Sketch, texture: MTLTexture) { received += 1 }
}

private final class NoOpExtension: SketchExtension {}
