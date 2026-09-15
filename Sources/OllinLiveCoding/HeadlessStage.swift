import CoreGraphics
import Foundation
import Metal
import MetalKit
import Ollin

/// A stage with no window, for the headless checks: a Metal view, one frame at
/// a time through a real `SketchRunner`, and a way to read back the picture it
/// drew and the state the sketch is holding.
///
/// It exists because carrying a run across a swap can only be checked against a
/// runner (the canvas and `setup()` live there, not in the session), and both
/// `--selftest` and `--sessiontest` need the same few moves.
@MainActor
enum HeadlessStage {

    /// A square view of `side` pixels in the format a window's canvas gives the
    /// present pass for a standard sketch.
    static func view(side: Int) -> MTKView? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: side, height: side), device: device)
        view.drawableSize = CGSize(width: side, height: side)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return view
    }

    /// Draw exactly one more frame of the run, and say whether one went
    /// through. A refresh the frame ring has no room for is dropped rather than
    /// drawn, which is the live path's own rule, so the ask is repeated until
    /// the sketch's own counter says a frame actually landed.
    @discardableResult
    static func step(_ runner: SketchRunner, _ view: MTKView, _ sketch: Sketch,
                     counter: String = "frames") -> Bool {
        let before = saved(counter, of: sketch) ?? 0
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            runner.draw(in: view)
            if (saved(counter, of: sketch) ?? 0) > before { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.004))
        }
        return false
    }

    /// Draw the next frame with the grab armed and hand back the picture the
    /// window would have shown. It is the frame itself, never an extra one: on
    /// a canvas that never clears an extra frame is an extra mark.
    static func grab(_ sink: FrameSink, _ runner: SketchRunner, _ view: MTKView,
                     _ sketch: Sketch) -> CGImage? {
        sink.images.removeAll()
        sink.armed = true
        defer { sink.armed = false }
        guard step(runner, view, sketch) else { return nil }
        let deadline = Date().addingTimeInterval(20)
        while sink.images.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        return sink.images.last
    }

    /// How many light bars stand across the middle of the canvas. On a canvas
    /// that never clears and a sketch that paints one bar per frame, that is
    /// how many frames the run has drawn, read off the picture with no
    /// instrumentation inside the sketch.
    static func bars(of image: CGImage) -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &pixels, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return -1 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let row = height / 2
        var count = 0
        var inside = false
        for x in 0..<width {
            let lit = pixels[(row * width + x) * 4] > 160
            if lit, !inside { count += 1 }
            inside = lit
        }
        return count
    }

    /// One of a loaded sketch's `@Saved` whole numbers, read the way a
    /// checkpoint reads them: the type belongs to the dylib, so this is the
    /// only way in from here.
    static func saved(_ name: String, of sketch: Sketch) -> Int? {
        guard let handle = sketch.savedProperties().first(where: { $0.name == name }),
              let data = try? handle.property.encodedValue() else { return nil }
        return try? JSONDecoder().decode(Int.self, from: data)
    }

    /// A sketch that piles one bar per frame onto a canvas that never clears,
    /// keeping count in a `@Saved` property. How many bars stand says how many
    /// frames the run has drawn, and whether `setup()` ran again (its
    /// background would have wiped them).
    ///
    /// `mark` is the bar's width, the one number an "edit" moves; `build` reads
    /// 1 from a plain compile and 2 from an optimized one, in `init` because
    /// a carried run never runs `setup()`.
    static func pilingProbe(mark: Int) -> String {
        """
        import Ollin
        final class RunProbe: Sketch {
            @Saved var frames = 0
            @Param(0...2) var build = 0.0
            @Param(1...40) var mark = \(mark).0
            override var canvasSize: CanvasSize { .square(256) }
            required init() {
                super.init()
                build = _isDebugAssertConfiguration() ? 1 : 2
            }
            override func setup() {
                noClear()
                background(.black)
            }
            override func draw() {
                frames += 1
                noStroke()
                fill(.white)
                drawRect(Double(frames - 1) * 16, 0, \(mark), 256)
            }
        }
        """
    }
}

/// An extension that only counts frames, for the check that a swap carrying the
/// run keeps the extensions the sketch installed for itself.
@MainActor
final class FrameCounter: SketchExtension {
    var frames = 0
    func afterFrame(_ sketch: Sketch, _ info: FrameInfo) { frames += 1 }
}

/// The rendered frame, for a check that needs to look at the canvas.
@MainActor
final class FrameSink: SketchExtension {
    var armed = false
    var images: [CGImage] = []
    var wantsRenderedFrame: Bool { armed }
    func frameRendered(_ sketch: Sketch, image: CGImage) { images.append(image) }
}
