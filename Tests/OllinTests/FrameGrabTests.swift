import CoreGraphics
import Testing
@testable import Ollin

/// The frame-grab seam's dispatch logic, exercised without a GPU or a window:
/// an extension is handed the rendered frame only when it opts in, and the
/// opt-in is read live so it can arm and disarm between frames. (The full
/// live path — the runner re-rendering off-screen and calling the hook — is
/// demonstrated by `Examples/Export/Capture`; the headless render the hook
/// hands over is covered by the snapshot tests.)
@Suite
@MainActor
struct FrameGrabTests {

    @Test func capturingExtensionReceivesFrameOnlyWhenArmed() {
        let sketch = Sketch()
        let recorder = Recorder()
        sketch.extend(recorder)

        // Disarmed: the seam reports no demand and delivers nothing.
        recorder.armed = false
        #expect(sketch.wantsRenderedFrames == false)
        sketch.runFrameRendered(Self.pixel)
        #expect(recorder.received == 0)

        // Armed: demand is reported and the frame is delivered.
        recorder.armed = true
        #expect(sketch.wantsRenderedFrames == true)
        sketch.runFrameRendered(Self.pixel)
        #expect(recorder.received == 1)
    }

    @Test func nonCapturingExtensionsAreSkipped() {
        let sketch = Sketch()
        let recorder = Recorder()
        recorder.armed = true
        sketch.extend(NoOpExtension())   // default wantsRenderedFrame == false
        sketch.extend(recorder)

        sketch.runFrameRendered(Self.pixel)
        #expect(recorder.received == 1)   // only the one that asked
    }

    /// A 1×1 stand-in frame — the dispatch doesn't inspect the pixels.
    static let pixel: CGImage = {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }()
}

private final class Recorder: SketchExtension {
    var armed = false
    var received = 0
    var wantsRenderedFrame: Bool { armed }
    func frameRendered(_ sketch: Sketch, _ image: CGImage) { received += 1 }
}

private final class NoOpExtension: SketchExtension {}
