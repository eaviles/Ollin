import AppKit
import Foundation
import Metal
import Testing
@testable import Ollin

/// A sketch running as the desktop wallpaper.
///
/// The claims here are the ones that would break the desktop rather than the
/// picture. The pane must sit under the desktop icons, or the piece covers the
/// files on the desk. It must take no clicks and no keys, or the desktop stops
/// being a desktop. And there must be one pane per display, each fitted the
/// way the sketch asked.
@MainActor
struct WallpaperHostTests {

    final class TestSketch: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
    }

    /// The shape the generator writes: the canvas follows whatever it is put on.
    final class FillingSketch: Sketch {
        override var windowMode: WindowMode { .resizable }
    }

    private func makePane(_ sketch: Sketch) throws -> WallpaperPane {
        try #require(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
        let screen = try #require(NSScreen.main, "no display on this machine")
        return try #require(WallpaperPane(screen: screen, sketch: sketch))
    }

    @Test func aPaneSitsUnderTheDesktopIcons() throws {
        let pane = try makePane(TestSketch())
        defer { pane.close() }
        // The two system levels: the picture the system keeps on the desktop,
        // and the icons over it. The pane belongs between them, so the files
        // on the desk stay on top of the piece.
        let desktop = Int(CGWindowLevelForKey(.desktopWindow))
        let icons = Int(CGWindowLevelForKey(.desktopIconWindow))
        #expect(pane.window.level.rawValue == desktop)
        #expect(pane.window.level.rawValue < icons,
                "a pane over the icons would bury the desktop")
    }

    @Test func aPaneStaysOutOfTheEventPath() throws {
        let pane = try makePane(TestSketch())
        defer { pane.close() }
        #expect(pane.window.ignoresMouseEvents,
                "a click on the desktop must land on the desktop")
        #expect(!pane.window.canBecomeKey,
                "wallpaper taking the keyboard would leave typing dead")
        #expect(pane.canvas.ignoresInput)
        #expect(!pane.canvas.acceptsFirstResponder)
    }

    @Test func aPaneIsOnEverySpace() throws {
        let pane = try makePane(TestSketch())
        defer { pane.close() }
        // Wallpaper does not scroll away: a swipe to another desktop keeps the
        // piece, and the window cycle never lands on it.
        #expect(pane.window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(pane.window.collectionBehavior.contains(.stationary))
        #expect(pane.window.collectionBehavior.contains(.ignoresCycle))
    }

    @Test func aDeclaredCanvasIsFittedToItsDisplay() throws {
        // A display is almost never the shape of a canvas, so a sketch that
        // states its own size is fitted at its proportions, centered on black,
        // while one that follows its view takes the whole display.
        let fitted = try makePane(TestSketch())
        defer { fitted.close() }
        #expect(fitted.runner.isFitted)

        let filling = try makePane(FillingSketch())
        defer { filling.close() }
        #expect(!filling.runner.isFitted)
    }

    @Test func theHostBuildsOnePanePerDisplay() throws {
        try #require(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
        try #require(NSScreen.main != nil, "no display on this machine")
        let host = WallpaperHost(makeSketch: { TestSketch() })
        host.openPanes()
        defer { host.closePanes() }
        #expect(host.panes.count == NSScreen.screens.count,
                "a display without a pane shows the plain desktop")
    }
}

/// A sketch running in the menu bar.
///
/// The strip lives beside the clock all day, so what matters is that it goes
/// up with its menu (the menu is the only way out), that it takes no input
/// beyond the click that opens that menu, and that it draws at a rate a
/// surface that never goes away can afford.
@MainActor
struct MenuBarHostTests {

    final class TestSketch: Sketch {
        override var canvasSize: CanvasSize { .square(64) }
    }

    final class FillingSketch: Sketch {
        override var windowMode: WindowMode { .resizable }
    }

    private func makeHost(_ makeSketch: @escaping @MainActor () -> Sketch) throws -> MenuBarHost {
        try #require(MTLCreateSystemDefaultDevice() != nil, "no Metal device on this machine")
        let host = MenuBarHost(width: 56, makeSketch: makeSketch)
        host.install()
        return host
    }

    @Test func theStripGoesUpWithACanvasAndAMenu() throws {
        let host = try makeHost { TestSketch() }
        defer { host.remove() }
        let item = try #require(host.statusItem)
        let canvas = try #require(host.canvas)
        #expect(canvas.sketch is TestSketch)
        #expect(canvas.delegate != nil, "nothing would drive the frames")
        // The menu is the only way out of a program with no window and no Dock
        // icon, so the quit row is load-bearing, not chrome.
        let menu = try #require(item.menu)
        let quit = try #require(menu.items.last)
        #expect(quit.action == #selector(NSApplication.terminate(_:)),
                "without this the piece can only be killed")
    }

    @Test func theCanvasTakesNoInput() throws {
        let host = try makeHost { TestSketch() }
        defer { host.remove() }
        let canvas = try #require(host.canvas)
        // The click has to fall through the canvas to the button under it,
        // which is what opens the menu. And the strip must never take the
        // keyboard from whatever is being typed in.
        #expect(canvas.ignoresInput)
        #expect(canvas.hitTest(NSPoint(x: 28, y: 10)) == nil)
        #expect(!canvas.acceptsFirstResponder)
    }

    @Test func aDeclaredCanvasIsFittedIntoTheStrip() throws {
        let fitted = try makeHost { TestSketch() }
        defer { fitted.remove() }
        #expect(try #require(fitted.runner).isFitted)

        let filling = try makeHost { FillingSketch() }
        defer { filling.remove() }
        #expect(!(try #require(filling.runner).isFitted))
    }

    @Test func theStripDrawsAtAWorkdayRate() throws {
        let host = try makeHost { TestSketch() }
        defer { host.remove() }
        // A strip beside the clock is worth a moving picture, not a whole
        // display's worth of frames, on a surface that is up all day.
        #expect(try #require(host.canvas).preferredFramesPerSecond == 30)
    }

    @Test func removingTheStripPutsTheCanvasAway() throws {
        let host = try makeHost { TestSketch() }
        host.remove()
        #expect(host.canvas == nil, "an abandoned canvas would go on drawing frames nobody sees")
        #expect(host.statusItem == nil)
    }
}
