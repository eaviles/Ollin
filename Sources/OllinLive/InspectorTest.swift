import AppKit
import Foundation
import Ollin
import SwiftUI

/// `swift run OllinLive --inspectortest`: two inspector controls driven by
/// posted events, and the parameters they moved read back. The parameters
/// list is hosted in a window built in this process; the number row's field
/// is clicked, given a value by key events, and confirmed with Return, and
/// the toggle is clicked, every event posted to the application's own queue,
/// which is where a real click lands after the window server, so the check
/// runs on a locked screen. Then each handle reads the new value, the sketch
/// reads it too, and `onChange` fired for both. The slider itself is drawn by
/// SwiftUI with no view of its own to aim at, so its drag is a desk check.
@MainActor
enum InspectorTest {
    final class Subject: Sketch {
        @Param(0 ... 200) var radius = 50.0
        @Param var visible = true
    }

    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let sketch = Subject()
        let handles = sketch.parameters()
        check(handles.count == 2, "the subject declares two parameters, found \(handles.count)")
        nonisolated(unsafe) var changes: [(String, ParamStored)] = []
        let list = ParametersListView(parameters: handles, sketchName: "InspectorTest",
                                      onChange: { changes.append(($0, $1)) })
        let hosting = NSHostingView(rootView: list.frame(width: 320))
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 360),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        app.finishLaunching()
        app.activate()
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        pump(app, for: 0.6)

        // The toggle first, a pure click: one click flips it.
        guard let toggle = view(named: "PlatformSwitch", under: hosting) else {
            fail("no switch among the inspector's views: \(classes(under: hosting))")
        }
        let box = screenFrame(of: toggle)
        let wasVisible = sketch.visible
        click(app, window, at: NSPoint(x: box.midX, y: box.midY))
        pump(app, for: 0.5)
        check(sketch.visible != wasVisible, "the click did not flip the toggle (window key: \(window.isKeyWindow))")
        guard case .boolean(let flipped) = handles[1].param.stored else {
            fail("the toggle's parameter reads \(handles[1].param.stored)")
        }
        check(flipped == sketch.visible, "the handle and the sketch disagree: \(flipped) vs \(sketch.visible)")
        check(changes.contains { $0.0 == "visible" }, "onChange never fired for visible")

        // The number row's field: click it, replace its text, confirm.
        guard let field = view(named: "AppKitTextField", under: hosting) else {
            fail("no text field among the inspector's views: \(classes(under: hosting))")
        }
        let fieldFrame = screenFrame(of: field)
        check(fieldFrame.width > 10 && fieldFrame.height > 5, "the field's frame reads \(fieldFrame)")
        click(app, window, at: NSPoint(x: fieldFrame.midX, y: fieldFrame.midY))
        pump(app, for: 0.3)
        // A window behind the lock screen is never the key window, and only a
        // key window's click gives a field the keyboard, so the field is
        // handed it here; the keys themselves still arrive as events.
        if !(window.firstResponder is NSTextView) { window.makeFirstResponder(field) }
        pump(app, for: 0.1)
        key(app, window, "a", code: 0, flags: .command)      // select whatever is there
        for (character, code) in [("1", 18), ("2", 19), ("0", 29)] { key(app, window, character, code: UInt16(code)) }
        key(app, window, "\r", code: 36)
        pump(app, for: 0.5)
        guard case .number(let typed) = handles[0].param.stored else {
            fail("the number parameter reads \(handles[0].param.stored)")
        }
        check(typed == 120, "typing 120 into the field left radius at \(typed); first responder "
              + "\(String(describing: window.firstResponder.map { type(of: $0) })), key window \(window.isKeyWindow)")
        check(sketch.radius == 120, "the sketch reads what the inspector set: \(sketch.radius)")
        check(changes.contains { $0.0 == "radius" }, "onChange never fired for radius")

        print("inspectortest: ok (the field took radius to 120, a click flipped visible to \(flipped))")
        exit(0)
    }

    // MARK: Events

    private static func click(_ app: NSApplication, _ window: NSWindow, at point: NSPoint) {
        post(app, window, .leftMouseDown, at: point)
        post(app, window, .leftMouseUp, at: point)
        pump(app, for: 0.2)
    }

    private static func post(_ app: NSApplication, _ window: NSWindow, _ type: NSEvent.EventType,
                             at screenPoint: NSPoint) {
        let local = window.convertPoint(fromScreen: screenPoint)
        guard let event = NSEvent.mouseEvent(with: type, location: local, modifierFlags: [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil,
                                             eventNumber: 1, clickCount: 1, pressure: 1) else {
            fail("could not make a \(type) event")
        }
        app.postEvent(event, atStart: false)
    }

    private static func key(_ app: NSApplication, _ window: NSWindow, _ characters: String,
                            code: UInt16, flags: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: code) else {
                fail("could not make a key event for \(characters)")
            }
            // Key events go to the window itself: the application routes them
            // to its key window, and a window with no screen to be key on has
            // none, while the window routes them to its first responder.
            window.sendEvent(event)
        }
        pump(app, for: 0.05)
    }

    /// Run the application's own event loop for a while, dispatching what
    /// was posted and letting SwiftUI lay out and settle.
    private static func pump(_ app: NSApplication, for seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let event = app.nextEvent(matching: .any, until: Date().addingTimeInterval(0.02),
                                         inMode: .default, dequeue: true) {
                app.sendEvent(event)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    // MARK: Views

    /// The first view under `root` whose class name contains `name`.
    private static func view(named name: String, under root: NSView) -> NSView? {
        var pending: [NSView] = [root]
        while let next = pending.popLast() {
            if String(describing: type(of: next)).contains(name) { return next }
            pending.append(contentsOf: next.subviews.reversed())
        }
        return nil
    }

    /// The class of every view under `root`, for a failure's sentence.
    private static func classes(under root: NSView) -> [String] {
        var pending: [NSView] = [root]
        var seen: [String] = []
        while let next = pending.popLast() {
            seen.append(String(describing: type(of: next)))
            pending.append(contentsOf: next.subviews.reversed())
        }
        return seen
    }

    private static func screenFrame(of view: NSView) -> NSRect {
        guard let window = view.window else { fail("the view has no window") }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    // MARK: Reporting

    private static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition { fail(message()) }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("inspectortest: \(message)\n".utf8))
        exit(1)
    }
}
