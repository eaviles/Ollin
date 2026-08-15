import AppKit
import Foundation
import Metal
import Testing
@testable import Ollin

/// Where a running sketch sits on the desk.
///
/// A piece that only ever fills its own window never needs this. It matters
/// when more than one window looks into one world, which is the same question a
/// wall of displays asks: every window has to describe the same desk in the same
/// numbers, or the world bends at the seams.
///
/// Two claims here cannot be read off the source. The desk is measured the way
/// the canvas is, from the top down, while the system measures it from the
/// bottom up, so a rectangle has to be turned over on the way through. And what
/// is reported is the canvas rather than the window, so a host with a title bar
/// or a sidebar says where the drawing is and not where its furniture is.
@MainActor
struct PlacementTests {

    @Test func theDeskIsMeasuredFromTheTopOfTheMainScreen() throws {
        let primary = try #require(NSScreen.screens.first)
        let tall = primary.frame.height

        // Sitting on the bottom edge of the main screen, the way the system
        // counts. Measured from the top, that is a whole screen down less its
        // own height. Without the turn it would read zero.
        let low = try #require(SketchRunner.desktopRect(CGRect(x: 0, y: 0, width: 100, height: 60)))
        #expect(low.x == 0)
        #expect(abs(low.y - (tall - 60)) < 0.001)

        // And sitting against the top edge reads zero.
        let high = try #require(SketchRunner.desktopRect(
            CGRect(x: 0, y: primary.frame.maxY - 60, width: 100, height: 60)))
        #expect(abs(high.y) < 0.001)

        // The size travels unchanged either way.
        #expect(low.width == 100 && low.height == 60)
    }

    @Test func nothingToMeasureGivesNothingBack() {
        #expect(SketchRunner.desktopRect(nil) == nil)
        #expect(SketchRunner.onScreen(CGRect(x: 0, y: 0, width: 10, height: 10), in: nil) == nil)
        // A sketch that has never been in a window (an export, a still) says so
        // rather than making a place up, which is what lets a piece fall back
        // to being its own world.
        #expect(Sketch().canvasOnScreen == nil)
        #expect(Sketch().screenFrame == nil)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aCanvasInAWindowSaysWhereItSitsAndNotWhereItsChromeIs() throws {
        let primary = try #require(NSScreen.screens.first)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let sketch = Sketch()
        let view = makeOllinMTKView(device: device, size: CGSize(width: 400, height: 300),
                                    sketch: sketch)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 300, width: 400, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = view

        let canvas = try #require(SketchRunner.onScreen(view.convert(view.bounds, to: nil),
                                                        in: view.window))
        #expect(canvas.width == 400 && canvas.height == 300)
        #expect(canvas.x == 200)
        #expect(abs(canvas.y - (primary.frame.maxY - 600)) < 0.001)

        // The window is the canvas plus its title bar, and the canvas sits
        // below that bar. Reporting the window instead would put the world half
        // an inch out at the top of every host that has one.
        let whole = try #require(SketchRunner.desktopRect(window.frame))
        #expect(whole.height > canvas.height)
        #expect(canvas.y > whole.y)
        #expect(canvas.x == whole.x)
    }
}
