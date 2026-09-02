import AppKit
@testable import Ollin
import Testing

/// The detached inspector and its seed box, in the order a standalone run
/// opens them: the panel first, the first frame's seed a moment later, and the
/// window becoming key on the first click into it.
///
/// A desk session found the box open empty, take the keyboard on that first
/// click, and keep it until another field was clicked. The window is real
/// here (an ordered-front panel), because every one of those is the window
/// system's doing rather than the view's.
@Suite
@MainActor
struct InspectorPanelFocusTests {

    /// Every text field under `view`, in tree order: the seed box is the first.
    private func textFields(under view: NSView) -> [NSTextField] {
        var found: [NSTextField] = []
        if let field = view as? NSTextField { found.append(field) }
        for child in view.subviews { found += textFields(under: child) }
        return found
    }

    /// Let the window system and SwiftUI settle.
    private func settle(_ seconds: Double = 0.25) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    @Test func theSeedBoxFillsAndNobodyHoldsTheKeyboard() throws {
        let stats = FrameStats()
        let sketch = Sketch()
        let controller = StatsPanelController()
        controller.sync(visible: true, sketch: sketch, stats: stats)
        settle()
        defer { controller.close() }

        let panel = try #require(controller.window)
        let content = try #require(panel.contentView)
        let seedBox = try #require(textFields(under: content).first)
        #expect(seedBox.stringValue.isEmpty, "no frame has drawn, so there is no seed to show yet")

        // The first frame reports its seed after the panel is already up.
        stats.update(fps: 60, frameTimeMS: 1, frameCount: 6, time: 0.1,
                     vertexCount: 0, sdfCount: 0, pointCount: 0, particleCount: 0,
                     canvasWidth: 1080, canvasHeight: 1080, variation: 4242,
                     profile: FrameProfile())
        settle()
        #expect(seedBox.stringValue == "4242",
                "the seed box should show the seed that arrived, not \"\(seedBox.stringValue)\"")

        // The first click into the panel makes it key. Nothing in it should be
        // handed the keyboard by that alone.
        panel.makeKey()
        settle()
        #expect(!(panel.firstResponder is NSTextView),
                "becoming key handed the keyboard to a text field")
        #expect(seedBox.stringValue == "4242")
    }
}
