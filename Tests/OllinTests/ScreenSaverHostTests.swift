import AppKit
import Foundation
import Metal
import ScreenSaver
import Testing
@testable import Ollin

/// A sketch running as the machine's screen saver.
///
/// Three claims here cannot be read off the source, and each of them is a way
/// the saver would be broken rather than merely wrong. It has to build its
/// canvas when the system starts it. It has to let go of that canvas when it
/// leaves the window, because the system makes a fresh view every time the saver
/// comes up and lets go of none of them, so a copy that keeps drawing is a copy
/// competing with its own replacement for the GPU. And it must not answer input:
/// the contract of a screen saver is that a key or a click gives the machine
/// back, and the view that answered would be the view that swallowed it.
@MainActor
struct ScreenSaverHostTests {

    /// A saver with a sketch in it, the way the generated one is written.
    final class TestSaverView: SketchSaverView {
        override func makeSketch() -> Sketch { TestSketch() }
    }

    final class TestSketch: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
    }

    /// The shape the generator writes: the canvas follows whatever it is put on.
    final class FillingSketch: Sketch {
        override var windowMode: WindowMode { .resizable }
    }

    // MARK: Building and putting away

    @Test func aSaverBuildsItsCanvasWhenTheSystemStartsIt() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
        let saver = try #require(TestSaverView(frame: NSRect(x: 0, y: 0, width: 320, height: 200),
                                               isPreview: false))
        // Nothing is built until the system says so, so a saver sitting in a
        // list costs no GPU at all.
        #expect(saver.subviews.isEmpty)

        saver.startAnimation()
        let canvas = try #require(saver.subviews.first as? OllinMTKView)
        #expect(canvas.sketch is TestSketch)
        #expect(canvas.delegate != nil, "nothing would drive the frames")
    }

    @Test func leavingTheWindowPutsTheCanvasAway() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let saver = try #require(TestSaverView(frame: window.contentLayoutRect, isPreview: false))
        window.contentView?.addSubview(saver)
        saver.startAnimation()
        #expect(!saver.subviews.isEmpty)

        // What the system does when the saver is over. `stopAnimation()` is not
        // this: that one arrives for the preview in System Settings and stays
        // quiet when somebody wakes the machine.
        saver.removeFromSuperview()
        #expect(saver.subviews.isEmpty, "an abandoned copy would go on drawing frames nobody sees")
    }

    // MARK: The click that gives the machine back

    @Test func theCanvasStaysOutOfTheEventPath() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
        let saver = try #require(TestSaverView(frame: NSRect(x: 0, y: 0, width: 320, height: 200),
                                               isPreview: false))
        saver.startAnimation()
        let canvas = try #require(saver.subviews.first as? OllinMTKView)

        #expect(canvas.ignoresInput)
        #expect(canvas.hitTest(NSPoint(x: 160, y: 100)) == nil,
                "a click on the canvas would be a click the saver ate")
        #expect(!canvas.acceptsFirstResponder, "a key press would go to the sketch instead of ending the saver")
    }

    @Test func aCanvasInAWindowStillTakesInput() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
        let device = try #require(MTLCreateSystemDefaultDevice())
        // The other side of the same switch: every ordinary host leaves it off,
        // and a sketch in a window reads the mouse as it always did.
        let canvas = makeOllinMTKView(device: device, size: CGSize(width: 64, height: 64),
                                      sketch: TestSketch())
        #expect(!canvas.ignoresInput)
        #expect(canvas.acceptsFirstResponder)
        #expect(canvas.hitTest(NSPoint(x: 32, y: 32)) != nil)
    }

    // MARK: Fitting the display

    @Test func aDeclaredCanvasKeepsItsProportionsOnTheDisplay() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
        let saver = try #require(TestSaverView(frame: NSRect(x: 0, y: 0, width: 320, height: 200),
                                               isPreview: false))
        saver.startAnimation()
        let canvas = try #require(saver.subviews.first as? OllinMTKView)
        #expect(canvas.frame == saver.bounds)
        // A display is almost never the shape of a canvas, so a sketch that
        // states its own size is fitted into the display rather than stretched
        // across it: a 64-square sketch on a 320 by 200 screen would otherwise
        // carry oval dots. The fit is the present pass a projector goes
        // through, and this is the flag that says the run goes through it.
        let runner = try #require(saver.runner)
        #expect(runner.isFitted)
    }

    @Test func aSketchThatFollowsItsViewFillsTheDisplayInstead() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
        // Nothing to fit: the canvas is already whatever it was put on, so
        // fitting it would be fitting it to itself.
        #expect(!SketchSaverView.fitsIntoTheDisplay(FillingSketch()))
        #expect(SketchSaverView.fitsIntoTheDisplay(TestSketch()))
    }

    // MARK: The framework's own files

    @Test func theFrameworkFindsItsOwnResources() throws {
        // A plug-in is loaded by somebody else's program, so the bundle written
        // beside that program is not ours. What matters is that the lookup
        // answers with a bundle carrying the shader segments, whichever of the
        // candidates it came from.
        let bundle = OllinResources.bundle
        #expect(bundle.url(forResource: "ShaderCore", withExtension: "metal") != nil,
                "the shader segments are not where the framework looks for them")
    }
}
